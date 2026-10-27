# Chapter 2 — Values, Types, and Variables

Zig is strict about values: every integer has an exact size, conversions are spelled out, and
overflow is a bug that the compiler or runtime catches. This chapter covers constants and
variables, number types, conversions, overflow, division, `undefined`, and printing values. In
`seek`, you'll add a version string and exit codes. [Chapter 1](01-getting-started.md) set up the
tools; [Chapter 3](03-control-flow.md) adds control flow.

## `const` and `var`

`const` names a value that never changes; `var` names one that can. Write the type after a colon,
or let the compiler infer it from the value.

`examples/ch02/variables.zig`

```zig
const std = @import("std");

pub fn main() void {
    const answer = 42; // constant: can never change
    var count: u32 = 0; // variable: can change; type written out
    count += 1;
    count += 1;

    const ratio: f64 = 0.75; // a type annotation on a const is fine too
    const name = "seek"; // type inferred from the literal

    std.debug.print("answer={d} count={d} ratio={d} name={s}\n", .{ answer, count, ratio, name });
}
```

```console
$ zig run examples/ch02/variables.zig
answer=42 count=2 ratio=0.75 name=seek
```

Prefer `const`; Zig enforces it. Each of these is a compile error, not a warning:

| Mistake | Error |
|---------|-------|
| `x = 2;` when `x` is `const` | `error: cannot assign to constant` |
| local `var` or `const` never used | `error: unused local variable` (or `constant`) |
| `var` never changed | `error: local variable is never mutated` + `note: consider using 'const'` |

```text
never_mut.zig:4:9: error: local variable is never mutated
    var count: u32 = 0;
        ^~~~~
never_mut.zig:4:9: note: consider using 'const'
```

These rules keep code honest: every name is used, and `var` really means "this changes". They
apply to locals only; file-scope declarations may go unused.

To ignore a value on purpose, assign it to `_`:

```zig
_ = some_value; // "I know this is unused"
```

## Integers

Integer types are `u` (unsigned) or `i` (signed) plus a bit width, any width from 0 to 65535.

| Type | Range | Typical use |
|------|-------|-------------|
| `u8` | 0 … 255 | bytes, characters, exit statuses |
| `i32` | −2³¹ … 2³¹−1 | general signed numbers |
| `u64` | 0 … 2⁶⁴−1 | large counts, file sizes |
| `usize` / `isize` | pointer-sized (64 bits on 64-bit machines) | lengths and indexes |
| `u3`, `i7`, … | 0 … 7, −64 … 63 | packed fields, small ranges |

`examples/ch02/integers.zig`

```zig
const std = @import("std");

pub fn main() void {
    const small: u8 = 255; // unsigned, 8 bits: 0..255
    const negative: i32 = -1_000_000; // signed, 32 bits; `_` separates digits
    const big: u64 = 0xFFFF_FFFF; // hexadecimal literal
    const flags: u3 = 0b101; // any width works: u3 holds 0..7
    const tiny: i7 = -64; // i7 holds -64..63
    const size: usize = 1024; // pointer-sized: lengths and indexes
    const letter: u8 = 'A'; // a character literal is just a number

    std.debug.print("{d} {d} {d} {d} {d} {d} {d}\n", .{ small, negative, big, flags, tiny, size, letter });
    std.debug.print("u8: {d}..{d}\n", .{ std.math.minInt(u8), std.math.maxInt(u8) });
    std.debug.print("i7: {d}..{d}\n", .{ std.math.minInt(i7), std.math.maxInt(i7) });
    std.debug.print("u3 takes {d} bits, u64 takes {d} bytes\n", .{ @bitSizeOf(u3), @sizeOf(u64) });

    // Literals without a type are `comptime_int`: exact, unlimited size.
    const huge = 1 << 100;
    std.debug.print("2^100 = {d}, as u8 after >> 96: {d}\n", .{ huge, @as(u8, huge >> 96) });
}
```

```console
$ zig run examples/ch02/integers.zig
255 -1000000 4294967295 5 -64 1024 65
u8: 0..255
i7: -64..63
u3 takes 3 bits, u64 takes 8 bytes
2^100 = 1267650600228229401496703205376, as u8 after >> 96: 16
```

