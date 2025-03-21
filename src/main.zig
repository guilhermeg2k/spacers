const std = @import("std");
const rl = @import("raylib.zig");
const math = std.math;
const utils = @import("utils.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const gpa_allocator = gpa.allocator();

const ScreenSize = Vector2D(u12){ .x = 1366, .y = 768 };

var gameState = GameState.init(gpa_allocator);

fn Vector2D(T: type) type {
    return struct {
        x: T,
        y: T,
    };
}

const GameState = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    score: i64,
    player: ?*GameObject,

    next_object_id: u64,
    objects: std.AutoArrayHashMap(u64, *GameObject),
    objects_add_poll: std.AutoArrayHashMap(*GameObject, *GameObject),
    objects_remove_poll: std.AutoArrayHashMap(*GameObject, *GameObject),

    fn init(alloc: std.mem.Allocator) Self {
        return Self{ .alloc = alloc, .player = null, .next_object_id = 0, .score = 0, .objects = std.AutoArrayHashMap(u64, *GameObject).init(alloc), .objects_add_poll = std.AutoArrayHashMap(*GameObject, *GameObject).init(alloc), .objects_remove_poll = std.AutoArrayHashMap(*GameObject, *GameObject).init(alloc) };
    }

    fn setPlayer(self: *Self, player: *GameObject) void {
        self.player = player;
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

    fn addObject(self: *Self, obj: *GameObject) !void {
        try self.objects_add_poll.put(obj, obj);
    }

    fn removeObject(self: *Self, obj: *GameObject) !void {
        try self.objects_remove_poll.put(obj, obj);
    }

    fn getObjectsByTag(self: *Self, tag: GameObjectTag) !std.ArrayList(*GameObject) {
        var it = self.objects.iterator();
        var arr = std.ArrayList(*GameObject).init(self.alloc);

        while (it.next()) |object| {
            if (object.value_ptr.*.tag == tag) {
                try arr.append(object.value_ptr.*);
            }
        }

        return arr;
    }

    fn scoreHit(self: *Self) void {
        self.score += 10;
    }

    fn scoreKill(self: *Self) void {
        self.score += 30;
    }

    fn removeScore(self: *Self, amount: i64) void {
        self.score = @max(0, self.score - amount);
    }

    fn update(self: *Self) !void {
        std.log.warn("Object count = {}\n Score = {}", .{ self.objects.count(), self.score });
        var it = self.objects.iterator();
        while (it.next()) |object| {
            try object.value_ptr.*.update();
        }

        var it2 = self.objects_add_poll.iterator();
        while (it2.next()) |object| {
            const o = object.value_ptr.*;
            try self.objects.put(o.id, o);

            if (o.tag == GameObjectTag.Player) {
                self.setPlayer(o);
            }
        }

        var it3 = self.objects_remove_poll.iterator();
        while (it3.next()) |object| {
            const o = object.value_ptr.*;
            const _object = self.objects.get(o.id);
            if (_object) |obj| {
                _ = self.objects.swapRemove(obj.id);
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
};

const GameObjectTag = enum {
    General,
    Player,
    Enemy,
    Bullet,
};

const GameObject = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    id: u64,
    tag: GameObjectTag,
    ptr: *anyopaque,
    updateFn: ?*const fn (ptr: *anyopaque) anyerror!void,
    drawFn: ?*const fn (ptr: *anyopaque) anyerror!void,
    deinitFn: ?*const fn (ptr: *anyopaque) void,

    fn init(
        alloc: std.mem.Allocator,
        ptr: *anyopaque,
        tag: GameObjectTag,
        updateFn: ?*const fn (ptr: *anyopaque) anyerror!void,
        drawFn: ?*const fn (ptr: *anyopaque) anyerror!void,
        deinitFn: ?*const fn (ptr: *anyopaque) void,
    ) !*Self {
        const object = try alloc.create(GameObject);

        object.* = GameObject{
            .alloc = alloc,
            .id = gameState.next_object_id,
            .tag = tag,
            .ptr = ptr,
            .updateFn = updateFn,
            .drawFn = drawFn,
            .deinitFn = deinitFn,
        };

        gameState.next_object_id += 1;

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
    size: Vector2D(f32),
    speed: f32,
    object: *GameObject,

    fn init(alloc: std.mem.Allocator) !*Player {
        const player = try alloc.create(Self);

        const object = try GameObject.init(alloc, player, GameObjectTag.Player, update, draw, deinit);

        player.* = Self{ .alloc = alloc, .speed = 700.0, .x = ScreenSize.x / 2, .y = ScreenSize.y / 2, .object = object, .size = .{ .x = 30, .y = 20 } };

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
        rl.DrawTriangle(.{ .x = self.x, .y = self.y }, .{ .x = self.x, .y = self.y + self.size.y }, .{ .x = self.x + self.size.x, .y = self.y + self.size.y / 2 }, rl.WHITE);
    }

    fn handleInput(self: *Self) !void {
        const delta_time = rl.GetFrameTime();
        const is_moving_up = rl.IsKeyDown(rl.KEY_W);
        const is_moving_down = rl.IsKeyDown(rl.KEY_S);
        const is_moving_left = rl.IsKeyDown(rl.KEY_A);
        const is_moving_right = rl.IsKeyDown(rl.KEY_D);

        if (is_moving_up) self.y = @max(self.y - 1 * self.speed * delta_time, 0);
        if (is_moving_down) self.y = @min(self.y + 1 * self.speed * delta_time, ScreenSize.y - self.size.y);
        if (is_moving_left) self.x = @max(self.x - 1 * self.speed * delta_time, 0);
        if (is_moving_right) self.x = @min(self.x + 1 * self.speed * delta_time, ScreenSize.x - self.size.x);

        if (rl.IsKeyPressed(rl.KEY_SPACE)) {
            const bullet = try Bullet.init(self.alloc, .{ .x = self.x, .y = self.y + self.size.y / 2 });
            try gameState.addObject(bullet.object);
        }
    }

    fn getRect(self: *Self) rl.Rectangle {
        return .{ .x = self.x, .y = self.y, .width = self.size.x, .height = self.size.y };
    }
};

const Bullet = struct {
    const Self = @This();
    pos: Vector2D(f32),
    size: Vector2D(u32),
    speed: f32,
    alloc: std.mem.Allocator,
    object: *GameObject,

    fn init(alloc: std.mem.Allocator, pos: Vector2D(f32)) !*Bullet {
        const bullet = try alloc.create(Self);
        const object = try GameObject.init(alloc, bullet, GameObjectTag.Bullet, update, draw, deinit);

        bullet.* = Self{
            .pos = pos,
            .size = .{ .x = 10, .y = 2 },
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

    fn getRect(self: *Self) rl.Rectangle {
        return .{ .x = self.pos.x, .y = self.pos.y, .width = @floatFromInt(self.size.x), .height = @floatFromInt(self.size.y + 5) };
    }

    fn draw(ptr: *anyopaque) !void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        rl.DrawRectangle(@intFromFloat(self.pos.x), @intFromFloat(self.pos.y), @intCast(self.size.x), @intCast(self.size.y), rl.WHITE);
    }

    fn update(ptr: *anyopaque) !void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        const delta_time = rl.GetFrameTime();
        self.pos.x += delta_time * self.speed;

        if (self.pos.x > ScreenSize.x) {
            try gameState.removeObject(self.object);
        }
    }
};

const EnemyMovType = enum {
    straigth,
    zigZag,
};

const Enemy = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    pos: Vector2D(f32),
    size: Vector2D(u32),
    minSize: u32,
    ySpawn: f32,
    speed: f32,
    movType: EnemyMovType,
    object: *GameObject,
    color: rl.Color,

    fn init(alloc: std.mem.Allocator, size: Vector2D(u32), ySpawn: f32, speed: f32, movType: EnemyMovType) !*Self {
        const enemy = try alloc.create(Self);

        const object = try GameObject.init(alloc, enemy, GameObjectTag.Enemy, update, draw, deinit);

        enemy.* = Self{
            .alloc = alloc,
            .pos = .{ .x = ScreenSize.x, .y = ySpawn },
            .size = size,
            .ySpawn = ySpawn,
            .minSize = 40,
            .speed = speed,
            .movType = movType,
            .object = object,
            .color = utils.generateColor(),
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

        self.pos.x -= delta_time * self.speed;

        if (self.movType == EnemyMovType.zigZag) {
            self.pos.y = (math.sin((self.pos.x + self.ySpawn) / self.speed * 2) + 1) / 2 * (ScreenSize.y - 50);
        }

        if (self.pos.x < 0) {
            gameState.removeScore(self.size.x * 3);
            try gameState.removeObject(self.object);
        }

        if (gameState.player) |player| {
            const p: *Player = @ptrCast(@alignCast(player.ptr));
            if (rl.CheckCollisionRecs(self.getRect(), p.getRect())) {
                gameState.score = 0;
            }
        }

        const bullets = try gameState.getObjectsByTag(GameObjectTag.Bullet);
        defer bullets.deinit();

        for (bullets.items) |bullet| {
            const b: *Bullet = @ptrCast(@alignCast(bullet.ptr));

            if (rl.CheckCollisionRecs(self.getRect(), b.getRect())) {
                try gameState.removeObject(b.object);
                if (self.size.x / 2 > self.minSize) {
                    const resizeBy = 2;
                    self.size = .{ .x = self.size.x / resizeBy, .y = self.size.y / resizeBy };
                    const width: f32 = @floatFromInt(self.size.x);
                    const height: f32 = @floatFromInt(self.size.y);
                    self.pos = Vector2D(f32){ .x = self.pos.x + width / 2, .y = self.pos.y + height / 2 };
                    gameState.scoreHit();
                } else {
                    try gameState.removeObject(self.object);
                    gameState.scoreKill();
                }
            }
        }
    }

    fn getRect(self: *Self) rl.Rectangle {
        return .{ .x = self.pos.x, .y = self.pos.y - 5, .width = @floatFromInt(self.size.x), .height = @floatFromInt(self.size.y + 10) };
    }

    fn draw(ptr: *anyopaque) !void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        rl.DrawRectangle(@intFromFloat(self.pos.x), @intFromFloat(self.pos.y), @intCast(self.size.x), @intCast(self.size.y), self.color);
    }
};

const EnemySpawner = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    spawnRate: i64,
    lastSpawn: i64,
    obj: *GameObject,

    fn init(alloc: std.mem.Allocator) !*Self {
        const spawn = try alloc.create(Self);
        const obj = try GameObject.init(alloc, spawn, GameObjectTag.General, update, null, deinit);
        spawn.* = Self{ .alloc = alloc, .obj = obj, .lastSpawn = 0, .spawnRate = 900 };
        return spawn;
    }

    fn update(ptr: *anyopaque) !void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        if (std.time.milliTimestamp() - self.lastSpawn > self.spawnRate) {
            const r_number = utils.generateRandomInt(20, ScreenSize.y - 20);
            const size = math.clamp(r_number, 20, ScreenSize.y / 4);

            const enemy = try Enemy.init(
                self.alloc,
                .{
                    .x = size,
                    .y = size,
                },
                @floatFromInt(r_number),
                300,
                if (r_number % 2 == 1) EnemyMovType.straigth else EnemyMovType.zigZag,
            );

            try gameState.addObject(enemy.object);
            self.lastSpawn = std.time.milliTimestamp();
        }
    }

    fn deinit(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.alloc.destroy(self);
    }
};

const Gui = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    obj: *GameObject,

    fn init(alloc: std.mem.Allocator) !*Self {
        const gui = try alloc.create(Self);
        const obj = try GameObject.init(alloc, gui, GameObjectTag.General, null, draw, deinit);
        gui.* = Self{ .alloc = alloc, .obj = obj };
        return gui;
    }

    fn draw(ptr: *anyopaque) !void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        const txt = try std.fmt.allocPrintZ(self.alloc, "{}", .{gameState.score});
        defer self.alloc.free(txt);
        rl.DrawText(txt, 10, 10, 40, rl.WHITE);
    }

    fn deinit(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.alloc.destroy(self);
    }
};

