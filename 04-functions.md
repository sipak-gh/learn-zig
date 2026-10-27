# Chapter 4 — Functions

Zig functions are plain: typed parameters, one return type, no overloading, no default
arguments, no closures. This chapter covers writing and calling them, argument passing, function
pointers, the patterns that replace closures and default arguments, and `defer`. In `seek`,
you'll split the program into functions and run the first real search.
[Chapter 3](03-control-flow.md) read the command line; [Chapter 5](05-errors-and-optionals.md)
handles errors properly.

## Declaring and calling functions

`examples/ch04/functions.zig`

```zig
const std = @import("std");

// Parameters are `name: Type`. The return type comes after the parentheses.
fn add(a: i32, b: i32) i32 {
    return a + b;
}

// A function that returns nothing returns `void`.
fn greet(name: []const u8) void {
    std.debug.print("hello, {s}\n", .{name});
}

// `pub` makes a function visible to files that @import this one.
pub fn square(x: i32) i32 {
    return x * x;
}

pub fn main() void {
    greet("zig");
    const sum = add(2, 3);
    std.debug.print("2 + 3 = {d}\n", .{sum});
    // Functions can be used before they are declared: order doesn't matter.
    std.debug.print("cube(3) = {d}\n", .{cube(3)});
    // A returned value must be used. Discard it explicitly with `_`.
    _ = square(4);
}

fn cube(x: i32) i32 {
    return x * square(x);
}
```

```console
$ zig run examples/ch04/functions.zig
hello, zig
2 + 3 = 5
cube(3) = 27
```

The rules:

- **The return type is required.** Write `void` when there's nothing to return.
- **`return` is required.** There's no "last expression is the result" rule; a bare `a + b;` as
  the last line is an error, because its value is ignored.
- **Return values can't be ignored.** Calling `add(1, 2);` on its own line fails:

  ```text
  ignored.zig:5:8: error: value of type 'u32' ignored
      add(1, 2);
      ~~~^~~~~~
  ignored.zig:5:8: note: all non-void values must be used
  ignored.zig:5:8: note: to discard the value, assign it to '_'
  ```

- **Unused parameters are errors**: `error: unused function parameter`. Name the parameter `_` to
  accept and ignore it.
- **Argument counts must match.** `add(1)` gives `error: expected 2 argument(s), found 1`.
- **Order doesn't matter.** `main` calls `cube`, declared below it. File-scope declarations can
  refer to each other in any order.
- **Names are `camelCase`** for functions, `snake_case` for variables. Functions that return a
  type are `TitleCase` ([Chapter 13](13-generics.md)).

### Visibility: `pub`, `export`, and `extern`

| Keyword | Meaning |
|---------|---------|
| (none) | private to this file |
| `pub` | visible to other Zig files that `@import` this one |
| `export` | visible to the linker under its own name, with the C calling convention; for libraries used from C |
| `extern` | declared here, defined elsewhere, usually in a C library |

`main` must be `pub` so the startup code in `std` can find it. `export` and `extern` are for C
interop ([Chapter 19](19-low-level.md)).

## Parameters are constants

Every parameter is immutable. Assigning to one is a compile error:

```text
param.zig:2:5: error: cannot assign to constant
    x += 1;
    ^
```

To work with a changed value, copy it into a local `var`. To change the *caller's* value, pass a
pointer.

`examples/ch04/pass_by_value.zig`

```zig
const std = @import("std");

// Parameters are constants. To change a value, make a local copy...
fn withFirstSetTo99(values: [3]u32) [3]u32 {
    var copy = values;
    copy[0] = 99;
    return copy;
}

// ...or take a pointer to the caller's value (Chapter 6 covers pointers).
fn bump(counter: *u32) void {
    counter.* += 1;
}

pub fn main() void {
    const original = [3]u32{ 1, 2, 3 };
    const changed = withFirstSetTo99(original);
    std.debug.print("original: {any}\n", .{original});
    std.debug.print("changed:  {any}\n", .{changed});

    var count: u32 = 0;
    bump(&count);
    bump(&count);
    std.debug.print("count: {d}\n", .{count});
}
```

