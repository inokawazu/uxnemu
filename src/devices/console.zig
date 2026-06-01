const std = @import("std");
const uxn = @import("uxn");
const T = @This();

inIo: *std.Io.Reader,
outIo: *std.Io.Writer,
errIo: *std.Io.Writer,
args: [][]u8,
argi: usize,
argi_j: usize,
// end_args: bool,
// reached_inIo_end: bool = true,

pub const VECTOR: u8 = 0x10;
pub const READ: u8 = 0x12;
pub const TYPE: u8 = 0x17;
pub const WRITE: u8 = 0x18;
pub const ERROR: u8 = 0x19;
pub const ADDR: u8 = 0x1c;
pub const MODE: u8 = 0x1e;
pub const EXEC: u8 = 0x1f;

const Self = @This();

pub fn init(inIo: *std.Io.Reader, outIo: *std.Io.Writer, errIo: *std.Io.Writer, args: [][]u8) Self {
    const argi = 0;
    const argii = 0;

    // var end_inIo = false;
    // _ = inIo.peek(1) catch { end_inIo = true; };

    // const end_args = args.len == 0;

    return .{
        .inIo = inIo,
        .outIo = outIo,
        .errIo = errIo,
        .args = args,
        .argi = argi,
        .argi_j = argii,
        // .end_inIo = end_inIo,
        // .end_args= end_args,
    };
}

const reboot = boot;
pub fn boot(self: *Self, vm: *uxn.VM) void {
    for (0x10..0x20) |i| vm.ram[i] = 0;

    const input_type = if (!self.end_args())
        ConsoleInputType.argument
    else
        ConsoleInputType.no_queue;
    vm.store(@intFromEnum(input_type), TYPE, 0);
}

pub fn dei(_: *Self, vm: *uxn.VM, dev: u8, s: u1) u16 {
    // std.debug.print("running DEO for device 0x{X:2>0}\n", .{dev});
    const x = vm.fetch(dev, s);
    return x;
}

pub fn deo(self: *Self, vm: *uxn.VM, dev: u8, value: u16, s: u1) void {
    // std.debug.print("running DEO for device 0x{X:2>0}\n", .{dev});
    switch (dev) {
        WRITE => {
            const output = [_]u8{@truncate(value)};
            self.outIo.writeAll(&output) catch {
                @panic("Unimplemented\n");
            };
            self.outIo.flush() catch {
                @panic("Unimplemented\n");
            };
        },
        ERROR => {
            const output = [_]u8{@truncate(value)};
            self.errIo.writeAll(&output) catch {
                @panic("Unimplemented\n");
            };
            self.errIo.flush() catch {
                @panic("Unimplemented\n");
            };
        },
        else => {},
    }
    vm.store(value, dev, s);
}

pub fn end_args(self: *const Self) bool {
    return self.argi >= self.args.len;
}

pub fn end_inIo(self: *const Self) bool {
    _ = self.inIo.peek(1) catch {
        return true;
    };
    return false;
}

pub fn fetch_input(self: *Self) ConsoleInput {
    var console_input: ConsoleInput = undefined;
    if (!self.end_args()) {
        if (self.argi_j < self.args[self.argi].len) {
            console_input.c = self.args[self.argi][self.argi_j];
            console_input.t = .argument;
            self.argi_j += 1;
        } else {
            self.argi += 1;
            console_input.c = '\n';

            if (self.argi == self.args.len) {
                console_input.t = .argument_end;
            } else {
                console_input.t = .argument_spacer;
            }
            self.argi_j = 0;
        }
    } else if (!self.end_inIo()) {
        var output = [_]u8{0};
        self.inIo.readSliceAll(&output) catch unreachable;

        console_input.c = output[0];
        console_input.t = .stdin;
    } else {
        console_input.c = '\n';
        console_input.t = .no_queue;
    }

    return console_input;
}

pub fn read_input(self: *Self, vm: *uxn.VM) void {
    const input = self.fetch_input();
    vm.store(@intCast(input.c), @intCast(READ), 0);
    vm.store(@intFromEnum(input.t), @intCast(TYPE), 0);
}

const ConsoleInput = struct { c: u8, t: ConsoleInputType };

// no-queue(0), stdin(1), argument(2), argument-spacer(3), argument-end(4)
const ConsoleInputType = enum(u4) {
    no_queue = 0,
    stdin = 1,
    argument = 2,
    argument_spacer = 3,
    argument_end = 4,
};
