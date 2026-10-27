const std = @import("std");

// `zig build` runs this function to construct the build graph. Nothing is
// compiled here; we only describe *what* should be built and how.
pub fn build(b: *std.Build) void {
    // `-Dtarget=...` and `-Doptimize=...` on the command line.
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "seek",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    // `zig build` (the default "install" step) copies the binary to zig-out/bin.
    b.installArtifact(exe);

    // `zig build run -- ARGS` builds, installs, then runs seek with ARGS.
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    const run_step = b.step("run", "Run seek");
    run_step.dependOn(&run_cmd.step);

    // `zig build test` compiles and runs every `test` block reachable from main.zig.
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_tests.step);
}
