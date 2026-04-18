const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mibu_mod = b.addModule("mibu", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run all tests.");
    const tests = b.addTest(.{ .root_module = mibu_mod });
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);
}
