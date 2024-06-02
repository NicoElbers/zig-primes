const std = @import("std");
const fmt = std.fmt;

const eql = std.mem.eql;
const Allocator = std.mem.Allocator;
const parseInt = fmt.parseInt;

const Config = @import("config.zig").Config;

const gens = @import("candidate_gen.zig");
const checks = @import("checker.zig");
const workers = @import("worker.zig");

const runner = @import("runner.zig");

pub const std_options = .{
    .log_level = std.log.Level.info,
};

pub const AllCheckers = struct {
    simple: checks.Checker = checks.SimpleChecker.checker(),
    smart: checks.Checker = checks.SmartChecker.checker(),
    branchless: checks.Checker = checks.BranchlessChecker.checker(),
};

pub const AllGenerators = struct {
    simple: gens.Generator = gens.SimpleGen.generator(),
    smart: gens.Generator = gens.SmartGen.generator(),
};

pub const AllWorkers = struct {
    simple: workers.SimpleWorker,
    concurrent: workers.ConcurrentWorker,
};

pub fn main() !void {
    // const alloc = std.heap.page_allocator;

    // const checker = checks.BranchlessChecker.checker();
    // const gen = gens.SmartGen.generator();
    // var worker_instance = workers.ConcurrentWorker.init(gen, checker, 1);
    // const worker = worker_instance.worker();

    // const list = try worker.work(&alloc, 10_000);
    // list.deinit();

    var arena_alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_alloc.deinit();

    const alloc = arena_alloc.allocator();
    const config = Config.init(alloc) catch |err| {
        const CfgErr = Config.ConfigError;
        switch (err) {
            CfgErr.InvalidValue => {
                std.log.err("Invalid option", .{});
                std.process.exit(1);
            },
            CfgErr.OptionWithoutValue => {
                std.log.err("Didn't find a follow up value", .{});
                std.process.exit(1);
            },
            inline else => {
                std.log.err("Unknown error", .{});
                std.process.exit(1);
            },
        }
    };

    std.log.info(
        \\
        \\Input:
        \\  target  : {d}
        \\  warmup  : {d}
        \\  runs    : {d}
        \\  time    : {d}
        \\  threads : {d}
    , .{
        config.target,
        config.warmup,
        config.runs,
        config.time_ns,
        config.concurrency,
    });

    try runAll(config, alloc);
}

fn runAll(config: Config, alloc: Allocator) !void {
    const checker_info = @typeInfo(AllCheckers);
    const gen_info = @typeInfo(AllGenerators);
    const worker_info = @typeInfo(AllWorkers);

    inline for (worker_info.Struct.fields) |worker_field| {
        inline for (checker_info.Struct.fields) |checker_field| {
            inline for (gen_info.Struct.fields) |gen_field| {
                const gen: *const gens.Generator =
                    @ptrCast(@alignCast(gen_field.default_value.?));
                const check: *const checks.Checker =
                    @ptrCast(@alignCast(checker_field.default_value.?));

                const worker_type = worker_field.type;

                var worker_instance = worker_type.init(gen.*, check.*, 16);
                const worker = worker_instance.worker();

                var arena = std.heap.ArenaAllocator.init(alloc);
                defer arena.deinit();

                const config_alloc = arena.allocator();

                std.log.debug(
                    "Starting warmup for {s} worker with {s} checker and {s} generator",
                    .{ worker_field.name, checker_field.name, gen_field.name },
                );

                _ = try runner.runMany(
                    worker,
                    &config_alloc,
                    config.target,
                    config.warmup,
                );

                _ = arena.reset(.retain_capacity);

                std.log.info(
                    "Starting timed run for {s} worker with {s} checker and {s} generator",
                    .{ worker_field.name, checker_field.name, gen_field.name },
                );

                const runs = try runner.runFor(
                    worker,
                    &config_alloc,
                    config.target,
                    config.time_ns,
                );

                if (runs == 0) {
                    std.log.warn("Completed 0 runs in alloted time", .{});
                } else {
                    std.log.info(
                        "Ran {} times, average runtime {}ms",
                        .{ runs, config.time_ns / (runs * std.time.ns_per_ms) },
                    );
                }
            }
        }
    }
}

test "Run all" {
    const config = Config{
        .runs = 5,
        .warmup = 5,
        .target = 10_000,
        .concurrency = 8,
        .time_ns = 100_000_000,
    };

    try runAll(config, std.testing.allocator);
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
