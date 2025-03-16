const std = @import("std");
const rl = @import("raylib.zig");
const math = std.math;
const utils = @import("utils.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const gpa_allocator = gpa.allocator();

const ScreenSize = .{ .x = 1280, .y = 720 };

var gameState = GameState.init(gpa_allocator);

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
    updateFn: ?*const fn (ptr: *anyopaque) anyerror!void,
    drawFn: ?*const fn (ptr: *anyopaque) anyerror!void,
    deinitFn: ?*const fn (ptr: *anyopaque) void,

    fn init(
        alloc: std.mem.Allocator,
        ptr: *anyopaque,
        updateFn: ?*const fn (ptr: *anyopaque) anyerror!void,
        drawFn: ?*const fn (ptr: *anyopaque) anyerror!void,
        deinitFn: ?*const fn (ptr: *anyopaque) void,
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
        if (self.updateFn) |updateFn| {
            return updateFn(self.ptr);
        }
    }

    fn draw(self: *Self) !void {
        if (self.drawFn) |drawFn| {
            return drawFn(self.ptr);
        }
    }

    fn deinit(self: *Self) void {
        if (self.deinitFn) |deinitFn| {
            deinitFn(self.ptr);
        }
        self.alloc.destroy(self);
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
        rl.DrawTriangle(.{ .x = self.x, .y = self.y }, .{ .x = self.x, .y = self.y + 20 }, .{ .x = self.x + 30, .y = self.y + 10 }, rl.WHITE);
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
        rl.DrawRectangle(@intFromFloat(self.x), @intFromFloat(self.y), 10, 2, rl.WHITE);
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

const Enemy = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    x: f32,
    y: f32,
    yy: f32,
    speed: f32,
    object: *GameObject,

    fn init(alloc: std.mem.Allocator, x: f32, y: f32, speed: f32) !*Self {
        const enemy = try alloc.create(Self);

        const object = try GameObject.init(alloc, enemy, update, draw, deinit);

        enemy.* = Self{
            .alloc = alloc,
            .x = x,
            .y = y,
            .yy = y,
            .speed = speed,
            .object = object,
        };

        return enemy;
    }

    fn deinit(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.alloc.destroy(self);
    }

    fn update(ptr: *anyopaque) !void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        const delta_time = rl.GetFrameTime();

        self.x -= delta_time * self.speed;
        self.y = (math.sin((self.x + self.yy) / self.speed * 5) + 1) / 2 * (ScreenSize.y - 50);

        if (self.x < 0) {
            try gameState.removeObject(self.object);
        }
    }

    fn draw(ptr: *anyopaque) !void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        rl.DrawRectangle(@intFromFloat(self.x), @intFromFloat(self.y), 50, 50, rl.RED);
    }
};

const EnemySpawner = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    spawnRate: i64,
    lastSpawnEllapsed: i64,
    obj: *GameObject,

    fn init(alloc: std.mem.Allocator) !*Self {
        const spawn = try alloc.create(Self);
        const obj = try GameObject.init(alloc, spawn, update, null, deinit);
        spawn.* = Self{ .alloc = alloc, .obj = obj, .lastSpawnEllapsed = 0, .spawnRate = 100 };
        return spawn;
    }

    fn update(ptr: *anyopaque) !void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        if (std.time.milliTimestamp() - self.lastSpawnEllapsed > self.spawnRate) {
            const r_number = utils.generateRandomInt(0, ScreenSize.y);
            const enemy = try Enemy.init(self.alloc, ScreenSize.x, @floatFromInt(r_number), 500);
            try gameState.addObject(enemy.object);
            self.lastSpawnEllapsed = std.time.milliTimestamp();
        }
    }

    fn deinit(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.alloc.destroy(self);
    }
};

pub fn main() !void {
    defer {
        switch (gpa.deinit()) {
            .leak => @panic("leaked memory"),
            else => {},
        }
    }

    defer gameState.deinit();

    const player = try Player.init(gpa_allocator);
    try gameState.addObject(player.object);

    const enemy_spawner = try EnemySpawner.init(gpa_allocator);
    try gameState.addObject(enemy_spawner.obj);

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
