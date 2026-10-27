const std = @import("std");

const Point = struct { x: u8, y: u8 };

pub fn main(init: std.process.Init) void {
    const inputs = [_][]const u8{
        \\{"x": 1, "y": 2}
        ,
        \\{"x": 1, "y": 300}
        ,
        \\{"x": 1, "y": "two"}
        ,
        \\{"x": 1}
        ,
        \\{"x": 1, "y": 2, "x": 3}
        ,
        \\{"x": 1, "y":
        ,
        \\{"x": 1, "y": 2} trailing
        ,
    };
    for (inputs) |text| {
        if (std.json.parseFromSlice(Point, init.gpa, text, .{})) |parsed| {
            defer parsed.deinit();
            std.debug.print("{s:<26} -> x={d} y={d}\n", .{ text, parsed.value.x, parsed.value.y });
        } else |err| {
            std.debug.print("{s:<26} -> error.{t}\n", .{ text, err });
        }
    }
}
