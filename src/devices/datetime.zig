const std = @import("std");
const uxn = @import("uxn");
const epoch = @import("std").time.epoch;
const Self = @This();

// clock: std.Io.Clock,
io: std.Io,
addr_offest: u8 = 0xc0,

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
    const now_secs = std.Io.Clock.real.now(self.io).toSeconds();
    const ep_secs: epoch.EpochSeconds = .{.secs = @intCast(now_secs)};
    const ep_year_day = ep_secs.getEpochDay().calculateYearDay();
    const year: u16 = ep_year_day.year;
    const doty: u16 = ep_year_day.day;
    const ep_month_day = ep_year_day.calculateMonthDay();
    const month: u8 = ep_month_day.month.numeric() - 1;
    const day: u8 = ep_month_day.day_index + 1;
    const ep_day_secs = ep_secs.getDaySeconds();
    const hour: u8 = ep_day_secs.getHoursIntoDay();
    const minute: u8 = ep_day_secs.getMinutesIntoHour();
    const second: u8 = ep_day_secs.getSecondsIntoMinute();
    const dotw: u8 = getDotw(ep_secs);
    const isdst: u8 = @intFromBool(isDST(ep_secs));

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

// https://www.nist.gov/pml/time-and-frequency-division/popular-links/daylight-saving-time-dst
// begins at 2:00 a.m. on the second Sunday of March (at 2 a.m. the local time time skips ahead to 3 a.m. so there is one less hour in that day)
// ends at 2:00 a.m. on the first Sunday of November (at 2 a.m. the local time becomes 1 a.m. and that hour is repeated, so there is an extra hour in that day)
// TODO: current implementation is bast on US time (roughly).
// Should be taken from system or tz info...
fn isDST(ep_secs: epoch.EpochSeconds) bool {
    const ep_year_day = ep_secs.getEpochDay().calculateYearDay();

    const month_day = ep_year_day.calculateMonthDay();

    const dotw: u8 = getDotw(ep_secs);
    const first_dotw: u8 = @mod((dotw + 35) - month_day.day_index, 7);
    const first_sunday: u8 = if (first_dotw == 0) 0 else 7 - first_dotw;

    switch (month_day.month) {
        .jan, .feb, .dec => return false,
        .apr, .aug, .jul, .jun, .may, .oct, .sep => return true,
        .mar => return month_day.day_index >= first_sunday,
        .nov => return month_day.day_index < first_sunday,
    } 
}


fn getDotw(ep_secs: epoch.EpochSeconds) u8 {
    const ep_day = ep_secs.getEpochDay();
    return @intCast(@mod(ep_day.day + 4, 7));
}
