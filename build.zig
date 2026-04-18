pub fn build(b: *std.Build) void {
    // options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // deps
    const clap_mod = b.dependency("clap", .{ .target = target, .optimize = optimize }).module("clap");
    const mibu_mod = b.dependency("mibu", .{ .target = target, .optimize = optimize }).module("mibu");

    // build options
    const build_options = b.addOptions();
    build_options.addOption([]const u8, "version", getVersion(b));

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

    const kcov_step = b.step("kcov-tests", "Build unit test bin for kcov");
    const cov_tests = b.addTest(.{ .name = "kcov-tests", .root_module = mod, .use_llvm = true });
    const install_cov_tests = b.addInstallArtifact(cov_tests, .{ .dest_sub_path = "kcov-tests" });
    kcov_step.dependOn(&install_cov_tests.step);
}

fn getVersion(b: *std.Build) []const u8 {
    const sha = getSha(b);

    // 1. TENNIS_VERSION
    if (b.graph.environ_map.get("TENNIS_VERSION")) |v| {
        _ = std.SemanticVersion.parse(v) catch @panic("TENNIS_VERSION must be int.int.int");
        return b.fmt("{s} ({s})", .{ v, sha orelse @panic("TENNIS_VERSION requires git sha") });
    }

    // 2. sha? use that
    if (sha) |s| return b.fmt("built from source ({s})", .{s});

    // 3. fallback, probably just a tarball
    return "built from source (unknown sha)";
}

fn getSha(b: *std.Build) ?[]const u8 {
    var code: u8 = 0;
    const sha_output = b.runAllowFail(&.{ "git", "rev-parse", "--short", "HEAD" }, &code, .ignore) catch null;
    if (sha_output) |out| return std.mem.trim(u8, out, "\r\n");
    return null;
}

const std = @import("std");