```console
$ zig run examples/ch04/pass_by_value.zig
original: { 1, 2, 3 }
changed:  { 99, 2, 3 }
count: 2
```

- `*u32` is "pointer to a `u32`". `&count` takes the address of `count`. `counter.*` reads or
  writes the value it points to.
- Arguments are passed **by value** as far as your code can tell. For big values, like a large
  array or struct, the compiler may pass a hidden reference instead of copying, since the
  parameter can't change anyway. Don't depend on either choice; if you need a reference, use a
  pointer.

## Recursion

A function can call itself.

`examples/ch04/recursion.zig`

```zig
const std = @import("std");

fn factorial(n: u64) u64 {
    if (n <= 1) return 1;
    return n * factorial(n - 1);
}

// Greatest common divisor, Euclid's way.
fn gcd(a: u64, b: u64) u64 {
    return if (b == 0) a else gcd(b, a % b);
}

pub fn main() void {
    std.debug.print("10! = {d}\n", .{factorial(10)});
    std.debug.print("gcd(48, 36) = {d}\n", .{gcd(48, 36)});
}
```

```console
$ zig run examples/ch04/recursion.zig
10! = 3628800
gcd(48, 36) = 12
```

Each call uses stack space, and the stack is limited (on Linux, usually 8 MiB for the main
thread). Deep recursion on untrusted input can overflow it. Prefer a loop unless the depth is
small and known.

## Function pointers

A function's type is written `fn (i32) i32`; a **function pointer** is `*const fn (i32) i32`. It
lets you pass behavior as an argument or choose it at run time.

`examples/ch04/fn_pointers.zig`

```zig
const std = @import("std");

fn double(x: i32) i32 {
    return x * 2;
}

fn negate(x: i32) i32 {
    return -x;
}

// `op` is a pointer to any function that takes an i32 and returns an i32.
fn applyAll(values: []i32, op: *const fn (i32) i32) void {
    for (values) |*v| {
        v.* = op(v.*);
    }
}

pub fn main() void {
    var values = [_]i32{ 1, 2, 3 };
    applyAll(&values, &double);
    std.debug.print("doubled: {any}\n", .{values});
    applyAll(&values, &negate);
    std.debug.print("negated: {any}\n", .{values});

    // A function pointer can be stored and chosen at run time.
    var choice: u8 = 1;
    choice += 0;
    const op: *const fn (i32) i32 = if (choice == 0) &double else &negate;
    std.debug.print("op(5) = {d}\n", .{op(5)});
}
```

```console
$ zig run examples/ch04/fn_pointers.zig
doubled: { 2, 4, 6 }
negated: { -2, -4, -6 }
op(5) = -5
```

- `&double` takes the function's address. A call through the pointer looks normal: `op(5)`.
- `values: []i32` is a *slice*, a view of some `i32`s; `&values` turns the array into one.
  [Chapter 6](06-arrays-slices-pointers.md) explains slices.
- Function pointers are how Zig builds run-time interfaces such as `std.Io.Writer`.
  [Chapter 14](14-polymorphism.md) shows how.

## No closures: pass a context

Zig has no closures. A function declared inside another can't see the outer function's locals;
the compiler stops you:

```text
closure.zig:7:24: error: mutable 'factor' not accessible from here
            return x * factor;
                       ^~~~~~
closure.zig:3:9: note: declared mutable here
    var factor: i32 = 3;
        ^~~~~~
closure.zig:5:19: note: crosses namespace boundary here
    const scale = struct {
                  ^~~~~~
```

Instead, put the data the function needs into a struct and pass the struct.

`examples/ch04/context.zig`

```zig
const std = @import("std");

// Zig has no closures. Put the captured data in a struct and give the
// struct a function that uses it (Chapter 7 covers structs and methods).
const Scaler = struct {
    factor: i32,

    fn apply(self: Scaler, x: i32) i32 {
        return x * self.factor;
    }
};

fn applyAll(values: []i32, scaler: Scaler) void {
    for (values) |*v| {
        v.* = scaler.apply(v.*);
    }
}

pub fn main() void {
    var factor: i32 = 10;
    factor += 0; // known only at run time
    var values = [_]i32{ 1, 2, 3 };
    applyAll(&values, .{ .factor = factor });
    std.debug.print("scaled: {any}\n", .{values});
}
```

