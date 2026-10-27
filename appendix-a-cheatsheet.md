# Appendix A — Cheat Sheet

A quick reference for Zig 0.17.0, one section per topic. Every snippet compiles with 0.17.0; most
are fragments of a function body. Links point to the chapter with the full explanation.

## Commands

| Command | Does |
|---------|------|
| `zig run file.zig -- ARGS` | Build and run one file. `-O fast` optimizes, `-lc` links libc. |
| `zig test file.zig` | Run a file's `test` blocks. `--test-filter TEXT` keeps tests whose name contains `TEXT`. |
| `zig build-exe file.zig` | Build an executable from one file. `-O small`, `-target x86_64-windows`. |
| `zig init` | Create `build.zig`, `build.zig.zon`, and `src/` in the current directory. |
| `zig build` | Run `build.zig`'s default step (`install`); output goes to `zig-out/`. |
| `zig build run -- ARGS` | Run a step named `run`, passing `ARGS` to the program. |
| `zig build test --summary all` | Run tests and show every step. |
| `zig build -Doptimize=safe` | Build mode: `debug` (default), `safe`, `fast`, `small`. `--release=safe` is the same. |
| `zig build -Dtarget=aarch64-macos` | Cross-compile. `zig targets` lists everything. |
| `zig build -l` / `zig build -h` | List the project's steps / its options and all flags. |
| `zig build --watch` | Rebuild when a source file changes. |
| `zig build test --fuzz=100K` | Run fuzz tests for 100 000 inputs. |
| `zig fmt .` / `zig fmt --check .` | Format files / only list unformatted ones. |
| `zig fetch --save URL` | Add a dependency to `build.zig.zon`. |
| `zig cc`, `zig c++` | Use Zig as a C/C++ compiler (and cross-compiler). |
| `zig env` | Show where the standard library and cache are. |
| `zig std` | Open the standard library docs in a browser. |
| `zig version`, `zig zen` | Print the version / the Zen of Zig. |

Thread Sanitizer: add `-fsanitize-thread` to `zig run`, `zig test`, or `zig build-exe`.

## Program skeleton

```zig
const std = @import("std");

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa; // leak-checked in debug/safe builds
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    if (args.len < 2) {
        std.debug.print("usage: {s} FILE\n", .{args[0]});
        return 2;
    }
    const text = try std.Io.Dir.cwd().readFileAlloc(io, args[1], gpa, .limited(1 << 20));
    defer gpa.free(text);
    try stdout.print("{s}: {d} bytes\n", .{ args[1], text.len });
    try stdout.flush(); // buffered output: don't forget
    return 0;
}

test "a test next to the code" {
    try std.testing.expect(true);
}
```

`main` may return `void`, `u8` (the exit status), `!void`, or `!u8`. A returned error is printed
(with a return trace in debug builds) and the exit status is 1. See
[Chapter 1](01-getting-started.md) and [Chapter 11](11-files-and-io.md).

## Declarations and literals

```zig
const max_len = 64; // comptime_int
const pi: f64 = 3.14159;
var counter: u32 = 0; // container-level (global) variable
```

```zig
var x: i32 = 5; // mutable, type annotated
x += 1;
const y = x * 2; // immutable, type inferred (i32)
var buf: [16]u8 = undefined; // no initial value
buf[0] = 'z';
const a, const b = .{ 1, 2 }; // destructuring
_ = .{ y, a, b, buf }; // discard values on purpose
```

```zig
const n = 1_000_000;
const h = 0xff;
const o = 0o755;
const bin = 0b1010;
const ch = 'A'; // comptime_int 65
const f = 1.5e3;
const s = "hello\n"; // *const [6:0]u8
const multi =
    \\line one
    \\line two
;
const e = .green; // enum literal
```

Unused locals and parameters are compile errors (`_ = x;` discards on purpose), and so is
shadowing an outer name. ([Chapter 2](02-values-and-types.md))

## Types

