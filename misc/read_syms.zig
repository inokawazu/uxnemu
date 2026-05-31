const std = @import("std");

const Symbol = struct {
    memory: u16,
    symbol: []u8,

    fn compare (_: bool, s1: Symbol, s2: Symbol) bool {
        return s1.memory < s2.memory;
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    // const stat = try std.Io.File.stdin().stat(io);
    // var buffer = try gpa.alloc(u8, stat.size);
    // defer gpa.free(buffer);


    var stdin_buffer: [0x100]u8 = undefined;
    var reader = std.Io.File.stdin().reader(io, &stdin_buffer);
    const data = try reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(data);

    var i: usize = 0;
    while (i < data.len) {
        const size = std.mem.readVarInt(u16, data[i..i+2], .native);
        i += 2;

        const j = std.mem.findScalarPos(u8, data, i, 0) 
            orelse break;
        std.debug.print("0x{x:0>4}: '{s}'\n", .{size, data[i..j]});
        i = j + 1;
    }
}
