const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ThreadSafeAllocator = std.heap.ThreadSafeAllocator;

const generators = @import("candidate_gen.zig");
const checkers = @import("checker.zig");

const Generator = generators.Generator;
const Check = checkers.Checker;

pub const Worker = struct {
    const SelfPtr = *anyopaque;

    ptr: SelfPtr,
    workFn: *const fn (ptr: SelfPtr, alloc: *const Allocator, target: usize) anyerror!ArrayList(usize),

    fn init(ptr: anytype) Worker {
        const T = @TypeOf(ptr);
        const ptr_info = @typeInfo(T);

        if (ptr_info != .Pointer) @compileError("Pointer must be of type pointer");
        if (ptr_info.Pointer.size != .One)
            @compileError("Pointer must be a single item pointer");

        const child = ptr_info.Pointer.child;

        const wrapper = struct {
            pub fn inner(pointer: SelfPtr, alloc: *const Allocator, target: usize) anyerror!ArrayList(usize) {
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
    ) !ArrayList(usize) {
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
    ) !ArrayList(usize) {
        const candidates = try self.gen.gen(alloc, target);
        defer candidates.deinit();

        var primes = try ArrayList(usize).initCapacity(alloc.*, @max(10, target * (2 / 3)));
        for (candidates.items) |item| {
            if (self.checker.check(item)) {
                try primes.append(item);
            }
        }

        return primes;
    }
};

test SimpleWorker {
    const alloc = std.testing.allocator;

    const checker = checkers.BranchlessChecker.checker();
    const gen = generators.SmartGen.generator();
    var worker_instance = SimpleWorker.init(gen, checker, 1);
    const worker = worker_instance.worker();

    const list = try worker.work(&alloc, 100);
    defer list.deinit();
}

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
        alloc: *const Allocator,
        target: usize,
    ) !ArrayList(usize) {
        const scope = std.log.scoped(.worker);

        // Create candidates
        const candidates = try self.gen.gen(alloc, target);
        defer candidates.deinit();
        scope.debug("Created candidates: size {}", .{candidates.items.len});

        // Initialize thread return lists
        var return_lists: ArrayList(ArrayList(usize)) =
            try ArrayList(ArrayList(usize)).initCapacity(alloc.*, self.thread_num);
        defer {
            for (return_lists.items) |list| {
                list.deinit();
            }
            return_lists.deinit();
        }

        // Wrap allocator for use in threads
        var ts_alloc = ThreadSafeAllocator{
            .child_allocator = alloc.*,
        };

        for (0..return_lists.capacity) |_| {
            const list = ArrayList(usize).init(ts_alloc.allocator());
            try return_lists.append(list);
        }

        // Create error boolean
        var has_errored = false;

        // Calculate slice lengths
        const thread_slice_len: usize = @divTrunc(candidates.items.len, self.thread_num);
        scope.debug("Slice len: {}", .{thread_slice_len});

        // Populate threads
        var handles: ArrayList(std.Thread) = try ArrayList(std.Thread).initCapacity(alloc.*, self.thread_num);
        defer handles.deinit();

        // Spawn threads
        var slice_idx: usize = 0;
        for (0..self.thread_num - 1) |i| {
            // We already initialized to capacity so the pointer will not be invalid
            const ptr: *ArrayList(usize) = &return_lists.items[i];

            const handle = try std.Thread.spawn(.{}, threadFunction, .{
                self,
                ptr,
                &has_errored,
                candidates.items[slice_idx .. slice_idx + thread_slice_len],
            });

            slice_idx += thread_slice_len;

            try handles.append(handle);
        }

        // Final thread takes up all the remaining numbers
        {
            const ptr: *ArrayList(usize) = &return_lists.items[self.thread_num - 1];
            const handle = try std.Thread.spawn(.{}, threadFunction, .{
                self,
                ptr,
                &has_errored,
                candidates.items[slice_idx..],
            });

            try handles.append(handle);
        }

        for (handles.items) |handle| {
            handle.join();

            if (has_errored == true) {
                return error.ThreadFailed;
            }
        }
        scope.debug("Joined all thread", .{});

        // Output array
        var primes: ArrayList(usize) = ArrayList(usize).init(alloc.*);
        errdefer primes.deinit();

        for (return_lists.items) |list| {
            const slice = list.items;

            try primes.appendSlice(slice);
        }

        return primes;
    }

    fn threadFunction(
        self: *const ConcurrentWorker,
        out_ptr: *ArrayList(usize),
        err_ptr: *bool,
        slice: []const usize,
    ) !void {
        errdefer std.log.err("Thread failed", .{});
        errdefer err_ptr.* = true;

        // Do the calculations
        for (slice) |candidate| {
            if (self.checker.check(candidate)) {
                try out_ptr.append(candidate);
            }
        }
    }
};

test ConcurrentWorker {
    const checker = checkers.SimpleChecker.checker();
    const gen = generators.SimpleGen.generator();
    var worker_instance = ConcurrentWorker.init(gen, checker, 8);
    const worker = worker_instance.worker();

    const alloc = std.testing.allocator;

    const list = try worker.work(
        &alloc,
        10_000,
    );
    list.deinit();
}
