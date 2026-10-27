# Chapter 15 — Concurrency

So far every program in this book has done one thing at a time. seek searches one file, then the next, while the other CPU cores sit idle. This chapter shows how Zig runs work concurrently: starting tasks with `io.async` and `io.concurrent`, managing them in groups, passing data through queues, and coordinating them with events, mutexes, conditions, and semaphores. You will also cancel tasks, use plain threads and atomics, and write a data race on purpose to catch it with ThreadSanitizer. In the project, seek gets `-j/--jobs N` and searches many files at once, with output byte-for-byte identical to the one-file-at-a-time version.

## `std.Io` is the concurrency interface

[Chapter 11](11-files-and-io.md) introduced `std.Io` as the interface for all I/O. It is also the interface for concurrency: instead of creating threads, you ask an `Io` to run a function, and the `Io` implementation decides how.

When `main` takes a `std.process.Init`, `init.io` is a **`std.Io.Threaded`**, created by the startup code (`lib/std/start.zig`). It keeps a pool of worker threads:

- **`io.async`** hands the function to a free pool thread. If none is free, it calls the function on the spot. The pool holds at most one thread fewer than the number of CPU cores.
- **`io.concurrent`** always gets its own thread. When none can be started, it fails with `error.ConcurrencyUnavailable`.

Other `Io` implementations choose differently. One might run everything on a single thread. Another might switch between tasks on one thread while each waits for I/O (an *event loop*). Code that only uses `Io` works with all of them, as long as it respects the difference between `async` and `concurrent`.

Zig 0.17 has no `std.Thread.Pool`. For "a pool of workers", use `Io.Group`, covered below, on the `Io` that `main` receives.

## `async` and `await`

`io.async(function, args)` starts `function(args...)` and returns a **`Future`** without waiting. `future.await(io)` waits and returns the function's result:

`examples/ch15/async_await.zig`

```zig
const std = @import("std");
const Io = std.Io;

/// Pretends to download a file: waits `ms` milliseconds, then returns its
/// size. `io.sleep` can fail with error.Canceled (more on that later).
fn download(io: Io, name: []const u8, ms: i64) Io.Cancelable!usize {
    try io.sleep(.fromMilliseconds(ms), .awake);
    std.debug.print("  {s} finished\n", .{name});
    return @intCast(ms * 1000);
}

fn both(io: Io) !void {
    const start = Io.Clock.awake.now(io);

    // Start both downloads. Neither call waits for the download to finish.
    var big = io.async(download, .{ io, "big.iso", 200 });
    var small = io.async(download, .{ io, "small.txt", 100 });

    // `await` waits for a result. Every Future must be awaited (or
    // canceled) exactly once, or its resources leak.
    const a = try big.await(io);
    const b = try small.await(io);

    std.debug.print("  {d} + {d} bytes in {f}\n", .{ a, b, start.untilNow(io, .awake) });
}

pub fn main(init: std.process.Init) !void {
    std.debug.print("with init.io:\n", .{});
    try both(init.io);

    // An Io that never starts another thread: `async` just calls the
    // function on the spot.
    var single: Io.Threaded = .init_single_threaded;
    std.debug.print("with a single-threaded Io:\n", .{});
    try both(single.io());

    // `concurrent` refuses instead.
    if (single.io().concurrent(download, .{ single.io(), "x", 1 })) |_| {
        unreachable;
    } else |err| {
        std.debug.print("concurrent: {t}\n", .{err});
    }
}
```

```console
$ zig run examples/ch15/async_await.zig
with init.io:
  small.txt finished
  big.iso finished
  200000 + 100000 bytes in 200.556ms
with a single-threaded Io:
  big.iso finished
  small.txt finished
  200000 + 100000 bytes in 300.517ms
concurrent: ConcurrencyUnavailable
```

Your times will differ slightly.

- `io.async(download, .{ io, "big.iso", 200 })` takes the function and a tuple of its arguments, which the compiler checks against the function's parameters (as with `std.Thread.spawn` later). The result is a `Future(Io.Cancelable!usize)`: a future of the function's return type.
- With `init.io`, both downloads ran at the same time: 200 ms in total, and the short one finished first.
- `Io.Threaded.init_single_threaded` is an `Io` that never starts a thread. Its `async` ran each function immediately, inside the `io.async` call: same results, 300 ms.
- Its `concurrent` refused with `error.ConcurrencyUnavailable`.
- `await` returns whatever the function returned, here an error union, hence `try`.
- Every `Future` must be awaited or canceled. Until then, it may hold resources.

## `async` or `concurrent`?

`async` means "this *may* run at the same time as the code that follows". The code is correct either way, so `async` never fails: with no thread available, the function just runs right away. Use it for independent work, like the two downloads.

`concurrent` means "this *must* run at the same time as the code that follows". Use it when the task and the caller wait for each other, like a producer filling a queue that the caller drains. Run inline, the producer would fill the queue, block, and never return to let the caller drain it: a deadlock. `concurrent` refuses to run inline, so you get `error.ConcurrencyUnavailable` instead of a hang. Exercise 3 shows the deadlock.

## Groups: many tasks, one `await`

A `Future` tracks one task. An **`Io.Group`** tracks any number, and you wait for all of them at once:

`examples/ch15/group.zig`

```zig
const std = @import("std");
const Io = std.Io;

/// Sums one chunk. Each task writes to its own `out`, so no two tasks
/// ever touch the same memory.
fn sumChunk(chunk: []const u64, out: *u64) void {
    var total: u64 = 0;
    for (chunk) |n| total += n;
    out.* = total;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const numbers = try gpa.alloc(u64, 1_000_000);
    defer gpa.free(numbers);
    for (numbers, 1..) |*n, i| n.* = i;

    const task_count = 4;
    var partial: [task_count]u64 = undefined;
    const chunk_len = numbers.len / task_count;

    var group: Io.Group = .init;
    // If anything below fails, stop the tasks before `partial` and
    // `numbers` go away. After a successful `await` this does nothing.
    defer group.cancel(io);

    for (0..task_count) |t| {
        const start = t * chunk_len;
        const end = if (t == task_count - 1) numbers.len else start + chunk_len;
        group.async(io, sumChunk, .{ numbers[start..end], &partial[t] });
    }
    // Wait for every task in the group.
    try group.await(io);

    var total: u64 = 0;
    for (partial, 0..) |p, t| {
        std.debug.print("chunk {d}: {d}\n", .{ t, p });
        total += p;
    }
    std.debug.print("total:   {d}\n", .{total});
}
```

