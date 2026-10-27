# Chapter 11 — Files, Directories, and I/O

This chapter covers files, directories, paths, and the `Reader` and `Writer` interfaces behind all Zig I/O. seek currently loads whole files named on the command line. By the end it streams lines, walks directories, reads stdin, skips hidden and binary files, and filters by name. It builds on [Chapter 10](10-containers.md); [Chapter 12](12-comptime.md) then generates the flag parser at compile time.

## `std.Io`: I/O is a parameter

Functions that need memory take an allocator ([Chapter 8](08-memory-and-allocators.md)). I/O works the same way: any function that touches files, the clock, or the network takes an `io: std.Io` parameter.

```zig
pub fn main(init: std.process.Init) !void {
    const io = init.io; // the program's I/O implementation
    const file = try std.Io.Dir.cwd().openFile(io, "notes.txt", .{});
    defer file.close(io);
}
```

`std.Io` is an *interface*: a state pointer (`userdata`) plus a table of functions (`vtable`). The `init.io` in `main` is a `std.Io.Threaded`: it makes ordinary blocking system calls and uses worker threads for concurrency. Other implementations exist, such as event loops on io_uring or kqueue.

Why pass I/O explicitly?

- **You can see it.** A function without `io` cannot block on a file or socket.
- **You can swap it.** The same code runs on threads or an event loop; only `main` chooses.
- **One place for concurrency.** `async`, `await`, and cancellation also go through `io` ([Chapter 15](15-concurrency.md)).

Convention: `io` comes right after the allocator (or first if there is none). Most file calls look like `thing.method(io, ...)`.

## Files

A `std.Io.Dir` is an open directory; `std.Io.Dir.cwd()` is the current one. Relative paths resolve against the `Dir` you call.

`examples/ch11/files.zig`

```zig
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const cwd: std.Io.Dir = .cwd();

    // Create (or truncate) a file and write all of `data` to it.
    try cwd.writeFile(io, .{ .sub_path = "hello.txt", .data = "hello\nworld\n" });
    // Registered first, so it runs last: after `file.close` below.
    defer cwd.deleteFile(io, "hello.txt") catch {};

    // Open the file and ask the OS about it.
    const file = try cwd.openFile(io, "hello.txt", .{});
    defer file.close(io);
    const stat = try file.stat(io);
    std.debug.print("kind: {t}, size: {d} bytes\n", .{ stat.kind, stat.size });

    // Read a whole file into memory. We own the result and must free it.
    const contents = try cwd.readFileAlloc(io, "hello.txt", gpa, .limited(1024 * 1024));
    defer gpa.free(contents);
    std.debug.print("contents: \"{f}\"\n", .{std.zig.fmtString(contents)});

    // A missing file is an ordinary error value.
    if (cwd.openFile(io, "missing.txt", .{})) |f| {
        f.close(io);
    } else |err| {
        std.debug.print("missing.txt: {t}\n", .{err});
    }

    // The limit protects you from loading a huge file by accident.
    _ = cwd.readFileAlloc(io, "hello.txt", gpa, .limited(4)) catch |err| {
        std.debug.print("with a 4-byte limit: {t}\n", .{err});
    };
}
```

```console
$ zig run examples/ch11/files.zig
kind: file, size: 12 bytes
contents: "hello\nworld\n"
missing.txt: FileNotFound
with a 4-byte limit: StreamTooLong
```

(`std.zig.fmtString` shows escapes such as `\n`.)

| Call | What it does |
|---|---|
| `dir.openFile(io, path, .{})` | Opens for reading. `.{ .mode = .read_write }` to write too. |
| `dir.createFile(io, path, .{})` | Creates or truncates a file for writing. |
| `file.close(io)` | Closes. Cannot fail, so it fits in a `defer`. |
| `file.stat(io)` / `dir.statFile(io, path, .{})` | Size, `kind` (`.file`, `.directory`, `.sym_link`, …), times. |
| `dir.readFileAlloc(io, path, gpa, .limited(n))` | Whole file into a new slice. `error.StreamTooLong` if the file reaches the limit. |
| `dir.writeFile(io, .{ .sub_path, .data })` | Creates the file and writes all bytes. |
| `dir.deleteFile(io, path)` / `dir.deleteTree(io, path)` | Removes a file / a whole tree. |
| `dir.createDirPath(io, path)` | Like `mkdir -p`. |

Open, then `defer close` on the next line. The `defer` runs however the function exits.

`readFileAlloc` suits small files you need whole, like config. For input of unknown size, like seek's files, read through a buffer: a `Reader`.

## Readers

`std.Io.Reader` is the interface for any byte source: file, pipe, socket, decompressor, or memory. A Reader owns a **buffer**. You get slices that point *into that buffer*, so most reads copy nothing.

`std.Io.Reader.fixed(bytes)` reads from a slice. It has the same methods as a file Reader, so it is handy for learning and tests.

`examples/ch11/reader.zig`

```zig
const std = @import("std");

pub fn main() !void {
    // A Reader over bytes in memory. A File.Reader offers the same API.
    var r: std.Io.Reader = .fixed("#!seek\nfirst line\nsecond line\nlast, no newline");

    // peek looks at bytes without consuming them; toss consumes them.
    const magic = try r.peek(2);
    std.debug.print("peek: {s}\n", .{magic});
    if (std.mem.eql(u8, magic, "#!")) r.toss(2);

    // takeByte consumes one byte; discardDelimiterInclusive skips past '\n'.
    std.debug.print("byte: {c}\n", .{try r.takeByte()});
    _ = try r.discardDelimiterInclusive('\n');

    // takeDelimiter returns one line without its '\n', and null at the end.
    // The last line counts even without a trailing '\n'.
    while (try r.takeDelimiter('\n')) |line| {
        std.debug.print("line: \"{s}\" ({d} bytes)\n", .{ line, line.len });
    }
}
```

```console
$ zig run examples/ch11/reader.zig
peek: #!
byte: s
line: "first line" (10 bytes)
line: "second line" (11 bytes)
line: "last, no newline" (16 bytes)
```

Common methods:

