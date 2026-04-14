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

    const examples = [_][]const u8{
        "color",
        "event",
        "alternate_screen",
    };

    for (examples) |example_name| {
        const example = b.addExecutable(.{
            .name = example_name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example_name})),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "mibu", .module = mibu_mod },
                },
            }),
        });

        const install_example = b.addRunArtifact(example);
        const example_step = b.step(example_name, b.fmt("Run {s} example", .{example_name}));
        example_step.dependOn(&install_example.step);
        example_step.dependOn(&example.step);
    }
}
