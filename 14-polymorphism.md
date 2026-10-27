# Chapter 14 — Interfaces and Polymorphism

Many languages have an `interface` or `trait` keyword: declare some methods, and any type that implements them can be used through the interface. Zig has no such keyword. Instead it has a few patterns built from features you know: tagged unions, function pointers, `@fieldParentPtr`, and comptime. The standard library uses all of them. This chapter writes one small example, shapes with an area, in each style and compares them. Then it opens up `std.Io.Writer`, used since [Chapter 1](01-getting-started.md), and builds a custom writer. In the project, seek's matching and output modes become tagged unions, and a new `-W` flag matches whole lines against wildcards.

## Pattern 1: tagged unions

You met tagged unions in [Chapter 7](07-structs-enums-unions.md). A `union(enum)` value is exactly one of its variants, and a `switch` on it must handle every variant. That makes it an interface over a **closed set** of types:

`examples/ch14/shape_union.zig`

```zig
const std = @import("std");

const Circle = struct {
    radius: f64,
    pub fn area(c: Circle) f64 {
        return std.math.pi * c.radius * c.radius;
    }
};

const Rect = struct {
    width: f64,
    height: f64,
    pub fn area(r: Rect) f64 {
        return r.width * r.height;
    }
};

/// Pattern 1: a tagged union. The set of shapes is closed: it is exactly
/// the fields listed here.
const Shape = union(enum) {
    circle: Circle,
    rect: Rect,
    /// A variant can be plain data, without its own type and methods.
    square: f64,

    fn area(shape: Shape) f64 {
        return switch (shape) {
            .circle => |c| c.area(),
            .rect => |r| r.area(),
            .square => |side| side * side,
        };
    }

    fn name(shape: Shape) []const u8 {
        return @tagName(shape);
    }
};

/// When every variant has the same method, `inline else` writes the
/// switch for you.
const Shape2 = union(enum) {
    circle: Circle,
    rect: Rect,

    fn area(shape: Shape2) f64 {
        return switch (shape) {
            inline else => |s| s.area(),
        };
    }
};

pub fn main() void {
    const shapes = [_]Shape{
        .{ .circle = .{ .radius = 1 } },
        .{ .rect = .{ .width = 2, .height = 3 } },
        .{ .square = 4 },
    };
    for (shapes) |shape| std.debug.print("{s}: {d:.2}\n", .{ shape.name(), shape.area() });

    const s2: Shape2 = .{ .rect = .{ .width = 5, .height = 5 } };
    std.debug.print("Shape2 rect: {d:.2}\n", .{s2.area()});
    std.debug.print("@sizeOf(Shape) = {d}\n", .{@sizeOf(Shape)});
}
```

```console
$ zig run examples/ch14/shape_union.zig
circle: 3.14
rect: 6.00
square: 16.00
Shape2 rect: 25.00
@sizeOf(Shape) = 24
```

Things to notice:

- "Dispatch" is a `switch`. Each prong captures the payload with `|c|` and calls the variant's code. The compiler can inline all of it; there are no pointers to follow.
- The payload is stored **inside** the union. A `Shape` is its largest variant (`Rect`, 16 bytes) plus the tag, rounded up for alignment: 24 bytes. No allocation, and an array of shapes is one contiguous block.
- Variants don't need their own types: `.square` is just an `f64`.
- `@tagName` gives the active variant's name.
- **`inline else`** generates one prong per remaining variant, with `s` of that variant's type. When every variant has the same method, `inline else => |s| s.area()` is the whole dispatcher. Add a variant without `area` and that line stops compiling.
- Add a variant, and every `switch` without an `else` stops compiling until you handle it. That is this pattern's main strength: the compiler finds every place to update.

The weakness is the flip side: the set is closed. Code that uses `Shape` can't add a kind of shape without editing the union. That's fine within one program, where you own all the code. seek uses this pattern twice below.

## Pattern 2: vtables and fat pointers

To keep the set of types **open**, store a pointer to the object plus a pointer to a table of functions that handle it. The pair is a **fat pointer**; the table is a **vtable** (virtual function table):

`examples/ch14/shape_vtable.zig`

```zig
const std = @import("std");

/// Pattern 2: a fat pointer. A Shape is "a pointer to some object" plus
/// "a pointer to the functions that work on it", like std.mem.Allocator.
const Shape = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    const VTable = struct {
        area: *const fn (ptr: *anyopaque) f64,
        name: *const fn (ptr: *anyopaque) []const u8,
    };

    fn area(shape: Shape) f64 {
        return shape.vtable.area(shape.ptr);
    }

    fn name(shape: Shape) []const u8 {
        return shape.vtable.name(shape.ptr);
    }
};

const Circle = struct {
    radius: f64,

    fn area(ptr: *anyopaque) f64 {
        const c: *Circle = @ptrCast(@alignCast(ptr));
        return std.math.pi * c.radius * c.radius;
    }

    fn name(_: *anyopaque) []const u8 {
        return "circle";
    }

    /// One vtable for all circles, stored in the program's constant data.
    const vtable: Shape.VTable = .{ .area = area, .name = name };

    fn shape(c: *Circle) Shape {
        return .{ .ptr = c, .vtable = &vtable };
    }
};

const Rect = struct {
    width: f64,
    height: f64,

    fn area(ptr: *anyopaque) f64 {
        const r: *Rect = @ptrCast(@alignCast(ptr));
        return r.width * r.height;
    }

    fn name(_: *anyopaque) []const u8 {
        return "rect";
    }

    const vtable: Shape.VTable = .{ .area = area, .name = name };

    fn shape(r: *Rect) Shape {
        return .{ .ptr = r, .vtable = &vtable };
    }
};

/// Knows nothing about Circle or Rect. New shapes can be added in other
/// files, even other packages, without changing this function.
fn totalArea(shapes: []const Shape) f64 {
    var total: f64 = 0;
    for (shapes) |s| total += s.area();
    return total;
}

pub fn main() void {
    var circle: Circle = .{ .radius = 1 };
    var rect: Rect = .{ .width = 2, .height = 3 };
    const shapes = [_]Shape{ circle.shape(), rect.shape() };

    for (shapes) |s| std.debug.print("{s}: {d:.2}\n", .{ s.name(), s.area() });
    std.debug.print("total: {d:.2}\n", .{totalArea(&shapes)});

    // The Shape points at `rect`, so it sees changes to it.
    rect.width = 10;
    std.debug.print("rect after resize: {d:.2}\n", .{shapes[1].area()});
    std.debug.print("@sizeOf(Shape) = {d}\n", .{@sizeOf(Shape)});
}
```

