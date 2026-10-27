# Chapter 12 — Comptime

Zig has no macros, no preprocessor, and no separate generics language. It has one idea instead: **ordinary Zig code that runs while the program compiles**. That code can build lookup tables, take types as arguments, inspect structs, and generate types. This chapter teaches comptime from the ground up, then uses it to replace seek's hand-written flag parser from [Chapter 11](11-files-and-io.md) with one generated from the `Options` struct. [Chapter 13](13-generics.md) builds generic types on the same idea.

## One idea instead of four features

Other languages need several features for these jobs. Zig uses `comptime` for all of them:

| Job | C / C++ / Rust | Zig |
|---|---|---|
| Constants computed by the compiler | `constexpr`, `const fn` | any function, called at comptime |
| Generics | templates, generics | functions that take and return `type` |
| Conditional compilation | `#ifdef`, `cfg` | `if` on a comptime-known value |
| Reflection, code generation | macros, RTTI | `@typeInfo`, `inline for`, `@field` |

Why one feature? Comptime code is just Zig: same rules, same error messages, same debugging habits. No second macro language to learn, no text substitution to surprise you.

## Comptime values, blocks, and variables

A value is **comptime-known** when the compiler can work it out: literals, `const`s initialized from comptime-known values, and types. Values that depend on input (arguments, file contents, `var`s) are **runtime-known**.

Three ways to force compile-time evaluation:

- **`comptime f(x)`** runs one call at compile time.
- **`comptime { ... }`** runs a whole block at compile time.
- **A container-level `const`** (outside any function) is always evaluated at compile time.

A `comptime var` exists only while compiling. It can change during compilation; at run time it is a constant.

`examples/ch12/comptime_basics.zig`

```zig
const std = @import("std");

fn fibonacci(n: u32) u64 {
    var a: u64 = 0;
    var b: u64 = 1;
    for (0..n) |_| {
        const next = a + b;
        a = b;
        b = next;
    }
    return a;
}

/// A 256-entry table: true for bytes that may appear in an identifier.
/// The loop runs inside the compiler; the program only contains the result.
const is_ident = blk: {
    var table: [256]bool = @splat(false); // every element false
    for ('a'..'z' + 1) |c| table[c] = true;
    for ('A'..'Z' + 1) |c| table[c] = true;
    for ('0'..'9' + 1) |c| table[c] = true;
    table['_'] = true;
    break :blk table;
};

pub fn main() void {
    // The same function, called at compile time and at run time.
    const at_compile_time = comptime fibonacci(50);
    var n: u32 = 50;
    _ = &n; // pretend n could change, so it is runtime-known
    const at_run_time = fibonacci(n);
    std.debug.print("fib(50) = {d} (comptime) = {d} (runtime)\n", .{ at_compile_time, at_run_time });

    // A comptime variable can change while compiling, never at run time.
    comptime var count = 0;
    inline for (.{ "a", "bb", "ccc" }) |s| count += s.len;
    std.debug.print("total length: {d}\n", .{count});

    const word = "max_len=42";
    var end: usize = 0;
    while (end < word.len and is_ident[word[end]]) end += 1;
    std.debug.print("identifier: {s}\n", .{word[0..end]});
}
```

```console
$ zig run examples/ch12/comptime_basics.zig
fib(50) = 12586269025 (comptime) = 12586269025 (runtime)
total length: 6
identifier: max_len
```

This is **compile-time function evaluation** (CTFE). `fibonacci` is a normal function; nothing marks it "comptime-capable". The compiler runs it when asked, in an interpreter that follows run-time rules, overflow checks included.

Lookup tables are the classic use. The finished 256 bytes are stored in the executable, so the table costs nothing at startup, and `is_ident[c]` is one memory access. (`@splat(false)` fills every element with `false`.)

## Comptime parameters, and types as values

A `comptime` parameter must get a comptime-known value from every caller. In exchange, the body can use it where only comptime values are allowed, such as array lengths and types.

In Zig, **types are values** of type `type`. You can store a type in a `const`, pass it, and return it. Types exist only at compile time, so a `type` parameter is always `comptime`.

`examples/ch12/types_as_values.zig`

```zig
const std = @import("std");

/// Types are values of type `type`. This function takes one and returns one.
fn Pair(comptime T: type) type {
    return struct { first: T, second: T };
}

/// The smallest unsigned type that can hold `max`.
fn SmallestFor(comptime max: comptime_int) type {
    return if (max <= 255) u8 else if (max <= 65535) u16 else u32;
}

pub fn main() void {
    const Int = i32; // a type stored in a constant
    const x: Int = -5;
    std.debug.print("x: {s} = {d}\n", .{ @typeName(@TypeOf(x)), x });

    const p: Pair(f32) = .{ .first = 1.5, .second = 2.5 };
    std.debug.print("p.first: {s}, Pair(f32) == Pair(f32): {}\n", .{
        @typeName(@TypeOf(p.first)),
        Pair(f32) == Pair(f32),
    });

    std.debug.print("SmallestFor(200) = {s}, SmallestFor(1000) = {s}\n", .{
        @typeName(SmallestFor(200)),
        @typeName(SmallestFor(1000)),
    });

    // @TypeOf works on any expression, without evaluating it at run time.
    std.debug.print("@TypeOf(1 + 2) = {s}, @TypeOf(\"hi\") = {s}\n", .{
        @typeName(@TypeOf(1 + 2)),
        @typeName(@TypeOf("hi")),
    });
}
```

```console
$ zig run examples/ch12/types_as_values.zig
x: i32 = -5
p.first: f32, Pair(f32) == Pair(f32): true
SmallestFor(200) = u8, SmallestFor(1000) = u16
@TypeOf(1 + 2) = comptime_int, @TypeOf("hi") = *const [2:0]u8
```

- `@TypeOf(expr)` gives an expression's type; `@typeName(T)` its name as a string.
- `Pair(f32) == Pair(f32)` is `true`: calls with the same comptime arguments are cached and return the *same* type. Generics rely on this ([Chapter 13](13-generics.md)).
- Functions that return a type get `TitleCase` names, like types.

Types can't exist at run time. A type that depends on a runtime value fails to compile:

```zig
const args = init.minimal.args.toSlice(init.arena.allocator()) catch return;
const T = if (args.len > 1) u8 else u16;
```

```text
ce_runtime.zig:9:15: error: value with comptime-only type 'type' depends on runtime control flow
    const T = if (args.len > 1) u8 else u16;
              ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ce_runtime.zig:9:28: note: runtime control flow here
    const T = if (args.len > 1) u8 else u16;
                  ~~~~~~~~~^~~
ce_runtime.zig:9:15: note: types are not available at runtime
```

