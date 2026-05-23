const std = @import("std");
const uxn = @import("uxn.zig");
const Assembler = @import("assembler.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const source_file =  try std.Io.Dir.cwd().openFile(io, "hello.tal", .{});

    const file_size = ( try source_file.stat(io) ).size;
    const source_raw = try init.gpa.alloc(u8, file_size);
    defer init.gpa.free(source_raw);

    _ = try source_file.readPositionalAll(io, source_raw, 0);
    std.debug.print("{s}\n", .{source_raw});


    // const failing = try init.gpa.alloc(u8, 0x100);
    // for (0..failing.len) |i| {failing[i] = @intCast(i);}
    // std.debug.print("{d}\n", .{failing[10]});

    var assembler: Assembler = try .init(init.arena.allocator(), source_raw);
    // defer assembler.deinit();
    try assembler.assemble();


    const outfile = try std.Io.Dir.cwd().createFile(
        io,
        "test_hello.rom",
        .{ });
    defer outfile.close(io);
    // const outfile = try std.Io.Dir.cwd().openFile(
    //     io,
    //     "test_hello.rom",
    //     .{ .mode = .write_only });
    try outfile.writePositionalAll(io, assembler.rom(), 0);

    // var lexer: Lexer = .{ .source = source_raw};
    // var tokens = try lexer.lex(init.gpa);
    // defer tokens.deinit(init.gpa);

    // for (tokens.items) |token| {
    //     std.debug.print("{any}\n", .{token});
    // }

}

