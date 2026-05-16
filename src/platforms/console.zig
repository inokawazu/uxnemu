const std = @import("std");
const uxn = @import("uxn");
const Console = @import("devices").Console;
const print = @import("std").debug.print;


const UXNCLIError= error {
    MissingROM,
};


pub fn main(init: std.process.Init) !void {

    const io = init.io;

    const args = try init.minimal.args.toSlice(init.arena.child_allocator);

    if (args.len < 2) {
        //add error
        std.log.err("usage uxncli <input.rom> [args...]\n", .{});
        return UXNCLIError.MissingROM;
    }


    const program = try std.Io.Dir.cwd()
        .readFileAlloc(io, args[1], init.gpa, .unlimited);
    defer init.gpa.free(program);
    
    var vm = try uxn.VM.init(init.gpa);
    defer vm.deinit(init.gpa);

    try vm.load_rom(program);

    const uxn_args = try convertToMutableSlices(init.gpa, args[2..]);
    defer {
        for (uxn_args) |slice| init.gpa.free(slice);
        init.gpa.free(uxn_args);
    }

    const stdin_buffer = try init.gpa.alloc(u8, 0x100);
    var stdin = std.Io.File.stdin().reader(io, stdin_buffer);
    defer init.gpa.free(stdin_buffer);

    const stdout_buffer = try init.gpa.alloc(u8, 0x100);
    var stdout = std.Io.File.stdout().writer(io, stdout_buffer);
    defer init.gpa.free(stdout_buffer);

    const stderr_buffer = try init.gpa.alloc(u8, 0x100);
    var stderr = std.Io.File.stderr().writer(io, stderr_buffer);
    defer init.gpa.free(stderr_buffer);

    var console: Console = Console.init(
        &stdin.interface,
        &stdout.interface,
        &stderr.interface,
        uxn_args
    );


    const dev = uxn.Device.init(&console);

    // Reset Vector
    console.boot(&vm);
    vm.eval(uxn.RESET_VECTOR, dev);

    // Console Vector
    while (!console.end_args() or vm.ram[0x0f] == 0) {
        console.read_input(&vm);
        // print("{d} - {d}\n", .{vm.ram[Console.READ], vm.ram[Console.TYPE]});
        const console_vector_addr = vm.fetch(Console.VECTOR, 1);
        vm.eval(console_vector_addr, dev);
    } 

    std.process.exit(vm.ram[0x0f] & 0x7f);

    // console.read_input(&vm);
    // const console_vector_addr = vm.fetch(Console.VECTOR, 1);
    // vm.eval(console_vector_addr, dev);

    // testing BEGIN
    // while (!console.end_args()) {
    //     const out = console.update_input();
    //     // (comptime fmt: []const u8, args: anytype)
    //     if ( std.ascii.isPrint(out.c) )
    //     print("from {} Arg from Console: {c} {any}\n", .{console.argi, out.c, out.t})
    //     else 
    //     print("from {} Arg from Console: 0x{X:0>2} {any}\n", .{console.argi, out.c, out.t});
    // } 

    // if (console.end_inIo()) {
    //     print("There is no stdin...\n", .{});
    // }

    // while (!console.end_inIo()) {
    //     // print("has args\n", .{});
    //     const out = console.update_input();
    //     // (comptime fmt: []const u8, args: anytype)
    //     if ( std.ascii.isPrint(out.c) )
    //     print("Arg from stdin: {c} {any}\n", .{out.c, out.t})
    //     else 
    //     print("Arg from stdin: 0x{X:0>2} {any}\n", .{out.c, out.t});
    // } 

    // const lastOut = console.update_input();
    // print("This should be the no-queue: 0x{X:0>2} {any}\n", .{lastOut.c, lastOut.t});
    // testing END
}



fn convertToMutableSlices(allocator: std.mem.Allocator, input: []const [:0]const u8) ![][]u8 {
    const result = try allocator.alloc([]u8, input.len);
    errdefer {
        allocator.free(result);
        // for (result) |slice| allocator.free(slice);
    }

    for (input, 0..) |src, i| {
        const dst = try allocator.alloc(u8, src.len);
        @memcpy(dst, src);
        result[i] = dst;
    }

    return result;
}
