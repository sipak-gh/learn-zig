# Chapter 19 — Safety, Undefined Behavior, and Talking to C

Zig is a low-level language: you control memory layout, bits, and machine instructions, and you can
call C directly. This chapter starts with *illegal behavior*: bugs Zig catches in safe builds that
become undefined behavior in fast ones. Then come bit builtins, shifts, packed structs, alignment,
SIMD vectors, and calling C and being called from it. `seek` gets a vectorized scan for binary
files, a benchmark to prove it's faster, and `--color auto` finally detects a terminal.
[Chapter 18](18-build-system.md) covered the build system, used here to compile C and run the
benchmark. [Chapter 20](20-design-and-next-steps.md) closes the course.

## Illegal behavior

Some operations have no sensible result: adding past a type's maximum, reading index 5 of a
3-element array, unwrapping a `null`. Zig calls these **illegal behavior**. What happens depends on
the build mode ([Chapter 18](18-build-system.md)):

| Mode | Illegal behavior that the compiler can see | At run time |
|------|-------------------------------------------|-------------|
| `debug`, `safe` | compile error | **safety-checked**: the program panics with a message and a stack trace |
| `fast`, `small` | compile error | **undefined behavior**: the compiler assumed it can't happen |

You've seen overflow ([Chapter 2](02-values-and-types.md)) and bounds checks
([Chapter 6](06-arrays-slices-pointers.md)). Here's overflow with a value the compiler can't know,
from the command line:

`examples/ch19/overflow_panic.zig`

```zig
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    // The value comes from the command line, so the compiler can't check
    // the addition at compile time.
    const stock: u8 = try std.fmt.parseInt(u8, args[1], 10);
    const total: u8 = stock + 10;
    std.debug.print("{d} + 10 = {d}\n", .{ stock, total });
}
```

```console
$ zig run examples/ch19/overflow_panic.zig -- 100
100 + 10 = 110
$ zig run examples/ch19/overflow_panic.zig -- 250; echo "exit $?"
thread 301312 panic: integer overflow
…/examples/ch19/overflow_panic.zig:8:29: 0x11e8934 in main (overflow_panic.zig)
    const total: u8 = stock + 10;
                            ^
…/lib/std/start.zig:827:30: 0x11e93a8 in callMain (std.zig)
    return wrapMain(root.main(.{
                             ^
…/lib/std/start.zig:248:5: 0x11e86e1 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
Aborted (core dumped)
exit 134
```

(Thread IDs, addresses, and paths differ.) A panic prints the message and a stack trace to stderr
and aborts with `SIGABRT`, which the shell reports as status 134. `safe` mode gives the same
message and line.

The same program in `fast` mode:

```console
$ zig run -O fast examples/ch19/overflow_panic.zig -- 250
250 + 10 = 004
$ zig run -O fast examples/ch19/overflow_panic.zig -- 246
246 + 10 = 000
$ zig run -O small examples/ch19/overflow_panic.zig -- 250
250 + 10 = 4
```

`004`? The sum wrapped to 4, but that's not the strange part. Overflow is illegal, so the optimizer
concluded that `stock + 10` can't overflow, that `total` is at least 10, and that it always prints
at least two digits. Both conclusions follow from a fact that turned out false. That's
**undefined behavior**: not "some arbitrary number" but "the program's logic no longer holds
anywhere the bad value reaches". The result can change with the mode (`small` printed `4`), the
compiler version, or unrelated edits.

If the compiler can see the overflow, it's a compile error in every mode:

```text
ct.zig:5:29: error: overflow of integer type 'u8' with value '260'
    const total: u8 = stock + 10;
                      ~~~~~~^~~~
```

