const std = @import("std");

pub const Checker = struct {
    checkFn: *const fn (n: usize) bool,

    fn init(ptr: anytype) Checker {
        const T = @TypeOf(ptr);
        const ptr_info = @typeInfo(T);

        if (ptr_info != .Pointer) @compileError("Pointer must be of type pointer");
        if (ptr_info.Pointer.size != .One)
            @compileError("Pointer must be a single item pointer");

        const child = ptr_info.Pointer.child;

        const wrapper = struct {
            pub fn inner(n: usize) bool {
                return @call(std.builtin.CallModifier.always_inline, child.check, .{n});
            }
        };

        return Checker{
            .checkFn = wrapper.inner,
        };
    }

    pub fn check(self: Checker, n: usize) bool {
        return self.checkFn(n);
    }
};

pub const SimpleChecker = struct {
    pub fn checker() Checker {
        return Checker.init(&SimpleChecker{});
    }

    fn check(n: usize) bool {
        @setCold(false); // This function will be hot asf
        if (n < 2) return false;

        for (2..n) |div| {
            if (n % div == 0) return false;
        }

        return true;
    }
};

pub const SmartChecker = struct {
    pub fn checker() Checker {
        return Checker.init(&SimpleChecker{});
    }

    fn check(n: usize) bool {
        @setCold(false);
        if (n < 2) return false;
        if (n <= 3) return true;

        var check_num: usize = 5;
        if ((n % 2) == 0 or (n % 3) == 0) {
            return false;
        }
        while (check_num * check_num <= n) : (check_num += 6) {
            if (n % check_num == 0) return false;
            if (n % (check_num + 2) == 0) return false;
        }
    }
};

pub const BranchlessChecker = struct {
    pub fn checker() Checker {
        return Checker.init(&BranchlessChecker{});
    }

    fn check(n: usize) bool {
        @setCold(false); // This function will be hot asf
        if (n < 2) return false;
        if (n <= 3) return true;

        var check_num: usize = 5;
        var maybe_prime: bool = (n % 2) != 0 and (n % 3) != 0;
        while (maybe_prime and check_num * check_num <= n) : (check_num += 6) {
            maybe_prime = n % check_num != 0 and n % (check_num + 2) != 0;
        }

        return maybe_prime;
    }
};

test SimpleChecker {
    const tst = std.testing;

    const CheckerTests = struct {
        pub fn tsts(checker: Checker) !void {
            try tst.expect(checker.check(2));
            try tst.expect(checker.check(3));
            try tst.expect(checker.check(5));
            try tst.expect(checker.check(7));
            try tst.expect(checker.check(11));
            try tst.expect(checker.check(13));
            try tst.expect(checker.check(17));
            try tst.expect(checker.check(19));
            try tst.expect(checker.check(23));
            try tst.expect(checker.check(29));
            try tst.expect(checker.check(31));
            try tst.expect(checker.check(37));
            try tst.expect(checker.check(41));
            try tst.expect(checker.check(43));
            try tst.expect(checker.check(47));
            try tst.expect(checker.check(53));
            try tst.expect(checker.check(59));
            try tst.expect(checker.check(61));
            try tst.expect(checker.check(67));
            try tst.expect(checker.check(71));
            try tst.expect(checker.check(73));
            try tst.expect(checker.check(79));
            try tst.expect(checker.check(83));
            try tst.expect(checker.check(89));
            try tst.expect(checker.check(97));

            try tst.expect(!checker.check(0));
            try tst.expect(!checker.check(1));
            try tst.expect(!checker.check(4));
            try tst.expect(!checker.check(6));
            try tst.expect(!checker.check(8));
            try tst.expect(!checker.check(9));
            try tst.expect(!checker.check(10));
            try tst.expect(!checker.check(25));
            try tst.expect(!checker.check(27));
        }
    };

    try CheckerTests.tsts(SimpleChecker.checker());
    try CheckerTests.tsts(SmartChecker.checker());
    try CheckerTests.tsts(BranchlessChecker.checker());
}
