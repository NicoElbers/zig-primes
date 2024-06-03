const std = @import("std");

const workers = @import("worker.zig");

const Worker = workers.Worker;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

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

test runOnce {
    const checkers = @import("checker.zig");
    const gens = @import("candidate_gen.zig");

    const checker = checkers.BranchlessChecker.checker();
    const gen = gens.SmartGen.generator();
    var worker_instance = workers.SimpleWorker.init(
        gen,
        checker,
        1,
    );
    const worker = worker_instance.worker();

    _ = try runOnce(
        worker,
        &std.testing.allocator,
        10_000,
    );
}

pub fn runMany(worker: Worker, arena: *ArenaAllocator, target: usize, runs: usize) !u64 {
    if (runs == 0) {
        return 0;
    }

    const alloc = arena.allocator();

    var total_time: u64 = 0;
    for (0..runs) |i| {
        total_time += try runOnce(worker, &alloc, target);
        std.log.debug(
            "Completed run {} : total time {}",
            .{ i, total_time / std.time.ns_per_ms },
        );
    }
    return total_time / (runs * std.time.ns_per_ms);
}

test runMany {
    const checkers = @import("checker.zig");
    const gens = @import("candidate_gen.zig");

    const checker = checkers.BranchlessChecker.checker();
    const gen = gens.SmartGen.generator();
    var worker_instance = workers.SimpleWorker.init(
        gen,
        checker,
        1,
    );
    const worker = worker_instance.worker();

    _ = try runMany(
        worker,
        &std.testing.allocator,
        10_000,
        5,
    );
}

pub fn runFor(worker: Worker, arena: *ArenaAllocator, target: usize, duration_ns: u64) !u64 {
    var completion_counter: u64 = 0;

    const alloc = arena.allocator();

    var timer = try std.time.Timer.start();
    while (timer.read() < duration_ns) : (completion_counter += 1) {
        _ = try runOnce(worker, &alloc, target);
        _ = arena.reset(.retain_capacity);
    }

    return completion_counter -| 1;
}

test runFor {
    const checkers = @import("checker.zig");
    const gens = @import("candidate_gen.zig");

    const alloc = std.testing.allocator;

    const checker = checkers.BranchlessChecker.checker();
    const gen = gens.SmartGen.generator();
    var worker_instance = workers.ConcurrentWorker.init(
        gen,
        checker,
        16,
    );
    const worker = worker_instance.worker();

    for (0..1000) |_| {
        _ = try runFor(
            worker,
            &alloc,
            1_000_000,
            1,
        );
    }
}