```console
$ zig run examples/ch15/group.zig
chunk 0: 31250125000
chunk 1: 93750125000
chunk 2: 156250125000
chunk 3: 218750125000
total:   500000500000
```

- `var group: Io.Group = .init;` creates an empty group. It needs no allocator and no `deinit`.
- `group.async(io, function, args)` and `group.concurrent(io, function, args)` work like `io.async` and `io.concurrent` but return no `Future`. The function's return type must coerce to `Io.Cancelable!void` (`void` does). A group task can't return a value, so each task writes its result through a pointer.
- `group.await(io)` waits for every task in the group. It returns `error.Canceled` if *this* task is canceled while waiting.
- `group.cancel(io)` asks every task in the group to stop, then waits for them all. It is the group's cleanup: `defer group.cancel(io);` right after creating the group guarantees that no task outlives the data it points to, even if the code in between returns an error. After a successful `await`, the group is empty and `cancel` does nothing.
- Each task writes only to its own `partial[t]`, and the main thread reads `partial` only after `await`, so no two threads touch the same memory at the same time. That is the simplest way to stay safe, and seek uses it too.

## Channels: `Io.Queue`

To pass values between running tasks, use an **`Io.Queue(T)`**: a fixed-size, thread-safe FIFO that other languages call a *channel*:

`examples/ch15/queue.zig`

```zig
const std = @import("std");
const Io = std.Io;

fn producer(io: Io, queue: *Io.Queue(u32)) Io.Cancelable!void {
    // Closing tells the consumer that nothing more is coming.
    defer queue.close(io);
    for (1..6) |i| {
        // Blocks while the queue is full.
        queue.putOne(io, @intCast(i * i)) catch |err| switch (err) {
            error.Closed => return,
            error.Canceled => |e| return e,
        };
        std.debug.print("put {d}\n", .{i * i});
    }
}

fn consumer(io: Io, queue: *Io.Queue(u32), sum: *u32) Io.Cancelable!void {
    while (true) {
        // Blocks while the queue is empty. Once it is closed *and* empty,
        // getOne returns error.Closed.
        const n = queue.getOne(io) catch |err| switch (err) {
            error.Closed => return,
            error.Canceled => |e| return e,
        };
        std.debug.print("        got {d}\n", .{n});
        sum.* += n;
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    // The queue doesn't allocate: it uses the buffer you give it, so it
    // holds at most 2 items at a time.
    var buffer: [2]u32 = undefined;
    var queue: Io.Queue(u32) = .init(&buffer);
    var sum: u32 = 0;

    // Each side waits for the other, so they must really run at the same
    // time: `concurrent`, not `async`.
    var group: Io.Group = .init;
    defer group.cancel(io);
    try group.concurrent(io, producer, .{ io, &queue });
    try group.concurrent(io, consumer, .{ io, &queue, &sum });
    try group.await(io);

    std.debug.print("sum = {d}\n", .{sum});
}
```

```console
$ zig run examples/ch15/queue.zig
put 1
put 4
put 9
        got 1
        got 4
        got 9
        got 16
put 16
put 25
        got 25
sum = 55
```

The interleaving changes from run to run; only `sum = 55` is certain. `got 16` before `put 16` just means the consumer printed before the producer did.

- `Io.Queue(u32).init(&buffer)` uses the buffer you give it, so a queue never allocates. Its capacity is the buffer's length.
- `putOne` blocks while the queue is full, and `getOne` blocks while it is empty. Both are cancelation points (see below), so they can return `error.Canceled`.
- `close` marks the end of the stream. After that, `put` fails with `error.Closed`, and `get` returns the remaining items, then `error.Closed`. Closing in a `defer` releases the consumer even if the producer fails.
- Batch versions `put(io, items, min)` and `get(io, buffer, min)` move up to a slice of items at a time.
- The producer and consumer wait for each other, so they are started with `concurrent`.

## Coordinating tasks

`std.Io` has the classic synchronization primitives. They work with any `Io` implementation and take `io` as a parameter. Each blocking call has a cancelable form that can return `error.Canceled` and an `...Uncancelable` form.

### `Io.Event`: a one-time signal

An `Io.Event` starts `.unset`. `set` flips it to set for good and wakes every task blocked in `wait`:

`examples/ch15/event.zig`

```zig
const std = @import("std");
const Io = std.Io;

fn runner(io: Io, id: usize, start: *Io.Event) Io.Cancelable!void {
    // Blocks until the event is set. If it already is, returns at once.
    try start.wait(io);
    std.debug.print("runner {d} goes\n", .{id});
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var start: Io.Event = .unset;
    var group: Io.Group = .init;
    defer group.cancel(io);
    for (1..4) |id| try group.concurrent(io, runner, .{ io, id, &start });

    std.debug.print("ready...\n", .{});
    try io.sleep(.fromMilliseconds(100), .awake);
    std.debug.print("set!\n", .{});
    // Wakes every waiting task, and every future `wait` returns at once.
    start.set(io);

    try group.await(io);
}
```

```console
$ zig run examples/ch15/event.zig
ready...
set!
runner 1 goes
runner 2 goes
runner 3 goes
```

The runners may go in any order. An `Event` is a 4-byte enum, so one per item of work costs almost nothing; seek does exactly that. `reset` makes an event reusable, but only when nobody is waiting on it.

### `Io.Mutex` and `Io.Condition`

A **mutex** (*mutual exclusion* lock) protects data that several tasks change. One task at a time holds it; the others block in `lock` until it is released. A **condition variable** lets a task sleep until another task changes the protected data:

`examples/ch15/condition.zig`

```zig
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
```

```console
$ zig run examples/ch15/condition.zig
2 jobs done
all 4 jobs done
```

- `mutex.lockUncancelable(io)` followed by `defer mutex.unlock(io)` is the standard shape: the lock is released however the block ends. `try mutex.lock(io)` is the cancelable form; functions that return `void` can't `try`, so they use `lockUncancelable`.
- `cond.wait(io, &mutex)` must be called with the mutex held. It releases the mutex while sleeping and locks it again before returning.
- Always wait in a `while` loop that re-checks the condition. A wakeup only means "something changed", not "what you are waiting for is true".
- `signal` wakes one waiter, and `broadcast` wakes all of them.

### `Io.Semaphore`: at most N at a time

