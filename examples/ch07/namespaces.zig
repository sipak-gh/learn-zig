const std = @import("std");

/// A struct with no fields is just a namespace for declarations.
const units = struct {
    pub const km_per_mile = 1.609344;

    pub fn milesToKm(miles: f64) f64 {
        return miles * km_per_mile;
    }
};

/// `@This()` is the type of the innermost struct. `Self` is a common name.
const Counter = struct {
    const Self = @This();

    count: u32 = 0,

    pub fn bump(self: *Self) void {
        self.count += 1;
    }
};

pub fn main() void {
    std.debug.print("26.2 miles = {d:.1} km\n", .{units.milesToKm(26.2)});
    std.debug.print("@sizeOf(units) = {d}\n", .{@sizeOf(units)});

    var counter: Counter = .{};
    counter.bump();
    counter.bump();
    std.debug.print("count = {d}\n", .{counter.count});

    // A tuple: a struct whose fields have no names, only positions.
    const t = .{ 42, "hi", true };
    std.debug.print("t[0] = {d}, t[1] = {s}, t.len = {d}\n", .{ t[0], t[1], t.len });

    // Destructure a tuple into separate constants.
    const n, const word, _ = t;
    std.debug.print("n = {d}, word = {s}\n", .{ n, word });

    // An anonymous struct literal with no result type gets a new struct type.
    const pet = .{ .name = "Rex", .legs = 4 };
    std.debug.print("{s} has {d} legs\n", .{ pet.name, pet.legs });
}
