//! Zig's naming conventions in one file. The file has no top-level
//! fields, so it is a namespace and its name is snake_case.

const std = @import("std");

/// TitleCase: types and type aliases.
const Celsius = f32;

/// snake_case: constants and variables, even comptime-known ones.
const freezing_point: Celsius = 0;

const Reading = struct {
    // snake_case: fields.
    station_name: []const u8,
    temperature: Celsius,

    // camelCase: functions and methods.
    pub fn isFreezing(reading: Reading) bool {
        return reading.temperature <= freezing_point;
    }
};

/// TitleCase: a function that returns a type.
fn Pair(comptime T: type) type {
    return struct { first: T, second: T };
}

/// camelCase: every other function. Acronyms are ordinary words:
/// `parseCsvLine`, not `parseCSVLine`.
fn parseCsvLine(line: []const u8) Reading {
    var fields = std.mem.splitScalar(u8, line, ',');
    const station_name = fields.first();
    const temperature = std.fmt.parseFloat(Celsius, fields.next().?) catch 0;
    return .{ .station_name = station_name, .temperature = temperature };
}

pub fn main() void {
    const readings: Pair(Reading) = .{
        .first = parseCsvLine("Oslo,-3.5"),
        .second = parseCsvLine("Lisbon,14"),
    };
    // A variable holding a function is callable, so it is camelCase too.
    const checkFrost = Reading.isFreezing;
    for ([_]Reading{ readings.first, readings.second }) |reading| {
        std.debug.print("{s}: {d} freezing={}\n", .{ reading.station_name, reading.temperature, checkFrost(reading) });
    }
    std.debug.print("{s}\n", .{@typeName(Pair(Reading))});
}