## Reflection: `@typeInfo`

`@typeInfo(T)` describes `T` as an ordinary value of type `std.lang.Type`, a tagged union (`std.builtin.Type` is an older alias). Tags include `.int`, `.float`, `.bool`, `.pointer`, `.array`, `.optional`, `.@"struct"`, `.@"enum"`, `.@"union"`, `.@"fn"`, and more; keywords need `@"..."` quoting.

`examples/ch12/type_info.zig`

```zig
const std = @import("std");

/// Prints a one-line description of any type, using reflection.
fn describe(comptime T: type) void {
    switch (@typeInfo(T)) {
        .int => |info| std.debug.print("{s}: {t} integer, {d} bits\n", .{ @typeName(T), info.signedness, info.bits }),
        .optional => |info| std.debug.print("{s}: optional {s}\n", .{ @typeName(T), @typeName(info.child) }),
        .@"enum" => |info| {
            std.debug.print("{s}: enum with", .{@typeName(T)});
            for (info.field_names) |name| std.debug.print(" .{s}", .{name});
            std.debug.print("\n", .{});
        },
        .@"struct" => |info| {
            std.debug.print("{s}: struct with {d} fields\n", .{ @typeName(T), info.field_names.len });
            // field_names, field_types and field_attrs are parallel arrays.
            // `inline for`: FieldType is a type, so it must be comptime-known.
            inline for (info.field_names, info.field_types, info.field_attrs) |name, FieldType, attrs| {
                const default = if (attrs.default_value_ptr != null) " (has default)" else "";
                std.debug.print("  {s}: {s}{s}\n", .{ name, @typeName(FieldType), default });
            }
            for (info.decl_names) |name| std.debug.print("  pub decl {s}\n", .{name});
        },
        else => std.debug.print("{s}: {t}\n", .{ @typeName(T), @typeInfo(T) }),
    }
}

const Color = enum { red, green, blue };

const Config = struct {
    name: []const u8,
    retries: u8 = 3,
    color: ?Color = null,

    pub const default_name = "seek";
};

pub fn main() void {
    describe(u7);
    describe(i64);
    describe(?f32);
    describe(Color);
    describe(Config);
    describe(bool);
}
```

```console
$ zig run examples/ch12/type_info.zig
u7: unsigned integer, 7 bits
i64: signed integer, 64 bits
?f32: optional f32
type_info.Color: enum with .red .green .blue
type_info.Config: struct with 3 fields
  name: []const u8
  retries: u8 (has default)
  color: ?type_info.Color (has default)
  pub decl default_name
bool: bool
```

Struct info uses **parallel arrays**: `field_names[i]`, `field_types[i]`, and `field_attrs[i]` describe field `i`. `field_attrs[i].default_value_ptr` is non-null when the field has a default. `decl_names` lists public declarations.

> **Older tutorials** show `info.fields`, an array of structs with `.name` and `.type`. Zig 0.17 removed that layout; use `field_names` and `field_types`.

`switch (@typeInfo(T))` is the usual shape of reflective code: one prong per kind of type, each with its payload.

## `inline for`, `inline while`, `inline else`

The struct branch above uses **`inline for`**. A normal `for` runs at run time, so its loop variable is runtime-known. A `type` can't be, so a normal `for` over `field_types` fails:

```text
examples/ch12/type_info.zig:16:40: error: values of type 'type' must be comptime-known, but index value is runtime-known
            for (info.field_names, info.field_types, info.field_attrs) |name, FieldType, attrs| {
                                   ~~~~^~~~~~~~~~~~
examples/ch12/type_info.zig:16:40: note: types are not available at runtime
```

`inline for` **unrolls** the loop at compile time: one copy of the body per element, each with comptime-known loop variables. Use it when:

- the elements have different types (a tuple), or
- the body needs comptime-known values (a type, a field name for `@field`).

`inline while` unrolls a `while` whose condition uses a `comptime var`. **`inline else`** in a `switch` makes one prong per remaining case, so the captured tag is comptime-known in each.

`examples/ch12/inline_loops.zig`

```zig
const std = @import("std");

const Shape = union(enum) {
    circle: struct { r: f64 },
    square: struct { side: f64 },
    rect: struct { w: f64, h: f64 },
};

fn name(shape: Shape) []const u8 {
    // `inline else` makes one prong per remaining tag. In each copy, `tag`
    // and the payload's type are comptime-known.
    return switch (shape) {
        inline else => |payload, tag| std.fmt.comptimePrint("{s} with {d} field(s)", .{
            @tagName(tag),
            @typeInfo(@TypeOf(payload)).@"struct".field_names.len,
        }),
    };
}

pub fn main() void {
    // The elements of a tuple have different types. A normal `for` can't
    // loop over them; `inline for` unrolls into one copy per element.
    const values = .{ @as(u8, 42), @as(i16, -7), true, 2.5 };
    inline for (values) |v| {
        std.debug.print("{s}: {any}\n", .{ @typeName(@TypeOf(v)), v });
    }

    // `inline while` unrolls too; the counter must be comptime.
    comptime var bits = 8;
    inline while (bits <= 64) : (bits *= 2) {
        std.debug.print("u{d} max = {d}\n", .{ bits, std.math.maxInt(@Int(.unsigned, bits)) });
    }

    std.debug.print("{s}\n", .{name(.{ .rect = .{ .w = 1, .h = 2 } })});
    std.debug.print("{s}\n", .{name(.{ .circle = .{ .r = 1 } })});
}
```

```console
$ zig run examples/ch12/inline_loops.zig
u8: 42
i16: -7
bool: true
comptime_float: 2.5
u8 max = 255
u16 max = 65535
u32 max = 4294967295
u64 max = 18446744073709551615
rect with 2 field(s)
circle with 1 field(s)
```

`std.fmt.comptimePrint` is `print` at compile time; it returns a string constant.

Each unrolled copy is more machine code. Use `inline` when you need comptime-known loop values, not as a speed trick.

## Fields by name: `@field`, `@hasField`, `@hasDecl`, `@FieldType`

| Builtin | Gives |
|---|---|
| `@field(x, "name")` | The field (or declaration) `name`; readable and assignable. Name must be comptime-known. |
| `@hasField(T, "name")` | Whether struct, union, or enum `T` has that field. |
| `@hasDecl(T, "name")` | Whether `T` has a **public** declaration (function, constant, ...) with that name. |
| `@FieldType(T, "name")` | The field's type. |

