const std = @import("std");

/// Anything with a `run` method, with its concrete type erased.
const Task = struct {
    ptr: *anyopaque,
    runFn: *const fn (ptr: *anyopaque) void,

    /// `object` must be a pointer to a value with `pub fn run(self: *T) void`.
    fn init(object: anytype) Task {
        const T = @typeInfo(@TypeOf(object)).pointer.child;
        // One wrapper function is generated per T. It knows the real type
        // and turns the *anyopaque back into a *T.
        const gen = struct {
            fn run(ptr: *anyopaque) void {
                const self: *T = @ptrCast(@alignCast(ptr));
                self.run();
            }
        };
        return .{ .ptr = object, .runFn = gen.run };
    }

    fn run(task: Task) void {
        task.runFn(task.ptr);
    }
};

const Greeter = struct {
    name: []const u8,
    pub fn run(self: *Greeter) void {
        std.debug.print("hello, {s}\n", .{self.name});
    }
};

const Counter = struct {
    count: u32 = 0,
    pub fn run(self: *Counter) void {
        self.count += 1;
        std.debug.print("count is now {d}\n", .{self.count});
    }
};

pub fn main() void {
    var greeter: Greeter = .{ .name = "Zig" };
    var counter: Counter = .{};

    // Different types, one array: every element is just a Task.
    const tasks = [_]Task{ .init(&greeter), .init(&counter), .init(&counter) };
    for (tasks) |task| task.run();
    std.debug.print("@sizeOf(Task) = {d}\n", .{@sizeOf(Task)});
}
