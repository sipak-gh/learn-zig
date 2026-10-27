const std = @import("std");

const Settings = struct {
    name: []const u8,
    jobs: u8 = 4,
    globs: []const []const u8 = &.{},
    color: enum { auto, always, never } = .auto,
};

const good =
    \\.{
    \\    .name = "my search",
    \\    .globs = .{ "*.zig", "*.md" },
    \\    .color = .never, // ZON allows comments
    \\}
;

const bad =
    \\.{ .name = "x", .jobs = 1000 }
;

pub fn main(init: std.process.Init) !void {
    var buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &buffer);
    const out = &stdout_writer.interface;

    var arena: std.heap.ArenaAllocator = .init(init.gpa);
    defer arena.deinit();

    for ([_][:0]const u8{ good, bad }) |source| {
        var diagnostics: std.zon.parse.Diagnostics = undefined;
        const settings = std.zon.parse.fromSlice(Settings, .{
            .gpa = init.gpa,
            .arena = arena.allocator(), // the result lives in the arena
            .source = source,
            .diagnostics = &diagnostics,
        }) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.ParseZon => {
                try out.print("{f}", .{diagnostics.fmt("settings.zon")});
                continue;
            },
        };
        try out.print("name={s} jobs={d} globs={d} color={t}\n", .{
            settings.name, settings.jobs, settings.globs.len, settings.color,
        });

        // And back to ZON text.
        try std.zon.stringify.serialize(settings, .{}, out);
        try out.writeByte('\n');
    }
    try out.flush();
}
