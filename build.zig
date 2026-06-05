const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const uxn = b.addModule("uxn", .{
        .root_source_file = b.path("src/uxn.zig"),
        .target = target,
        .optimize = optimize,
    });

    const ctime = b.addTranslateC(.{ 
        .root_source_file = b.path("src/c/test_time.h"),
        .target = target,
        .optimize = optimize,
    },);
    const time = ctime.createModule();

    const devices = b.addModule("devices", .{
        .root_source_file = b.path("src/devices/devices.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "uxn", .module = uxn },
            .{ .name = "ctime", .module = time },
        },
    });

    const cli_exe = b.addExecutable(.{
        .name = "uxncli",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/platforms/cli.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "uxn", .module = uxn },
                .{ .name = "devices", .module = devices },
            },
        }),
    });

    addExeToBuild(b, cli_exe, "run_cli", "Run the cli emulator");

    const asm_exe = b.addExecutable(.{
        .name = "uxnasm",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/asm/uxnasm.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "uxn", .module = uxn },
                .{ .name = "devices", .module = devices },
            },
        }),
    });

    addExeToBuild(b, asm_exe, "run_asm", "Run the assembler");

    const test_step = b.step("test", "Run Emulator Tests");

    // uxn test files
    const uxn_test_files = [_][]const u8{
        "src/uxn.zig",
        // add more uxn source files here as needed
    };

    for (uxn_test_files) |path| {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(path),
                .target = target,
            }),
        });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }

    // devices test files — each gets its own test artifact so tests in
    // sibling files (imported via relative paths) actually run
    const devices_test_files = [_][]const u8{
        "src/devices/devices.zig",
        "src/devices/system.zig",
        // add more device source files here as needed
    };

    for (devices_test_files) |path| {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(path),
                .target = target,
                .imports = &.{
                    .{ .name = "uxn", .module = uxn },
                },
            }),
        });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }


    // devices test files — each gets its own test artifact so tests in
    // sibling files (imported via relative paths) actually run
    const assembler_test_files = [_][]const u8{
        "src/asm/assembler.zig",
        "src/asm/lexer.zig",
    };

    for (assembler_test_files) |path| {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(path),
                .target = target,
                .imports = &.{
                    .{ .name = "uxn", .module = uxn },
                },
            }),
        });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }

}

fn addExeToBuild(b: *std.Build, exe: *std.Build.Step.Compile, name: []const u8, description: []const u8) void {
    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step(name, description);
    run_step.dependOn(&run_cmd.step);
}