| Method | Returns | Notes |
|---|---|---|
| `takeDelimiter(d)` | `?[]u8` | Next line without `d`; `null` at end. |
| `takeDelimiterExclusive(d)` / `takeDelimiterInclusive(d)` | `[]u8` | Same, but `error.EndOfStream` at end. |
| `peek(n)` | `[]u8` | Next `n` bytes, **not consumed**. `error.EndOfStream` if fewer. |
| `toss(n)` | `void` | Consume `n` bytes you peeked. |
| `take(n)` / `takeByte()` | `[]u8` / `u8` | Consume and return. |
| `discardDelimiterInclusive(d)` | `usize` | Skip through the next `d`. |
| `buffered()` | `[]u8` | What is in the buffer now. |
| `allocRemaining(gpa, limit)` | `[]u8` | Everything left, in a new allocation. |
| `streamRemaining(w)` | `usize` | Copy everything left into a Writer. |

Errors:

- `error.ReadFailed`: the underlying read failed. The concrete reader (e.g. `File.Reader`) keeps the real cause in its `err` field.
- `error.EndOfStream`: you asked for more bytes than exist.
- `error.StreamTooLong`: a line did not fit in the buffer.

**Lifetime rule:** a returned slice points into the buffer and is valid only until the next call on that reader. Copy (`gpa.dupe`) what you keep.

### Lines longer than the buffer

A line that doesn't fit in the buffer makes `takeDelimiter` return `error.StreamTooLong`. Here an 8-byte buffer shows it. (`limited` wraps a reader with a buffer you choose; here it fakes a file reader with a tiny buffer.)

`examples/ch11/long_line.zig`

```zig
const std = @import("std");

pub fn main() !void {
    var source: std.Io.Reader = .fixed("short\nthis line is too long\nok\n");
    // Read `source` through an 8-byte buffer, like a File.Reader with a
    // tiny buffer would.
    var small_buffer: [8]u8 = undefined;
    var limited = source.limited(.unlimited, &small_buffer);
    const r = &limited.interface;

    while (true) {
        const line = r.takeDelimiter('\n') catch |err| {
            std.debug.print("error: {t}\n", .{err});
            // Skip the rest of the long line and keep going.
            _ = try r.discardDelimiterInclusive('\n');
            continue;
        } orelse break;
        std.debug.print("line: {s}\n", .{line});
    }
}
```

```console
$ zig run examples/ch11/long_line.zig
line: short
error: StreamTooLong
line: ok
```

Skipping is one option. seek instead copies a long line into a growing buffer, so no line is lost (see `nextLine` below).

### Reading a file

`file.reader(io, &buffer)` returns a `std.Io.File.Reader`: the file, the read position, and an `interface` field holding the `std.Io.Reader`. Take a **pointer** to it:

```zig
var buffer: [64 * 1024]u8 = undefined;
var file_reader = file.reader(io, &buffer);
const r: *std.Io.Reader = &file_reader.interface;
```

Two kinds:

| | Use for | Why |
|---|---|---|
| `file.reader(io, &buf)` | regular files | Positional reads; can seek, knows the size. |
| `file.readerStreaming(io, &buf)` | stdin, pipes, sockets | Front to back only; pipes cannot seek. |

### Standard input, output, and error

`std.Io.File.stdin()`, `.stdout()`, and `.stderr()` are always-open `File` values. Don't close them. This program upper-cases stdin:

`examples/ch11/stdin_upper.zig`

```zig
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var in_buffer: [4096]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &in_buffer);
    const in = &stdin_reader.interface;

    var out_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), io, &out_buffer);
    const out = &stdout_writer.interface;

    var count: usize = 0;
    while (in.takeDelimiter('\n')) |maybe_line| {
        const line = maybe_line orelse break;
        count += 1;
        for (line) |c| try out.writeByte(std.ascii.toUpper(c));
        try out.writeByte('\n');
    } else |err| switch (err) {
        // The File.Reader keeps the real OS error in `err`.
        error.ReadFailed => return stdin_reader.err.?,
        error.StreamTooLong => return error.LineTooLong,
    }
    try out.print("{d} lines\n", .{count});
    try out.flush();
}
```

```console
$ printf 'hello\nzig\n' | zig run examples/ch11/stdin_upper.zig
HELLO
ZIG
2 lines
$ printf 'no newline' | zig run examples/ch11/stdin_upper.zig
NO NEWLINE
1 lines
```

Note the loop shape. `takeDelimiter` returns `error{...}!?[]u8`, an error union around an optional. `while (expr) |maybe_line| ... else |err|` unwraps the error; `orelse break` unwraps the optional. seek uses this shape too.

## Writers

`std.Io.Writer` is the output side. It also owns a buffer. Writes fill the buffer; when it is full, or when you call `flush`, the bytes go to the destination in one system call.

`examples/ch11/writer.zig`

```zig
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var buffer: [256]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &buffer);
    const out = &stdout_writer.interface;

    try out.writeAll("name    score\n");
    try out.splatByteAll('-', 13);
    try out.writeByte('\n');
    for ([_][]const u8{ "ada", "linus" }, [_]u32{ 42, 7 }) |name, score| {
        try out.print("{s:<7} {d:>5}\n", .{ name, score });
    }

    // Nothing has reached stdout yet: it is all in `buffer`.
    std.debug.print("(stderr) {d} bytes buffered\n", .{out.buffered().len});
    try out.flush();

    // A fixed writer writes into an array and fails when it is full.
    var small: [8]u8 = undefined;
    var fixed: std.Io.Writer = .fixed(&small);
    fixed.writeAll("123456789") catch |err| {
        std.debug.print("(stderr) fixed: {t} after \"{s}\"\n", .{ err, fixed.buffered() });
    };
}
```

```console
$ zig run examples/ch11/writer.zig
(stderr) 56 bytes buffered
name    score
-------------
ada        42
linus       7
(stderr) fixed: WriteFailed after "12345678"
```

The stderr line prints first, though the code writes the table first: the table waited in `buffer` until `flush`. `std.debug.print` is unbuffered.

| Method | Does |
|---|---|
| `writeAll(bytes)` | Write a slice. |
| `writeByte(b)` | Write one byte. |
| `print(fmt, args)` | Formatted output ([Chapter 9](09-strings-and-formatting.md)). |
| `splatByteAll(b, n)` | Write `b` `n` times. |
| `flush()` | Send the buffer to the destination. |
| `buffered()` | Bytes waiting in the buffer. |

