pub const Checkers = .{
    VectorChecker,
    CheatingVectorChecker,
    BranchlessChecker,
    RustChecker,
};

pub fn SimpleChecker(comptime CheckerGen: type) type {
    return struct {
        checker_gen: CheckerGen,

        pub fn init(checker_gen: CheckerGen) @This() {
            return .{
                .checker_gen = checker_gen,
            };
        }

        pub fn check(self: *@This(), num: u32) bool {
            self.checker_gen.reset();
            var check_num = self.checker_gen.next();
            while (check_num * check_num <= num) : (check_num = self.checker_gen.next()) {
                if (num % check_num == 0) {
                    return false;
                }
            }
            return num % check_num != 0 or num == 2;
        }
    };
}

pub fn RustChecker(comptime CheckerGen: type) type {
    return struct {
        checker_gen: CheckerGen,

        pub fn init(checker_gen: CheckerGen) @This() {
            return .{
                .checker_gen = checker_gen,
            };
        }

        pub fn check(self: *@This(), num: u32) bool {
            self.checker_gen.reset();

            if (num < 4) {
                @branchHint(.unlikely);
                return true;
            }

            if ((num % 2 == 0 or num % 3 == 0) and (num != 2 and num != 3)) {
                @branchHint(.likely);
                return false;
            }

            var check_num = self.checker_gen.next();
            while (check_num < 5) : (check_num = self.checker_gen.next()) {}

            while (check_num * check_num <= num) : (check_num = self.checker_gen.next()) {
                if (num % check_num == 0) {
                    return false;
                }
            }
            return true;
        }
    };
}

pub fn BranchlessChecker(comptime CheckerGen: type) type {
    return struct {
        checker_gen: CheckerGen,

        pub fn init(checker_gen: CheckerGen) @This() {
            return .{
                .checker_gen = checker_gen,
            };
        }

        pub fn check(self: *@This(), num: u32) bool {
            self.checker_gen.reset();

            if ((num % 2 == 0 or num % 3 == 0) and (num != 2 and num != 3)) {
                @branchHint(.likely);
                return false;
            }

            var check_num = self.checker_gen.next();
            while (check_num < 5) : (check_num = self.checker_gen.next()) {}

            var keep_checking: bool = true;
            while (check_num * check_num <= num and keep_checking) : (check_num = self.checker_gen.next()) {
                keep_checking = num % check_num != 0;
            }

            return keep_checking or num == 2 or num == 3;
        }
    };
}

pub fn VectorChecker(comptime CheckerGen: type) type {
    return struct {
        checker_gen: CheckerGen,

        const vector_len = simd.suggestVectorLength(u32) orelse 1;
        const VecT = @Vector(vector_len, u32);

        pub fn init(checker_gen: CheckerGen) @This() {
            return .{
                .checker_gen = checker_gen,
            };
        }

        pub fn check(self: *@This(), num: u32) bool {
            self.checker_gen.reset();

            if ((num % 2 == 0 or num % 3 == 0) and (num != 2 and num != 3)) {
                @branchHint(.likely);
                return false;
            }

            const num_vec: VecT = @splat(num);
            var check_vec: VecT = self.checkVector();
            var keep_checking: bool = true;
            while (keep_checking and
                check_vec[0] * check_vec[0] <= num) : (check_vec = self.checkVector())
            {
                const pred = check_vec < num_vec;
                const mod_vec = num_vec % check_vec;
                const valid_vec = @select(u32, pred, mod_vec, @as(VecT, @splat(1)));
                keep_checking = @reduce(.Min, valid_vec) != 0;
            }

            return keep_checking;
        }

        fn checkVector(self: *@This()) VecT {
            var vec: VecT = undefined;

            inline for (0..vector_len) |i| {
                vec[i] = self.checker_gen.next();
            }

            return vec;
        }
    };
}

pub fn CheatingVectorChecker(comptime CheckerGen: type) type {
    return struct {
        checker_gen: CheckerGen,

        const vector_len = simd.suggestVectorLength(u32) orelse 1;
        const VecT = @Vector(vector_len, u32);

        pub fn init(checker_gen: CheckerGen) @This() {
            return .{
                .checker_gen = checker_gen,
            };
        }

        pub fn check(self: *@This(), num: u32) bool {
            self.checker_gen.reset();

            if (num < 25) {
                @branchHint(.unlikely);
                switch (num) {
                    2,
                    3,
                    5,
                    7,
                    11,
                    13,
                    17,
                    19,
                    23,
                    => return true,
                    else => return false,
                }
            }

            if (num % 2 == 0 or num % 3 == 0) {
                @branchHint(.likely);
                return false;
            }

            const num_vec: VecT = @splat(num);
            var check_vec: VecT = self.checkVector();
            while (check_vec[0] * check_vec[0] <= num) : (check_vec = self.checkVector()) {
                const mod_vec = num_vec % check_vec;
                if (@reduce(.Min, mod_vec) == 0) return false;
            }

            return true;
        }

        fn checkVector(self: *@This()) VecT {
            var vec: VecT = undefined;

            inline for (0..vector_len) |i| {
                vec[i] = self.checker_gen.next();
            }

            return vec;
        }
    };
}

const std = @import("std");
const simd = std.simd;
