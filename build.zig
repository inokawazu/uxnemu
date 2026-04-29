const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("uxn", .{
        .root_source_file = b.path("src/uxn.zig"),
        .target = target,
    });
    

    const exe = b.addExecutable(.{
        .name = "uxncli",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/platforms/console.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "uxn", .module = mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run_cli", "Run the cli emulator");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }




    const raylib_lib = b.dependency("raylib", .{
        .target = target,
        .optimize = optimize,
        .platform = .glfw,
    });
    const raylib = raylib_lib.module("raylib");

    const exe_ray = b.addExecutable(.{
        .name = "uxnray",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/platforms/raylib.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "uxn", .module = mod },
            },
        }),
    });

    exe_ray.root_module.addImport("raylib", raylib);

    b.installArtifact(exe_ray);

    const run_ray_step = b.step("run_ray", "Run the cli emulator");

    const run_ray_cmd = b.addRunArtifact(exe_ray);
    run_ray_step.dependOn(&run_ray_cmd.step);

    run_ray_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_ray_cmd.addArgs(args);
    }







    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run Emulator Tests");
    test_step.dependOn(&run_mod_tests.step);
}