`examples/ch12/fields.zig`

```zig
const std = @import("std");

const Settings = struct {
    verbose: bool = false,
    level: u8 = 1,
    name: []const u8 = "default",

    pub const version = 2;
};

/// Sets the field called `name` (a comptime string) to `value`.
fn set(settings: *Settings, comptime name: []const u8, value: @FieldType(Settings, name)) void {
    @field(settings, name) = value;
}

/// Prints `name=value` for every field, whatever the struct.
fn dump(value: anytype) void {
    const T = @TypeOf(value);
    inline for (@typeInfo(T).@"struct".field_names) |name| {
        const field = @field(value, name);
        if (@TypeOf(field) == []const u8) {
            std.debug.print("  {s}={s}\n", .{ name, field });
        } else {
            std.debug.print("  {s}={any}\n", .{ name, field });
        }
    }
}

pub fn main() void {
    var s: Settings = .{};
    set(&s, "level", 3);
    set(&s, "name", "seek");
    std.debug.print("settings:\n", .{});
    dump(s);

    std.debug.print("@FieldType(Settings, \"level\") = {s}\n", .{@typeName(@FieldType(Settings, "level"))});
    std.debug.print("@hasField(Settings, \"level\") = {}\n", .{@hasField(Settings, "level")});
    std.debug.print("@hasField(Settings, \"version\") = {}\n", .{@hasField(Settings, "version")});
    std.debug.print("@hasDecl(Settings, \"version\") = {}\n", .{@hasDecl(Settings, "version")});
    // @field also reads declarations.
    std.debug.print("@field(Settings, \"version\") = {d}\n", .{@field(Settings, "version")});
}
```

```console
$ zig run examples/ch12/fields.zig
settings:
  verbose=false
  level=3
  name=seek
@FieldType(Settings, "level") = u8
@hasField(Settings, "level") = true
@hasField(Settings, "version") = false
@hasDecl(Settings, "version") = true
@field(Settings, "version") = 2
```

Notes:

- The parameter type `@FieldType(Settings, name)` depends on an earlier comptime parameter. `set(&s, "level", 300)` is a compile error: 300 doesn't fit in a `u8`.
- `dump` takes `anytype`: whatever type the caller passes. [Chapter 13](13-generics.md) covers it.
- `if (@TypeOf(field) == []const u8)` compares types. The condition is comptime-known, so only the taken branch is compiled per field. That matters: `{s}` on a `bool` wouldn't compile.
- Fields are data in each value; declarations (`pub const`, `pub fn`) belong to the type. `@hasField` sees only fields, `@hasDecl` only public declarations.

## Making types: `@Int`, `@Tuple`, `@Struct`, `@Enum`, ...

Reflection also runs the other way. These builtins **build** a type from a description:

| Builtin | Builds |
|---|---|
| `@Int(.unsigned, 12)` | `u12` |
| `@Tuple(&.{ A, B })` | `struct { A, B }` |
| `@Struct(layout, BackingInt, names, &types, &attrs)` | a struct type |
| `@Enum(TagInt, mode, names, &values)` | an enum type |
| `@Union(layout, ArgType, names, &types, &attrs)` | a union type |
| `@Pointer(size, attrs, Elem, sentinel)`, `@Fn(...)`, `@EnumLiteral()` | pointer, function, and enum literal types |

(Zig before 0.16 had a single `@Type(info)` builtin for this; 0.16 replaced it with these.)

`examples/ch12/make_types.zig`

```zig
const std = @import("std");

pub fn main() void {
    // @Int builds an integer type from a signedness and a bit count.
    const U12 = @Int(.unsigned, 12);
    const max: U12 = std.math.maxInt(U12);
    std.debug.print("{s}: max {d}\n", .{ @typeName(U12), max });

    // @Tuple builds a tuple type from a list of field types.
    const Row = @Tuple(&.{ []const u8, u32 });
    const row: Row = .{ "fox", 3 };
    std.debug.print("{s}: {s} {d}\n", .{ @typeName(Row), row[0], row[1] });

    // @Enum builds an enum from a tag type, names, and values.
    const Level = @Enum(u8, .exhaustive, &.{ "low", "high" }, &.{ 1, 10 });
    const level: Level = .high;
    std.debug.print("Level.{t} = {d}\n", .{ level, @backingInt(level) });

    // @Struct builds a struct type. Here: every field of Point, as an optional.
    const Patch = Partial(Point);
    const patch: Patch = .{ .y = 7 };
    std.debug.print("patch: x={?d} y={?d}\n", .{ patch.x, patch.y });
}

const Point = struct { x: i32, y: i32 };

/// A struct with the same field names as T, but every field optional and
/// defaulting to null.
fn Partial(comptime T: type) type {
    const info = @typeInfo(T).@"struct";
    var types: [info.field_names.len]type = undefined;
    var attrs: [info.field_names.len]std.lang.Type.Struct.FieldAttributes = undefined;
    for (info.field_types, 0..) |FieldType, i| {
        types[i] = ?FieldType;
        const default: ?FieldType = null;
        attrs[i] = .{ .default_value_ptr = &default };
    }
    return @Struct(.auto, null, info.field_names, &types, &attrs);
}
```

```console
$ zig run examples/ch12/make_types.zig
u12: max 4095
struct { []const u8, u32 }: fox 3
Level.high = 10
patch: x=null y=7
```

`Partial` uses a plain `for`, not `inline for`. A function that returns `type` always runs entirely at compile time, so its loops already are compile-time loops. `inline for` is only needed in functions that also run at run time.

Use generated types sparingly; a hand-written struct is easier to read. They pay off when a type must follow another type automatically, as `Partial(T)` does.

## Conditional compilation and the `builtin` module

`@import("builtin")` is a module the compiler generates for each build. It describes the target and build options:

| Declaration | Example values |
|---|---|
| `builtin.os.tag` | `.linux`, `.macos`, `.windows`, ... |
| `builtin.cpu.arch` | `.x86_64`, `.aarch64`, ... |
| `builtin.mode` | `.debug`, `.safe`, `.fast`, `.small` (from `-O`) |
| `builtin.is_test` | `true` inside `zig test` |

Conditional compilation is just an `if` (or `switch`) on a comptime-known condition. **The branch not taken is not analyzed**, so it may call functions that don't exist on this platform.

`examples/ch12/builtin_info.zig`

