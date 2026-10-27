# Chapter 5 — Errors and Optionals

Zig has no exceptions and, by default, no null pointers. A value that might be missing has an
**optional** type, `?T`. An operation that might fail returns an **error union**, `E!T`. Both are
ordinary values that the compiler makes you handle. This chapter covers optionals, error sets,
`try`, `catch`, `errdefer`, and error return traces. In `seek`, file errors become one-line
messages and bad usage gets its own error set. [Chapter 4](04-functions.md) ran the first search;
[Chapter 6](06-arrays-slices-pointers.md) handles many paths.

## Optionals: `?T`

`?u32` means "a `u32`, or `null`". You must unwrap it to use the value.

`examples/ch05/optionals.zig`

```zig
const std = @import("std");

// `?u32` is "a u32 or null". Here, null means "no digit found".
fn firstDigit(text: []const u8) ?u32 {
    for (text) |c| {
        if (c >= '0' and c <= '9') return c - '0';
    }
    return null;
}

pub fn main() void {
    const inputs = [_][]const u8{ "abc7d", "none" };
    for (inputs) |text| {
        // `if` with a capture: runs the first branch only if there's a value.
        if (firstDigit(text)) |d| {
            std.debug.print("{s}: digit {d}\n", .{ text, d });
        } else {
            std.debug.print("{s}: no digit\n", .{text});
        }

        // `orelse` supplies a default when the value is null.
        const digit = firstDigit(text) orelse 0;
        std.debug.print("{s}: digit or 0: {d}\n", .{ text, digit });
    }

    // `.?` unwraps, asserting "this is not null". It panics if it is.
    const sure = firstDigit("x9").?;
    std.debug.print("sure: {d}\n", .{sure});

    // Optionals compare with null and print as `null`.
    const missing = firstDigit("");
    std.debug.print("missing == null: {}, printed: {any}\n", .{ missing == null, missing });
}
```

```console
$ zig run examples/ch05/optionals.zig
abc7d: digit 7
abc7d: digit or 0: 7
none: no digit
none: digit or 0: 0
sure: 9
missing == null: true, printed: null
```

| Syntax | Meaning |
|--------|---------|
| `?T` | a `T` or `null` |
| `return null;` / `return x;` | a plain `T` coerces to `?T` automatically |
| `if (opt) \|v\| { ... } else { ... }` | run with the value `v`, or the `else` if `null` |
| `opt orelse default` | the value, or `default` if `null` |
| `opt orelse return ...` | the value, or leave the function |
| `opt.?` | the value; panics if `null` (short for `opt orelse unreachable`) |
| `opt == null` | test without unwrapping |

Using an optional where a plain value is expected is a compile error with a helpful note:

```text
opt.zig:6:24: error: expected type 'u32', found '?u32'
    const n: u32 = find(5);
                   ~~~~^~~
opt.zig:6:24: note: cannot convert optional to payload type
opt.zig:6:24: note: consider using '.?', 'orelse', or 'if'
```

`.?` on a `null` is a bug, caught in safe builds:

```text
thread 294678 panic: attempt to use null value
…/unwrap.zig:6:22: 0x11e939a in main (unwrap.zig)
    const n = find(1).?;
                     ^
```

Use `.?` only when you know the value is there; otherwise use `if` or `orelse`.

### Looping over optionals

`while` with a capture loops until the value is `null`. That's how Zig **iterators** work: `next()`
returns the next item, or `null` at the end. `seek` used this in Chapter 4.

`examples/ch05/while_optional.zig`

```zig
const std = @import("std");

pub fn main() void {
    // splitScalar returns an iterator. Its next() returns ?[]const u8:
    // the next piece, or null when there are no more.
    var words = std.mem.splitScalar(u8, "red,green,blue", ',');

    // `while` with a capture loops until next() returns null.
    while (words.next()) |word| {
        std.debug.print("word: {s}\n", .{word});
    }

    // `orelse` can also leave the function or the loop.
    var parts = std.mem.splitScalar(u8, "a=1", '=');
    const key = parts.next() orelse return;
    const value = parts.next() orelse return;
    std.debug.print("key={s} value={s}\n", .{ key, value });
}
```

```console
$ zig run examples/ch05/while_optional.zig
word: red
word: green
word: blue
key=a value=1
```

