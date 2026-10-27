# Chapter 8 — Memory and Allocators

In most languages a runtime handles memory for you. Zig has no hidden allocations: any function that
needs heap memory takes an **allocator** as a parameter, and you free what you get. That's a bit of
work. In return, you always know where memory comes from, you can pick an allocator per call, and
the safe allocator shows you exactly where you leaked. This chapter covers the `Allocator`
interface, the allocators in `std`, ownership, and cleanup with `defer`, `errdefer`, and
`init`/`deinit`. Then `seek` gets its first module, `search.zig`, with a `Searcher` that owns its
memory.
[Chapter 7](07-structs-enums-unions.md) introduced structs and methods;
[Chapter 9](09-strings-and-formatting.md) works with text.

## Why no hidden allocations

An allocation can fail, takes time, and must be freed. Zig makes all three visible:

- **It can fail.** Allocation returns `error.OutOfMemory`, a normal error you handle with `try` or
  `catch` ([Chapter 5](05-errors-and-optionals.md)). No exceptions, no surprise aborts.
- **It takes time.** A function without an allocator parameter doesn't allocate. The signature
  shows the cost.
- **Someone must free it.** The caller picks the allocator and so the strategy: a general-purpose
  heap, an arena freed all at once, or a fixed buffer on the stack.

You saw this rule in Chapter 6: `++` needs lengths known at compile time, because joining runtime
strings needs new memory, and that needs an allocator.

## The `Allocator` interface

`std.mem.Allocator` is a small struct: a pointer to an allocator's state plus a table of
functions. Every allocator in `std` gives you one through `.allocator()`, so code that takes an
`Allocator` works with all of them. [Chapter 14](14-polymorphism.md) shows how such interfaces are
built.

You've used one since Chapter 3: `init.arena.allocator()` in `main`. `std.process.Init` also gives
you `init.gpa`, a **general-purpose allocator** for memory you free yourself.

`examples/ch08/basics.zig`

```zig
const std = @import("std");

const Point = struct { x: i32, y: i32 };

pub fn main(init: std.process.Init) !void {
    // A general-purpose allocator, set up for us by the start code.
    const gpa = init.gpa;

    // alloc/free: a slice of N items. The contents start undefined.
    const squares = try gpa.alloc(u64, 5);
    defer gpa.free(squares);
    for (squares, 0..) |*sq, i| sq.* = i * i;
    std.debug.print("squares: {any}\n", .{squares});

    // create/destroy: exactly one item, returned as a pointer.
    const p = try gpa.create(Point);
    defer gpa.destroy(p);
    p.* = .{ .x = 3, .y = 4 };
    std.debug.print("point: ({d}, {d})\n", .{ p.x, p.y });

    // dupe: copy a slice into new memory that we own.
    const name = try gpa.dupe(u8, "seek");
    defer gpa.free(name);
    name[0] = 'S';
    std.debug.print("name: {s}\n", .{name});

    // print: format into newly allocated memory.
    const msg = try gpa.print("{s} has {d} letters", .{ name, name.len });
    defer gpa.free(msg);
    std.debug.print("msg: {s}\n", .{msg});

    // realloc: change the size, keeping the contents. The result may live
    // at a new address, so always use the returned slice.
    var buf = try gpa.alloc(u8, 3);
    @memcpy(buf, "abc");
    buf = try gpa.realloc(buf, 6);
    defer gpa.free(buf);
    @memcpy(buf[3..], "def");
    std.debug.print("buf: {s}\n", .{buf});
}
```

```console
$ zig run examples/ch08/basics.zig
squares: { 0, 1, 4, 9, 16 }
point: (3, 4)
name: Seek
msg: Seek has 4 letters
buf: abcdef
```

The methods you'll use most:

| Method | Gives you | Free with |
|---|---|---|
| `alloc(T, n)` | `[]T` with `n` undefined items | `free(slice)` |
| `create(T)` | `*T`, one undefined item | `destroy(ptr)` |
| `dupe(T, slice)` | `[]T`, a copy of `slice` | `free(slice)` |
| `print(fmt, args)` | `[]u8`, formatted text | `free(slice)` |
| `realloc(slice, n)` | the slice resized to `n` (maybe moved) | `free(slice)` |

- **Each returns an error union.** You must `try` or `catch` it, or the compiler stops you:

```console
$ zig run no_try.zig
no_try.zig:5:8: error: type 'error{OutOfMemory}![]u8' does not support indexing
    buf[0] = 'x';
    ~~~^~~
no_try.zig:5:8: note: operand must be an array, slice, tuple, or vector
```

- **Free with the same allocator**, and pass the whole slice you got back (same pointer, same
  length).
- **`defer` right after the allocation.** Put `defer gpa.free(x);` on the next line. Every
  allocation visibly has its free, and it runs on every path out of the scope, including errors.
- `@memcpy(dest, src)` copies between slices of equal length; `@memset(dest, value)` fills one.
- `std.mem.Allocator.Error` is `error{OutOfMemory}`, the only error an allocator returns.

> **New in 0.17:** `allocator.print` replaces `std.fmt.allocPrint` (still there, deprecated). You'll
> see `allocPrint` in older code.

