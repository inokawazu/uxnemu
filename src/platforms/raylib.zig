const std = @import("std");
const raylib = @import("raylib");
const uxn = @import("uxn");

// gba 240 x 160
const WIDTH: u32 = 160 * 2;
const HEIGHT: u32 = 144 * 2;

// Devices addresses
const SYSTEM_R: u8 = 0x08;
const SYSTEM_G: u8 = 0x0a;
const SYSTEM_B: u8 = 0x0c;
const SYSTEM_WST: u8 = 0x04;
const SYSTEM_RST: u8 = 0x05;
const SYSTEM_STATE: u8 = 0x0f;

const SCREEN_VECTOR: u8 = 0x20;
const SCREEN_WIDTH: u8 = 0x22;
const SCREEN_HEIGHT: u8 = 0x24;
const SCREEN_AUTO: u8 = 0x26;
const SCREEN_X: u8 = 0x28;
const SCREEN_Y: u8 = 0x2a;
const SCREEN_ADDR: u8 = 0x2c;
const SCREEN_PIXEL: u8 = 0x2e;
const SCREEN_SPRITE: u8 = 0x2f;

const MOUSE_VECTOR: u8 = 0x90;
const MOUSE_X: u8 = 0x92;
const MOUSE_Y: u8 = 0x94;
const MOUSE_STATE: u8 = 0x96;
const MOUSE_SCROLLX: u8 = 0x9a;
const MOUSE_SCROLLY: u8 = 0x9c;

const CONTROLLER_VECTOR: u8 = 0x80;

const RESET_VECTOR: u16 = 0x100;

var system_colors: [4]raylib.struct_Color = .{
    raylib.BLACK, raylib.WHITE, raylib.BLUE, raylib.RED,
};

var threaded = std.Io.Threaded.init_single_threaded;
var io = threaded.io();

const Pixel = packed struct {
    color: u2,
    mode: u1,
    flip_x: u1,
    flip_y: u1,
    layer: u1,
    fill: u1,
    auto: u1,
};

fn ray_dei(cpu: *uxn.CPU, addr: u16, _: u1) u16 {
    switch (addr) {
        SYSTEM_RST => {
            return cpu.rp;
        },
        SYSTEM_WST => {
            return cpu.wp;
        },
        else => {
            std.debug.print("NOT IMPLEMENTED DEI (0x{X:0>4})\n", .{addr});
            @panic("TODO");
        },
    }
}

fn ray_deo(cpu: *uxn.CPU, addr: u16, value: u16, s: u1) void {
    switch (addr) {
        SYSTEM_RST => {
            cpu.rp = @truncate(value);
        },
        SYSTEM_WST => {
            cpu.wp = @truncate(value);
        },
        SYSTEM_R, SYSTEM_G, SYSTEM_B => {
            cpu.store(value, addr, s);
            const r = cpu.fetch(SYSTEM_R, 1);
            const g = cpu.fetch(SYSTEM_G, 1);
            const b = cpu.fetch(SYSTEM_B, 1);
            update_colors(r, g, b);
        },
        MOUSE_VECTOR, CONTROLLER_VECTOR => {
            cpu.store(value, addr, 1);
        },
        SCREEN_X, SCREEN_X + 1, SCREEN_Y, SCREEN_Y + 1, SCREEN_PIXEL, SCREEN_SPRITE, SCREEN_AUTO => {
            cpu.store(value, addr, s);
        },
        else => {
            std.debug.print("NOT IMPLEMENTED DEO (0x{X:0>4})\n", .{addr});
            @panic("TODO\n");
            // cpu.store(value, addr, s);
        },
    }
    return;
}

pub fn main(init: std.process.Init) !void {
    var screen_buffer = try init.gpa.alloc(u8, WIDTH * HEIGHT);
    defer init.gpa.free(screen_buffer);
    for (0..screen_buffer.len) |i| {
        screen_buffer[i] = 1;
    }

    var cpu = uxn.CPU.init();

    const args = try init.minimal.args.toSlice(init.gpa);
    defer init.gpa.free(args);

    const nargs = args.len;
    if (nargs < 2) {
        std.debug.print("Usage {s} <program.rom>\n", .{args[0]});
        std.process.exit(1);
    }

    const file_path = args[1];

    const program = try std.Io.Dir.cwd().readFileAlloc(io, file_path, init.gpa, .unlimited);
    defer init.gpa.free(program);

    cpu.load_rom(program);
    cpu.pc = RESET_VECTOR;
    cpu.eval(ray_dei, ray_deo);

    raylib.InitWindow(WIDTH, HEIGHT, "Raylib UXN");
    while (!raylib.WindowShouldClose()) {
        if (cpu.ram[SYSTEM_STATE] != 0) {
            raylib.CloseWindow();
        }

        if (raylib.IsKeyPressed(raylib.KEY_ESCAPE)) {
            raylib.CloseWindow();
        }

        raylib.BeginDrawing();

        for (0..HEIGHT) |yi| {
            for (0..WIDTH) |xi| {
                const color_index = screen_buffer[xi + WIDTH * yi];
                raylib.DrawPixel(@intCast(xi), @intCast(yi), system_colors[color_index]);
            }
        }

        raylib.EndDrawing();
    }
}

// TODO: test
fn update_colors(r: u16, g: u16, b: u16) void {
    // 0xABCD -> AAAA
    for (0..system_colors.len) |i| {
        system_colors[i].r = @truncate(r >> @truncate(system_colors.len - i - 1));
        system_colors[i].g = @truncate(g >> @truncate(system_colors.len - i - 1));
        system_colors[i].b = @truncate(b >> @truncate(system_colors.len - i - 1));
        system_colors[i].a = 0xFF;
    }
}
