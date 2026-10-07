const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{ .default_target = .{
        .os_tag = .windows,
        .cpu_arch = .x86_64,
    } });

    const exe = b.addExecutable(.{
        .name = "grace",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/launcher.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    const dll = b.addLibrary(.{
        .name = "grace",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/grace.zig"),
            .optimize = optimize,
            .target = target,
        }),
    });
    b.installArtifact(dll);
}
