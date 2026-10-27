const std = @import("std");

pub fn main(init: std.process.Init) !void {
    // A string literal is a pointer to a constant, 0-terminated array.
    const hello = "hello";
    std.debug.print("type of \"hello\": {s}\n", .{@typeName(@TypeOf(hello))});
    std.debug.print("len {d}, byte after the end: {d}\n", .{ hello.len, hello[hello.len] });

    // It coerces to every common string type.
    const as_slice: []const u8 = hello; // length, no terminator promised
    const as_zslice: [:0]const u8 = hello; // length and a 0 at [len]
    const as_cstr: [*:0]const u8 = hello; // no length: ends at the first 0
    std.debug.print("{s} {s} {s}\n", .{ as_slice, as_zslice, as_cstr });

    // std.mem.span finds the 0 and gives back a slice with a length.
    const back = std.mem.span(as_cstr);
    std.debug.print("span: {s} ({s}, len {d})\n", .{ back, @typeName(@TypeOf(back)), back.len });

    // You can build sentinel-terminated arrays yourself.
    const digits = [_:0]u8{ '1', '2', '3' };
    std.debug.print("type of digits: {s}\n", .{@typeName(@TypeOf(digits))});

    // Command-line arguments come from the OS as 0-terminated strings.
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    std.debug.print("type of args: {s}\n", .{@typeName(@TypeOf(args))});
    for (args[1..]) |arg| {
        const plain: []const u8 = arg; // drop the sentinel: always allowed
        std.debug.print("arg {s} has {d} bytes\n", .{ plain, plain.len });
    }
}
