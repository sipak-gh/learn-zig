const std = @import("std");

/// Pretends to read the next word into `buf`, like a reader would.
fn readWord(buf: []u8, word: []const u8) []u8 {
    @memcpy(buf[0..word.len], word);
    return buf[0..word.len];
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const input = [_][]const u8{ "red", "tan", "red", "fig" };
    var buf: [16]u8 = undefined;

    // Wrong: the map stores the slice, not the bytes. Every key points into
    // `buf`, which the next word overwrites.
    var bad: std.StringHashMapUnmanaged(void) = .empty;
    defer bad.deinit(gpa);
    for (input) |w| try bad.put(gpa, readWord(&buf, w), {});
    var bad_keys = bad.keyIterator();
    std.debug.print("bad: ", .{});
    while (bad_keys.next()) |k| std.debug.print("[{s}]", .{k.*});
    std.debug.print(" ({d} entries)\n", .{bad.count()});

    // Right: copy the key the first time we see it. The map owns the copies,
    // so free them before the map goes away.
    var good: std.StringHashMapUnmanaged(void) = .empty;
    defer {
        var keys = good.keyIterator();
        while (keys.next()) |k| gpa.free(k.*);
        good.deinit(gpa);
    }
    for (input) |w| {
        const gop = try good.getOrPut(gpa, readWord(&buf, w));
        if (!gop.found_existing) {
            // The new slot is already in the map. If dupe fails, take it out
            // again so `defer` never frees a key we didn't allocate.
            errdefer good.removeByPtr(gop.key_ptr);
            gop.key_ptr.* = try gpa.dupe(u8, gop.key_ptr.*);
        }
    }
    var good_keys = good.keyIterator();
    std.debug.print("good:", .{});
    while (good_keys.next()) |k| std.debug.print("[{s}]", .{k.*});
    std.debug.print(" ({d} entries)\n", .{good.count()});
}