`orelse` takes any expression, including `return`, `break`, `continue`, or a block, so "get it or
bail out" is a one-liner.

### Optional pointers

A pointer like `*u32` always points at something; it can't be `null`:

```text
null_ptr.zig:2:21: error: expected type '*u32', found '@TypeOf(null)'
    const p: *u32 = null;
                    ^~~~
```

"Maybe a pointer" is `?*u32`, and you unwrap it like any optional. A null pointer dereference can
only happen if you write `.?` or `orelse unreachable` yourself.

`examples/ch05/optional_pointers.zig`

```zig
const std = @import("std");

// A pointer `*u32` can never be null. "Maybe a pointer" is `?*u32`.
fn largest(values: []u32) ?*u32 {
    if (values.len == 0) return null;
    var best = &values[0];
    for (values) |*v| {
        if (v.* > best.*) best = v;
    }
    return best;
}

pub fn main() void {
    var values = [_]u32{ 3, 9, 4 };
    if (largest(&values)) |p| {
        p.* = 0; // reset the largest value through the pointer
    }
    std.debug.print("values: {any}\n", .{values});

    // An optional pointer costs nothing: null is stored as address 0.
    std.debug.print("size of *u32: {d}, size of ?*u32: {d}\n", .{ @sizeOf(*u32), @sizeOf(?*u32) });
    std.debug.print("size of u32: {d}, size of ?u32: {d}\n", .{ @sizeOf(u32), @sizeOf(?u32) });
}
```

```console
$ zig run examples/ch05/optional_pointers.zig
values: { 3, 0, 4 }
size of *u32: 8, size of ?*u32: 8
size of u32: 4, size of ?u32: 8
```

An optional pointer is the same size as a pointer: address 0 means `null`. Other optionals need
an extra flag, so `?u32` is bigger than `u32` (sizes shown are for a 64-bit machine).

## Errors

An **error** is a named value like `error.FileNotFound`. An **error set** is a list of them. An
**error union** `E!T` holds either a `T` or an error from set `E`.

`examples/ch05/errors.zig`

```zig
const std = @import("std");

// An error set lists the errors a function can return.
const ParseError = error{ Empty, BadDigit };

// `ParseError!u8` is an error union: a u8 or one of the errors in ParseError.
fn parseDigit(text: []const u8) ParseError!u8 {
    if (text.len == 0) return error.Empty;
    const c = text[0];
    if (c < '0' or c > '9') return error.BadDigit;
    return c - '0';
}

// `try x` means `x catch |err| return err`: pass errors up to the caller.
fn sumOfFirstDigits(a: []const u8, b: []const u8) ParseError!u8 {
    const x = try parseDigit(a);
    const y = try parseDigit(b);
    return x + y;
}

pub fn main() void {
    // `catch` with a value: use a default on any error.
    const d = parseDigit("x") catch 0;
    std.debug.print("with default: {d}\n", .{d});

    // `catch |err| switch`: handle each error separately.
    for ([_][]const u8{ "7", "", "?" }) |text| {
        const value = parseDigit(text) catch |err| switch (err) {
            error.Empty => {
                std.debug.print("'{s}': empty input\n", .{text});
                continue;
            },
            error.BadDigit => {
                std.debug.print("'{s}': not a digit\n", .{text});
                continue;
            },
        };
        std.debug.print("'{s}': {d}\n", .{ text, value });
    }

    // `if` with an error union: the else branch captures the error.
    if (sumOfFirstDigits("4", "5")) |sum| {
        std.debug.print("sum: {d}\n", .{sum});
    } else |err| {
        std.debug.print("failed: {t}\n", .{err});
    }

    // {t} and @errorName both give an error's name.
    const err: ParseError = error.BadDigit;
    std.debug.print("{t} / {s}\n", .{ err, @errorName(err) });
}
```

```console
$ zig run examples/ch05/errors.zig
with default: 0
'7': 7
'': empty input
'?': not a digit
sum: 9
BadDigit / BadDigit
```

Ways to deal with an error union:

| Syntax | Meaning |
|--------|---------|
| `try x` | the value, or return the error to *my* caller |
| `x catch default` | the value, or `default` on any error |
| `x catch \|err\| expr` | the value, or run `expr` with the error (often `switch (err)`) |
| `x catch \|err\| return err` | the long form of `try` |
| `if (x) \|v\| { ... } else \|err\| { ... }` | branch on success or failure |
| `x catch unreachable` | assert that it can't fail (see below) |