| Type | Meaning |
|------|---------|
| `i8` … `i64`, `u8` … `u64`, `u3`, `u21`, … | Integers of any width up to 65535 bits |
| `isize`, `usize` | Pointer-sized integers; `usize` for lengths and indexes |
| `comptime_int`, `comptime_float` | Types of literals: arbitrary precision, compile time only |
| `f16`, `f32`, `f64`, `f80`, `f128` | Floats |
| `bool` | `true`, `false` |
| `void` | No value (`{}`) |
| `noreturn` | Never returns: `return`, `break`, `unreachable`, `@panic` |
| `type` | A type as a value (compile time only) |
| `anyerror` | Any error |
| `[N]T`, `[_]T{…}` | Array; length is part of the type |
| `[]T`, `[]const T` | Slice: pointer + length |
| `*T`, `*const T` | Pointer to one item |
| `[*]T` | Pointer to an unknown number of items (C style) |
| `[:0]const u8`, `[*:0]const u8` | NUL-terminated (sentinel) slice / pointer |
| `?T` | Optional: a `T` or `null` |
| `E!T`, `!T` | Error union: a `T` or an error from set `E` (inferred with `!T`) |
| `@Vector(N, T)` | SIMD vector |
| `*const fn (i32) i32` | Function pointer |

Strings are `[]const u8`: bytes, usually UTF-8. ([Chapter 6](06-arrays-slices-pointers.md),
[Chapter 9](09-strings-and-formatting.md))

## Operators

| Operator | Meaning |
|----------|---------|
| `+ - * /` | Arithmetic; overflow is illegal behavior (checked in debug/safe) |
| `+% -% *%` | Wrapping arithmetic |
| `+\| -\| *\|` | Saturating arithmetic |
| `@divTrunc`, `@divFloor`, `@divCeil`, `@mod`, `@rem` | Signed division and remainder (`/` and `%` need unsigned or comptime-known operands) |
| `<< >> & \| ^ ~` | Bit operations; the shift amount type is `std.math.Log2Int(T)` |
| `and or !` | Boolean logic (short-circuit) |
| `a orelse b` | Value of optional `a`, or `b` if null |
| `a catch b` | Value of error union `a`, or `b` on error |
| `x.?` | Unwrap optional (illegal if null) |
| `p.*`, `&x` | Dereference, address of |
| `a ++ b` | Concatenate arrays (compile time) |
| `a[i..j]`, `a[i..]` | Slice |

```zig
const a: u8 = 250;
try testing.expectEqual(4, a +% 10); // wrapping
try testing.expectEqual(255, a +| 10); // saturating
try testing.expectEqual(1, @mod(-7, 2));
const maybe: ?u8 = null;
try testing.expectEqual(0, maybe orelse 0);
```

## Control flow

```zig
const kind = if (n % 2 == 0) "even" else "odd"; // if is an expression

var i: usize = 0;
while (i < 3) : (i += 1) {} // continue expression

for (0..4) |k| sum += k; // a range: 0, 1, 2, 3
for (items, 0..) |item, index| sum += item * index; // several sequences at once

const grade = switch (n) {
    0...4 => 'F',
    5, 6 => 'C',
    else => 'A',
};

const found = blk: { // labeled block with a value
    for (items) |item| if (item == 20) break :blk true;
    break :blk false;
};

outer: for (0..3) |row| {
    for (0..3) |col| if (col == row) continue :outer;
}
```

`switch` must be exhaustive. `for` loops over arrays, slices, and ranges only; for anything else,
use `while (iterator.next()) |item|`. ([Chapter 3](03-control-flow.md))

## Functions

```zig
fn add(a: i32, b: i32) i32 {
    return a + b;
}
fn maxOf(comptime T: type, a: T, b: T) T {
    return if (a > b) a else b;
}
fn twice(x: anytype) @TypeOf(x) {
    return x * 2;
}

const op: *const fn (i32, i32) i32 = &add;
```

