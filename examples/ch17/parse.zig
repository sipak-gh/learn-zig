const std = @import("std");

const Config = struct {
    name: []const u8,
    jobs: u8 = 4, // used when the JSON has no "jobs"
    paths: []const []const u8,
    color: enum { auto, always, never } = .auto,
    max_count: ?usize = null,
};

const input =
    \\{
    \\  "name": "seek \u0021",
    \\  "paths": ["src", "docs"],
    \\  "color": "never",
    \\  "max_count": null
    \\}
;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    const parsed = try std.json.parseFromSlice(Config, gpa, input, .{});
    // Frees everything the parser allocated: strings, the slice of paths...
    defer parsed.deinit();
    const config = parsed.value;

    std.debug.print("name={s} jobs={d} paths={d} first={s}\n", .{
        config.name, config.jobs, config.paths.len, config.paths[0],
    });
    std.debug.print("color={t} max_count={?d}\n", .{ config.color, config.max_count });

    // Unknown fields are an error unless you ask to ignore them.
    const extra =
        \\{"name": "x", "paths": [], "verbose": true}
    ;
    if (std.json.parseFromSlice(Config, gpa, extra, .{})) |p| {
        p.deinit();
    } else |err| {
        std.debug.print("strict: {t}\n", .{err});
    }
    const relaxed = try std.json.parseFromSlice(Config, gpa, extra, .{ .ignore_unknown_fields = true });
    defer relaxed.deinit();
    std.debug.print("relaxed: name={s}\n", .{relaxed.value.name});

    // With your own arena, the "Leaky" variant returns the value directly.
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const numbers = try std.json.parseFromSliceLeaky([]i32, arena.allocator(), "[1, -2, 3]", .{});
    std.debug.print("numbers={any}\n", .{numbers});
}
