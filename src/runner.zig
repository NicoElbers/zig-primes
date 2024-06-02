const std = @import("std");

const workers = @import("worker.zig");

const Worker = workers.Worker;
const Allocator = std.mem.Allocator;

pub fn runOnce(worker: Worker, alloc: *const Allocator, target: usize) !u64 {
    std.log.debug("Starting a run", .{});
    var timer = try std.time.Timer.start();

    const primes = try worker.work(alloc, target);
    defer primes.deinit();

    const time = timer.read();

    std.log.debug(
        "Found {} primes under {} : took {}ms",
        .{ primes.items.len, target, time / std.time.ns_per_ms },
    );

    return time;
}

test "Test leak once" {
    const checkers = @import("checker.zig");
    const gens = @import("candidate_gen.zig");

    const checker = checkers.BranchlessChecker.checker();
    const gen = gens.SmartGen.generator();
    var worker_instance = workers.ConcurrentWorker.init(
        gen,
        checker,
        16,
    );
    const worker = worker_instance.worker();

    _ = try runOnce(
        worker,
        &std.testing.allocator,
        1_000_000,
    );
}

pub fn runMany(worker: Worker, alloc: *const Allocator, target: usize, runs: usize) !u64 {
    if (runs == 0) {
        return 0;
    }

    var total_time: u64 = 0;
    for (0..runs) |i| {
        total_time += try runOnce(worker, alloc, target);
        std.log.debug(
            "Completed run {} : total time {}",
            .{ i, total_time / std.time.ns_per_ms },
        );
    }
    return total_time / (runs * std.time.ns_per_ms);
}

test "runMany all configurations" {
    const checks = @import("checker.zig");
    const gens = @import("candidate_gen.zig");

    const AllCheckers = struct {
        simple: checks.Checker = checks.SimpleChecker.checker(),
        smart: checks.Checker = checks.SmartChecker.checker(),
        branchless: checks.Checker = checks.BranchlessChecker.checker(),
    };
    const checker_info = @typeInfo(AllCheckers);

    const AllGenerators = struct {
        simple: gens.Generator = gens.SimpleGen.generator(),
        smart: gens.Generator = gens.SmartGen.generator(),
    };
    const gen_info = @typeInfo(AllGenerators);

    const AllWorkers = struct {
        simple: workers.SimpleWorker,
        parallel: workers.ConcurrentWorker,
    };
    const worker_info = @typeInfo(AllWorkers);

    inline for (gen_info.Struct.fields) |gen_field| {
        inline for (checker_info.Struct.fields) |checker_field| {
            inline for (worker_info.Struct.fields) |worker_field| {
                const gen: *const gens.Generator =
                    @ptrCast(@alignCast(gen_field.default_value.?));
                const check: *const checks.Checker =
                    @ptrCast(@alignCast(checker_field.default_value.?));

                const worker_type = worker_field.type;

                var worker_instance = worker_type.init(gen.*, check.*, 16);
                const worker = worker_instance.worker();

                _ = try runMany(
                    worker,
                    &std.testing.allocator,
                    10_000,
                    5,
                );
            }
        }
    }
}

pub fn runFor(worker: Worker, alloc: *const Allocator, target: usize, duration_ns: u64) !u64 {
    var completion_counter: u64 = 0;

    var timer = try std.time.Timer.start();
    while (timer.read() < duration_ns) : (completion_counter += 1) {
        _ = try runOnce(worker, alloc, target);
    }

    return completion_counter -| 1;
}

test "runFor all configurations" {
    const checks = @import("checker.zig");
    const gens = @import("candidate_gen.zig");

    const AllCheckers = struct {
        simple: checks.Checker = checks.SimpleChecker.checker(),
        smart: checks.Checker = checks.SmartChecker.checker(),
        branchless: checks.Checker = checks.BranchlessChecker.checker(),
    };
    const checker_info = @typeInfo(AllCheckers);

    const AllGenerators = struct {
        simple: gens.Generator = gens.SimpleGen.generator(),
        smart: gens.Generator = gens.SmartGen.generator(),
    };
    const gen_info = @typeInfo(AllGenerators);

    const AllWorkers = struct {
        simple: workers.SimpleWorker,
        parallel: workers.ConcurrentWorker,
    };
    const worker_info = @typeInfo(AllWorkers);

    inline for (gen_info.Struct.fields) |gen_field| {
        inline for (checker_info.Struct.fields) |checker_field| {
            inline for (worker_info.Struct.fields) |worker_field| {
                const gen: *const gens.Generator =
                    @ptrCast(@alignCast(gen_field.default_value.?));
                const check: *const checks.Checker =
                    @ptrCast(@alignCast(checker_field.default_value.?));

                const worker_type = worker_field.type;

                var worker_instance = worker_type.init(gen.*, check.*, 16);
                const worker = worker_instance.worker();

                _ = try runFor(
                    worker,
                    &std.testing.allocator,
                    1_000,
                    1_000_000,
                );
            }
        }
    }
}
