const std = @import("std");
const Allocator = std.mem.Allocator;

const generators = @import("candidate_gen.zig");
const checkers = @import("checker.zig");

const Generator = generators.Generator;
const Check = checkers.Checker;

pub const Worker = struct {
    const SelfPtr = *anyopaque;

    ptr: SelfPtr,
    workFn: *const fn (ptr: SelfPtr, alloc: *const Allocator, target: usize) anyerror!std.ArrayList(usize),

    fn init(ptr: anytype) Worker {
        const T = @TypeOf(ptr);
        const ptr_info = @typeInfo(T);

        if (ptr_info != .Pointer) @compileError("Pointer must be of type pointer");
        if (ptr_info.Pointer.size != .One)
            @compileError("Pointer must be a single item pointer");

        const child = ptr_info.Pointer.child;

        const wrapper = struct {
            pub fn inner(pointer: SelfPtr, alloc: *const Allocator, target: usize) anyerror!std.ArrayList(usize) {
                const self: T = @ptrCast(@alignCast(pointer));
                return @call(std.builtin.CallModifier.always_inline, child.work, .{ self, alloc, target });
            }
        };

        return Worker{
            .ptr = ptr,
            .workFn = wrapper.inner,
        };
    }

    pub fn work(
        self: Worker,
        alloc: *const Allocator,
        target: usize,
    ) !std.ArrayList(usize) {
        return self.workFn(self.ptr, alloc, target);
    }
};

pub const SimpleWorker = struct {
    const Self = @This();

    gen: Generator,
    checker: Check,

    pub fn worker(self: *SimpleWorker) Worker {
        return Worker.init(self);
    }

    pub fn init(
        gen: Generator,
        checker: Check,
        threads: usize,
    ) Self {
        _ = threads;

        return Self{
            .gen = gen,
            .checker = checker,
        };
    }

    pub fn work(
        self: *const Self,
        alloc: *const Allocator,
        target: usize,
    ) !std.ArrayList(usize) {
        const candidates = try self.gen.gen(alloc, target);
        defer candidates.deinit();

        var primes = std.ArrayList(usize).init(alloc.*);

        for (candidates.items) |item| {
            if (self.checker.check(item)) {
                try primes.append(item);
            }
        }
        return primes;
    }
};

pub const ConcurrentWorker = struct {
    const Self = @This();

    gen: Generator,
    checker: Check,
    thread_num: usize,

    pub fn worker(self: *ConcurrentWorker) Worker {
        return Worker.init(self);
    }

    pub fn init(
        gen: Generator,
        checker: Check,
        threads: usize,
    ) Self {
        if (threads == 0) {
            @panic("Threads cannot be 0");
        }

        return Self{
            .gen = gen,
            .checker = checker,
            .thread_num = threads,
        };
    }

    pub fn work(
        self: *const Self,
        base_alloc: *const Allocator,
        target: usize,
    ) !std.ArrayList(usize) {
        // Wrap allocator
        var thread_safe_alloc: std.heap.ThreadSafeAllocator = std.heap.ThreadSafeAllocator{
            .child_allocator = base_alloc.*,
        };
        const alloc = thread_safe_alloc.allocator();

        // Create candidates
        const candidates = try self.gen.gen(&alloc, target);
        defer candidates.deinit();
        std.log.debug("Created candidates: size {}", .{candidates.items.len});

        // Thread return values
        var return_lists: std.ArrayList(?std.ArrayList(usize)) =
            try std.ArrayList(?std.ArrayList(usize)).initCapacity(alloc, self.thread_num);
        defer {
            for (return_lists.items) |nullable_list| {
                if (nullable_list) |list| {
                    list.deinit();
                }
            }
            return_lists.deinit();
        }

        return_lists.expandToCapacity();

        // Calculate slice lengths
        const thread_slice_len: usize = @divTrunc(candidates.items.len, self.thread_num);
        std.log.debug("Slice len: {}", .{thread_slice_len});

        // Populate threads
        var handles: std.ArrayList(std.Thread) = try std.ArrayList(std.Thread).initCapacity(alloc, self.thread_num);
        defer handles.deinit();

        // Spawn threads
        var slice_idx: usize = 0;
        for (0..self.thread_num - 1) |i| {
            // We already initialized to capacity so the pointer will not be invalid
            const ptr: *?std.ArrayList(usize) = &return_lists.items[i];

            const handle = try std.Thread.spawn(.{}, threadFunction, .{
                self,
                ptr,
                &thread_safe_alloc,
                candidates.items[slice_idx .. slice_idx + thread_slice_len],
            });

            slice_idx += thread_slice_len;

            try handles.append(handle);
        }

        // Final thread takes up all the remaining numbers
        {
            const ptr: *?std.ArrayList(usize) = &return_lists.items[self.thread_num - 1];
            const handle = try std.Thread.spawn(.{}, threadFunction, .{
                self,
                ptr,
                &thread_safe_alloc,
                candidates.items[slice_idx..],
            });

            try handles.append(handle);
        }

        // Output array
        var primes: std.ArrayList(usize) = std.ArrayList(usize).init(alloc);
        errdefer primes.deinit();

        for (handles.items, 0..) |handle, i| {
            errdefer std.log.err("Something broke while joining threads", .{});

            // Make sure the thread is done
            handle.join();

            // The thread either put it's ArrayList in the buffer or put null there
            const list: std.ArrayList(usize) = return_lists.items[i] orelse return error.ThreadFailure;
            defer list.deinit();

            // Append to the output, this for some arcane reason fails
            try primes.appendSlice(list.items);
        }
        std.log.debug("Joined all thread", .{});

        return primes;
    }

    fn threadFunction(
        self: *const ConcurrentWorker,
        ptr: *?std.ArrayList(usize),
        alloc_instance: *std.heap.ThreadSafeAllocator,
        slice: []const usize,
    ) !void {
        errdefer std.log.debug("Thread failed", .{});

        // if something goes wrong, make sure we give null
        errdefer ptr.* = null;

        const alloc: std.mem.Allocator = alloc_instance.allocator();

        // Create the output array
        var primes: std.ArrayList(usize) = std.ArrayList(usize).init(alloc);
        errdefer primes.deinit();

        // Do the calculations
        for (slice) |candidate| {
            if (self.checker.check(candidate)) {
                try primes.append(candidate);
            }
        }

        // put the output array in the output pointer
        ptr.* = primes;
    }
};

test ConcurrentWorker {
    const checker = checkers.BranchlessChecker.checker();
    const gen = generators.SmartGen.generator();
    var worker_instance = ConcurrentWorker.init(gen, checker, 1);
    const worker = worker_instance.worker();

    const list = try worker.work(&std.testing.allocator, 10_000);
    list.deinit();
}