The only write error is `error.WriteFailed`. The concrete `File.Writer` keeps the real cause in its `err` field.

### Why `flush` matters

**Forget `flush` and the output is lost.** Copy `writer.zig` to `no_flush.zig`, delete `try out.flush();`, and run it:

```console
$ zig run no_flush.zig
(stderr) 56 bytes buffered
(stderr) fixed: WriteFailed after "12345678"
```

The table never appears. Zig has no destructors, so nothing flushes for you; the stack buffer just vanishes on return. So:

- Flush once at the end of `main` (seek does).
- Flush stdout *before* writing to stderr when terminal order matters (seek's `reportError` does).
- Size the buffer for the job. 4 KiB is a good default; bigger means fewer system calls.

Why buffer? Unbuffered, each `writeAll` is a system call: a million short lines, a million calls. A 4 KiB buffer cuts that to a few thousand.

### Gotcha: take a pointer to `interface`, never a copy

The interface must stay *inside* its `File.Writer`: its functions find the `File.Writer` from the interface's address ([Chapter 14](14-polymorphism.md) shows how). A copy lives elsewhere, so they read garbage:

```zig
const stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &buffer);
var out = stdout_writer.interface; // a copy: wrong
try out.writeAll("hello\n");
try out.flush();
```

```console
$ zig run copy_iface.zig
Segmentation fault at address 0x79
.../lib/std/Io.zig:556:29: 0x103e316 in operate (std.zig)
    return io.vtable.operate(io.userdata, operation);
                            ^
...
```

(Addresses vary.) Always write `const out = &stdout_writer.interface;` with `var stdout_writer`. The compiler often catches the slip: `var stdout_writer` plus only a copy of `.interface` gives `error: local variable is never mutated`, a hint you forgot the `&`.

### Writers into memory

| Writer | Writes into | When full |
|---|---|---|
| `std.Io.Writer.fixed(&array)` | a fixed array | `error.WriteFailed` |
| `std.Io.Writer.Allocating.init(gpa)` | a growing heap buffer | grows (fails only when out of memory) |
| `std.Io.Writer.Discarding` | nowhere (counts bytes) | never |

`Allocating` builds a string of unknown length: `aw.writer` is the Writer, `aw.written()` the result, `aw.deinit()` frees it. seek uses one for very long lines.

## Directories

Open the directory with `.iterate = true`, then pick a tool:

| Tool | Visits | Entry gives you |
|---|---|---|
| `dir.iterate()` | direct children | `name`, `kind` |
| `dir.walk(gpa)` | every level | `path` (relative to `dir`), `basename`, `kind`, `dir` |
| `dir.walkSelectively(gpa)` | only directories you `enter` | same as `walk` |

`examples/ch11/list_dir.zig`

```zig
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const cwd: std.Io.Dir = .cwd();

    // Build a small tree to explore, and remove it when we are done.
    try cwd.createDirPath(io, "demo-tree/src/util");
    defer cwd.deleteTree(io, "demo-tree") catch {};
    try cwd.writeFile(io, .{ .sub_path = "demo-tree/README.md", .data = "hi\n" });
    try cwd.writeFile(io, .{ .sub_path = "demo-tree/src/main.zig", .data = "" });
    try cwd.writeFile(io, .{ .sub_path = "demo-tree/src/util/str.zig", .data = "" });

    // `.iterate = true` is required to list a directory's entries.
    var dir = try cwd.openDir(io, "demo-tree", .{ .iterate = true });
    defer dir.close(io);

    // One level: iterate(). Entry names are only valid until the next call.
    std.debug.print("top level:\n", .{});
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        std.debug.print("  {t:<9} {s}\n", .{ entry.kind, entry.name });
    }

    // Every level: walk(). The OS decides the order, so collect and sort.
    var paths: std.ArrayList([]u8) = .empty;
    defer {
        for (paths.items) |p| gpa.free(p);
        paths.deinit(gpa);
    }
    var walker = try dir.walk(gpa);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        // entry.path is reused by the next call, so copy it.
        try paths.append(gpa, try gpa.dupe(u8, entry.path));
    }
    std.mem.sort([]u8, paths.items, {}, lessThan);

    std.debug.print("all files:\n", .{});
    for (paths.items) |p| std.debug.print("  {s}\n", .{p});
}

fn lessThan(_: void, a: []u8, b: []u8) bool {
    return std.mem.lessThan(u8, a, b);
}
```

```console
$ zig run examples/ch11/list_dir.zig
top level:
  directory src
  file      README.md
all files:
  README.md
  src/main.zig
  src/util/str.zig
```

Things to know:

- **Order is undefined.** The file system decides; your "top level" order may differ. Sort for stable output.
- **Entries are borrowed.** `entry.name`, `entry.path`, and `entry.basename` change on the next `next()`. Copy what you keep (the ownership rule from [Chapter 10](10-containers.md)).
- **Forgetting `.iterate = true`** doesn't fail at `openDir`. In Debug it crashes later with `panic: programmer bug caused syscall error: BADF`. If you see that while listing, check the open options.
- **`walk` enters every directory**, even ones like `.git`. With `walkSelectively` you call `walker.enter(io, entry)` only for directories you want; the rest are never read.
- `walk` doesn't follow symbolic links to directories; a link has `kind == .sym_link`.

## Paths

`std.fs.path` works on path *strings*; it never touches the disk.

`examples/ch11/paths.zig`

```zig
const std = @import("std");
const path = std.fs.path;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    const joined = try path.join(gpa, &.{ "src", "util", "str.zig" });
    defer gpa.free(joined);

    std.debug.print("join:      {s}\n", .{joined});
    std.debug.print("basename:  {s}\n", .{path.basename(joined)});
    std.debug.print("dirname:   {?s}\n", .{path.dirname(joined)});
    std.debug.print("extension: {s}\n", .{path.extension(joined)});
    std.debug.print("stem:      {s}\n", .{path.stem(joined)});
    std.debug.print("dirname of \"str.zig\": {?s}\n", .{path.dirname("str.zig")});
    std.debug.print("absolute?  {} {}\n", .{ path.isAbsolute(joined), path.isAbsolute("/etc") });
}
```

```console
$ zig run examples/ch11/paths.zig
join:      src/util/str.zig
basename:  str.zig
dirname:   src/util
extension: .zig
stem:      str
dirname of "str.zig": null
absolute?  false true
```

- `join` allocates. It uses the platform separator (`/`, or `\` on Windows) and handles separators already at the edges of parts.
- `basename`, `dirname`, `extension`, and `stem` return slices of the input: nothing to free.
- `dirname` returns `?[]const u8`; a bare file name has no directory.

## Detecting binary files

grep-like tools skip binary files. A common test: a NUL byte in the first few KiB means binary. Text files almost never contain NUL.

`peek` fits: it fills the buffer and shows the start of the input without consuming it, so line reading still starts at byte 0.

`examples/ch11/binary.zig`

```zig
const std = @import("std");

/// Reports whether the first `probe_len` bytes contain a NUL byte.
/// peek leaves the bytes in the reader, so reading can continue normally.
fn looksBinary(reader: *std.Io.Reader, probe_len: usize) !bool {
    const head = reader.peek(probe_len) catch |err| switch (err) {
        // Shorter input: everything there is is already buffered.
        error.EndOfStream => reader.buffered(),
        else => |e| return e,
    };
    return std.mem.findScalar(u8, head, 0) != null;
}

pub fn main() !void {
    const inputs = [_][]const u8{ "plain text\n", "fox\x00binary\n", "" };
    for (inputs) |bytes| {
        var r: std.Io.Reader = .fixed(bytes);
        const binary = try looksBinary(&r, 8);
        // Nothing was consumed: the first line is still there.
        const first = try r.takeDelimiter('\n') orelse "(empty)";
        std.debug.print("binary={} first line: \"{f}\"\n", .{ binary, std.zig.fmtString(first) });
    }
}
```

```console
$ zig run examples/ch11/binary.zig
binary=false first line: "plain text"
binary=true first line: "fox\x00binary"
binary=false first line: "(empty)"
```

`peek(n)` needs a buffer of at least `n` bytes. seek's buffer is 64 KiB and its probe 8 KiB, so it fits.

## Is stdout a terminal?

Tools often act differently when a person is watching, e.g. color on a terminal but not in a pipe. `file.isTty(io)` tells you which.

`examples/ch11/is_tty.zig`

```zig
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const stdout_tty = try std.Io.File.stdout().isTty(io);
    const stdin_tty = try std.Io.File.stdin().isTty(io);
    std.debug.print("stdout is a terminal: {}\n", .{stdout_tty});
    std.debug.print("stdin is a terminal:  {}\n", .{stdin_tty});
}
```

Run in a terminal, then with stdout piped:

```console
$ zig run examples/ch11/is_tty.zig
stdout is a terminal: true
stdin is a terminal:  true
$ zig run examples/ch11/is_tty.zig | cat
stdout is a terminal: false
stdin is a terminal:  true
```

seek's `--color auto` uses this in [Chapter 19](19-low-level.md). Until then, `auto` means `never`.

## Building seek: recursive search and streaming lines

What changes:

- **Directories** are walked recursively. Files in each directory are sorted, so output is the same everywhere.
- **Hidden** entries (names starting with `.`) are skipped unless `--hidden`.
- **`--glob GLOB`** keeps only files whose base name matches a shell wildcard (`*`, `?`).
- **No PATH** means `.`; **`-`** means stdin.
- **Streaming:** files are read line by line through a 64 KiB buffer, so memory no longer depends on file size.
- **Binary** files (NUL in the first 8 KiB) are skipped silently.

### A binary test file

Add a binary fixture next to the text files:

```console
$ printf 'fox\000binary\n' > testdata/data.bin
```

### The wildcard matcher: `src/match.zig` (new)

`--glob '*.md'` needs a wildcard matcher. A recursive one is short but can take exponential time on patterns like `*a*a*a*b`. The iterative one below remembers only the latest `*`; on a mismatch it lets that star swallow one more byte and retries. That suffices: a later `*` can absorb whatever an earlier one would have.

Create `src/match.zig`:

```zig
//! Pattern matching helpers.

/// Reports whether all of `text` matches the shell-style wildcard `pattern`:
/// `*` matches any run of bytes (even an empty one), `?` matches exactly one
/// byte, and every other byte matches itself.
///
/// It walks both slices once, remembering the most recent `*`. On a
/// mismatch it backtracks: that `*` swallows one more byte of `text` and
/// matching resumes right after it. That keeps the cost at
/// O(pattern.len * text.len) in the worst case.
pub fn wildcardMatch(pattern: []const u8, text: []const u8) bool {
    var p: usize = 0; // position in pattern
    var t: usize = 0; // position in text
    var star: ?usize = null; // index of the last `*` seen in pattern
    var star_t: usize = 0; // where in text that `*` started matching

    while (t < text.len) {
        if (p < pattern.len and pattern[p] == '*') {
            // Look for `*` before comparing bytes, or a `*` in the pattern
            // would match a `*` in the text literally.
            star = p;
            star_t = t;
            p += 1; // first, let `*` match nothing
        } else if (p < pattern.len and (pattern[p] == '?' or pattern[p] == text[t])) {
            p += 1;
            t += 1;
        } else if (star) |s| {
            p = s + 1;
            star_t += 1; // let `*` match one more byte
            t = star_t;
        } else {
            return false;
        }
    }
    // Trailing `*`s match the empty rest of the text.
    while (p < pattern.len and pattern[p] == '*') p += 1;
    return p == pattern.len;
}
```

Trace `*.md` against `todo.md`: the `*` first matches nothing. `.` ≠ `t`, so the star takes `t`, `o`, `d`, `o`. Then `.md` matches and both run out together: `true`. `?usize` for `star` says "maybe a position".

### `src/main.zig`: defaults and new flags

Three edits. First, the help text gets a description and two flags:

```zig
const help = usage ++
    \\
    \\Search each PATH (default: .) for lines containing PATTERN.
    \\Directories are searched recursively; - means standard input.
    \\
    \\options:
    \\  -i            ignore case
    \\  -v            select non-matching lines
    \\  -n            show line numbers
    \\  -c            print only a count of selected lines per file
    \\  -l            print only the names of files with selected lines
    \\  -m N          stop after N selected lines per file
    \\  --hidden      search hidden files and directories
    \\  --glob GLOB   only search files whose name matches GLOB (* and ?)
    \\  --color WHEN  highlight matches: auto, always, never
    \\  -h, --help    show this help
    \\  --version     show the version
    \\
;
```

Second, a missing PATH is no longer an error. Remove `MissingPath` from `UsageError` and from the usage-error list in `main`:

```zig
/// Mistakes in how seek was called.
const UsageError = error{ UnknownFlag, MissingValue, InvalidValue, MissingPattern };
```

```zig
    const status = run(init.gpa, init.io, args, stdout, stderr) catch |err| switch (err) {
        error.UnknownFlag,
        error.MissingValue,
        error.InvalidValue,
        error.MissingPattern,
        => blk: {
            try stderr.writeAll(usage);
            break :blk .trouble;
        },
        error.OutOfMemory, error.WriteFailed => |e| return e,
    };
```

Third, `parseArgs` handles `--hidden` and `--glob` (just before the `--color` branch) and defaults the paths at the end. The complete function:

```zig
fn parseArgs(args: []const [:0]const u8, stderr: *std.Io.Writer) (UsageError || std.Io.Writer.Error)!Command {
    var options: Options = .{};
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        // "-" alone is a PATH (standard input, later), not an option.
        if (arg.len < 2 or arg[0] != '-') break;
        // "--" ends the options, so `seek -- -v` searches for "-v".
        if (eql(arg, "--")) {
            i += 1;
            break;
        }
        if (eql(arg, "--version")) return .version;
        if (eql(arg, "-h") or eql(arg, "--help")) return .help;

        if (eql(arg, "-i")) {
            options.ignore_case = true;
        } else if (eql(arg, "-v")) {
            options.invert = true;
        } else if (eql(arg, "-n")) {
            options.line_numbers = true;
        } else if (eql(arg, "-c")) {
            options.count_only = true;
        } else if (eql(arg, "-l")) {
            options.files_only = true;
        } else if (eql(arg, "-m")) {
            const value = try takeValue(args, &i, stderr);
            options.max_count = std.fmt.parseInt(usize, value, 10) catch {
                try stderr.print("seek: invalid value '{s}' for {s}\n", .{ value, arg });
                return error.InvalidValue;
            };
        } else if (eql(arg, "--hidden")) {
            options.hidden = true;
        } else if (eql(arg, "--glob")) {
            options.glob = try takeValue(args, &i, stderr);
        } else if (eql(arg, "--color")) {
            const value = try takeValue(args, &i, stderr);
            // Turn "always" into Color.always; null if no tag has that name.
            options.color = std.meta.stringToEnum(Color, value) orelse {
                try stderr.print("seek: invalid value '{s}' for {s}\n", .{ value, arg });
                return error.InvalidValue;
            };
        } else {
            try stderr.print("seek: unknown flag '{s}'\n", .{arg});
            return error.UnknownFlag;
        }
    }
    if (i >= args.len) return error.MissingPattern;
    const paths = args[i + 1 ..];
    return .{
        .search = .{
            .options = options,
            .pattern = args[i],
            // No PATH means the current directory.
            .paths = if (paths.len > 0) paths else &.{"."},
        },
    };
}
```

`&.{"."}` points to a one-element array built at compile time that lives for the whole program. It coerces to `[]const [:0]const u8`, like `paths`.

### `src/search.zig`: imports and constants

At the top, add `Io` and the matcher, and replace `max_file_size` with two constants:

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const wildcardMatch = @import("match.zig").wildcardMatch;

/// Size of the buffer each file is read through. Lines longer than this
/// still work, they just take a slower path (see `nextLine`).
const read_buffer_len = 64 * 1024;

/// A file is binary if a NUL byte appears in its first 8 KiB.
const binary_probe_len = 8 * 1024;
```

