const std = @import("std");
const Io = std.Io;

/// Counts finished jobs. `mutex` protects `done`; `changed` lets a task
/// sleep until `done` changes instead of checking it in a busy loop.
const Progress = struct {
    mutex: Io.Mutex = .init,
    changed: Io.Condition = .init,
    done: usize = 0,

    fn finishOne(p: *Progress, io: Io) void {
        p.mutex.lockUncancelable(io);
        defer p.mutex.unlock(io);
        p.done += 1;
        p.changed.signal(io);
    }

    fn waitFor(p: *Progress, io: Io, n: usize) void {
        p.mutex.lockUncancelable(io);
        defer p.mutex.unlock(io);
        // `wait` unlocks the mutex while it sleeps and locks it again
        // before returning. Always re-check in a loop: waking up does not
        // mean the condition you want is true yet.
        while (p.done < n) p.changed.waitUncancelable(io, &p.mutex);
    }
};

fn job(io: Io, ms: i64, progress: *Progress) Io.Cancelable!void {
    try io.sleep(.fromMilliseconds(ms), .awake);
    progress.finishOne(io);
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var progress: Progress = .{};

    var group: Io.Group = .init;
    defer group.cancel(io);
    for ([_]i64{ 30, 10, 50, 20 }) |ms| try group.concurrent(io, job, .{ io, ms, &progress });

    progress.waitFor(io, 2);
    std.debug.print("2 jobs done\n", .{});
    progress.waitFor(io, 4);
    std.debug.print("all 4 jobs done\n", .{});

    try group.await(io);
}
