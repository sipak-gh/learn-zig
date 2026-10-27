const std = @import("std");

const input =
    \\{"tool": "seek", "version": [1, 0], "ratio": 2.5, "tags": null,
    \\ "authors": [{"name": "Ann"}, {"name": "Bo"}]}
;

pub fn main(init: std.process.Init) !void {
    // std.json.Value can hold any JSON document.
    const parsed = try std.json.parseFromSlice(std.json.Value, init.gpa, input, .{});
    defer parsed.deinit();
    const root = parsed.value;

    // Value is a tagged union: null, bool, integer, float, number_string,
    // string, array, object.
    const object = root.object; // safety-checked: panics if root isn't an object
    std.debug.print("tool: {s}\n", .{object.get("tool").?.string});
    std.debug.print("major: {d}\n", .{object.get("version").?.array.items[0].integer});
    std.debug.print("ratio: {d}\n", .{object.get("ratio").?.float});
    std.debug.print("missing: {}\n", .{object.get("license") == null});

    // Walk all fields in order, switching on the kind of value.
    var it = object.iterator();
    while (it.next()) |entry| {
        const kind: []const u8 = switch (entry.value_ptr.*) {
            .null => "null",
            .bool => "bool",
            .integer, .float, .number_string => "number",
            .string => "string",
            .array => |array| if (array.items.len > 0 and array.items[0] == .object) "array of objects" else "array",
            .object => "object",
        };
        std.debug.print("{s}: {s}\n", .{ entry.key_ptr.*, kind });
    }
}
