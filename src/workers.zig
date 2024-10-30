pub const Workers = .{ SimpleWorker, PreAllocWorker };

pub fn SimpleWorker(comptime Gen: type) type {
    return struct {
        gen: Gen,

        pub fn init(gen: Gen) @This() {
            return .{
                .gen = gen,
            };
        }

        pub fn work(self: *@This(), alloc: Allocator, limit: u32) !ArrayList(u32) {
            self.gen.reset();
            var array_list: ArrayList(u32) = .init(alloc);

            while (self.gen.next(limit)) |prime|
                try array_list.append(prime);

            return array_list;
        }
    };
}

pub fn PreAllocWorker(comptime Gen: type) type {
    return struct {
        gen: Gen,

        pub fn init(gen: Gen) @This() {
            return .{
                .gen = gen,
            };
        }

        pub fn work(self: *@This(), alloc: Allocator, comptime limit: u32) !ArrayList(u32) {
            self.gen.reset();
            const upper_limit_primes = @max(10, limit / 3 * 2);

            var array_list: ArrayList(u32) = try .initCapacity(alloc, upper_limit_primes);

            while (self.gen.next(limit)) |prime|
                array_list.appendAssumeCapacity(prime);

            return array_list;
        }
    };
}

pub fn MultiWorker(comptime Gen: type) type {
    return struct {
        gen: Gen,

        pub fn init(gen: Gen) @This() {
            return .{
                .gen = gen,
            };
        }

        pub fn work(self: *@This(), alloc: Allocator, limit: u64) !ArrayList(u64) {
            _ = limit;
            self.gen.reset();
            var tsa = std.heap.ThreadSafeAllocator{ .child_allocator = alloc };
            const tsalloc = tsa.allocator();

            .Thread.spawn(.{ .allocator = tsalloc }, undefined, .{undefined});
            @compileError("TODO");
        }

        fn threadFunction() !void {}
    };
}

const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