const Star = struct {
    size: Vector2D(f32),
    pos: Vector2D(f32),
    color: rl.Color,
    alpha: f32,
    invert_alpha: bool,
};

const StarsBG = struct {
    const Self = @This();
    const NUMBER_OF_STARS = 100;

    alloc: std.mem.Allocator,
    stars: [NUMBER_OF_STARS]Star,
    obj: *GameObject,

    fn init(alloc: std.mem.Allocator) !*Self {
        const bg = try alloc.create(Self);
        const obj = try GameObject.init(alloc, bg, GameObjectTag.General, update, draw, deinit);

        bg.* = Self{ .alloc = alloc, .obj = obj, .stars = [_]Star{.{
            .size = .{ .x = 0, .y = 0 },
            .pos = .{ .x = 0, .y = 0 },
            .alpha = 0,
            .invert_alpha = true,
            .color = rl.WHITE,
        }} ** NUMBER_OF_STARS };

        bg.randomizeStars();
        return bg;
    }

    fn randomizeStars(self: *Self) void {
        for (&self.stars) |*star| {
            const x = utils.generateRandomInt(0, ScreenSize.x);
            const y = utils.generateRandomInt(0, ScreenSize.y);

            const invert_alpha = utils.generateRandomInt(0, 1) == 1;
            const alpha = @as(f32, @floatFromInt(utils.generateRandomInt(30, 60))) / 100.0;
            const size: f32 = @floatFromInt(utils.generateRandomInt(1, 4));

            star.size = .{ .x = size * 2, .y = size };
            star.pos = .{ .x = @floatFromInt(x), .y = @floatFromInt(y) };
            star.alpha = alpha;
            star.invert_alpha = invert_alpha;
            star.color = utils.generateColor();
        }
    }

    fn draw(ptr: *anyopaque) !void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        for (&self.stars) |*star| {
            rl.DrawRectangle(@intFromFloat(star.pos.x), @intFromFloat(star.pos.y), @intFromFloat(star.size.x), @intFromFloat(star.size.y), rl.Fade(star.color, star.alpha));
        }
    }

    fn update(ptr: *anyopaque) !void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        const delta_time = rl.GetFrameTime();

        for (&self.stars) |*star| {
            const alpha = star.alpha;

            if (alpha >= 0.9) {
                star.invert_alpha = false;
            } else if (alpha <= 0) {
                star.invert_alpha = true;
            }

            const alpha_factor: f32 = if (star.invert_alpha == true) 0.2 else -0.2;

            star.alpha += alpha_factor * delta_time * 4;
            star.pos.x -= delta_time * 500;

            if (star.pos.x <= 0) {
                star.pos.x = ScreenSize.x;
                star.pos.y = @floatFromInt(utils.generateRandomInt(0, ScreenSize.y));
            }
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

    const bg = try StarsBG.init(gpa_allocator);
    try gameState.addObject(bg.obj);

    const player = try Player.init(gpa_allocator);
    try gameState.addObject(player.object);

    const enemy_spawner = try EnemySpawner.init(gpa_allocator);
    try gameState.addObject(enemy_spawner.obj);

    const gui = try Gui.init(gpa_allocator);
    try gameState.addObject(gui.obj);

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