## Leaks, double frees, and the safe allocator

In Debug and ReleaseSafe builds, `init.gpa` is a `std.heap.SafeAllocator`. It records where each
allocation came from, checks your frees, and when `main` returns, reports anything you didn't free:

`examples/ch08/leak.zig`

```zig
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    const kept = try gpa.dupe(u8, "freed properly");
    defer gpa.free(kept);

    // Bug: nobody frees this.
    const lost = try gpa.alloc(u8, 100);
    @memset(lost, 0);

    std.debug.print("done: {s}\n", .{kept});
}
```

```console
$ zig run examples/ch08/leak.zig
done: freed properly
error(SafeAllocator): leaked [addr: 71e79d6c6f80, len: 100 (0x64) align: 1] allocated at: 
…/examples/ch08/leak.zig:10:31: 0x11e8849 in main (leak.zig)
    const lost = try gpa.alloc(u8, 100);
                              ^
…/lib/std/start.zig:827:30: 0x11e93a8 in callMain (std.zig)
    return wrapMain(root.main(.{
                             ^
…/lib/std/start.zig:248:5: 0x11e86e1 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^

$ echo $?
0
```

(Addresses and paths differ on your machine.)

- The report gives the size and a stack trace of the **allocation**, usually enough to find the
  missing `free`.
- **Leaks don't change the exit status**: it's still 0. In tests a leak *does* fail the test (see
  below).
- In ReleaseFast and ReleaseSmall, `init.gpa` is a fast allocator without checks (`smp_allocator`,
  or `c_allocator` when you link libc), so there's no report.

Freeing twice is worse than leaking: the memory may already belong to someone else. The safe
allocator panics with all three stack traces (shortened here):

`examples/ch08/double_free.zig`

```zig
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    const data = try gpa.alloc(u8, 16);
    gpa.free(data);
    gpa.free(data); // Bug: freed twice.
}
```

```console
$ zig run examples/ch08/double_free.zig
thread 281199 panic: double free of [addr: 7127e49faee8, len: 16 (0x10) align: 1]
alloc: 
…/examples/ch08/double_free.zig:6:31: 0x11e87aa in main (double_free.zig)
    const data = try gpa.alloc(u8, 16);
                              ^
…
first free: 
…/examples/ch08/double_free.zig:7:13: 0x11e8843 in main (double_free.zig)
    gpa.free(data);
            ^
…
second free:
…
…/examples/ch08/double_free.zig:8:13: 0x11e8878 in main (double_free.zig)
    gpa.free(data); // Bug: freed twice.
            ^
…
```

It also catches frees of memory it never handed out, and most writes after a free.

### Setting one up yourself

Zig's start code sets up `init.gpa`. If `main` doesn't take `std.process.Init`, or you want a
separate allocator for part of a program, make one:

`examples/ch08/own_gpa.zig`

```zig
const std = @import("std");

pub fn main() !void {
    // Without std.process.Init you set up the allocator yourself.
    var safe: std.heap.SafeAllocator = .init(std.heap.page_allocator, .{});
    // deinit reports leaks and returns how many there were.
    defer _ = safe.deinit();
    const gpa = safe.allocator();

    const words = try gpa.alloc([]const u8, 2);
    defer gpa.free(words);
    words[0] = "hello";
    words[1] = "allocator";
    std.debug.print("{s} {s}\n", .{ words[0], words[1] });
}
```

```console
$ zig run examples/ch08/own_gpa.zig
hello allocator
```

- `SafeAllocator.init(backing, options)` wraps a **backing** allocator that provides the actual
  memory. `std.heap.page_allocator` asks the OS for whole pages.
- `safe` must be a `var`, since allocating changes it. `safe.allocator()` points to it, so `safe`
  must outlive every use of `gpa`.
- `deinit` returns the number of leaks. `_ =` discards it; you could check it instead.

> **New in 0.17:** `SafeAllocator` replaces `std.heap.DebugAllocator`, which still exists but is
> deprecated (its older name, `GeneralPurposeAllocator`, is gone). Most tutorials use
> `var gpa: std.heap.DebugAllocator(.{}) = .init;` and `gpa.deinit() == .leak`.

## Arena allocators

An **arena** takes memory from another allocator and hands it out in pieces. You don't free the
pieces; you free the whole arena with `deinit`, or empty it for reuse with `reset`.

`examples/ch08/arena.zig`

```zig
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    // An arena takes memory from a "child" allocator and frees it all at once.
    var arena_state: std.heap.ArenaAllocator = .init(init.gpa);
    defer arena_state.deinit(); // frees everything allocated below
    const arena = arena_state.allocator();

    for (0..3) |round| {
        // Free this round's memory at the end of the round, but keep the
        // capacity so the next round doesn't have to ask the gpa again.
        defer _ = arena_state.reset(.retain_capacity);

        // Allocate freely; no individual frees needed.
        var used: usize = 0;
        for (0..1000) |i| {
            const line = try arena.print("round {d}, line {d}\n", .{ round, i });
            used += line.len;
        }
        std.debug.print("round {d}: {d} bytes used, capacity {d}\n", .{ round, used, arena_state.queryCapacity() });
    }
}
```

