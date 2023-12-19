const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "ora",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    addDependencies(b, exe, target, optimize);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    addDependencies(b, main_tests, target, optimize);

    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}

pub fn addDependencies(
    b: *std.Build,
    step: *std.build.Step.Compile,
    target: std.zig.CrossTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });

    const xev = b.dependency("libxev", .{ .target = target, .optimize = optimize });
    step.addModule("xev", xev.module("xev"));

    step.linkLibC();
    step.addIncludePath(.{ .path = "include/sokol_gp/" });
    step.addIncludePath(.{ .path = "include/sokol/" });
    step.addIncludePath(.{ .path = "include/stb/" });
    step.addIncludePath(.{ .path = "include/fontstash/src/" });

    step.addModule("sokol", dep_sokol.module("sokol"));
    step.linkLibrary(dep_sokol.artifact("sokol"));
    b.installArtifact(step);

    const glfw_dep = b.dependency("mach_glfw", .{
        .target = step.target,
        .optimize = step.optimize,
    });
    step.addModule("mach-glfw", glfw_dep.module("mach-glfw"));
    @import("mach_glfw").link(glfw_dep.builder, step);

    step.addCSourceFile(.{
        .file = .{ .path = "include/deps.c" },
        .flags = &.{},
    });
}