A **semaphore** is a counter of permits. `wait` takes one, blocking while there are none, and `post` gives one back. Use it for "at most N of these at once", such as limiting open connections:

`examples/ch15/semaphore.zig`

```zig
const std = @import("std");
const Io = std.Io;

var running: std.atomic.Value(usize) = .init(0);
var most_running: std.atomic.Value(usize) = .init(0);

fn job(io: Io, id: usize, slots: *Io.Semaphore) Io.Cancelable!void {
    // Take a permit; blocks while there are none left.
    try slots.wait(io);
    // Give it back when done, so the next job can start.
    defer slots.post(io);

    const now = running.fetchAdd(1, .monotonic) + 1;
    _ = most_running.fetchMax(now, .monotonic);
    std.debug.print("job {d} starts ({d} running)\n", .{ id, now });
    try io.sleep(.fromMilliseconds(50), .awake);
    _ = running.fetchSub(1, .monotonic);
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    // Two permits: at most two jobs hold one at any moment.
    var slots: Io.Semaphore = .{ .permits = 2 };

    var group: Io.Group = .init;
    defer group.cancel(io);
    for (1..7) |id| try group.concurrent(io, job, .{ io, id, &slots });
    try group.await(io);

    std.debug.print("at most {d} jobs ran at once\n", .{most_running.load(.monotonic)});
}
```

```console
$ zig run examples/ch15/semaphore.zig
job 3 starts (1 running)
job 5 starts (2 running)
job 6 starts (2 running)
job 4 starts (2 running)
job 2 starts (2 running)
job 1 starts (2 running)
at most 2 jobs ran at once
```

The job order varies. `Io.Semaphore` is built from a `Mutex` and a `Condition` in `lib/std/Io/Semaphore.zig`, a short file worth reading now. The counters in the example are atomics, covered shortly.

## Cancelation

`future.cancel(io)` is `await` plus a request: "please stop". Cancelation in Zig is **cooperative**: nothing is killed. Instead, the task's next **cancelation point** returns `error.Canceled`. A cancelation point is any `Io` function with `error.Canceled` in its error set: `sleep`, file reads, `Queue.getOne`, `Event.wait`, `Mutex.lock`, and so on. The task returns, running its `defer`s, and `cancel` returns the task's result:

`examples/ch15/cancel.zig`

```zig
const std = @import("std");
const Io = std.Io;

/// Ticks forever. Every `io.sleep` is a cancelation point: once someone
/// asks this task to stop, the next sleep returns error.Canceled.
fn ticker(io: Io) Io.Cancelable!void {
    defer std.debug.print("ticker: cleaning up\n", .{});
    var n: usize = 0;
    while (true) {
        try io.sleep(.fromMilliseconds(40), .awake);
        n += 1;
        std.debug.print("tick {d}\n", .{n});
    }
}

/// Pure computation has no cancelation points of its own, so it checks
/// for a cancelation request now and then.
fn crunch(io: Io) Io.Cancelable!u64 {
    var x: u64 = 0;
    var i: u64 = 0;
    while (true) : (i += 1) {
        x +%= i *% i;
        if (i % 1_000_000 == 0) try io.checkCancel();
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var tick = try io.concurrent(ticker, .{io});
    try io.sleep(.fromMilliseconds(100), .awake);
    // Request cancelation, then wait for the task to finish.
    tick.cancel(io) catch |err| std.debug.print("ticker returned {t}\n", .{err});

    var work = try io.concurrent(crunch, .{io});
    try io.sleep(.fromMilliseconds(20), .awake);
    if (work.cancel(io)) |x| {
        std.debug.print("crunch finished: {d}\n", .{x});
    } else |err| {
        std.debug.print("crunch returned {t}\n", .{err});
    }
}
```

```console
$ zig run examples/ch15/cancel.zig
tick 1
tick 2
ticker: cleaning up
ticker returned Canceled
crunch returned Canceled
```

- The ticker's `try io.sleep(...)` returned `error.Canceled`, `try` propagated it, and the `defer` ran as for any other error.
- `crunch` never calls `Io`, so on its own it would never notice the request. Long computations call `io.checkCancel()` now and then: a cancelation point that does nothing else.
- The request is delivered **once**. If a task catches `error.Canceled` and carries on, later cancelation points won't fail. Ignoring `error.Canceled` is usually a bug: let it propagate.
- The `...Uncancelable` variants, like `waitUncancelable` and `lockUncancelable`, are never cancelation points. Use them when the task must not be interrupted there, or when nothing will ever cancel it.
- `cancel` and `await` are fine on a finished task: calling either again just returns the stored result. So `defer future.cancel(io)` is a safe cleanup line even after an `await`.

You saw `error.Canceled` in the `Io.Cancelable` error sets of earlier chapters. This is where it comes from.

## Threads and atomics

Under `Io` are ordinary OS threads, which you can create directly with **`std.Thread`**:

`examples/ch15/threads.zig`

```zig
const std = @import("std");

var hits: std.atomic.Value(usize) = .init(0);

fn work(id: usize, rounds: usize) void {
    for (0..rounds) |_| _ = hits.fetchAdd(1, .monotonic);
    std.debug.print("thread {d} done\n", .{id});
}

pub fn main() !void {
    const cpus = std.Thread.getCpuCount() catch 1;
    std.debug.print("{d} CPUs\n", .{cpus});

    var threads: [3]std.Thread = undefined;
    for (&threads, 0..) |*t, id| {
        // A real OS thread. `args` is a tuple matching `work`'s parameters.
        t.* = try std.Thread.spawn(.{}, work, .{ id, 1000 });
    }
    // Every spawned thread must be joined (or detached).
    for (threads) |t| t.join();

    std.debug.print("hits = {d}\n", .{hits.load(.monotonic)});
}
```

```console
$ zig run examples/ch15/threads.zig
32 CPUs
thread 0 done
thread 1 done
thread 2 done
hits = 3000
```

- `std.Thread.spawn(config, function, args)` starts a thread. `.{}` takes the default config (16 MiB of stack). It fails with errors such as `error.ThreadQuotaExceeded`.
- Every thread must be either `join`ed (waited for) or `detach`ed. A `std.Thread` can't return a value: write results through a pointer, as with groups.
- `std.Thread.getCpuCount()` returns the number of logical CPUs. It can fail, so programs fall back to 1.