(That's with `const stock: u8 = 250;` instead of the command-line value.)

### The catalog

`examples/ch19/illegal_panic.zig` commits one kind of illegal behavior per case. Each uses `n`, a
number that's 4 at run time but unknown to the compiler:

`examples/ch19/illegal_panic.zig`

```zig
//! Each case does something illegal. Run with a case name as the argument.

const std = @import("std");

const Shape = union(enum) { circle: f32, square: f32 };
const Color = enum(u8) { red, green, blue };

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const case = args[1];
    // A runtime number the compiler can't see through.
    const n: usize = args.len + 2; // 4 when there is one argument

    if (std.mem.eql(u8, case, "bounds")) {
        const items = [_]u8{ 1, 2, 3 };
        const i = n + 1;
        std.debug.print("{d}\n", .{items[i]});
    } else if (std.mem.eql(u8, case, "null")) {
        const maybe: ?usize = if (n > 100) n else null;
        std.debug.print("{d}\n", .{maybe.?});
    } else if (std.mem.eql(u8, case, "cast")) {
        const big: u32 = @intCast(n * 100);
        const small: u8 = @intCast(big);
        std.debug.print("{d}\n", .{small});
    } else if (std.mem.eql(u8, case, "unreachable")) {
        if (n != 0) unreachable;
    } else if (std.mem.eql(u8, case, "divide")) {
        const zero = n - 4;
        std.debug.print("{d}\n", .{100 / zero});
    } else if (std.mem.eql(u8, case, "enum")) {
        const color: Color = @fromBackingInt(@intCast(n));
        std.debug.print("{t}\n", .{color});
    } else if (std.mem.eql(u8, case, "union")) {
        const shape: Shape = if (n > 0) .{ .circle = 1 } else .{ .square = 2 };
        std.debug.print("{d}\n", .{shape.square});
    } else if (std.mem.eql(u8, case, "slice")) {
        const text = "hello";
        std.debug.print("{s}\n", .{text[n..2]});
    }
}
```

The first line of each panic (stack traces as above):

```console
$ zig run examples/ch19/illegal_panic.zig -- bounds
thread 302144 panic: index out of bounds: index 5, len 3
$ zig run examples/ch19/illegal_panic.zig -- null
thread 302178 panic: attempt to use null value
$ zig run examples/ch19/illegal_panic.zig -- cast
thread 302183 panic: integer does not fit in destination type
$ zig run examples/ch19/illegal_panic.zig -- unreachable
thread 302185 panic: reached unreachable code
$ zig run examples/ch19/illegal_panic.zig -- divide
thread 302189 panic: division by zero
$ zig run examples/ch19/illegal_panic.zig -- enum
thread 302191 panic: invalid enum value
$ zig run examples/ch19/illegal_panic.zig -- union
thread 302193 panic: access of union field 'square' while field 'circle' is active
$ zig run examples/ch19/illegal_panic.zig -- slice
thread 302195 panic: start index 4 is larger than end index 2
```

| Illegal behavior | Example | Safe alternative |
|------------------|---------|------------------|
| Integer overflow | `a + b` too big | `+%` `+|` `std.math.add`, a wider type |
| Index out of bounds | `items[5]` with length 3 | check `i < items.len`, iterate with `for` |
| Unwrapping `null` | `maybe.?` | `orelse`, `if (maybe) \|x\|` |
| Integer cast that doesn't fit | `@intCast(1000)` to `u8` | `std.math.cast(u8, x)` returns `?u8` |
| Reaching `unreachable` | `else => unreachable` | return an error |
| Division by zero | `100 / zero` | check first |
| Invalid enum value | `@fromBackingInt(4)` as a `Color` | `std.enums.fromInt(Color, x)` returns `?Color` |
| Wrong union field | `shape.square` when it's a circle | `switch` on the tag |
| Bad slice bounds | `text[4..2]` | check the bounds |
| Shift that loses bits | `@shlExact` (below) | `<<`, `std.math.shl` |

The checks are cheap: a compare and a branch almost never taken. That's why `safe` is a good
default for releases.

In `fast` mode the program prints nonsense and exits with status 0:

```console
$ zig run -O fast examples/ch19/illegal_panic.zig -- bounds; echo "exit $?"
0
exit 0
$ zig run -O fast examples/ch19/illegal_panic.zig -- null; echo "exit $?"
4
exit 0
```

`items[5]` read whatever was in memory past the array. `maybe.?` returned the payload slot of a
`null` optional. You'd never notice either in testing.

**Not everything is checked.** Some illegal behavior has no cheap check, even in Debug:

- **Reading `undefined` memory.** `debug` and `safe` builds fill it with `0xaa` bytes, so a `u32`
  reads as `0xaaaaaaaa`, recognizable in a debugger, but nothing panics.
- **Use after free.** `std.heap.SafeAllocator` (what `init.gpa` is in `debug` and `safe` builds)
  panics on double frees and reports leaks ([Chapter 8](08-memory-and-allocators.md)), but reading
  through a dangling pointer isn't caught.
- **Data races** between threads ([Chapter 15](15-concurrency.md)).
- **Pointer casts to the wrong type** with `@ptrCast`, and violating `noalias`.

The langref's [Illegal Behavior](https://ziglang.org/documentation/0.17.0/#Illegal-Behavior)
section lists every kind.

### Checked, wrapping, saturating

[Chapter 2](02-values-and-types.md) introduced the operators that say what you want when a result
doesn't fit. One more: `std.math.add` and friends turn overflow into an error.

`examples/ch19/arithmetic.zig`

```zig
const std = @import("std");

pub fn main() void {
    const a: u8 = 250;
    const b: u8 = 10;

    // Wrapping: modulo 2^8, like C's unsigned arithmetic.
    std.debug.print("wrapping:   {d}\n", .{a +% b});
    // Saturating: stops at the type's limits.
    std.debug.print("saturating: {d}\n", .{a +| b});
    std.debug.print("saturating: {d}\n", .{@as(u8, 5) -| 10});

    // Checked: overflow becomes an error you handle.
    if (std.math.add(u8, a, b)) |sum| {
        std.debug.print("checked:    {d}\n", .{sum});
    } else |err| {
        std.debug.print("checked:    {t}\n", .{err});
    }

    // The builtin returns the wrapped result and an overflow bit.
    const sum, const overflowed = @addWithOverflow(a, b);
    std.debug.print("builtin:    {d}, overflow bit {d}\n", .{ sum, overflowed });

    // Signed integers too: the minimum has no positive counterpart.
    const min: i8 = std.math.minInt(i8);
    std.debug.print("-%({d}) = {d}\n", .{ min, -%min });
}
```

```console
$ zig run examples/ch19/arithmetic.zig
wrapping:   4
saturating: 255
saturating: 0
checked:    Overflow
builtin:    4, overflow bit 1
-%(-128) = -128
```

Use `std.math.add`, `sub`, `mul`, and `cast` for values from outside the program: sizes from a
file header, counts from the network. `std.fmt.parseInt`, used by `seek`'s flag parser, checks the
same way and returns `error.Overflow` for a number that doesn't fit.

### `@setRuntimeSafety`

`@setRuntimeSafety(false)` turns the checks off for the rest of the current scope (function or
block), even in `debug` and `safe` builds; `@setRuntimeSafety(true)` turns them on, even in `fast`
builds.

```zig
/// Sums bytes. The caller promises the total fits in a u32 (at most
/// 16 MiB of input), so the overflow check is wasted work here.
fn sum(bytes: []const u8) u32 {
    @setRuntimeSafety(false);
    var total: u32 = 0;
    for (bytes) |b| total += b;
    return total;
}
```

Use it rarely: in a measured hot loop, with a comment saying why the illegal case can't happen. If
the promise breaks, you get undefined behavior even in Debug. The usual pattern: build with `safe`
and turn safety off only where a profiler says it matters.

## Bits

Systems code often treats integers as bags of bits: flags, hash functions, file formats, network
protocols. Zig's bit builtins compile to single CPU instructions where the CPU has them.

`examples/ch19/bits.zig`

```zig
const std = @import("std");

pub fn main() void {
    const x: u8 = 0b0010_1100;

    std.debug.print("x           = 0b{b:0>8} ({d})\n", .{ x, x });
    std.debug.print("@popCount   = {d}\n", .{@popCount(x)}); // bits set
    std.debug.print("@clz        = {d}\n", .{@clz(x)}); // leading zeros
    std.debug.print("@ctz        = {d}\n", .{@ctz(x)}); // trailing zeros
    std.debug.print("@bitReverse = 0b{b:0>8}\n", .{@bitReverse(x)});
    std.debug.print("@byteSwap   = 0x{x}\n", .{@byteSwap(@as(u32, 0x11223344))});

    // Reinterpret the bits of one type as another of the same size.
    const one: f32 = 1.0;
    std.debug.print("1.0 as bits = 0x{x}\n", .{@as(u32, @bitCast(one))});

    // The shift amount of a u32 must fit in a u5 (0..31):
    // std.math.Log2Int(u32) is u5.
    var amount: std.math.Log2Int(u32) = 0;
    amount += 31;
    std.debug.print("1 << {d}     = 0x{x}\n", .{ amount, @as(u32, 1) << amount });

    // @shlExact asserts that no 1 bits are shifted out.
    std.debug.print("@shlExact   = {d}\n", .{@shlExact(@as(u8, 0b0001_0000), 3)});

    // std.math.shl accepts any amount; bits shifted too far give 0.
    std.debug.print("math.shl    = {d}\n", .{std.math.shl(u8, 1, 9)});

    // Reading a little-endian integer from bytes, as a file format would.
    const bytes = [_]u8{ 0x78, 0x56, 0x34, 0x12 };
    std.debug.print("readInt     = 0x{x}\n", .{std.mem.readInt(u32, &bytes, .little)});
}
```

```console
$ zig run examples/ch19/bits.zig
x           = 0b00101100 (44)
@popCount   = 3
@clz        = 2
@ctz        = 2
@bitReverse = 0b00110100
@byteSwap   = 0x44332211
1.0 as bits = 0x3f800000
1 << 31     = 0x80000000
@shlExact   = 128
math.shl    = 0
readInt     = 0x12345678
```

- `@popCount`, `@clz`, `@ctz` count set bits, leading zeros, and trailing zeros. `@ctz` finds the
  lowest set bit; `@bitSizeOf(T) - @clz(x)` is the number of bits needed to hold `x`.
- `@byteSwap` reverses byte order (little- ↔ big-endian). `std.mem.readInt` and `writeInt` do it
  for you when reading bytes.
- `@bitCast` reinterprets bits as another type of the same size, without conversion: `1.0` is
  `0x3f800000` in IEEE 754. `@intFromFloat`, by contrast, converts the *value*.

### Shifts

In C, shifting a 32-bit integer by 32 or more is undefined behavior. Zig rules it out with types:
the right side of `<<` and `>>` must be `std.math.Log2Int(T)`, the smallest unsigned type holding
`0` to `bits - 1`. For a `u32` that's `u5`. A runtime `u32` amount doesn't compile:

```text
sh1.zig:4:47: error: expected type 'u5', found 'u32'
    std.debug.print("{d}\n", .{@as(u32, 1) << amount});
                                              ^~~~~~
sh1.zig:4:47: note: unsigned 5-bit int cannot represent all possible unsigned 32-bit values
```

Nor does a constant that's too big: `@as(u8, 1) << 9` gives `error: type 'u3' cannot represent
integer value '9'`. Convert with `@intCast` (checked) when you know the amount is in range, or use
`std.math.shl`/`shr`, which accept any amount.

`<<` silently drops bits that move past the top. `@shlExact` promises no 1 bits are lost, checked
like overflow. `<<|` saturates; `@shlWithOverflow` reports. With a runtime amount of 5:

```console
$ zig run sh2.zig
thread 302925 panic: left shift overflowed bits
```

## Memory layout

### Packed structs

A normal `struct` lets the compiler choose field order and padding. An `extern struct` follows the
target's C ABI rules, so C code can share it. A **`packed struct`** puts fields at exact bit
positions inside one integer, first field in the lowest bits. Its *backing integer* can be named:
`packed struct(u9)` must add up to exactly 9 bits.

`examples/ch19/packed.zig`

```zig
const std = @import("std");

/// File permission bits, as in `chmod`: one bool per bit, lowest first.
const Mode = packed struct(u9) {
    other_x: bool = false,
    other_w: bool = false,
    other_r: bool = false,
    group_x: bool = false,
    group_w: bool = false,
    group_r: bool = false,
    owner_x: bool = false,
    owner_w: bool = false,
    owner_r: bool = false,
};

/// The same three fields with the three layouts.
const Auto = struct { a: bool, b: u32, c: bool }; // the compiler may reorder
const C = extern struct { a: bool, b: u32, c: bool }; // C's rules, in order
const Bits = packed struct { a: bool, b: u30, c: bool }; // bits of one integer

pub fn main() void {
    const mode: Mode = .{ .owner_r = true, .owner_w = true, .group_r = true, .other_r = true };
    std.debug.print("mode as octal: {o}\n", .{@as(u9, @bitCast(mode))});

    const exec: Mode = @bitCast(@as(u9, 0o755));
    std.debug.print("0o755 owner_x={} group_w={}\n", .{ exec.owner_x, exec.group_w });

    std.debug.print("auto: {d} bytes, extern: {d} bytes, packed: {d} bytes\n", .{
        @sizeOf(Auto), @sizeOf(C), @sizeOf(Bits),
    });
    std.debug.print("offset of b: extern byte {d}, packed bit {d}\n", .{
        @offsetOf(C, "b"), @bitOffsetOf(Bits, "b"),
    });

    // Alignment: the address of a value is a multiple of its alignment.
    std.debug.print("align of u8, u32, u64: {d} {d} {d}\n", .{ @alignOf(u8), @alignOf(u32), @alignOf(u64) });
    var buffer: [64]u8 align(16) = undefined;
    std.debug.print("buffer address % 16 = {d}\n", .{@intFromPtr(&buffer) % 16});
}
```

```console
$ zig run examples/ch19/packed.zig
mode as octal: 644
0o755 owner_x=true group_w=false
auto: 8 bytes, extern: 12 bytes, packed: 4 bytes
offset of b: extern byte 4, packed bit 1
align of u8, u32, u64: 1 4 8
buffer address % 16 = 0
```

`Mode` is the nine permission bits of a Unix file. `@bitCast` converts it to and from a `u9`, and
each bit has a name: no masks, shifts, or `#define`s. In C it would be `mode & 0o100` and a
comment.

The three layouts: `Auto` takes 8 bytes because the compiler put the two `bool`s together; `C`
takes 12 because C's rules keep the order and pad `b` to a 4-byte boundary; `Bits` fits in 32
bits. Use `packed` for bit flags and hardware registers, `extern` for structs shared with C, and
plain `struct` for everything else.

### Alignment

Every type has an **alignment**: its address must be a multiple of `@alignOf(T)`; a `u32` sits at
an address divisible by 4. Pointer types carry alignment: `*u32` means "aligned to 4",
`*align(1) u32` means "may be anywhere", as a packed field or byte buffer requires. `align(16)` on
a variable raises its alignment, for SIMD loads or a hardware buffer. To turn a pointer with weaker
alignment into one with stronger (from `*anyopaque` or `[*]u8` to `*u32`), use `@alignCast`, which
checks the address in safe builds. The C callback below uses it.

### `volatile`

The optimizer never removes, merges, or reorders loads and stores through a `*volatile T`. That's
for memory-mapped I/O, where a "memory" address is really a device register. Not for threads: use
atomics ([Chapter 15](15-concurrency.md)).

## SIMD with `@Vector`

Modern CPUs can apply one operation to 16, 32, or 64 bytes at once with **SIMD** (single
instruction, multiple data). `@Vector(len, T)` is a value of `len` lanes of `T`, and ordinary
operators work on all lanes at once:

`examples/ch19/simd.zig`

```zig
const std = @import("std");

pub fn main() void {
    const V = @Vector(4, i32);
    const a: V = .{ 1, 2, 3, 4 };
    const b: V = .{ 10, 20, 30, 40 };

    // Operators work lane by lane.
    std.debug.print("a + b  = {any}\n", .{a + b});
    std.debug.print("a * b  = {any}\n", .{a * b});

    // @splat fills every lane with one value.
    const twos: V = @splat(2);
    std.debug.print("a * 2  = {any}\n", .{a * twos});

    // Comparisons give a vector of bools; @reduce combines the lanes.
    const big = b > @as(V, @splat(15));
    std.debug.print("b > 15 = {any}\n", .{big});
    std.debug.print("any: {}, all: {}\n", .{ @reduce(.Or, big), @reduce(.And, big) });
    std.debug.print("sum of a = {d}\n", .{@reduce(.Add, a)});

    // Lanes can be read like array elements, and arrays coerce to vectors.
    const array: [4]i32 = .{ 5, 6, 7, 8 };
    const from_array: V = array;
    std.debug.print("lane 2 = {d}\n", .{from_array[2]});

    // @select picks each lane from one of two vectors.
    std.debug.print("select = {any}\n", .{@select(i32, big, a, b)});

    std.debug.print("suggested u8 lanes on this CPU: {?d}\n", .{std.simd.suggestVectorLength(u8)});
}
```

```console
$ zig run examples/ch19/simd.zig
a + b  = { 11, 22, 33, 44 }
a * b  = { 10, 40, 90, 160 }
a * 2  = { 2, 4, 6, 8 }
b > 15 = { false, true, true, true }
any: true, all: false
sum of a = 10
lane 2 = 7
select = { 10, 2, 3, 4 }
suggested u8 lanes on this CPU: 32
```

- The length must be comptime-known. Any length works; the compiler splits or pads to fit the
  hardware, and falls back to scalar code on a CPU without SIMD.
- `std.simd.suggestVectorLength(T)` returns the target CPU's natural lane count as a
  `?comptime_int`: 32 bytes with AVX2 (this machine), 16 with SSE2 or ARM NEON, `null` with no
  vector unit. Yours may differ.
- Comparisons give `@Vector(len, bool)`. `@reduce(.Or, …)` asks "any lane true?", `.And` "all?",
  `.Add` sums the lanes.
- An array of the same length coerces to a vector; that's how slice data gets in.

`std.mem.findScalar`, `std.mem.eql`, and others are already vectorized. Write your own when the
standard library lacks the loop you need.

## Talking to C

Zig speaks C at the binary level: it can call C functions, be called by C, share structs, and
compile C code, with no wrapper layer or runtime cost.

### Calling C functions

An `extern` function declaration says "this exists elsewhere; link to it". With `extern "c"`, it's
in the C library. Types must match C's: `c_int` is `int`, `c_long` is `long`, and so on; C strings
are `[*:0]const u8`.

`examples/ch19/c_extern.zig`

```zig
//! Calling C's standard library directly. Run with `zig run -lc`.

const std = @import("std");

// Declarations of functions that live in libc. The types are C's:
// c_int is C's `int`, and [*:0]const u8 is a NUL-terminated `const char *`.
extern "c" fn abs(x: c_int) c_int;
extern "c" fn strlen(s: [*:0]const u8) usize;
extern "c" fn atoi(s: [*:0]const u8) c_int;
extern "c" fn qsort(
    base: *anyopaque,
    count: usize,
    size: usize,
    compare: *const fn (?*const anyopaque, ?*const anyopaque) callconv(.c) c_int,
) void;

/// C calls this function, so it must use C's calling convention.
fn compareInts(a: ?*const anyopaque, b: ?*const anyopaque) callconv(.c) c_int {
    const x: *const c_int = @ptrCast(@alignCast(a.?));
    const y: *const c_int = @ptrCast(@alignCast(b.?));
    return switch (std.math.order(x.*, y.*)) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

pub fn main() void {
    std.debug.print("abs(-7) = {d}\n", .{abs(-7)});
    std.debug.print("strlen(\"hello\") = {d}\n", .{strlen("hello")});
    std.debug.print("atoi(\"42abc\") = {d}\n", .{atoi("42abc")});

    var numbers = [_]c_int{ 42, -3, 17, 0, 8 };
    qsort(&numbers, numbers.len, @sizeOf(c_int), compareInts);
    std.debug.print("qsort: {any}\n", .{numbers});

    // std.c has declarations for much of libc already.
    std.debug.print("getpid() > 0: {}\n", .{std.c.getpid() > 0});
}
```

`-lc` links the C library:

```console
$ zig run -lc examples/ch19/c_extern.zig
abs(-7) = 7
strlen("hello") = 5
atoi("42abc") = 42
qsort: { -3, 0, 8, 17, 42 }
getpid() > 0: true
$ zig run examples/ch19/c_extern.zig
examples/ch19/c_extern.zig:7:8: error: dependency on libc must be explicitly specified in the build command
extern "c" fn abs(x: c_int) c_int;
       ^~~
…
```

Zig programs don't need libc: `seek` talks to the OS directly through `std.Io`. When you want it,
say so: `-lc` on the command line or `.link_libc = true` in `createModule`.

A function C calls back, like `qsort`'s comparator, needs **`callconv(.c)`**: Zig's own calling
convention is unspecified and may pass arguments differently. The convention is part of the
pointer type, so forgetting it is a compile error, not a crash:

```text
examples/ch19/c_extern.zig:34:50: error: expected type '*const fn (T, T) callconv(.c) c_int', found '*const fn (T, T) c_int'
    qsort(&numbers, numbers.len, @sizeOf(c_int), compareInts);
                                                 ^~~~~~~~~~~
examples/ch19/c_extern.zig:34:50: note: T = ?*const anyopaque
…
examples/ch19/c_extern.zig:34:50: note: calling convention 'auto' cannot cast into calling convention 'x86_64_sysv'
```

`?*const anyopaque` is C's `const void *`: a possibly-null pointer to something of unknown type.
`@ptrCast` changes the pointee type; `@alignCast` checks that the address suits a `c_int`.

A shorter comparator is tempting: `return @intFromBool(x.* > y.*) - @intFromBool(x.* < y.*);`. It
panics with "integer overflow" inside `qsort`, because `@intFromBool` returns a `u1` and `0 - 1`
doesn't fit. The stack trace runs from `compareInts` through glibc's `msort.c` back to `main`:
safety checks work across the language boundary.

`std.c` already declares much of libc (`std.c.getpid`, `std.c.malloc`, `std.c.printf`, …), and
`std.heap.c_allocator` is an `Allocator` using `malloc` and `free`.

### Building C code with Zig

For your own C code, let the build system compile it. A tiny project with a C function in
`src/add.c`, declared in `src/add.h`:

```c
// src/add.h
#ifndef ADD_H
#define ADD_H

int add(int a, int b);

#endif
```

```c
// src/add.c
#include "add.h"

int add(int a, int b) {
    return a + b;
}
```

Calling it from Zig needs Zig declarations of the header's contents. **translate-c** reads C
headers and writes the equivalent Zig. A header `src/c.h` collects what we want:

```c
// src/c.h
#include <string.h>
#include "add.h"
```

`build.zig`

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Translate the C header into a Zig module.
    const translate = b.addTranslateC(.{
        .root_source_file = b.path("src/c.h"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "cdemo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "c", .module = translate.createModule() },
            },
        }),
    });
    // Compile the C file with Zig's built-in C compiler and link it in.
    exe.root_module.addCSourceFile(.{ .file = b.path("src/add.c"), .flags = &.{"-std=c99"} });
    exe.root_module.addIncludePath(b.path("src"));
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    b.step("run", "Run the demo").dependOn(&run.step);
}
```

`src/main.zig`

```zig
const std = @import("std");
// The module made by translate-c from src/c.h: Zig declarations for
// everything the header declares.
const c = @import("c");

