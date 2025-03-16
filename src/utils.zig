const std = @import("std");

var prng = std.Random.DefaultPrng.init(213321);
const rand = prng.random();

pub fn generateRandomInt(min: u32, max: u32) u32 {
    return rand.intRangeAtMost(u32, min, max);
}
