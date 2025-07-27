const std = @import("std");
const rlz = @import("raylib_zig");

const exe_name = "hackathon";

const all_targets: []const std.Target.Query = &.{
    .{ .cpu_arch = .aarch64, .os_tag = .macos },
    // .{ .cpu_arch = .aarch64, .os_tag = .linux },
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    // .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .x86_64, .os_tag = .windows },
    //
    // TODO: add WASM support
    //.{ .cpu_arch = .wasm32, .os_tag = .emscripten },
};

const wasm_targets: []const std.Target.Query = &.{
    // TODO: add WASM support
    .{ .cpu_arch = .wasm32, .os_tag = .emscripten },
};

pub fn build(b: *std.Build) !void {
    const build_all = b.option(bool, "ball", "Build and package");
    const build_wasm = b.option(bool, "wasm", "Build and package WASM");

    const emcc = rlz.emcc;
    _ = emcc;

    const optimize = b.standardOptimizeOption(.{});

    const run_step = b.step("run", "Run the app");
    const pack_step = b.step("pack", "Build and package for each supported OS/arch");

    try buildRun(b, run_step, optimize);

    if (build_all orelse false) {
        try buildPack(b, pack_step, optimize, all_targets);
    } else if (build_wasm orelse false) {
        try buildPack(b, pack_step, optimize, wasm_targets);
    }
}

fn buildRun(b: *std.Build, parent: *std.Build.Step, optimize: std.builtin.OptimizeMode) !void {
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

const pkg_folder = "pkg";

// TODO: fix this function
fn buildPack(b: *std.Build, parent: *std.Build.Step, optimize: std.builtin.OptimizeMode, targets: []const std.Target.Query) !void {
    const rm_pkg = b.addSystemCommand(&.{ "rm", "-rf", pkg_folder });

    const mkdir_pkg = b.addSystemCommand(&.{ "mkdir", pkg_folder });
    mkdir_pkg.step.dependOn(&rm_pkg.step);

    for (targets) |t| {
        const target = b.resolveTargetQuery(t);
        const target_triple = try t.zigTriple(b.allocator);

        const exe = b.addExecutable(.{
            .name = exe_name,
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });

        try addRaylibDep(b, exe, target, optimize);

        const target_output = b.addInstallArtifact(exe, .{
            .dest_dir = .{
                .override = .{
                    .custom = target_triple,
                },
            },
        });

        b.getInstallStep().dependOn(&target_output.step);

        const move_output = b.addSystemCommand(&.{
            "mv",
            try std.fmt.allocPrint(b.allocator, "zig-out/{s}", .{target_triple}),
            ".",
        });

        move_output.step.dependOn(b.getInstallStep());

        const zip = b.addSystemCommand(&.{
            "zip",
            "-r",
            try std.fmt.allocPrint(b.allocator, "{s}/{s}.zip", .{ pkg_folder, target_triple }),
            target_triple,
        });

        zip.step.dependOn(&mkdir_pkg.step);
        zip.step.dependOn(&move_output.step);

        const rm_exe = b.addSystemCommand(&.{ "rm", "-rf", target_triple });
        rm_exe.step.dependOn(&zip.step);

        parent.dependOn(&rm_exe.step);
    }
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
