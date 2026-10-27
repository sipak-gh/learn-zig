# Chapter 6 — Arrays, Slices, and Pointers

Zig gives you direct control over memory, so you must know where data lives and how you refer to
it. This chapter covers **arrays**, **slices**, and the **pointer** kinds (single-item, many-item,
optional, sentinel-terminated): how types track length and `const`-ness, how bounds checks catch
bugs, and why returning a pointer to stack memory is wrong. Then `seek` searches many files.
Previous: [Chapter 5](05-errors-and-optionals.md). Next: [Chapter 7](07-structs-enums-unions.md).

## Arrays

An array is a fixed number of same-type values, side by side. The length is part of the type:
`[3]u8` and `[4]u8` differ.

`examples/ch06/arrays.zig`

```zig
const std = @import("std");

pub fn main() void {
    // An array has a length that is part of its type: [3]u8.
    const primes = [3]u8{ 2, 3, 5 };
    // `_` lets the compiler count the elements for you.
    const vowels = [_]u8{ 'a', 'e', 'i', 'o', 'u' };
    // A result type lets you drop the type from the literal.
    const origin: [2]i32 = .{ 0, 0 };
    // @splat fills every element with one value.
    const zeros: [4]u16 = @splat(0);

    std.debug.print("primes: {any}, len {d}\n", .{ primes, primes.len });
    std.debug.print("vowels: {s}, len {d}\n", .{ &vowels, vowels.len });
    std.debug.print("origin: {any}, zeros: {any}\n", .{ origin, zeros });
    std.debug.print("type of primes: {s}\n", .{@typeName(@TypeOf(primes))});

    // Arrays are values. Assignment copies every element.
    var copy = primes;
    copy[0] = 99;
    std.debug.print("primes[0] = {d}, copy[0] = {d}\n", .{ primes[0], copy[0] });

    // Loop by value, or by pointer to change elements in place.
    var squares: [5]u32 = undefined;
    for (&squares, 0..) |*sq, i| sq.* = @intCast(i * i);
    var sum: u32 = 0;
    for (squares) |sq| sum += sq;
    std.debug.print("squares: {any}, sum {d}\n", .{ squares, sum });

    // Arrays of the same type compare with std.mem.eql (on slices), not ==.
    std.debug.print("equal: {}\n", .{std.mem.eql(u8, &primes, &[_]u8{ 2, 3, 5 })});
}
```

```console
$ zig run examples/ch06/arrays.zig
primes: { 2, 3, 5 }, len 3
vowels: aeiou, len 5
origin: { 0, 0 }, zeros: { 0, 0, 0, 0 }
type of primes: [3]u8
primes[0] = 2, copy[0] = 99
squares: { 0, 1, 4, 9, 16 }, sum 30
equal: true
```

- `[N]T{...}` states the length; `[_]T{...}` counts it for you.
- `.len` is the length, known at compile time for arrays.
- **Arrays are values.** Assigning or passing one copies it (the compiler may skip the copy
  invisibly).
- `@splat(v)` fills an array with `v`. `undefined` leaves it unset; write every element before
  reading it.
- `for (&squares, 0..) |*sq, i|` loops over a *pointer* to the array, so `sq` is a `*u32` and
  `sq.* = ...` writes into the array. Pointers are explained below.

`==` doesn't work on arrays. Use `std.mem.eql`:

```console
$ zig run array_eq.zig
array_eq.zig:6:33: error: operator == not allowed for type '[3]u8'
    std.debug.print("{}\n", .{a == b});
                              ~~^~~~
```

A constant index past the end is a compile error:

```console
$ zig run bad_index.zig
bad_index.zig:5:39: error: index 5 outside array of length 3
    std.debug.print("{d}\n", .{primes[5]});
                                      ^
```

(This chapter trims the `referenced by:` lines after compiler errors.)

## Building arrays at compile time: `++`, `@splat`, and nesting