```console
$ zig run examples/ch04/context.zig
scaled: { 10, 20, 30 }
```

This is more typing than a closure, but nothing is hidden: you see exactly what data the function
uses, where it lives, and for how long. `std` uses this "context" pattern for sorting and hash
maps. `.{ .factor = factor }` builds a `Scaler`; the parameter supplies the type.
[Chapter 7](07-structs-enums-unions.md) covers structs.

## No default arguments: an options struct

Zig has no default arguments and no overloading. For optional settings, take a struct whose
fields have defaults; the caller lists only what it changes.

`examples/ch04/options.zig`

```zig
const std = @import("std");

// Zig has no default arguments. Instead, take an options struct whose
// fields have default values.
const BannerOptions = struct {
    width: usize = 20,
    fill: u8 = '=',
    shout: bool = false,
};

fn banner(title: []const u8, options: BannerOptions) void {
    for (0..options.width) |_| std.debug.print("{c}", .{options.fill});
    std.debug.print("\n{s}{s}\n", .{ title, if (options.shout) "!" else "" });
}

pub fn main() void {
    banner("defaults", .{});
    banner("custom", .{ .width = 10, .fill = '*', .shout = true });
}
```

```console
$ zig run examples/ch04/options.zig
====================
defaults
**********
custom!
```

`.{}` means "all defaults", and field names make each call clear. `std` uses this pattern
everywhere; `Dir.openFile`, for example, takes an options struct, usually `.{}`.

## A preview: `anytype`

An `anytype` parameter accepts any type. The compiler builds and checks a separate version of the
function for each type it's called with.

`examples/ch04/anytype_preview.zig`

```zig
const std = @import("std");

// `anytype` accepts an argument of any type. The compiler makes a separate
// copy of the function for each type it is called with (Chapter 13).
fn twice(x: anytype) @TypeOf(x) {
    return x + x;
}

pub fn main() void {
    const a: u8 = 21;
    const b: f64 = 1.25;
    std.debug.print("{d} {d}\n", .{ twice(a), twice(b) });
}
```

```console
$ zig run examples/ch04/anytype_preview.zig
42 2.5
```

`@TypeOf(x)` is the type of `x`, so the return type follows the argument. `std.debug.print`'s
second parameter is `anytype`; that's how it accepts any tuple. [Chapter 13](13-generics.md)
covers generics.

## `inline fn` and `noreturn`

`inline fn` forces the body to be copied into every call site.

`examples/ch04/inline_fn.zig`

```zig
const std = @import("std");

// `inline fn` pastes the body into every call site. Rarely needed: the
// optimizer already inlines small functions when it helps.
inline fn isEven(n: u32) bool {
    return n % 2 == 0;
}

pub fn main() void {
    for (1..5) |i| {
        const n: u32 = @intCast(i);
        std.debug.print("{d} even? {}\n", .{ n, isEven(n) });
    }
}
```

```console
$ zig run examples/ch04/inline_fn.zig
1 even? false
2 even? true
3 even? false
4 even? true
```

Use `inline fn` only with a reason, such as making a result comptime-known at the call site. For
speed, trust the optimizer.

`noreturn` is the return type of a function that never comes back: it exits, panics, or loops
forever. A `noreturn` call fits anywhere a value of any type is expected.

`examples/ch04/noreturn.zig`

```zig
const std = @import("std");

// `noreturn` means "this function never returns to its caller".
fn fatal(message: []const u8) noreturn {
    std.debug.print("fatal: {s}\n", .{message});
    std.process.exit(2);
}

pub fn main() void {
    var config_ok = false;
    config_ok = config_ok and true; // a runtime value
    // A `noreturn` call fits anywhere a value is expected.
    const level: u8 = if (config_ok) 3 else fatal("no config");
    std.debug.print("level {d}\n", .{level});
}
```

