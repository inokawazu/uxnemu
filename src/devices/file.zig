const std = @import("std");
const uxn = @import("uxn");

const Self = @This();

// |a0 @File1/vector $2 &success $2 &stat $2 &delete $1 &append $1 &name $2 &length $2 &read $2 &write $2
// |b0 @File2/vector $2 &success $2 &stat $2 &delete $1 &append $1 &name $2 &length $2 &read $2 &write $2

mem_offset: u8 = 0xa0,
    io: std.Io,
    file: ?std.Io.File = null,
    // dir: ?std.Io.Dir = null,


    const DeviceAddress = enum(u8) {
        vector = 0x00,
        success = 0x02,
        stat = 0x04,
        delete = 0x06,
        append = 0x07,
        name = 0x08,
        length = 0x0a,
        read = 0x0c,
        write = 0x0e,
    };

pub fn devAddr(self: *Self, da: DeviceAddress) u8 {
    return @intFromEnum(da) + self.mem_offset;
}

pub fn dei(_: *Self, vm: *uxn.VM, dev: u8, s: u1) u16 {
    return vm.zp_fetch(dev, s);
}

pub fn deo(self: *Self, vm: *uxn.VM, dev: u8, value: u16, s: u1) void {
    vm.zp_store(value, dev, s);

    const device_enum: DeviceAddress = @enumFromInt(dev - self.mem_offset);
    std.debug.print("Operation: '{any}'\n", .{device_enum});
    if (device_enum == .name)
        std.debug.print("Filename: '{s}'\n", .{self.getFileName(vm)});
    if (device_enum == .length)
        std.debug.print("Length: '{d}'\n", .{self.getLength(vm)});

    if ( dev == self.devAddr(.name) ) {
        if (self.file) |file| {
            file.close(self.io);
            self.file = null;
        }
    } else if (dev == self.devAddr(.read)) {
        const cwd = std.Io.Dir.cwd();
        const sub_path = getStr(
            vm, 
            vm.fetch(self.devAddr(.name), 1));

        const stat = 
            cwd.statFile( self.io, sub_path, .{}) catch return;

        switch (stat.kind) {
            .file => {
                if (self.file == null)
                    self.file = cwd.openFile(self.io, sub_path, .{ .mode = .read_only })
                        catch return;

                const rptr: usize = @intCast(vm.fetch(self.devAddr(.read), 1));
                const rptr_end: usize = @min(rptr + self.getLength(vm)+1, vm.ram.len);
                const buffer = vm.ram[rptr..rptr_end];

                const nread = self.file.?.readStreaming(self.io, &.{buffer}) catch 0;
                // var file_buffer: [4096]u8 = undefined;
                // var fr = self.file.?.reader(self.io, &file_buffer);
                // const nread = fr.interface.(buffer) catch 0;

                vm.store(@intCast(nread), self.devAddr(.success), 1);
            },
            .directory => {
                const dir = cwd.openDir(self.io, sub_path, .{ .iterate = true }) catch return;
                defer dir.close(self.io);

                var iter = dir.iterate();
                var rptr: usize = @intCast(vm.fetch(self.devAddr(.read), 1));
                while (iter.next(self.io) catch return) |x|
                    rptr += self.writeStatInfo(vm, dir, x.name, @truncate(rptr)) catch return;
                },
                else => {}
        }
    } else if (dev == self.devAddr(.stat)) {
        const cwd = std.Io.Dir.cwd();
        const stat_addr = self.devAddr(.stat);
        _ = self.writeStatInfo(
            vm, cwd, 
            self.getFileName(vm), 
            stat_addr) catch return;
    } else if (dev == self.devAddr(.write)) {
        const is_append = vm.fetch(self.devAddr(.append), 0) != 0x00;
        const sub_path = self.getFileName(vm);

        if (self.file == null)
            self.file = std.Io.Dir.cwd()
                .createFile(
                    self.io,
                    sub_path,
                    .{ .truncate = !is_append, .read = false })
                catch { 
                    std.debug.print("write: failed to make writable file.\n", .{});
                    return;
                };

        var wbuffer = std.mem.zeroes([64]u8);
        var writer = self.file.?.writer(self.io, &wbuffer);

        const wptr: usize = vm.fetch(self.devAddr(.write), 1);
        const wptr_end: usize = @min(wptr+self.getLength(vm)+1, vm.ram.len);

        const towrite = vm.ram[wptr..wptr_end];
        
        std.debug.print("I am writing {s} to {s}\n", .{towrite, self.getFileName(vm)});

        writer.interface.writeAll(towrite) 
            catch {
                std.debug.print("write: failed to write data to file buffer\n", .{});
                return;
            };

        vm.store(@truncate(towrite.len), self.devAddr(.success), 1);
    } else if (dev == self.devAddr(.delete)) {
        if (self.file != null)
            self.file.?.close(self.io);

        const sub_path = self.getFileName(vm);
        std.Io.Dir.cwd().deleteFile(self.io, sub_path) catch {
            std.debug.print("write: failed to delete file\n", .{});
            vm.store(0, self.devAddr(.success), 1);
        };
        vm.store(1, self.devAddr(.success), 1);
    }
}

fn writeStatInfo(self: *Self, vm: *uxn.VM, dir: std.Io.Dir, sub_path: []const u8, rptr: usize) !usize {
    var info_str: [4]u8 = undefined;
    const maybe_stat: ?std.Io.Dir.Stat = dir.statFile(self.io, sub_path, .{}) catch null;
    if (maybe_stat) |stat| {
        switch (stat.kind) {
            .file => {
                if (stat.size > 64000) {
                    @memmove(&info_str, "????");
                } else {
                    _ = try std.fmt.bufPrint(&info_str, "{x:0>4}", .{stat.size});
                }
            },
            .directory => @memmove(&info_str, "----"),
            else => @memmove(&info_str, "!!!!"),
        }
    } else {
        @memmove(&info_str, "!!!!");
    }

    const rptr_end: usize = @min(
        rptr + self.getLength(vm) + 1,
        rptr + info_str.len + sub_path.len + 2 + 1,
        vm.ram.len);
    const buffer = vm.ram[rptr..rptr_end];
    const written = try std.fmt.bufPrint(buffer, "{s} {s}\n", .{info_str, sub_path});
    return written.len;
}

fn getFileName(self: *Self, vm: *uxn.VM) []u8 {
    return getStr( vm, vm.fetch(self.devAddr(.name), 1));
}

fn getStr(vm: *uxn.VM, addr: u16) []u8 {
    const end_addr = std.mem.findScalarPos(
        u8, vm.ram, 
        @intCast(addr), 0x00)
        orelse vm.ram.len;
    return vm.ram[addr..end_addr];
}

fn getLength(self: *Self, vm: *uxn.VM) usize {
    return vm.fetch(self.devAddr(.length), 1);
}