The `Options` doc comment drops "The flags arrive in Chapters 9 to 11." (`hidden` and `glob` exist since [Chapter 7](07-structs-enums-unions.md)). The `Searcher` doc comment now calls the arena scratch memory, since it no longer holds whole files:

```zig
/// Memory: the Searcher owns a copy of the pattern and of every path
/// (allocated with `gpa`), plus an arena for per-file scratch memory that is
/// reset after every file. Call `deinit` to free everything.
```

### Collecting paths: `addPath`, `addFile`, `addDirectory`

Replace `addPath` in `Searcher` with these three methods:

```zig
    /// Queues `path` for searching: a file, "-" for standard input, or a
    /// directory, which is walked recursively.
    pub fn addPath(self: *Searcher, path: []const u8) (Allocator.Error || Io.Writer.Error)!void {
        if (!std.mem.eql(u8, path, "-")) {
            // If stat fails we queue the path anyway: opening it later
            // reports the error, in order with the other output.
            if (Io.Dir.cwd().statFile(self.io, path, .{})) |stat| {
                if (stat.kind == .directory) return self.addDirectory(path);
            } else |_| {}
        }
        try self.addFile(try self.gpa.dupe(u8, path));
    }

    /// Takes ownership of `path` and queues it.
    fn addFile(self: *Searcher, path: []const u8) Allocator.Error!void {
        // If append fails, nobody else will ever free `path`.
        errdefer self.gpa.free(path);
        try self.files.append(self.gpa, path);
    }

    /// Queues every file below `root`, skipping hidden entries (unless
    /// --hidden) and files whose name doesn't match --glob.
    fn addDirectory(self: *Searcher, root: []const u8) (Allocator.Error || Io.Writer.Error)!void {
        var dir = Io.Dir.cwd().openDir(self.io, root, .{ .iterate = true }) catch |err| {
            return self.reportError(root, err);
        };
        defer dir.close(self.io);

        // A selective walker only descends into directories we `enter`,
        // so hidden directories are skipped without reading them at all.
        var walker = try dir.walkSelectively(self.gpa);
        defer walker.deinit();

        const first_new = self.files.items.len;
        while (walker.next(self.io)) |maybe_entry| {
            const entry = maybe_entry orelse break;
            if (!self.options.hidden and entry.basename[0] == '.') continue;
            switch (entry.kind) {
                .directory => walker.enter(self.io, entry) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    else => {
                        const sub = try std.fs.path.join(self.gpa, &.{ root, entry.path });
                        defer self.gpa.free(sub);
                        try self.reportError(sub, err);
                    },
                },
                .file => {
                    if (self.options.glob) |glob| {
                        if (!wildcardMatch(glob, entry.basename)) continue;
                    }
                    // `entry.path` is relative to `root` and only valid until
                    // the next call to `next`, so we build an owned copy.
                    // Searching "." prints `poem.txt` rather than `./poem.txt`.
                    const path = if (std.mem.eql(u8, root, "."))
                        try self.gpa.dupe(u8, entry.path)
                    else
                        try std.fs.path.join(self.gpa, &.{ root, entry.path });
                    try self.addFile(path);
                },
                // Symbolic links, sockets, devices, ...: not searched.
                else => {},
            }
        } else |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => try self.reportError(root, err),
        }

        // The order a directory lists its entries in depends on the file
        // system. Sorting makes the output the same on every machine.
        std.mem.sort([]const u8, self.files.items[first_new..], {}, pathLessThan);
    }
```