```zig
const std = @import("std");
const builtin = @import("builtin");

// A comptime `if` on a comptime-known condition: the other branch is not
// even compiled, so it may use APIs that don't exist on this platform.
const line_ending = if (builtin.os.tag == .windows) "\r\n" else "\n";

pub fn main() void {
    std.debug.print("os: {t}, arch: {t}, mode: {t}\n", .{
        builtin.os.tag,
        builtin.cpu.arch,
        builtin.mode,
    });
    std.debug.print("line ending: {d} byte(s)\n", .{line_ending.len});

    if (builtin.mode == .debug) {
        std.debug.print("debug build: safety checks are on\n", .{});
    } else {
        std.debug.print("release build\n", .{});
    }
}
```

```console
$ zig run examples/ch12/builtin_info.zig
os: linux, arch: x86_64, mode: debug
line ending: 1 byte(s)
debug build: safety checks are on
$ zig run -O ReleaseFast examples/ch12/builtin_info.zig
os: linux, arch: x86_64, mode: fast
line ending: 1 byte(s)
release build
```

Your `os` and `arch` may differ. Unlike C's `#ifdef`, the condition is a typed, compiler-checked expression, and both branches are ordinary code.

## `@embedFile`

`@embedFile("path")` reads a file **at compile time** and gives its contents as a string constant, as if pasted in as a literal. The path is relative to the source file. Typical uses: help text, templates, test fixtures, certificates. No file is needed at run time.

`examples/ch12/embed.zig`

```zig
const std = @import("std");

// The file's bytes become a constant in the program, like a string
// literal. The path is relative to this source file.
const source = @embedFile("embed.zig");

// Comptime code can work on embedded data too.
const line_count = std.mem.countScalar(u8, source, '\n');

pub fn main() void {
    std.debug.print("this program's source: {d} bytes, {d} lines\n", .{ source.len, line_count });
    const first_line = source[0..std.mem.findScalar(u8, source, '\n').?];
    std.debug.print("first line: {s}\n", .{first_line});
}
```

```console
$ zig run examples/ch12/embed.zig
this program's source: 552 bytes, 14 lines
first line: const std = @import("std");
```

seek will embed its help text in [Chapter 18](18-build-system.md).

## Errors and debugging at compile time

### `@compileError`: your own error messages

`@compileError("msg")` stops compilation with your message if the compiler reaches it. In a comptime `switch` or `if`, only reached branches count, so you can reject bad uses of a function with a clear explanation:

```zig
fn bitsOf(comptime T: type) u16 {
    return switch (@typeInfo(T)) {
        .int => |info| info.bits,
        else => @compileError("bitsOf: expected an integer type, found " ++ @typeName(T)),
    };
}

pub fn main() void {
    std.debug.print("{d}\n", .{bitsOf(u7)});
    std.debug.print("{d}\n", .{bitsOf(f32)});
}
```

```text
ce_compile_error.zig:6:17: error: bitsOf: expected an integer type, found f32
        else => @compileError("bitsOf: expected an integer type, found " ++ @typeName(T)),
                ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
referenced by:
    main: ce_compile_error.zig:12:38
```

`bitsOf(u7)` compiles. Only the `f32` call fails; "referenced by" points at it.

### `@compileLog`: printf debugging for comptime

`@compileLog(args...)` prints values while compiling. It always fails the build, so you can't leave one in by accident:

```zig
fn square(comptime x: comptime_int) comptime_int {
    @compileLog("square called with", x);
    return x * x;
}
```

```text
ce_log.zig:4:5: error: found compile log statement
    @compileLog("square called with", x);
    ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Compile Log Output:
@as(*const [18:0]u8, "square called with"), @as(comptime_int, 12)
```

### `@setEvalBranchQuota`: the infinite-loop guard

Comptime code could loop forever, so the compiler counts *backward branches* (loop iterations and calls) and gives up after 1000. Real work, like a prime table, needs more. `@setEvalBranchQuota(n)` raises the limit for the current comptime evaluation.

`examples/ch12/eval_quota.zig`

```zig
const std = @import("std");

/// The first `n` prime numbers, computed by trial division.
fn primes(comptime n: usize) [n]u32 {
    // The default limit is 1000 backward branches (loop iterations and
    // recursive calls) per comptime evaluation. This needs more.
    @setEvalBranchQuota(100_000);
    var result: [n]u32 = undefined;
    var count: usize = 0;
    var candidate: u32 = 2;
    while (count < n) : (candidate += 1) {
        var d: u32 = 2;
        const is_prime = while (d * d <= candidate) : (d += 1) {
            if (candidate % d == 0) break false;
        } else true;
        if (is_prime) {
            result[count] = candidate;
            count += 1;
        }
    }
    return result;
}

// Computed while compiling; the binary just contains 500 numbers.
const table = primes(500);

pub fn main() void {
    std.debug.print("first: {any}\n", .{table[0..10]});
    std.debug.print("500th prime: {d}\n", .{table[499]});
}
```

```console
$ zig run examples/ch12/eval_quota.zig
first: { 2, 3, 5, 7, 11, 13, 17, 19, 23, 29 }
500th prime: 3571
```

Without the `@setEvalBranchQuota` line:

```text
quota_bad.zig:10:5: error: evaluation exceeded 1000 backwards branches
    while (count < n) : (candidate += 1) {
    ^~~~~
quota_bad.zig:10:5: note: use @setEvalBranchQuota() to raise the branch limit from 1000
quota_bad.zig:24:21: note: called at comptime here
const table = primes(500);
              ~~~~~~^~~~~
```

### What comptime can't do

Comptime code runs inside the compiler, with no outside world. It can't do I/O (files, network, clock, printing), allocate with a runtime allocator, or call external functions. Only `@embedFile` and `@import` read files, in a controlled way.

This keeps builds **reproducible** (same source, same program) and safe: comptime code can't touch your files.

A function that prints can't run at compile time:

```zig
fn answer() u32 {
    std.debug.print("computing...\n", .{});
    return 42;
}

const value = answer(); // container-level: evaluated at compile time
```

```text
.../lib/std/Io/Threaded.zig:2402:35: error: unable to resolve comptime value
    const thread = Thread.current orelse return .unblocked;
                   ~~~~~~~~~~~~~~~^~~~~~~~~~~~~~~~~~~~~~~~
...
ce_print.zig:4:20: note: called at comptime from here
    std.debug.print("computing...\n", .{});
    ~~~~~~~~~~~~~~~^~~~~~~~~~~~~~~~~~~~~~~
ce_print.zig:8:21: note: called at comptime from here
const value = answer();
              ~~~~~~^~
ce_print.zig:8:21: note: initializer of container-level variable must be comptime-known
```

The first lines point deep into the standard library. Follow the "called at comptime from here" notes down to your own code.

