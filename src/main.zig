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
    .logFn = localLog,
};

fn localLog(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    switch (scope) {
        // .worker => return,
        else => {},
    }

    std.log.defaultLog(
        level,
        scope,
        format,
        args,
    );
}

pub const AllCheckers = struct {
    // simple: checks.Checker = checks.SimpleChecker.checker(),
    // smart: checks.Checker = checks.SmartChecker.checker(),
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
    const scope = std.log.scoped(.main);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const alloc = arena.allocator();
    // const alloc = std.heap.page_allocator;

    const config = Config.init(alloc) catch |err| {
        const CfgErr = Config.ConfigError;
        switch (err) {
            CfgErr.InvalidValue => {
                scope.err("Invalid option", .{});
                std.process.exit(1);
            },
            CfgErr.OptionWithoutValue => {
                scope.err("Didn't find a follow up value", .{});
                std.process.exit(1);
            },
            inline else => {
                scope.err("Unknown error", .{});
                std.process.exit(1);
            },
        }
    };

    scope.info(
        \\
        \\Input:
        \\  target  : {d}
        \\  warmup  : {d}
        \\  time    : {d}
        \\  threads : {d}
    , .{
        config.target,
        config.warmup,
        config.time_ns,
        config.concurrency,
    });

    try runAll(config, alloc);
}

fn runAll(config: Config, alloc: Allocator) !void {
    const scope = std.log.scoped(.main);

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

                scope.debug(
                    "Starting warmup for {s} worker with {s} checker and {s} generator",
                    .{ worker_field.name, checker_field.name, gen_field.name },
                );

                var arena = std.heap.ArenaAllocator.init(alloc);

                _ = try runner.runMany(
                    worker,
                    &arena,
                    config.target,
                    config.warmup,
                );

                _ = arena.reset(.retain_capacity);

                scope.info(
                    "Starting timed run for {s} worker with {s} checker and {s} generator",
                    .{ worker_field.name, checker_field.name, gen_field.name },
                );

                const runs = try runner.runFor(
                    worker,
                    &arena,
                    config.target,
                    config.time_ns,
                );

                if (runs == 0) {
                    scope.warn("Completed 0 runs in alloted time\n", .{});
                } else {
                    scope.info(
                        "\tRan {} times, average runtime {}ms\n",
                        .{ runs, config.time_ns / (runs * std.time.ns_per_ms) },
                    );
                }
            }
        }
    }
}

test runAll {
    const config = Config{
        .warmup = 0,
        .target = 1_000,
        .time_ns = 10_000_000,
        .concurrency = 16,
    };

    const alloc = std.testing.allocator;

    try runAll(config, alloc);
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