Prefer `Io` tasks in most code; `std.Thread` ties you to OS threads. Use raw threads for a long-lived thread that you control yourself.

### `std.atomic.Value`

`hits` is shared by three threads, so a plain `usize` would be a bug (see the next section). **`std.atomic.Value(T)`** wraps a value so that every access is **atomic**: no thread ever sees it half-updated. Its main operations:

| Operation | Effect |
|---|---|
| `.init(v)` | a new value (not atomic: do it before sharing) |
| `load(order)` / `store(v, order)` | read / write |
| `fetchAdd(n, order)`, `fetchSub`, `fetchMax`, ... | update and return the **old** value, as one step |
| `swap(v, order)` | write and return the old value |
| `cmpxchgStrong(expected, new, ok_order, fail_order)` | write `new` only if the value is `expected`; returns `null` on success, else the actual value |

Every operation takes a **memory order** (`std.lang.AtomicOrder`):

- **`.monotonic`**: the operation itself is atomic, but it makes no promises about *other* memory. Enough for counters and statistics.
- **`.release`** on a store, paired with **`.acquire`** on a load that sees the stored value: everything the storing thread wrote *before* the release is visible to the loading thread *after* the acquire. Use this to *publish* data, such as "the buffer is ready".
- **`.acq_rel`**: both, for read-modify-write operations. **`.seq_cst`**: the strongest, with one global order of all such operations; the safe choice when in doubt.

You rarely publish data with raw atomics. `Event.set`/`wait`, `Mutex.unlock`/`lock`, and `Queue.put`/`get` include the release/acquire pairing: whatever a task wrote before `set` is visible to a task that returns from `wait`.

## Data races

A **data race** happens when two threads access the same memory at the same time, at least one writes, and nothing orders the accesses. Unlike Rust's type system, Zig's doesn't prevent data races at compile time. A data race is undefined behavior, and it often shows up as wrong numbers rather than crashes:

`examples/ch15/race.zig`

```zig
const std = @import("std");

var counter: usize = 0;

fn bump() void {
    for (0..1_000_000) |_| counter += 1;
}

pub fn main(init: std.process.Init) !void {
    var group: std.Io.Group = .init;
    try group.concurrent(init.io, bump, .{});
    try group.concurrent(init.io, bump, .{});
    try group.await(init.io);
    std.debug.print("counter = {d}\n", .{counter});
}
```

```console
$ zig run examples/ch15/race.zig
counter = 1027826
$ zig run examples/ch15/race.zig
counter = 1000000
$ zig run examples/ch15/race.zig
counter = 1041166
```

Two tasks each add one a million times, so the answer should be `2000000`. `counter += 1` is three steps: load, add, store. When both threads load the same old value, both store the same new value, and one increment is lost. Try `10_000` iterations: on many runs one task finishes before the other gets going, the answer comes out right, and **the bug hides**. Bugs like this pass every test and then fail in production.

Two fixes, both correct:

`examples/ch15/race_fixed.zig`

```zig
const std = @import("std");
const Io = std.Io;

// Fix 1: make the counter atomic.
var atomic_counter: std.atomic.Value(usize) = .init(0);

fn bumpAtomic() void {
    for (0..1_000_000) |_| _ = atomic_counter.fetchAdd(1, .monotonic);
}

// Fix 2: keep a plain counter, but only touch it while holding a lock.
var mutex: Io.Mutex = .init;
var locked_counter: usize = 0;

fn bumpLocked(io: Io) void {
    for (0..1_000_000) |_| {
        mutex.lockUncancelable(io);
        defer mutex.unlock(io);
        locked_counter += 1;
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var group: Io.Group = .init;
    try group.concurrent(io, bumpAtomic, .{});
    try group.concurrent(io, bumpAtomic, .{});
    try group.concurrent(io, bumpLocked, .{io});
    try group.concurrent(io, bumpLocked, .{io});
    try group.await(io);
    std.debug.print("atomic = {d}, mutex = {d}\n", .{ atomic_counter.load(.monotonic), locked_counter });
}
```

```console
$ zig run examples/ch15/race_fixed.zig
atomic = 2000000, mutex = 2000000
```

Use an atomic for a lone counter, and a mutex when several values must change together, such as a counter *and* a list.

### ThreadSanitizer

**ThreadSanitizer** (TSan), built into the compiler, instruments every memory access and reports conflicting accesses that aren't ordered. Enable it with `-fsanitize-thread`:

```console
$ zig build-exe -fsanitize-thread examples/ch15/race.zig
$ ./race
==================
WARNING: ThreadSanitizer: data race (pid=319818)
  Read of size 8 at 0x57a486e35990 by thread T2:
    #0 race.bump …/race.zig:6 (race+0x1f4ba5)
    #1 Io.Group.concurrent__func_769.TypeErased.start …/Io.zig:1389 (race+0x1f4a5d)
    …
  Previous write of size 8 at 0x57a486e35990 by thread T1:
    #0 race.bump …/race.zig:6 (race+0x1f4bd2)
    …
SUMMARY: ThreadSanitizer: data race …/race.zig:6 in race.bump
==================
counter = 2000000
ThreadSanitizer: reported 2 warnings
$ echo $?
66
```

(Shortened; the real report also shows where each thread was created.) This run printed the *right* answer because TSan slows the program down, yet TSan still reported the race: it detects the unordered accesses themselves, not wrong results. The program exits with status 66. On `race_fixed.zig` it reports nothing. In a `build.zig`, set `.sanitize_thread = true` in the options passed to `b.createModule`.

TSan makes a program several times slower and only sees the code paths that actually run. Use it on tests and debug runs, not in release builds.

## Which allocators are thread-safe?

Memory is shared state too. The documentation comments in 0.17 say:

- **`init.gpa`** is thread-safe: any task or thread can allocate and free with it.
- **`init.arena`** is thread-safe.
- A **`std.heap.ArenaAllocator`** you create allocates thread-safely if its child allocator is thread-safe. **`reset` and `deinit` are not thread-safe**: they free everything, including memory another thread may still be using.
- `std.heap.FixedBufferAllocator` has a separate `threadSafeAllocator()` method; its plain `allocator()` is not thread-safe.

The practical rule, which seek follows: give each worker its own arena, and reset it only from that worker.

## Building seek: searching files in parallel

seek's search loop suits parallel work: every file is independent. The hard part is the output. If each worker printed matches as it found them, lines from different files would mix and the file order would change from run to run. Locking stdout around each file would keep lines together, but files would still come out in random order.