- Literals: decimal `42`, hex `0xff`, octal `0o755`, binary `0b1010`. Underscores may separate
  digits: `1_000_000`.
- A character literal like `'A'` is just a number (65).
- Signed integers use two's complement.
- `@sizeOf(T)` gives bytes; `@bitSizeOf(T)` gives bits.

### `comptime_int`

An untyped integer literal, like `42` or `1 << 100`, has type `comptime_int`. It exists only while
compiling, is exact, and has no size limit. When used, it **coerces** to the type the context
needs, *if the value fits*. Assigning `300` to a `u8` doesn't compile:

```text
toobig.zig:4:23: error: type 'u8' cannot represent integer value '300'
    const small: u8 = 300;
                      ^~~
```

No silent truncation, not even of constants.

## Floats

Zig has `f16`, `f32`, `f64`, `f80`, and `f128` (IEEE 754). Use `f64` unless you have a reason not
to. Untyped float literals are `comptime_float`.

`examples/ch02/floats.zig`

```zig
const std = @import("std");

pub fn main() void {
    const a: f32 = 1.5;
    const b: f64 = 1e-3; // scientific notation
    const c = 7.0 / 2.0; // comptime_float: 3.5
    const third: f64 = 1.0 / 3.0;

    std.debug.print("a={d} b={d} c={d}\n", .{ a, b, c });
    std.debug.print("third={d} rounded={d:.3}\n", .{ third, third });
    std.debug.print("0.1 + 0.2 = {d}\n", .{@as(f64, 0.1) + @as(f64, 0.2)});
    std.debug.print("sqrt(2) = {d:.5}, pi = {d:.5}\n", .{ @sqrt(@as(f64, 2)), std.math.pi });
    std.debug.print("inf={d} nan={d}\n", .{ std.math.inf(f64), std.math.nan(f64) });
}
```

```console
$ zig run examples/ch02/floats.zig
a=1.5 b=0.001 c=3.5
third=0.3333333333333333 rounded=0.333
0.1 + 0.2 = 0.30000000000000004
sqrt(2) = 1.41421, pi = 3.14159
inf=inf nan=nan
```

- `{d:.3}` prints 3 digits after the point.
- `0.1 + 0.2` isn't exactly `0.3` in binary floating point, in any language.
- `@sqrt` is a builtin; `std.math` has constants and more functions.

## `bool` and `void`

`bool` is `true` or `false`. The operators are `and`, `or`, and `!` ("not"). `and` and `or`
short-circuit: the right side runs only if needed.

`void` is the type with exactly one value, `{}`. It takes zero bytes. A function that returns
nothing returns `void`.

`examples/ch02/bool_void.zig`

```zig
const std = @import("std");

pub fn main() void {
    const sunny = true;
    const warm = false;
    std.debug.print("and={} or={} not={}\n", .{ sunny and warm, sunny or warm, !sunny });
    std.debug.print("as int: {d}\n", .{@intFromBool(sunny)});

    // `void` has exactly one value, written `{}`. It takes no space.
    const nothing: void = {};
    std.debug.print("void: {any}, size {d}\n", .{ nothing, @sizeOf(void) });
}
```

```console
$ zig run examples/ch02/bool_void.zig
and=false or=true not=false
as int: 1
void: void, size 0
```

There's no "truthiness": `if (count)` with an integer doesn't compile; write `if (count != 0)`.
Booleans become integers only via `@intFromBool`.

## Printing values

`std.debug.print` and `Writer.print` share one format language. A placeholder is `{specifier}`;
arguments come in order from `.{ ... }`.

| Specifier | Prints | Example → output |
|-----------|--------|------------------|
| `{d}` | a number in decimal | `255` → `255` |
| `{x}` / `{X}` | hex | `255` → `ff` / `FF` |
| `{b}` / `{o}` | binary / octal | `5` → `101` |
| `{c}` | a `u8` as a character | `'z'` → `z` |
| `{s}` | a string | `"hi"` → `hi` |
| `{any}` | anything, in a debug form | `"hi"` → `{ 104, 105 }` |
| `{}` | the default for simple values (numbers, bools) | `true` → `true` |

