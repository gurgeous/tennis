pub fn build(b: *std.Build) void {
    // options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //
    // deps
    //

    const clap_mod = b.dependency("clap", .{ .target = target, .optimize = optimize }).module("clap");
    const mibu_mod = b.dependency("mibu", .{ .target = target, .optimize = optimize }).module("mibu");
    const zcsv_mod = b.dependency("zcsv", .{ .target = target, .optimize = optimize }).module("zcsv");

    //
    // build options
    //

    const build_options = b.addOptions();
    const appVersion = @import("build.zig.zon").version;
    const version = if (appVersion.len > 0) appVersion else "unknown";
    build_options.addOption([]const u8, "version", version);

    //
    // main
    //

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "clap", .module = clap_mod },
            .{ .name = "mibu", .module = mibu_mod },
            .{ .name = "zcsv", .module = zcsv_mod },
            .{ .name = "build_options", .module = build_options.createModule() },
        },
    });

    const exe = b.addExecutable(.{ .name = "tennis", .root_module = mod });
    b.installArtifact(exe);

    //
    // run
    //

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    //
    // run tests
    //

    const test_step = b.step("test", "Run unit tests");
    const unit_tests = b.addTest(.{ .name = "tennis-tests", .root_module = mod });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);

    //
    // tennis-tests artifact, for kcov
    //

    const install_unit_tests = b.addInstallArtifact(unit_tests, .{ .dest_sub_path = "tennis-tests" });
    const test_bin_step = b.step("test-bin", "Build unit test binary");
    test_bin_step.dependOn(&install_unit_tests.step);

    const coverage_tests = b.addTest(.{
        .name = "tennis-coverage-tests",
        .root_module = mod,
        .use_llvm = true,
    });
    const install_coverage_tests = b.addInstallArtifact(coverage_tests, .{ .dest_sub_path = "tennis-coverage-tests" });
    const coverage_bin_step = b.step("coverage-bin", "Build LLVM-backed unit test binary");
    coverage_bin_step.dependOn(&install_coverage_tests.step);
}

const std = @import("std");
