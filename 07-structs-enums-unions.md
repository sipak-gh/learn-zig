# Chapter 7 — Structs, Enums, and Unions

`seek` is now a few functions passing the same six arguments around. This chapter shows how to
make your own types: **structs** group values, **enums** name a fixed set of choices, and **unions**
hold one of several kinds of value. You'll also meet methods, namespaces, tuples, and special
layouts. Then you'll restructure `seek` around an `Options` struct, a `Command` union, and a
`Searcher` with methods: same behavior, easier to grow. Previous:
[Chapter 6](06-arrays-slices-pointers.md). Next: [Chapter 8](08-memory-and-allocators.md)
(allocators and memory ownership).

## Structs

A struct groups named fields. This one has a default value, a constant, and methods:

`examples/ch07/structs.zig`

```zig
const std = @import("std");

/// A point on a grid. `y` has a default, so you may leave it out.
const Point = struct {
    x: i32,
    y: i32 = 0,

    /// A declaration inside the struct: `Point.origin`.
    pub const origin: Point = .{ .x = 0, .y = 0 };

    /// The usual name for "make a new value".
    pub fn init(x: i32, y: i32) Point {
        return .{ .x = x, .y = y };
    }

    /// Takes the point by value: it only reads.
    pub fn distance(p: Point) u32 {
        return @abs(p.x) + @abs(p.y);
    }

    /// Takes a pointer: it changes the caller's point.
    pub fn move(p: *Point, dx: i32, dy: i32) void {
        p.x += dx;
        p.y += dy;
    }
};

pub fn main() void {
    const a = Point{ .x = 3, .y = 4 }; // typed literal
    const b: Point = .{ .x = 7 }; // the result type gives `.{}` its type; y = 0
    var c: Point = .origin; // decl literal: Point.origin
    const d: Point = .init(5, -2); // decl literal calling Point.init

    std.debug.print("a = {any}\n", .{a});
    std.debug.print("b.y = {d}, d = ({d}, {d})\n", .{ b.y, d.x, d.y });

    // Method call syntax passes the value as the first argument.
    std.debug.print("a.distance() = {d}, Point.distance(a) = {d}\n", .{ a.distance(), Point.distance(a) });

    // `c` is a var, so `c.move` passes `&c` automatically.
    c.move(2, 3);
    c.move(1, 1);
    std.debug.print("c = ({d}, {d})\n", .{ c.x, c.y });

    // Structs are values: assignment copies.
    var e = c;
    e.x = 100;
    std.debug.print("c.x = {d}, e.x = {d}\n", .{ c.x, e.x });

    // Fields work the same through a pointer: no `->` needed.
    const p = &e;
    p.y = -1;
    std.debug.print("e = ({d}, {d}), size {d} bytes\n", .{ e.x, e.y, @sizeOf(Point) });
}
```

```console
$ zig run examples/ch07/structs.zig
a = .{ .x = 3, .y = 4 }
b.y = 0, d = (5, -2)
a.distance() = 7, Point.distance(a) = 7
c = (3, 4)
c.x = 3, e.x = 100
e = (100, -1), size 8 bytes
```

### Struct types are values

`const Point = struct { ... };` A struct type has no name of its own. You bind it to a constant, and
that name becomes the type's name. Types are values in Zig ([Chapter 12](12-comptime.md)).

### Literals and result types

- `Point{ .x = 3, .y = 4 }` names the type in the literal.
- `const b: Point = .{ .x = 7 };` leaves it out: `.{ ... }` takes its type from where the value goes,
  its **result type**. This is the usual Zig style.
- Every field without a default must be set:

```console
$ zig run missing_field.zig
missing_field.zig:4:23: error: missing struct field: x
    const p: Point = .{ .y = 1 };
                     ~^~~~~~~~~~
missing_field.zig:1:15: note: struct declared here
const Point = struct { x: i32, y: i32 = 0 };
              ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~
```

Give a field a default only when one value suits almost everyone. If *every* field has a default,
`.{}` is a full value: handy for option sets.

### Declarations and decl literals

Constants and functions declared in a struct belong to the type, not to each value: `Point.origin`,
`Point.init`.

When the result type is known, `.origin` means `Point.origin` and `.init(5, -2)` means
`Point.init(5, -2)`. These are **decl literals**, used all over `std`:

```zig
var list: std.ArrayList(u8) = .empty;
var writer: std.Io.File.Writer = .initStreaming(...);
```

The second line is already in `seek`'s `main`. By convention, `init` builds a value and `empty`
is a ready-to-use empty value.

### Methods

A function in a struct whose first parameter is the struct (or a pointer to it) is a **method**.
`a.distance()` is short for `Point.distance(a)`.

- **By value** (`p: Point`) when the method only reads. Zig may pass a reference behind the scenes;
  you can't tell.