`++` joins two arrays whose lengths are known at compile time (the result's length goes in its type).
String literals are arrays, so `++` joins them too.

A multidimensional array is an array of arrays: `[3][3]u8` is 3 rows of `[3]u8`.

`examples/ch06/array_ops.zig`

```zig
const std = @import("std");

// `++` joins arrays whose lengths are known at compile time.
const head = [_]u8{ 1, 2 };
const tail = [_]u8{ 3, 4, 5 };
const joined = head ++ tail; // [5]u8

// String literals are arrays too, so `++` joins them.
const greeting = "hello" ++ ", " ++ "world";

// A 3×3 grid is an array of 3 arrays of 3 bytes.
const Grid = [3][3]u8;

pub fn main() void {
    std.debug.print("joined: {any} ({d} items)\n", .{ joined, joined.len });
    std.debug.print("greeting: {s}\n", .{greeting});

    // Every row, then every cell, starts as '.'.
    var grid: Grid = @splat(@splat('.'));
    grid[1][1] = 'X';
    grid[0][2] = 'O';
    for (grid) |row| std.debug.print("{s}\n", .{&row});

    // Destructuring pulls the elements of an array into separate constants.
    const x, const y, _ = tail;
    std.debug.print("x={d} y={d}\n", .{ x, y });
}
```

```console
$ zig run examples/ch06/array_ops.zig
joined: { 1, 2, 3, 4, 5 } (5 items)
greeting: hello, world
..O
.X.
...
x=3 y=4
```

- `const Grid = [3][3]u8;` names a type. Types are values in Zig ([Chapter 12](12-comptime.md)).
- `@splat(@splat('.'))`: the inner `@splat` makes a row of `'.'`; the outer one repeats that row.
- `const x, const y, _ = tail;` destructures; `_` skips an element.

`++` needs compile-time-known *lengths*. A runtime slice has no length in its type, so `++` can't
join it. You need an allocator for that ([Chapter 8](08-memory-and-allocators.md)):

```console
$ zig run runtime_concat.zig
runtime_concat.zig:6:32: error: unable to resolve comptime value
    std.debug.print("{s}\n", .{name ++ "!"});
                               ^~~~
runtime_concat.zig:6:32: note: slice being concatenated must be comptime-known
```

> **Older Zig had `**`.** Zig 0.16 and earlier repeated arrays with `[_]u8{0} ** 10`. Zig 0.17
> removed it in favor of `@splat`; the old form no longer parses:
>
> ```console
> $ zig run repeat.zig
> repeat.zig:4:31: error: binary operator '*' has whitespace on one side, but not the other
>     const dashes = [_]u8{'-'} ** 10;
>                               ^
> ```
>
> Write `const dashes: [10]u8 = @splat('-');` instead.

## Slices

For "some number of items" known only at run time (part of an array, a line, the arguments), use
a **slice**. A slice `[]T` is a pointer to the first item plus a length. It doesn't own the items;
it *views* memory that lives elsewhere.

`examples/ch06/slices.zig`

```zig
const std = @import("std");

pub fn main() void {
    var numbers = [_]i32{ 10, 20, 30, 40, 50 };

    // A runtime index makes a slice: a pointer plus a length.
    var start: usize = 1;
    _ = &start; // pretend `start` could change, so it is runtime-known
    const middle = numbers[start..4];
    std.debug.print("middle = {any}, len {d}\n", .{ middle, middle.len });

    // A slice points into the array. Writing through it changes the array.
    middle[0] = 99;
    std.debug.print("numbers = {any}\n", .{numbers});

    // Omit the end to slice to the end. Slicing a slice gives another view.
    const rest = numbers[start..];
    const last_two = rest[rest.len - 2 ..];
    std.debug.print("rest = {any}, last_two = {any}\n", .{ rest, last_two });

    // `&array` is a pointer to the whole array; it coerces to a slice.
    const all: []const i32 = &numbers;
    std.debug.print("sum = {d}\n", .{sum(all)});
    std.debug.print("sum of middle = {d}\n", .{sum(middle)});

    // A slice is two machine words, whatever its length.
    std.debug.print("@sizeOf([]i32) = {d}, @sizeOf([5]i32) = {d}\n", .{ @sizeOf([]i32), @sizeOf([5]i32) });

    // Comptime-known bounds give a pointer to an array, with the length in the type.
    const first_two = numbers[0..2];
    std.debug.print("type of numbers[0..2]: {s}\n", .{@typeName(@TypeOf(first_two))});
    std.debug.print("type of numbers[start..4]: {s}\n", .{@typeName(@TypeOf(middle))});

    // Empty slices are fine.
    const none = numbers[2..2];
    std.debug.print("none.len = {d}\n", .{none.len});
}

/// Works for any number of items: arrays, parts of arrays, heap memory.
fn sum(items: []const i32) i64 {
    var total: i64 = 0;
    for (items) |n| total += n;
    return total;
}
```

```console
$ zig run examples/ch06/slices.zig
middle = { 20, 30, 40 }, len 3
numbers = { 10, 99, 30, 40, 50 }
rest = { 99, 30, 40, 50 }, last_two = { 40, 50 }
sum = 229
sum of middle = 169
@sizeOf([]i32) = 16, @sizeOf([5]i32) = 20
type of numbers[0..2]: *[2]i32
type of numbers[start..4]: []i32
none.len = 0
```

The slicing rules:

| Expression | Meaning |
|---|---|
| `a[s..e]` | items `s` up to, not including, `e` (length `e - s`) |
| `a[s..]` | from `s` to the end |
| `a[s..][0..n]` | `n` items starting at `s` ("slice by length") |
| `&a` | pointer to the whole array; coerces to a slice |

- **Slicing never copies.** `middle[0] = 99` changed `numbers[1]`.
- A slice is 16 bytes on a 64-bit machine (pointer + length), however many items it covers.
- **Compile-time bounds give an array pointer.** `numbers[0..2]` is `*[2]i32`, a pointer to exactly
  2 items; it coerces to `[]i32` where a slice is expected. A runtime bound (`start`) gives a real
  slice, `[]i32`.
- `_ = &start;` makes the compiler treat `start` as a variable. Without it, a `var` that never
  changes is a compile error ([Chapter 2](02-values-and-types.md)).
- A `[]const T` parameter accepts arrays, parts of arrays, and heap memory alike, so slices are the
  normal way to pass "many items".

### `[]T` versus `[]const T`

`[]const T` means "I only read through this slice". `[]T` means "I may write through it".

- `[]T` coerces to `[]const T` (giving up write access is always safe). Never the reverse.
- Slicing a `const` array gives `const` items; slicing a `var` array gives mutable items.

Passing a `const` array to a function that writes is a compile error:

```zig
fn zero(items: []u8) void {
    for (items) |*item| item.* = 0;
}

pub fn main() void {
    const data = [_]u8{ 1, 2, 3 };
    zero(&data);
}
```

```console
$ zig run const_slice.zig
const_slice.zig:7:10: error: expected type '[]u8', found '*const [3]u8'
    zero(&data);
         ^~~~~
const_slice.zig:7:10: note: cast discards const qualifier
const_slice.zig:1:16: note: parameter type declared here
fn zero(items: []u8) void {
               ^~~~
```

Rule of thumb: take `[]const T` unless the function must write. That's why strings are `[]const u8`.

## Bounds checking

In safe builds (Debug and ReleaseSafe), every index and slice is checked at run time. Going out of
bounds panics instead of reading random memory.

`examples/ch06/bounds_panic.zig`

```zig
const std = @import("std");

pub fn main() void {
    const letters = [_]u8{ 'a', 'b', 'c' };
    var i: usize = 0;
    // Bug: `<=` walks one step past the end.
    while (i <= letters.len) : (i += 1) {
        std.debug.print("{c}\n", .{letters[i]});
    }
}
```

```console
$ zig run examples/ch06/bounds_panic.zig
a
b
c
thread 266348 panic: index out of bounds: index 3, len 3
…/examples/ch06/bounds_panic.zig:8:43: 0x11e93cc in main (bounds_panic.zig)
        std.debug.print("{c}\n", .{letters[i]});
                                          ^
…/lib/std/start.zig:788:64: 0x11e8cab in callMain (std.zig)
    if (fn_info.param_types.len == 0) return wrapMain(root.main());
                                                               ^
…/lib/std/start.zig:248:5: 0x11e86e1 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
Aborted (core dumped)
```

(Thread IDs, addresses and paths differ on your machine.)

- The panic names the bad index and the length; the trace points to the line.
- Slicing is checked too: `a[2..9]` on a 5-item array panics the same way.
- ReleaseFast and ReleaseSmall drop these checks for speed. Out-of-bounds access there is *illegal
  behavior*: anything can happen. [Chapter 19](19-low-level.md) covers build modes and safety.

Bounds checks are cheap and stop buffer overflows, a whole class of security bugs.

## Single-item pointers: `*T`

A pointer holds the address of a value. `&x` takes the address; `p.*` reads or writes the value.

`examples/ch06/pointers.zig`

```zig
const std = @import("std");

/// Takes a pointer so it can change the caller's variable.
fn increment(counter: *u32) void {
    counter.* += 1;
}

/// A const pointer can read but not write.
fn show(label: []const u8, value: *const u32) void {
    std.debug.print("{s}: {d}\n", .{ label, value.* });
}

pub fn main() void {
    var hits: u32 = 0;
    const p = &hits; // p: *u32 — the address of `hits`
    p.* = 10; // write through the pointer
    increment(p);
    increment(&hits);
    show("hits", &hits); // *u32 coerces to *const u32

    // The address of a `const` gives a `*const` pointer.
    const limit: u32 = 100;
    const lp = &limit;
    std.debug.print("type of &hits: {s}, type of &limit: {s}\n", .{
        @typeName(@TypeOf(p)),
        @typeName(@TypeOf(lp)),
    });

    // A pointer to an element of an array.
    var scores = [_]u32{ 7, 8, 9 };
    const second = &scores[1];
    second.* *= 10;
    std.debug.print("scores = {any}\n", .{scores});

    // A pointer to a whole array can be indexed and has a length.
    const all = &scores;
    all[0] = 1;
    std.debug.print("all.len = {d}, scores[0] = {d}\n", .{ all.len, scores[0] });

    // `{*}` prints the address. It changes from run to run.
    std.debug.print("p = {*}\n", .{p});
}
```

```console
$ zig run examples/ch06/pointers.zig
hits: 12
type of &hits: *u32, type of &limit: *const u32
scores = { 7, 80, 9 }
all.len = 3, scores[0] = 1
p = u32@7ffc11323738
```

(The address on the last line differs on every run.)

- `*T` points to exactly one `T`; a `*const T` can't change it.
- `const p = &hits;` — `p` always points to `hits`, but `hits` is mutable. `const` on the left is
  about the variable; `const` inside the type (`*const u32`) is about the value pointed to.
- Parameters are constants ([Chapter 4](04-functions.md)). To let a function change your variable,
  pass a pointer. Methods change their struct the same way (next chapter).
- `*[N]T` (pointer to an array) supports indexing and `.len`, and coerces to a slice.

Writing through a `*const` is a compile error:

```zig
pub fn main() void {
    const x: i32 = 1;
    const p = &x;
    p.* = 2;
}
```

```console
$ zig run const_ptr.zig
const_ptr.zig:4:6: error: cannot assign to constant
    p.* = 2;
    ~^~
```

`*T` has no pointer arithmetic, and there's no C-style `->`: `p.field` works directly on a pointer
to a struct ([Chapter 7](07-structs-enums-unions.md)).

## Optional pointers: `?*T`

A Zig pointer is **never null**. If "no value" is possible, say so with `?*T`:

```console
$ zig run null_ptr.zig
null_ptr.zig:2:21: error: expected type '*i32', found '@TypeOf(null)'
    const p: *i32 = null;
                    ^~~~
```

Unwrap it with the tools from [Chapter 5](05-errors-and-optionals.md): `if (p) |ptr|`, `orelse`,
and `.?`.

`examples/ch06/optional_pointers.zig`

```zig
const std = @import("std");

/// Returns a pointer to the first even number, or null if there is none.
fn firstEven(numbers: []u32) ?*u32 {
    for (numbers) |*n| {
        if (n.* % 2 == 0) return n;
    }
    return null;
}

pub fn main() void {
    var numbers = [_]u32{ 3, 5, 8, 11, 12 };

    // Unwrap with `if`: inside the block `p` is a plain *u32.
    if (firstEven(&numbers)) |p| {
        p.* = 0; // change the array through the pointer
    }
    std.debug.print("numbers = {any}\n", .{numbers});

    var odd = [_]u32{ 1, 3 };
    const found = firstEven(&odd);
    std.debug.print("found in odd: {any}\n", .{found});

    // `.?` unwraps when you know it can't be null (it panics if it is).
    const zero = firstEven(&numbers).?;
    std.debug.print("zero.* = {d}\n", .{zero.*});

    // `orelse` supplies a fallback.
    var fallback: u32 = 42;
    const target = firstEven(&odd) orelse &fallback;
    std.debug.print("target.* = {d}\n", .{target.*});

    // Null is stored as address 0, so an optional pointer costs nothing extra.
    std.debug.print("@sizeOf(*u32) = {d}, @sizeOf(?*u32) = {d}\n", .{ @sizeOf(*u32), @sizeOf(?*u32) });
}
```

```console
$ zig run examples/ch06/optional_pointers.zig
numbers = { 3, 5, 0, 11, 12 }
found in odd: null
zero.* = 0
target.* = 42
@sizeOf(*u32) = 8, @sizeOf(?*u32) = 8
```

- `|*n|` captures a pointer to each item, so the function can return an address inside the
  caller's array.
- You must handle `null` before dereferencing. The "billion-dollar mistake" of null pointers becomes
  a type error.
- `?*T` is the same size as `*T`. Address 0 means `null`, as in C, but the type says so.

## Many-item pointers: `[*]T`

`[*]T` points to an unknown number of items. It supports indexing and pointer arithmetic but has
**no length and no bounds checks**. A slice is a `[*]T` plus a length; `slice.ptr` is the pointer
part.

`examples/ch06/many_item.zig`

```zig
const std = @import("std");

pub fn main() void {
    var data = [_]u8{ 'z', 'i', 'g', '!' };
    const slice: []u8 = &data;

    // A slice is made of a many-item pointer (`.ptr`) and a length (`.len`).
    const many: [*]u8 = slice.ptr;
    std.debug.print("type of slice.ptr: {s}\n", .{@typeName(@TypeOf(many))});

    // You can index a many-item pointer, but it has no length and no
    // bounds check: many[100] would compile and read garbage.
    many[0] = 'Z';
    std.debug.print("many[0..3] = {s}\n", .{many[0..3]});

    // Pointer arithmetic moves the pointer by whole elements.
    const from_second = many + 1;
    std.debug.print("from_second[0] = {c}\n", .{from_second[0]});

    // Give it a length again by slicing: now it is safe to use.
    const back: []u8 = many[0..data.len];
    std.debug.print("back = {s}, len {d}\n", .{ back, back.len });
}
```

```console
$ zig run examples/ch06/many_item.zig
type of slice.ptr: [*]u8
many[0..3] = Zig
from_second[0] = i
back = Zig!, len 4
```

You'll rarely write `[*]T`. It exists for C interop (C's `char *` doesn't say how many items) and
low-level code. Turn it into a slice as soon as you know the length.

## Pointer and slice types at a glance

| Type | Points to | Length | Index | Typical use |
|---|---|---|---|---|
| `*T` | one `T` | — | no | change a caller's variable, refer to a struct |
| `*[N]T` | `N` items | `N`, in the type | yes | `&array`, `a[0..2]` with constant bounds |
| `[]T` | many items | runtime `.len` | yes, checked | the normal "many items" type |
| `[*]T` | many items | unknown | yes, unchecked | C interop, low-level code |
| `[:0]T` | many items + a 0 after them | runtime `.len` | yes, checked | strings that C also needs |
| `[*:0]T` | items up to the first 0 | unknown | yes | C strings (`char *`) |
| `?*T` | one `T` or nothing | — | no | "maybe a pointer" |

Add `const` after the brackets (`[]const u8`, `*const T`, `[*:0]const u8`) for read-only items.

## Sentinel-terminated arrays, slices, and pointers

C ends a string with a 0 byte. Zig puts that in the type: `[N:0]u8`, `[:0]u8` and `[*:0]u8` promise
a `0` right after the last item. The value after the colon is the **sentinel**.

`examples/ch06/sentinels.zig`

```zig
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    // A string literal is a pointer to a constant, 0-terminated array.
    const hello = "hello";
    std.debug.print("type of \"hello\": {s}\n", .{@typeName(@TypeOf(hello))});
    std.debug.print("len {d}, byte after the end: {d}\n", .{ hello.len, hello[hello.len] });

    // It coerces to every common string type.
    const as_slice: []const u8 = hello; // length, no terminator promised
    const as_zslice: [:0]const u8 = hello; // length and a 0 at [len]
    const as_cstr: [*:0]const u8 = hello; // no length: ends at the first 0
    std.debug.print("{s} {s} {s}\n", .{ as_slice, as_zslice, as_cstr });

    // std.mem.span finds the 0 and gives back a slice with a length.
    const back = std.mem.span(as_cstr);
    std.debug.print("span: {s} ({s}, len {d})\n", .{ back, @typeName(@TypeOf(back)), back.len });

    // You can build sentinel-terminated arrays yourself.
    const digits = [_:0]u8{ '1', '2', '3' };
    std.debug.print("type of digits: {s}\n", .{@typeName(@TypeOf(digits))});

    // Command-line arguments come from the OS as 0-terminated strings.
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    std.debug.print("type of args: {s}\n", .{@typeName(@TypeOf(args))});
    for (args[1..]) |arg| {
        const plain: []const u8 = arg; // drop the sentinel: always allowed
        std.debug.print("arg {s} has {d} bytes\n", .{ plain, plain.len });
    }
}
```

```console
$ zig run examples/ch06/sentinels.zig -- fox poem.txt
type of "hello": *const [5:0]u8
len 5, byte after the end: 0
hello hello hello
span: hello ([:0]const u8, len 5)
type of digits: [3:0]u8
type of args: []const [:0]const u8
arg fox has 3 bytes
arg poem.txt has 8 bytes
```

- **A string literal is `*const [N:0]u8`**: a pointer to a constant array of `N` bytes plus a `0`.
  `"hello"` is `*const [5:0]u8`. `.len` doesn't count the `0`, but you may read it at index `len`.
- That type coerces to `[]const u8`, `[:0]const u8`, and `[*:0]const u8`, so a literal fits anywhere
  a string is expected.
- `[*:0]const u8` is a C string: no length, "read until the 0". `std.mem.span` walks to the 0 and
  returns a proper slice.
- `zig run file.zig -- args` passes the arguments after `--` to the program.
- The arguments are `[]const [:0]const u8`: a slice of 0-terminated strings. Dropping the sentinel
  (`[:0]const u8` → `[]const u8`) is always allowed. The reverse isn't: a plain slice doesn't promise
  a 0 after its end.

```console
$ zig run cstr.zig
cstr.zig:3:34: error: expected type '[*:0]const u8', found '[]const u8'
    const c_str: [*:0]const u8 = greeting;
                                 ^~~~~~~~
```

Prefer `[]const u8`. Use sentinel types only where a C API or the OS needs the 0.

## Alignment and `@ptrCast`

Every type has an **alignment**: its address must be a multiple of it (a `u32` usually needs 4).
`@alignOf(T)` gives the value. Pointer types carry it, so the compiler knows when a conversion is
safe.

`@ptrCast` makes a pointer point to a different type. It's the sharpest tool here: the compiler
can't check that the bytes make sense.

`examples/ch06/alignment.zig`

```zig
const std = @import("std");

pub fn main() void {
    std.debug.print("@alignOf(u8)  = {d}\n", .{@alignOf(u8)});
    std.debug.print("@alignOf(u32) = {d}\n", .{@alignOf(u32)});
    std.debug.print("@alignOf(u64) = {d}\n", .{@alignOf(u64)});

    // Four bytes, placed at an address that is valid for a u32.
    const bytes: [4]u8 align(4) = .{ 0x78, 0x56, 0x34, 0x12 };

    // @ptrCast reinterprets the memory behind a pointer. The result depends
    // on the CPU's byte order, so this prints 12345678 on little-endian CPUs.
    const word: *const u32 = @ptrCast(&bytes);
    std.debug.print("word = {x}\n", .{word.*});

    // @bitCast does the same for values, with no pointers involved.
    const same: u32 = @bitCast(bytes);
    std.debug.print("same = {x}\n", .{same});
}
```

```console
$ zig run examples/ch06/alignment.zig
@alignOf(u8)  = 1
@alignOf(u32) = 4
@alignOf(u64) = 8
word = 12345678
same = 12345678
```

- `align(4)` puts the array at a multiple of 4, so the `*const u32` view is valid. Without it,
  `@ptrCast` would give a misaligned pointer: illegal behavior.
- `@alignCast` asserts that a pointer is more aligned than its type says (safety-checked).
- Prefer `@bitCast` (values) or `std.mem` helpers. Use `@ptrCast` only for raw memory or C.
  [Chapter 19](19-low-level.md) goes deeper.

## Stack memory lifetime: the dangling pointer

Locals live in the function's **stack frame**. After the function returns, the next call reuses
that memory, so a pointer or slice into it *dangles*: it points to someone else's memory.

Zig catches the simplest case:

```zig
fn counter() *u32 {
    var count: u32 = 0;
    count += 1;
    return &count;
}
```

```console
$ zig run return_local.zig
return_local.zig:4:13: error: returning address of expired local variable 'count'
    return &count;
            ^~~~~
return_local.zig:2:9: note: declared runtime-known here
    var count: u32 = 0;
        ^~~~~
```

It can't catch every case. Returning a slice of a local buffer compiles, and prints garbage:

`examples/ch06/dangling.zig`

```zig
const std = @import("std");

/// BUG: returns a slice of `buf`, which lives in this function's stack
/// frame. The memory is reused as soon as the function returns.
fn reversedBad(text: []const u8) []const u8 {
    var buf: [32]u8 = undefined;
    for (text, 0..) |c, i| buf[text.len - 1 - i] = c;
    return buf[0..text.len];
}

/// Fixed: the caller owns the buffer, so the result lives as long as the
/// caller's buffer does.
fn reversed(buf: []u8, text: []const u8) []u8 {
    const out = buf[0..text.len];
    for (text, 0..) |c, i| out[text.len - 1 - i] = c;
    return out;
}

pub fn main() void {
    const bad = reversedBad("stressed");
    std.debug.print("bad:  {s}\n", .{bad});

    var buf: [32]u8 = undefined;
    const good = reversed(&buf, "stressed");
    std.debug.print("good: {s}\n", .{good});
}
```

```console
$ zig run examples/ch06/dangling.zig
bad:  ��������
good: desserts
```

In Debug and ReleaseSafe, Zig fills `undefined` memory with the byte `0xaa`. `std.debug.print`
reused the old stack frame, so `bad` shows eight `0xaa` bytes, drawn as `�`. Other code or build
modes might show the right answer by luck, or crash.

Three ways to return data that outlives the function:

1. **The caller passes a buffer** (`reversed` above). `std` uses this pattern a lot.
2. **Return a value, not a pointer.** A `[32]u8` array is copied out.
3. **Allocate on the heap** with an allocator from the caller
   ([Chapter 8](08-memory-and-allocators.md)).

String literals and file-level `const`s are safe: they live in read-only data for the whole run.

## Building seek: patterns and paths

`seek` searches one file so far. Now it accepts any number of PATHs:

```
seek [OPTIONS] PATTERN [PATH ...]
```

`args` is `[]const [:0]const u8`. `args[1]` is PATTERN; everything after it is a PATH. So the paths
are just `args[2..]`: no copying, no new memory.

Two new questions:

- **What if one file fails?** Report it and keep going.
- **What's the exit status?** Like `grep`: 2 if *any* error happened (even with matches), else 0 if
  anything matched, else 1.

Open `src/main.zig`. In `run`, replace everything from the `const pattern = argAt(args, 1) ...` line
to the end of the function with this:

```zig
    const pattern = argAt(args, 1) orelse return error.MissingPattern;
    // Everything after PATTERN is a PATH. Slicing doesn't copy anything:
    // `paths` is a pointer and a length into the memory of `args`.
    const paths = args[2..];
    if (paths.len == 0) return error.MissingPath;

    var matched_any = false;
    var had_error = false;
    for (paths) |path| {
        // Read the whole file into memory. The arena frees it when seek exits.
        const contents = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(max_file_size)) catch |err| {
            // One unreadable file must not stop the search: report and go on.
            try reportError(stdout, stderr, path, err);
            had_error = true;
            continue;
        };
        if (try searchText(stdout, path, pattern, contents) > 0) matched_any = true;
    }

    if (had_error) return exit_trouble;
    return if (matched_any) exit_ok else exit_no_match;
}
```

The `const pattern = ...` line is unchanged; the old `const path = ...` line and the single-file
code after it are gone.

- `args[2..]` is safe when `args.len` is exactly 2: it's an empty slice. (`args.len < 2` already
  returned `MissingPattern`.)
