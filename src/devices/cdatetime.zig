const std = @import("std");
const uxn = @import("uxn");
const epoch = @import("std").time.epoch;
const ctime = @import("ctime");
const Self = @This();

addr_offest: u8 = 0xc0,
datetime_t: ?*const ctime.tm = null,

const datetime_zt: ctime.tm = .{};

const DeviceAddress = enum(u8) {
    year = 0x00,
    month = 0x02,
    day = 0x03,
    hour = 0x04,
    minute = 0x05,
    second = 0x06,
    dotw = 0x07,
    doty = 0x08,
    isdst = 0x0a,
    _,
};

pub fn devAddr(self: *Self, da: DeviceAddress) u8 {
    return self.addr_offest +% @intFromEnum(da);
}

fn setAddr(self: *Self, vm: *uxn.VM, x: u16, da: DeviceAddress) void {
    const s: u1 = switch (da) {
        .year, .doty => 1,
        else => 0,
    };
    const dev_addr = self.devAddr(da);
    return vm.zp_store(x, dev_addr, s);
}


// TODO: make the time configurable
pub fn dei(self: *Self, vm: *uxn.VM, dev: u8, s: u1) u16 {
    const datetime_seconds = ctime.time(null);
    self.datetime_t = ctime.localtime(&datetime_seconds);
    if (self.datetime_t == null)
        self.datetime_t = &datetime_zt;

    const dtt = self.datetime_t.?;
    const year: u16 = @intCast(dtt.tm_year + 1900);
    const doty: u16 = @intCast(dtt.tm_yday);
    const month: u8 = @intCast(dtt.tm_mon);
    const day: u8 = @intCast(dtt.tm_mday);
    const hour: u8 = @intCast(dtt.tm_hour);
    const minute: u8 = @intCast(dtt.tm_min);
    const second: u8 = @intCast(dtt.tm_sec);
    const dotw: u8 = @intCast(dtt.tm_wday);
    const isdst: u8 = @intCast(dtt.tm_isdst);

    self.setAddr(vm, year, .year);
    self.setAddr(vm, month, .month);
    self.setAddr(vm, day, .day);
    self.setAddr(vm, hour, .hour);
    self.setAddr(vm, minute, .minute);
    self.setAddr(vm, second, .second);
    self.setAddr(vm, dotw, .dotw);
    self.setAddr(vm, doty, .doty);
    self.setAddr(vm, isdst, .isdst);

    return vm.zp_fetch(dev, s);
}

pub fn deo(_: *Self, vm: *uxn.VM, dev: u8, value: u16, s: u1) void {
    vm.zp_store(value, dev, s);
}