- **Pointer** (`p: *Point`) when it changes the struct. `c.move(2, 3)` passes `&c` for you.
- **Const pointer** (`p: *const Point`) to read with a guarantee of no copy (for large structs).

`self` isn't a keyword, just a common parameter name.

A mutating method on a constant fails, because `&counter` is a `*const`:

```zig
const Counter = struct {
    count: u32 = 0,

    fn bump(self: *Counter) void {
        self.count += 1;
    }
};

pub fn main() void {
    const counter: Counter = .{};
    counter.bump();
}
```

```console
$ zig run const_method.zig
const_method.zig:11:12: error: expected type '*const_method.Counter', found '*const const_method.Counter'
    counter.bump();
    ~~~~~~~^~~~~
const_method.zig:11:12: note: cast discards const qualifier
const_method.zig:4:19: note: parameter type declared here
    fn bump(self: *Counter) void {
                  ^~~~~~~~
```

Make it `var counter` and it works.

### Copies, pointers and equality

- Structs are values: `var e = c;` copies all fields.
- Through a pointer, `p.y` works directly; there's no `->`.
- `==` doesn't work on structs. Compare fields yourself or use `std.meta.eql` (below):

```console
$ zig run struct_eq.zig
struct_eq.zig:6:11: error: operator == not allowed for type 'struct_eq.Point'
    _ = a == b;
        ~~^~~~
struct_eq.zig:1:15: note: struct declared here
const Point = struct { x: i32, y: i32 };
              ^~~~~~~~~~~~~~~~~~~~~~~~~
```

## Namespaces, `@This()`, and tuples

A struct with only declarations is a **namespace**: it groups related constants and functions and
takes no memory.

Every Zig **file** is a struct too. `@import("std")` returns a struct with declarations `mem`,
`debug`, `Io`, and so on. That's why `std.mem.eql` reads like field access.

`examples/ch07/namespaces.zig`

```zig
const std = @import("std");

/// A struct with no fields is just a namespace for declarations.
const units = struct {
    pub const km_per_mile = 1.609344;

    pub fn milesToKm(miles: f64) f64 {
        return miles * km_per_mile;
    }
};

/// `@This()` is the type of the innermost struct. `Self` is a common name.
const Counter = struct {
    const Self = @This();

    count: u32 = 0,

    pub fn bump(self: *Self) void {
        self.count += 1;
    }
};

pub fn main() void {
    std.debug.print("26.2 miles = {d:.1} km\n", .{units.milesToKm(26.2)});
    std.debug.print("@sizeOf(units) = {d}\n", .{@sizeOf(units)});

    var counter: Counter = .{};
    counter.bump();
    counter.bump();
    std.debug.print("count = {d}\n", .{counter.count});

    // A tuple: a struct whose fields have no names, only positions.
    const t = .{ 42, "hi", true };
    std.debug.print("t[0] = {d}, t[1] = {s}, t.len = {d}\n", .{ t[0], t[1], t.len });

    // Destructure a tuple into separate constants.
    const n, const word, _ = t;
    std.debug.print("n = {d}, word = {s}\n", .{ n, word });

    // An anonymous struct literal with no result type gets a new struct type.
    const pet = .{ .name = "Rex", .legs = 4 };
    std.debug.print("{s} has {d} legs\n", .{ pet.name, pet.legs });
}
```

```console
$ zig run examples/ch07/namespaces.zig
26.2 miles = 42.2 km
@sizeOf(units) = 0
count = 2
t[0] = 42, t[1] = hi, t.len = 3
n = 42, word = hi
Rex has 4 legs
```

- Style: namespaces use `lower_case` (`units`, `std.mem`); types with fields use `TitleCase`.
- `@This()` is the struct it's written in. Useful inside a struct with no name yet, or in a file:
  `const Seek = @This();` names the file's own struct.
- A **tuple**, `.{ 42, "hi", true }`, is a struct with numbered fields: `t[0]`, `.len`. The index
  must be comptime-known, because each field can have a different type.
- An anonymous struct literal with no result type (`.{ .name = "Rex", .legs = 4 }`) gets a new
  struct type of its own.
- You've used tuples since Chapter 1: the `.{ ... }` passed to `print` is a tuple.

## Enums

An enum is a type with a fixed set of named values:

`examples/ch07/enums.zig`