There are no exceptions, no hidden jumps, and no `finally`. An error leaves a function only
through a visible `try` or `return`, so reading a function shows every place it can return early.

### Errors can't be ignored

An error union is a value, and unused values are compile errors. You saw this in
[Chapter 1](01-getting-started.md) when a `try` was missing:

```text
error: error union of type 'error{WriteFailed}!void' is ignored
note: consider using 'try', 'catch', or 'if'
```

You can't forget an error; to ignore one, say so: `catch {}`.

Switching on errors is exhaustive, like any `switch`. Forget one and the compiler lists it:

```text
errs.zig:8:37: error: switch must handle all possibilities
    const v = parse("") catch |err| switch (err) {
                                    ^~~~~~
errs.zig:8:37: note: unhandled error value: 'error.TooBig'
```

`try` works only in a function that can return an error. In `pub fn main() void`, it fails with
`note: function cannot return an error`. Change the return type to `!void`, or handle the error
with `catch`.

### `{t}` and `@errorName`

The `{t}` format specifier ("tag name") prints an error's name. `@errorName(err)` returns the name
as a string, for use outside `print`. `{t}` also prints enum value names
([Chapter 7](07-structs-enums-unions.md)).

## Error sets: explicit, inferred, merged

`examples/ch05/error_sets.zig`

```zig
const std = @import("std");

const ReadError = error{ NotFound, AccessDenied };
const ParseError = error{ Empty, BadDigit };

// `||` merges two error sets.
const LoadError = ReadError || ParseError;

fn read(name: []const u8) ReadError![]const u8 {
    if (std.mem.eql(u8, name, "secret")) return error.AccessDenied;
    if (std.mem.eql(u8, name, "missing")) return error.NotFound;
    return "7";
}

fn parse(text: []const u8) ParseError!u8 {
    if (text.len == 0) return error.Empty;
    if (text[0] < '0' or text[0] > '9') return error.BadDigit;
    return text[0] - '0';
}

// Both functions' errors fit in LoadError, so `try` works on each.
fn load(name: []const u8) LoadError!u8 {
    return try parse(try read(name));
}

// With `!u8` and no set, the compiler infers the set from the body.
fn loadTwice(name: []const u8) !u8 {
    return try load(name) * 2;
}

pub fn main() void {
    for ([_][]const u8{ "config", "secret", "missing" }) |name| {
        if (loadTwice(name)) |v| {
            std.debug.print("{s}: {d}\n", .{ name, v });
        } else |err| {
            std.debug.print("{s}: error.{t}\n", .{ name, err });
        }
    }

    // Every error set coerces to `anyerror`, the set of all errors.
    const any: anyerror = error.NotFound;
    std.debug.print("anyerror holds: {t}\n", .{any});
}
```

```console
$ zig run examples/ch05/error_sets.zig
config: 14
secret: error.AccessDenied
missing: error.NotFound
anyerror holds: NotFound
```

| Form | Meaning |
|------|---------|
| `error{ A, B }` | an error set with two errors |
| `E!T` | an error union with an explicit set |
| `!T` (return types only) | an **inferred** set: whatever errors the body can return |
| `E1 \|\| E2` | the union of two sets |
| `anyerror` | the global set of every error in the program |

A smaller set coerces to a bigger one, so `try read(...)` works inside `load`. The reverse is a
compile error, as is a function with an explicit set returning an error that isn't in it:

```text
errs.zig:4:18: error: expected type 'error{BadDigit,Empty}!u8', found 'error{Overflow}'
    return error.Overflow;
                 ^~~~~~~~
errs.zig:4:18: note: 'error.Overflow' not a member of destination error set
```

Which to use?

- **Inferred `!T`** is the default for most functions. It's short and stays correct as the body
  changes. A `switch` on an inferred set is still checked for exhaustiveness.
- **An explicit set** makes the errors part of the function's contract. A new failure inside the
  function is then a compile error *in that function* until you add it to the set. Use it for
  public APIs and boundaries you want to keep stable. Function types also need one:
  `*const fn () !void` gives `error: function type cannot have an inferred error set`.