```console
$ zig run examples/ch14/shape_vtable.zig
circle: 3.14
rect: 6.00
total: 9.14
rect after resize: 30.00
@sizeOf(Shape) = 16
```

Things to notice:

- `Shape` is two pointers (16 bytes), whatever the shape. `ptr` is `*anyopaque`, a pointer to an unknown type: the type erasure from [Chapter 13](13-generics.md#type-erasure-a-preview).
- Each implementation casts the pointer back with `@ptrCast(@alignCast(ptr))`. Nothing checks the cast. Each type's `shape()` method is the only place that pairs a pointer with a vtable, so they always match.
- The vtable is a `const` declaration: one per type, in read-only memory. `&vtable` points to it.
- `totalArea` works with any `Shape`, including types written later, in other files or packages.
- A `Shape` **refers to** the object; it doesn't contain it. Changing `rect` changes what `shapes[1].area()` returns. The object must outlive the fat pointer.
- Each call follows two pointers and makes an indirect call, which the compiler usually can't inline.

This is exactly how `std.mem.Allocator` is defined (`lib/std/mem/Allocator.zig`, doc comments removed):

```zig
ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    alloc: *const fn (*anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8,
    resize: *const fn (*anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool,
    remap: *const fn (*anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8,
    free: *const fn (*anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void,
};
```

A file is a struct ([Chapter 7](07-structs-enums-unions.md)), so `ptr` and `vtable` are the fields of `Allocator`. The methods you call, like `alloc`, `free`, `create`, and `dupe`, are ordinary functions built on these four. Every allocator, from `SafeAllocator` to `ArenaAllocator`, has an `allocator()` method returning this fat pointer, just like `Circle.shape()`. That's why any allocator can be passed as an `Allocator`.

seek's `FindFn` from [Chapter 9](09-strings-and-formatting.md) was the smallest version of this idea: one function pointer, chosen at run time.

## Pattern 3: an interface field and `@fieldParentPtr`

A variation puts the interface **inside** the implementation, as a field. Callers get a pointer to that field. The implementation's functions receive it and step back to the containing struct with **`@fieldParentPtr`**:

`examples/ch14/shape_parent_ptr.zig`

```zig
const std = @import("std");

/// Pattern 3: the interface is a field inside the implementation, like
/// std.Io.Writer. It can hold data shared by all shapes (here `name`), and
/// callers pass `*Shape` around.
const Shape = struct {
    vtable: *const VTable,
    name: []const u8,

    const VTable = struct {
        area: *const fn (shape: *const Shape) f64,
    };

    fn area(shape: *const Shape) f64 {
        return shape.vtable.area(shape);
    }
};

const Circle = struct {
    radius: f64,
    shape: Shape = .{ .vtable = &.{ .area = area }, .name = "circle" },

    fn area(shape: *const Shape) f64 {
        // `shape` points at the `shape` field of some Circle. Step back
        // from the field to the struct that contains it.
        const c: *const Circle = @alignCast(@fieldParentPtr("shape", shape));
        return std.math.pi * c.radius * c.radius;
    }
};

const Rect = struct {
    width: f64,
    height: f64,
    shape: Shape = .{ .vtable = &.{ .area = area }, .name = "rect" },

    fn area(shape: *const Shape) f64 {
        const r: *const Rect = @alignCast(@fieldParentPtr("shape", shape));
        return r.width * r.height;
    }
};

fn describe(shape: *const Shape) void {
    std.debug.print("{s}: {d:.2}\n", .{ shape.name, shape.area() });
}

pub fn main() void {
    const circle: Circle = .{ .radius = 1 };
    const rect: Rect = .{ .width = 2, .height = 3 };

    // Always take the address of the field inside the object.
    describe(&circle.shape);
    describe(&rect.shape);

    std.debug.print("@offsetOf(Rect, \"shape\") = {d}\n", .{@offsetOf(Rect, "shape")});
}
```

```console
$ zig run examples/ch14/shape_parent_ptr.zig
circle: 3.14
rect: 6.00
@offsetOf(Rect, "shape") = 16
```

`@fieldParentPtr("shape", shape)` takes a pointer to a field named `shape` and returns a pointer to the struct around it, by subtracting the field's offset. Here the offset is 16, because the compiler put `width` and `height` first, but you don't need to know that: the result type (`*const Rect`) tells the builtin which struct to use. `@alignCast` is needed because the builtin can't know the parent's alignment.

Why use this instead of pattern 2?

- The interface struct can hold **data** shared by all implementations, not just function pointers. Here it's a `name`; in `std.Io.Writer` it's the buffer, which makes writing fast (see below).
- Callers pass one pointer, `*Shape`, not a two-pointer struct.

The price is a new way to get it wrong: **never copy the interface out of its parent**. Add this to `main`:

```zig
    const copy = circle.shape;
    describe(&copy);
```

and it compiles, then prints something like:

```text
circle: 0.00
```

`copy` is a lone `Shape` on the stack. `@fieldParentPtr` assumes it is inside a `Circle` and computes an address in unrelated stack memory. This is undefined behavior: a wrong number, garbage, or a crash. [Chapter 11](11-files-and-io.md)'s gotcha "take a pointer to `interface`, never a copy" is this bug. Always take the field's address in place (`&circle.shape`), and store `*Shape`, never `Shape`.

## Pattern 4: static duck typing with `anytype`

If the type is known at compile time, you need no run-time machinery. [Chapter 13](13-generics.md)'s `anytype` is already an interface, checked by the compiler:

`examples/ch14/shape_anytype.zig`

```zig
const std = @import("std");

const Circle = struct {
    radius: f64,
    pub fn area(c: Circle) f64 {
        return std.math.pi * c.radius * c.radius;
    }
};

const Rect = struct {
    width: f64,
    height: f64,
    pub fn area(r: Rect) f64 {
        return r.width * r.height;
    }
};

/// Pattern 4: static duck typing. Any value with an `area` method works,
/// and each call is resolved at compile time.
fn describe(shape: anytype) void {
    std.debug.print("{s}: {d:.2}\n", .{ @typeName(@TypeOf(shape)), shape.area() });
}

/// A tuple can hold different types; `inline for` visits each one with
/// its real type.
fn totalArea(shapes: anytype) f64 {
    var total: f64 = 0;
    inline for (shapes) |s| total += s.area();
    return total;
}

pub fn main() void {
    const circle: Circle = .{ .radius = 1 };
    const rect: Rect = .{ .width = 2, .height = 3 };
    describe(circle);
    describe(rect);
    std.debug.print("total: {d:.2}\n", .{totalArea(.{ circle, rect, rect })});
}
```

```console
$ zig run examples/ch14/shape_anytype.zig
shape_anytype.Circle: 3.14
shape_anytype.Rect: 6.00
total: 15.14
```

Every call is direct and can be inlined. `Circle` and `Rect` know nothing of each other or of any interface. For several types at once, a tuple holds values of different types and `inline for` unrolls the loop, one copy of the body per element.

The limits: each type gets its own copy of the code, all types must be known at compile time, and you can't build a run-time list of mixed types (a tuple's length and types are fixed at compile time). `std.debug.print` and `{f}` work this way: `print` checks at compile time that the value has a `format` method.