Parameters are constants. Small structs are passed by value and large ones may be passed by
reference; don't rely on either. `pub` makes a declaration visible to other files. ([Chapter 4](04-functions.md))

## Errors

```zig
const ParseError = error{ Empty, TooLong };

fn check(s: []const u8) ParseError!usize {
    if (s.len == 0) return error.Empty;
    if (s.len > max_len) return error.TooLong;
    return s.len;
}

fn useCheck(gpa: Allocator, s: []const u8) ![]u8 {
    const n = try check(s); // on error, return it to the caller
    const copy = try gpa.alloc(u8, n);
    errdefer gpa.free(copy); // runs only if a later step fails
    @memcpy(copy, s);
    return copy;
}
```

```zig
const n = check("") catch 0; // a default on error
if (check("abc")) |len| {
    std.debug.print("{d}\n", .{len});
} else |err| switch (err) {
    error.Empty, error.TooLong => {},
}
const copy = try useCheck(gpa, "hi");
defer gpa.free(copy); // runs when the scope ends
```

`catch |err| switch (err) { … }` handles each error (exhaustively). `{t}` prints an error's name. ([Chapter 5](05-errors-and-optionals.md))

## Optionals

```zig
var maybe: ?u32 = null;
maybe = 42;
if (maybe) |value| std.debug.print("{d}\n", .{value});
const v = maybe.?; // illegal behavior if null
const idx = std.mem.findScalar(u8, "zig", 'g') orelse return error.NotFound;
while (it.next()) |word| count += word.len; // loop until null
```

## Pointers, arrays, slices

```zig
var x: u8 = 1;
const p: *u8 = &x;
p.* += 1;

var array = [_]u8{ 1, 2, 3, 4, 5 }; // [5]u8
const slice: []u8 = array[1..4]; // pointer + length
const tail = array[3..]; // *[2]u8: length known at compile time
const many: [*]u8 = &array; // unknown length
const z: [:0]const u8 = "hi"; // z[2] == 0
const zeros: [4]u8 = @splat(0); // every element 0
```

([Chapter 6](06-arrays-slices-pointers.md))

## Structs, enums, unions

```zig
const Point = struct {
    x: i32 = 0, // default value
    y: i32 = 0,

    pub const origin: Point = .{};

    pub fn init(x: i32, y: i32) Point {
        return .{ .x = x, .y = y };
    }
    pub fn moveBy(self: *Point, dx: i32) void {
        self.x += dx;
    }
};

const Color = enum(u8) { red = 1, green, blue };

const Shape = union(enum) {
    circle: f32,
    square: f32,
    pub fn area(shape: Shape) f32 {
        return switch (shape) {
            .circle => |r| 3.14 * r * r,
            .square => |side| side * side,
        };
    }
};

const Flags = packed struct(u8) { read: bool, write: bool, unused: u6 = 0 };
```

```zig
var p: Point = .init(1, 2); // decl literal: Point.init(1, 2)
p.moveBy(3); // Point.moveBy(&p, 3)
const o: Point = .origin; // decl literal: Point.origin
const c: Color = .green;
const raw = @backingInt(c); // 2
const s: Shape = .{ .square = 2 };
const f: Flags = .{ .read = true, .write = false };
const byte: u8 = @bitCast(f); // 1
const pair = .{ 1, "one" }; // tuple: pair[1]
```

Also: `extern struct` (C layout), non-exhaustive `enum(u8) { a, b, _ }`, `opaque {}`.
([Chapter 7](07-structs-enums-unions.md), [Chapter 19](19-low-level.md))

## Comptime and generics

```zig
fn Stack(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();
        items: [capacity]T = undefined,
        len: usize = 0,
        pub fn push(self: *Self, item: T) void {
            self.items[self.len] = item;
            self.len += 1;
        }
    };
}

fn fieldCount(comptime T: type) usize {
    return @typeInfo(T).@"struct".field_names.len;
}
```

