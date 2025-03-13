const std = @import("std");
const rl = @import("raylib.zig");
const math = @import("std").math;

var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 8 }){};
const gpa_allocator = gpa.allocator();

const ScreenSize = .{ .x = 1280, .y = 720 };

const Bullet = struct {
    const Self = @This();
    x: f32,
    y: f32,
    speed: f32,
    alloc: std.mem.Allocator,

    fn init(alloc: std.mem.Allocator, x: f32, y: f32) !*Self {
        const bullet = try alloc.create(Self);

        bullet.* = Self{
            .x = x,
            .y = y,
            .alloc = alloc,
            .speed = 1000.0,
        };

        return bullet;
    }

    fn draw(self: *const Self) void {
        rl.DrawRectangle(@intFromFloat(self.x), @intFromFloat(self.y), 10, 2, rl.RED);
    }

    fn update(self: *Self) void {
        const delta_time = rl.GetFrameTime();
        self.x += delta_time * self.speed;
    }
};

const Player = struct {
    const Self = @This();

    x: f32,
    y: f32,
    speed: f32,
    bullets: std.ArrayList(*Bullet),
    alloc: std.mem.Allocator,

    fn init(alloc: std.mem.Allocator) Self {
        return .{ .alloc = alloc, .speed = 700.0, .x = ScreenSize.x / 2, .y = ScreenSize.y / 2, .bullets = std.ArrayList(*Bullet).init(alloc) };
    }

    fn deinit(self: *Self) void {
        self.bullets.deinit();
    }

    fn handleInput(self: *Self) !void {
        const delta_time = rl.GetFrameTime();
        const is_moving_up = rl.IsKeyDown(rl.KEY_W);
        const is_moving_down = rl.IsKeyDown(rl.KEY_S);
        const is_moving_left = rl.IsKeyDown(rl.KEY_A);
        const is_moving_right = rl.IsKeyDown(rl.KEY_D);

        if (is_moving_up) self.y = @max(self.y - 1 * self.speed * delta_time, 0);
        if (is_moving_down) self.y = @min(self.y + 1 * self.speed * delta_time, ScreenSize.y - 20);
        if (is_moving_left) self.x = @max(self.x - 1 * self.speed * delta_time, 0);
        if (is_moving_right) self.x = @min(self.x + 1 * self.speed * delta_time, ScreenSize.x - 30);

        if (rl.IsKeyPressed(rl.KEY_SPACE)) {
            const bullet = try Bullet.init(self.alloc, self.x, self.y);
            try self.bullets.append(bullet);
        }
    }

    fn update(self: *Self) !void {
        try self.handleInput();
        for (self.bullets.items) |b| {
            b.update();
        }
    }

    fn draw(self: *Self) void {
        rl.DrawTriangle(.{ .x = self.x, .y = self.y }, .{ .x = self.x, .y = self.y + 20 }, .{ .x = self.x + 30, .y = self.y + 10 }, rl.RED);

        for (self.bullets.items) |b| {
            b.draw();
        }
    }
};

pub fn main() !void {
    var player = Player.init(gpa_allocator);
    defer player.deinit();
    rl.SetConfigFlags(rl.FLAG_MSAA_4X_HINT | rl.FLAG_VSYNC_HINT);
    rl.InitWindow(ScreenSize.x, ScreenSize.y, "Spacers");
    defer rl.CloseWindow();

    // defer {
    //     switch (gpa.deinit()) {
    //         .leak => @panic("leaked memory"),
    //         else => {},
    //     }
    // }

    while (!rl.WindowShouldClose()) {
        try player.update();
        {
            rl.BeginDrawing();
            defer rl.EndDrawing();
            rl.ClearBackground(rl.BLACK);
            player.draw();
            rl.DrawFPS(ScreenSize.x - 100, 10);
        }
    }
}