## Choosing a pattern

| | Tagged union | Vtable (fat pointer) | Interface field + `@fieldParentPtr` | `anytype` |
|---|---|---|---|---|
| Set of types | closed | open | open | open |
| Known at | run time | run time | run time | compile time |
| Call cost | a `switch` | indirect call | indirect call | direct call |
| Storage | inline, no pointers | object lives elsewhere | object lives elsewhere | inline |
| Adding a type | edit the union and every `switch` | write a new type | write a new type | write a new type |
| Adding an operation | one new `switch` | change every implementation | change every implementation | write it |
| In `std` | `std.json.Value`, `std.lang.Type` | `std.mem.Allocator`, `std.Random` | `std.Io.Writer`, `std.Io.Reader` | `std.debug.print`, `std.mem.sort` |

Rules of thumb:

- Start with a **tagged union** when you own all the variants. It is the most common choice in Zig, and the compiler checks every use.
- Use a **vtable** (either kind) when other people's code must add implementations, as with allocators and writers.
- Use **`anytype`** or `comptime T: type` when the type is fixed at compile time and you want zero overhead.

## How `std.Io.Writer` works

Every `print` in this book went through a `*std.Io.Writer`. Its fields (from `lib/std/Io/Writer.zig`):

```zig
vtable: *const VTable,
/// If this has length zero, the writer is unbuffered, and `flush` is a no-op.
buffer: []u8,
/// In `buffer` before this are buffered bytes, after this is `undefined`.
end: usize = 0,
```

It is pattern 3: the `Writer` sits inside an implementation such as `File.Writer` (as its `interface` field) or `Writer.Allocating` (as `writer`). And it holds the **buffer**. That is the key design decision: the fast path of every write lives in the interface and needs no virtual call. Here is `write`:

```zig
pub fn write(w: *Writer, bytes: []const u8) Error!usize {
    if (w.end + bytes.len <= w.buffer.len) {
        @branchHint(.likely);
        @memcpy(w.buffer[w.end..][0..bytes.len], bytes);
        w.end += bytes.len;
        return bytes.len;
    }
    return w.vtable.drain(w, &.{bytes}, 1);
}
```

If the bytes fit, they are copied into the buffer; no function pointer is involved. Only when the buffer is full does the writer call the implementation's **`drain`**, which must send the buffered bytes (`buffer[0..end]`) and then the new data somewhere.

`VTable` has four functions; only `drain` is required:

- **`drain(w, data, splat)`** consumes `buffer[0..end]` first, then each slice in `data`, with the last slice counting **`splat`** times. So a writer can handle "4096 spaces" without materializing them. It returns how many bytes of `data` it consumed (not counting the buffer), which may be fewer than all.
- **`sendFile`** can copy straight from a file (on Linux, without passing the bytes through user memory). The default reports "unimplemented", and the caller falls back to reading and writing.
- **`flush`** defaults to calling `drain` until the buffer is empty.
- **`rebase`** makes room in the buffer; the default suits most writers.

`std.Io.Reader` is built the same way: a buffer in the interface and a `stream` function in its vtable.

## Writing your own `Writer`

A writer that upper-cases everything and passes it to another writer needs one function:

`examples/ch14/upper_writer.zig`

