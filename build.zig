const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    const lib = b.addStaticLibrary(.{
        .name = "tracy",
        .target = target,
        .optimize = optimize,
    });
    lib.root_module.sanitize_c = false;
    lib.defineCMacro("TRACY_ENABLE", "");
    lib.addCSourceFile(.{
        .file = .{ .path = "public/TracyClient.cpp" },
        .flags = &.{},
    });
    lib.linkLibCpp();

    if (target.result.os.tag == .windows) {
        lib.linkSystemLibrary("advapi32");
        lib.linkSystemLibrary("dbghelp");
        lib.linkSystemLibrary("user32");
        lib.linkSystemLibrary("ws2_32");
    }

    b.installArtifact(lib);

    _ = b.addModule("tracy", .{
        .root_source_file = .{ .path = "tracy.zig" },
    });
}