Notes:

- `if (statFile(...)) |stat| { ... } else |_| {}` is an `if` over an error union. If `stat` fails, the path is queued anyway; opening it later reports the error in order with the other output.
- `addFile` **takes ownership** of an allocated path. Both callers allocate (`dupe` or `join`), so the ownership rule lives in one place.
- `walker.next` returns `Error!?Entry`, like `takeDelimiter`, so the loop has the same shape.
- A directory we cannot enter (e.g. no permission) is reported, and the walk goes on.
- Sorting only `items[first_new..]` keeps the roots in command-line order: `seek fox b a` searches `b` first.

At the end of the file, below `Searcher`, add the comparison function:

```zig
fn pathLessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}
```

### Reading through a buffer: `searchAll`, `searchFile`, `searchReader`

`searchAll` only changes its error set: `searchFile` can now run out of memory (for long lines):

```zig
    /// Searches every queued file, in order.
    pub fn searchAll(self: *Searcher) (Allocator.Error || Io.Writer.Error)!void {
        for (self.files.items) |path| try self.searchFile(path);
    }
```

Replace `searchFile`:

```zig
    /// Searches one file ("-" is standard input). Problems are reported,
    /// not returned: a file we cannot read must not stop the whole search.
    fn searchFile(self: *Searcher, path: []const u8) (Allocator.Error || Io.Writer.Error)!void {
        // Free this file's scratch memory (keeping the capacity) on return.
        defer _ = self.file_arena.reset(.retain_capacity);

        const is_stdin = std.mem.eql(u8, path, "-");
        const file: Io.File = if (is_stdin) .stdin() else Io.Dir.cwd().openFile(self.io, path, .{}) catch |err| {
            return self.reportError(path, err);
        };
        defer if (!is_stdin) file.close(self.io);

        // Stdin may be a pipe, which can only be read front to back
        // ("streaming"); regular files can be read at any position.
        var buffer: [read_buffer_len]u8 = undefined;
        var file_reader = if (is_stdin) file.readerStreaming(self.io, &buffer) else file.reader(self.io, &buffer);
        const name = if (is_stdin) "(standard input)" else path;

        const result = self.searchReader(&file_reader.interface, name) catch |err| switch (err) {
            // The Io.Reader interface only says "read failed"; the concrete
            // File.Reader remembers why.
            error.ReadFailed => return self.reportError(path, file_reader.err.?),
            else => |e| return e,
        };
        // Binary files are skipped silently.
        const matches = result orelse return;
        if (matches > 0) self.matched_any = true;

        // -l wins over -c, like in grep.
        if (self.options.files_only) {
            if (matches > 0) try self.stdout.print("{s}\n", .{name});
        } else if (self.options.count_only) {
            try self.stdout.print("{s}:{d}\n", .{ name, matches });
        }
    }
```