- **`anyerror`** loses that checking. Use it only when you can't know the set, such as when
  storing errors from many unrelated sources.

## `errdefer`

`errdefer` is a `defer` that runs only if the function returns an **error**. Use it to undo a
half-finished job.

`examples/ch05/errdefer.zig`

```zig
const std = @import("std");

const SetupError = error{DiskFull};

fn setup(fail: bool) SetupError!void {
    std.debug.print("open log\n", .{});
    defer std.debug.print("  defer: always runs\n", .{});
    // errdefer runs only if this function returns an error.
    errdefer std.debug.print("  errdefer: close log again\n", .{});

    if (fail) return error.DiskFull;
    std.debug.print("setup done\n", .{});
}

pub fn main() void {
    setup(false) catch {};
    std.debug.print("---\n", .{});
    setup(true) catch |err| std.debug.print("setup failed: {t}\n", .{err});
}
```

```console
$ zig run examples/ch05/errdefer.zig
open log
setup done
  defer: always runs
---
open log
  errdefer: close log again
  defer: always runs
setup failed: DiskFull
```

The typical pattern: allocate something, `errdefer` its release, then do more work that can fail.
On success the caller gets the resource; on failure nothing leaks. You'll use this in
[Chapter 8](08-memory-and-allocators.md).

Older Zig code sometimes writes `errdefer |err| ...` to see the error. That capture was removed
from the language, and Zig 0.17 rejects it:

```text
errdefer_capture.zig:9:14: error: expected block or expression, found '|'
    errdefer |err| std.debug.print("{t}\n", .{err});
             ^
```

If you need the error, handle it with `catch |err|` at the call site.

## Error return traces

When `main` returns an error, Zig prints its name. Debug builds also print an **error return
trace**: the path the error took, one `try` at a time.

`examples/ch05/trace.zig`

```zig
const std = @import("std");

fn readConfig(name: []const u8) !u8 {
    if (name.len == 0) return error.NoName;
    return 1;
}

fn loadSettings() !u8 {
    return try readConfig("");
}

// Returning an error from main prints its name and the error return
// trace: every `try` it passed through.
pub fn main() !void {
    const level = try loadSettings();
    std.debug.print("level {d}\n", .{level});
}
```

```console
$ zig run examples/ch05/trace.zig
error: NoName
…/examples/ch05/trace.zig:4:24: 0x11e871e in readConfig (trace.zig)
    if (name.len == 0) return error.NoName;
                       ^
…/examples/ch05/trace.zig:9:12: 0x11e87b2 in loadSettings (trace.zig)
    return try readConfig("");
           ^
…/examples/ch05/trace.zig:15:19: 0x11e8875 in main (trace.zig)
    const level = try loadSettings();
                  ^
$ echo $?
1
```

Read it top to bottom: where the error was created, then each `try` that passed it on. It's not a
stack trace of where the program *is*, but the history of where the *error went*. Release builds
(`-O safe`, `fast`, `small`) leave the trace out by default and print only `error: NoName`. Try
`zig run -O safe` on this file to see the difference.

## `catch unreachable`

`x catch unreachable` says "this can't fail". If it fails anyway, a safe build panics.

`examples/ch05/catch_unreachable.zig`

```zig
const std = @import("std");

pub fn main() void {
    // The input is a constant we wrote ourselves, so parsing can't fail.
    // `catch unreachable` says so; a safe build panics if we're wrong.
    const port = std.fmt.parseInt(u16, "8080", 10) catch unreachable;
    std.debug.print("port: {d}\n", .{port});
}
```

```console
$ zig run examples/ch05/catch_unreachable.zig
port: 8080
```

It's fine when failure is truly impossible, like parsing a constant you wrote. It's wrong for
anything the outside world controls: files, user input, the network, memory. Those failures will
happen; handle them.

## Building seek: robust errors

Two problems from Chapter 4 need fixing:

- A missing file prints an error trace and exits with 1. Users should get one line and exit
  status 2.
- Unknown flags like `-x` are taken as the PATTERN instead of being rejected.

The plan:

- `run` handles file errors where they happen: print `seek: PATH: ErrorName` to stderr and
  return exit status 2.
