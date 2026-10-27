const std = @import("std");

pub fn main() !void {
    var source: std.Io.Reader = .fixed("short\nthis line is too long\nok\n");
    // Read `source` through an 8-byte buffer, like a File.Reader with a
    // tiny buffer would.
    var small_buffer: [8]u8 = undefined;
    var limited = source.limited(.unlimited, &small_buffer);
    const r = &limited.interface;

    while (true) {
        const line = r.takeDelimiter('\n') catch |err| {
            std.debug.print("error: {t}\n", .{err});
            // Skip the rest of the long line and keep going.
            _ = try r.discardDelimiterInclusive('\n');
            continue;
        } orelse break;
        std.debug.print("line: {s}\n", .{line});
    }
}