seek keeps its output **deterministic** instead:

1. `searchAll` gives every file a `FileResult` slot: an `Io.Writer.Allocating` that collects that file's output, the match count, any error, and an `Io.Event` named `done`.
2. Up to `-j` workers take file indices from a shared atomic counter. Each one searches its file into that file's own writer, then sets the file's `done` event.
3. The main thread walks the files *in order*. For each one, it waits for `done`, prints the buffered output, reports any error, and records the stats.

No two threads ever write the same memory: workers write only to the results they took, and the main thread reads a result only after its `done` is set. The `Event` supplies the release/acquire ordering that makes the worker's writes visible. The stats need no lock, because only the main thread touches them.

The cost: a file's output waits in memory until every earlier file is printed, and one slow early file holds up everything after it. For a grep, that trade is worth it.

The milestone: **`-j/--jobs N`** sets the number of workers, one per CPU by default. `-j 1` behaves like before, and every `-j` gives the same output.

### `src/cli.zig`

Add the field after `stats`:

```zig
    stats: bool = false,
    jobs: ?usize = null,
```

its short name, after `max_count`:

```zig
        .max_count = 'm',
        .jobs = 'j',
```

and its description:

```zig
        .stats = "print statistics to stderr when done",
        .jobs = "search N files at a time (default: number of CPUs)",
```

The generic parser from [Chapter 12](12-comptime.md) already handles `?usize`, so this is the whole change.

### `src/search.zig`

Add `FileResult` after `binary_probe_len`:

```zig
/// What searching one file produced. A worker fills it in, then sets
/// `done`; the main thread waits for `done` before reading anything else.
const FileResult = struct {
    /// Everything the printer wrote for this file.
    output: Io.Writer.Allocating,
    /// Selected lines; null for a binary file or after an error.
    matches: ?usize = null,
    err: ?anyerror = null,
    done: Io.Event = .unset,
};
```

The `Searcher` doc comment gains a paragraph, the scratch arena moves out of the `Searcher`, and a `jobs` field takes its place:

```zig
/// Searches files for a pattern and remembers how it went.
///
/// Use it in two phases: `addPath` for every path to search, then
/// `searchAll`.
///
/// `searchAll` searches up to `jobs` files at once but prints the results
/// in the order the files were added.
///
/// Memory: the Searcher owns a copy of the pattern and of every path
/// (allocated with `gpa`). Call `deinit` to free everything.
pub const Searcher = struct {
    gpa: Allocator,
    io: std.Io,
    pattern: []const u8,
    options: Options,
    /// Decides whether a line matches; refers to `pattern`.
    matcher: Matcher,
    printer: Printer,
    /// How many files to search at the same time (-j).
    jobs: usize,
```

The `file_arena` field is gone: one worker would reset a shared arena while another was still using it. In `init`, replace `.file_arena = .init(gpa),` with:

```zig
            // By default, one worker per CPU. `-j 0` would mean "no workers",
            // so we treat it like `-j 1`.
            .jobs = @max(1, options.jobs orelse std.Thread.getCpuCount() catch 1),
```

`options.jobs orelse std.Thread.getCpuCount() catch 1` reads as "the user's number, else the CPU count, else 1". `@max(1, ...)` turns `-j 0` into 1. In `deinit`, delete the `self.file_arena.deinit();` line:

```zig
    pub fn deinit(self: *Searcher) void {
        self.stats.deinit(self.gpa);
        for (self.files.items) |path| self.gpa.free(path);
        self.files.deinit(self.gpa);
        self.gpa.free(self.pattern);
        self.* = undefined; // catch use-after-deinit in safe builds
    }
```

Now the heart of the change. Replace `searchAll` with:

```zig
    /// Searches every queued file and prints the results in order.
    ///
    /// Workers take the next file index from a shared atomic counter and
    /// write each file's output into that file's own `FileResult`. This
    /// thread waits for the results one by one, in order, and prints them,
    /// so the output is the same no matter which worker finishes first.
    pub fn searchAll(self: *Searcher) (Allocator.Error || Io.Writer.Error)!void {
        const files = self.files.items;
        const results = try self.gpa.alloc(FileResult, files.len);
        defer self.gpa.free(results);
        for (results) |*result| result.* = .{ .output = .init(self.gpa) };
        defer for (results) |*result| result.output.deinit();

        var next_index: std.atomic.Value(usize) = .init(0);
        var group: Io.Group = .init;
        // If printing fails we return early while workers are still
        // running. `cancel` asks them to stop and waits until they have, so
        // none of them can touch `results` after it is freed. (Defers run
        // in reverse order: this one runs first.) On success, the workers
        // are finishing anyway.
        defer group.cancel(self.io);

        var started: usize = 0;
        for (0..@min(self.jobs, files.len)) |_| {
            // `concurrent` fails with error.ConcurrencyUnavailable if no
            // thread can be started; fewer workers is fine.
            group.concurrent(self.io, worker, .{ self, results, &next_index }) catch break;
            started += 1;
        }
        // No workers at all: search everything on this thread first.
        if (started == 0) worker(self, results, &next_index);

        for (files, results) |path, *result| {
            // Not a cancelation point: nobody cancels the main thread.
            result.done.waitUncancelable(self.io);
            try self.stdout.writeAll(result.output.written());
            // Free this file's output now instead of at the end.
            result.output.deinit();
            result.output = .init(self.gpa);

            if (result.err) |err| switch (err) {
                // The output is an Allocating writer: it only fails when
                // it runs out of memory.
                error.OutOfMemory, error.WriteFailed => return error.OutOfMemory,
                else => try self.reportError(path, err),
            };
            // Binary files (null) are skipped silently.
            const matches = result.matches orelse continue;
            if (matches > 0) self.matched_any = true;
            // Only this thread touches the stats, so they need no locking.
            try self.stats.record(self.gpa, displayName(path), matches);
        }
    }
```

Things to notice:

