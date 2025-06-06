const std = @import("std");
const raylib_build = @import("raylib");

pub fn build(b: *std.Build) void {
    // 1) Pick up --target flags (e.g. --target, --cpu)
    const target = b.standardTargetOptions(.{});
    // 2) Pick up --release-fast / --debug / etc.
    const optimize = b.standardOptimizeOption(.{});

    // 3) Create a single module for your game entry point
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 4) Build an executable from that module
    const exe = b.addExecutable(.{
        .name = "zig_asteroids",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    // RAYLIB INCLUDES

    exe.addIncludePath(b.path("raygui"));

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
        .linux_display_backend = .X11,
    });

    const raylib = raylib_dep.module("raylib"); // main raylib module
    const raygui = raylib_dep.module("raygui"); // raygui module
    const raylib_artifact = raylib_dep.artifact("raylib"); // raylib C library

    exe.linkLibrary(raylib_artifact);
    exe.root_module.addImport("raylib", raylib);
    exe.root_module.addImport("raygui", raygui);

    // 6) Make `zig build run` work
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // 7) Support `zig build install`
    b.installArtifact(exe);
}