## Building seek: a flag parser generated from `Options`

seek's `parseArgs` from Chapter 11 is a long `if`/`else` chain, one branch per flag, plus hand-written help text. Adding a flag means editing three places and keeping them in sync.

Now `Options` becomes the single source of truth:

- Each field is a long flag: `ignore_case` → `--ignore-case`.
- A `shorts` declaration adds one-letter aliases.
- A `descriptions` declaration gives the help text.
- The field type decides parsing: `bool` is a switch, an integer takes a number, an enum one of its tag names, `[]const u8` any string. Optionals wrap any of these.
- `--help` lists all options, generated at compile time.

Free extras: long names, `--name=value`, and flags mixed with positionals (`seek fox testdata -n`).

### `src/cli.zig` (new)

`Options` and `Color` move here from `search.zig`. `help` and `version` become ordinary `bool` fields, flags like any other.

Create `src/cli.zig`:

```zig
//! Command-line options and a flag parser generated at compile time.
//!
//! `parse` and `help` work for any struct type whose fields all have default
//! values. Each field becomes a long flag (`ignore_case` -> `--ignore-case`);
//! a `shorts` declaration adds one-letter aliases and a `descriptions`
//! declaration provides the help text.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// When to highlight matches.
pub const Color = enum { auto, always, never };

/// Everything the user can configure. Every field has a default, so `.{}`
/// is a complete value. Adding a field here adds a flag to seek.
pub const Options = struct {
    ignore_case: bool = false,
    invert: bool = false,
    line_numbers: bool = false,
    count_only: bool = false,
    files_only: bool = false,
    max_count: ?usize = null,
    hidden: bool = false,
    glob: ?[]const u8 = null,
    color: Color = .auto,
    help: bool = false,
    version: bool = false,

    /// One-letter aliases. An anonymous struct literal is a handy
    /// compile-time "map" from field name to value.
    pub const shorts = .{
        .ignore_case = 'i',
        .invert = 'v',
        .line_numbers = 'n',
        .count_only = 'c',
        .files_only = 'l',
        .max_count = 'm',
        .help = 'h',
    };

    pub const descriptions = .{
        .ignore_case = "ignore case when matching",
        .invert = "select lines that do NOT match",
        .line_numbers = "print line numbers",
        .count_only = "print only a count of selected lines per file",
        .files_only = "print only names of files with selected lines",
        .max_count = "stop after N selected lines per file",
        .hidden = "search hidden files and directories",
        .glob = "only search files whose name matches GLOB (* and ?)",
        .color = "highlight matches",
        .help = "show this help",
        .version = "show the version",
    };
};

pub const Error = error{ UnknownFlag, MissingValue, InvalidValue };

/// Filled in by `parse` to tell the caller which argument was wrong.
pub const Diagnostic = struct {
    flag: []const u8 = "",
    value: []const u8 = "",
};

/// Parses `args` (without the program name) into a `T`. Flags and
/// positional arguments may be mixed; everything after `--` is positional.
/// Returns the options and the positional arguments; the latter is
/// allocated with `gpa` and owned by the caller.
pub fn parse(
    comptime T: type,
    gpa: Allocator,
    args: []const [:0]const u8,
    diag: *Diagnostic,
) (Error || Allocator.Error)!struct { T, []const []const u8 } {
    // These checks run while compiling; a typo in `shorts` is a compile error.
    comptime validate(T);
    const fields = @typeInfo(T).@"struct";

    var options: T = .{};
    var positionals: std.ArrayList([]const u8) = .empty;
    errdefer positionals.deinit(gpa);

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--")) {
            for (args[i + 1 ..]) |rest| try positionals.append(gpa, rest);
            break;
        }
        // "-" alone is a PATH (standard input), not a flag.
        if (arg.len < 2 or arg[0] != '-') {
            try positionals.append(gpa, arg);
            continue;
        }

        // Accept both `--color always` and `--color=always`.
        const flag, const attached_value: ?[]const u8 = if (std.mem.cutScalar(u8, arg, '=')) |parts|
            .{ parts[0], parts[1] }
        else
            .{ arg, null };
        diag.* = .{ .flag = flag };

        // `inline for` unrolls the loop at compile time: one copy of the
        // body per field, each with its own comptime-known name and type.
        const known = inline for (fields.field_names, fields.field_types) |name, FieldType| {
            if (isFlag(T, name, flag)) {
                if (FieldType == bool) {
                    // A switch takes no value: `--hidden=yes` is a mistake.
                    if (attached_value) |value| {
                        diag.value = value;
                        return error.InvalidValue;
                    }
                    @field(options, name) = true;
                } else {
                    const value = attached_value orelse blk: {
                        i += 1;
                        if (i == args.len) return error.MissingValue;
                        break :blk args[i];
                    };
                    diag.value = value;
                    @field(options, name) = try parseValue(FieldType, value);
                }
                break true;
            }
        } else false;
        if (!known) return error.UnknownFlag;
    }
    return .{ options, try positionals.toOwnedSlice(gpa) };
}

/// Reports whether `flag` (like "-i" or "--ignore-case") names field `name`.
fn isFlag(comptime T: type, comptime name: []const u8, flag: []const u8) bool {
    if (std.mem.cutPrefix(u8, flag, "--")) |long| {
        return std.mem.eql(u8, long, comptime kebab(name));
    }
    if (@hasField(@TypeOf(T.shorts), name)) {
        const short: u8 = @field(T.shorts, name);
        return flag.len == 2 and flag[1] == short;
    }
    return false;
}

/// Converts the text of a flag's value to the field's type.
fn parseValue(comptime V: type, text: []const u8) error{InvalidValue}!V {
    return switch (@typeInfo(V)) {
        .int => std.fmt.parseInt(V, text, 10) catch error.InvalidValue,
        .@"enum" => std.meta.stringToEnum(V, text) orelse error.InvalidValue,
        .optional => |optional| try parseValue(optional.child, text),
        .pointer => if (V == []const u8) text else unsupported(V),
        else => unsupported(V),
    };
}

fn unsupported(comptime V: type) noreturn {
    @compileError("cli: unsupported option type " ++ @typeName(V));
}

/// "ignore_case" -> "ignore-case", computed at compile time.
fn kebab(comptime name: []const u8) []const u8 {
    comptime {
        var buffer: [name.len]u8 = name[0..name.len].*;
        std.mem.replaceScalar(u8, &buffer, '_', '-');
        // Copy into a constant so the result can outlive this block.
        const result = buffer;
        return &result;
    }
}

/// The placeholder shown after a flag in the help text: nothing for a
/// bool, `N` for a number, the choices for an enum, and the field name in
/// upper case for a string.
fn valueName(comptime V: type, comptime name: []const u8) []const u8 {
    comptime {
        return switch (@typeInfo(V)) {
            .bool => "",
            .int => " N",
            .optional => |optional| valueName(optional.child, name),
            .@"enum" => |info| blk: {
                var choices: []const u8 = " ";
                for (info.field_names, 0..) |choice, i| {
                    choices = choices ++ (if (i > 0) "|" else "") ++ choice;
                }
                break :blk choices;
            },
            else => blk: {
                var upper: [name.len]u8 = undefined;
                _ = std.ascii.upperString(&upper, name);
                const result = upper;
                break :blk " " ++ &result;
            },
        };
    }
}

/// Builds the option list for `--help` from the fields of `T`. All of it
/// happens at compile time; the program only contains the finished string.
pub fn help(comptime T: type) []const u8 {
    comptime {
        validate(T);
        var text: []const u8 = "";
        const fields = @typeInfo(T).@"struct";
        for (fields.field_names, fields.field_types) |name, FieldType| {
            const short = if (@hasField(@TypeOf(T.shorts), name))
                std.fmt.comptimePrint("-{c}, ", .{@field(T.shorts, name)})
            else
                "    ";
            const long = "--" ++ kebab(name) ++ valueName(FieldType, name);
            text = text ++ std.fmt.comptimePrint("  {s}{s:<26} {s}\n", .{
                short,
                long,
                @field(T.descriptions, name),
            });
        }
        return text;
    }
}

/// Compile-time checks that turn mistakes into readable compile errors.
fn validate(comptime T: type) void {
    const info = @typeInfo(T);
    if (info != .@"struct") @compileError("cli: expected a struct, found " ++ @typeName(T));
    for (info.@"struct".field_names, info.@"struct".field_attrs) |name, attrs| {
        if (attrs.default_value_ptr == null) @compileError("cli: field '" ++ name ++ "' needs a default value");
        if (!@hasField(@TypeOf(T.descriptions), name)) @compileError("cli: field '" ++ name ++ "' needs a description");
    }
    for (@typeInfo(@TypeOf(T.shorts)).@"struct".field_names) |name| {
        if (!@hasField(T, name)) @compileError("cli: shorts." ++ name ++ " is not a field of " ++ @typeName(T));
    }
}
```