Width, alignment, and fill go after a colon: `{d:5}` pads to 5, `{d:<5}` aligns left, `{d:0>5}`
pads with zeros (`00042`), `{s:>4}` right-aligns a string. [Chapter 9](09-strings-and-formatting.md)
has the full details.

The format string is checked at compile time, so a wrong specifier is a compile error, not
garbage output:

```text
…/lib/std/Io/Writer.zig:1935:5: error: invalid format string 'd' for type '*const [2:0]u8'
```

That's `{d}` used with `"hi"`. Printing a string with plain `{}` gives
`error: cannot format slice without a specifier (i.e. {s}, {x}, {b64}, or {any})`.

## Coercion and casts

Zig converts a value to another type automatically (**coercion**) only when nothing can be lost.
Anything else needs an explicit **cast**: a builtin that names what you want.

`examples/ch02/coercion.zig`

```zig
const std = @import("std");

pub fn main() void {
    // Widening: every u8 value fits in a u32, so this just works.
    var byte: u8 = 200;
    byte += 0; // (makes `byte` a runtime value; see "comptime-known" below)
    const wide: u32 = byte;
    const signed: i16 = byte; // u8 fits in i16 (but not in i8)

    // Narrowing needs a builtin that says what you mean.
    var big: u32 = 300;
    big += 0;
    const checked: u16 = @intCast(big); // "it fits": checked in safe builds
    const cut: u8 = @truncate(big); // keep the low 8 bits: 300 - 256 = 44

    // Int -> float coerces when the float holds every value exactly.
    const exact: f64 = byte; // f64 holds every u8
    var count: i64 = 7;
    count += 0;
    const f: f64 = @floatFromInt(count); // f64 can't hold every i64: cast
    const back: i32 = @intFromFloat(f * 1.9); // 13.3 -> 13 (toward zero)

    // @as(T, x) is a safe, explicit coercion. Handy where no type is written.
    const sum = @as(u64, byte) + 1000;

    std.debug.print("wide={d} signed={d} checked={d} cut={d}\n", .{ wide, signed, checked, cut });
    std.debug.print("exact={d} f={d} back={d}\n", .{ exact, f, back });
    std.debug.print("sum={d} has type {s}\n", .{ sum, @typeName(@TypeOf(sum)) });
}
```

```console
$ zig run examples/ch02/coercion.zig
wide=200 signed=200 checked=300 cut=44
exact=200 f=7 back=13
sum=1200 has type u64
```

The rules:

