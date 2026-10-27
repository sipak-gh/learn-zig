const std = @import("std");

const Monster = struct {
    hp: u32,
    x: f32,
    y: f32,
    name: []const u8,
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    // Stores each field in its own array: all hp values together, all x
    // values together, and so on.
    var monsters: std.MultiArrayList(Monster) = .empty;
    defer monsters.deinit(gpa);

    try monsters.append(gpa, .{ .hp = 10, .x = 0, .y = 0, .name = "slime" });
    try monsters.append(gpa, .{ .hp = 45, .x = 3, .y = 1, .name = "troll" });
    try monsters.append(gpa, .{ .hp = 7, .x = 8, .y = 2, .name = "bat" });

    // items(.hp) is a []u32 holding just that field. A loop over it touches
    // only the memory it needs.
    const hp = monsters.items(.hp);
    var total: u32 = 0;
    for (hp) |h| total += h;
    std.debug.print("{d} monsters, total hp {d}\n", .{ monsters.len, total });

    for (monsters.items(.x)) |*x| x.* += 1; // everyone moves right

    // get(i) puts a whole struct back together.
    const troll = monsters.get(1);
    std.debug.print("{s} at ({d}, {d})\n", .{ troll.name, troll.x, troll.y });
}
