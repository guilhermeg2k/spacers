const std = @import("std");
const rl = @import("raylib.zig");
const math = @import("std").math;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const gpa_allocator = gpa.allocator();
var gameState = GameState.init(gpa_allocator);

const ScreenSize = .{ .x = 1280, .y = 720 };

const GameState = struct {
    const Self = @This();

    nextId: u64,
    objects: std.AutoHashMap(u64, *GameObject),
    objects_add_poll: std.ArrayList(*GameObject),
    objects_remove_poll: std.ArrayList(*GameObject),
    alloc: std.mem.Allocator,

    fn init(alloc: std.mem.Allocator) Self {
        return .{ .alloc = alloc, .nextId = 0, .objects = std.AutoHashMap(u64, *GameObject).init(alloc), .objects_add_poll = std.ArrayList(*GameObject).init(alloc), .objects_remove_poll = std.ArrayList(*GameObject).init(alloc) };
    }

    fn addObject(self: *Self, obj: *GameObject) !void {
        try self.objects_add_poll.append(obj);
    }

    fn removeObject(self: *Self, obj: *GameObject) !void {
        try self.objects_remove_poll.append(obj);
    }

    fn update(self: *Self) !void {
        std.log.warn("Object count = {}\n", .{self.objects.count()});
        var it = self.objects.iterator();
        while (it.next()) |object| {
            try object.value_ptr.*.update();
        }

        for (self.objects_add_poll.items) |o| {
            try self.objects.put(o.id, o);
        }

        for (self.objects_remove_poll.items) |o| {
            const object = self.objects.get(o.id);
            if (object) |obj| {
                _ = self.objects.remove(obj.id);
                obj.deinit();
            }
        }

        self.objects_add_poll.clearRetainingCapacity();
        self.objects_remove_poll.clearRetainingCapacity();
    }

    fn draw(self: *Self) !void {
        var it = self.objects.iterator();
        while (it.next()) |object| {
            try object.value_ptr.*.draw();
        }
    }

    fn deinit(self: *Self) void {
        var it = self.objects.iterator();
        while (it.next()) |object| {
            object.value_ptr.*.deinit();
        }

        self.objects.deinit();
        self.objects_add_poll.deinit();
        self.objects_remove_poll.deinit();
    }
};

const GameObject = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    id: u64,
    ptr: *anyopaque,
    updateFn: *const fn (ptr: *anyopaque) anyerror!void,
    drawFn: *const fn (ptr: *anyopaque) anyerror!void,
    deinitFn: *const fn (ptr: *anyopaque) void,

    fn init(
        alloc: std.mem.Allocator,
        ptr: *anyopaque,
        updateFn: *const fn (ptr: *anyopaque) anyerror!void,
        drawFn: *const fn (ptr: *anyopaque) anyerror!void,
        deinitFn: *const fn (ptr: *anyopaque) void,
    ) !*Self {
        const object = try alloc.create(GameObject);

        object.* = GameObject{
            .alloc = alloc,
            .id = gameState.nextId,
            .ptr = ptr,
            .updateFn = updateFn,
            .drawFn = drawFn,
            .deinitFn = deinitFn,
        };

        gameState.nextId += 1;

        return object;
    }

    fn update(self: *Self) !void {
        return self.updateFn(self.ptr);
    }

    fn draw(self: *Self) !void {
        return self.drawFn(self.ptr);
    }

    fn deinit(self: *Self) void {
        self.deinitFn(self.ptr);
        self.alloc.destroy(self);
    }
};

const Bullet = struct {
    const Self = @This();
    x: f32,
    y: f32,
    speed: f32,
    alloc: std.mem.Allocator,
    object: *GameObject,

    fn init(alloc: std.mem.Allocator, x: f32, y: f32) !*Bullet {
        const bullet = try alloc.create(Self);
        const object = try GameObject.init(alloc, bullet, update, draw, deinit);

        bullet.* = Self{
            .x = x,
            .y = y,
            .alloc = alloc,
            .speed = 1000.0,
            .object = object,
        };

        return bullet;
    }

    fn deinit(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.alloc.destroy(self);
    }

    fn draw(ptr: *anyopaque) !void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        rl.DrawRectangle(@intFromFloat(self.x), @intFromFloat(self.y), 10, 2, rl.RED);
    }

    fn update(ptr: *anyopaque) !void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        const delta_time = rl.GetFrameTime();
        self.x += delta_time * self.speed;

        if (self.x > ScreenSize.x) {
            try gameState.removeObject(self.object);
        }
    }
};

const Player = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    x: f32,
    y: f32,
    speed: f32,
    object: *GameObject,

    fn init(alloc: std.mem.Allocator) !*Player {
        const player = try alloc.create(Self);

        const object = try GameObject.init(alloc, player, update, draw, deinit);

        player.* = Self{ .alloc = alloc, .speed = 700.0, .x = ScreenSize.x / 2, .y = ScreenSize.y / 2, .object = object };

        return player;
    }

    fn deinit(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.alloc.destroy(self);
    }

    fn update(ptr: *anyopaque) !void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        try self.handleInput();
    }

    fn draw(ptr: *anyopaque) !void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        rl.DrawTriangle(.{ .x = self.x, .y = self.y }, .{ .x = self.x, .y = self.y + 20 }, .{ .x = self.x + 30, .y = self.y + 10 }, rl.RED);
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
            const bullet = try Bullet.init(self.alloc, self.x, self.y + 10);
            try gameState.addObject(bullet.object);
        }
    }
};

pub fn main() !void {
    defer {
        switch (gpa.deinit()) {
            .leak => @panic("leaked memory"),
            else => {},
        }
    }

    const player = try Player.init(gpa_allocator);
    try gameState.addObject(player.object);
    defer gameState.deinit();

    rl.SetConfigFlags(rl.FLAG_MSAA_4X_HINT | rl.FLAG_VSYNC_HINT);
    rl.InitWindow(ScreenSize.x, ScreenSize.y, "Spacers");
    defer rl.CloseWindow();

    while (!rl.WindowShouldClose()) {
        try gameState.update();
        {
            rl.BeginDrawing();
            defer rl.EndDrawing();

            try gameState.draw();
            rl.ClearBackground(rl.BLACK);
            rl.DrawFPS(ScreenSize.x - 100, 10);
        }
    }
}
