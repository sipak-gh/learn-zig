const std = @import("std");

const Suit = enum {
    clubs,
    diamonds,
    hearts,
    spades,

    /// Enums can have methods, just like structs.
    pub fn isRed(suit: Suit) bool {
        return switch (suit) {
            .diamonds, .hearts => true,
            .clubs, .spades => false,
        };
    }
};

/// An explicit tag type fixes the integer behind each value.
const Level = enum(u8) { low = 1, medium = 5, high = 10 };

/// `_` makes the enum non-exhaustive: every u8 is a valid Status.
const Status = enum(u8) { ok = 0, not_found = 4, _ };

pub fn main() void {
    // `.hearts` is an enum literal. The result type says which enum.
    const card: Suit = .hearts;
    std.debug.print("{t} is red: {}\n", .{ card, card.isRed() });
    std.debug.print("@tagName: {s}, equal: {}\n", .{ @tagName(Suit.spades), card == .hearts });

    // Enum <-> integer.
    const level: Level = .medium;
    const raw: u8 = @backingInt(level);
    const back: Level = @fromBackingInt(10);
    std.debug.print("{t} = {d}, 10 = {t}\n", .{ level, raw, back });

    // Without an explicit tag type, Zig picks the smallest that fits.
    std.debug.print("@sizeOf(Suit) = {d}, @sizeOf(Level) = {d}\n", .{ @sizeOf(Suit), @sizeOf(Level) });

    // A non-exhaustive enum can hold numbers that have no name.
    const s: Status = @fromBackingInt(7);
    switch (s) {
        .ok => std.debug.print("ok\n", .{}),
        .not_found => std.debug.print("not found\n", .{}),
        _ => std.debug.print("unknown status {d}\n", .{@backingInt(s)}),
    }

    // Look a value up by name (returns null for unknown names).
    const parsed = std.meta.stringToEnum(Suit, "clubs");
    std.debug.print("parsed: {any}\n", .{parsed});
}
