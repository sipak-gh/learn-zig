const std = @import("std");

pub fn main(init: std.process.Init) !void {
    // An arena takes memory from a "child" allocator and frees it all at once.
    var arena_state: std.heap.ArenaAllocator = .init(init.gpa);
    defer arena_state.deinit(); // frees everything allocated below
    const arena = arena_state.allocator();

    for (0..3) |round| {
        // Free this round's memory at the end of the round, but keep the
        // capacity so the next round doesn't have to ask the gpa again.
        defer _ = arena_state.reset(.retain_capacity);

        // Allocate freely; no individual frees needed.
        var used: usize = 0;
        for (0..1000) |i| {
            const line = try arena.print("round {d}, line {d}\n", .{ round, i });
            used += line.len;
        }
        std.debug.print("round {d}: {d} bytes used, capacity {d}\n", .{ round, used, arena_state.queryCapacity() });
    }
}
