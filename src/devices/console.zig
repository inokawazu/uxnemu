const std = @import("std");
const uxn = @import("uxn");
const T = @This();

inIo: *std.Io.Reader,
outIo: *std.Io.Writer,
errIo: *std.Io.Writer,
args: [][]u8,
argi: usize,
argi_j: usize,
addr_offest: u8 = 0x10,

const DeviceAddress = enum(u8) {
    vector = 0x00,
    read = 0x02,
    console_type = 0x07,
    write = 0x08,
    console_error = 0x09,
    addr = 0x0c,
    mode = 0x0e,
    exec = 0x0f,
    _,
};

const ConsoleInput = struct { c: u8, t: ConsoleInputType };

// no-queue(0), stdin(1), argument(2), argument-spacer(3), argument-end(4)
const ConsoleInputType = enum(u4) {
    no_queue = 0,
    stdin = 1,
    argument = 2,
    argument_spacer = 3,
    argument_end = 4,
};

pub fn devAddr(self: *Self, da: DeviceAddress) u8 {
    return self.addr_offest +% @intFromEnum(da);
}

pub fn vector(self: * Self, vm: *uxn.VM) u16 {
    const vector_addr = self.devAddr(.vector);
    return vm.zp_fetch(vector_addr, 1);
}

const Self = @This();

pub fn init(inIo: *std.Io.Reader, outIo: *std.Io.Writer, errIo: *std.Io.Writer, args: [][]u8) Self {
    const argi = 0;
    const argii = 0;

    return .{
        .inIo = inIo,
        .outIo = outIo,
        .errIo = errIo,
        .args = args,
        .argi = argi,
        .argi_j = argii,
    };
}

const reboot = boot;
pub fn boot(self: *Self, vm: *uxn.VM) void {
    for (0x10..0x20) |i| vm.ram[i] = 0;

    const input_type = if (!self.end_args())
        ConsoleInputType.argument
    else
        ConsoleInputType.no_queue;

    vm.zp_store(@intFromEnum(input_type), self.devAddr(.console_type), 0);
}

pub fn dei(_: *Self, vm: *uxn.VM, dev: u8, s: u1) u16 {
    return vm.zp_fetch(dev, s);
}

pub fn deo(self: *Self, vm: *uxn.VM, dev: u8, value: u16, s: u1) void {
    const device_enum: DeviceAddress = @enumFromInt(dev -% self.addr_offest); 

    vm.zp_store(value, dev, s);
    switch (device_enum) {
        .write => {
            const output = [_]u8{@truncate(value)};
            self.outIo.writeAll(&output) catch
                return std.debug.print("Failed to write to stdout\n", .{});
            self.outIo.flush() catch
                return std.debug.print("Failed to write to flush\n", .{});
            },
            .console_error => {
                const output = [_]u8{@truncate(value)};
                self.errIo.writeAll(&output) catch
                    return std.debug.print("Failed to write to stderr\n", .{});

                self.errIo.flush() catch
                    return std.debug.print("Failed to write to flush\n", .{});
                },
                else => {},
                _ => {},
    }
}

fn end_args(self: *const Self) bool {
    return self.argi >= self.args.len;
}

fn end_inIo(self: *const Self) bool {
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
    vm.zp_store(input.c, self.devAddr(.read), 0);
    vm.zp_store(@intFromEnum(input.t), self.devAddr(.console_type), 0);
}
