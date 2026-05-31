const std = @import("std");
const uxn = @import("uxn");

debug_writer: *std.Io.Writer,

const Self = @This();

// 00 Unused*    08 red*
// 01            09
// 02 expansion* 0a green*
// 03            0b
// 04 wst        0c blue*
// 05 rst        0d
// 06 metadata*  0e debug
// 07            0f state

pub const DeviceAddress = enum(u8) {
    unused = 0x00,
    unused2 = 0x01,
    expansion = 0x02,
    expansion2 = 0x03,
    wst = 0x04,
    rst = 0x05,
    metadata = 0x06,
    metadata2 = 0x07,
    red = 0x08,
    red2 = 0x09,
    green = 0x0a,
    green2 = 0x0b,
    blue = 0x0c,
    blue2 = 0x0d,
    debug = 0x0e,
    state = 0x0f,
};

pub fn state(vm: *uxn.VM) u8 {
    return @truncate(vm.fetch(@intFromEnum(DeviceAddress.state), 0));
}

pub fn dei(_: *Self, vm: *uxn.VM, dev: u16, s: u1) u16 {
    const dev_enum: DeviceAddress = @enumFromInt(dev);
    switch (dev_enum) {
        .wst => return vm.ptr[0],
        .rst => return vm.ptr[1],
        else => return vm.fetch(dev, s),
    }
}

pub fn deo(self: *const Self, vm: *uxn.VM, dev: u16, value: u16, s: u1) void {
    const dev_enum: DeviceAddress = @enumFromInt(dev);
    switch (dev_enum) {
        .wst => vm.ptr[0] = @truncate(value),
        .rst => vm.ptr[1] = @truncate(value),
        .expansion => expansion_deo(vm, value),
        .debug => if (value != 0) debug_deo(self, vm),
        else => vm.store(value, dev, s),
    }
}

fn expansion_deo(_: *uxn.VM, _: u16) void {
    @panic("TODO: expansion_deo");
    // TODO
}

fn debug_deo(self: *const Self, vm: *uxn.VM) void {
    const rs = [_]usize{ 0, 1 };
    for (rs) |r| {
        var i: isize = @max(vm.ptr[r], 7);
        if (r == 0) {
            self.debug_writer.print("WST ", .{}) catch {};
        } else {
            self.debug_writer.print("RST ", .{}) catch {};
        }

        while (i >= vm.ptr[r]) : (i -= 1) {
            self.debug_writer.print("00", .{}) catch {};
            if (i == vm.ptr[r]) {
                self.debug_writer.print("|", .{}) catch {};
            } else {
                self.debug_writer.print(" ", .{}) catch {};
            }
        }

        while (i >= 0) : (i -= 1) {
            const s_value = vm.stk[r][@intCast(i)];
            self.debug_writer.print("{x:0>2} ", .{s_value}) catch {};
        }
        self.debug_writer.print("<\n", .{}) catch {};
    }
}

test "testing dei/deo" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    const buffer = try gpa.alloc(u8, 0x100);
    defer gpa.free(buffer);
    var stderr = std.Io.File.stderr().writer(io, buffer);
    var dev: Self = .{ .debug_writer = &stderr.interface };
    var vm = try uxn.VM.init(gpa);
    defer vm.deinit(gpa);

    dev.deo(&vm, @intFromEnum(DeviceAddress.wst), 0xAF, 0);
    try std.testing.expectEqual(0xAF, vm.ptr[0]);
    const wst_via_dei = dev.dei(&vm, @intFromEnum(DeviceAddress.wst), 0);
    try std.testing.expectEqual(0xAF, wst_via_dei);

    dev.deo(&vm, @intFromEnum(DeviceAddress.rst), 0x30, 0);
    try std.testing.expectEqual(0xAF, vm.ptr[0]);
    try std.testing.expectEqual(0x30, vm.ptr[1]);
    const rst_via_dei = dev.dei(&vm, @intFromEnum(DeviceAddress.rst), 0);
    try std.testing.expectEqual(0x30, rst_via_dei);

    dev.deo(&vm, @intFromEnum(DeviceAddress.wst), 0x00, 0);
    dev.deo(&vm, @intFromEnum(DeviceAddress.rst), 0x00, 0);

    try std.testing.expectEqual(0x00, vm.ptr[0]);
    try std.testing.expectEqual(0x00, vm.ptr[1]);
}

test "debug print" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    const buffer = try gpa.alloc(u8, 0x100);
    defer gpa.free(buffer);
    var stderr = std.Io.File.stderr().writer(io, buffer);
    var dev: Self = .{ .debug_writer = &stderr.interface };
    var vm = try uxn.VM.init(gpa);
    defer vm.deinit(gpa);

    for (1..4) |i| {
        vm.push(@truncate(i), 0, 0);
    }

    for (4..6) |i| {
        vm.push(@truncate(i), 1, 0);
    }

    dev.debug_deo(&vm);
    try std.testing.expectStringStartsWith(buffer, "WST 00 00 00 00 00|03 02 01 <\nRST 00 00 00 00 00 00|05 04 <\n");
}
