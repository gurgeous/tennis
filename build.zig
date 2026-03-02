const std = @import("std");

pub fn build(b: *std.Build) void {
    // options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const version = b.option([]const u8, "version", "Application version") orelse detectVersion(b) orelse "unknown";

    //
    // deps
    //

    const clap_dep = b.dependency("clap", .{
        .target = target,
        .optimize = optimize,
    });
    const csv_dep = b.dependency("csv", .{
        .target = target,
        .optimize = optimize,
    });
    const mibu_dep = b.dependency("mibu", .{
        .target = target,
        .optimize = optimize,
    });

    const clap_mod = clap_dep.module("clap");
    const csv_mod = csv_dep.module("zcsv");
    const mibu_mod = mibu_dep.module("mibu");
    const build_options = b.addOptions();
    build_options.addOption([]const u8, "version", version);

    // main
    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "mibu", .module = mibu_mod },
            .{ .name = "clap", .module = clap_mod },
            .{ .name = "zig_csv", .module = csv_mod },
            .{ .name = "build_options", .module = build_options.createModule() },
        },
    });

    const exe = b.addExecutable(.{ .name = "tennis", .root_module = mod });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");
    const unit_tests = b.addTest(.{ .root_module = mod });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);
}

fn detectVersion(b: *std.Build) ?[]const u8 {
    const result = std.process.Child.run(.{
        .allocator = b.allocator,
        .argv = &.{ "git", "describe", "--tags", "--always", "--dirty" },
    }) catch return null;
    defer b.allocator.free(result.stdout);
    defer b.allocator.free(result.stderr);

    if (result.term.Exited != 0) return null;

    const trimmed = std.mem.trimRight(u8, result.stdout, &std.ascii.whitespace);
    if (trimmed.len == 0) return null;

    return b.allocator.dupe(u8, trimmed) catch null;
}