```zig
const std = @import("std");

const Suit = enum {
    clubs,
    diamonds,
    hearts,
    spades,

    /// Enums can have methods, just like structs.
    pub fn isRed(suit: Suit) bool {
        return switch (suit) {
            .diamonds, .hearts => true,
            .clubs, .spades => false,
        };
    }
};

/// An explicit tag type fixes the integer behind each value.
const Level = enum(u8) { low = 1, medium = 5, high = 10 };

/// `_` makes the enum non-exhaustive: every u8 is a valid Status.
const Status = enum(u8) { ok = 0, not_found = 4, _ };

pub fn main() void {
    // `.hearts` is an enum literal. The result type says which enum.
    const card: Suit = .hearts;
    std.debug.print("{t} is red: {}\n", .{ card, card.isRed() });
    std.debug.print("@tagName: {s}, equal: {}\n", .{ @tagName(Suit.spades), card == .hearts });

    // Enum <-> integer.
    const level: Level = .medium;
    const raw: u8 = @backingInt(level);
    const back: Level = @fromBackingInt(10);
    std.debug.print("{t} = {d}, 10 = {t}\n", .{ level, raw, back });

    // Without an explicit tag type, Zig picks the smallest that fits.
    std.debug.print("@sizeOf(Suit) = {d}, @sizeOf(Level) = {d}\n", .{ @sizeOf(Suit), @sizeOf(Level) });

    // A non-exhaustive enum can hold numbers that have no name.
    const s: Status = @fromBackingInt(7);
    switch (s) {
        .ok => std.debug.print("ok\n", .{}),
        .not_found => std.debug.print("not found\n", .{}),
        _ => std.debug.print("unknown status {d}\n", .{@backingInt(s)}),
    }

    // Look a value up by name (returns null for unknown names).
    const parsed = std.meta.stringToEnum(Suit, "clubs");
    std.debug.print("parsed: {any}\n", .{parsed});
}
```

```console
$ zig run examples/ch07/enums.zig
hearts is red: true
@tagName: spades, equal: true
medium = 5, 10 = high
@sizeOf(Suit) = 1, @sizeOf(Level) = 1
unknown status 7
parsed: .clubs
```

- **Enum literals** like `.hearts` need a result type to know their enum. Compare them directly:
  `card == .hearts`.
- A typo is a compile error, not a silent bug:

```console
$ zig run bad_literal.zig
bad_literal.zig:4:25: error: enum 'bad_literal.Suit' has no member named 'heart'
    const card: Suit = .heart;
                       ~^~~~~
bad_literal.zig:1:14: note: enum declared here
const Suit = enum { clubs, diamonds, hearts, spades };
             ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
```

- **`switch` must cover every value.** Add an enum value and the compiler lists every `switch` to
  update:

```console
$ zig run missing_case.zig
missing_case.zig:6:12: error: switch must handle all possibilities
    return switch (suit) {
           ^~~~~~
missing_case.zig:3:46: note: unhandled enumeration value: 'spades'
const Suit = enum { clubs, diamonds, hearts, spades };
                                             ^~~~~~
missing_case.zig:3:14: note: enum 'missing_case.Suit' declared here
const Suit = enum { clubs, diamonds, hearts, spades };
             ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
```

  So avoid `else` in switches on your own enums: it silently swallows new values.

- **Names:** `@tagName(value)` returns the name as a string; `{t}` prints it.
- **Integers:** an enum is stored as an integer, its **tag type**. Choose it with `enum(u8)` and set
  values with `= 5`. Convert with `@backingInt(e)` (enum → integer) and `@fromBackingInt(n)`
  (integer → enum; the result type picks the enum). A number with no matching value is caught by a
  safety check.
- **Non-exhaustive enums** end with `_`. Every tag-type value is valid, so a `switch` needs a `_ =>`
  prong for unnamed ones. Use them for outside numbers (file formats, protocols) that may grow.
- `std.meta.stringToEnum(T, name)` turns a string into an enum value, or `null`. `seek` uses it in
  Chapter 9 to parse `--color`.

> **New in 0.17:** `@backingInt` and `@fromBackingInt` replace `@intFromEnum` and `@enumFromInt`.
> The old names still compile but are deprecated; you'll see them in older code.

## Unions

A union holds **one of several** kinds of value. A **tagged union**, `union(enum)`, also remembers
which kind, so you can `switch` on it safely. Other languages call this a sum type, variant, or
algebraic data type.

`examples/ch07/unions.zig`

