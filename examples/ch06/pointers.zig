const std = @import("std");

/// Takes a pointer so it can change the caller's variable.
fn increment(counter: *u32) void {
    counter.* += 1;
}

/// A const pointer can read but not write.
fn show(label: []const u8, value: *const u32) void {
    std.debug.print("{s}: {d}\n", .{ label, value.* });
}

pub fn main() void {
    var hits: u32 = 0;
    const p = &hits; // p: *u32 — the address of `hits`
    p.* = 10; // write through the pointer
    increment(p);
    increment(&hits);
    show("hits", &hits); // *u32 coerces to *const u32

    // The address of a `const` gives a `*const` pointer.
    const limit: u32 = 100;
    const lp = &limit;
    std.debug.print("type of &hits: {s}, type of &limit: {s}\n", .{
        @typeName(@TypeOf(p)),
        @typeName(@TypeOf(lp)),
    });

    // A pointer to an element of an array.
    var scores = [_]u32{ 7, 8, 9 };
    const second = &scores[1];
    second.* *= 10;
    std.debug.print("scores = {any}\n", .{scores});

    // A pointer to a whole array can be indexed and has a length.
    const all = &scores;
    all[0] = 1;
    std.debug.print("all.len = {d}, scores[0] = {d}\n", .{ all.len, scores[0] });

    // `{*}` prints the address. It changes from run to run.
    std.debug.print("p = {*}\n", .{p});
}