- `path` is `[:0]const u8`; it coerces to the `[]const u8` parameters of `searchText` and
  `reportError`.
- `catch |err| { ...; continue; }` handles the error and moves to the next path.

Now add `reportError` right after `run`, before `argAt`:

```zig
/// Reports a problem with `path` on stderr. Both writers are buffered, so we
/// flush stdout first and stderr right after: that way messages appear in the
/// order things happened, even when both streams go to the same terminal.
fn reportError(stdout: *std.Io.Writer, stderr: *std.Io.Writer, path: []const u8, err: anyerror) std.Io.Writer.Error!void {
    try stdout.flush();
    try stderr.print("seek: {s}: {t}\n", .{ path, err });
    try stderr.flush();
}
```

- Writers are passed by pointer (`*std.Io.Writer`) because writing changes them. A copy would have
  its own buffer position and lose data.
- `err: anyerror` accepts any error. `readFileAlloc` can fail in many ways; we print only the name.
- **Why flush stdout first?** Both writers buffer bytes until they flush. Without it, an error for
  the *second* file could appear before the matches from the *first*. Try it: in `reportError`,
  replace `try stdout.flush();` with `_ = stdout;` (deleting the line gives "unused function
  parameter"), rebuild, and run:

  ```console
  $ ./zig-out/bin/seek dog testdata/poem.txt nope.txt
  seek: nope.txt: FileNotFound
  testdata/poem.txt:jumps over the lazy dog.
  testdata/poem.txt:the dog just sleeps.
  ```

  The error jumped ahead. Put the flush back.

### Checkpoint

```console
$ zig build
$ ./zig-out/bin/seek fox testdata/poem.txt testdata/notes/todo.md testdata/notes/log.txt
testdata/poem.txt:The quick brown fox
testdata/notes/todo.md:- feed the fox
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
$ ./zig-out/bin/seek zebra testdata/poem.txt nope.txt
seek: nope.txt: FileNotFound
$ echo $?
2
$ ./zig-out/bin/seek fox
usage: seek [OPTIONS] PATTERN [PATH ...]
$ echo $?
2
```

The second command exits 2 despite matches: an error wins, as in `grep`. A directory is still an
error (`seek: testdata/notes: IsDir`) until [Chapter 11](11-files-and-io.md).

The complete project at this point is in `project/ch06/`.

## Summary

- `[N]T` is an array: length in the type, stored inline, copied on assignment. `[_]T{...}` counts
  for you; `@splat(v)` fills; `.len` is the length.
- `++` joins arrays with compile-time-known lengths. `**` is gone in 0.17; use `@splat`.
- `[]T` is a slice: pointer + runtime length. `a[s..e]`, `a[s..]`, `a[s..][0..n]` are views, not
  copies. Constant bounds give `*[N]T`.
- `[]const T` is read-only; `[]T` coerces to it, never the reverse.
- Indexing and slicing are bounds-checked in Debug and ReleaseSafe.
- `*T` points to one item: `&x` takes an address, `p.*` dereferences. `*const T` is read-only.
- Pointers can't be null. Use `?*T` and unwrap it; it costs no extra space.
- `[*]T` has no length and no checks: for C and low-level code.
- Sentinel types (`[N:0]T`, `[:0]T`, `[*:0]T`) promise a terminator. String literals are
  `*const [N:0]u8` and coerce to `[]const u8`.
- `@alignOf`, `align(n)`, `@ptrCast` are for raw memory; prefer `@bitCast`.
- Never return a pointer or slice into a local. Take a caller's buffer, return a value, or allocate.

## Exercises

1. Write `fn reverseInPlace(items: []u8) void` that reverses a slice by swapping from both ends.
   Test it on a copy of `"stressed"` (hint: `var word = "stressed".*;` copies the literal into a
   mutable array) and on an empty array.

<details><summary>Solution</summary>

```zig
const std = @import("std");

fn reverseInPlace(items: []u8) void {
    if (items.len < 2) return;
    var i: usize = 0;
    var j: usize = items.len - 1;
    while (i < j) : ({
        i += 1;
        j -= 1;
    }) {
        const tmp = items[i];
        items[i] = items[j];
        items[j] = tmp;
    }
}

pub fn main() void {
    var word = "stressed".*; // copy the literal into a mutable array
    reverseInPlace(&word);
    std.debug.print("{s}\n", .{&word});

    var empty = [_]u8{};
    reverseInPlace(&empty);
    std.debug.print("empty ok\n", .{});
}
```

```console
$ zig run reverse.zig
desserts
empty ok
```

The early return matters: for an empty slice, `items.len - 1` would overflow.

</details>

2. Write `fn largest(items: []i32) ?*i32` that returns a pointer to the largest item (the first one
   if there are ties), or `null` for an empty slice. Use it to set the largest item of
   `{ 12, 31, 7, 31, 25 }` to 0.

<details><summary>Solution</summary>

```zig
const std = @import("std");

fn largest(items: []i32) ?*i32 {
    if (items.len == 0) return null;
    var best = &items[0];
    for (items[1..]) |*item| {
        if (item.* > best.*) best = item;
    }
    return best;
}

pub fn main() void {
    var temps = [_]i32{ 12, 31, 7, 31, 25 };
    if (largest(&temps)) |p| p.* = 0;
    std.debug.print("{any}\n", .{temps});

    var none = [_]i32{};
    std.debug.print("{any}\n", .{largest(&none)});
}
```

```console
$ zig run largest.zig
{ 12, 0, 7, 31, 25 }
null
```

</details>

3. Write `fn cLen(s: [*:0]const u8) usize` that counts bytes up to the sentinel, without
   `std.mem.span`. Check it against `std.mem.span(s).len`.

<details><summary>Solution</summary>

```zig
const std = @import("std");

fn cLen(s: [*:0]const u8) usize {
    var n: usize = 0;
    while (s[n] != 0) n += 1;
    return n;
}

pub fn main() void {
    const hello: [*:0]const u8 = "hello";
    std.debug.print("{d} {d}\n", .{ cLen(hello), std.mem.span(hello).len });
    std.debug.print("{d}\n", .{cLen("")});
}
```

```console
$ zig run clen.zig
5 5
0
```

This is how C's `strlen` works, and why it's slow for long strings: it reads every byte. A slice
already knows its length.

</details>

4. `seek fox testdata/poem.txt testdata/poem.txt` searches the file twice. Make `seek` skip a path
   that appeared earlier on the command line. Hint: `paths[0..i]` is the paths before the current
   one. (The real `seek` searches duplicates, like `grep`; this is just practice.)

<details><summary>Solution</summary>

Change the loop header in `run` and add a helper:

```zig
    for (paths, 0..) |path, i| {
        if (seenBefore(paths[0..i], path)) continue;
        // ... the loop body stays the same ...
    }
```

```zig
/// Reports whether `path` appears in `earlier`.
fn seenBefore(earlier: []const [:0]const u8, path: []const u8) bool {
    for (earlier) |other| {
        if (std.mem.eql(u8, other, path)) return true;
    }
    return false;
}
```

```console
$ ./zig-out/bin/seek fox testdata/poem.txt testdata/poem.txt testdata/notes/log.txt testdata/poem.txt
testdata/poem.txt:The quick brown fox
testdata/notes/log.txt:2024-01-01 saw a fox near the barn
testdata/notes/log.txt:2024-01-03 fox tracks in the snow
```

For `i == 0`, `paths[0..0]` is empty, so the first path is always searched.

</details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-6--arrays-slices-and-pointers)
