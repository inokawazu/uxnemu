const std = @import("std");
const raylib = @import("raylib");
// const uxn = @import("uxn");


pub fn main() !void {
    const screen_size = 600;
    raylib.InitWindow(screen_size, screen_size, "Hello from zig");
    raylib.SetTargetFPS(60);

    // const earth_green:raylib.Color = .{.r = 24, .g = 94, .b = 63, .a = 0};
    const earth_green:raylib.Color = .{ .r = 22, .g = 85, .b = 57, .a = 0 };

    var box_speed: raylib.Vector2 = .{.x = 0, .y = 0};
    var pos : raylib.Vector2 = .{.x = 300, .y = 300};

    const box_size: i32 = 50;
    const accel: f32= 1;

    while (!raylib.WindowShouldClose()) {

        if (raylib.GetKeyPressed() == raylib.KEY_ESCAPE) {
            raylib.CloseWindow();
        }

        if (raylib.IsKeyDown(raylib.KEY_S) or raylib.IsKeyDown(raylib.KEY_DOWN)) {
            box_speed.y += accel;
        }
        if (raylib.IsKeyDown(raylib.KEY_W) or raylib.IsKeyDown(raylib.KEY_UP)) {
            box_speed.y -= accel;
        }
        if (raylib.IsKeyDown(raylib.KEY_A) or raylib.IsKeyDown(raylib.KEY_LEFT)) {
            box_speed.x -= accel;
        }
        if (raylib.IsKeyDown(raylib.KEY_D) or raylib.IsKeyDown(raylib.KEY_RIGHT)) {
            box_speed.x += accel;
        }

        pos.x += box_speed.x;
        pos.y += box_speed.y;

        box_speed.x *= 0.8;
        box_speed.y *= 0.8;

        // std.debug.print("box_position = {}\n", .{box_position});
        // std.debug.print("mod = {}\n", .{@mod(box_position.x, screen_size)});

        pos.x = @mod(pos.x, screen_size);
        pos.y = @mod(pos.y, screen_size);

        // raylib.DrawRectangleV(position: struct_Vector2, size: struct_Vector2, color: struct_Color)
        raylib.BeginDrawing();
        raylib.ClearBackground(earth_green);

        raylib.DrawFPS(10, 10);

        raylib.DrawRectangleV(pos, .{.x = box_size, .y = box_size},  raylib.PINK);
        raylib.DrawRectangleV(.{ .x = pos.x + screen_size, .y =  pos.y}, .{.x = box_size, .y = box_size},  raylib.PINK);
        raylib.DrawRectangleV(.{ .x = pos.x - screen_size, .y =  pos.y}, .{.x = box_size, .y = box_size},  raylib.PINK);
        raylib.DrawRectangleV(.{ .x = pos.x, .y =  pos.y + screen_size}, .{.x = box_size, .y = box_size},  raylib.PINK);
        raylib.DrawRectangleV(.{ .x = pos.x, .y =  pos.y - screen_size}, .{.x = box_size, .y = box_size},  raylib.PINK);

        raylib.DrawRectangleV(.{ .x = pos.x + screen_size, .y =  pos.y + screen_size}, .{.x = box_size, .y = box_size},  raylib.PINK);
        raylib.DrawRectangleV(.{ .x = pos.x - screen_size, .y =  pos.y - screen_size}, .{.x = box_size, .y = box_size},  raylib.PINK);
        raylib.DrawRectangleV(.{ .x = pos.x - screen_size, .y =  pos.y + screen_size}, .{.x = box_size, .y = box_size},  raylib.PINK);
        raylib.DrawRectangleV(.{ .x = pos.x + screen_size, .y =  pos.y - screen_size}, .{.x = box_size, .y = box_size},  raylib.PINK);

        raylib.DrawText("This is some text.", 200, 300, 24, raylib.BLUE);

        raylib.EndDrawing();

    }
}