```zig
const std = @import("std");

/// A tagged union: a value is exactly one of these, and Zig remembers which.
const Shape = union(enum) {
    circle: f64, // radius
    rect: struct { w: f64, h: f64 },
    point, // no payload (void)

    pub fn area(shape: Shape) f64 {
        // `switch` must handle every tag. `|r|` captures the payload.
        return switch (shape) {
            .circle => |r| std.math.pi * r * r,
            .rect => |r| r.w * r.h,
            .point => 0,
        };
    }

    /// `|*r|` captures a pointer to the payload, so we can change it.
    pub fn scale(shape: *Shape, factor: f64) void {
        switch (shape.*) {
            .circle => |*r| r.* *= factor,
            .rect => |*r| {
                r.w *= factor;
                r.h *= factor;
            },
            .point => {},
        }
    }
};

pub fn main() void {
    var shapes = [_]Shape{
        .{ .circle = 1 },
        .{ .rect = .{ .w = 2, .h = 3 } },
        .point,
    };

    for (&shapes) |*shape| {
        shape.scale(2);
        std.debug.print("{t}: area {d:.2}\n", .{ shape.*, shape.area() });
    }

    // A tagged union compares against its tags.
    const first = shapes[0];
    std.debug.print("first is a circle: {}\n", .{first == .circle});

    // `if` with a tag check, then read the payload directly.
    if (first == .circle) std.debug.print("radius {d}\n", .{first.circle});

    std.debug.print("@sizeOf(Shape) = {d}\n", .{@sizeOf(Shape)});
}
```

```console
$ zig run examples/ch07/unions.zig
circle: area 12.57
rect: area 24.00
point: area 0.00
first is a circle: true
radius 2
@sizeOf(Shape) = 24
```

- Each field is one **variant**. A field without a type (`point`) carries no data; write it
  `.point`, like an enum literal.
- Make a value by setting one field: `.{ .circle = 1 }`.
- `switch (shape) { .circle => |r| ... }` gives the active variant's payload. With `|*r|` (switching
  on `shape.*`), `r` points into the union, so you can change it in place.
- `shape == .circle` checks the tag; `{t}` prints it.
- Size = largest payload + tag + padding: 16 bytes for `rect`, plus the tag, rounded up to 24.

Use a tagged union when a value is "one of these, each with its own data", like `seek`'s command
line below.

### Bare unions

A plain `union` has no tag; you must know which field is active. Safe builds keep a hidden tag to
catch mistakes:

`examples/ch07/bare_union.zig`

```zig
const std = @import("std");

/// A bare union has no tag. Only one field is valid at a time, and in safe
/// builds Zig keeps a hidden tag to check which one.
const Number = union {
    int: i64,
    float: f64,
};

pub fn main() void {
    var n: Number = .{ .int = 42 };
    std.debug.print("int: {d}\n", .{n.int});

    n = .{ .float = 2.5 }; // switch the active field by assigning a whole value
    std.debug.print("float: {d}\n", .{n.float});

    std.debug.print("int again: {d}\n", .{n.int}); // wrong field: panic
}
```

```console
$ zig run examples/ch07/bare_union.zig
int: 42
float: 2.5
thread 276043 panic: access of union field 'int' while field 'float' is active
…/examples/ch07/bare_union.zig:17:44: 0x11e9440 in main (bare_union.zig)
    std.debug.print("int again: {d}\n", .{n.int}); // wrong field: panic
                                           ^
…
```

You can't `switch` on a bare union. In ReleaseFast the hidden tag is gone and a wrong access is
illegal behavior. Prefer `union(enum)` unless you must save the tag's space or match a C layout.

## Memory layout: `packed`, `extern`, and `opaque`

A normal struct has no guaranteed layout; Zig may reorder fields to save space. For a fixed layout:

- **`packed struct`** packs fields bit by bit, no padding. It has a backing integer and converts with
  `@backingInt` / `@fromBackingInt`. Good for flags and hardware registers.
- **`extern struct`** uses the target's C ABI layout. Use it for structs shared with C.

An **`opaque`** type has unknown size and layout; you can only hold pointers to it. C libraries
often hand out such "handles".

`examples/ch07/layout.zig`

```zig
const std = @import("std");

/// A packed struct lays its fields out bit by bit, here in exactly 8 bits.
const Permissions = packed struct(u8) {
    read: bool = false,
    write: bool = false,
    exec: bool = false,
    _unused: u5 = 0,
};

/// A normal struct: Zig may reorder fields to save space.
const Normal = struct { a: u8, b: u32, c: u8 };

/// An extern struct: C's layout rules, fields in the order written.
const CCompatible = extern struct { a: u8, b: u32, c: u8 };

/// An opaque type has unknown size and layout. You only ever hold
/// pointers to it, usually handles from a C library.
const Handle = opaque {};

pub fn main() void {
    const p: Permissions = .{ .read = true, .exec = true };
    std.debug.print("bits: {b:0>8}, size {d}\n", .{ @backingInt(p), @sizeOf(Permissions) });

    const q: Permissions = @fromBackingInt(0b010);
    std.debug.print("write only: {}\n", .{q.write and !q.read});

    std.debug.print("@sizeOf(Normal) = {d}, @sizeOf(CCompatible) = {d}\n", .{ @sizeOf(Normal), @sizeOf(CCompatible) });
    std.debug.print("@sizeOf(*Handle) = {d}\n", .{@sizeOf(*Handle)});
}
```

