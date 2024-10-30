pub const CheckerGenerators = .{SmartCheckerGen};
pub const Generators = .{SimpleGenerator};

const SmartCheckerGen = struct {
    num: u32,
    state: enum { @"2", @"3", even, odd },

    pub fn init() @This() {
        return .{
            .num = 2,
            .state = .@"2",
        };
    }

    pub fn reset(self: *@This()) void {
        self.state = .@"2";
    }

    pub fn next(self: *@This()) u32 {
        switch (self.state) {
            .@"2" => {
                self.state = .@"3";
                return 2;
            },
            .@"3" => {
                self.state = .even;
                self.num = 5;
                return 3;
            },
            .even => {
                self.state = .odd;
                return self.num;
            },
            .odd => {
                defer self.num += 6;
                self.state = .even;
                return self.num + 2;
            },
        }
    }
};

const SimpleCheckerGen = struct {
    num: u32,

    const start = 2;

    pub fn init() @This() {
        return .{
            .num = start,
        };
    }

    pub fn reset(self: *@This()) void {
        self.num = start;
    }

    pub fn next(self: *@This()) u32 {
        defer self.num += 1;
        return self.num;
    }
};

// ---------------------------------------------------------

pub fn SimpleGenerator(comptime Checker: type) type {
    return struct {
        checker: Checker,
        num: u32,

        const start = 2;

        fn nextCanditate(self: *@This()) u32 {
            defer self.num += 1;
            return self.num;
        }

        pub fn init(checker: Checker) @This() {
            return .{
                .checker = checker,
                .num = start,
            };
        }

        pub fn reset(self: *@This()) void {
            self.num = start;
        }

        pub fn next(self: *@This(), limit: u32) ?u32 {
            var num = self.nextCanditate();
            while (num < limit) : (num = self.nextCanditate()) {
                if (self.checker.check(num))
                    return num;
            }
            return null;
        }
    };
}
