//! `zig build bench`: times three ways of looking for a zero byte.

const std = @import("std");
const Io = std.Io;
const bytes = @import("bytes"); // provided by build.zig

const size = 64 * 1024 * 1024;
const runs = 20;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer: Io.File.Writer = .initStreaming(.stdout(), io, &stdout_buffer);
    const out = &stdout_writer.interface;

    // No zero until the very last byte, so every function reads it all.
    const data = try gpa.alloc(u8, size);
    defer gpa.free(data);
    @memset(data, 'a');
    data[size - 1] = 0;

    try out.print("scanning {d} MiB, best of {d} runs\n", .{ size / (1024 * 1024), runs });
    try measure(io, out, "scalar loop", bytes.containsZeroScalar, data);
    try measure(io, out, "@Vector", bytes.containsZero, data);
    try measure(io, out, "std.mem.findScalar", stdFind, data);
    try out.flush();
}

fn stdFind(data: []const u8) bool {
    return std.mem.findScalar(u8, data, 0) != null;
}

fn measure(
    io: Io,
    out: *Io.Writer,
    name: []const u8,
    comptime scan: fn ([]const u8) bool,
    data: []const u8,
) !void {
    var best: Io.Duration = .max;
    for (0..runs) |_| {
        const start = Io.Clock.awake.now(io);
        const found = scan(data);
        const elapsed = start.untilNow(io, .awake);
        // Without this, the optimizer may notice `found` is unused and
        // delete the call we are trying to time.
        std.mem.doNotOptimizeAway(found);
        if (!found) return error.ZeroNotFound;
        if (elapsed.nanoseconds < best.nanoseconds) best = elapsed;
    }
    const seconds = @as(f64, @floatFromInt(best.nanoseconds)) / std.time.ns_per_s;
    const gib_per_second = @as(f64, @floatFromInt(data.len)) / (1024 * 1024 * 1024) / seconds;
    try out.print("{s:<20} {d:>8.2} ms  {d:>6.1} GiB/s\n", .{
        name,
        @as(f64, @floatFromInt(best.nanoseconds)) / std.time.ns_per_ms,
        gib_per_second,
    });
}
