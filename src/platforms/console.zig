const std = @import("std");
const uxn = @import("uxn");
const print = @import("std").debug.print;


const EOF: u8 = 0x04;

// console
// 10 vector   18      write
// 11 19 error
// 12 read 1a --
// 13 -- 1b --
// 14 -- 1c addr*
// 15 -- 1d
// 16 -- 1e mode
// 17 type 1f exec

fn console_dei(_: std.Io, cpu: *uxn.CPU, dev: u16, s: u1) u16 {
    const x = cpu.fetch(dev, s);
    return x;
}

fn console_deo(io: std.Io, cpu: *uxn.CPU, dev: u16, value: u16, s: u1) void {
    switch (dev) {
        0x18 => {
            const output = [_]u8{@truncate(value)};
            std.Io.File.stdout().writeStreamingAll(io, &output) 
                catch {print("Failed to write", .{});};
        },
        0x19 => {
            const output = [_]u8{@truncate(value)};
            std.Io.File.stderr().writeStreamingAll(io, &output) 
                catch {print("Failed to write", .{});};
        },
        else => {
            cpu.store(value, dev, s);
        },
    }
}


pub fn main(init: std.process.Init) !void {
    const io = init.io;

    const args = try init.minimal.args.toSlice(init.arena.child_allocator);

    if (args.len < 2) {
        //add error
        print("no args found\n", .{});
        return;
    }

    // const arg1: []u8 = std.mem.span();
    const file = try std.Io.Dir.cwd().openFile(io, args[1], .{});

    var program = [_]u8{0} ** 0xff00;

    // const nread = try file.read(&program);
    const nread = try file.readPositionalAll(io, &program, 0);

    var cpu = uxn.CPU.init();


    for (cpu.ram) |b| {
        if (b != 0) break;
    } else {
        // print("The initial ram is zeroed.\n", .{});
    }

    cpu.load_rom(program[0..nread]);

    for (cpu.ram[0..0xFF]) |b| {
        if (b != 0) break;
    } else {
        // print("The initial devices are zeroed.\n", .{});
    }



    // INIT

    const ConsoleInput = struct {c: u8, t: u8};
    var argi: usize = 2;
    var argi_j: usize = 0;
    var stdin_end = false;
    const stdin_buffer = try init.gpa.alloc(u8, 265);
    defer init.gpa.free(stdin_buffer);

    var stdin = std.Io.File.stdin().reader(io, stdin_buffer);

    _ = stdin.interface.peek(1) catch { stdin_end = true; };
    
    if (args.len > 2) {
        // print("there are args!\n", .{});
        cpu.store( 2, 0x17, 0);
    } else if (!stdin_end) {
        cpu.store( 1, 0x17, 0);
    }

    //  Reset vector.
    cpu.eval(io, console_dei, console_deo);
    while (cpu.fetch(0x0f, 0) == 0) {

        var console_input: ConsoleInput =  undefined;
        if (argi < args.len) {
            if (argi_j < args[argi].len) {
                console_input.c = args[argi][argi_j];
                console_input.t = 2;
                argi_j += 1;
            } else {
                argi += 1;
                console_input.c = '\n';
                console_input.t = if (argi == args.len) 4 else 3;
                argi_j = 0;
            }
        } else if (!stdin_end) {
            var output = [_]u8{0};
            stdin.interface.readSliceAll(&output) catch {
                output[0] = EOF;
            };

            console_input.c = output[0];
            console_input.t = if (output[0] == EOF) 4 else 1;
        } else {
            console_input.c = EOF;
            console_input.t = 0;
        }

        cpu.store(console_input.c, 0x12, 0);
        cpu.store(console_input.t, 0x17, 0);

        if (cpu.fetch(0x10, 0) != 0) {
            cpu.pc = cpu.fetch(0x10, 1);
            cpu.eval(io, console_dei, console_deo);
        } else {
            break;
        }

    }
}

