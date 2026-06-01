const std = @import("std");
const uxn = @import("uxn");
const Console = @import("devices").Console;
const System = @import("devices").System;
const print = @import("std").debug.print;

const UXNCLIError = error{
    MissingROM,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    const args = try init.minimal.args.toSlice(init.arena.child_allocator);

    if (args.len < 2) {
        //add error
        std.log.err("usage uxncli <input.rom> [args...]\n", .{});
        return UXNCLIError.MissingROM;
    }

    const program = try std.Io.Dir.cwd()
        .readFileAlloc(io, args[1], init.gpa, .unlimited);
    defer init.gpa.free(program);

    var vm = try uxn.VM.init(init.gpa);
    defer vm.deinit(init.gpa);

    try vm.load_rom(program);

    const uxn_args = try convertToMutableSlices(init.gpa, args[2..]);
    defer {
        for (uxn_args) |slice| init.gpa.free(slice);
        init.gpa.free(uxn_args);
    }

    const stdin_buffer = try init.gpa.alloc(u8, 0x100);
    var stdin = std.Io.File.stdin().reader(io, stdin_buffer);
    defer init.gpa.free(stdin_buffer);

    const stdout_buffer = try init.gpa.alloc(u8, 0x100);
    var stdout = std.Io.File.stdout().writer(io, stdout_buffer);
    defer init.gpa.free(stdout_buffer);

    const stderr_buffer = try init.gpa.alloc(u8, 0x100);
    var stderr = std.Io.File.stderr().writer(io, stderr_buffer);
    defer init.gpa.free(stderr_buffer);

    var console: Console = Console.init(&stdin.interface, &stdout.interface, &stderr.interface, uxn_args);

    var system: System = .{ .debug_writer = &stderr.interface };

    var cli_dev: CLI = .{ .console = &console, .system = &system };

    const dev = uxn.Device.init(&cli_dev);

    // Reset Vector
    console.boot(&vm);
    vm.eval(uxn.RESET_VECTOR, dev);

    // Console Vector
    while (vm.ram[Console.VECTOR] != 0 and System.state(&vm) == 0) {
        console.read_input(&vm);
        const console_vector_addr = vm.fetch(Console.VECTOR, 1);
        vm.eval(console_vector_addr, dev);
    }

    std.process.exit(System.state(&vm) & 0x7f);
}

fn convertToMutableSlices(allocator: std.mem.Allocator, input: []const [:0]const u8) ![][]u8 {
    const result = try allocator.alloc([]u8, input.len);
    errdefer {
        allocator.free(result);
        // for (result) |slice| allocator.free(slice);
    }

    for (input, 0..) |src, i| {
        const dst = try allocator.alloc(u8, src.len);
        @memcpy(dst, src);
        result[i] = dst;
    }

    return result;
}

const CLI = struct {
    console: *Console,
    system: *System,

    const Self = @This();

    pub fn dei(self: *Self, vm: *uxn.VM, dev: u8, s: u1) u16 {
        switch (dev) {
            0x00...0x0f => return self.system.dei(vm, dev, s),
            0x10...0x1f => return self.console.dei(vm, dev, s),
            else => return vm.fetch(dev, s),
        }
    }

    pub fn deo(self: *Self, vm: *uxn.VM, dev: u8, value: u16, s: u1) void {
        switch (dev) {
            0x00...0x0f => return self.system.deo(vm, dev, value, s),
            0x10...0x1f => return self.console.deo(vm, dev, value, s),
            else => vm.store(value, dev, s),
        }
    }
};