- `results` is one allocation, freed by a `defer`; a second `defer` deinitializes every writer. `for (results) |*result| result.* = ...` initializes each element through a pointer.
- `defer group.cancel(self.io)` is declared *after* those two `defer`s, so it runs *before* them (defers run in reverse order). If `writeAll` fails halfway, the workers are stopped and waited for before `results` is freed. Otherwise a worker could write into freed memory.
- `group.concurrent(...) catch break` starts as many workers as it can; one worker is as correct as eight. If none started, the main thread does all the searching itself before printing. The workers wait on nothing but files, so `group.async` would also be correct, but when `async` ran inline, the main thread would search every file before printing the first. With `concurrent`, printing starts as soon as the first file is done.
- The main thread uses `waitUncancelable`. Nothing cancels it, so a cancelable `wait` would only add an impossible error case.
- After printing a file, its writer is freed and replaced by an empty one. That releases memory early and leaves the `defer` something valid to `deinit`.
- `error.WriteFailed` from a worker can only come from its `Allocating` writer, which fails only when out of memory, so it is reported as `error.OutOfMemory`.

The worker is new. Add it after `searchAll`:

```zig
    /// Runs on a worker thread until no files are left. Many workers share
    /// one Searcher, so they only read from it (`*const`), and each has
    /// its own scratch arena: resetting an arena is not thread-safe.
    fn worker(self: *const Searcher, results: []FileResult, next_index: *std.atomic.Value(usize)) void {
        var arena: std.heap.ArenaAllocator = .init(self.gpa);
        defer arena.deinit();
        while (true) {
            // Adds 1 and returns the old value in one indivisible step, so
            // no two workers ever get the same index. `.monotonic` is
            // enough: the counter only hands out numbers, it doesn't
            // publish any other data.
            const i = next_index.fetchAdd(1, .monotonic);
            if (i >= results.len) return;

            const result = &results[i];
            if (self.searchFile(self.files.items[i], &result.output.writer, arena.allocator())) |matches| {
                result.matches = matches;
            } else |err| {
                // seek is shutting down (see `group.cancel` in searchAll).
                if (err == error.Canceled) return;
                result.err = err;
            }
            _ = arena.reset(.retain_capacity);
            // `set` publishes everything written to `result` above: after
            // `wait` returns, the main thread is guaranteed to see it.
            result.done.set(self.io);
        }
    }
```

- `self: *const Searcher`: all workers share one `Searcher`, so they only read from it, and the compiler enforces that: setting `self.had_error` in a worker wouldn't compile. Errors travel back in `result.err` instead.
- `fetchAdd(1, .monotonic)` returns the old value and increments the counter in one indivisible step, so every index goes to exactly one worker. The counter publishes no other data (`done.set` does that), so `.monotonic` is enough.
- The arena is created per worker and reset per file, by its owner only.
- `error.Canceled` means `searchAll` called `group.cancel`. The worker just returns, since no one is waiting for the result.

`searchFile` used to report its own errors and record its own stats. Both must now happen on the main thread, in order, so it returns its result instead and takes the writer and arena as parameters:

```zig
    /// Searches one file ("-" is standard input), writing to `out`. Returns
    /// the number of selected lines, or null for a binary file.
    fn searchFile(self: *const Searcher, path: []const u8, out: *Io.Writer, arena: Allocator) !?usize {
        const is_stdin = std.mem.eql(u8, path, "-");
        const file: Io.File = if (is_stdin) .stdin() else try Io.Dir.cwd().openFile(self.io, path, .{});
        defer if (!is_stdin) file.close(self.io);

        // Stdin may be a pipe, which can only be read front to back
        // ("streaming"); regular files can be read at any position. The
        // buffer lives on this worker's stack.
        var buffer: [read_buffer_len]u8 = undefined;
        var file_reader = if (is_stdin) file.readerStreaming(self.io, &buffer) else file.reader(self.io, &buffer);

        return self.searchReader(&file_reader.interface, displayName(path), out, arena) catch |err| switch (err) {
            // The Io.Reader interface only says "read failed"; the concrete
            // File.Reader remembers why.
            error.ReadFailed => file_reader.err.?,
            else => |e| e,
        };
    }
```

The `buffer` is on the worker's own stack (16 MiB by default), so 64 KiB per file is fine.

`searchReader` gets the same two parameters, uses them in place of `self.stdout` and `self.file_arena`, and calls `printer.fileDone` itself. In ch14, `searchFile` made that call:

```zig
    /// Reads `reader` line by line, hands every selected line to the
    /// printer, and returns how many lines were selected, or null if the
    /// input looks binary. A line is selected when it matches, or, with -v,
    /// when it doesn't. Stops early at the -m limit. `arena` holds lines
    /// too long for the reader's buffer.
    fn searchReader(
        self: *const Searcher,
        reader: *Io.Reader,
        path: []const u8,
        out: *Io.Writer,
        arena: Allocator,
    ) (error{ReadFailed} || Allocator.Error || Io.Writer.Error)!?usize {
        if (try looksBinary(reader)) return null;

        // For -l, one selected line answers the question. Comparing a
        // tagged union with an enum literal compares the active tag.
        const limit: usize = if (self.printer == .files) 1 else self.options.max_count orelse std.math.maxInt(usize);

        var long_line: Io.Writer.Allocating = .init(arena);
        var matches: usize = 0;
        var line_number: usize = 1;
        while (matches < limit) : (line_number += 1) {
            const line = try nextLine(reader, &long_line) orelse break;
            const found = self.matcher.find(line) != null;
            if (found == self.options.invert) continue;
            matches += 1;
            try self.printer.line(out, path, line_number, line);
        }
        try self.printer.fileDone(out, path, matches);
        return matches;
    }
```

Finally, the `"(standard input)"` naming moves into a helper after the `Searcher`, because both `searchFile` and `searchAll` need it:

```zig
/// How a path appears in the output.
fn displayName(path: []const u8) []const u8 {
    return if (std.mem.eql(u8, path, "-")) "(standard input)" else path;
}
```

`main.zig` doesn't change.

### Checkpoint