```zig
const std = @import("std");
const Writer = std.Io.Writer;

/// A std.Io.Writer that upper-cases everything and passes it on to
/// another writer.
const UpperWriter = struct {
    out: *Writer,
    drains: usize = 0,
    /// The interface. Callers use `&upper.writer`; it must not be copied
    /// out of the UpperWriter, or `drain` can't find its way back.
    writer: Writer,

    fn init(out: *Writer, buffer: []u8) UpperWriter {
        return .{
            .out = out,
            .writer = .{ .vtable = &.{ .drain = drain }, .buffer = buffer },
        };
    }

    /// Called when `buffer` is full, and by `flush`. Must consume the
    /// buffered bytes first, then `data`, whose last element counts
    /// `splat` times. Returns how many bytes of `data` it consumed.
    fn drain(w: *Writer, data: []const []const u8, splat: usize) Writer.Error!usize {
        const self: *UpperWriter = @alignCast(@fieldParentPtr("writer", w));
        self.drains += 1;
        try self.emit(w.buffer[0..w.end]);
        w.end = 0;

        var consumed: usize = 0;
        for (data[0 .. data.len - 1]) |bytes| {
            try self.emit(bytes);
            consumed += bytes.len;
        }
        const pattern = data[data.len - 1];
        for (0..splat) |_| {
            try self.emit(pattern);
            consumed += pattern.len;
        }
        return consumed;
    }

    fn emit(self: *UpperWriter, bytes: []const u8) Writer.Error!void {
        for (bytes) |byte| try self.out.writeByte(std.ascii.toUpper(byte));
    }
};

pub fn main() !void {
    var result: [256]u8 = undefined;
    var out: Writer = .fixed(&result);

    var buffer: [16]u8 = undefined;
    var upper: UpperWriter = .init(&out, &buffer);
    const w = &upper.writer; // a pointer to the field, never a copy

    try w.writeAll("hello, ");
    try w.print("{s} has {d} letters", .{ "zig", 3 });
    try w.print(" and a [{s:->8}]\n", .{"pad"});
    try w.writeAll("bye\n");
    std.debug.print("before flush: {d} drains, {d} bytes still buffered\n", .{ upper.drains, w.end });
    try w.flush();
    std.debug.print("after flush:  {d} drains\n", .{upper.drains});
    std.debug.print("{s}", .{out.buffered()});
}
```

```console
$ zig run examples/ch14/upper_writer.zig
before flush: 2 drains, 4 bytes still buffered
after flush:  3 drains
HELLO, ZIG HAS 3 LETTERS AND A [-----PAD]
BYE
```

Things to notice:

- `drain` finds its `UpperWriter` with `@fieldParentPtr("writer", w)`, the same line `Writer.Discarding` uses in the standard library.
- It follows the contract: buffer first (then `w.end = 0`), then every slice of `data`, the last one repeated `splat` times.
- The 16-byte buffer collects small writes. `print` produces many small pieces (`"hello, "`, `"zig"`, `" has "`, ...), but `drain` ran only twice for 46 bytes. With a 4 KiB buffer and a file behind it, that's one system call instead of dozens.
- `.vtable = &.{ .drain = drain }` takes the address of a comptime-known struct literal. Omitted fields use the `VTable` defaults (`sendFile`, `flush`, `rebase`).
- The target, `Writer.fixed(&result)`, writes into a plain array; `buffered()` returns what was written. It fails with `error.WriteFailed` when the array is full.
- `const w = &upper.writer;` points to the field. As in pattern 3, `const w = upper.writer;` would copy the interface, and `drain` would compute a bogus `UpperWriter` address.

## Testing code that writes

Because output functions take a `*Writer`, tests can pass a writer that keeps the bytes in memory. Two are useful:

- **`std.Io.Writer.Allocating`** grows as needed. Read the result with `written()`.
- **`std.Io.Writer.fixed(buffer)`** writes into an array you provide. Read the result with `buffered()`.

`examples/ch14/report.zig`

```zig
const std = @import("std");
const Writer = std.Io.Writer;

const Score = struct { name: []const u8, points: u32 };

/// Two output formats. Neither knows where the bytes go: a file, a
/// terminal, or memory. That is the caller's choice of *Writer.
const Format = union(enum) {
    text: struct { width: usize },
    csv,

    fn write(format: Format, w: *Writer, scores: []const Score) Writer.Error!void {
        switch (format) {
            .text => |text| for (scores) |s| {
                try w.print("{s}", .{s.name});
                try w.splatByteAll('.', text.width -| s.name.len);
                try w.print("{d}\n", .{s.points});
            },
            .csv => {
                try w.writeAll("name,points\n");
                for (scores) |s| try w.print("{s},{d}\n", .{ s.name, s.points });
            },
        }
    }
};

const example_scores = [_]Score{ .{ .name = "ada", .points = 42 }, .{ .name = "grace", .points = 7 } };

pub fn main(init: std.process.Init) !void {
    var buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &buffer);
    const stdout = &stdout_writer.interface;
    try Format.write(.{ .text = .{ .width = 8 } }, stdout, &example_scores);
    try Format.write(.csv, stdout, &example_scores);
    try stdout.flush();
}

test "text format, into growable memory" {
    var out: Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try Format.write(.{ .text = .{ .width = 8 } }, &out.writer, &example_scores);
    try std.testing.expectEqualStrings("ada.....42\ngrace...7\n", out.written());
}

test "csv format, into a fixed buffer" {
    var buffer: [64]u8 = undefined;
    var w: Writer = .fixed(&buffer);
    try Format.write(.csv, &w, &example_scores);
    try std.testing.expectEqualStrings("name,points\nada,42\ngrace,7\n", w.buffered());
}

test "a fixed buffer that is too small fails" {
    var buffer: [10]u8 = undefined;
    var w: Writer = .fixed(&buffer);
    try std.testing.expectError(error.WriteFailed, Format.write(.csv, &w, &example_scores));
}
```

```console
$ zig run examples/ch14/report.zig
ada.....42
grace...7
name,points
ada,42
grace,7
$ zig test examples/ch14/report.zig
1/3 report.test.text format, into growable memory...OK
2/3 report.test.csv format, into a fixed buffer...OK
3/3 report.test.a fixed buffer that is too small fails...OK
All 3 tests passed.
```

`Format` is a tagged union, but the tests don't care which pattern produced the bytes; they only see a `*Writer`. `splatByteAll('.', n)` writes `n` dots. `-|` is saturating subtraction: it stops at zero instead of overflowing when a name is longer than the column. The constant is named `example_scores` because a parameter may not shadow a declaration in the file: naming it `scores` would be a compile error.

## Building seek: a `Matcher`, a `Printer`, and `-W`

Since [Chapter 9](09-strings-and-formatting.md), seek has picked its matching with a function pointer (`FindFn`), and `searchFile`/`searchReader` have picked the output with a pile of `if`s on the options. Both become tagged unions:

- **`Matcher`** in `match.zig`: `literal`, `ignore_case`, or `wildcard`. `find(line)` returns where the match is.
- **`Printer`** in a new `output.zig`: `lines`, `count`, or `files`. The search code reports what it finds; the printer decides how it looks.

