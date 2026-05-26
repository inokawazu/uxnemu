const std = @import("std");
const Assembler = @import("assembler.zig");

pub fn main(init: std.process.Init) !void {

    // const args = try init.minimal.args.toSlice(init.arena.allocator());
    var args = try init.minimal.args.iterateAllocator(init.arena.allocator());
    defer args.deinit();

    const exe_name = args.next() orelse return error.MissingProgramName;
    _ = exe_name;

    const source_file_path = args.next() orelse return error.MissingSource;

    const maybe_rom_file_path = args.next();
    // if (args.len > 2) args[2]
    // else null;

    var rom_file_path: [:0]const u8 = undefined;

    if (maybe_rom_file_path) |path| {
        rom_file_path = path;
    } else {
        rom_file_path = try replaceExt(init.gpa, source_file_path, ".rom");
    }
    defer if (maybe_rom_file_path == null) init.gpa.free(rom_file_path);

    const io = init.io;
    const source_file = try std.Io.Dir.cwd().openFile(io, source_file_path, .{});

    const file_size = (try source_file.stat(io)).size;
    const source_raw = try init.gpa.alloc(u8, file_size);
    defer init.gpa.free(source_raw);

    _ = try source_file.readPositionalAll(io, source_raw, 0);

    var assembler: Assembler = try .init(init.arena.allocator(), source_raw);
    try assembler.assemble();

    const outfile = try std.Io.Dir.cwd().createFile(io, rom_file_path, .{});
    defer outfile.close(io);
    try outfile.writePositionalAll(io, assembler.rom(), 0);

    std.debug.print("Assembled {s} in {d} bytes.\n", .{ std.fs.path.basename(rom_file_path), assembler.rom().len });
}

fn replaceExt(gpa: std.mem.Allocator, source_file_path: []const u8, replacement: []const u8) ![:0]u8 {
    const stem = std.fs.path.stem(source_file_path);
    return std.mem.concatWithSentinel(gpa, u8, &.{ stem, replacement }, 0);
}