```zig
var stack: Stack(u8, 4) = .{};
stack.push(7);
const squares = comptime blk: { // run a block at compile time
    var result: [4]u32 = undefined;
    for (&result, 0..) |*r, i| r.* = i * i;
    break :blk result;
};
inline for (.{ u8, u16 }) |T| { // unrolled: T is comptime-known
    _ = @bitSizeOf(T);
}
```

`@compileError("message")` stops compilation with your message. ([Chapter 12](12-comptime.md),
[Chapter 13](13-generics.md))

## Memory

```zig
const nums = try gpa.alloc(u32, 3); // slice
defer gpa.free(nums);
const one = try gpa.create(Point); // single item
defer gpa.destroy(one);
const text = try gpa.print("{d}-{s}", .{ 7, "x" }); // formatted, allocated
defer gpa.free(text);
const copy = try gpa.dupe(u8, text);
defer gpa.free(copy);

var arena: std.heap.ArenaAllocator = .init(gpa);
defer arena.deinit(); // frees everything at once

var buffer: [64]u8 = undefined;
var fba: std.heap.FixedBufferAllocator = .init(&buffer); // no heap at all

var list: std.ArrayList(u8) = .empty;
defer list.deinit(gpa);
try list.appendSlice(gpa, "abc");

var map: std.StringHashMapUnmanaged(u32) = .empty;
defer map.deinit(gpa);
try map.put(gpa, "a", 1);
```

| Allocator | Use it for |
|-----------|------------|
| `init.gpa` | General purpose; a `SafeAllocator` (leak and double-free checks) in debug/safe builds |
| `init.arena` | Memory that lives until the program exits |
| `std.heap.ArenaAllocator` | Many allocations freed together |
| `std.heap.FixedBufferAllocator` | Allocating from a buffer you provide |
| `std.heap.SafeAllocator` | Your own leak-checking allocator |
| `std.heap.page_allocator` | Whole pages from the OS; a backing allocator |
| `std.heap.c_allocator` | `malloc`/`free` (needs libc) |
| `std.testing.allocator` | Tests: fails the test on a leak |

([Chapter 8](08-memory-and-allocators.md), [Chapter 10](10-containers.md))

## Formatting

| Specifier | Prints | `255` / value → output |
|-----------|--------|------------------------|
| `{d}` | decimal number | `255` |
| `{x}`, `{X}` | hex (also bytes of a string) | `ff`, `FF` |
| `{b}`, `{o}` | binary, octal | `11111111`, `377` |
| `{c}`, `{u}` | a byte / a Unicode code point as a character | `'z'` → `z` |
| `{s}` | a string (`[]const u8`) | `"str"` → `str` |
| `{t}` | an enum tag or error name | `Color.red` → `red`, `error.Oops` → `Oops` |
| `{any}` | anything, field by field | `[_]u8{ 1, 2 }` → `{ 1, 2 }` |
| `{?d}` | an optional | `null` → `null` |
| `{f}` | call the value's `format` method | |
| `{*}` | a pointer's address | |
| `{d:>4}`, `{d:0>3}`, `{d:.2}` | width and fill, precision | `7` → `   7`, `007`; `3.14159` → `3.14` |
| `{{`, `}}` | literal braces | |

`std.debug.print` writes to stderr, unbuffered. For stdout, use a buffered `std.Io.File.Writer`
and `flush` it. ([Chapter 9](09-strings-and-formatting.md))

## Testing

```zig
test "name" {
    try std.testing.expect(ok);
    try std.testing.expectEqual(expected, actual);
    try std.testing.expectEqualStrings("abc", text);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2 }, bytes);
    try std.testing.expectError(error.Empty, check(""));
    try std.testing.checkAllAllocationFailures(std.testing.allocator, fillPlaylist, .{});
}
test check {} // a doctest: named after a declaration
```

`return error.SkipZigTest;` skips a test; `@import("builtin").is_test` is true in test builds.
([Chapter 16](16-testing.md))