```console
$ zig run examples/ch04/noreturn.zig
fatal: no config
$ echo $?
2
```

`std.process.exit` ends the process at once: pending `defer`s don't run and buffered writers
aren't flushed. That's why `seek` returns its status from `main` instead.

## `defer`

`defer` schedules a statement to run when the current block ends, however it ends: falling off
the end, `return`, or `break`. Several `defer`s run in **reverse** order.

`examples/ch04/defer_order.zig`

```zig
const std = @import("std");

fn work(fail: bool) u8 {
    std.debug.print("start\n", .{});
    // `defer` runs its statement when the enclosing block exits,
    // however it exits: falling off the end or `return`.
    defer std.debug.print("cleanup 1\n", .{});
    defer std.debug.print("cleanup 2\n", .{}); // runs first: reverse order
    if (fail) {
        std.debug.print("bailing out early\n", .{});
        return 1;
    }
    std.debug.print("finished\n", .{});
    return 0;
}

pub fn main() void {
    _ = work(false);
    std.debug.print("---\n", .{});
    _ = work(true);
    std.debug.print("---\n", .{});

    // Defers belong to the block they're in, so in a loop they run at the
    // end of every iteration.
    for (0..2) |i| {
        defer std.debug.print("end of iteration {d}\n", .{i});
        std.debug.print("iteration {d}\n", .{i});
    }
}
```

```console
$ zig run examples/ch04/defer_order.zig
start
finished
cleanup 2
cleanup 1
---
start
bailing out early
cleanup 2
cleanup 1
---
iteration 0
end of iteration 0
iteration 1
end of iteration 1
```

The typical use is cleanup right next to setup:

```zig
const file = try dir.openFile(io, path, .{});
defer file.close(io);
// ... use file; it is closed on every way out of this block
```

Reverse order releases things opposite to how they were acquired, which is what you want when one
depends on another. A `defer` runs only if execution reached it: a `return` *before* the `defer`
line skips it. [Chapter 5](05-errors-and-optionals.md) adds `errdefer`, which runs only when the
block exits with an error.

## Building seek: the first search

`seek` now searches. Given a PATTERN and a PATH, it reads the file and prints each line containing
the pattern, as `path:line`. Only the first PATH is searched for now;
[Chapter 6](06-arrays-slices-pointers.md) handles the rest.

### Test files

Create some files to search by running these commands in the project directory (the one with
`build.zig`). Some are used only in later chapters.

```sh
mkdir -p testdata/notes
printf 'The quick brown fox\njumps over the lazy dog.\nA Fox is quick and clever;\nthe dog just sleeps.\nFoxes everywhere!\n' > testdata/poem.txt
printf '# TODO\n- feed the fox\n- walk the dog\n- fix the fence\n' > testdata/notes/todo.md
printf '2024-01-01 saw a fox near the barn\n2024-01-02 nothing to report\n2024-01-03 fox tracks in the snow\n' > testdata/notes/log.txt
printf 'the fox knows a secret\n' > testdata/.secret.txt
```

On Windows without a POSIX shell, create the files in an editor. `testdata/poem.txt` contains:

```text
The quick brown fox
jumps over the lazy dog.
A Fox is quick and clever;
the dog just sleeps.
Foxes everywhere!
```

| File | Contents |
|------|----------|
| `testdata/notes/todo.md` | `# TODO`, `- feed the fox`, `- walk the dog`, `- fix the fence` (one per line) |
| `testdata/notes/log.txt` | `2024-01-01 saw a fox near the barn`, `2024-01-02 nothing to report`, `2024-01-03 fox tracks in the snow` |
| `testdata/.secret.txt` | `the fox knows a secret` |

Every file ends with a newline.

### The code

Replace `src/main.zig` with:

`src/main.zig`

