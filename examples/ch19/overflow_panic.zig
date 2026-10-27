const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    // The value comes from the command line, so the compiler can't check
    // the addition at compile time.
    const stock: u8 = try std.fmt.parseInt(u8, args[1], 10);
    const total: u8 = stock + 10;
    std.debug.print("{d} + 10 = {d}\n", .{ stock, total });
}