## Builtin functions

| Builtin | Does |
|---------|------|
| `@import("std")`, `@import("file.zig")` | Import a module or file (a struct) |
| `@embedFile("path")` | A file's contents as a compile-time string |
| `@as(T, x)` | Coerce `x` to `T` (only safe conversions) |
| `@intCast(x)` | Integer to another integer type; checked |
| `@truncate(x)` | Keep only the low bits |
| `@floatFromInt(x)`, `@intFromFloat(x)`, `@floatCast(x)` | Number conversions |
| `@backingInt(x)`, `@fromBackingInt(n)` | Enum or `packed struct(uN)` ↔ its backing integer (`@fromBackingInt` is checked). They replace the deprecated `@intFromEnum` and `@enumFromInt`; `zig fmt` upgrades old code. |
| `@intFromBool(b)` | `true` → 1 |
| `@bitCast(x)` | Same bits, different type |
| `@ptrCast(p)`, `@alignCast(p)`, `@constCast(p)` | Pointer casts |
| `@intFromPtr(p)`, `@ptrFromInt(n)` | Pointer ↔ address |
| `@TypeOf(x)`, `@typeInfo(T)`, `@typeName(T)` | Reflection |
| `@This()` | The enclosing struct, enum, or union type |
| `@Int(.unsigned, 18)`, `@Struct(…)`, `@Enum(…)`, `@Tuple(…)` | Build a type at compile time |
| `@sizeOf(T)`, `@bitSizeOf(T)`, `@alignOf(T)`, `@offsetOf(T, "f")` | Layout |
| `@field(x, "name")` | Field or declaration by comptime name |
| `@hasField(T, "name")`, `@hasDecl(T, "name")` | Does it exist? (`@hasDecl`: public declarations only) |
| `@tagName(e)`, `@errorName(err)` | Name as a string |
| `@compileError("msg")`, `@compileLog(x)` | Stop compiling with a message / print at compile time |
| `@panic("msg")`, `@trap()` | Stop the program |
| `@min(a, b, …)`, `@max(…)`, `@abs(x)`, `@sqrt(x)` | Math |
| `@divTrunc`, `@divFloor`, `@divCeil`, `@divExact`, `@mod`, `@rem` | Division |
| `@addWithOverflow(a, b)`, `@subWithOverflow`, `@mulWithOverflow` | Result and overflow bit, as a tuple |
| `@shlExact`, `@shrExact`, `@shlWithOverflow` | Shifts that check lost bits |
| `@popCount`, `@clz`, `@ctz`, `@byteSwap`, `@bitReverse` | Bit counting and reordering |
| `@splat(x)`, `@reduce(.Add, v)`, `@select`, `@shuffle` | Vectors (and `@splat` for arrays) |
| `@memcpy(dst, src)`, `@memset(dst, x)`, `@memmove(dst, src)` | Copy and fill memory |
| `@fieldParentPtr("field", ptr)` | From a field's pointer to its parent struct |
| `@src()` | File, line, and function name |
| `@setRuntimeSafety(false)` | Turn off safety checks in this scope |
| `@setEvalBranchQuota(n)` | Allow longer compile-time loops |
| `@branchHint(.cold)` | Tell the optimizer a branch is unlikely |
| `@atomicLoad`, `@atomicStore`, `@atomicRmw`, `@cmpxchgStrong` | Atomics (prefer `std.atomic.Value`) |

Examples:

```zig
const big: u32 = 300;
const small: u8 = @intCast(big - 100); // 200; panics if it doesn't fit
const low: u8 = @truncate(big); // 0x2c
const name = @tagName(Color.green); // "green"
const U18 = @Int(.unsigned, 18); // u18
const r = @addWithOverflow(@as(u8, 250), 10); // .{ 4, 1 }
const v: @Vector(4, u8) = @splat(2);
const total = @reduce(.Add, v); // 8
```

