const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const GeneratorError = error{
    TooLowTarget,
} || Allocator.Error;

pub const Generator = struct {
    genFn: *const fn (
        alloc: *const Allocator,
        target: usize,
    ) GeneratorError!std.ArrayList(usize),

    fn init(ptr: anytype) Generator {
        const T = @TypeOf(ptr);
        const ptr_info = @typeInfo(T);

        if (ptr_info != .Pointer) @compileError("Pointer must be of type pointer");
        if (ptr_info.Pointer.size != .One)
            @compileError("Pointer must be a single item pointer");

        const child = ptr_info.Pointer.child;

        const wrapper = struct {
            pub fn inner(alloc: *const Allocator, target: usize) GeneratorError!ArrayList(usize) {
                return @call(.always_inline, child.gen, .{ alloc, target });
                // return child.gen(alloc, target);
            }
        };

        return Generator{
            .genFn = wrapper.inner,
        };
    }

    pub fn gen(
        self: Generator,
        alloc: *const Allocator,
        target: usize,
    ) GeneratorError!std.ArrayList(usize) {
        return self.genFn(alloc, target);
    }
};

pub const SimpleGen = struct {
    pub fn generator() Generator {
        return Generator.init(&SimpleGen{});
    }

    fn gen(
        alloc: *const Allocator,
        target: usize,
    ) GeneratorError!std.ArrayList(usize) {
        var candidates = std.ArrayList(usize).init(alloc.*);
        errdefer candidates.deinit();

        for (0..target + 1) |n| {
            try candidates.append(n);
        }

        return candidates;
    }
};

test SimpleGen {
    const alloc = std.testing.allocator;
    var cands = try SimpleGen.gen(&alloc, 10);

    const slice = try cands.toOwnedSlice();
    defer alloc.free(slice);

    const expected: []const usize = &[_]usize{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    try std.testing.expectEqualSlices(usize, expected, slice);
}

pub const SmartGen = struct {
    pub fn generator() Generator {
        return Generator.init(&SmartGen{});
    }

    fn gen(alloc: *const Allocator, target: usize) GeneratorError!std.ArrayList(usize) {
        if (target < 5) return GeneratorError.TooLowTarget;

        var candidates = std.ArrayList(usize).init(alloc.*);
        errdefer candidates.deinit();

        try candidates.append(2);
        try candidates.append(3);

        var num: usize = 5;
        while (num + 2 <= target) {
            try candidates.append(num);

            num += 2;

            try candidates.append(num);

            num += 4;
        }

        if (num <= target) try candidates.append(num);

        return candidates;
    }
};

test SmartGen {
    const tst = std.testing;

    const alloc = tst.allocator;
    var cands = try SmartGen.gen(&alloc, 30);

    const slice = try cands.toOwnedSlice();
    defer alloc.free(slice);

    const expected: []const usize = &[_]usize{ 2, 3, 5, 7, 11, 13, 17, 19, 23, 25, 29 };
    try tst.expectEqualSlices(usize, expected, slice);
}

test "SmartGen 5" {
    const tst = std.testing;

    const alloc = tst.allocator;
    var cands = try SmartGen.gen(&alloc, 5);

    const slice = try cands.toOwnedSlice();
    defer alloc.free(slice);

    const expected: []const usize = &[_]usize{ 2, 3, 5 };
    try tst.expectEqualSlices(usize, expected, slice);
}

test "SmartGen too small" {
    const tst = std.testing;

    const alloc = tst.allocator;
    try tst.expectError(GeneratorError.TooLowTarget, SmartGen.gen(&alloc, 4));
}
