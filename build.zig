const std = @import("std");
const rlz = @import("raylib_zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "hackathon",
        .root_module = exe_mod,
    });

    // Raylib
    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,

        .platform = rlz.PlatformBackend.glfw,
        .linux_display_backend = rlz.LinuxDisplayBackend.X11,

        // See https://github.com/Not-Nik/raylib-zig/issues/219
        // We can either have users download both, or maybe try disabling lld?
        // .shared = true,
    });

    const raylib = raylib_dep.module("raylib"); // main raylib module
    const raygui = raylib_dep.module("raygui"); // raygui module
    const raylib_artifact = raylib_dep.artifact("raylib"); // raylib C library

    exe.linkLibrary(raylib_artifact);
    exe.root_module.addImport("raylib", raylib);
    exe.root_module.addImport("raygui", raygui);

    // Build the C library
    const lib_c = b.addStaticLibrary(.{
        .name = "c_lib",
        .target = target,
        .optimize = optimize,
    });

    lib_c.addCSourceFile(.{
        .file = b.path("src/lib.c"),
        .flags = &[_][]const u8{"-std=c99"},
    });
    lib_c.addIncludePath(b.path("include"));
    lib_c.linkLibC();

    exe.addIncludePath(b.path("include"));
    exe.addIncludePath(b.path("src"));
    exe.linkLibrary(lib_c);
    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // Allow passing args to the exe like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
