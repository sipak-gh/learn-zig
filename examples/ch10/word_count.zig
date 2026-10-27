const std = @import("std");

const text =
    \\the cat sat on the mat
    \\the dog sat on the cat
;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    // Word -> count. For []const u8 keys use a String hash map.
    var counts: std.StringHashMapUnmanaged(usize) = .empty;
    defer counts.deinit(gpa);

    var words = std.mem.tokenizeAny(u8, text, " \n");
    while (words.next()) |word| {
        // One lookup: find the slot for `word`, creating it if needed.
        const gop = try counts.getOrPut(gpa, word);
        if (!gop.found_existing) gop.value_ptr.* = 0;
        gop.value_ptr.* += 1;
    }

    // Copy the entries into a list so we can sort them.
    const Entry = struct { word: []const u8, n: usize };
    var entries: std.ArrayList(Entry) = .empty;
    defer entries.deinit(gpa);
    var it = counts.iterator();
    while (it.next()) |e| try entries.append(gpa, .{ .word = e.key_ptr.*, .n = e.value_ptr.* });

    // Most frequent first; ties in alphabetical order.
    std.mem.sort(Entry, entries.items, {}, struct {
        fn lessThan(_: void, a: Entry, b: Entry) bool {
            if (a.n != b.n) return a.n > b.n;
            return std.mem.lessThan(u8, a.word, b.word);
        }
    }.lessThan);

    for (entries.items) |e| std.debug.print("{s:<4} {d}\n", .{ e.word, e.n });
}
