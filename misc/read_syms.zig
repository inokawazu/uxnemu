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
    const stat = try std.Io.File.stdin().stat(io);
    var buffer = try gpa.alloc(u8, stat.size);
    defer gpa.free(buffer);
    
    const readn = try std.Io.File.stdin().readPositionalAll(io, buffer, 0);
    if (readn < stat.size) {
        return error.ReadLessThanBuffer;
    }

    var symbols = try std.ArrayList(Symbol).initCapacity(gpa, 64);
    defer symbols.deinit(gpa);

    

    var pos: usize = 0;
    while ( pos + 2 <= buffer.len ) {
        const memory_bytes = buffer[pos..pos+2];
        const memory: u16 = ( @as(u16, memory_bytes[0]) << 4 ) | @as(u16, memory_bytes[1]);
        pos += 2;
        var end_symbol_pos = pos;
        while (end_symbol_pos < buffer.len and buffer[end_symbol_pos] != 0x00) { 
            end_symbol_pos += 1; 
        }
        const symbol = buffer[pos..end_symbol_pos+1];
        pos = end_symbol_pos+1;
        
        // std.fmt.Alt(comptime Data: type, comptime formatFn: fn (Data, *Writer) error{WriteFailed}!void)
        try symbols.append(gpa, .{ .memory = memory, .symbol = symbol });
    }

    std.mem.sort(Symbol, symbols.items, false, Symbol.compare);

    for (symbols.items) |symbol| {
        std.debug.print("0x{X:0>4} : {s}\n", .{symbol.memory, symbol.symbol});
    }
}