How it works:

- **`shorts` and `descriptions`** are anonymous struct literals whose field names are option names. `@TypeOf(T.shorts)` is a struct type, so `@hasField(@TypeOf(T.shorts), name)` asks "does this option have a short form?" and `@field(T.shorts, name)` reads it: a map that exists only at compile time.
- **`parse`** loops over the arguments at run time. For each flag, `inline for` checks every field. Unrolled, it is a chain of `if`s, one per field, like the hand-written parser. Each copy knows its `name` and `FieldType`, so `@field(options, name) = ...` and `FieldType == bool` work.
- **`const known = inline for (...) { ... break true; } else false;`** A loop is an expression: `break true` leaves it with a value; the `else` value is used if it finishes without breaking.
- **`const flag, const attached_value: ?[]const u8 = ...`** destructures a two-element tuple. `std.mem.cutScalar(u8, arg, '=')` returns `?struct { []const u8, []const u8 }`: the parts before and after the first `=`, or `null`.
- **The return type `struct { T, []const []const u8 }`** is an inline tuple type; `main` destructures it the same way.
- **`parseValue`** switches on `@typeInfo(V)`. For an optional it calls itself with the child type, so `?usize` parses as `usize`. This recursion happens at compile time: each `V` gets its own copy.
- **`unsupported`** returns `noreturn`, so it fits any branch. An unknown field type such as `f64` gives `cli: unsupported option type f64` at compile time, not a run-time surprise.
- **`kebab`** runs in a `comptime` block. `buffer` is a `var` that changes while compiling. Copying it into `const result` freezes it, so `&result` points to a constant stored in the program. A pointer to the `var` could not leave the comptime block.
- **`help`** builds the whole string with `++` and `comptimePrint`; `{s:<26}` pads the flag to 26 columns. The executable holds only the finished text.
- **`validate`** turns mistakes in `Options` into compile errors. A field without a default would make `var options: T = .{}` fail confusingly, so we check first and explain.
- **`Diagnostic`**: `parse` doesn't print. It returns an error and fills `diag` so the caller can write a good message; libraries shouldn't decide where messages go. This "diagnostic out-parameter" pattern is common in the standard library.

### `src/main.zig` (rewritten)

`Command`, `UsageError`, `parseArgs`, `takeValue`, `eql`, and `argAt` are gone. Replace the whole file:

```zig
const std = @import("std");
const cli = @import("cli.zig");
const Options = cli.Options;
const Searcher = @import("search.zig").Searcher;

const version = "0.1.0";

const usage = "usage: seek [OPTIONS] PATTERN [PATH ...]\n";

// cli.help runs at compile time, so `help` is one constant string.
const help = usage ++
    \\
    \\Search each PATH (default: .) for lines containing PATTERN.
    \\Directories are searched recursively; - means standard input.
    \\
    \\options:
    \\
++ cli.help(Options);

/// The process exit status. An explicit tag type (`u8`) fixes each value.
const ExitCode = enum(u8) {
    ok = 0, // a line matched (or nothing went wrong)
    no_match = 1, // nothing matched
    trouble = 2, // bad usage or an error
};

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), init.io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    const status = run(init.gpa, init.io, args[1..], stdout, stderr) catch |err| switch (err) {
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
    try stdout.flush();
    try stderr.flush();
    return @backingInt(status);
}

/// Runs seek with the arguments after the program name.
fn run(
    gpa: std.mem.Allocator,
    io: std.Io,
    args: []const [:0]const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !ExitCode {
    var diag: cli.Diagnostic = .{};
    const options, const positionals = cli.parse(Options, gpa, args, &diag) catch |err| {
        switch (err) {
            error.UnknownFlag => try stderr.print("seek: unknown flag '{s}'\n", .{diag.flag}),
            error.MissingValue => try stderr.print("seek: {s} needs a value\n", .{diag.flag}),
            error.InvalidValue => try stderr.print("seek: invalid value '{s}' for {s}\n", .{ diag.value, diag.flag }),
            error.OutOfMemory => {},
        }
        return err;
    };
    defer gpa.free(positionals);

    if (options.help) {
        try stdout.writeAll(help);
        return .ok;
    }
    if (options.version) {
        try stdout.print("seek {s}\n", .{version});
        return .ok;
    }
    if (positionals.len == 0) return error.MissingPattern;
    const pattern = positionals[0];
    // No PATH means the current directory.
    const default_paths: []const []const u8 = &.{"."};
    const paths = if (positionals.len > 1) positionals[1..] else default_paths;

    var searcher: Searcher = try .init(gpa, io, pattern, options, stdout, stderr);
    defer searcher.deinit();

    for (paths) |path| try searcher.addPath(path);
    try searcher.searchAll();

    if (searcher.had_error) return .trouble;
    return if (searcher.matched_any) .ok else .no_match;
}
```