- The 64 KiB buffer is a local array on the stack: no allocation per file.
- Stdin is never closed (`defer if (!is_stdin) ...`).
- `searchReader` returns `!?usize`: an error, `null` for binary, or a count. `result orelse return` handles binary.
- `reportError` returns `Io.Writer.Error`, which fits our return type, so `return self.reportError(...)` works.

Replace `searchText` with `searchReader`. Only the signature, the binary check, and the line source change:

```zig
    /// Reads `reader` line by line and returns how many lines are selected,
    /// printing them unless -c or -l asked for a summary instead, or null if
    /// the input looks binary. A line is selected when it contains the
    /// pattern, or, with -v, when it doesn't. Stops early at the -m limit.
    fn searchReader(self: *Searcher, reader: *Io.Reader, path: []const u8) (error{ReadFailed} || Allocator.Error || Io.Writer.Error)!?usize {
        if (try looksBinary(reader)) return null;

        // Inverted matches have nothing to highlight. `auto` behaves like
        // `never` until Chapter 19 teaches seek to detect a terminal.
        const highlight: ?Highlight = if (self.options.color == .always and !self.options.invert)
            .{ .pattern = self.pattern, .find = self.find }
        else
            null;

        // For -l, one selected line answers the question.
        const limit: usize = if (self.options.files_only) 1 else self.options.max_count orelse std.math.maxInt(usize);
        const print_lines = !self.options.count_only and !self.options.files_only;

        var long_line: Io.Writer.Allocating = .init(self.file_arena.allocator());
        var matches: usize = 0;
        var line_number: usize = 1;
        while (matches < limit) : (line_number += 1) {
            const line = try nextLine(reader, &long_line) orelse break;
            const found = self.find(line, self.pattern) != null;
            if (found == self.options.invert) continue;
            matches += 1;
            if (!print_lines) continue;
            const match: Match = .{
                .path = path,
                .line_number = if (self.options.line_numbers) line_number else null,
                .text = line,
                .highlight = highlight,
            };
            try self.stdout.print("{f}\n", .{match});
        }
        return matches;
    }
```

