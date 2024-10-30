pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    std.debug.print("features: {s}\n", .{@import("builtin").cpu.model.name});

    const alloc = gpa.allocator();

    const limit = 10_000_000;
    const timeout_ns = std.time.ns_per_s * 5;

    try runAll(alloc, limit, timeout_ns);
}

fn runAll(alloc: Allocator, comptime limit: u32, timeout_ns: u64) !void {
    inline for (CheckerGenerators) |checker_s| {
        const checker_gen = checker_s.init();

        inline for (Checkers) |checker_fn| {
            const Checker = checker_fn(@TypeOf(checker_gen));
            const checker = Checker.init(checker_gen);

            inline for (Generators) |gen_fn| {
                const Generator = gen_fn(@TypeOf(checker));
                const generator = Generator.init(checker);

                inline for (Workers) |worker_fn| {
                    const Worker = worker_fn(@TypeOf(generator));
                    var worker = Worker.init(generator);

                    const res = try run(&worker, alloc, limit, timeout_ns);

                    std.debug.print("{s}:\n\t{any:.2}\n", .{ @typeName(Worker), res });
                }
            }
        }
    }
}

const Result = struct {
    runs: u32,
    avg_time: u64,
    total_time: u64,

    pub fn format(value: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;

        const avg_ms: f128 = @as(f128, @floatFromInt(value.avg_time)) / @as(f128, @floatFromInt(std.time.ns_per_ms));
        const total_ms: f128 = @as(f128, @floatFromInt(value.total_time)) / @as(f128, @floatFromInt(std.time.ns_per_ms));

        try writer.writeAll("{ avg_time: ");
        try std.fmt.formatType(avg_ms, "d", options, writer, 5);
        try writer.writeAll(" ms, total_time: ");
        try std.fmt.formatType(total_ms, "d", options, writer, 5);
        try writer.writeAll(" ms }");
    }
};

fn run(worker_impl: anytype, alloc: Allocator, comptime limit: u32, timeout_ns: u64) !Result {
    comptime assert(std.meta.hasFn(@TypeOf(worker_impl.*), "work"));

    var runs: u32 = 0;

    const len = blk: {
        const test_arr = try worker_impl.work(alloc, limit);
        defer test_arr.deinit();
        break :blk test_arr.items.len;
    };

    std.debug.print("Len: {d}\n", .{len});

    var timer = try std.time.Timer.start();
    while (timer.read() < timeout_ns) : (runs += 1) {
        const arr = try worker_impl.work(alloc, limit);
        assert(arr.items.len == len);
        arr.deinit();
    }

    const final_time = timer.read();
    const avg_time = @divTrunc(final_time, runs);

    return .{
        .runs = runs,
        .avg_time = avg_time,
        .total_time = final_time,
    };
}

const std = @import("std");
const checkers = @import("checkers.zig");
const generators = @import("generators.zig");
const workers = @import("workers.zig");

const Checkers = checkers.Checkers;
const Generators = generators.Generators;
const CheckerGenerators = generators.CheckerGenerators;
const Workers = workers.Workers;

const Allocator = std.mem.Allocator;

const assert = std.debug.assert;

test "all" {
    const primes_under_100 = [_]u32{ 2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89, 97 };
    const limit = 100;

    const alloc = std.testing.allocator;

    inline for (CheckerGenerators) |checker_s| {
        const checker_gen = checker_s.init();
        inline for (Checkers) |checker_fn| {
            const Checker = checker_fn(@TypeOf(checker_gen));
            const checker = Checker.init(checker_gen);

            inline for (Generators) |gen_fn| {
                const Generator = gen_fn(@TypeOf(checker));
                const generator = Generator.init(checker);

                inline for (Workers) |worker_fn| {
                    const Worker = worker_fn(@TypeOf(generator));
                    var worker = Worker.init(generator);

                    const array_list = try worker.work(alloc, limit);
                    defer array_list.deinit();

                    std.debug.print("Testing: {s}\n", .{@typeName(Worker)});
                    std.testing.expectEqualSlices(u32, &primes_under_100, array_list.items) catch {};
                }
            }
        }
    }
}