```zig
const std = @import("std");

const version = "0.1.0";

const exit_ok: u8 = 0; // a line matched (or nothing went wrong)
const exit_no_match: u8 = 1; // nothing matched
const exit_trouble: u8 = 2; // bad usage or an error

const usage = "usage: seek [OPTIONS] PATTERN [PATH ...]\n";

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

    // main only wires things together; `run` does the work.
    const status = try run(init.io, arena, args, stdout, stderr);
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
) !u8 {
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--version")) {
            try stdout.print("seek {s}\n", .{version});
            return exit_ok;
        }
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try stdout.writeAll(usage);
            return exit_ok;
        }
    }

    // For now we need exactly a PATTERN and one PATH.
    if (args.len < 3) {
        try stderr.writeAll(usage);
        return exit_trouble;
    }
    const pattern = args[1];
    const path = args[2];

    // Read the whole file into memory. The arena frees it when seek exits.
    const contents = try std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(max_file_size));

    const matches = try searchText(stdout, path, pattern, contents);
    return if (matches > 0) exit_ok else exit_no_match;
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

### How it fits together

`main` is now only wiring. It gathers what the program needs (arguments, I/O interface, arena,
two writers), hands it to `run`, then flushes both writers and returns the status.

| Function | Job | Returns |
|----------|-----|---------|
| `main` | set up, call `run`, flush | exit status, or an error |
| `run` | handle the flags and the command line, read the file | exit status, or an error |
| `searchText` | print matching lines of one text | number of matching lines, or an error |

- **No globals.** `run` gets everything through its parameters, so its signature says exactly
  what it can touch: the I/O interface, some memory, the arguments, and two writers. That makes
  it easy to test later ([Chapter 16](16-testing.md)).
- **The parameter types.** `std.Io` is the I/O interface from `init.io`. `std.mem.Allocator` is
  what `init.arena.allocator()` returns. `*std.Io.Writer` is a pointer to a writer, exactly what
  `&stdout_writer.interface` has been all along.
- **The parameter list is long**, so it's one per line with a trailing comma, a layout `zig fmt`
  keeps.
- **`!u8` and `!usize`** mean "a `u8` (or `usize`), or an error". The compiler works out which
  errors are possible, and `try` passes any error up to the caller. Chapter 5 explains both.

### Reading a file

```zig
const contents = try std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(max_file_size));
```

| Part | Meaning |
|------|---------|
| `std.Io.Dir.cwd()` | the current working directory |
| `.readFileAlloc(...)` | read a whole file into newly allocated memory |
| `io` | the I/O interface that does the reading |
| `path` | relative to that directory (absolute paths work too) |
| `arena` | where to allocate the bytes; freed when `seek` exits |
| `.limited(max_file_size)` | fail with `error.StreamTooLong` instead of reading more than 16 MiB |

The result is a `[]u8` holding the file's bytes. Reading a whole file at once is simple and fine
for now; [Chapter 11](11-files-and-io.md) switches to streaming line by line.

### Splitting and matching

- `std.mem.endsWith(u8, text, "\n")` checks for a final newline, which `body` then drops.
  Otherwise, splitting `"a\nb\n"` on `\n` would give a third, empty line.
- `text[0 .. text.len - 1]` is a slice: all bytes except the last.
- `std.mem.splitScalar(u8, body, '\n')` returns an **iterator**. Each `lines.next()` returns the
  next line, or `null` when none are left.
- `while (lines.next()) |line|` loops until `next()` returns `null`, naming each line `line`.
  It's the optional-unwrapping `while` from [Chapter 5](05-errors-and-optionals.md); for now,
  read it as "for each line".
- `std.mem.find(u8, line, pattern)` returns the position of `pattern` in `line`, or `null`.
  `!= null` turns that into "does it contain it?". Older code calls this `std.mem.indexOf`; in
  Zig 0.17 that name is a deprecated alias of `find`.
- `searchText` doesn't change its parameters, so they're constants as usual. It keeps its count
  in a local `var`.

The search is case-sensitive: `Fox` doesn't match `fox`. [Chapter 9](09-strings-and-formatting.md)
adds `-i`.

### When the file is missing

Try a file that doesn't exist:

```console
$ zig build
$ ./zig-out/bin/seek fox nope.txt
error: FileNotFound
…/lib/std/Io/Threaded.zig:4993:35: 0x11a0fa4 in dirOpenFilePosix (std.zig)
                        .NOENT => return error.FileNotFound,
                                  ^