Things to notice:

- `run` gets `args[1..]`: the program name isn't parsed.
- `run` returns `!ExitCode`, an **inferred error set**, yet `main`'s `switch` lists every error by name. The compiler checks that list against what `run` can return. If a later change adds an error, `main` stops compiling until you handle it: a cheap, useful guarantee.
- `error.MissingPattern` isn't declared anywhere. With an inferred error set, `return error.MissingPattern` is enough.
- `default_paths` needs an explicit type: `&.{"."}` alone has no slice type for `if` to unify with `positionals[1..]`.

### `src/search.zig`

Delete `Color` and `Options` from `search.zig` (they live in `cli.zig` now) and import `Options`. The top of the file becomes:

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const wildcardMatch = @import("match.zig").wildcardMatch;
const Options = @import("cli.zig").Options;

/// Size of the buffer each file is read through. Lines longer than this
/// still work, they just take a slower path (see `nextLine`).
const read_buffer_len = 64 * 1024;

/// A file is binary if a NUL byte appears in its first 8 KiB.
const binary_probe_len = 8 * 1024;

/// ANSI escape sequences: bold red, then back to normal.
const ansi_match = "\x1b[1;31m";
const ansi_reset = "\x1b[0m";
```

Nothing else in `search.zig` changes; `Searcher` reads the same fields as before.

### Checkpoint

```console
$ zig build
$ ./zig-out/bin/seek -h
usage: seek [OPTIONS] PATTERN [PATH ...]

Search each PATH (default: .) for lines containing PATTERN.
Directories are searched recursively; - means standard input.

options:
  -i, --ignore-case              ignore case when matching
  -v, --invert                   select lines that do NOT match
  -n, --line-numbers             print line numbers
  -c, --count-only               print only a count of selected lines per file
  -l, --files-only               print only names of files with selected lines
  -m, --max-count N              stop after N selected lines per file
      --hidden                   search hidden files and directories
      --glob GLOB                only search files whose name matches GLOB (* and ?)
      --color auto|always|never  highlight matches
  -h, --help                     show this help
      --version                  show the version