```console
$ zig build
$ ./zig-out/bin/seek -j 1 -n fox testdata
testdata/notes/log.txt:1:2024-01-01 saw a fox near the barn
testdata/notes/log.txt:3:2024-01-03 fox tracks in the snow
testdata/notes/todo.md:2:- feed the fox
testdata/poem.txt:1:The quick brown fox
$ ./zig-out/bin/seek -j 8 -n fox testdata
testdata/notes/log.txt:1:2024-01-01 saw a fox near the barn
testdata/notes/log.txt:3:2024-01-03 fox tracks in the snow
testdata/notes/todo.md:2:- feed the fox
testdata/poem.txt:1:The quick brown fox
$ ./zig-out/bin/seek -j 0 -c fox testdata
testdata/notes/log.txt:2
testdata/notes/todo.md:1
testdata/poem.txt:1
$ ./zig-out/bin/seek --stats -j 4 -l -i fox testdata
testdata/notes/log.txt
testdata/notes/todo.md
testdata/poem.txt
--- stats ---
files searched: 3
files matched:  3
matching lines: 3
elapsed:        1.352ms
top files:
     1  testdata/notes/log.txt
     1  testdata/notes/todo.md
     1  testdata/poem.txt
$ ./zig-out/bin/seek fox testdata | head -n 2
testdata/notes/log.txt:2024-01-01 saw a fox near the barn
testdata/notes/log.txt:2024-01-03 fox tracks in the snow
$ ./zig-out/bin/seek -j x fox testdata; echo "exit $?"
seek: invalid value 'x' for -j
usage: seek [OPTIONS] PATTERN [PATH ...]
exit 2
$ ./zig-out/bin/seek fox testdata/nope testdata/poem.txt
seek: testdata/nope: FileNotFound
testdata/poem.txt:The quick brown fox
```

Every `-j` gives the same output, and errors still appear in their place in the order. `seek -h` lists the new option:

```text
  -j, --jobs N                   search N files at a time (default: number of CPUs)
```

For three tiny files, threads cost more than they save: run the `--stats` line with `-j 1` and with the default, and the default is usually a little slower. Starting threads takes time, and there is almost no work to share.

### Is it faster?

Search something bigger, like the standard library sources in the `lib/std` directory next to your `zig` binary (adjust the path). These timings are from a 32-core machine and a Debug build of seek:

```console
$ STD=~/.local/zig-x86_64-linux-0.17.0/lib/std
$ ./zig-out/bin/seek --stats -j 1 -c errdefer $STD 2>&1 >/dev/null | grep -E 'searched|elapsed'
files searched: 563
elapsed:        346.615ms
$ ./zig-out/bin/seek --stats -j 8 -c errdefer $STD 2>&1 >/dev/null | grep -E 'searched|elapsed'
files searched: 563
elapsed:        55.683ms
```

(`2>&1 >/dev/null` sends the stats on stderr into the pipe and throws away the normal output.)

| `-j` | 1 | 2 | 4 | 8 | 32 |
|---|---|---|---|---|---|
| elapsed (Debug) | 347 ms | 173 ms | 89 ms | 56 ms | 50 ms |

Two workers halve the time and four halve it again. Then the gains flatten out, as the file system and the main thread's printing become the limit. The output is identical for every `-j`: compare `./zig-out/bin/seek -j 1 -c errdefer $STD | md5sum` with the same command using `-j 32`.

### Checking seek with ThreadSanitizer

Build seek with TSan and run it on many files:

```console
$ zig build-exe -fsanitize-thread -OReleaseFast src/main.zig -femit-bin=seek-tsan
$ ./seek-tsan -j 16 -c errdefer $STD > /dev/null; echo "exit $?"
exit 0
```

No reports. Use `-OReleaseFast` here. In Debug and ReleaseSafe builds, `init.gpa` is Zig's checking allocator (`std.heap.SafeAllocator`), and with 0.17 TSan can report false races on memory that this allocator frees on one thread and hands out again on another, many inside `lib/std/heap/SafeAllocator.zig` (try a search with many matches, such as `-n e`). TSan links the C library, so in a `-OReleaseFast` build `init.gpa` is the C library's `malloc`, which TSan understands, and the same seek code runs clean. Delete `seek-tsan` when you are done.

The complete project at this point is in `project/ch15/`.

## Summary

- `std.Io` is the concurrency interface. `init.io` is an `Io.Threaded` with a thread pool. Zig 0.17 has no `std.Thread.Pool`.
- `io.async` returns a `Future` and **may** run the function inline. `io.concurrent` **must** run it concurrently and can fail with `error.ConcurrencyUnavailable`. Use `concurrent` when the task and the caller wait for each other. Await or cancel every `Future`.
- `Io.Group` runs many tasks. `group.await` waits for all of them, and `defer group.cancel(io)` makes sure none outlives its data.
- `Io.Queue(T)` is a fixed-size channel over your own buffer, with `close` to end the stream. `Event`, `Mutex`, `Condition`, and `Semaphore` coordinate tasks. Each blocking call has a cancelable and an `...Uncancelable` form.
- Cancelation is cooperative: the next cancelation point returns `error.Canceled`. Let it propagate, and call `checkCancel` in long computations.
- `std.Thread.spawn`/`join` gives you raw threads. `std.atomic.Value` gives atomic operations with memory orders: `.monotonic` for counters, release/acquire to publish data.
- Zig doesn't prevent data races. Avoid shared mutable state. Where you can't, use an atomic or a mutex. Test with `-fsanitize-thread`.
- seek searches with `-j` workers, but its output is deterministic: per-file buffers, per-file `Event`s, and printing in order on the main thread.

## Exercises

1. **Raw threads.** Rewrite `examples/ch15/group.zig` with `std.Thread.spawn` and `join` instead of an `Io.Group`.

   <details><summary>Solution</summary>

   ```zig
   const std = @import("std");

   fn sumChunk(chunk: []const u64, out: *u64) void {
       var total: u64 = 0;
       for (chunk) |n| total += n;
       out.* = total;
   }

   pub fn main(init: std.process.Init) !void {
       const gpa = init.gpa;

       const numbers = try gpa.alloc(u64, 1_000_000);
       defer gpa.free(numbers);
       for (numbers, 1..) |*n, i| n.* = i;

       const thread_count = 4;
       var partial: [thread_count]u64 = undefined;
       var threads: [thread_count]std.Thread = undefined;
       const chunk_len = numbers.len / thread_count;

       for (&threads, 0..) |*thread, t| {
           const start = t * chunk_len;
           const end = if (t == thread_count - 1) numbers.len else start + chunk_len;
           thread.* = try std.Thread.spawn(.{}, sumChunk, .{ numbers[start..end], &partial[t] });
       }
       for (threads) |thread| thread.join();

       var total: u64 = 0;
       for (partial) |p| total += p;
       std.debug.print("total: {d}\n", .{total});
   }
   ```

   ```console
   $ zig run thread_sum.zig
   total: 500000500000
   ```

   Spawning can fail, so each `spawn` needs a `try`. A real program would also use an `errdefer` to join the threads already started before returning the error. A group's `defer group.cancel(io)` does that for free.

   </details>

