const std = @import("std");
const buildin = @import("builtin");

const Dependencies = [_][]const u8{ "pretty", "mibu" };
const Tests = [_][]const u8{ //
    "src/ast_tests.zig",
    "src/env_tests.zig",
    "src/evaluation_tests.zig",
    "src/gc_tests.zig",
    "src/reader_tests.zig",
    "src/value_tests.zig",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .Debug });

    const lib = b.addStaticLibrary(.{
        .name = "owl",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "owl",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    for (Dependencies) |dept| {
        const library = b.dependency(dept, .{ .target = target, .optimize = optimize });
        exe.root_module.addImport(dept, library.module(dept));
    }

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");

    for (Tests) |test_path| {
        const t = b.addTest(.{
            .root_source_file = b.path(test_path),
            .target = target,
            .optimize = optimize,
        });
        const run = b.addRunArtifact(t);
        test_step.dependOn(&run.step);
    }
}