$ ./zig-out/bin/seek fox testdata -n
testdata/notes/log.txt:1:2024-01-01 saw a fox near the barn
testdata/notes/log.txt:3:2024-01-03 fox tracks in the snow
testdata/notes/todo.md:2:- feed the fox
testdata/poem.txt:1:The quick brown fox
$ ./zig-out/bin/seek --max-count=1 -n fox testdata
testdata/notes/log.txt:1:2024-01-01 saw a fox near the barn
testdata/notes/todo.md:2:- feed the fox
testdata/poem.txt:1:The quick brown fox
$ ./zig-out/bin/seek --ignore-case --line-numbers fox testdata/poem.txt
testdata/poem.txt:1:The quick brown fox
testdata/poem.txt:3:A Fox is quick and clever;
testdata/poem.txt:5:Foxes everywhere!
$ ./zig-out/bin/seek --color=always -i quick testdata/poem.txt | cat -v
testdata/poem.txt:The ^[[1;31mquick^[[0m brown fox
testdata/poem.txt:A Fox is ^[[1;31mquick^[[0m and clever;
```

`Diagnostic` makes errors clear (each exits with status 2):

```console
$ ./zig-out/bin/seek --hidden=yes fox testdata
seek: invalid value 'yes' for --hidden
usage: seek [OPTIONS] PATTERN [PATH ...]
$ ./zig-out/bin/seek -m two fox testdata
seek: invalid value 'two' for -m
usage: seek [OPTIONS] PATTERN [PATH ...]
$ ./zig-out/bin/seek --glob
seek: --glob needs a value
usage: seek [OPTIONS] PATTERN [PATH ...]
$ ./zig-out/bin/seek -in fox testdata
seek: unknown flag '-in'
usage: seek [OPTIONS] PATTERN [PATH ...]
$ ./zig-out/bin/seek --frobnicate fox
seek: unknown flag '--frobnicate'
usage: seek [OPTIONS] PATTERN [PATH ...]
```

After `--`, everything is positional, so this searches `testdata` for `-n` and finds nothing (exit 1):

```console
$ ./zig-out/bin/seek -- -n testdata; echo "exit $?"
exit 1
```

Bundled short flags (`-in`) aren't supported; Exercise 5 adds them.

Now watch `validate` work. In `Options.shorts`, misspell `.invert = 'v'` as `.invertt = 'v'` and build:

```text
src/cli.zig:226:34: error: cli: shorts.invertt is not a field of cli.Options
        if (!@hasField(T, name)) @compileError("cli: shorts." ++ name ++ " is not a field of " ++ @typeName(T));
                                 ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
src/cli.zig:75:22: note: called at comptime here
    comptime validate(T);
             ~~~~~~~~^~~
```

`zig build` reports it twice (via `parse` and via `help`) inside its usual "failed command" summary. A typo in the flag table is now a clear compile error, not a flag that silently does nothing. Undo the typo before continuing.

The complete project at this point is in `project/ch12/`.

## Summary

- `comptime` is one mechanism for constants, generics, conditional compilation, and reflection. Comptime code is ordinary Zig.
- Force compile-time evaluation with `comptime expr`, `comptime { }`, or a container-level `const`. `comptime var` exists only while compiling.
- Any function can run at compile time (CTFE); lookup tables are the classic use.
- Types are comptime-only values of type `type`. `@TypeOf` and `@typeName` inspect them.
- `@typeInfo(T)` returns a `std.lang.Type`. Struct info has parallel `field_names`, `field_types`, `field_attrs`, plus `decl_names`.
- `@Int`, `@Tuple`, `@Struct`, `@Enum`, `@Union`, `@Pointer`, `@Fn` build types (`@Type` is gone).
- `inline for`, `inline while`, `inline else` unroll at compile time, making loop values comptime-known.
- `@field`, `@hasField`, `@hasDecl`, `@FieldType` access fields and declarations by comptime name.
- `@compileError` for your own errors, `@compileLog` to debug, `@setEvalBranchQuota` to raise the 1000-branch limit.
- `@import("builtin")` gives OS, CPU, and build mode; an `if` on them is conditional compilation.
- `@embedFile` includes a file at compile time. Otherwise comptime has no I/O, which keeps builds reproducible.
- seek's flag parser and help text are generated from `Options`: one struct defines every flag.

## Exercises

1. **Hex table.** Build a comptime table `hex_values: [256]?u4` mapping `'0'..'9'`, `'a'..'f'`, `'A'..'F'` to their values and every other byte to `null`. Use it to write `fn parseHex(text: []const u8) ?u32`.

   <details><summary>Solution</summary>

   ```zig
   const std = @import("std");

   /// hex_values[c] is the value of hex digit c, or null.
   const hex_values = blk: {
       var table: [256]?u4 = @splat(null);
       for ("0123456789abcdef", 0..) |c, i| {
           table[c] = i;
           table[std.ascii.toUpper(c)] = i;
       }
       break :blk table;
   };

   fn parseHex(text: []const u8) ?u32 {
       var result: u32 = 0;
       for (text) |c| {
           const digit = hex_values[c] orelse return null;
           result = result * 16 + digit;
       }
       return result;
   }

   pub fn main() void {
       std.debug.print("{?d} {?d} {?d}\n", .{ parseHex("ff"), parseHex("C0DE"), parseHex("xyz") });
   }
   ```

   ```console
   $ zig run hex.zig
   255 49374 null
   ```

   </details>

2. **`maxOf`.** Write `fn maxOf(comptime T: type) T` returning the largest value of any integer or float type (`std.math.maxInt`, `std.math.floatMax`). Any other type must give a compile error naming the type.

   <details><summary>Solution</summary>

   ```zig
   const std = @import("std");

   fn maxOf(comptime T: type) T {
       return switch (@typeInfo(T)) {
           .int => std.math.maxInt(T),
           .float => std.math.floatMax(T),
           else => @compileError("maxOf: " ++ @typeName(T) ++ " is not a number type"),
       };
   }

   pub fn main() void {
       std.debug.print("{d} {d} {e}\n", .{ maxOf(u8), maxOf(i3), maxOf(f32) });
   }
   ```

   ```console
   $ zig run maxof.zig
   255 3 3.4028235e38
   ```

   `maxOf(bool)` fails with `error: maxOf: bool is not a number type`.

   </details>

3. **Field-wise equality.** Write `fn eqlFields(a: anytype, b: @TypeOf(a)) bool` comparing two structs field by field: `[]const u8` fields by content (`std.mem.eql`), everything else with `==`.

   <details><summary>Solution</summary>

   ```zig
   const std = @import("std");

   /// Compares two structs field by field. Fields of type []const u8 are
   /// compared by content; everything else with ==.
   fn eqlFields(a: anytype, b: @TypeOf(a)) bool {
       const info = @typeInfo(@TypeOf(a)).@"struct";
       inline for (info.field_names, info.field_types) |name, FieldType| {
           const x = @field(a, name);
           const y = @field(b, name);
           const same = if (FieldType == []const u8) std.mem.eql(u8, x, y) else x == y;
           if (!same) return false;
       }
       return true;
   }

   const User = struct { name: []const u8, age: u8, admin: bool = false };

   pub fn main() void {
       const a: User = .{ .name = "ada", .age = 36 };
       var buffer = "ada".*; // same text, different memory
       const b: User = .{ .name = &buffer, .age = 36 };
       const c: User = .{ .name = "ada", .age = 37 };
       std.debug.print("a == b: {}, a == c: {}\n", .{ eqlFields(a, b), eqlFields(a, c) });
   }
   ```

   ```console
   $ zig run eql.zig
   a == b: true, a == c: false
   ```

   </details>

4. **A new option.** Add `quiet: bool = false,` to seek's `Options` (after `version`) and build. What happens? Remove `= false` and build again. What do the two messages tell you, and what else must change to finish the feature?

   <details><summary>Solution</summary>

   With the default value but no description:

   ```text
   src/cli.zig:224:56: error: cli: field 'quiet' needs a description
   ```

   Without the default value, `validate` reports the earlier problem first:

   ```text
   src/cli.zig:223:46: error: cli: field 'quiet' needs a default value
   ```

   To finish, add `.quiet = "..."` to `descriptions` (and optionally `.quiet = 'q'` to `shorts`). The parser and `--help` need no changes. Then make `Searcher` act on `options.quiet`: the only feature code you write.

   </details>

5. **Bundled short flags.** Make `seek -in fox` mean `seek -i -n fox`. Every letter of a bundle must be the short name of a `bool` field; otherwise report the whole argument as an unknown flag, as before.

   <details><summary>Solution</summary>

   Add this function to `cli.zig`:

   ```zig
   /// Handles bundled switches like `-in`: every letter must be the short
   /// name of a bool field. Returns false if `arg` isn't such a bundle.
   fn parseBundle(comptime T: type, options: *T, arg: []const u8) bool {
       if (arg.len <= 2 or arg[1] == '-') return false;
       const fields = @typeInfo(T).@"struct";
       var parsed = options.*;
       for (arg[1..]) |c| {
           const known = inline for (fields.field_names, fields.field_types) |name, FieldType| {
               if (FieldType == bool and @hasField(@TypeOf(T.shorts), name) and @field(T.shorts, name) == c) {
                   @field(parsed, name) = true;
                   break true;
               }
           } else false;
           if (!known) return false;
       }
       options.* = parsed;
       return true;
   }
   ```

   In `parse`, call it right after the positional check:

   ```zig
           if (arg.len < 2 or arg[0] != '-') {
               try positionals.append(gpa, arg);
               continue;
           }
           if (parseBundle(T, &options, arg)) continue;
   ```

   It writes to a copy (`parsed`), so a bad bundle leaves `options` untouched.

   ```console
   $ ./zig-out/bin/seek -in fox testdata/poem.txt
   testdata/poem.txt:1:The quick brown fox
   testdata/poem.txt:3:A Fox is quick and clever;
   testdata/poem.txt:5:Foxes everywhere!
   $ ./zig-out/bin/seek -ic fox testdata
   testdata/notes/log.txt:2
   testdata/notes/todo.md:1
   testdata/poem.txt:3
   $ ./zig-out/bin/seek -im 1 fox testdata
   seek: unknown flag '-im'
   usage: seek [OPTIONS] PATTERN [PATH ...]
   ```

   </details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-12--comptime)