Why not vtables? Both sets are closed: seek owns every matcher and output mode, and no outside code will add one. A union stores its data inline (the wildcard matcher needs a pattern *and* a flag, which a bare function pointer can't carry), needs no allocation, and the compiler checks every `switch` when a fourth variant arrives. Both still write to a `*std.Io.Writer`, a vtable interface, because *that* set really is open: a file, a terminal, or memory in a test.

The new matcher brings a feature: **`-W`/`--wildcard`** treats PATTERN as a wildcard (`*` and `?`) that must match the **whole line**, using the matcher `--glob` already uses for file names.

### `src/match.zig`

Replace `src/match.zig` with:

```zig
//! Pattern matching: the line matchers behind PATTERN, and the wildcard
//! matcher shared by -W and --glob.

const std = @import("std");

/// Where a match was found in a line: `line[start..end]`.
pub const Span = struct {
    start: usize,
    end: usize,
};

/// The ways seek can match a line. A tagged union is a closed set: every
/// `switch` on it must handle every kind, and the compiler checks that.
pub const Matcher = union(enum) {
    /// The line contains the pattern.
    literal: []const u8,
    /// The line contains the pattern, ignoring ASCII case (-i).
    ignore_case: []const u8,
    /// The whole line matches a wildcard pattern (-W).
    wildcard: Wildcard,

    pub const Wildcard = struct {
        pattern: []const u8,
        ignore_case: bool,
    };

    /// Picks the matcher for the command-line options. The matcher refers
    /// to `pattern`, it doesn't copy it.
    pub fn init(pattern: []const u8, ignore_case: bool, wildcard: bool) Matcher {
        if (wildcard) return .{ .wildcard = .{ .pattern = pattern, .ignore_case = ignore_case } };
        if (ignore_case) return .{ .ignore_case = pattern };
        return .{ .literal = pattern };
    }

    /// Returns the first match in `line`, if any.
    pub fn find(matcher: Matcher, line: []const u8) ?Span {
        switch (matcher) {
            .literal => |needle| {
                const start = std.mem.find(u8, line, needle) orelse return null;
                return .{ .start = start, .end = start + needle.len };
            },
            .ignore_case => |needle| {
                const start = std.ascii.findIgnoreCase(line, needle) orelse return null;
                return .{ .start = start, .end = start + needle.len };
            },
            .wildcard => |w| {
                const matched = if (w.ignore_case)
                    wildcardMatchIgnoreCase(w.pattern, line)
                else
                    wildcardMatch(w.pattern, line);
                return if (matched) .{ .start = 0, .end = line.len } else null;
            },
        }
    }
};

/// Reports whether all of `text` matches the shell-style wildcard `pattern`:
/// `*` matches any run of bytes (even an empty one), `?` matches exactly one
/// byte, and every other byte matches itself.
pub fn wildcardMatch(pattern: []const u8, text: []const u8) bool {
    return matchWildcard(false, pattern, text);
}

/// Like `wildcardMatch`, but ignores ASCII case.
pub fn wildcardMatchIgnoreCase(pattern: []const u8, text: []const u8) bool {
    return matchWildcard(true, pattern, text);
}

/// The matcher behind both functions above. `ignore_case` is a comptime
/// parameter, so the compiler generates two specialized copies and the
/// check below costs nothing at run time.
///
/// It walks both slices once, remembering the most recent `*`. On a
/// mismatch it backtracks: that `*` swallows one more byte of `text` and
/// matching resumes right after it. That keeps the cost at
/// O(pattern.len * text.len) in the worst case.
fn matchWildcard(comptime ignore_case: bool, pattern: []const u8, text: []const u8) bool {
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
        } else if (p < pattern.len and (pattern[p] == '?' or eqlByte(ignore_case, pattern[p], text[t]))) {
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

fn eqlByte(comptime ignore_case: bool, a: u8, b: u8) bool {
    return if (ignore_case) std.ascii.toLower(a) == std.ascii.toLower(b) else a == b;
}
```

Things to notice:

- **`Matcher.find`** switches on the matcher and captures each payload: `|needle|` for the string variants, `|w|` for the `Wildcard` struct. It returns a `Span`, so the highlighter knows exactly what to color. A wildcard match spans the whole line.
- **`init`** is called as `.init(...)` with result type `Matcher`, like `std.ArrayList`'s `.empty`. `-W` wins; `-i` then picks between the other two, or sets the wildcard's `ignore_case`.
- **`matchWildcard(comptime ignore_case: bool, ...)`** is the old `wildcardMatch` body, except bytes are compared with `eqlByte(ignore_case, ...)`. Because `ignore_case` is comptime, `matchWildcard(false, ...)` and `matchWildcard(true, ...)` are two separate functions, and in each the `if` inside `eqlByte` is decided at compile time: the `-i` check never runs at run time. `wildcardMatch` and `wildcardMatchIgnoreCase` are thin public wrappers, so `--glob` still calls `wildcardMatch`.
- The matcher **refers to** the pattern without copying it. `Searcher` owns the pattern and outlives the matcher.

### `src/output.zig` (new)

`Match`, its `format` method, `writeHighlighted`, and the ANSI codes move here from `search.zig`. Create `src/output.zig`:

```zig
//! Writing results. Search code reports what it found to a `Printer`; the
//! printer decides what that looks like.

const std = @import("std");
const Io = std.Io;
const Matcher = @import("match.zig").Matcher;
const Options = @import("cli.zig").Options;

/// ANSI escape sequences: bold red, then back to normal.
const ansi_match = "\x1b[1;31m";
const ansi_reset = "\x1b[0m";

/// The output modes, as a tagged union: a value is exactly one of them,
/// and each carries only the data it needs.
pub const Printer = union(enum) {
    /// Print every selected line (the default).
    lines: Lines,
    /// -c: print `path:count` for every file.
    count,
    /// -l: print the names of files with a selected line.
    files,

    pub const Lines = struct {
        line_numbers: bool,
        /// Null means "print lines without color".
        highlight: ?Matcher,
    };

    pub fn init(options: Options, matcher: Matcher) Printer {
        // -l wins over -c, like in grep.
        if (options.files_only) return .files;
        if (options.count_only) return .count;
        return .{
            .lines = .{
                .line_numbers = options.line_numbers,
                // Inverted matches have nothing to highlight. `auto` behaves like
                // `never` until Chapter 19 teaches seek to detect a terminal.
                .highlight = if (options.color == .always and !options.invert) matcher else null,
            },
        };
    }

    /// Called for every selected line.
    pub fn line(printer: Printer, w: *Io.Writer, path: []const u8, line_number: usize, text: []const u8) Io.Writer.Error!void {
        switch (printer) {
            .lines => |lines| {
                const match: Match = .{
                    .path = path,
                    .line_number = if (lines.line_numbers) line_number else null,
                    .text = text,
                    .highlight = lines.highlight,
                };
                try w.print("{f}\n", .{match});
            },
            .count, .files => {},
        }
    }

    /// Called once a file has been searched, with its number of selected lines.
    pub fn fileDone(printer: Printer, w: *Io.Writer, path: []const u8, matches: usize) Io.Writer.Error!void {
        switch (printer) {
            .lines => {},
            .count => try w.print("{s}:{d}\n", .{ path, matches }),
            .files => if (matches > 0) try w.print("{s}\n", .{path}),
        }
    }
};

/// One selected line, ready to print with `{f}`.
pub const Match = struct {
    path: []const u8,
    /// Null unless line numbers were requested (-n).
    line_number: ?usize,
    text: []const u8,
    /// Null means "print the text as is".
    highlight: ?Matcher = null,

    /// Called by the `{f}` format specifier: writes `path:[line:]text`.
    pub fn format(match: Match, w: *Io.Writer) Io.Writer.Error!void {
        try w.print("{s}:", .{match.path});
        if (match.line_number) |n| try w.print("{d}:", .{n});
        if (match.highlight) |matcher| {
            try writeHighlighted(w, match.text, matcher);
        } else {
            try w.writeAll(match.text);
        }
    }
};

/// Writes `text`, wrapping every match in ANSI colors.
fn writeHighlighted(w: *Io.Writer, text: []const u8, matcher: Matcher) Io.Writer.Error!void {
    var rest = text;
    while (matcher.find(rest)) |span| {
        // An empty match (an empty pattern, or `-W '*'` on an empty line)
        // has nothing to color, and searching again would find it forever.
        if (span.end == span.start) break;
        // The format string is comptime-known, so `++` can splice in the
        // escape codes at compile time.
        try w.print("{s}" ++ ansi_match ++ "{s}" ++ ansi_reset, .{ rest[0..span.start], rest[span.start..span.end] });
        rest = rest[span.end..];
    }
    try w.writeAll(rest);
}
```

Things to notice:

- `count` and `files` have **no payload**. In a `union(enum)`, a variant without a type has type `void`; `return .files;` creates it with an enum literal.
- `Printer.line` and `Printer.fileDone` each switch exhaustively. `.count, .files => {}` handles two variants in one prong.
- The "`-l` wins over `-c`" rule now lives in one place, `init`.
- `Match.highlight` is now a `?Matcher`: the highlighter asks the matcher where the matches are. That makes highlighting work for `-W`, which the old `Highlight` (a pattern and a find function) couldn't express.
- `writeHighlighted` loops `while (matcher.find(rest)) |span|`. An empty span (an empty PATTERN, or `-W '*'` on an empty line) would be found at the same place forever, so the loop stops there.

### `src/search.zig`

Update the imports:

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const match = @import("match.zig");
const Matcher = match.Matcher;
const Printer = @import("output.zig").Printer;
const Options = @import("cli.zig").Options;
const Stats = @import("stats.zig").Stats;
```

Delete everything between `binary_probe_len` and the `Searcher` doc comment: `ansi_match`, `ansi_reset`, `FindFn`, `findExact`, `Highlight`, `Match`, and `writeHighlighted`. They are gone or moved to `output.zig`.

In `Searcher`, replace the `find` field with two new ones:

```zig
    options: Options,
    /// Decides whether a line matches; refers to `pattern`.
    matcher: Matcher,
    printer: Printer,
    file_arena: std.heap.ArenaAllocator,
```

`init` creates them. The matcher must refer to the Searcher's own copy of the pattern, so that copy comes first:

```zig
    ) Allocator.Error!Searcher {
        // Copy the pattern so the Searcher doesn't depend on the lifetime
        // of the caller's memory.
        const owned_pattern = try gpa.dupe(u8, pattern);
        const matcher: Matcher = .init(owned_pattern, options.ignore_case, options.wildcard);
        return .{
            .gpa = gpa,
            .io = io,
            .pattern = owned_pattern,
            .options = options,
            .matcher = matcher,
            .printer = .init(options, matcher),
            .file_arena = .init(gpa),
            .stdout = stdout,
            .stderr = stderr,
        };
    }