```console
$ zig run examples/ch08/arena.zig
round 0: 17890 bytes used, capacity 24614
round 1: 17890 bytes used, capacity 24614
round 2: 17890 bytes used, capacity 24614
```

- 3000 allocations, no `free`. `defer arena_state.deinit()` releases it all, and the leak checker
  on `init.gpa` stays quiet.
- `reset(.retain_capacity)` forgets every allocation but keeps the memory, so after round 0 the
  arena asks `init.gpa` for nothing. `reset(.free_all)` gives everything back. `reset` returns a
  `bool` (whether keeping the capacity worked), hence `_ =`.
- The exact capacity depends on the build and the backing allocator, so yours may differ. What
  matters is that it stays the same every round.
- `arena.free(x)` is allowed but usually does nothing. It only gives memory back when `x` is the
  most recent allocation.

Use an arena when many allocations **die together**: one request, one file, one game frame, or one
run of a short program. `init.arena` is an arena that lives as long as the process, which is why
`main` could use it without freeing anything.

Don't use an arena for data that grows and shrinks over time. Nothing is reused until the reset,
so memory only goes up.

## Fixed buffers: no heap at all

A `FixedBufferAllocator` hands out pieces of a buffer you give it, often a stack array. When it's
full, allocation fails with `OutOfMemory`:

`examples/ch08/fixed_buffer.zig`

```zig
const std = @import("std");

pub fn main() void {
    // All memory comes from this stack array; no heap at all.
    var buffer: [64]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&buffer);
    const allocator = fba.allocator();

    const a = allocator.dupe(u8, "fits easily") catch unreachable;
    std.debug.print("a = {s}\n", .{a});

    // Ask for more than is left: OutOfMemory is an ordinary error.
    if (allocator.alloc(u8, 100)) |big| {
        std.debug.print("got {d} bytes\n", .{big.len});
    } else |err| {
        std.debug.print("alloc failed: {t}\n", .{err});
    }

    // reset makes the whole buffer available again.
    fba.reset();
    const b = allocator.alloc(u8, 64) catch unreachable;
    std.debug.print("after reset: got {d} bytes\n", .{b.len});
}
```

```console
$ zig run examples/ch08/fixed_buffer.zig
a = fits easily
alloc failed: OutOfMemory
after reset: got 64 bytes
```

- This lets you call code that wants an `Allocator` where there's no heap: embedded systems,
  kernels, or a hot loop that shouldn't touch `malloc`.
- `catch unreachable` says "this can't fail". Fine here: 11 bytes fit in 64. If you're wrong, a
  safe build panics.
- `std.heap.BufferFirstAllocator` uses a fixed buffer first and falls back to another allocator
  when it's full. (Before 0.17 it was `StackFallbackAllocator`.)

## Which allocator?

| Allocator | Use it for |
|---|---|
| `init.gpa` | memory you free yourself, of any size and lifetime. Leak-checked in safe builds. |
| `init.arena` / `std.heap.ArenaAllocator` | many allocations freed together |
| `std.heap.FixedBufferAllocator` | a known upper bound; no heap |
| `std.heap.page_allocator` | large blocks straight from the OS, or as a backing allocator |
| `std.heap.smp_allocator` | a fast thread-safe gpa for release builds (what `init.gpa` becomes) |
| `std.heap.c_allocator` | C's `malloc`/`free`; needs libc to be linked |
| `std.testing.allocator` | in tests: fails the test on leaks |

A common pattern: `init.gpa` for long-lived data you manage, plus an arena for each batch of
short-lived work. `seek` does exactly this by the end of the chapter.

## Ownership: who frees it?

Zig has no garbage collector and no borrow checker. Ownership is a **convention**, written in doc
comments and signatures:

- A function returning allocated memory says so, usually "The caller owns the result". The caller
  frees it with the same allocator.
- A function that needs memory takes an `Allocator` parameter, first or right after `self`. Naming
  it `gpa` says "I'll free what I take"; `arena` says "I won't bother".
- A struct that owns memory gets an `init` that allocates and a `deinit` that frees.

`examples/ch08/ownership.zig`

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Returns "Hello, NAME!". The caller owns the result and must free it
/// with the same allocator.
fn greet(gpa: Allocator, name: []const u8) Allocator.Error![]u8 {
    return gpa.print("Hello, {s}!", .{name});
}

