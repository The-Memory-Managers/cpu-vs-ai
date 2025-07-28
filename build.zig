const std = @import("std");
const rlz = @import("raylib_zig");

const exe_name = "hackathon";

pub fn build(b: *std.Build) !void {
    const build_wasm = b.option(bool, "bwasm", "Build and package WASM");

    const emcc = rlz.emcc;
    _ = emcc;

    const optimize = b.standardOptimizeOption(.{});

    const run_step = b.step("run", "Run the app");

    if (build_wasm orelse false) {
        try buildWasm(b, run_step, optimize);
    } else {
        try buildNative(b, run_step, optimize);
    }
}

fn buildNative(b: *std.Build, parent: *std.Build.Step, optimize: std.builtin.OptimizeMode) !void {
    const target = b.standardTargetOptions(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = exe_name,
        .root_module = exe_mod,
    });

    try addRaylibDep(b, exe, target, optimize);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    parent.dependOn(&run_cmd.step);
}

fn buildWasm(b: *std.Build, parent: *std.Build.Step, optimize: std.builtin.OptimizeMode) !void {
    if (true)
        @panic("WASM builds are not supported at this time");

    const target = b.standardTargetOptions(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = exe_name,
        .root_module = exe_mod,
    });

    try addRaylibDep(b, exe, target, optimize);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    parent.dependOn(&run_cmd.step);
}

fn addRaylibDep(b: *std.Build, exe: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !void {
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
}