```

In `addPath`, the glob check now calls the function through the `match` namespace:

```zig
                    if (self.options.glob) |glob| {
                        if (!match.wildcardMatch(glob, entry.basename)) continue;
                    }
```

At the end of `searchFile`, the `-l`/`-c` printing becomes one call:

```zig
        try self.stats.record(self.gpa, name, matches);
        try self.printer.fileDone(self.stdout, name, matches);
    }
```

And `searchReader` gets shorter:

```zig
    /// Reads `reader` line by line, hands every selected line to the
    /// printer, and returns how many lines were selected, or null if the
    /// input looks binary. A line is selected when it matches, or, with -v,
    /// when it doesn't. Stops early at the -m limit.
    fn searchReader(self: *Searcher, reader: *Io.Reader, path: []const u8) (error{ReadFailed} || Allocator.Error || Io.Writer.Error)!?usize {
        if (try looksBinary(reader)) return null;

        // For -l, one selected line answers the question. Comparing a
        // tagged union with an enum literal compares the active tag.
        const limit: usize = if (self.printer == .files) 1 else self.options.max_count orelse std.math.maxInt(usize);

        var long_line: Io.Writer.Allocating = .init(self.file_arena.allocator());
        var matches: usize = 0;
        var line_number: usize = 1;
        while (matches < limit) : (line_number += 1) {
            const line = try nextLine(reader, &long_line) orelse break;
            const found = self.matcher.find(line) != null;
            if (found == self.options.invert) continue;
            matches += 1;
            try self.printer.line(self.stdout, path, line_number, line);
        }
        return matches;
    }