const Pair = struct {
    first: []u8,
    second: []u8,

    /// Copies both strings. If the second copy fails, the first one is
    /// freed again, so the function never leaks.
    fn init(gpa: Allocator, a: []const u8, b: []const u8) Allocator.Error!Pair {
        const first = try gpa.dupe(u8, a);
        errdefer gpa.free(first); // runs only if we return an error below
        const second = try gpa.dupe(u8, b);
        return .{ .first = first, .second = second };
    }

    fn deinit(self: *Pair, gpa: Allocator) void {
        gpa.free(self.first);
        gpa.free(self.second);
        self.* = undefined;
    }
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    const hello = try greet(gpa, "Zig");
    defer gpa.free(hello);
    std.debug.print("{s}\n", .{hello});

    var pair: Pair = try .init(gpa, "left", "right");
    defer pair.deinit(gpa);
    std.debug.print("{s} {s}\n", .{ pair.first, pair.second });

    // A 10-byte buffer: "left" fits, "a much longer string" does not.
    var small: [10]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&small);
    if (Pair.init(fba.allocator(), "left", "a much longer string")) |_| {
        std.debug.print("unexpected success\n", .{});
    } else |err| {
        std.debug.print("Pair.init failed with {t}; end_index after cleanup = {d}\n", .{ err, fba.end_index });
    }
}
```

```console
$ zig run examples/ch08/ownership.zig
Hello, Zig!
left right
Pair.init failed with OutOfMemory; end_index after cleanup = 0
```

### `defer` and `errdefer` for cleanup

You met both in [Chapter 5](05-errors-and-optionals.md). With allocators they're essential:

- **`defer`** runs when the scope exits, for any reason. Use it when the function keeps the memory
  to the end: `const x = try gpa.alloc(...); defer gpa.free(x);`.
- **`errdefer`** runs only when the scope exits **with an error**. Use it when ownership is about to
  pass to the caller: on success the caller owns the memory; if a later step fails, the half-built
  result is cleaned up.

In `Pair.init`, the first `dupe` worked and the second failed. `errdefer gpa.free(first)` gave the
first copy back, so nothing leaked: the fixed buffer's `end_index` (how much is in use) is back to
0. Without the `errdefer`, `"left"` would be lost.

`defer`s and `errdefer`s run in **reverse order**, last first, so you tear down in the opposite
order you built up.

> **New in 0.17:** `errdefer |err| { ... }` (capturing the error) was removed. It no longer parses:
>
> ```console
> $ zig run errdefer_capture.zig
> errdefer_capture.zig:5:14: error: expected block or expression, found '|'
>     errdefer |err| {
>              ^
> ```
>
> If you need the error, use `catch |err|` in the caller.

### `init` and `deinit`

Structs that own memory follow a pattern used throughout `std`:

- `init(gpa, ...)` allocates and returns the value (or an error). Use `errdefer` inside so a failed
  `init` leaves nothing behind.
- `deinit(self: *T)` frees everything the struct owns. `defer` it right after `init`:
  `var pair: Pair = try .init(gpa, ...); defer pair.deinit(gpa);`.
- End `deinit` with `self.* = undefined;`. Safe builds fill the struct with `0xaa` bytes, so use
  after `deinit` tends to crash loudly instead of quietly working.
- The allocator is either stored in the struct (`self.gpa`) or passed to `deinit`, as in
  `Pair.deinit`. `std` does both. Storing costs 16 bytes; passing makes every caller repeat it.

## Testing for leaks

In `test` blocks, use `std.testing.allocator`, a safe allocator that **fails the test** on any
leak:

`examples/ch08/alloc_test.zig`

```zig
const std = @import("std");

/// Returns a new string with the bytes of `s` in reverse order.
/// The caller owns the result.
fn reversed(gpa: std.mem.Allocator, s: []const u8) ![]u8 {
    const out = try gpa.alloc(u8, s.len);
    for (s, 0..) |c, i| out[s.len - 1 - i] = c;
    return out;
}

test "reversed frees properly" {
    const gpa = std.testing.allocator;
    const r = try reversed(gpa, "stressed");
    defer gpa.free(r);
    try std.testing.expectEqualStrings("desserts", r);
}

test "reversed leaks" {
    const gpa = std.testing.allocator;
    const r = try reversed(gpa, "drawer");
    try std.testing.expectEqualStrings("reward", r);
}
```

```console
$ zig test examples/ch08/alloc_test.zig
1/2 alloc_test.test.reversed frees properly...OK
2/2 alloc_test.test.reversed leaks...OK
[SafeAllocator] (err): leaked [addr: 766d97d2a010, len: 6 (0x6) align: 1] allocated at: 
…/examples/ch08/alloc_test.zig:6:30: 0x12545fc in reversed (alloc_test.zig)
    const out = try gpa.alloc(u8, s.len);
                             ^
…/examples/ch08/alloc_test.zig:20:27: 0x1254c20 in test.reversed leaks (alloc_test.zig)
    const r = try reversed(gpa, "drawer");
                          ^
…

All 2 tests passed.
1 errors were logged.
1 tests leaked memory.
error: the following test command failed with exit code 1:
…/test --seed=0xd556aa6
```

Both tests' checks passed, but the leak fails the run. `zig test` runs a file's tests;
[Chapter 16](16-testing.md) covers testing, including `std.testing.FailingAllocator` for checking
your `errdefer`s.

## Building seek: a search module that owns its memory

`seek` allocates `args` and each file's contents, all in `init.arena`, which is freed only at
exit. Fine for three files. With 50,000 files (once seek walks directories in Chapter 11), every
file stays in memory until the end.

The fix:

- Give the `Searcher` its own arena for file contents and **reset it after every file**. Memory use
  then stays at the size of the biggest file.
- Make the `Searcher` own a copy of the pattern, with `init` and `deinit`.
- Use `init.gpa`, so the safe allocator checks that we free everything.

Also, `main.zig` is getting long, so we'll move the searching into its own file.

### Files are structs: `src/search.zig`

Every `.zig` file is a struct. `@import("search.zig")` returns it, and other files can use its
`pub` declarations. Everything else stays private to the file.

Create `src/search.zig`:

```zig
//! Searching files for a pattern. Every file is a struct: this one is a
//! namespace whose `pub` declarations main.zig reaches through @import.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Refuse to load files larger than this into memory.
const max_file_size = 16 * 1024 * 1024;

/// When to highlight matches.
pub const Color = enum { auto, always, never };

/// Everything the user can configure. Every field has a default, so `.{}`
/// is a complete value. The flags arrive in Chapters 9 to 11.
pub const Options = struct {
    ignore_case: bool = false, // -i
    invert: bool = false, // -v
    line_numbers: bool = false, // -n
    count_only: bool = false, // -c
    files_only: bool = false, // -l
    max_count: ?usize = null, // -m N
    hidden: bool = false, // --hidden
    glob: ?[]const u8 = null, // --glob GLOB
    color: Color = .auto, // --color WHEN
};

/// One matching line.
pub const Match = struct {
    path: []const u8,
    line_number: usize,
    text: []const u8,

    /// Writes the match in seek's output format, `path:text`.
    pub fn write(match: Match, out: *std.Io.Writer) std.Io.Writer.Error!void {
        try out.print("{s}:{s}\n", .{ match.path, match.text });
    }
};
```

- `//!` starts a **top-level doc comment**, documenting the file (the struct) itself. `///`
  documents the declaration after it.
- `Color`, `Options` and `Match` move here unchanged except for `pub`. Delete them from `main.zig`.
- `max_file_size` moves too and stays private; only `search.zig` uses it.
- `const Allocator = std.mem.Allocator;` is a common shortcut.

Now the `Searcher`. Add it to the end of `search.zig`:

```zig
/// Searches files for a pattern and remembers how it went.
///
/// Memory: the Searcher owns a copy of the pattern (allocated with `gpa`)
/// and an arena for file contents that is reset after every file, so memory
/// use stays flat no matter how many files we search. Call `deinit` to free
/// everything.
pub const Searcher = struct {
    gpa: Allocator,
    io: std.Io,
    pattern: []const u8,
    options: Options,
    file_arena: std.heap.ArenaAllocator,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    matched_any: bool = false,
    had_error: bool = false,

    pub fn init(
        gpa: Allocator,
        io: std.Io,
        pattern: []const u8,
        options: Options,
        stdout: *std.Io.Writer,
        stderr: *std.Io.Writer,
    ) Allocator.Error!Searcher {
        return .{
            .gpa = gpa,
            .io = io,
            // Copy the pattern so the Searcher doesn't depend on the lifetime
            // of the caller's memory.
            .pattern = try gpa.dupe(u8, pattern),
            .options = options,
            .file_arena = .init(gpa),
            .stdout = stdout,
            .stderr = stderr,
        };
    }

    pub fn deinit(self: *Searcher) void {
        self.file_arena.deinit();
        self.gpa.free(self.pattern);
        self.* = undefined; // catch use-after-deinit in safe builds
    }

    /// Searches one file. Problems are reported, not returned: a file we
    /// cannot read must not stop the whole search.
    pub fn searchPath(self: *Searcher, path: []const u8) std.Io.Writer.Error!void {
        // Whatever happens below, free this file's memory (but keep the
        // arena's capacity around for the next file) when we return.
        defer _ = self.file_arena.reset(.retain_capacity);
        const arena = self.file_arena.allocator();

        const contents = std.Io.Dir.cwd().readFileAlloc(self.io, path, arena, .limited(max_file_size)) catch |err| {
            try self.reportError(path, err);
            return;
        };
        if (try self.searchText(path, contents) > 0) self.matched_any = true;
    }

    /// Prints every line of `text` that contains the pattern and returns
    /// how many lines matched.
    fn searchText(self: *const Searcher, path: []const u8, text: []const u8) std.Io.Writer.Error!usize {
        // A trailing newline ends the last line; it doesn't start a new one.
        const body = if (std.mem.endsWith(u8, text, "\n")) text[0 .. text.len - 1] else text;

        var matches: usize = 0;
        var lines = std.mem.splitScalar(u8, body, '\n');
        var line_number: usize = 1;
        while (lines.next()) |line| : (line_number += 1) {
            if (std.mem.find(u8, line, self.pattern) == null) continue;
            const match: Match = .{ .path = path, .line_number = line_number, .text = line };
            try match.write(self.stdout);
            matches += 1;
        }
        return matches;
    }

    /// Reports a problem with `path` on stderr, flushing stdout first so the
    /// two streams interleave in the order things happened.
    fn reportError(self: *Searcher, path: []const u8, err: anyerror) std.Io.Writer.Error!void {
        self.had_error = true;
        try self.stdout.flush();
        try self.stderr.print("seek: {s}: {t}\n", .{ path, err });
        try self.stderr.flush();
    }
};
```

What changed from the Chapter 7 `Searcher`:

- **New fields:** `gpa` (so `deinit` can free with it) and `file_arena`. The `arena` field is gone.
- **`init`** copies the pattern with `gpa.dupe`, so the `Searcher` no longer depends on how long
  the caller's `args` live. Harmless today, but a struct holding borrowed slices becomes a trap as
  code changes. The doc comment states the ownership rules.
- `.file_arena = .init(gpa)` is a decl literal for `std.heap.ArenaAllocator.init(gpa)`. The arena
  gets its memory from `gpa`, so the leak checker sees it too.
- `init` can fail only at the `dupe`, the first allocation, so there's nothing for an `errdefer`
  to clean up yet. (Creating the arena allocates nothing.)
- **`deinit`** frees in reverse order of `init` and ends with `self.* = undefined`.
- **`searchPath`** reads the file into `file_arena` and `defer`s the reset, so it happens on every
  exit: success, a file error, or a write error. `.retain_capacity` keeps the memory for the next
  file.
- `contents` is freed by the reset, so it must not outlive `searchPath`. Nothing keeps it:
  `searchText` only prints lines.
- `searchPath`, `init`, `deinit` and `Match.write` are `pub` because `main.zig` calls them.
  `searchText` and `reportError` stay private.
- The `exitCode` method is gone. Its only caller, `run`, reads the two flags directly.

### `src/main.zig`

Replace the top of `main.zig`, through `UsageError`, with this. It imports the new module and
keeps only what `main.zig` uses:

```zig
const std = @import("std");
// A relative path imports another file of this module. The result is a
// struct type; we pull out the declarations main needs.
const search = @import("search.zig");
const Options = search.Options;
const Searcher = search.Searcher;

const version = "0.1.0";

const usage = "usage: seek [OPTIONS] PATTERN [PATH ...]\n";

/// The process exit status. An explicit tag type (`u8`) fixes each value.
const ExitCode = enum(u8) {
    ok = 0, // a line matched (or nothing went wrong)
    no_match = 1, // nothing matched
    trouble = 2, // bad usage or an error
};

/// What the command line asks seek to do: a tagged union, so each case
/// carries exactly the data it needs.
const Command = union(enum) {
    help,
    version,
    search: Search,

    const Search = struct {
        options: Options = .{},
        pattern: []const u8,
        paths: []const [:0]const u8,
    };
};

/// Mistakes in how seek was called.
const UsageError = error{ UnknownFlag, MissingPattern, MissingPath };
```

`max_file_size`, `Color`, `Options`, `Match` and `Searcher` leave `main.zig`. `ExitCode`,
`Command` and `parseArgs` stay: they're about the command line, not searching.

In `main`, pass `init.gpa` to `run` instead of `arena`, and let `OutOfMemory` through:

```zig
    // init.gpa is a general-purpose allocator. In Debug builds it is a
    // SafeAllocator that reports leaks when main returns.
    const status = run(init.gpa, init.io, args, stdout, stderr) catch |err| switch (err) {
        error.UnknownFlag, error.MissingPattern, error.MissingPath => blk: {
            try stderr.writeAll(usage);
            break :blk .trouble;
        },
        error.OutOfMemory, error.WriteFailed => |e| return e,
    };
```

- `main` still puts `args` in `init.arena`. They live for the whole program, so that's right.
- `run` can now fail with `error.OutOfMemory` (from `Searcher.init`). The error `switch` must
  handle it or it won't compile. `|e| return e` returns it from `main`; Zig then prints
  `error: OutOfMemory` and exits with status 1.

Finally, `run`:

```zig
fn run(
    gpa: std.mem.Allocator,
    io: std.Io,
    args: []const [:0]const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) (UsageError || std.mem.Allocator.Error || std.Io.Writer.Error)!ExitCode {
    switch (try parseArgs(args, stderr)) {
        .help => {
            try stdout.writeAll(usage);
            return .ok;
        },
        .version => {
            try stdout.print("seek {s}\n", .{version});
            return .ok;
        },
        .search => |cmd| {
            var searcher: Searcher = try .init(gpa, io, cmd.pattern, cmd.options, stdout, stderr);
            defer searcher.deinit();

            for (cmd.paths) |path| try searcher.searchPath(path);

            if (searcher.had_error) return .trouble;
            return if (searcher.matched_any) .ok else .no_match;
        },
    }
}
```

- `run` takes `gpa` instead of `arena` first.
- `std.mem.Allocator.Error` joins the error set with `||`.
- `try .init(...)` then `defer searcher.deinit()`: the init/deinit pair. Whatever happens in the
  loop, the searcher is cleaned up.
- The capture is now `|cmd|`, not `|search|`. Zig forbids a name that **shadows** another in scope,
  and `search` now names the imported module:

```console
$ zig build
...
src/main.zig:79:21: error: capture shadows declaration of 'search'
        .search => |search| {
                    ^~~~~~
src/main.zig:4:1: note: declared here
const search = @import("search.zig");
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
```

`parseArgs` doesn't change.

### Checkpoint

The behavior is the same as in Chapter 7:

```console
$ zig build
$ ./zig-out/bin/seek fox testdata/poem.txt testdata/notes/log.txt
testdata/poem.txt:The quick brown fox
testdata/notes/log.txt:2024-01-01 saw a fox near the barn
testdata/notes/log.txt:2024-01-03 fox tracks in the snow
$ ./zig-out/bin/seek dog nope.txt testdata/poem.txt testdata/notes/todo.md
seek: nope.txt: FileNotFound
testdata/poem.txt:jumps over the lazy dog.
testdata/poem.txt:the dog just sleeps.
testdata/notes/todo.md:- walk the dog
$ echo $?
2
$ ./zig-out/bin/seek --version
seek 0.1.0
$ ./zig-out/bin/seek -x fox testdata/poem.txt
seek: unknown flag '-x'
usage: seek [OPTIONS] PATTERN [PATH ...]
```

No leak report: everything was freed. To prove the checker is watching, comment out
`defer searcher.deinit();` in `run`, rebuild, and run:

```console
$ ./zig-out/bin/seek fox testdata/poem.txt
testdata/poem.txt:The quick brown fox
error(SafeAllocator): leaked [addr: 7e246561c498, len: 502 (0x1f6) align: 8] allocated at: 
…/lib/std/mem/Allocator.zig:147:26: 0x116ffdd in rawAlloc (std.zig)
    return a.vtable.alloc(a.ptr, len, alignment, ret_addr);
                         ^
…/lib/std/Io/Writer.zig:2767:42: 0x122b1b3 in ensureTotalCapacity (std.zig)
        return ensureTotalCapacityPrecise(a, better_capacity);
                                         ^
…
(additional stack frames may have been skipped...)

error(SafeAllocator): leaked [addr: 7e246561c408, len: 3 (0x3) align: 1] allocated at: 
…/lib/std/mem/Allocator.zig:481:40: 0x1055aee in dupe__func_109 (std.zig)
    const new_buf = try allocator.alloc(T, m.len);
                                       ^
…/src/search.zig:69:36: 0x11f8bcc in init (main.zig)
            .pattern = try gpa.dupe(u8, pattern),
                                   ^
…/src/main.zig:80:47: 0x11f4ff1 in run (main.zig)
            var searcher: Searcher = try .init(gpa, io, cmd.pattern, cmd.options, stdout, stderr);
                                              ^
…/src/main.zig:50:23: 0x11e9a6f in main (main.zig)
    const status = run(init.gpa, init.io, args, stdout, stderr) catch |err| switch (err) {
                      ^
…
$ echo $?
0
```

Two leaks:

- **3 bytes**: the copy of `"fox"` from `Searcher.init`. The trace points right at the `dupe`.
- **502 bytes**: the arena's retained buffer. `readFileAlloc` grows its buffer with an
  `Io.Writer.Allocating`, and the trace stops at 7 frames, inside `std`, before reaching
  `searchPath`. The size is the clue: it's the arena's capacity, not the 111-byte file.

The exit status is still 0: leaks are reported, not fatal. Put the `defer` back.

The complete project at this point is in `project/ch08/`.

## Summary

- Zig has no hidden allocations. Functions that allocate take a `std.mem.Allocator`, and every
  allocation can fail with `error.OutOfMemory`.
- `alloc`/`free` for slices, `create`/`destroy` for single items, plus `dupe`, `print` and
  `realloc`. Free with the same allocator, and put the `defer ...free(...)` on the next line.
- `init.gpa` is a `SafeAllocator` in Debug and ReleaseSafe: it reports leaks (with stack traces)
  and panics on double frees. Leaks don't change the exit status.
- `ArenaAllocator` frees everything at once with `deinit` or `reset`; use it when allocations die
  together. `init.arena` lives for the whole program.
- `FixedBufferAllocator` allocates from a buffer you give it, with no heap.
- Ownership is a convention: document "the caller owns the result"; structs that own memory get
  `init`/`deinit`; `deinit` ends with `self.* = undefined`.
- `defer` frees on every exit; `errdefer` frees only on error, when ownership was about to pass to
  the caller. They run in reverse order. `errdefer |err|` is gone in 0.17.
- `std.testing.allocator` fails a test that leaks.
- Every file is a struct; `pub` declarations are its public API; `//!` documents the file.

## Exercises

1. Write `fn joinWords(gpa: std.mem.Allocator, words: []const []const u8) ![]u8` that joins words
   with single spaces using exactly **one** allocation. Test it with `std.testing.allocator` and
   compare the result with `std.mem.join(gpa, " ", words)`. Handle an empty list.

<details><summary>Solution</summary>

```zig
const std = @import("std");

/// Joins `words` with single spaces. The caller owns the result.
fn joinWords(gpa: std.mem.Allocator, words: []const []const u8) ![]u8 {
    if (words.len == 0) return gpa.alloc(u8, 0);
    var total: usize = words.len - 1; // the spaces
    for (words) |w| total += w.len;

    const out = try gpa.alloc(u8, total);
    var i: usize = 0;
    for (words, 0..) |w, n| {
        if (n > 0) {
            out[i] = ' ';
            i += 1;
        }
        @memcpy(out[i..][0..w.len], w);
        i += w.len;
    }
    return out;
}

test joinWords {
    const gpa = std.testing.allocator;
    const words = [_][]const u8{ "no", "hidden", "allocations" };

    const mine = try joinWords(gpa, &words);
    defer gpa.free(mine);
    const theirs = try std.mem.join(gpa, " ", &words);
    defer gpa.free(theirs);

    try std.testing.expectEqualStrings("no hidden allocations", mine);
    try std.testing.expectEqualStrings(theirs, mine);

    const empty = try joinWords(gpa, &.{});
    defer gpa.free(empty);
    try std.testing.expectEqual(0, empty.len);
}
```

```console
$ zig test join.zig
1/1 join.decltest.joinWords...OK
All 1 tests passed.
```

Two passes (measure, then copy) avoid growing a buffer. The empty result is still allocated and
freed: `alloc(u8, 0)` and freeing it are both valid. `test joinWords` (a name instead of a string)
is a *doctest*, a test tied to a declaration.

</details>

2. Using a `FixedBufferAllocator` over a 256-byte array, count how many `alloc(u64, 8)` calls
   succeed before `OutOfMemory`.

<details><summary>Solution</summary>

```zig
const std = @import("std");

pub fn main() void {
    var buffer: [256]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&buffer);
    const allocator = fba.allocator();

    var count: usize = 0;
    while (true) {
        _ = allocator.alloc(u64, 8) catch break;
        count += 1;
    }
    std.debug.print("{d} allocations of 64 bytes fit in 256 bytes\n", .{count});
}
```

```console
$ zig run fba_count.zig
4 allocations of 64 bytes fit in 256 bytes
```

`catch break` leaves the loop on the first failure. If the buffer weren't aligned for `u64`, the
first allocation would skip a few bytes, and only 3 might fit.

</details>

3. Write `fn copyAll(gpa: Allocator, names: []const []const u8) Allocator.Error![][]u8` that returns
   copies of all strings (the caller owns the outer slice and each string). It must not leak if
   any allocation fails. Test this with `std.testing.FailingAllocator`, which fails the N-th
   allocation: `var failing: std.testing.FailingAllocator = .init(std.testing.allocator, .{ .fail_index = n });`.

<details><summary>Solution</summary>

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Returns copies of all `names`. The caller owns the outer slice and
/// every string in it.
fn copyAll(gpa: Allocator, names: []const []const u8) Allocator.Error![][]u8 {
    const out = try gpa.alloc([]u8, names.len);
    errdefer gpa.free(out);

    var done: usize = 0;
    errdefer for (out[0..done]) |name| gpa.free(name);

    for (names) |name| {
        out[done] = try gpa.dupe(u8, name);
        done += 1;
    }
    return out;
}

fn freeAll(gpa: Allocator, names: [][]u8) void {
    for (names) |name| gpa.free(name);
    gpa.free(names);
}

test "copyAll copies" {
    const gpa = std.testing.allocator;
    const copies = try copyAll(gpa, &.{ "ann", "bob", "cy" });
    defer freeAll(gpa, copies);
    try std.testing.expectEqualStrings("bob", copies[1]);
}

test "copyAll cleans up when an allocation fails" {
    // Fail the 1st, 2nd, 3rd and 4th allocation in turn.
    for (0..4) |fail_index| {
        var failing: std.testing.FailingAllocator = .init(std.testing.allocator, .{ .fail_index = fail_index });
        const result = copyAll(failing.allocator(), &.{ "ann", "bob", "cy" });
        try std.testing.expectError(error.OutOfMemory, result);
    }
}
```

```console
$ zig test copies.zig
1/2 copies.test.copyAll copies...OK
2/2 copies.test.copyAll cleans up when an allocation fails...OK
All 2 tests passed.
```

`done` tells the second `errdefer` how many strings exist. The `errdefer`s run in reverse order:
strings first, then the outer slice. Delete the `errdefer for` line and the second test reports
three leaked 3-byte strings.

</details>

4. Watch the arena at work. Add a `peak_capacity: usize = 0` field to `Searcher`. In `searchPath`,
   before the reset, record the largest `self.file_arena.queryCapacity()` seen so far. In `run`,
   print it on stderr after the loop. (Not part of the real `seek`.)

<details><summary>Solution</summary>

In `search.zig`, add the field after `had_error`, and replace the `defer` line in `searchPath`
with a `defer` block:

```zig
    peak_capacity: usize = 0,
```

```zig
        defer {
            self.peak_capacity = @max(self.peak_capacity, self.file_arena.queryCapacity());
            _ = self.file_arena.reset(.retain_capacity);
        }
```

In `run`, after the `for` loop, flush stdout (so the matches come first, as in `reportError`) and
print:

```zig
            try stdout.flush();
            try stderr.print("seek: peak arena capacity {d} bytes\n", .{searcher.peak_capacity});
```

```console
$ ./zig-out/bin/seek fox testdata/poem.txt testdata/notes/log.txt testdata/notes/todo.md
testdata/poem.txt:The quick brown fox
testdata/notes/log.txt:2024-01-01 saw a fox near the barn
testdata/notes/log.txt:2024-01-03 fox tracks in the snow
testdata/notes/todo.md:- feed the fox
seek: peak arena capacity 478 bytes
```

Three files, and the arena never held more than one file's worth. Without the reset it would keep
all three.

</details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-8--memory-and-allocators)