…/lib/std/Io/Dir.zig:581:5: 0x10374a0 in openFile (std.zig)
    return io.vtable.dirOpenFile(io.userdata, dir, sub_path, options);
    ^
…/lib/std/Io/Dir.zig:1364:16: 0x11f6db4 in readFileAllocOptions__func_824 (std.zig)
    var file = try dir.openFile(io, sub_path, .{
               ^
…/lib/std/Io/Dir.zig:1342:5: 0x11f6990 in readFileAlloc (std.zig)
    return readFileAllocOptions(dir, io, sub_path, gpa, limit, .of(u8), null);
    ^
…/src/main.zig:62:22: 0x11e918c in run (main.zig)
    const contents = try std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(max_file_size));
                     ^
…/src/main.zig:27:20: 0x11e98ab in main (main.zig)
    const status = try run(init.io, arena, args, stdout, stderr);
                   ^
[exit 1]
```

(The `…` stands for the full paths on your machine. Addresses and `std` line numbers may differ.)

`readFileAlloc` returned `error.FileNotFound`, and each `try` passed it up through `run` and out
of `main`. When `main` returns an error, Zig prints its name and, in Debug builds, an **error
return trace**: every `try` the error passed through, from where it started to `main`. The exit
status is 1.

That helps you as a developer but is wrong for a tool: users should get a one-line message, and
grep's convention says trouble is status 2, not 1. Chapter 5 fixes this.

### Checkpoint

```console
$ zig build
$ ./zig-out/bin/seek fox testdata/poem.txt
testdata/poem.txt:The quick brown fox
[exit 0]
$ ./zig-out/bin/seek dog testdata/poem.txt
testdata/poem.txt:jumps over the lazy dog.
testdata/poem.txt:the dog just sleeps.
[exit 0]
$ ./zig-out/bin/seek Fox testdata/poem.txt
testdata/poem.txt:A Fox is quick and clever;
testdata/poem.txt:Foxes everywhere!
[exit 0]
$ ./zig-out/bin/seek zebra testdata/poem.txt
[exit 1]
$ ./zig-out/bin/seek fox
usage: seek [OPTIONS] PATTERN [PATH ...]
[exit 2]
```

`seek fox` now prints usage: without a PATH there's nothing to search. The complete project at
this point is in `project/ch04/`.

## Summary

- `fn name(param: Type) ReturnType { ... }`. Return types and `return` are required. Return
  values must be used or discarded with `_ =`.
- Parameters are constants. Copy into a `var` to modify, or take a pointer (`*T`) to change the
  caller's value. Don't depend on whether the compiler copies or references.
- No access modifier means file-private. `pub` exports to other Zig files; `export`/`extern` are
  for C.
- Function pointers: `*const fn (i32) i32`, created with `&func`.
- No closures: pass a struct with the data (a "context"). No default arguments: pass an options
  struct with default field values, called with `.{ ... }`.
- `anytype` parameters accept any type; `@TypeOf(x)` gets it. More in Chapter 13.
- `inline fn` forces inlining; rarely needed. `noreturn` marks functions that never return.
- `defer` runs at block exit, in reverse order, on every exit path that reached it.
- `seek` is split into `main` (wiring), `run` (logic), and `searchText` (matching), with every
  dependency passed explicitly.

## Exercises

1. Write `max`, `min`, and `clamp(x, lo, hi)` for `i32`. Build `clamp` from the other two. Test
   with -5, 3, and 12 between 0 and 10.

   <details><summary>Solution</summary>

   ```zig
   const std = @import("std");

   fn max(a: i32, b: i32) i32 {
       return if (a > b) a else b;
   }

   fn min(a: i32, b: i32) i32 {
       return if (a < b) a else b;
   }

   fn clamp(x: i32, lo: i32, hi: i32) i32 {
       return min(max(x, lo), hi);
   }

   pub fn main() void {
       for ([_]i32{ -5, 3, 12 }) |x| {
           std.debug.print("clamp({d}, 0, 10) = {d}\n", .{ x, clamp(x, 0, 10) });
       }
   }
   ```

   ```console
   $ zig run clamp.zig
   clamp(-5, 0, 10) = 0
   clamp(3, 0, 10) = 3
   clamp(12, 0, 10) = 10
   ```

   `std` already has these as `@max`, `@min`, and `std.math.clamp`.

   </details>

2. Write a recursive `fib(n: u64) u64` and print the first 10 Fibonacci numbers, starting at 0.

   <details><summary>Solution</summary>

   ```zig
   const std = @import("std");

   fn fib(n: u64) u64 {
       if (n < 2) return n;
       return fib(n - 1) + fib(n - 2);
   }

   pub fn main() void {
       for (0..10) |n| {
           std.debug.print("{d} ", .{fib(n)});
       }
       std.debug.print("\n", .{});
   }
   ```

   ```console
   $ zig run fib.zig
   0 1 1 2 3 5 8 13 21 34 
   ```

   This version recomputes the same values many times, so it slows down fast. A loop with two
   variables is much quicker.

   </details>

3. Write `countIf(values: []const i32, pred: *const fn (i32) bool) usize`. Use it to count the
   even and the negative numbers in `{ -3, -2, 0, 5, 8, 11 }`.

   <details><summary>Solution</summary>

   ```zig
   const std = @import("std");

   fn countIf(values: []const i32, pred: *const fn (i32) bool) usize {
       var count: usize = 0;
       for (values) |v| {
           if (pred(v)) count += 1;
       }
       return count;
   }

   fn isEven(x: i32) bool {
       return @mod(x, 2) == 0;
   }

   fn isNegative(x: i32) bool {
       return x < 0;
   }

   pub fn main() void {
       const values = [_]i32{ -3, -2, 0, 5, 8, 11 };
       std.debug.print("even: {d}\n", .{countIf(&values, &isEven)});
       std.debug.print("negative: {d}\n", .{countIf(&values, &isNegative)});
   }
   ```

   ```console
   $ zig run count_if.zig
   even: 3
   negative: 2
   ```

   `x % 2` wouldn't compile for a signed `x` ([Chapter 2](02-values-and-types.md)), so `isEven`
   uses `@mod`.

   </details>

4. Predict the output, then run it:

   ```zig
   const std = @import("std");

   pub fn main() void {
       defer std.debug.print("A\n", .{});
       {
           defer std.debug.print("B\n", .{});
           std.debug.print("C\n", .{});
       }
       defer std.debug.print("D\n", .{});
       std.debug.print("E\n", .{});
   }
   ```

   <details><summary>Solution</summary>

   ```console
   $ zig run defer_quiz.zig
   C
   B
   E
   D
   A
   ```

   `B` belongs to the inner block, so it runs when that block ends, right after `C`. At the end of
   `main`, the remaining defers run in reverse: `D`, then `A`.

   </details>

5. Make `seek` search *every* PATH, not just the first. The exit status should be 0 if any file
   had a match.

   <details><summary>Solution</summary>

   In `run`, replace everything from `const pattern = args[1];` to the end of the function with:

   ```zig
   const pattern = args[1];

   var matches: usize = 0;
   for (args[2..]) |path| {
       const contents = try std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(max_file_size));
       matches += try searchText(stdout, path, pattern, contents);
   }
   return if (matches > 0) exit_ok else exit_no_match;
   ```

   ```console
   $ zig build
   $ ./zig-out/bin/seek fox testdata/poem.txt testdata/notes/todo.md testdata/notes/log.txt
   testdata/poem.txt:The quick brown fox
   testdata/notes/todo.md:- feed the fox
   testdata/notes/log.txt:2024-01-01 saw a fox near the barn
   testdata/notes/log.txt:2024-01-03 fox tracks in the snow
   [exit 0]
   ```

   One missing file still stops everything with an error trace; Chapter 5 makes `seek` report it
   and carry on. Undo this change before continuing so your code matches the snapshots.
   [Chapter 6](06-arrays-slices-pointers.md) adds multiple paths its own way.

   </details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-4--functions)
