const std = @import("std");
const uxn = @import("uxnemu");
const print = @import("std").debug.print;


// console
// 10 vector   18      write
// 11 19 error
// 12 read 1a --
// 13 -- 1b --
// 14 -- 1c addr*
// 15 -- 1d
// 16 -- 1e mode
// 17 type 1f exec

fn console_dei(cpu: *uxn.CPU, dev: u16, s: u1) u16 {
    const x = cpu.fetch(dev, s);
    // print("Getting input DEI [0x{x:0>2}] => 0x{x:0>2}...\n", .{dev, x});
    return x;
}

fn console_deo(cpu: *uxn.CPU, dev: u16, value: u16, s: u1) void {
    // print("Sending output DEO 0x{x:0>2} => [0x{x:0>2}]\n", .{value, dev});
    switch (dev) {
    // static void console_deo_stdout(void) { fputc(dev[0x18], stdout), fflush(stdout); }
        0x18 => {
            // print("printing to std ({})\n", .{cpu.ram[dev]});
            var stdout = std.fs.File.stdout();
            var out = [1]u8{@intCast(value)};
            _ = stdout.write(&out) catch {print("Failed to write", .{});};
        },
    // static void console_deo_stderr(void) { fputc(dev[0x19], stderr), fflush(stderr); }
        0x19 => {
            const stderr = std.fs.File.stderr();
            var out = [1]u8{@intCast(value)};
            _ = stderr.write(&out) catch {print("Failed to write", .{});};
        },
    // static void console_deo_hb(void) { fprintf(stderr, "%02x", dev[0x1a]); }
    // static void console_deo_lb(void) { fprintf(stderr, "%02x", dev[0x1b]); }
    // static void console_deo_vector(void) { console_vector = peek2(&dev[0x10]); }
        else => {
            cpu.store(value, dev, s);
        },
    }
}


pub fn main() !void {
    const args = std.os.argv;

    if (args.len < 2) {
        //add error
        print("no args found", .{});
        return;
    }

    const arg1: []u8 = std.mem.span(args[1]);
    const file = try std.fs.cwd().openFile(arg1, .{});

    var program = [_]u8{0} ** 0xff00;

    const nread = try file.read(&program);

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
    if (args.len > 2) {
        // print("There are args for uxn\n", .{});
        cpu.store( 1, 0x17, 0);
    }

    var feeder: ConsoleInputFeeder = .{.args = args};
    cpu.eval(console_dei, console_deo);

    while (cpu.fetch(0x0f, 0) == 0) {

        const console_input = feeder.next_input();
            // print("getting input from keyboard {}\n", .{console_input});
            cpu.store(console_input.c, 0x12, 0);
            cpu.store(console_input.t, 0x17, 0);

        if (cpu.fetch(0x10, 0) != 0 and console_input.t != 0) {
            cpu.pc = cpu.fetch(0x10, 1);
            cpu.eval(console_dei, console_deo);
        } else {
            break;
        }

    }
}

    
const ConsoleInput = struct {c: u8, t: u8};

const ConsoleInputFeeder= struct {
    args: [][*:0]u8,
    // stdin: std.fs.File = std.fs.File.stdin(),
    // stdin_buffer: [1]u8 = [1]u8{0},
    current_arg: usize = 2,
    arg_i: usize = 0,
    args_end: bool = false,
    stdin_end: bool = false,

    const EOF: u8 = 0x04;
    pub fn init(args: [][*:0]u8) ConsoleInputFeeder {
        return .{
            .args = args,
            .args_end = args.len > 2,
        };
    }

    fn next_input(self: *ConsoleInputFeeder) ConsoleInput {
        if (!self.args_end and self.current_arg < self.args.len) {
            const arg: []u8 = std.mem.span(self.args[self.current_arg]);
            if (self.arg_i < arg.len) {
                defer self.arg_i += 1;
                return .{.c = self.args[self.current_arg][self.arg_i], .t = 2};
            } else if (!self.args_end) {
                self.args_end = false;
                self.arg_i = 0;
                self.current_arg += 1;
                const t: u8 = if (self.current_arg == self.args.len) 4 else 3;
                return .{.c = '\n', .t = t};
            }
        }

        if (!self.stdin_end) {
            const stdin = std.fs.File.stdin();
            var buffer = [_]u8{};
            var reader  = stdin.readerStreaming(&buffer);
            var output = [_]u8{0};
            _ = reader.interface.readSliceAll(&output) catch { 
                self.stdin_end = true;
                return .{.c = '\n', .t = 4}; 
            };

            return .{.c = output[0], .t = if (output[0] == EOF) 0 else 1};
        }

        return .{.c = EOF, .t = 0};
    }
};