```console
$ zig run examples/ch07/layout.zig
bits: 00000101, size 1
write only: true
@sizeOf(Normal) = 8, @sizeOf(CCompatible) = 12
@sizeOf(*Handle) = 8
```

- A packed struct's first field is the lowest bit: `read` is bit 0, `exec` is bit 2.
- `packed struct(u8)` checks that the fields total exactly 8 bits.
- `Normal` is 8 bytes because Zig reorders fields to avoid padding. `CCompatible` keeps the written
  order and pays for padding: 1 + 3 (padding) + 4 + 1 + 3 (padding) = 12.
- `{b:0>8}` prints binary, zero-padded to 8 digits ([Chapter 9](09-strings-and-formatting.md)).

`seek` doesn't need these. [Chapter 19](19-low-level.md) returns to them with C interop.

## A first look at reflection

Zig can inspect types at compile time. Full reflection with `@typeInfo` is in
[Chapter 12](12-comptime.md); here's a taste:

`examples/ch07/reflection.zig`

```zig
const std = @import("std");

const Settings = struct {
    verbose: bool = false,
    width: u16 = 80,
    name: []const u8 = "seek",
};

pub fn main() void {
    // Field names are known at compile time.
    for (std.meta.fieldNames(Settings)) |name| {
        std.debug.print("field: {s}\n", .{name});
    }

    // `@field` accesses a field by a compile-time name.
    var s: Settings = .{};
    @field(s, "width") = 120;
    std.debug.print("width = {d}, has 'color': {}\n", .{ s.width, @hasField(Settings, "color") });

    // `==` doesn't work on structs; std.meta.eql compares field by field.
    const t: Settings = .{ .width = 120 };
    std.debug.print("equal: {}\n", .{std.meta.eql(s, t)});
}
```

```console
$ zig run examples/ch07/reflection.zig
field: verbose
field: width
field: name
width = 120, has 'color': false
equal: true
```

- `std.meta.fieldNames(T)` lists field names. `@field(value, "name")` reads or writes a field by a
  comptime-known name. `@hasField` checks if a field exists.
- `std.meta.eql` compares field by field but doesn't follow pointers: for the `name` slice it
  compares address and length, not text. Both point to the same `"seek"` literal here, so they're
  equal. Use `std.mem.eql` to compare string contents.

## Result locations: a swap that doesn't swap

`p = .{ ... }` doesn't build a temporary and copy it. Zig writes each field straight into `p`. That
avoids copies and is usually invisible, but it shows when the new value reads the old one:

`examples/ch07/result_location.zig`

```zig
const std = @import("std");

const Pair = struct { a: i32, b: i32 };

pub fn main() void {
    // Looks like a swap, but Zig writes each field straight into `p`:
    // p.a = p.b; then p.b = p.a (which is already overwritten).
    var p: Pair = .{ .a = 1, .b = 2 };
    p = .{ .a = p.b, .b = p.a };
    std.debug.print("broken swap: a={d} b={d}\n", .{ p.a, p.b });

    // Copy the old value first.
    var q: Pair = .{ .a = 1, .b = 2 };
    const old = q;
    q = .{ .a = old.b, .b = old.a };
    std.debug.print("real swap:   a={d} b={d}\n", .{ q.a, q.b });
}
```

```console
$ zig run examples/ch07/result_location.zig
broken swap: a=2 b=2
real swap:   a=2 b=1
```

Where a value is written is its **result location**. Arrays work the same
(`arr = .{ arr[1], arr[0] }`). If an initializer reads what it's assigning to, copy the old value
first.

## Building seek: types for options, commands and searches

`run` mixes four jobs: parsing arguments, looping over files, searching text, and reporting errors.
Every helper takes `stdout`, `stderr`, `path`, `pattern`..., and Chapters 9–11 add a dozen flags.
Time for structure:

- `ExitCode`: an enum instead of three loose `u8` constants.
- `Options`: one struct holding every setting, with defaults.
- `Command`: a tagged union for "what the user asked for": help, version, or a search.
- `Match`: one matching line, which knows how to print itself.
- `Searcher`: the state of a search, with methods that do the work.

Behavior doesn't change, so the same commands check it. Almost all of `src/main.zig` changes; go
through it top to bottom.

### ExitCode

Delete the three `exit_*` constants and add this enum after `max_file_size`:

```zig
/// The process exit status. An explicit tag type (`u8`) fixes each value.
const ExitCode = enum(u8) {
    ok = 0, // a line matched (or nothing went wrong)
    no_match = 1, // nothing matched
    trouble = 2, // bad usage or an error
};
```

A function returning `ExitCode` can only return these three values; a `u8` could be anything.

### Color and Options

Add these right after `ExitCode`:

```zig
/// When to highlight matches.
const Color = enum { auto, always, never };

/// Everything the user can configure. Every field has a default, so `.{}`
/// is a complete value. The flags arrive in Chapters 9 to 11.
const Options = struct {
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
```

