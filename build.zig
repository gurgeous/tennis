pub fn build(b: *std.Build) void {
    // options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //
    // deps
    //

    const clap_dep = b.dependency("clap", .{ .target = target, .optimize = optimize });
    const mibu_dep = b.dependency("mibu", .{ .target = target, .optimize = optimize });
    const zcsv_dep = b.dependency("csv", .{ .target = target, .optimize = optimize });

    const clap_mod = clap_dep.module("clap");
    const mibu_mod = mibu_dep.module("mibu");
    const zcsv_mod = zcsv_dep.module("zcsv");

    // build optoions
    const build_options = b.addOptions();
    const appVersion = @import("build.zig.zon").version;
    const version = if (appVersion.len > 0) appVersion else "unknown";
    build_options.addOption([]const u8, "version", version);

    // main
    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "clap", .module = clap_mod },
            .{ .name = "mibu", .module = mibu_mod },
            .{ .name = "zig_csv", .module = zcsv_mod },
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

const std = @import("std");
