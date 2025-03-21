const std = @import("std");
const rl = @import("raylib.zig");

var prng = std.Random.DefaultPrng.init(21332112312);
const rand = prng.random();

pub fn generateRandomInt(min: u32, max: u32) u32 {
    return rand.intRangeAtMost(u32, min, max);
}

pub fn generateColor() rl.Color {
    const r = generateRandomInt(0, 255);
    const g = generateRandomInt(0, 255);
    const b = generateRandomInt(0, 255);
    return rl.Color{ .r = @intCast(r), .g = @intCast(g), .b = @intCast(b), .a = 200 };
}