pub fn main() void {
    std.debug.print("add(2, 3) = {d}\n", .{c.add(2, 3)});
    std.debug.print("strlen = {d}\n", .{c.strlen("hello")});
}
```

```console
$ zig build run
add(2, 3) = 5
strlen = 5
```

(With a `build.zig.zon` as usual.) The generated module has lines like `pub extern fn add(a:
c_int, b: c_int) c_int;` and `pub extern fn strlen(__s: [*c]const u8) usize;`. `[*c]` is a *C
pointer*: possibly null, pointing to one item or many. It exists only for translated code; convert
to a proper Zig pointer type as soon as you can.

> **Version note.** Older code imports C headers with `const c = @cImport(@cInclude("…"));`.
> **`@cImport` is gone in 0.17** (`error: invalid builtin function: '@cImport'`); translating C
> moved to the build system. `b.addTranslateC` works in 0.17 but is itself deprecated in favor of
> the official `translate-c` package (`zig fetch --save
> git+https://codeberg.org/ziglang/translate-c#zig-0.17.x`): the same implementation, with more
> options. Check the [release notes](https://ziglang.org/download/0.17.0/release-notes.html) when
> you set up a real C project.

### Being called from C: `export`

`export` makes a Zig function callable from C, with the C calling convention and an unmangled
symbol name.

```zig
// mathlib.zig
// `export` gives the function C's calling convention and an unmangled
// symbol name, so C code can call it.
export fn zig_twice(x: c_int) c_int {
    return x * 2;
}
```

```c
// use.c
#include <stdio.h>

int zig_twice(int x);

int main(void) {
    printf("zig_twice(21) = %d\n", zig_twice(21));
    return 0;
}
```

```console
$ zig build-lib mathlib.zig
$ ls
libmathlib.a  mathlib.zig  use.c
$ zig cc -o use use.c libmathlib.a && ./use
zig_twice(21) = 42
```

`zig build-lib` makes a static library (`-dynamic` for a shared one) that any C toolchain can link.
In `build.zig`, use `b.addLibrary(.{ .linkage = .static, … })`. That's how projects replace C code
with Zig piece by piece.

## Building seek: vectorized binary detection and a terminal check

Two changes:

- Binary-file detection ([Chapter 11](11-files-and-io.md)) looks for a zero byte in the first 8
  KiB of each file. A new `src/bytes.zig` does it with `@Vector`, and `zig build bench` measures it
  against a plain loop and the standard library.
- `--color auto`, the default, behaved like `never` until now. Now it means "color when standard
  output is a terminal".

### `src/bytes.zig`

Create `src/bytes.zig` with scalar and vector versions of the same check:

`src/bytes.zig`

```zig
//! Byte-scanning helpers: a plain loop and a SIMD version of the same check.

const std = @import("std");
const testing = std.testing;

/// How many bytes one vector holds on the target CPU (for example 16 with
/// SSE2, 32 with AVX2), or null if the CPU has no suitable vector unit.
const vector_len = std.simd.suggestVectorLength(u8);

/// Reports whether `bytes` contains a zero byte, one byte at a time.
pub fn containsZeroScalar(bytes: []const u8) bool {
    for (bytes) |byte| {
        if (byte == 0) return true;
    }
    return false;
}

/// Reports whether `bytes` contains a zero byte, checking a whole vector of
/// bytes per step.
pub fn containsZero(bytes: []const u8) bool {
    const len = vector_len orelse return containsZeroScalar(bytes);
    const Chunk = @Vector(len, u8);
    const zeros: Chunk = @splat(0);

    var i: usize = 0;
    while (i + len <= bytes.len) : (i += len) {
        // A fixed-size array coerces to a vector of the same length.
        const chunk: Chunk = bytes[i..][0..len].*;
        // `==` compares lane by lane, giving a @Vector(len, bool);
        // @reduce(.Or, ...) asks "is any lane true?".
        if (@reduce(.Or, chunk == zeros)) return true;
    }
    // Fewer than `len` bytes are left over.
    return containsZeroScalar(bytes[i..]);
}

test containsZero {
    // Try every length up to a few vectors, with the zero at every position,
    // so the vector loop and the leftover tail both get checked.
    var buffer: [200]u8 = undefined;
    for (0..buffer.len) |len| {
        const bytes = buffer[0..len];
        @memset(bytes, 'a');
        try testing.expect(!containsZero(bytes));
        for (0..len) |zero_at| {
            bytes[zero_at] = 0;
            try testing.expect(containsZero(bytes));
            try testing.expectEqual(containsZeroScalar(bytes), containsZero(bytes));
            bytes[zero_at] = 'a';
        }
    }
}
```

- `vector_len orelse return containsZeroScalar(bytes)`: `vector_len` is a comptime
  `?comptime_int`. Without SIMD it's `null`, the function is just the scalar loop, and the vector
  code is never compiled. Otherwise `len` is a comptime constant, as `@Vector` requires.
- `bytes[i..][0..len]` slices with a comptime-known length, giving a **pointer to an array**,
  `*const [len]u8` ([Chapter 6](06-arrays-slices-pointers.md)). `.*` loads the array, which
  coerces to `@Vector(len, u8)`. The loop condition guarantees `len` bytes; safe builds still
  bounds-check the slice.
- The loop handles whole vectors; the leftover tail (less than one vector) goes to the scalar loop.
- The test tries every length from 0 to 199 with a zero at every position, covering lengths below,
  at, and above multiples of the vector length, and compares with the scalar version. Off-by-one
  errors at the vector/tail boundary are the classic SIMD bug.

### `src/search.zig`: use it

At the top, with the other imports:

```zig
const Stats = @import("stats.zig").Stats;
const bytes = @import("bytes.zig");
```

and at the end of `looksBinary`, replace

```zig
    return std.mem.findScalar(u8, head, 0) != null;
```

with

```zig
    return bytes.containsZero(head);
```

### `src/main.zig`: the test and the terminal check

Add `bytes.zig` to the `test` block at the bottom of `src/main.zig`, so its test runs with the
others:

```zig
test {
    _ = @import("bytes.zig");
    _ = @import("cli.zig");
```

Then the terminal check. In `run`, the parsed `options` become a `var`, since we'll change one
field:

```zig
    var options, const positionals = cli.parse(Options, gpa, args, &diag) catch |err| {
```

After `paths` is computed, before the `Searcher` is created, resolve `auto`:

```zig
    const paths = if (positionals.len > 1) positionals[1..] else default_paths;

    // `--color auto` means color only when a person is watching: when
    // stdout is a terminal, not a pipe or a file.
    if (options.color == .auto) {
        const tty = try std.Io.File.stdout().isTty(io);
        options.color = if (tty) .always else .never;
    }

    var searcher: Searcher = try .init(gpa, io, pattern, options, stdout, stderr);
```

`isTty` asks the OS whether the file is a terminal. Running `seek` by hand, it is; with `| less`,
`> out.txt`, or in a script, it isn't, and escape codes there would be noise. After this block
`options.color` is never `auto`, so the rest of the program, worker threads included, sees only
`always` or `never`.

Now build:

```console
$ zig build
install
+- install seek
   +- compile exe seek debug native 1 errors
src/main.zig:38:82: error: switch must handle all possibilities
    const status = run(init.gpa, init.io, args[1..], stdout, stderr) catch |err| switch (err) {
                                                                                 ^~~~~~
src/main.zig:38:82: note: unhandled error value: 'error.Canceled'
referenced by:
    callMain [inlined]: …/lib/std/start.zig:827:30
    callMainWithArgs [inlined]: …/lib/std/start.zig:729:20
    posixCallMainAndExit: …/lib/std/start.zig:681:38
    2 reference(s) hidden; use '-freference-trace=5' to see all references
error: 1 compilation errors
…
```

`isTty` returns `Io.Cancelable!bool`: like every `Io` operation, it may report that the task was
canceled ([Chapter 15](15-concurrency.md)). The `try` added `error.Canceled` to `run`'s inferred
error set, and `main`'s `switch` names every error, so the compiler caught the new one. That's why
`main` doesn't use `else =>`, which would have swallowed it silently. Add it to the errors `main`
passes on:

```zig
        error.OutOfMemory, error.WriteFailed, error.Canceled => |e| return e,
```

`src/output.zig` needs no code changes, but a comment in `Printer.init` is out of date. Replace

```zig
                // Inverted matches have nothing to highlight. `auto` behaves like
                // `never` until Chapter 19 teaches seek to detect a terminal.
```

with

```zig
                // Inverted matches have nothing to highlight. main.zig has
                // already turned `auto` into `always` or `never`.
```

On Windows `isTty` works too, but older consoles also need `File.enableAnsiEscapeCodes` before
they show colors. `seek` doesn't call it; a Windows-focused tool would.

### `bench/bench.zig`: measuring

Is the vector version faster? Measure. Create a folder `bench/` next to `src/`, with
`bench/bench.zig`:

`bench/bench.zig`

```zig
//! `zig build bench`: times three ways of looking for a zero byte.

const std = @import("std");
const Io = std.Io;
const bytes = @import("bytes"); // provided by build.zig

const size = 64 * 1024 * 1024;
const runs = 20;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer: Io.File.Writer = .initStreaming(.stdout(), io, &stdout_buffer);
    const out = &stdout_writer.interface;

    // No zero until the very last byte, so every function reads it all.
    const data = try gpa.alloc(u8, size);
    defer gpa.free(data);
    @memset(data, 'a');
    data[size - 1] = 0;

    try out.print("scanning {d} MiB, best of {d} runs\n", .{ size / (1024 * 1024), runs });
    try measure(io, out, "scalar loop", bytes.containsZeroScalar, data);
    try measure(io, out, "@Vector", bytes.containsZero, data);
    try measure(io, out, "std.mem.findScalar", stdFind, data);
    try out.flush();
}

fn stdFind(data: []const u8) bool {
    return std.mem.findScalar(u8, data, 0) != null;
}

fn measure(
    io: Io,
    out: *Io.Writer,
    name: []const u8,
    comptime scan: fn ([]const u8) bool,
    data: []const u8,
) !void {
    var best: Io.Duration = .max;
    for (0..runs) |_| {
        const start = Io.Clock.awake.now(io);
        const found = scan(data);
        const elapsed = start.untilNow(io, .awake);
        // Without this, the optimizer may notice `found` is unused and
        // delete the call we are trying to time.
        std.mem.doNotOptimizeAway(found);
        if (!found) return error.ZeroNotFound;
        if (elapsed.nanoseconds < best.nanoseconds) best = elapsed;
    }
    const seconds = @as(f64, @floatFromInt(best.nanoseconds)) / std.time.ns_per_s;
    const gib_per_second = @as(f64, @floatFromInt(data.len)) / (1024 * 1024 * 1024) / seconds;
    try out.print("{s:<20} {d:>8.2} ms  {d:>6.1} GiB/s\n", .{
        name,
        @as(f64, @floatFromInt(best.nanoseconds)) / std.time.ns_per_ms,
        gib_per_second,
    });
}
```

- `comptime scan: fn ([]const u8) bool` takes the function as a comptime parameter, so each
  `measure` call is compiled for one function and the call can be inlined, as in real use. (A
  runtime function pointer would add an indirect call to the measurement.)
- The **best** of 20 runs filters out noise: other programs, first-run page faults.
- `std.mem.doNotOptimizeAway(found)` makes the optimizer believe the result is used. Benchmarks
  that throw the result away often measure nothing.
- The awake clock is monotonic, as in [Chapter 13](13-generics.md)'s `--stats`.

`bench.zig` is outside `src/`, so `@import("../src/bytes.zig")` isn't allowed
([Chapter 18](18-build-system.md)). The build gives it `bytes.zig` as a named module,
`@import("bytes")`.

### `build.zig`: the `bench` step

Add a second executable at the end of `build`:

```zig
    test_step.dependOn(&run_exe_tests.step);

    // `zig build bench` builds a second executable and runs it. Timing a
    // Debug build would measure the safety checks, so the benchmark is
    // always optimized, whatever -Doptimize says.
    const bench = b.addExecutable(.{
        .name = "bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/bench.zig"),
            .target = target,
            .optimize = .fast,
            // bench.zig sits outside src/, so it gets bytes.zig as a named
            // module: `@import("bytes")`.
            .imports = &.{.{
                .name = "bytes",
                .module = b.createModule(.{ .root_source_file = b.path("src/bytes.zig") }),
            }},
        }),
    });
    const run_bench = b.addRunArtifact(bench);
    const bench_step = b.step("bench", "Time the zero-byte scanners");
    bench_step.dependOn(&run_bench.step);
}
```

- `.optimize = .fast` ignores `-Doptimize`: benchmarking a Debug build measures the debug build,
  not the algorithm.
- The `bytes` module has no `.target` or `.optimize`, so it takes the bench's.
- The bench isn't installed (no `installArtifact`), so only `zig build bench` builds it, not
  `zig build`.
- `bytes.zig` is now compiled into two executables: as a file of `seek`'s module and as the bench's
  `bytes` module. That's fine: a file can't belong to two modules of the *same* compilation, but
  these are separate programs.

Finally, add `"bench"` to `.paths` in `build.zig.zon`, so the folder is part of the package:

```zig
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
        "bench",
    },
```

### Checkpoint

```console
$ zig build test --summary all
Build Summary: 4/4 steps succeeded; 25/25 tests passed
test success
+- run test 25 pass (25 total) 19ms MaxRSS:6M
   +- compile test debug native success 391ms MaxRSS:166M
      +- options success

$ zig build bench
scanning 64 MiB, best of 20 runs
scalar loop             10.09 ms     6.2 GiB/s
@Vector                  3.32 ms    18.8 GiB/s
std.mem.findScalar       3.05 ms    20.5 GiB/s
```

The numbers are from a laptop with AVX2 (32-byte vectors); yours will differ, but the shape
shouldn't: the vector loop is about three times as fast as the scalar loop and about as fast as the
(also vectorized) standard library. Not 32 times: at these speeds the limit is how fast memory
delivers bytes, not how fast the CPU compares them.

For the terminal check, run `seek` in your terminal:

```console
$ zig build
$ ./zig-out/bin/seek fox testdata/poem.txt
testdata/poem.txt:The quick brown fox
```

"fox" appears in bold red. Through a pipe colors are off, and `--color always` turns them back on.
`cat -v` makes the escape codes visible:

```console
$ ./zig-out/bin/seek fox testdata/poem.txt | cat -v
testdata/poem.txt:The quick brown fox
$ ./zig-out/bin/seek --color always fox testdata/poem.txt | cat -v
testdata/poem.txt:The quick brown ^[[1;31mfox^[[0m
```

To see what a terminal receives without one at hand, `script` runs a command with a
pseudo-terminal as its stdout (the `^M` is the terminal's line-ending translation):

```console
$ script -qc "./zig-out/bin/seek fox testdata/poem.txt" /dev/null < /dev/null | cat -v
testdata/poem.txt:The quick brown ^[[1;31mfox^[[0m^M
```

`zig build run -- fox testdata/poem.txt` passes the terminal through to `seek`, so colors work
there too.

The complete project at this point is in `project/ch19/`.

## Summary

- **Illegal behavior** (overflow, bounds, null unwrap, bad casts, `unreachable`, division by zero,
  invalid enum or union access, bad slices) panics with a message in `debug` and `safe` builds and
  is **undefined behavior** in `fast` and `small`, where the optimizer assumes it never happens.
  If the compiler can see it, it's a compile error.
- Undefined behavior doesn't just give a wrong number; it breaks the program's logic wherever the
  value goes (`250 + 10 = 004`).
- Ask for the arithmetic you mean: `+%` wrapping, `+|` saturating, `std.math.add` checked,
  `@addWithOverflow`. `@setRuntimeSafety(false)` removes checks in one scope.
- Bit builtins: `@popCount`, `@clz`, `@ctz`, `@byteSwap`, `@bitReverse`, `@bitCast`. Shift amounts
  have type `std.math.Log2Int(T)`; `@shlExact` checks that no bits are lost.
- `packed struct` puts fields at exact bit positions; `extern struct` uses the C layout. Alignment
  is part of pointer types; `@alignCast` checks it. `volatile` is for memory-mapped I/O.
- `@Vector(len, T)` with `@splat`, lane-wise operators, `@reduce`, and `@select` is portable SIMD.
  `std.simd.suggestVectorLength` picks a lane count.
- C interop: `extern "c" fn` with C types, `-lc` / `.link_libc`, `callconv(.c)` for callbacks,
  `export` to be called from C, `addCSourceFile` to compile C, `addTranslateC` to import headers
  (`@cImport` is gone in 0.17).
- Benchmark optimized builds, take the best of many runs, and use `doNotOptimizeAway`.

## Exercises

1. Write `countNewlines(bytes: []const u8) usize` with `@Vector`, plus a scalar version and a test
   comparing them on random input of every length up to 300. Hint: `@select` can turn a vector of
   bools into a vector of 1s and 0s, and `@reduce(.Add, …)` sums it.

   <details><summary>Solution</summary>

   In a file `newlines.zig`:

   ```zig
   const std = @import("std");

   const vector_len = std.simd.suggestVectorLength(u8);

   pub fn countScalar(bytes: []const u8) usize {
       var count: usize = 0;
       for (bytes) |byte| {
           if (byte == '\n') count += 1;
       }
       return count;
   }

   pub fn countNewlines(bytes: []const u8) usize {
       const len = vector_len orelse return countScalar(bytes);
       const Chunk = @Vector(len, u8);
       const newlines: Chunk = @splat('\n');
       const ones: Chunk = @splat(1);
       const zeros: Chunk = @splat(0);

       var count: usize = 0;
       var i: usize = 0;
       while (i + len <= bytes.len) : (i += len) {
           const chunk: Chunk = bytes[i..][0..len].*;
           // 1 in every lane that holds a newline, 0 elsewhere. The sum of at
           // most 64 ones fits in a u8.
           const hits = @select(u8, chunk == newlines, ones, zeros);
           count += @reduce(.Add, hits);
       }
       return count + countScalar(bytes[i..]);
   }

   test countNewlines {
       var buffer: [300]u8 = undefined;
       var prng: std.Random.DefaultPrng = .init(1);
       const random = prng.random();
       for (0..buffer.len) |len| {
           const bytes = buffer[0..len];
           for (bytes) |*b| b.* = if (random.uintLessThan(u8, 4) == 0) '\n' else 'x';
           try std.testing.expectEqual(countScalar(bytes), countNewlines(bytes));
       }
       try std.testing.expectEqual(3, countNewlines("a\nb\nc\n"));
   }
   ```

   ```console
   $ zig test newlines.zig
   1/1 newlines.decltest.countNewlines...OK
   All 1 tests passed.
   ```

   `@reduce(.Add, hits)` adds `u8` lanes, so the sum is a `u8`. That's safe because a vector has
   at most 64 lanes on current CPUs; with longer vectors you'd widen first. A fixed seed keeps the
   test reproducible.

   </details>

2. FAT file systems and ZIP files store a date in 16 bits: the day in bits 0–4, the month in bits
   5–8, and the years since 1980 in bits 9–15. Decode `0x5A21` with a `packed struct(u16)` and
   `@bitCast`, then encode January 1, 2025 back.

   <details><summary>Solution</summary>

   ```zig
   const std = @import("std");

   /// A date as FAT file systems and ZIP files store it, in 16 bits.
   const DosDate = packed struct(u16) {
       day: u5, // 1-31
       month: u4, // 1-12
       years_since_1980: u7,
   };

   pub fn main() void {
       const raw: u16 = 0x5A21;
       const date: DosDate = @bitCast(raw);
       std.debug.print("{d}-{d:0>2}-{d:0>2}\n", .{
           @as(u16, date.years_since_1980) + 1980, date.month, date.day,
       });

       const back: DosDate = .{ .day = 1, .month = 1, .years_since_1980 = 45 };
       std.debug.print("0x{X}\n", .{@as(u16, @bitCast(back))});
   }
   ```

   ```console
   $ zig run dosdate.zig
   2025-01-01
   0x5A21
   ```

   The first field is the lowest bits. `@as(u16, …)` widens the `u7` before adding 1980, which
   doesn't fit in 7 bits.

   </details>

3. In `seek`'s `build.zig`, change the bench's `.optimize = .fast` to `.optimize = optimize` and
   run `zig build bench` (Debug) and `zig build bench -Doptimize=safe`. What happens, and why?
   Change it back afterwards.

   <details><summary>Solution</summary>

   ```console
   $ zig build bench
   scanning 64 MiB, best of 20 runs
   scalar loop             35.29 ms     1.8 GiB/s
   @Vector                103.89 ms     0.6 GiB/s
   std.mem.findScalar     101.81 ms     0.6 GiB/s
   $ zig build bench -Doptimize=safe
   scanning 64 MiB, best of 20 runs
   scalar loop             15.32 ms     4.1 GiB/s
   @Vector                  3.42 ms    18.3 GiB/s
   std.mem.findScalar       4.82 ms    13.0 GiB/s
   ```

   In Debug the vector versions are about **three times slower** than the plain loop: without
   optimization every vector operation goes through memory, far from the few instructions it
   becomes in an optimized build. A Debug benchmark would have "proved" SIMD useless. In `safe`
   mode the vector loop is as fast as in `fast` mode, and the scalar loop is slower, because of
   the safety checks and less aggressive loop optimization. Always benchmark the mode you ship.

   </details>

4. Why does the following program fail to compile, while `overflow_panic.zig` compiles and panics
   at run time?

   ```zig
   const std = @import("std");

   pub fn main() void {
       const stock: u8 = 250;
       const total: u8 = stock + 10;
       std.debug.print("{d}\n", .{total});
   }
   ```

   <details><summary>Solution</summary>

   ```text
   ct.zig:5:29: error: overflow of integer type 'u8' with value '260'
       const total: u8 = stock + 10;
                         ~~~~~~^~~~
   ```

   `stock` is a `const` initialized with a literal, so it's comptime-known
   ([Chapter 2](02-values-and-types.md)), and the compiler evaluates `stock + 10`. Illegal behavior
   during compile-time evaluation is always a compile error, in every build mode. In
   `overflow_panic.zig` the value comes from `parseInt` on a command-line argument, a runtime
   value, so the check happens at run time.

   </details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-19--safety-undefined-behavior-and-talking-to-c)