The full list is in the language reference's
[Builtin Functions](https://ziglang.org/documentation/0.17.0/#Builtin-Functions) section.

## Standard library map

| Namespace | What's there |
|-----------|--------------|
| `std.mem` | Slices: `eql`, `find`, `findScalar`, `startsWith`, `endsWith`, `splitScalar`, `tokenizeScalar`, `trim`, `cutScalar`, `sort`, `print` (format into a buffer; replaces the deprecated `std.fmt.bufPrint`), `Allocator` |
| `std.fmt` | `parseInt`, `parseFloat`, `comptimePrint` |
| `std.ascii`, `std.unicode` | `toLower`, `isDigit`, `eqlIgnoreCase`, `findIgnoreCase`; UTF-8 validation and iteration |
| `std.math` | `maxInt`, `minInt`, `cast`, `order`, `Log2Int`, float functions |
| `std.ArrayList(T)` | Growable array (`.empty`, pass the allocator to each call) |
| `std.AutoHashMapUnmanaged`, `std.StringHashMapUnmanaged` | Hash maps; `…ArrayHashMapUnmanaged` keep insertion order |
| `std.MultiArrayList`, `std.PriorityQueue`, `std.StaticStringMap`, `std.EnumSet`, `std.EnumArray` | More containers |
| `std.heap` | Allocators: `ArenaAllocator`, `FixedBufferAllocator`, `SafeAllocator`, `page_allocator`, `smp_allocator`, `c_allocator` |
| `std.Io` | I/O interface: `Writer`, `Reader`, `File`, `Dir`, `Clock`, `Group`, `Queue`, `Mutex`, `Event`, `net` |
| `std.fs.path` | `join`, `basename`, `extension`, `dirname` |
| `std.process` | `Init` (what `main` receives), `exit` |
| `std.Thread`, `std.atomic` | `getCpuCount`, `spawn`; `atomic.Value(T)` |
| `std.json`, `std.zon` | `json.fmt`, `json.parseFromSlice`, `json.Value`; `zon.parse.fromSlice`, `zon.stringify.serialize` |
| `std.testing` | `expect…`, `allocator`, `tmpDir`, `checkAllAllocationFailures`, `fuzz` |
| `std.debug` | `print`, `assert`, `panic` |
| `std.log` | `info`, `warn`, `err`, `debug`, scoped loggers |
| `std.Random` | `DefaultPrng` and friends |
| `std.crypto`, `std.compress`, `std.http` | Hashes and ciphers, deflate and others, HTTP client and server |
| `std.simd`, `std.c` | `suggestVectorLength`; C types and libc functions |
| `std.lang` | Language-level types: `Optimize`, `Type` (what `@typeInfo` returns) |

Each lives under the `std_dir` that `zig env` prints: `std.Io.Writer` is `std/Io/Writer.zig`.

## `build.zig`

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    run.addPassthruArgs();
    b.step("run", "Run the app").dependOn(&run.step);

    const tests = b.addTest(.{ .root_module = exe.root_module });
    b.step("test", "Run unit tests").dependOn(&b.addRunArtifact(tests).step);
}
```

More pieces ([Chapter 18](18-build-system.md)):

| Want | Write |
|------|-------|
| A `-Dname=…` option | `b.option(T, "name", "description")` returns `?T` |
| Values the program can `@import` | `const o = b.addOptions(); o.addOption(T, "name", value); exe.root_module.addOptions("build_options", o);` |
| Another module | `.imports = &.{.{ .name = "bytes", .module = b.createModule(…) }}` |
| A dependency | `zig fetch --save URL`, then `b.dependency("name", .{}).module("name")` |
| libc / C sources | `.link_libc = true` in `createModule`; `module.addCSourceFile(.{ .file = b.path("x.c") })` |
| A fixed mode for one artifact | `.optimize = .fast` instead of `optimize` |

Sources for this appendix: [REFERENCES.md](REFERENCES.md#appendix-a--cheat-sheet)
