// read_syms.zig <file.rom.sym>
// Lists out the symbols from a .sym file produced by drifblim


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

    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len < 2) {
        std.log.err("{s} <file.rom.sym>", .{args[0]});
        return error.MissingArgument;
    }

    const data = try std.Io.Dir.cwd().readFileAlloc(
        io, args[1], gpa, .unlimited
        );
    defer gpa.free(data);


    var stdout_buffer: [0x100]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &stdout_buffer);

    var i: usize = 0;
    while (i < data.len) {
        const size = std.mem.readVarInt(u16, data[i..i+2], .big);
        i += 2;

        const j = std.mem.findScalarPos(u8, data, i, 0) 
            orelse break;
        try writer.interface.print("0x{x:0>4}:{s}\n", .{size, data[i..j]});
        i = j + 1;
    }
    try writer.flush();
}