| From → to | How |
|-----------|-----|
| smaller int → bigger int that holds every value (`u8` → `u32`, `u8` → `i16`) | automatic |
| `f32` → `f64` | automatic |
| int → float that holds every value exactly (`u8`, `i32` → `f64`) | automatic |
| bigger int → smaller int, value fits | `@intCast(x)` (panics in safe builds if it doesn't fit) |
| bigger int → smaller int, drop high bits | `@truncate(x)` |
| int → float (when not automatic) | `@floatFromInt(x)` |
| float → int (rounds toward zero) | `@intFromFloat(x)` (panics if out of range) |
| `bool` → int | `@intFromBool(b)` |
| any safe coercion, made explicit | `@as(T, x)` |

Casts like `@intCast` take their target type from context: `const checked: u16 = @intCast(big)`.
With no declared type, wrap it: `@as(u16, @intCast(big))`.

Narrowing without a cast:

```text
narrow.zig:6:23: error: expected type 'u8', found 'u32'
    const small: u8 = big;
                      ^~~
narrow.zig:6:23: note: unsigned 8-bit int cannot represent all possible unsigned 32-bit values
```

And `@intCast` at run time with a value that doesn't fit:

```text
thread 274750 panic: integer does not fit in destination type
…/intcast_panic.zig:6:23: 0x11e93ca in main (intcast_panic.zig)
    const small: u8 = @intCast(big);
                      ^
```

> **Gotcha: comptime-known values coerce if they fit.** `const big: u32 = 200; const small: u8 =
> big;` compiles, because the compiler knows `big` is 200. With `var big` it doesn't. That's why
> the examples above use `var` plus `+= 0` to make runtime values.

## Overflow is illegal behavior

What happens when a `u8` holding 250 gets 10 added? In C, unsigned values wrap silently and
signed overflow is undefined behavior. In Zig, overflow with plain `+`, `-`, `*` is **illegal
behavior** for both. Debug and ReleaseSafe builds check it and stop the program:

`examples/ch02/overflow_panic.zig`

```zig
const std = @import("std");

pub fn main() void {
    var x: u8 = 250;
    std.debug.print("x = {d}\n", .{x});
    x += 10; // 260 doesn't fit in a u8: illegal behavior
    std.debug.print("x = {d}\n", .{x});
}
```

```console
$ zig run examples/ch02/overflow_panic.zig
x = 250
thread 273670 panic: integer overflow
…/examples/ch02/overflow_panic.zig:6:7: 0x11e93b6 in main (overflow_panic.zig)
    x += 10; // 260 doesn't fit in a u8: illegal behavior
      ^
…/lib/std/start.zig:788:64: 0x11e8cab in callMain (std.zig)
    if (fn_info.param_types.len == 0) return wrapMain(root.main());
                                                               ^
…/lib/std/start.zig:248:5: 0x11e86e1 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
```

The panic names the bug and the exact line (thread IDs and addresses vary). The process then
aborts (exit status 134 on Linux). In `-O fast` or `-O small` builds the check is gone and the
result is undefined:

```console
$ zig run -O fast examples/ch02/overflow_panic.zig
x = 250
x = 4
```

If the compiler can see the overflow, it refuses to compile:

```text
ctoverflow.zig:5:34: error: overflow of integer type 'u8' with value '256'
    std.debug.print("{d}\n", .{x + 1});
                               ~~^~~
```

Why so strict? The Zen says *"Runtime crashes are better than bugs"*. A crash points at the
problem; a silently wrapped number corrupts data far away. And since overflow is illegal, the
optimizer may assume it never happens, which makes release builds faster.

When you *want* other behavior, use a different operator:

`examples/ch02/overflow.zig`

```zig
const std = @import("std");

pub fn main() void {
    var x: u8 = 250;
    x += 5; // 255: fine

    // Pick the overflow behavior you want, explicitly:
    const wrapped = x +% 10; // wrapping: 265 mod 256 = 9
    const saturated = x +| 10; // saturating: stops at 255
    const result, const overflowed = @addWithOverflow(x, 10); // result + a flag

    std.debug.print("wrapped={d} saturated={d}\n", .{ wrapped, saturated });
    std.debug.print("@addWithOverflow: result={d} overflowed={d}\n", .{ result, overflowed });

    const small: i8 = -128;
    std.debug.print("-%(-128) = {d}, 0 -% 1 as u8 = {d}\n", .{ -%small, @as(u8, 0) -% 1 });
}
```

```console
$ zig run examples/ch02/overflow.zig
wrapped=9 saturated=255
@addWithOverflow: result=9 overflowed=1
-%(-128) = -128, 0 -% 1 as u8 = 255
```

| Want | Operators |
|------|-----------|
| checked (default) | `+ - * +=` … |
| wrapping (modular arithmetic: hashes, checksums) | `+% -% *% -%x` |
| saturating (clamp at min/max) | `+| -| *| <<|` |
| result plus an overflow bit | `@addWithOverflow`, `@subWithOverflow`, `@mulWithOverflow`, `@shlWithOverflow` |

`@addWithOverflow` returns a pair (a *tuple*, [Chapter 7](07-structs-enums-unions.md));
`const result, const overflowed = ...` unpacks it. The flag is a `u1`: 1 means it overflowed.

## Division

For unsigned integers, `/` and `%` are plain division and remainder. For **signed** integers,
`-7 / 2` has several reasonable answers, so Zig makes you pick one:

`examples/ch02/division.zig`

```zig
const std = @import("std");

pub fn main() void {
    // Unsigned: `/` and `%` are unambiguous.
    const a: u32 = 7;
    std.debug.print("7 / 2 = {d}, 7 % 2 = {d}\n", .{ a / 2, a % 2 });

    // Signed: say which rounding you want.
    const n: i32 = -7;
    const d: i32 = 2;
    std.debug.print("@divTrunc(-7, 2) = {d}\n", .{@divTrunc(n, d)}); // toward zero: -3
    std.debug.print("@divFloor(-7, 2) = {d}\n", .{@divFloor(n, d)}); // toward -inf: -4
    std.debug.print("@rem(-7, 2) = {d}\n", .{@rem(n, d)}); // sign of dividend: -1
    std.debug.print("@mod(-7, 2) = {d}\n", .{@mod(n, d)}); // never negative: 1

    // Floats: `/` is ordinary division.
    const f: f64 = -7;
    std.debug.print("-7.0 / 2 = {d}\n", .{f / 2});
}
```

```console
$ zig run examples/ch02/division.zig
7 / 2 = 3, 7 % 2 = 1
@divTrunc(-7, 2) = -3
@divFloor(-7, 2) = -4
@rem(-7, 2) = -1
@mod(-7, 2) = 1
-7.0 / 2 = -3.5
```

| Builtin | Rounds | `-7, 2` gives |
|---------|--------|---------------|
| `@divTrunc` | toward zero (what C does) | −3 |
| `@divFloor` | toward −∞ | −4 |
| `@divCeil` | toward +∞ | −3 |
| `@divExact` | asserts no remainder (panics otherwise) | panic |
| `@rem` | remainder with the sign of the dividend (C's `%`) | −1 |
| `@mod` | remainder that is never negative | 1 |

`/` on a runtime signed value is a compile error:

```text
signeddiv.zig:6:34: error: division with 'i32' and 'comptime_int': signed integers must use @divTrunc, @divFloor, @divCeil, or @divExact
    std.debug.print("{d}\n", .{a / 2});
                               ~~^~~
```

`%` on a signed value gives `signed integers and floats must use @rem or @mod`. Division by zero
is illegal behavior too: `panic: division by zero` in safe builds.

## `undefined`, discards, and names

`undefined` means "no meaningful value yet". Use it when you'll assign before reading, like the
stdout buffer in [Chapter 1](01-getting-started.md). Reading an `undefined` value is a bug. Debug
builds fill undefined memory with `0xaa` bytes to make such bugs easier to spot, but don't rely
on it.

`examples/ch02/undefined_discard.zig`

```zig
const std = @import("std");

pub fn main() void {
    // `undefined`: "no value yet". Reading it before assigning is a bug.
    var total: u32 = undefined;
    total = 10;

    // `_ = expr;` evaluates and throws away a value, on purpose.
    _ = total + 1;

    // @"..." lets any text be an identifier, even keywords.
    const @"error count" = 3;
    const @"fn" = "a keyword as a name";

    std.debug.print("total={d} errors={d} {s}\n", .{ total, @"error count", @"fn" });
}
```

```console
$ zig run examples/ch02/undefined_discard.zig
total=10 errors=3 a keyword as a name
```

Identifiers start with a letter or `_` and contain letters, digits, and `_`. `@"..."` allows
anything else. You'll mostly see it for names that clash with keywords, like `@"struct"` or
`@"error"`, when talking to C or reflecting on types.

**No shadowing.** An inner scope can't reuse a name from an outer one:

```text
shadow.zig:6:15: error: local constant 'x' shadows local constant from outer scope
        const x: u32 = 2;
              ^
shadow.zig:4:11: note: previous declaration here
    const x: u32 = 1;
          ^
```

File-level names count too: a local `std` or `version` would clash. The upside: within a scope, a
name always means the same thing. Separate (non-nested) scopes may reuse names.

## Comptime-known vs. runtime values

Some values are known while compiling: literals, `const`s built from them, types. Others exist
only at run time: `var`s, user input, file contents. Zig tracks the difference, and some places
require **comptime-known** values, such as array lengths:

`examples/ch02/comptime_known.zig`

```zig
const std = @import("std");

const width = 4; // comptime-known: a literal
const height = width * 2; // computed by the compiler

pub fn main() void {
    // Array lengths must be known at compile time. `height` is.
    const grid: [height]u8 = undefined;

    // `var` values are runtime values, even when they look constant.
    var n: usize = 3;
    n += 1;

    std.debug.print("grid has {d} cells, n = {d}\n", .{ grid.len, n });
    std.debug.print("height is {s}, n is {s}\n", .{ @typeName(@TypeOf(height)), @typeName(@TypeOf(n)) });
}
```

```console
$ zig run examples/ch02/comptime_known.zig
grid has 8 cells, n = 4
height is comptime_int, n is usize
```

A `var` can't hold a `comptime_int`, because at run time it needs a fixed size:

```text
varcomptime.zig:4:9: error: variable of type 'comptime_int' must be const or comptime
    var n = 5;
        ^
varcomptime.zig:4:9: note: to modify this variable at runtime, it must be given an explicit fixed-size number type
```

Fix it with a type: `var n: u32 = 5;`. [Chapter 12](12-comptime.md) covers running real code at
compile time.

## Building seek: version and exit codes

`seek` needs a version string and grep's three exit statuses:

| Status | Meaning |
|--------|---------|
| 0 | a line matched |
| 1 | nothing matched |
| 2 | trouble: bad usage or an error |

Replace `src/main.zig` with:

`src/main.zig`

```zig
const std = @import("std");

/// The version of seek. A file-scope `const` is known at compile time and
/// costs nothing at run time; its type is inferred from the string literal.
const version = "0.1.0";

// Exit statuses, following grep's convention. Each has an explicit type:
// `u8` is what the operating system expects for an exit status.
const exit_ok: u8 = 0; // a line matched (or nothing went wrong)
const exit_no_match: u8 = 1; // nothing matched
const exit_trouble: u8 = 2; // bad usage or an error

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("seek {s}\n", .{version});
    try stdout.print("usage: seek [OPTIONS] PATTERN [PATH ...]\n", .{});
    try stdout.print("exit status: {d} = match, {d} = no match, {d} = trouble\n", .{
        exit_ok,
        exit_no_match,
        exit_trouble,
    });
    try stdout.flush();
}
```

What changed:

- `version` is a file-scope `const`, its type inferred from the string literal.
- The exit statuses are `u8` constants with explicit types. An exit status is a byte, so `u8` is
  the honest type. A `comptime_int` would print fine too, but the type documents intent.
  [Chapter 7](07-structs-enums-unions.md) turns them into an `enum`.
- The third `print`'s argument list has a trailing comma, so `zig fmt` puts each argument on its
  own line.

`main` still returns `!void`, so these aren't real exit statuses yet.
[Chapter 3](03-control-flow.md) does that.

### Checkpoint

```console
$ zig build run
seek 0.1.0
usage: seek [OPTIONS] PATTERN [PATH ...]
exit status: 0 = match, 1 = no match, 2 = trouble
```

The complete project at this point is in `project/ch02/`.

## Summary

- `const` for values that don't change, `var` for ones that do. Unused locals and never-mutated
  `var`s are compile errors. `_ = x;` discards on purpose.
- Integers have explicit widths: `u8`, `i32`, `u64`, `usize`, even `u3`. Untyped literals are
  `comptime_int` (exact, unlimited) and coerce only if the value fits.
- Floats: `f16` to `f128`; default to `f64`. Untyped float literals are `comptime_float`.
- `bool` has no truthiness. `void` has one value, `{}`.
- Coercion happens only when nothing can be lost. Otherwise cast: `@intCast`, `@truncate`,
  `@floatFromInt`, `@intFromFloat`, `@intFromBool`. `@as(T, x)` makes a coercion explicit.
- Overflow with `+ - *` is illegal behavior: a compile error, or a panic in safe builds. Use `+%`
  (wrap), `+|` (saturate), or `@addWithOverflow` when you mean it.
- Signed division needs `@divTrunc`, `@divFloor`, `@divCeil`, or `@divExact`; remainders use
  `@rem` or `@mod`.
- `undefined` means "not set yet". Names can't shadow other names. `@"..."` quotes any identifier.
- Some places (array lengths, for one) need comptime-known values.
- Format specifiers: `{d}` numbers, `{s}` strings, `{any}` anything, `{x}` hex, `{c}` characters.

## Exercises

1. Compute the seconds in a 365-day year as a `u32`, and in 1000 such years. Does the second
   number fit in a `u32`? Print both and `std.math.maxInt(u32)`.

   <details><summary>Solution</summary>

   ```zig
   const std = @import("std");

   pub fn main() void {
       const per_year: u32 = 60 * 60 * 24 * 365;
       const per_millennium: u64 = @as(u64, per_year) * 1000;
       std.debug.print("year: {d} s, millennium: {d} s\n", .{ per_year, per_millennium });
       std.debug.print("u32 max: {d}\n", .{std.math.maxInt(u32)});
   }
   ```

   ```console
   $ zig run seconds.zig
   year: 31536000 s, millennium: 31536000000 s
   u32 max: 4294967295
   ```

   It doesn't fit: 31,536,000,000 exceeds the `u32` maximum. `@as(u64, per_year)` widens
   *before* multiplying. Plain `per_year * 1000` would be computed as `u32` and, since both
   values are comptime-known, fail to compile with an overflow error.

   </details>

2. Convert a runtime `i32` temperature in Celsius to Fahrenheit (`F = C × 9 / 5 + 32`) as an
   `f64`. Test with −40.

   <details><summary>Solution</summary>

   ```zig
   const std = @import("std");

   pub fn main() void {
       var celsius: i32 = -40;
       celsius += 0; // a runtime value
       const c: f64 = @floatFromInt(celsius);
       const fahrenheit = c * 9.0 / 5.0 + 32.0;
       std.debug.print("{d}°C = {d}°F\n", .{ celsius, fahrenheit });
   }
   ```

   ```console
   $ zig run temp.zig
   -40°C = -40°F
   ```

   `const c: f64 = celsius;` would also compile, since `f64` holds every `i32` exactly. The cast
   makes the conversion visible.

   </details>

3. Predict each line, then run it to check:

   ```zig
   const a: u8 = 200;
   std.debug.print("{d}\n", .{a +% 100});
   std.debug.print("{d}\n", .{a +| 100});
   std.debug.print("{d}\n", .{@divFloor(-9, 4)});
   std.debug.print("{d}\n", .{@mod(-9, 4)});
   std.debug.print("{d}\n", .{@rem(-9, 4)});
   std.debug.print("{x}\n", .{@as(u8, @truncate(@as(u16, 0x1234)))});
   ```

   <details><summary>Solution</summary>

   ```text
   44
   255
   -3
   3
   -1
   34
   ```

   300 wraps to 44 (300 − 256); saturation stops at 255; −9 / 4 = −2.25 rounds down to −3;
   `@mod` is never negative (−9 = −3 × 4 + 3); `@rem` keeps the sign of −9; truncating `0x1234`
   to 8 bits leaves `0x34`.

   </details>

4. This program doesn't compile. Fix it to print `-3` (division rounding toward zero), changing as
   little as possible.

   ```zig
   const std = @import("std");

   pub fn main() void {
       var total: i32 = -17;
       var parts: i32 = 5;
       const each = total / parts;
       std.debug.print("{d}\n", .{each});
   }
   ```

   <details><summary>Solution</summary>

   The compiler reports three errors: two never-mutated `var`s, and a signed `/`.

   ```zig
   const std = @import("std");

   pub fn main() void {
       var total: i32 = -17;
       total += 0;
       const parts: i32 = 5;
       const each = @divTrunc(total, parts);
       std.debug.print("{d}\n", .{each});
   }
   ```

   `parts` becomes `const`. `total` stays a runtime `var` (here via `+= 0`; real code would change
   it for a reason). Making both `const` would also compile with plain `/`, since the compiler can
   then do the division itself.

   </details>

5. In `seek`, change `exit_trouble` to `256`. What does `zig build` say? Why is `u8` the right
   type for exit statuses?

   <details><summary>Solution</summary>

   ```text
   src/main.zig:11:26: error: type 'u8' cannot represent integer value '256'
   const exit_trouble: u8 = 256; // bad usage or an error
                            ^~~
   ```

   On POSIX systems a parent process sees only the low 8 bits of an exit status. With `u8`, the
   compiler rejects values that would be silently cut off. Change it back to `2` so your code
   matches the snapshots.

   </details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-2--values-types-and-variables)