- `.{}` means "all defaults". Nothing sets these fields until Chapters 9–11. Unused struct fields
  are fine; only unused *locals* are errors.
- `max_count: ?usize = null` means "no limit", clearer than a magic 0.
- `color: Color = .auto`: the field's type tells Zig which enum.

### Command

Add this after `Options`, then move the existing `UsageError` declaration below it (top-level order
doesn't matter to the compiler; this just groups the types):

```zig
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
```

- `help` and `version` carry no data; `search` carries everything a search needs.
- `Search` is declared *inside* `Command`, so its full name is `Command.Search`. Nesting keeps
  helper types next to their user.
- `paths` is a slice into `args`, as in Chapter 6. Nothing is copied.

### Match

A `Match` is one matching line. Add it after `UsageError`:

```zig
/// One matching line.
const Match = struct {
    path: []const u8,
    line_number: usize,
    text: []const u8,

    /// Writes the match in seek's output format, `path:text`.
    fn write(match: Match, out: *std.Io.Writer) std.Io.Writer.Error!void {
        try out.print("{s}:{s}\n", .{ match.path, match.text });
    }
};
```

`write` only reads, so it takes the match by value. `line_number` isn't printed until `-n` in
Chapter 9.

### Searcher

The main change: `searchText` and `reportError` become methods of a `Searcher`, which holds what
they used to take as arguments. Delete the old `reportError`, `argAt` and `searchText` functions at
the bottom of the file, and add this after `Match`:

```zig
/// Searches files for a pattern and remembers how it went.
const Searcher = struct {
    io: std.Io,
    arena: std.mem.Allocator,
    pattern: []const u8,
    options: Options,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    matched_any: bool = false,
    had_error: bool = false,

    /// Searches one file. Problems are reported, not returned: a file we
    /// cannot read must not stop the whole search. `self` is a pointer
    /// because this method updates `matched_any` and `had_error`.
    fn searchPath(self: *Searcher, path: []const u8) std.Io.Writer.Error!void {
        const contents = std.Io.Dir.cwd().readFileAlloc(self.io, path, self.arena, .limited(max_file_size)) catch |err| {
            try self.reportError(path, err);
            return;
        };
        if (try self.searchText(path, contents) > 0) self.matched_any = true;
    }

    /// Prints every line of `text` that contains the pattern and returns
    /// how many lines matched. Only reads `self`, so it takes a const pointer.
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

    fn exitCode(self: Searcher) ExitCode {
        if (self.had_error) return .trouble;
        return if (self.matched_any) .ok else .no_match;
    }
};
```

Each `self` parameter says what the method does with the searcher:

| Method | `self` | Why |
|---|---|---|
| `searchPath` | `*Searcher` | sets `matched_any` (and calls `reportError`, which needs `*Searcher`) |
| `searchText` | `*const Searcher` | only reads `pattern` and `stdout` |
| `reportError` | `*Searcher` | sets `had_error` |
| `exitCode` | `Searcher` | only reads two bools; a copy is fine |

- `searchText`'s body is unchanged except for `self.pattern`, `self.stdout`, and the new `Match`.
  The fields `matched_any` and `had_error` replace Chapter 6's two locals, so `run` no longer tracks
  them.
- `self.stdout` is a `*std.Io.Writer`. Writing through it changes the writer, not the `Searcher`, so
  `searchText` can write through a `*const Searcher`.
- `searchPath` returns `std.Io.Writer.Error!void`: only write errors escape. File errors are
  reported and swallowed.

### main

Two lines in `main` change. The usage-error branch breaks with an `ExitCode`, and the return
converts it to the `u8` the OS expects:

```zig
    const status = run(init.io, arena, args, stdout, stderr) catch |err| switch (err) {
        error.UnknownFlag, error.MissingPattern, error.MissingPath => blk: {
            try stderr.writeAll(usage);
            break :blk .trouble;
        },
        error.WriteFailed => return err,
    };
    try stdout.flush();
    try stderr.flush();
    // The enum's backing integer is the number the operating system sees.
    return @backingInt(status);
}
```

`break :blk .trouble` works because `status` gets its type (`ExitCode`) from `run`'s return type.

### run and parseArgs

Replace `run` (with its doc comment) with this `run`, and add `parseArgs` after it:

```zig
fn run(
    io: std.Io,
    arena: std.mem.Allocator,
    args: []const [:0]const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) (UsageError || std.Io.Writer.Error)!ExitCode {
    switch (try parseArgs(args, stderr)) {
        .help => {
            try stdout.writeAll(usage);
            return .ok;
        },
        .version => {
            try stdout.print("seek {s}\n", .{version});
            return .ok;
        },
        .search => |search| {
            var searcher: Searcher = .{
                .io = io,
                .arena = arena,
                .pattern = search.pattern,
                .options = search.options,
                .stdout = stdout,
                .stderr = stderr,
            };
            for (search.paths) |path| try searcher.searchPath(path);
            return searcher.exitCode();
        },
    }
}

/// Turns the command line into a Command. Unknown flags are reported on
/// `stderr` so the user sees which one was wrong.
fn parseArgs(args: []const [:0]const u8, stderr: *std.Io.Writer) (UsageError || std.Io.Writer.Error)!Command {
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--version")) return .version;
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) return .help;
        if (arg.len > 1 and arg[0] == '-') {
            try stderr.print("seek: unknown flag '{s}'\n", .{arg});
            return error.UnknownFlag;
        }
    }
    if (args.len < 2) return error.MissingPattern;
    if (args.len < 3) return error.MissingPath;
    return .{ .search = .{ .pattern = args[1], .paths = args[2..] } };
}
```

- `run` is short: parse, then `switch` on the command. Forget one of the three variants and it
  won't compile.
- `.search => |search|` captures the `Command.Search` payload.
- `var searcher: Searcher = .{ ... }` sets every field without a default; `matched_any` and
  `had_error` start `false`. It's a `var` because its methods change it.
- `return .version;` works because the return type is `Command`. A variant without a payload is
  written like an enum literal.
- `return .{ .search = .{ .pattern = ..., .paths = ... } };` builds a union holding a struct with no
  type names. Result types flow inward: the outer `.{}` is a `Command`, so `.search`'s value is a
  `Command.Search`. `options` is omitted and gets its default `.{}`.
- `argAt` is gone: checking `args.len` directly is clearer.

Run `zig fmt src/main.zig` if your indentation drifted, then build.

### Checkpoint

Same output as Chapter 6:

```console
$ zig build
$ ./zig-out/bin/seek fox testdata/poem.txt testdata/notes/log.txt
testdata/poem.txt:The quick brown fox
testdata/notes/log.txt:2024-01-01 saw a fox near the barn
testdata/notes/log.txt:2024-01-03 fox tracks in the snow
$ echo $?
0
$ ./zig-out/bin/seek dog nope.txt testdata/poem.txt testdata/notes/todo.md
seek: nope.txt: FileNotFound
testdata/poem.txt:jumps over the lazy dog.
testdata/poem.txt:the dog just sleeps.
testdata/notes/todo.md:- walk the dog
$ echo $?
2
$ ./zig-out/bin/seek --version
seek 0.1.0
$ ./zig-out/bin/seek -h
usage: seek [OPTIONS] PATTERN [PATH ...]
$ ./zig-out/bin/seek -x fox testdata/poem.txt
seek: unknown flag '-x'
usage: seek [OPTIONS] PATTERN [PATH ...]
$ echo $?
2
```

The complete project at this point is in `project/ch07/`.

## Summary

- `struct` groups fields, with optional defaults; `.{ ... }` takes its type from the result type.
  Structs are copied on assignment and can't be compared with `==`.
- Declarations in a struct (`pub const`, `pub fn`) belong to the type. **Decl literals** like
  `.init(...)` and `.empty` use them when the result type is known.
- Methods take the struct first: by value to read, `*T` to change, `*const T` to read without
  copying.
- A struct with only declarations is a namespace. Every file is a struct. `@This()` is the
  enclosing type.
- Tuples are structs with numbered fields: `.{ 1, "a" }`, `t[0]`, `t.len`.
- `enum` names a fixed set of values. `switch` must be exhaustive. `{t}` and `@tagName` give the
  name; `@backingInt` / `@fromBackingInt` convert to and from integers. `_` makes it
  non-exhaustive.
- `union(enum)` holds one variant plus a tag. `switch` with `|x|` or `|*x|` reads or changes the
  payload. Bare unions have no tag and are checked only in safe builds.
- `packed struct` gives a bit-exact layout; `extern struct` gives the C layout; `opaque` hides
  layout entirely.
- `std.meta.fieldNames`, `@field`, `@hasField` and `std.meta.eql` preview reflection.
- Assignment writes straight into the result location, so `x = .{ .a = x.b, .b = x.a }` doesn't
  swap.

## Exercises

1. Write `const Weekday = enum(u3) { monday, ..., sunday }` with methods `isWeekend()` and `next()`
   (the day after `.sunday` is `.monday`). Print four days starting at `.friday`.

<details><summary>Solution</summary>

```zig
const std = @import("std");

const Weekday = enum(u3) {
    monday,
    tuesday,
    wednesday,
    thursday,
    friday,
    saturday,
    sunday,

    pub fn isWeekend(day: Weekday) bool {
        return day == .saturday or day == .sunday;
    }

    pub fn next(day: Weekday) Weekday {
        if (day == .sunday) return .monday;
        return @fromBackingInt(@backingInt(day) + 1);
    }
};

pub fn main() void {
    var day: Weekday = .friday;
    for (0..4) |_| {
        std.debug.print("{t} weekend={}\n", .{ day, day.isWeekend() });
        day = day.next();
    }
}
```

```console
$ zig run weekday.zig
friday weekend=false
saturday weekend=true
sunday weekend=true
monday weekend=false
```

Without the `.sunday` check, `@backingInt(.sunday) + 1` is 7. That fits in a `u3`, but no day has
value 7, so `@fromBackingInt` panics with "invalid enum value".

</details>

2. Write a `Rect` struct with `x, y: i32` and `w, h: u31`, a decl `unit` (a 1×1 rectangle at the
   origin), and methods `init`, `area` (returning `u64`) and `contains(p: Point) bool`. Create
   rectangles with decl literals.

<details><summary>Solution</summary>

```zig
const std = @import("std");

const Point = struct { x: i32, y: i32 };

const Rect = struct {
    x: i32,
    y: i32,
    w: u31,
    h: u31,

    pub const unit: Rect = .{ .x = 0, .y = 0, .w = 1, .h = 1 };

    pub fn init(x: i32, y: i32, w: u31, h: u31) Rect {
        return .{ .x = x, .y = y, .w = w, .h = h };
    }

    pub fn area(r: Rect) u64 {
        return @as(u64, r.w) * r.h;
    }

    pub fn contains(r: Rect, p: Point) bool {
        return p.x >= r.x and p.x < r.x + r.w and
            p.y >= r.y and p.y < r.y + r.h;
    }
};

pub fn main() void {
    const r: Rect = .init(2, 3, 4, 5);
    const u: Rect = .unit;
    std.debug.print("area {d}, unit area {d}\n", .{ r.area(), u.area() });
    std.debug.print("{} {} {}\n", .{
        r.contains(.{ .x = 2, .y = 3 }),
        r.contains(.{ .x = 6, .y = 3 }),
        u.contains(.{ .x = 0, .y = 0 }),
    });
}
```

```console
$ zig run rect.zig
area 20, unit area 1
true false true
```

`u31` can't be negative yet fits in an `i32`, so `r.x + r.w` needs no cast. `@as(u64, r.w) * r.h`
widens before multiplying, so a large area can't overflow.

</details>

3. Define `const Token = union(enum) { number: i64, plus, minus }` and write
   `fn eval(tokens: []const Token) i64` that evaluates `5 + 3 - 10` from left to right.

<details><summary>Solution</summary>

```zig
const std = @import("std");

const Token = union(enum) {
    number: i64,
    plus,
    minus,
};

/// Evaluates tokens like `5 + 3 - 2` from left to right.
fn eval(tokens: []const Token) i64 {
    var total: i64 = 0;
    var sign: i64 = 1;
    for (tokens) |token| {
        switch (token) {
            .number => |n| total += sign * n,
            .plus => sign = 1,
            .minus => sign = -1,
        }
    }
    return total;
}

pub fn main() void {
    const tokens = [_]Token{ .{ .number = 5 }, .plus, .{ .number = 3 }, .minus, .{ .number = 10 } };
    std.debug.print("{d}\n", .{eval(&tokens)});
}
```

```console
$ zig run tokens.zig
-2
```

</details>

4. Give `Searcher` an `unreadable: usize = 0` field counting files it couldn't read. After the
   search, if any failed, print `seek: N of M files could not be read` on stderr.

<details><summary>Solution</summary>

Add the field next to `had_error`, and count in `reportError`:

```zig
    matched_any: bool = false,
    had_error: bool = false,
    unreadable: usize = 0,
```

```zig
    fn reportError(self: *Searcher, path: []const u8, err: anyerror) std.Io.Writer.Error!void {
        self.had_error = true;
        self.unreadable += 1;
        // ... rest unchanged ...
```

In `run`, after the loop:

```zig
            for (search.paths) |path| try searcher.searchPath(path);
            if (searcher.unreadable > 0) {
                try stderr.print("seek: {d} of {d} files could not be read\n", .{ searcher.unreadable, search.paths.len });
            }
            return searcher.exitCode();
```

```console
$ ./zig-out/bin/seek dog nope.txt testdata/poem.txt testdata/notes
seek: nope.txt: FileNotFound
testdata/poem.txt:jumps over the lazy dog.
testdata/poem.txt:the dog just sleeps.
seek: testdata/notes: IsDir
seek: 2 of 3 files could not be read
```

The second `reportError` already flushed all matches, so the summary comes last. (This exercise
isn't part of the real `seek`.)

</details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-7--structs-enums-and-unions)
