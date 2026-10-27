const std = @import("std");

pub fn main() !void {
    const word = "naïve café";

    // Bytes: a for loop over a []const u8 sees bytes, not characters.
    std.debug.print("{d} bytes:", .{word.len});
    for (word) |byte| std.debug.print(" {x:0>2}", .{byte});
    std.debug.print("\n", .{});

    // Code points: decode the UTF-8 with a Utf8View.
    const view = try std.unicode.Utf8View.init(word);
    var it = view.iterator();
    var n: usize = 0;
    while (it.nextCodepoint()) |cp| : (n += 1) {
        // `cp` is a u21; {u} prints it as UTF-8 again.
        std.debug.print("[{u}]", .{cp});
        if (cp > 127) std.debug.print("=U+{X:0>4}", .{cp});
    }
    std.debug.print("\n{d} code points\n", .{n});
    std.debug.print("utf8CountCodepoints: {d}\n", .{try std.unicode.utf8CountCodepoints(word)});

    // Invalid UTF-8 is rejected by init.
    const bad = "caf\xe9"; // Latin-1 é, not UTF-8
    if (std.unicode.Utf8View.init(bad)) |_| {
        std.debug.print("valid\n", .{});
    } else |err| {
        std.debug.print("bad: {t}\n", .{err});
    }
}
