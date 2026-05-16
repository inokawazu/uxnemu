const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});



    const uxn = b.addModule("uxn", .{
        .root_source_file = b.path("src/uxn.zig"),
        .target = target,
    });

    const devices = b.addModule("devices", .{
        .root_source_file = b.path("src/devices/devices.zig"),
        .target = target,
            .imports = &.{
                .{ .name = "uxn", .module = uxn },
            },
    });



    const exe = b.addExecutable(.{
        .name = "uxncli",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/platforms/console.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "uxn", .module = uxn },
                .{ .name = "devices", .module = devices },
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





    const uxn_tests = b.addTest(.{
        .root_module = uxn,
    });
    const run_uxn_tests = b.addRunArtifact(uxn_tests);

    const devices_tests = b.addTest(.{
        .root_module = devices,
    });
    const run_devices_tests = b.addRunArtifact(devices_tests);


    const test_step = b.step("test", "Run Emulator Tests");
    test_step.dependOn(&run_uxn_tests.step);
    test_step.dependOn(&run_devices_tests.step);
}