- Usage mistakes become errors in their own set, `UsageError`. `main` catches them, prints the
  usage line, and returns 2.
- Any other error (so far only `WriteFailed`: stdout or stderr is broken) still goes up and out
  of `main`.

Replace `src/main.zig` with:

`src/main.zig`

```zig
const std = @import("std");

const version = "0.1.0";

const exit_ok: u8 = 0; // a line matched (or nothing went wrong)
const exit_no_match: u8 = 1; // nothing matched
const exit_trouble: u8 = 2; // bad usage or an error

const usage = "usage: seek [OPTIONS] PATTERN [PATH ...]\n";

/// Mistakes in how seek was called. Keeping them in their own error set
/// separates "you called seek wrong" from "something failed while working".
const UsageError = error{ UnknownFlag, MissingPattern, MissingPath };

/// Refuse to load files larger than this into memory.
const max_file_size = 16 * 1024 * 1024;

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), init.io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    // main only wires things together; `run` does the work. Usage errors
    // become exit status 2; any other error (stdout closed, ...) propagates.
    const status = run(init.io, arena, args, stdout, stderr) catch |err| switch (err) {
        error.UnknownFlag, error.MissingPattern, error.MissingPath => blk: {
            try stderr.writeAll(usage);
            break :blk exit_trouble;
        },
        error.WriteFailed => return err,
    };
    try stdout.flush();
    try stderr.flush();
    return status;
}

/// Runs seek with the given command line and returns the exit status.
/// Everything it needs is passed in explicitly: no globals.
fn run(
    io: std.Io,
    arena: std.mem.Allocator,
    args: []const [:0]const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) (UsageError || std.Io.Writer.Error)!u8 {
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--version")) {
            try stdout.print("seek {s}\n", .{version});
            return exit_ok;
        }
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try stdout.writeAll(usage);
            return exit_ok;
        }
        // A lone "-" is not a flag; it will mean standard input later.
        if (arg.len > 1 and arg[0] == '-') {
            try stderr.print("seek: unknown flag '{s}'\n", .{arg});
            return error.UnknownFlag;
        }
    }

    const pattern = argAt(args, 1) orelse return error.MissingPattern;
    const path = argAt(args, 2) orelse return error.MissingPath;

    // Read the whole file into memory. The arena frees it when seek exits.
    // A file we can't read is reported, not fatal: `catch` handles the error.
    const contents = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(max_file_size)) catch |err| {
        try stderr.print("seek: {s}: {t}\n", .{ path, err });
        return exit_trouble;
    };

    const matches = try searchText(stdout, path, pattern, contents);
    return if (matches > 0) exit_ok else exit_no_match;
}

/// Returns the argument at `index`, or null if there are not that many.
fn argAt(args: []const [:0]const u8, index: usize) ?[]const u8 {
    return if (index < args.len) args[index] else null;
}

/// Prints every line of `text` that contains `pattern` as `path:line` and
/// returns how many lines matched.
fn searchText(out: *std.Io.Writer, path: []const u8, pattern: []const u8, text: []const u8) !usize {
    // A trailing newline ends the last line; it doesn't start a new, empty one.
    const body = if (std.mem.endsWith(u8, text, "\n")) text[0 .. text.len - 1] else text;

    var matches: usize = 0;
    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |line| {
        if (std.mem.find(u8, line, pattern) != null) {
            try out.print("{s}:{s}\n", .{ path, line });
            matches += 1;
        }
    }
    return matches;
}
```

### What changed

**A `UsageError` set.** `UnknownFlag`, `MissingPattern`, and `MissingPath` are ways the user
called `seek` wrong, separate from failures during the work, like a missing file.

**`run` has an explicit error set:** `(UsageError || std.Io.Writer.Error)!u8`. `run` can fail in
exactly two ways: a usage error or a failed write (`std.Io.Writer.Error` is `error{WriteFailed}`).
The signature documents that. If a later change lets a new error escape, `run` stops compiling
until you decide what to do with it.

**`main` handles each error by name:**

```zig
const status = run(init.io, arena, args, stdout, stderr) catch |err| switch (err) {
    error.UnknownFlag, error.MissingPattern, error.MissingPath => blk: {
        try stderr.writeAll(usage);
        break :blk exit_trouble;
    },
    error.WriteFailed => return err,
};
```