2. **Many consumers.** Change `queue.zig` so one producer sends the numbers 1 to 100 and *three* consumers take from the same queue. Add everything into one shared total, and count the items each consumer handled.

   <details><summary>Solution</summary>

   ```zig
   const std = @import("std");
   const Io = std.Io;

   fn producer(io: Io, queue: *Io.Queue(u32)) Io.Cancelable!void {
       defer queue.close(io);
       for (1..101) |n| {
           queue.putOne(io, @intCast(n)) catch |err| switch (err) {
               error.Closed => return,
               error.Canceled => |e| return e,
           };
       }
   }

   fn consumer(io: Io, queue: *Io.Queue(u32), total: *std.atomic.Value(u32), count: *u32) Io.Cancelable!void {
       while (true) {
           const n = queue.getOne(io) catch |err| switch (err) {
               error.Closed => return,
               error.Canceled => |e| return e,
           };
           _ = total.fetchAdd(n, .monotonic);
           count.* += 1;
       }
   }

   pub fn main(init: std.process.Init) !void {
       const io = init.io;

       var buffer: [4]u32 = undefined;
       var queue: Io.Queue(u32) = .init(&buffer);
       var total: std.atomic.Value(u32) = .init(0);
       var counts: [3]u32 = @splat(0);

       var group: Io.Group = .init;
       defer group.cancel(io);
       try group.concurrent(io, producer, .{ io, &queue });
       for (&counts) |*count| try group.concurrent(io, consumer, .{ io, &queue, &total, count });
       try group.await(io);

       std.debug.print("items per consumer: {any}\n", .{counts});
       std.debug.print("total = {d}\n", .{total.load(.monotonic)});
   }
   ```

   ```console
   $ zig run consumers.zig
   items per consumer: { 66, 17, 17 }
   total = 5050
   ```

   The split changes from run to run; the total never does. Each `getOne` hands an item to exactly one consumer. The shared total is an atomic, and each consumer's count has its own slot, read only after `await`. `-fsanitize-thread` reports nothing.

   </details>

3. **Predict the deadlock.** In `queue.zig`, replace both `try group.concurrent(...)` calls with `group.async(...)` (no `try`: `Group.async` can't fail). What happens with `init.io`? Then replace `const io = init.io;` with:

   ```zig
       var single: Io.Threaded = .init_single_threaded;
       const io = single.io();
       _ = init;
   ```

   What happens now, and why?

   <details><summary>Solution</summary>

   With `init.io`, it still prints `sum = 55`: the pool had free threads, so both tasks really ran at the same time. With the single-threaded `Io`, it prints

   ```text
   put 1
   put 4
   ```

   and hangs forever (press Ctrl+C). `group.async(io, producer, ...)` ran the producer inline. It filled the two-slot queue, then blocked in `putOne` waiting for a consumer that hadn't been started and never would be. The program works only when the `Io` happens to have a spare thread: a bug, even if it never shows on your machine. With `concurrent`, the single-threaded `Io` fails straight away with `error.ConcurrencyUnavailable` instead.

   </details>

4. **Work from a queue.** In seek, replace the atomic `next_index` counter with an `Io.Queue(usize)`. `searchAll` puts every file index into the queue and closes it, and the workers take indices until the queue is closed. Check that the output is unchanged for `-j 1` and `-j 8`.

   <details><summary>Solution</summary>

   In `searchAll`, replace the `next_index` line with:

   ```zig
           // Every file index goes into the queue up front, then the queue is
           // closed: workers take indices until `getOne` says error.Closed.
           const queue_buffer = try self.gpa.alloc(usize, files.len);
           defer self.gpa.free(queue_buffer);
           var queue: Io.Queue(usize) = .init(queue_buffer);
           for (0..files.len) |i| {
               // The buffer has room for every index and the queue isn't
               // closed yet, so this can neither block nor fail.
               queue.putOneUncancelable(self.io, i) catch unreachable;
           }
           queue.close(self.io);
   ```

   pass `&queue` instead of `&next_index` where `searchAll` starts or calls `worker`, and change the start of `worker` (the rest stays the same):

   ```zig
       fn worker(self: *const Searcher, results: []FileResult, queue: *Io.Queue(usize)) void {
           var arena: std.heap.ArenaAllocator = .init(self.gpa);
           defer arena.deinit();
           while (true) {
               // error.Closed: no files left. error.Canceled: seek is
               // shutting down.
               const i = queue.getOne(self.io) catch return;
   ```

   The buffer is freed by a `defer` declared before `defer group.cancel`, so it outlives the workers. A queue could feed workers while files are still being discovered, and `getOne` is a cancelation point. The atomic counter is cheaper and needs no allocation, so for a list that is complete before the search starts, it fits better. That is why seek uses it.

   </details>

5. **Find the bug.** A colleague "simplified" the body of seek's worker loop:

   ```zig
               const result = &results[i];
               const matches = self.searchFile(self.files.items[i], &result.output.writer, arena.allocator()) catch |err| {
                   if (err == error.Canceled) return;
                   result.err = err;
                   continue;
               };
               result.matches = matches;
               _ = arena.reset(.retain_capacity);
               result.done.set(self.io);
   ```

   `seek fox testdata` works fine. What does `seek fox testdata/nope testdata/poem.txt` do? Fix it without repeating any code.

   <details><summary>Solution</summary>

   It hangs, printing nothing. Opening `testdata/nope` fails, and the `catch` block records the error and `continue`s, skipping `result.done.set`, so the main thread waits forever for file 0's `done`. (The arena isn't reset either.) A `defer` inside a loop body runs at the end of *every* iteration, including one cut short by `continue`:

   ```zig
               const result = &results[i];
               // Runs at the end of every iteration, however it ends.
               defer result.done.set(self.io);
               defer _ = arena.reset(.retain_capacity);
               const matches = self.searchFile(self.files.items[i], &result.output.writer, arena.allocator()) catch |err| {
                   if (err == error.Canceled) return;
                   result.err = err;
                   continue;
               };
               result.matches = matches;
   ```

   ```console
   $ ./zig-out/bin/seek fox testdata/nope testdata/poem.txt
   seek: testdata/nope: FileNotFound
   testdata/poem.txt:The quick brown fox
   ```

   Every path that takes an index must set its `done`. A missed signal doesn't crash; it hangs, which is harder to debug. Tie the signal to the scope with `defer`.

   </details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-15--concurrency)
