const std = @import("std");
const fmt = std.fmt;

const eql = std.mem.eql;
const Allocator = std.mem.Allocator;
const parseInt = fmt.parseInt;

pub const Config = struct {
    pub const ConfigError = error{
        OptionWithoutValue,
        InvalidValue,
    } || fmt.ParseIntError || std.process.ArgIterator.InitError;

    const Self = @This();

    target: usize = 1_000_000,
    runs: u32 = 1,
    warmup: u32 = 0,
    concurrency: u32 = 16,
    time_ns: u64 = 5 * std.time.ns_per_s,

    /// Allocator is only used to parse arguments, the config will be placed on the
    /// stack and does not have to be deallocated.
    pub fn init(alloc: Allocator) ConfigError!Self {
        const T: type = usize;

        var config = Self{};

        var args = try std.process.argsWithAllocator(alloc);
        defer args.deinit();

        while (args.next()) |arg| {
            if (eql(u8, arg, "-t")) {
                const next_arg = args.next() orelse return ConfigError.OptionWithoutValue;

                config.target = try parseInt(T, next_arg, 10);
            } else if (eql(u8, arg, "-r")) {
                const next_arg = args.next() orelse return ConfigError.OptionWithoutValue;

                config.runs = try parseInt(u32, next_arg, 10);
            } else if (eql(u8, arg, "-w")) {
                const next_arg = args.next() orelse return ConfigError.OptionWithoutValue;

                config.warmup = try parseInt(u32, next_arg, 10);
            } else if (eql(u8, arg, "-c")) {
                const next_arg = args.next() orelse return ConfigError.OptionWithoutValue;

                const concurrency = try parseInt(u32, next_arg, 10);

                if (concurrency == 0) return ConfigError.InvalidValue;

                config.concurrency = concurrency;
            } else if (eql(u8, arg, "-d")) {
                const next_arg = args.next() orelse return ConfigError.OptionWithoutValue;

                config.time_ns = try parseInt(u64, next_arg, 10) * std.time.ns_per_s;
            }
        }

        return config;
    }
};