```

`self.printer == .files` compares a tagged union with an enum literal: it checks the active tag and ignores the payload. Handy when you only need to know *which* variant you have.

### `src/cli.zig`

Add the option after `invert`:

```zig
    invert: bool = false,
    wildcard: bool = false,
    line_numbers: bool = false,
```

its short name:

```zig
        .invert = 'v',
        .wildcard = 'W',
```

and its description:

```zig
        .invert = "select lines that do NOT match",
        .wildcard = "PATTERN is a wildcard (* and ?) matched against the whole line",
```

### Checkpoint

```console
$ zig build
$ ./zig-out/bin/seek -W '*fox*' testdata
testdata/notes/log.txt:2024-01-01 saw a fox near the barn
testdata/notes/log.txt:2024-01-03 fox tracks in the snow
testdata/notes/todo.md:- feed the fox
testdata/poem.txt:The quick brown fox
$ ./zig-out/bin/seek -W 'the*' testdata/poem.txt
testdata/poem.txt:the dog just sleeps.
$ ./zig-out/bin/seek -W -i 'the*' testdata/poem.txt
testdata/poem.txt:The quick brown fox
testdata/poem.txt:the dog just sleeps.
$ ./zig-out/bin/seek -W -n '*fox' testdata
testdata/notes/todo.md:2:- feed the fox
testdata/poem.txt:1:The quick brown fox
```

Quote wildcard patterns, or the shell expands `*` itself. Unlike a plain PATTERN, `-W` matches the **whole line**, so a pattern without `*` must equal the line:

```console
$ ./zig-out/bin/seek -W fox testdata; echo "exit $?"
exit 1
```

A pattern that starts with `-` looks like a flag; put it after `--`:

```console
$ ./zig-out/bin/seek -W '- f*' testdata/notes/todo.md
seek: unknown flag '- f*'
usage: seek [OPTIONS] PATTERN [PATH ...]
$ ./zig-out/bin/seek -W -- '- f*' testdata/notes/todo.md
testdata/notes/todo.md:- feed the fox
testdata/notes/todo.md:- fix the fence
```

Highlighting now asks the matcher, so `-W` colors the whole line, and the old modes still work (`cat -v` shows the escape codes):

```console
$ ./zig-out/bin/seek -W --color always 'the*' testdata/poem.txt | cat -v
testdata/poem.txt:^[[1;31mthe dog just sleeps.^[[0m
$ ./zig-out/bin/seek --color always -i -n fox testdata/poem.txt | cat -v
testdata/poem.txt:1:The quick brown ^[[1;31mfox^[[0m
testdata/poem.txt:3:A ^[[1;31mFox^[[0m is quick and clever;
testdata/poem.txt:5:^[[1;31mFox^[[0mes everywhere!
$ ./zig-out/bin/seek -c -W '*e*' testdata
testdata/notes/log.txt:3
testdata/notes/todo.md:3
testdata/poem.txt:5
```

`-W -i` folds ASCII letters only, like `-i`.

### Exhaustiveness at work

Add a fourth variant to `Matcher`, after `wildcard`:

```zig
    /// The line starts with the pattern.
    prefix: []const u8,
```

and build:

```text
src/match.zig:39:9: error: switch must handle all possibilities
        switch (matcher) {
        ^~~~~~
src/match.zig:22:5: note: unhandled enumeration value: 'prefix'
    prefix: []const u8,
    ^~~~~~
```

The compiler points at the `switch` that needs a new prong. The function-pointer design had no such safety net. Remove the variant again (or finish it: that is Exercise 2 in another form).

The complete project at this point is in `project/ch14/`.

## Summary

- Zig has no interface keyword. Four patterns cover it: tagged unions, vtable fat pointers, an interface field with `@fieldParentPtr`, and `anytype`.
- A **tagged union** is a closed set: data inline, dispatch by `switch`, and every `switch` checked when you add a variant. `inline else` writes uniform dispatch for you.
- A **fat pointer** (`ptr: *anyopaque` + `vtable: *const VTable`) is an open set, like `std.mem.Allocator`. The object lives elsewhere and must outlive the pointer.
- An **interface field** puts shared data (like a buffer) in the interface. Implementations recover their struct with `@fieldParentPtr`. Never copy the interface out of its parent.
- **`anytype`** is a compile-time interface with direct calls, for types known at compile time.
- `std.Io.Writer` keeps the buffer in the interface, so most writes never call the vtable. A custom writer needs only `drain`: consume the buffer, then `data`, with the last slice repeated `splat` times.
- Test output code with `Writer.Allocating` or `Writer.fixed`.
- seek's matching is a `Matcher` union and its output modes are a `Printer` union. `-W` matches whole lines against wildcards, specialized at compile time for `-i`.

## Exercises

1. **A counting writer.** Write `LineCounter`, a `std.Io.Writer` implementation that discards everything but counts the bytes and newlines written. Make sure `splat` is counted correctly: test it with `w.splatByteAll('\n', 100)`.

   <details><summary>Solution</summary>

   ```zig
   const std = @import("std");
   const Writer = std.Io.Writer;

   /// A writer that throws bytes away but counts them, and the lines.
   const LineCounter = struct {
       bytes: usize = 0,
       lines: usize = 0,
       writer: Writer,

       fn init(buffer: []u8) LineCounter {
           return .{ .writer = .{ .vtable = &.{ .drain = drain }, .buffer = buffer } };
       }

       fn drain(w: *Writer, data: []const []const u8, splat: usize) Writer.Error!usize {
           const self: *LineCounter = @alignCast(@fieldParentPtr("writer", w));
           self.count(w.buffer[0..w.end], 1);
           w.end = 0;
           var consumed: usize = 0;
           for (data[0 .. data.len - 1]) |bytes| {
               self.count(bytes, 1);
               consumed += bytes.len;
           }
           const pattern = data[data.len - 1];
           self.count(pattern, splat);
           return consumed + pattern.len * splat;
       }

       fn count(self: *LineCounter, bytes: []const u8, times: usize) void {
           self.bytes += bytes.len * times;
           self.lines += std.mem.countScalar(u8, bytes, '\n') * times;
       }
   };

   pub fn main() !void {
       var buffer: [8]u8 = undefined;
       var counter: LineCounter = .init(&buffer);
       const w = &counter.writer;
       for (0..3) |i| try w.print("line {d}\n", .{i});
       try w.splatByteAll('\n', 100);
       try w.flush();
       std.debug.print("{d} bytes, {d} lines\n", .{ counter.bytes, counter.lines });
   }
   ```

   ```console
   $ zig run line_counter.zig
   121 bytes, 103 lines
   ```

   Three 7-byte lines plus 100 newlines. `splatByteAll` hands `drain` a one-byte slice with `splat` set to the count, so `count` multiplies instead of looping.

   </details>

2. **Whole-line matching.** Add `-x`/`--line` to seek: the line must equal PATTERN exactly (with `-i`, ignoring ASCII case). Make it a new `Matcher` variant.

   <details><summary>Solution</summary>

   In `cli.zig`, add `line: bool = false,` after `wildcard`, `.line = 'x',` to `shorts`, and `.line = "the whole line must equal PATTERN",` to `descriptions`.

   In `match.zig`, add the variant. `Wildcard` already holds "a pattern and an `ignore_case` flag", so reuse it:

   ```zig
       wildcard: Wildcard,
       /// The whole line equals the pattern (-x).
       whole_line: Wildcard,
   ```

   The build now fails at `switch (matcher)` in `find`. Add the prong:

   ```zig
               .whole_line => |w| {
                   const equal = if (w.ignore_case)
                       std.ascii.eqlIgnoreCase(line, w.pattern)
                   else
                       std.mem.eql(u8, line, w.pattern);
                   return if (equal) .{ .start = 0, .end = line.len } else null;
               },
   ```

   Extend `init`:

   ```zig
       pub fn init(pattern: []const u8, ignore_case: bool, wildcard: bool, whole_line: bool) Matcher {
           if (wildcard) return .{ .wildcard = .{ .pattern = pattern, .ignore_case = ignore_case } };
           if (whole_line) return .{ .whole_line = .{ .pattern = pattern, .ignore_case = ignore_case } };
   ```

   and pass `options.line` in `Searcher.init`:

   ```zig
           const matcher: Matcher = .init(owned_pattern, options.ignore_case, options.wildcard, options.line);
   ```

   Nothing else in `output.zig` or `search.zig` changes: highlighting and printing only see `find`.

   ```console
   $ ./zig-out/bin/seek -x 'Foxes everywhere!' testdata
   testdata/poem.txt:Foxes everywhere!
   $ ./zig-out/bin/seek -x -i 'FOXES EVERYWHERE!' testdata
   testdata/poem.txt:Foxes everywhere!
   $ ./zig-out/bin/seek -x -c -- '- feed the fox' testdata
   testdata/notes/log.txt:0
   testdata/notes/todo.md:1
   testdata/poem.txt:0
   ```

   </details>

3. **Adding an operation.** Add a `perimeter` function to the tagged-union `Shape` in `shape_union.zig`, and then to the vtable `Shape` in `shape_vtable.zig`. In each version, how many places did you have to change? What would change if you instead added a `Triangle` type?

   <details><summary>Solution</summary>

   In the tagged union, one new function with one `switch`:

   ```zig
       fn perimeter(shape: Shape) f64 {
           return switch (shape) {
               .circle => |c| 2 * std.math.pi * c.radius,
               .rect => |r| 2 * (r.width + r.height),
               .square => |side| 4 * side,
           };
       }
   ```

   In the vtable version, add `perimeter: *const fn (ptr: *anyopaque) f64,` to `VTable`. Every implementation breaks until it provides one:

   ```text
   shape_vtable.zig:37:35: error: missing struct field: perimeter
   shape_vtable.zig:57:35: error: missing struct field: perimeter
   ```

   So you also write `Circle.perimeter` and `Rect.perimeter`, add them to both vtables, and add a `perimeter` wrapper to `Shape`. If the implementations lived in other people's code, you would break all of it.

   Adding a `Triangle` is the mirror image. The vtable version needs only a new struct with its own vtable. The tagged union needs a new variant and a new prong in every `switch` on `Shape`. A closed set makes new operations cheap; an open set makes new types cheap. Pick the pattern by which you expect to add more often.

   </details>

4. **Which pattern?** For each case, pick a pattern from this chapter and say why.
   1. The tokens of a small expression parser: numbers, identifiers, `+`, `*`, `(`, `)`.
   2. A plugin interface for a text editor that third parties implement in their own packages.
   3. A `sum` function that should work on slices of any integer or float type.
   4. A logging library where the user picks a destination (a file, the terminal, or memory) at run time, and wants writes to be fast.

   <details><summary>Solution</summary>

   1. **Tagged union.** The parser owns every token kind, some carry data (a number's value, an identifier's text), and the compiler catches a token you forgot to handle.
   2. **Vtable** (fat pointer). The set of implementations is open and known only at run time.
   3. **`comptime T: type`** (or `anytype`). The type is known at compile time, so there's no reason to pay for run-time dispatch.
   4. **An interface field with a buffer**, like `std.Io.Writer`, or better, just accept a `*std.Io.Writer`. The destination is chosen at run time, and the buffer in the interface makes most writes a `memcpy`.

   </details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-14--interfaces-and-polymorphism)
