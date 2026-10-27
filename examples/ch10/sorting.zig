const std = @import("std");

const Player = struct { name: []const u8, score: u32 };

/// Sorts by score, highest first. The context (`void` here) is passed to
/// every comparison; this function doesn't need one.
fn byScoreDesc(_: void, a: Player, b: Player) bool {
    return a.score > b.score;
}

/// A context with data: sort indexes by the values they point at.
const ByValue = struct {
    values: []const f64,
    fn lessThan(ctx: ByValue, a: usize, b: usize) bool {
        return ctx.values[a] < ctx.values[b];
    }
};

pub fn main() void {
    var numbers = [_]i32{ 5, -2, 9, 0, 3 };
    std.mem.sort(i32, &numbers, {}, std.sort.asc(i32));
    std.debug.print("asc:  {any}\n", .{numbers});
    std.mem.sort(i32, &numbers, {}, std.sort.desc(i32));
    std.debug.print("desc: {any}\n", .{numbers});

    var names = [_][]const u8{ "pear", "Apple", "fig", "apple" };
    std.mem.sort([]const u8, &names, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b); // byte order: 'A' < 'a'
        }
    }.lessThan);
    std.debug.print("names:", .{});
    for (names) |n| std.debug.print(" {s}", .{n});
    std.debug.print("\n", .{});

    var players = [_]Player{
        .{ .name = "ann", .score = 70 },
        .{ .name = "bob", .score = 90 },
        .{ .name = "cy", .score = 70 },
        .{ .name = "di", .score = 85 },
    };
    // sort is stable: ann stays before cy.
    std.mem.sort(Player, &players, {}, byScoreDesc);
    for (players) |p| std.debug.print("{s}:{d} ", .{ p.name, p.score });
    std.debug.print("\n", .{});

    const prices = [_]f64{ 2.5, 0.5, 9.0, 1.25 };
    var order = [_]usize{ 0, 1, 2, 3 };
    std.mem.sortUnstable(usize, &order, ByValue{ .values = &prices }, ByValue.lessThan);
    std.debug.print("cheapest first: {any}\n", .{order});
}
