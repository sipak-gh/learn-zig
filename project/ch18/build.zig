const std = @import("std");

// `zig build` runs this function to construct the build graph. Nothing is
// compiled here; we only describe *what* should be built and how.
pub fn build(b: *std.Build) void {
    // `-Dtarget=...` and `-Doptimize=...` on the command line.
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // A project-specific option: `zig build -Dversion=1.2.3`. Without it,
    // the version comes from build.zig.zon, which build.zig can @import.
    const version = b.option([]const u8, "version", "Version string for --version") orelse
        @import("build.zig.zon").version;

    // Values computed here become a module that the program imports as
    // @import("build_options").
    const options = b.addOptions();
    options.addOption([]const u8, "version", version);

    const exe = b.addExecutable(.{
        .name = "seek",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addOptions("build_options", options);
    // `zig build` (the default "install" step) copies the binary to zig-out/bin.
    b.installArtifact(exe);

    // `zig build run -- ARGS` builds, installs, then runs seek with ARGS.
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    const run_step = b.step("run", "Run seek");
    run_step.dependOn(&run_cmd.step);

    // `zig build test` builds main.zig in test mode and runs its tests. The
    // tests share the executable's module, build_options included.
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_tests.step);
}
