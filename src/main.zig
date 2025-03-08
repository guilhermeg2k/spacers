const std = @import("std");
const ray = @import("raylib.zig");

pub fn main() !void {
    const width = 800;
    const height = 600;

    ray.SetConfigFlags(ray.FLAG_MSAA_4X_HINT | ray.FLAG_VSYNC_HINT);
    ray.InitWindow(width, height, "RayLib test");
    defer ray.CloseWindow();

    // var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 8 }){};
    // const allocator = gpa.allocator();
    // defer {
    //     switch (gpa.deinit()) {
    //         .leak => @panic("leaked memory"),
    //         else => {},
    //     }
    // }

    var x: f32 = 400;
    var y: f32 = 300;
    const speed = 3.0;
    // const ph = 40;

    while (!ray.WindowShouldClose()) {
        if (ray.IsKeyDown(ray.KEY_W)) y -= 1 * speed;
        if (ray.IsKeyDown(ray.KEY_S)) y += 1 * speed;
        if (ray.IsKeyDown(ray.KEY_A)) x -= 1 * speed;
        if (ray.IsKeyDown(ray.KEY_D)) x += 1 * speed;

        {
            ray.BeginDrawing();
            defer ray.EndDrawing();

            ray.ClearBackground(ray.BLACK);

            ray.DrawTriangle(.{ .x = x, .y = y }, .{ .x = x, .y = y + 20 }, .{ .x = x + 30, .y = y + 10 }, ray.RED);

            ray.DrawFPS(width - 100, 10);
        }
    }
}