The old trailing-newline special case is gone: `takeDelimiter` treats a final `\n` as the end of the last line.

### Binary detection and long lines

Add two helpers at the end of the file, after `pathLessThan`:

```zig
/// Peeks at the start of the input, without consuming it, and reports
/// whether it contains a NUL byte.
fn looksBinary(reader: *Io.Reader) error{ReadFailed}!bool {
    const head = reader.peek(binary_probe_len) catch |err| switch (err) {
        // A short input: everything there is is now in the buffer.
        error.EndOfStream => reader.buffered(),
        error.ReadFailed => |e| return e,
    };
    return std.mem.findScalar(u8, head, 0) != null;
}

/// Returns the next line without its '\n', or null at the end of the input.
/// Normally the line is a slice of the reader's buffer. A line that doesn't
/// fit in the buffer is copied into `long_line` instead, so no line is too
/// long to search. Either way the slice is valid until the next call.
fn nextLine(reader: *Io.Reader, long_line: *Io.Writer.Allocating) (error{ReadFailed} || Allocator.Error)!?[]const u8 {
    if (reader.takeDelimiter('\n')) |line| {
        return line;
    } else |err| switch (err) {
        error.ReadFailed => |e| return e,
        error.StreamTooLong => {},
    }
    long_line.clearRetainingCapacity();
    _ = reader.streamDelimiterEnding(&long_line.writer, '\n') catch |err| switch (err) {
        error.ReadFailed => |e| return e,
        // An Allocating writer only fails when it can't allocate.
        error.WriteFailed => return error.OutOfMemory,
    };
    // Unless the input ended, the '\n' is still buffered: skip it.
    if (reader.bufferedLen() > 0) reader.toss(1);
    return long_line.written();
}
```

`nextLine` is a fast path plus a fallback:

1. Usually `takeDelimiter` returns a slice of the 64 KiB buffer. No copy.
2. A line longer than the buffer: `streamDelimiterEnding` copies bytes into an `Allocating` writer up to `\n` or end of input. It leaves the `\n`, so `toss(1)` skips it.
3. The `Allocating` writer uses the file arena, which `searchFile` resets after each file.

Error sets stay precise. `looksBinary` can only fail with `ReadFailed`. `nextLine` maps `WriteFailed` (for an `Allocating` writer, only "out of memory") to `OutOfMemory`.

### Checkpoint

```console
$ zig build
$ ./zig-out/bin/seek fox testdata
testdata/notes/log.txt:2024-01-01 saw a fox near the barn
testdata/notes/log.txt:2024-01-03 fox tracks in the snow
testdata/notes/todo.md:- feed the fox
testdata/poem.txt:The quick brown fox
$ ./zig-out/bin/seek -n -i fox testdata
testdata/notes/log.txt:1:2024-01-01 saw a fox near the barn
testdata/notes/log.txt:3:2024-01-03 fox tracks in the snow
testdata/notes/todo.md:2:- feed the fox
testdata/poem.txt:1:The quick brown fox
testdata/poem.txt:3:A Fox is quick and clever;
testdata/poem.txt:5:Foxes everywhere!
$ ./zig-out/bin/seek --hidden fox testdata
testdata/.secret.txt:the fox knows a secret
testdata/notes/log.txt:2024-01-01 saw a fox near the barn
testdata/notes/log.txt:2024-01-03 fox tracks in the snow
testdata/notes/todo.md:- feed the fox
testdata/poem.txt:The quick brown fox
$ ./zig-out/bin/seek --glob '*.md' fox testdata
testdata/notes/todo.md:- feed the fox
$ ./zig-out/bin/seek --glob '*.txt' -c fox testdata
testdata/notes/log.txt:2
testdata/poem.txt:1
$ ./zig-out/bin/seek fox testdata/data.bin; echo "exit $?"
exit 1
$ printf 'one fox\ntwo dogs\n' | ./zig-out/bin/seek -n fox -
(standard input):1:one fox
$ ./zig-out/bin/seek -i fox - < testdata/poem.txt
(standard input):The quick brown fox
(standard input):A Fox is quick and clever;
(standard input):Foxes everywhere!
$ cd testdata && ../zig-out/bin/seek -l fox; cd ..
notes/log.txt
notes/todo.md
poem.txt
$ ./zig-out/bin/seek fox testdata nope.txt; echo "exit $?"
testdata/notes/log.txt:2024-01-01 saw a fox near the barn
testdata/notes/log.txt:2024-01-03 fox tracks in the snow
testdata/notes/todo.md:- feed the fox
testdata/poem.txt:The quick brown fox
seek: nope.txt: FileNotFound
exit 2
```

From the project root, the hidden and binary rules work together: `.zig-cache/` is hidden, and `zig-out/bin/seek` contains "usage" but is binary:

```console
$ ./zig-out/bin/seek -l usage
src/main.zig
```

Things to notice:

- **Quote globs**, or the shell expands `*.md` before seek sees it.
- **Hidden-skipping and `--glob` apply only to walked files.** A path you name is always searched: `seek fox testdata/.secret.txt` works.
- **Order:** files are sorted within each root, by bytes (uppercase before lowercase).
- **No PATH means `.`, not stdin** (unlike grep). Use `-` for stdin.
- **CRLF files:** lines keep their `\r`, printed as-is (`^M` under `cat -v`). A known limitation.

The complete project at this point is in `project/ch11/`.

## Summary

- I/O goes through `std.Io`, passed explicitly like an allocator. `init.io` is a `std.Io.Threaded`.
- Files: `Dir.cwd()`, `openFile`, `createFile`, `close`, `stat`, `readFileAlloc` (with a limit), `writeFile`, `deleteTree`.
- `std.Io.Reader`/`Writer` are buffered interfaces. Use `&x.interface`: a pointer, never a copy.
- Reader slices are valid until the next call. `takeDelimiter` returns `?[]u8` and handles a missing final newline.
- `peek` looks ahead without consuming (binary detection).
- **Flush** writers, or output is lost. The only write error is `WriteFailed`; the concrete writer keeps the cause.
- `reader` (positional) for files, `readerStreaming` for stdin and pipes.
- Directories need `.iterate = true`. `iterate`: one level; `walk`: recursive; `walkSelectively`: you choose. Order is undefined: sort.
- `std.fs.path` works on strings. `join` allocates; `basename`, `dirname`, `extension` slice.
- `file.isTty(io)`: is a person watching?

