const std = @import("std");
const Build = std.Build;
const Step = Build.Step;
const Run = Step.Run;

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const fmt_step = b.addFmt(Step.Fmt.Options{ .paths = &[_][]const u8{
        "src",
        "build.zig",
    } });
    b.default_step.dependOn(&fmt_step.step);

    const exe = b.addExecutable(.{
        .name = "zig_primes",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const main_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_main_tests = b.addRunArtifact(main_tests);

    const runner_tests = b.addTest(.{
        .root_source_file = b.path("src/runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_runner_tests = b.addRunArtifact(runner_tests);

    const gen_tests = b.addTest(.{
        .root_source_file = b.path("src/candidate_gen.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_gen_tests = b.addRunArtifact(gen_tests);

    const checker_tests = b.addTest(.{
        .root_source_file = b.path("src/checker.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_checker_tests = b.addRunArtifact(checker_tests);

    const worker_tests = b.addTest(.{
        .root_source_file = b.path("src/worker.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_worker_tests = b.addRunArtifact(worker_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_main_tests.step);
    test_step.dependOn(&run_runner_tests.step);
    test_step.dependOn(&run_gen_tests.step);
    test_step.dependOn(&run_checker_tests.step);
    test_step.dependOn(&run_worker_tests.step);
}