- `catch |err| switch (err)` runs only if `run` fails. On success, `status` is `run`'s result.
- The usage prong prints the usage line, then makes `exit_trouble` the value of the whole `catch`
  expression with a labeled block ([Chapter 3](03-control-flow.md)).
- `error.WriteFailed => return err` passes write failures on. If stdout is broken, there's nothing
  sensible left to print.
- The switch lists every error, with no `else`, so a new error in `run` would also need a
  decision here.

**Optional arguments.** `argAt` returns `?[]const u8`: the argument, or `null` if there aren't
enough. `orelse return error.MissingPattern` turns "missing" into an error in one line.

**File errors are caught where they happen.** `readFileAlloc` can fail in many ways: the file
doesn't exist, is a directory, is too big, can't be read. `catch |err| { ... }` prints the error's
name with `{t}` and returns `exit_trouble`: no trace, no crash. The `try` inside that block still
propagates a write failure.

**Unknown flags are rejected.** Any argument longer than one character that starts with `-` is a
flag, and any flag other than `--version` and `--help` is unknown for now. A lone `-` isn't a
flag: by convention it means "standard input", which [Chapter 11](11-files-and-io.md) adds. The
message goes to stderr before the error is returned, because only `run` knows which flag it was.

Why `{t}` and not `{s}`? `err` is an error, not a string; `{t}` prints its name. `{s}` with
`@errorName(err)` would print the same thing.

### Checkpoint

```console
$ zig build
$ ./zig-out/bin/seek fox nope.txt
seek: nope.txt: FileNotFound
[exit 2]
$ ./zig-out/bin/seek fox testdata/notes
seek: testdata/notes: IsDir
[exit 2]
$ ./zig-out/bin/seek -x fox testdata/poem.txt
seek: unknown flag '-x'
usage: seek [OPTIONS] PATTERN [PATH ...]
[exit 2]
$ ./zig-out/bin/seek fox
usage: seek [OPTIONS] PATTERN [PATH ...]
[exit 2]
$ ./zig-out/bin/seek
usage: seek [OPTIONS] PATTERN [PATH ...]
[exit 2]
```

The Chapter 4 searches work as before. `testdata/notes` is a directory, so reading it as a file
fails with `IsDir`; [Chapter 11](11-files-and-io.md) makes `seek` search directories. The
complete project at this point is in `project/ch05/`.

## Summary

- `?T` is "a `T` or `null`". Unwrap with `if (x) |v|`, `while (x) |v|`, `orelse`, or `.?`
  (which panics on `null`). Plain pointers can't be `null`; `?*T` can, at no extra size.
- `error{ A, B }` is an error set. `E!T` is "a `T` or an error from `E`". `!T` infers the set.
  `||` merges sets. `anyerror` holds any error.
- `try` returns the error to the caller. `catch` handles it: with a default, a block, or
  `switch (err)`. `if (x) |v| ... else |err| ...` branches on both.
- Errors and optionals are values: ignoring one is a compile error. Error switches are exhaustive.
- `errdefer` runs cleanup only when the function returns an error. It has no capture in 0.17.
- An error returned from `main` prints its name (plus an error return trace in Debug builds) and
  exits with status 1.
- `{t}` or `@errorName` gives an error's name.
- `catch unreachable` is only for impossible failures, never for outside input.
- `seek` reports file errors in one line, rejects unknown flags, and exits with 2 on trouble.

## Exercises

1. Write `parseU8(text: []const u8) ParseError!u8` without using `std.fmt`. Return
   `error.Empty`, `error.BadDigit`, or `error.TooBig` (over 255). Test `"42"`, `""`, `"4x"`, and
   `"300"`.

   <details><summary>Solution</summary>

   ```zig
   const std = @import("std");

   const ParseError = error{ Empty, BadDigit, TooBig };

   fn parseU8(text: []const u8) ParseError!u8 {
       if (text.len == 0) return error.Empty;
       var value: u16 = 0;
       for (text) |c| {
           if (c < '0' or c > '9') return error.BadDigit;
           value = value * 10 + (c - '0');
           if (value > 255) return error.TooBig;
       }
       return @intCast(value);
   }

   pub fn main() void {
       for ([_][]const u8{ "42", "", "4x", "300" }) |text| {
           if (parseU8(text)) |v| {
               std.debug.print("\"{s}\" -> {d}\n", .{ text, v });
           } else |err| {
               std.debug.print("\"{s}\" -> error.{t}\n", .{ text, err });
           }
       }
   }
   ```

   ```console
   $ zig run parse_u8.zig
   "42" -> 42
   "" -> error.Empty
   "4x" -> error.BadDigit
   "300" -> error.TooBig
   ```

   `value` is a `u16`, so `value * 10` can't overflow before the `> 255` check: it's at most
   255 × 10 + 9. The check guarantees the final `@intCast` fits.

   </details>