## Exercises

1. **`head`.** Write `head.zig`: print the first 3 lines of the file named by the first argument, each prefixed with its line number. Read through a `File.Reader` with a 4 KiB buffer, not `readFileAlloc`.

   <details><summary>Solution</summary>

   ```zig
   const std = @import("std");

   pub fn main(init: std.process.Init) !void {
       const io = init.io;
       const args = try init.minimal.args.toSlice(init.arena.allocator());
       if (args.len < 2) return error.MissingPath;

       const file = try std.Io.Dir.cwd().openFile(io, args[1], .{});
       defer file.close(io);
       var buffer: [4096]u8 = undefined;
       var file_reader = file.reader(io, &buffer);
       const in = &file_reader.interface;

       var out_buffer: [4096]u8 = undefined;
       var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), io, &out_buffer);
       const out = &stdout_writer.interface;

       var n: usize = 1;
       while (n <= 3) : (n += 1) {
           const line = try in.takeDelimiter('\n') orelse break;
           try out.print("{d}: {s}\n", .{ n, line });
       }
       try out.flush();
   }
   ```

   ```console
   $ zig run head.zig -- project/ch11/testdata/poem.txt
   1: The quick brown fox
   2: jumps over the lazy dog.
   3: A Fox is quick and clever;
   ```

   </details>

2. **Extension count.** Walk a directory given on the command line; print how many files have each extension (`"(none)"` for none), sorted by extension. Hint: `std.StringHashMap(usize)` from [Chapter 10](10-containers.md); `entry.basename` is borrowed.

   <details><summary>Solution</summary>

   `std.fs.path.extension` slices the borrowed basename, so dupe it before using it as a map key.

   ```zig
   const std = @import("std");

   pub fn main(init: std.process.Init) !void {
       const io = init.io;
       const gpa = init.gpa;
       const args = try init.minimal.args.toSlice(init.arena.allocator());
       const root = if (args.len > 1) args[1] else ".";

       var dir = try std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true });
       defer dir.close(io);
       var walker = try dir.walk(gpa);
       defer walker.deinit();

       var counts: std.StringHashMap(usize) = .init(gpa);
       defer {
           var it = counts.keyIterator();
           while (it.next()) |key| gpa.free(key.*);
           counts.deinit();
       }

       while (try walker.next(io)) |entry| {
           if (entry.kind != .file) continue;
           const ext = std.fs.path.extension(entry.basename);
           const key = if (ext.len == 0) "(none)" else ext;
           const gop = try counts.getOrPut(key);
           if (!gop.found_existing) {
               gop.key_ptr.* = try gpa.dupe(u8, key);
               gop.value_ptr.* = 0;
           }
           gop.value_ptr.* += 1;
       }

       var keys: std.ArrayList([]const u8) = .empty;
       defer keys.deinit(gpa);
       var it = counts.keyIterator();
       while (it.next()) |key| try keys.append(gpa, key.*);
       std.mem.sort([]const u8, keys.items, {}, lessThan);
       for (keys.items) |key| std.debug.print("{s:<8} {d}\n", .{ key, counts.get(key).? });
   }

   fn lessThan(_: void, a: []const u8, b: []const u8) bool {
       return std.mem.lessThan(u8, a, b);
   }
   ```

   ```console
   $ zig run ext_count.zig -- project/ch11
   .bin     1
   .md      1
   .txt     3
   .zig     4
   .zon     1
   ```

   </details>

3. **Predict the output.** In `project/ch11/` after `zig build`, predict the output and exit status, then check:

   ```console
   $ ./zig-out/bin/seek fox testdata/.secret.txt
   $ ./zig-out/bin/seek --glob '*.bin' fox testdata
   $ ./zig-out/bin/seek --glob '?oem.*' -c '' testdata
   ```

   <details><summary>Solution</summary>

   ```console
   $ ./zig-out/bin/seek fox testdata/.secret.txt; echo "exit $?"
   testdata/.secret.txt:the fox knows a secret
   exit 0
   $ ./zig-out/bin/seek --glob '*.bin' fox testdata; echo "exit $?"
   exit 1
   $ ./zig-out/bin/seek --glob '?oem.*' -c '' testdata; echo "exit $?"
   testdata/poem.txt:5
   exit 0
   ```

   - A path named on the command line is never filtered as hidden.
   - `data.bin` passes the glob but is binary, so it is skipped silently. Nothing matches: exit 1.
   - The empty pattern matches every line, so `-c` counts `poem.txt`'s 5 lines.

   </details>

4. **Writer into memory.** Write `fn render(w: *std.Io.Writer, names: []const []const u8) !void` that writes the names comma-separated. Call it with a `std.Io.Writer.fixed` over a 64-byte array and with a `std.Io.Writer.Allocating`. Print both results with `std.debug.print`.

   <details><summary>Solution</summary>

   One function works with any Writer. That is the point of the interface.

   ```zig
   const std = @import("std");

   fn render(w: *std.Io.Writer, names: []const []const u8) !void {
       for (names, 0..) |name, i| {
           if (i > 0) try w.writeAll(", ");
           try w.writeAll(name);
       }
   }

   pub fn main(init: std.process.Init) !void {
       const names = [_][]const u8{ "ada", "grace", "linus" };

       var array: [64]u8 = undefined;
       var fixed: std.Io.Writer = .fixed(&array);
       try render(&fixed, &names);
       std.debug.print("fixed:      {s}\n", .{fixed.buffered()});

       var allocating: std.Io.Writer.Allocating = .init(init.gpa);
       defer allocating.deinit();
       try render(&allocating.writer, &names);
       std.debug.print("allocating: {s}\n", .{allocating.written()});
   }
   ```

   ```console
   $ zig run render.zig
   fixed:      ada, grace, linus
   allocating: ada, grace, linus
   ```

   </details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-11--files-directories-and-io)
