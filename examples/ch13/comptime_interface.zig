const std = @import("std");

/// The "interface": a Sink must have `pub fn write(self: *Sink, line: []const u8) void`.
fn requireSink(comptime T: type) void {
    if (!@hasDecl(T, "write")) {
        @compileError(@typeName(T) ++ " is not a Sink: it has no pub fn write");
    }
    const Expected = fn (*T, []const u8) void;
    if (@TypeOf(T.write) != Expected) {
        @compileError(@typeName(T) ++ ".write must be " ++ @typeName(Expected) ++
            ", found " ++ @typeName(@TypeOf(T.write)));
    }
}

/// A logger that numbers its lines and sends them to any Sink.
fn Logger(comptime Sink: type) type {
    comptime requireSink(Sink);
    return struct {
        const Self = @This();

        sink: *Sink,
        count: usize = 0,

        pub fn log(self: *Self, line: []const u8) void {
            self.count += 1;
            var buffer: [256]u8 = undefined;
            const text = std.mem.print(&buffer, "[{d}] {s}", .{ self.count, line }) catch line;
            self.sink.write(text);
        }
    };
}

const PrintSink = struct {
    pub fn write(_: *PrintSink, line: []const u8) void {
        std.debug.print("{s}\n", .{line});
    }
};

const ByteCounter = struct {
    bytes: usize = 0,
    pub fn write(self: *ByteCounter, line: []const u8) void {
        self.bytes += line.len;
    }
};

pub fn main() void {
    var printer: PrintSink = .{};
    var log_to_screen: Logger(PrintSink) = .{ .sink = &printer };
    log_to_screen.log("starting");
    log_to_screen.log("done");

    var counter: ByteCounter = .{};
    var log_to_counter: Logger(ByteCounter) = .{ .sink = &counter };
    log_to_counter.log("hello");
    log_to_counter.log("world");
    std.debug.print("counted {d} bytes\n", .{counter.bytes});
}