2. Write `safeDiv(a: i32, b: i32) ?i32` that returns `null` when `b` is 0. Use `orelse` with a
   block to print a message and `continue`.

   <details><summary>Solution</summary>

   ```zig
   const std = @import("std");

   fn safeDiv(a: i32, b: i32) ?i32 {
       if (b == 0) return null;
       return @divTrunc(a, b);
   }

   pub fn main() void {
       const pairs = [_][2]i32{ .{ 10, 3 }, .{ 7, 0 } };
       for (pairs) |p| {
           const q = safeDiv(p[0], p[1]) orelse {
               std.debug.print("{d} / {d}: undefined\n", .{ p[0], p[1] });
               continue;
           };
           std.debug.print("{d} / {d} = {d}\n", .{ p[0], p[1], q });
       }
   }
   ```

   ```console
   $ zig run safe_div.zig
   10 / 3 = 3
   7 / 0: undefined
   ```

   `[2]i32` is an array of two `i32`s; `.{ 10, 3 }` creates one.
   `@divTrunc(std.math.minInt(i32), -1)` would still overflow; handling that is a good extra
   exercise.

   </details>

3. `std.fmt.parseInt(u16, text, 10)` returns `error{ Overflow, InvalidCharacter }!u16`. Parse
   `"123"`, `"70000"`, and `"12a"`, and print a different message for each error with
   `catch |err| switch`.

   <details><summary>Solution</summary>

   ```zig
   const std = @import("std");

   pub fn main() void {
       for ([_][]const u8{ "123", "70000", "12a" }) |text| {
           const n = std.fmt.parseInt(u16, text, 10) catch |err| switch (err) {
               error.Overflow => {
                   std.debug.print("{s}: too large for a u16\n", .{text});
                   continue;
               },
               error.InvalidCharacter => {
                   std.debug.print("{s}: not a number\n", .{text});
                   continue;
               },
           };
           std.debug.print("{s}: {d}\n", .{ text, n });
       }
   }
   ```

   ```console
   $ zig run parse_int.zig
   123: 123
   70000: too large for a u16
   12a: not a number
   ```

   No `else` is needed: the switch covers the whole error set, and the compiler checks that.

   </details>

4. Predict the output, then run it:

   ```zig
   const std = @import("std");

   fn step(n: u32) !u32 {
       defer std.debug.print("defer {d}\n", .{n});
       errdefer std.debug.print("errdefer {d}\n", .{n});
       if (n == 2) return error.Two;
       return n;
   }

   pub fn main() void {
       _ = step(1) catch 0;
       _ = step(2) catch 0;
   }
   ```

   <details><summary>Solution</summary>

   ```console
   $ zig run quiz.zig
   defer 1
   errdefer 2
   defer 2
   ```

   `step(1)` succeeds, so only the `defer` runs. `step(2)` returns an error, so both run, in
   reverse order: the `errdefer` (declared last) first.

   </details>

5. `seek fox` (no PATH) prints only the usage line. Make it print `seek: missing PATH` first, the
   way unknown flags get their own message.

   <details><summary>Solution</summary>

   In `run`, replace the `const path = ...` line with:

   ```zig
   const path = argAt(args, 2) orelse {
       try stderr.writeAll("seek: missing PATH\n");
       return error.MissingPath;
   };
   ```

   ```console
   $ zig build
   $ ./zig-out/bin/seek fox
   seek: missing PATH
   usage: seek [OPTIONS] PATTERN [PATH ...]
   [exit 2]
   ```

   `orelse` accepts a block, so the message and the `return` fit in one place. Undo this change
   before continuing so your code matches the snapshots.

   </details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-5--errors-and-optionals)
