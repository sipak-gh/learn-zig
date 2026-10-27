# Chapter 9 — Strings, Text, and Formatting

Zig has no string type. A string is a byte slice, `[]const u8`, and you work with text through
ordinary slice functions: `std.mem` to search, split and trim, `std.ascii` for case, `std.unicode`
for UTF-8, and `std.fmt` to parse and format numbers. This chapter covers them all, plus format
strings and `format` methods for your own types. Then `seek` gets real options: `-i`, `-v`, `-n`,
and `--color`, which highlights matches in red. [Chapter 8](08-memory-and-allocators.md) covered
allocators, which you need to build new strings; [Chapter 10](10-containers.md) adds lists and hash
maps.

## Strings are byte slices

String literals came up in [Chapter 2](02-values-and-types.md) and slices in
[Chapter 6](06-arrays-slices-pointers.md). Here they are together:

`examples/ch09/strings.zig`

```zig
const std = @import("std");

pub fn main() void {
    // A string literal is a pointer to a null-terminated array of bytes.
    const hello = "héllo";
    std.debug.print("type: {s}\n", .{@typeName(@TypeOf(hello))});
    std.debug.print("len:  {d} bytes\n", .{hello.len});

    // It coerces to a slice, the type almost every function wants.
    const s: []const u8 = hello;
    std.debug.print("s[1] = {d} (0x{x}), s[2] = {d} (0x{x})\n", .{ s[1], s[1], s[2], s[2] });

    // Character literals are integers: their type is comptime_int.
    const c = 'A';
    std.debug.print("'A' = {d}, type {s}\n", .{ c, @typeName(@TypeOf(c)) });
    std.debug.print("'é' = {d} = U+{X:0>4}\n", .{ 'é', 'é' });

    // Escapes work as in C, plus \x and \u{...}.
    const escaped = "tab:\t| newline:\\n | hex:\x41 | unicode:\u{e9}";
    std.debug.print("{s}\n", .{escaped});

    // A multiline string literal: nothing is escaped, no trailing newline.
    const poem =
        \\The quick brown fox
        \\jumps over "the" lazy \dog.
    ;
    std.debug.print("{s}\n", .{poem});
    std.debug.print("poem has {d} bytes\n", .{poem.len});
}
```

```console
$ zig run examples/ch09/strings.zig
type: *const [6:0]u8
len:  6 bytes
s[1] = 195 (0xc3), s[2] = 169 (0xa9)
'A' = 65, type comptime_int
'é' = 233 = U+00E9
tab:	| newline:\n | hex:A | unicode:é
The quick brown fox
jumps over "the" lazy \dog.
poem has 47 bytes
```

- `"héllo"` is a `*const [6:0]u8`: a pointer to a 6-byte array followed by a 0. Five letters, six
  bytes, because `é` is two bytes in UTF-8 (`0xc3 0xa9`). Zig source is UTF-8, so literals are too.
- Indexing gives a **byte** (`u8`), not a character.
- `'A'` is the number 65, a `comptime_int`. `'é'` is 233, its Unicode code point, not a byte. To
  store a character literal in a `u8` it must fit: `const b: u8 = 'é';` works (233), `'⚡'` (9889)
  doesn't.
- `\x41` is one byte in hex; `\u{e9}` is a code point, written out as UTF-8.

### Multiline string literals

Each line starts with `\\`, and the rest is taken literally: quotes, backslashes, braces, no
escapes. Lines are joined with `\n`; the last gets no newline. The literal ends at the first line
not starting with `\\`, so the `;` goes on its own line. Use them for help text, test input, and
embedded data.

### UTF-8: bytes and code points

Usually you can treat text as bytes. Searching for `"fox"` works the same in ASCII or emoji-filled
text, because UTF-8 never puts an ASCII byte inside a multi-byte character. When you need
characters, decode the UTF-8:

`examples/ch09/utf8.zig`

```zig
const std = @import("std");

pub fn main() !void {
    const word = "naïve café";

    // Bytes: a for loop over a []const u8 sees bytes, not characters.
    std.debug.print("{d} bytes:", .{word.len});
    for (word) |byte| std.debug.print(" {x:0>2}", .{byte});
    std.debug.print("\n", .{});

    // Code points: decode the UTF-8 with a Utf8View.
    const view = try std.unicode.Utf8View.init(word);
    var it = view.iterator();
    var n: usize = 0;
    while (it.nextCodepoint()) |cp| : (n += 1) {
        // `cp` is a u21; {u} prints it as UTF-8 again.
        std.debug.print("[{u}]", .{cp});
        if (cp > 127) std.debug.print("=U+{X:0>4}", .{cp});
    }
    std.debug.print("\n{d} code points\n", .{n});
    std.debug.print("utf8CountCodepoints: {d}\n", .{try std.unicode.utf8CountCodepoints(word)});

    // Invalid UTF-8 is rejected by init.
    const bad = "caf\xe9"; // Latin-1 é, not UTF-8
    if (std.unicode.Utf8View.init(bad)) |_| {
        std.debug.print("valid\n", .{});
    } else |err| {
        std.debug.print("bad: {t}\n", .{err});
    }
}
```

```console
$ zig run examples/ch09/utf8.zig
12 bytes: 6e 61 c3 af 76 65 20 63 61 66 c3 a9
[n][a][ï]=U+00EF[v][e][ ][c][a][f][é]=U+00E9
10 code points
utf8CountCodepoints: 10
bad: InvalidUtf8
```

`Utf8View.init` checks that the bytes are valid UTF-8; its iterator returns one code point (`u21`)
at a time, or its bytes with `nextCodepointSlice`. A code point isn't always what a person calls a
character (an emoji with a skin tone is several), but it's enough for most programs. `std` has no
Unicode case folding or normalization; use a library for that.

## Searching and trimming with `std.mem`

`std.mem` works on slices of any type, so every function takes the element type first:
`std.mem.eql(u8, a, b)`. For strings it's `u8`.

`examples/ch09/search_mem.zig`

```zig
const std = @import("std");
const mem = std.mem;

pub fn main() void {
    const line = "  error: disk full (disk 2)  \n";

    // Comparing: never use == on slices.
    std.debug.print("eql: {}\n", .{mem.eql(u8, "zig", "zig")});

    // Finding: every find* returns ?usize, null when there's no match.
    std.debug.print("find \"disk\":      {?d}\n", .{mem.find(u8, line, "disk")});
    std.debug.print("findLast \"disk\":  {?d}\n", .{mem.findLast(u8, line, "disk")});
    std.debug.print("findScalar ':':   {?d}\n", .{mem.findScalar(u8, line, ':')});
    std.debug.print("find \"cpu\":       {?d}\n", .{mem.find(u8, line, "cpu")});
    std.debug.print("count \"disk\":     {d}\n", .{mem.count(u8, line, "disk")});

    // Trimming returns a shorter slice of the same memory: no copy.
    const trimmed = mem.trim(u8, line, " \n");
    std.debug.print("trimmed: \"{s}\"\n", .{trimmed});
    std.debug.print("startsWith error: {}\n", .{mem.startsWith(u8, trimmed, "error")});
    std.debug.print("endsWith \")\":    {}\n", .{mem.endsWith(u8, trimmed, ")")});

    // cutPrefix: the rest after a prefix, or null.
    if (mem.cutPrefix(u8, trimmed, "error: ")) |msg| {
        std.debug.print("message: \"{s}\"\n", .{msg});
    }

    // cut: split around the first match into a 2-tuple.
    if (mem.cut(u8, "key=value=x", "=")) |kv| {
        const key, const value = kv;
        std.debug.print("key \"{s}\", value \"{s}\"\n", .{ key, value });
    }
}
```

```console
$ zig run examples/ch09/search_mem.zig
eql: true
find "disk":      9
findLast "disk":  20
findScalar ':':   7
find "cpu":       null
count "disk":     2
trimmed: "error: disk full (disk 2)"
startsWith error: true
endsWith ")":    true
message: "disk full (disk 2)"
key "key", value "value=x"
```

`==` on two slices doesn't compile; `std.mem.eql` compares contents. Every result is a slice of
`line` or an index into it. Nothing is allocated or copied, so these are cheap and can't fail.

> **Zig 0.17:** the search functions were renamed from `indexOf*` to `find*`: `indexOf` → `find`,
> `indexOfScalar` → `findScalar`, `lastIndexOf` → `findLast`, and so on. The old names still work
> but are deprecated, so you'll see both online.

Other useful ones: `findAny` (first of several bytes), `findPos` (start from an index),
`trimStart`/`trimEnd`, `cutSuffix`, `cutScalar`, and `containsAtLeast`.

### Splitting and tokenizing

To walk a string's parts, `std.mem` has iterators. Each `next()` returns the next part (a slice of
the input) or `null` at the end, which fits a `while` with a capture
([Chapter 3](03-control-flow.md)):

`examples/ch09/split.zig`

```zig
const std = @import("std");
const mem = std.mem;

pub fn main() void {
    const csv = "a,b,,c";

    // splitScalar: every separator splits, so empty fields appear.
    var fields = mem.splitScalar(u8, csv, ',');
    std.debug.print("split:   ", .{});
    while (fields.next()) |f| std.debug.print("[{s}]", .{f});
    std.debug.print("\n", .{});

    // tokenizeScalar: runs of separators are skipped, no empty tokens.
    var tokens = mem.tokenizeScalar(u8, csv, ',');
    std.debug.print("tokenize:", .{});
    while (tokens.next()) |t| std.debug.print("[{s}]", .{t});
    std.debug.print("\n", .{});

    // tokenizeAny: any of several separator bytes.
    var words = mem.tokenizeAny(u8, "  one two\tthree\n", " \t\n");
    std.debug.print("words:   ", .{});
    while (words.next()) |w| std.debug.print("[{s}]", .{w});
    std.debug.print("\n", .{});

    // splitSequence: the separator is a whole string.
    var parts = mem.splitSequence(u8, "one :: two :: three", " :: ");
    std.debug.print("parts:   ", .{});
    while (parts.next()) |p| std.debug.print("[{s}]", .{p});
    std.debug.print("\n", .{});

    // The iterator can also give you the unsplit rest.
    var it = mem.splitScalar(u8, "cmd arg1 arg2", ' ');
    const cmd = it.first();
    std.debug.print("cmd [{s}], rest [{s}]\n", .{ cmd, it.rest() });
}
```

```console
$ zig run examples/ch09/split.zig
split:   [a][b][][c]
tokenize:[a][b][c]
words:   [one][two][three]
parts:   [one][two][three]
cmd [cmd], rest [arg1 arg2]
```

The rule: **split** when empty fields matter (CSV columns, lines), **tokenize** when they don't
(words separated by any whitespace). Each has three flavors: `Scalar` (one byte), `Any` (any byte
from a set) and `Sequence` (a whole string). `seek` has walked lines with `splitScalar` on `'\n'`
since Chapter 4.

The iterator is a struct holding the input and a position, so it must be `var`. It allocates
nothing.

### Building new strings

Searching and splitting return slices of what you have. A *new* string (joining, replacing,
formatting) needs memory: an allocator, or a buffer you provide:

`examples/ch09/build_strings.zig`

```zig
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    // Joining runtime strings needs new memory, so it needs an allocator.
    const parts = [_][]const u8{ "usr", "local", "bin" };
    const path = try std.mem.join(gpa, "/", &parts);
    defer gpa.free(path);
    std.debug.print("join:    {s}\n", .{path});

    const whole = try std.mem.concat(gpa, u8, &.{ "zig", "-", "0.17" });
    defer gpa.free(whole);
    std.debug.print("concat:  {s}\n", .{whole});

    const fixed = try std.mem.replaceOwned(u8, gpa, "colour and colour", "colour", "color");
    defer gpa.free(fixed);
    std.debug.print("replace: {s}\n", .{fixed});

    // Formatting into new memory: Allocator.print.
    const msg = try gpa.print("{s} has {d} parts", .{ path, parts.len });
    defer gpa.free(msg);
    std.debug.print("print:   {s}\n", .{msg});

    // Formatting into a buffer you already have: std.mem.print. No allocator.
    var buf: [32]u8 = undefined;
    const label = try std.mem.print(&buf, "item-{d:0>3}", .{7});
    std.debug.print("buffer:  {s}\n", .{label});

    // The buffer is too small: error.NoSpaceLeft.
    var tiny: [4]u8 = undefined;
    if (std.mem.print(&tiny, "{d}", .{123456})) |s| {
        std.debug.print("fits: {s}\n", .{s});
    } else |err| {
        std.debug.print("tiny:    {t}\n", .{err});
    }

    // Changing bytes in place needs a mutable copy.
    const upper = try gpa.dupe(u8, "shout");
    defer gpa.free(upper);
    for (upper) |*ch| ch.* = std.ascii.toUpper(ch.*);
    std.debug.print("upper:   {s}\n", .{upper});
}
```

```console
$ zig run examples/ch09/build_strings.zig
join:    usr/local/bin
concat:  zig-0.17
replace: color and color
print:   usr/local/bin has 3 parts
buffer:  item-007
tiny:    NoSpaceLeft
upper:   SHOUT
```

Each allocating call returns memory the caller owns, so each is followed by its `defer free`.
`std.mem.print` returns the part of `buf` it filled.

> **Zig 0.17:** `std.fmt.allocPrint(gpa, ...)` became `gpa.print(...)`, and `std.fmt.bufPrint`
> became `std.mem.print`. The old names are deprecated but common in older tutorials.

String literals live in read-only memory. To modify text, `dupe` it first (or copy it into an
array), as with `upper`.

## Case and characters: `std.ascii`

`std.ascii` has character tests (`isDigit`, `isAlphabetic`, `isWhitespace`, ...), case conversion,
and case-insensitive compare and search:

`examples/ch09/ascii.zig`

```zig
const std = @import("std");
const ascii = std.ascii;

pub fn main() void {
    std.debug.print("toLower('Q') = {c}\n", .{ascii.toLower('Q')});
    std.debug.print("isDigit('7') = {}\n", .{ascii.isDigit('7')});
    std.debug.print("eqlIgnoreCase: {}\n", .{ascii.eqlIgnoreCase("Zig", "ZIG")});
    std.debug.print("findIgnoreCase: {?d}\n", .{ascii.findIgnoreCase("The Quick Fox", "quick")});

    // lowerString writes into a buffer you provide.
    var buf: [32]u8 = undefined;
    std.debug.print("lowerString: {s}\n", .{ascii.lowerString(&buf, "Hello, WORLD")});

    // ASCII only: bytes above 127 are left alone.
    std.debug.print("eqlIgnoreCase(\"É\", \"é\"): {}\n", .{ascii.eqlIgnoreCase("É", "é")});
    std.debug.print("lowerString: {s}\n", .{ascii.lowerString(&buf, "CAFÉ")});
}
```

```console
$ zig run examples/ch09/ascii.zig
toLower('Q') = q
isDigit('7') = true
eqlIgnoreCase: true
findIgnoreCase: 4
lowerString: hello, world
eqlIgnoreCase("É", "é"): false
lowerString: cafÉ
```

It's ASCII only: `A`–`Z` and `a`–`z`. Non-ASCII bytes pass through unchanged. That's safe (it never
breaks UTF-8), but `É` and `é` stay different, the same trade-off `grep` makes in the C locale.

> **Zig 0.17:** `std.ascii.indexOfIgnoreCase` is now `findIgnoreCase`, matching the `std.mem`
> rename.

## Format strings

You've used `print("{s}: {d}\n", .{ name, n })` since Chapter 1. `std.debug.print`, every
`*std.Io.Writer`, `Allocator.print` and `std.mem.print` share this format language. A placeholder
looks like this:

```
{[argument][specifier]:[fill][alignment][width].[precision]}
```

All parts are optional; `{}` uses the type's default format.

### Specifiers

`examples/ch09/specifiers.zig`

```zig
const std = @import("std");

const Color = enum { red, green };
const Point = struct { x: i32, y: i32 };

pub fn main() void {
    const n: u8 = 200;
    std.debug.print("d: {d}  x: {x}  X: {X}  b: {b}  o: {o}\n", .{ n, n, n, n, n });
    std.debug.print("c: {c}  u: {u}\n", .{ 'z', '⚡' });
    std.debug.print("e: {e}  d: {d}\n", .{ 1234.5, 1234.5 });

    std.debug.print("s: {s}  q: {q}\n", .{ "tab\there", "tab\there" });
    std.debug.print("x on a string: {x}\n", .{"Zig"});

    std.debug.print("t: {t} {t}\n", .{ Color.green, error.NotFound });
    std.debug.print("B: {B}  Bi: {Bi:.2}\n", .{ 1_500_000, 1_500_000 });

    const maybe: ?u32 = null;
    const some: ?u32 = 42;
    std.debug.print("?: {?d} {?d}\n", .{ maybe, some });

    const ok: anyerror!u32 = 7;
    const bad: anyerror!u32 = error.Oops;
    std.debug.print("!: {!d} {!d}\n", .{ ok, bad });

    // any: the default format, works for structs, arrays, slices, ...
    const p: Point = .{ .x = 1, .y = -2 };
    std.debug.print("any: {any}\n", .{p});
    std.debug.print("any: {any}\n", .{[_]u8{ 1, 2, 3 }});

    // *: the address, not the value.
    std.debug.print("*: {*}\n", .{&p});

    // Arguments by position or by name; {{ and }} are literal braces.
    std.debug.print("{1s} {0s}!\n", .{ "world", "hello" });
    std.debug.print("{[name]s} is {[age]d}\n", .{ .name = "Ziggy", .age = 9 });
    std.debug.print("{{d}} prints braces\n", .{});
}
```

```console
$ zig run examples/ch09/specifiers.zig
d: 200  x: c8  X: C8  b: 11001000  o: 310
c: z  u: ⚡
e: 1.2345e3  d: 1234.5
s: tab	here  q: "tab\there"
x on a string: 5a6967
t: green NotFound
B: 1.5MB  Bi: 1.43MiB
?: null 42
!: 7 error.Oops
any: .{ .x = 1, .y = -2 }
any: { 1, 2, 3 }
*: specifiers.Point@12990a8
hello world!
Ziggy is 9
{d} prints braces
```

(The address after `@` will differ on your machine.)

| Specifier | Prints |
|---|---|
| `d` | number in decimal (integers, floats, and an enum's backing integer) |
| `x`, `X` | hex, lower or upper case; on strings, each byte as two hex digits |
| `b`, `o` | binary, octal |
| `e` | float in scientific notation |
| `c` | a `u8` as a character |
| `u` | a code point (up to `u21`) as UTF-8 |
| `s` | a string (`[]const u8`, or a `[*:0]const u8` up to the 0) |
| `q` | a string in double quotes, with escapes, ready to paste into Zig code |
| `t` | the tag name of an enum or tagged union, or the name of an error |
| `B`, `Bi` | a byte count in SI (kB, MB) or binary (KiB, MiB) units |
| `?` | an optional: the value, or `null`; put the value's specifier after it |
| `!` | an error union: the value, or the error; put the value's specifier after it |
| `any` | the default format for any type (also what `{}` means) |
| `*` | the address of a pointer |
| `f` | call the value's `format` method (below) |

Two common traps. Strings need `{s}`: with `{any}`, a `[]const u8` prints as numbers
(`{ 97, 98, 99 }`). And optionals need `{?}` (or `{any}`), with the inner specifier after it:
`{?d}`. Plain `{d}` on an optional is a compile error.

### Width, fill, alignment, precision

After a `:` you can pad the value to a width:

`examples/ch09/width.zig`

```zig
const std = @import("std");

pub fn main() void {
    // {[specifier]:[fill][alignment][width].[precision]}
    std.debug.print("[{d:5}]\n", .{42}); // width 5: right-aligned by default
    std.debug.print("[{d:<5}]\n", .{42}); // < left
    std.debug.print("[{d:^5}]\n", .{42}); // ^ center
    std.debug.print("[{d:0>5}]\n", .{42}); // fill with 0, align right
    std.debug.print("[{s:5}]\n", .{"ab"}); // strings too
    std.debug.print("[{s:.>5}]\n", .{"ab"}); // fill with '.', align right
    std.debug.print("[{s:-^9}]\n", .{"mid"});
    std.debug.print("[{d:.2}]\n", .{3.14159}); // precision: 2 decimals
    std.debug.print("[{d:8.3}]\n", .{3.14159}); // width 8, 3 decimals
    std.debug.print("[{x:0>8}]\n", .{0xbeef});

    // A small table.
    const rows = [_]struct { []const u8, u32, f64 }{
        .{ "apples", 3, 1.5 },
        .{ "kiwis", 12, 0.25 },
        .{ "watermelons", 1, 4.0 },
    };
    for (rows) |row| {
        const name, const qty, const price = row;
        std.debug.print("{s:<12}{d:>4} x {d:>5.2}\n", .{ name, qty, price });
    }
}
```

```console
$ zig run examples/ch09/width.zig
[   42]
[42   ]
[ 42  ]
[00042]
[   ab]
[...ab]
[---mid---]
[3.14]
[   3.142]
[0000beef]
apples         3 x  1.50
kiwis         12 x  0.25
watermelons    1 x  4.00
```

Values are right-aligned by default, strings too, so use `<` for a left-aligned text column. To pad
with something other than spaces, give the fill byte *and* an alignment: `{s:.>5}`. (`{d:05}` is a
shortcut for zero padding, but `{d:0>5}` is plainer.) Width counts **bytes**, so a column holding
`é` looks one character short.

### Format strings are checked at compile time

The format string must be comptime-known. `print` parses it during compilation and checks each
placeholder against its argument's type. A mistake is a compile error, not a crash or garbage:

`examples/ch09/bad_format.zig`

```zig
const std = @import("std");

pub fn main() void {
    const name = "seek";
    std.debug.print("{d}\n", .{name});
}
```

```console
$ zig run -freference-trace=4 examples/ch09/bad_format.zig
…/lib/std/Io/Writer.zig:1935:5: error: invalid format string 'd' for type '*const [4:0]u8'
    @compileError("invalid format string '" ++ fmt ++ "' for type '" ++ @typeName(@TypeOf(value)) ++ "'");
    ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
referenced by:
    printValue__func_787: …/lib/std/Io/Writer.zig:1188:40
    print__func_786: …/lib/std/Io/Writer.zig:805:25
    print__func_785: …/lib/std/debug.zig:330:39
    main: examples/ch09/bad_format.zig:5:20
    5 reference(s) hidden; use '-freference-trace=9' to see all references
```

The error comes from `@compileError` inside `std`, so it points there first. Read down the
`referenced by:` list to find your line: `examples/ch09/bad_format.zig:5:20`. By default only two
references are shown, not enough to reach `main`; `-freference-trace=N` shows more. The argument
count is checked too: `print("{s} and {s}\n", .{"one"})` fails with `error: too few arguments` (see
`examples/ch09/bad_format_args.zig`).

This is plain Zig code running at compile time, not compiler magic; [Chapter 12](12-comptime.md)
shows how.

## Parsing numbers

The opposite direction: text to numbers.

`examples/ch09/parse.zig`

```zig
const std = @import("std");

pub fn main() void {
    const inputs = [_][]const u8{ "42", "-7", "0x1F", "1_000", "300", "12abc", "" };
    for (inputs) |text| {
        // Base 0 means "detect": 0x, 0o and 0b prefixes are allowed.
        if (std.fmt.parseInt(u8, text, 0)) |n| {
            std.debug.print("{s:>7} -> {d}\n", .{ text, n });
        } else |err| {
            std.debug.print("{s:>7} -> {t}\n", .{ text, err });
        }
    }

    const hex = std.fmt.parseInt(u32, "ff", 16) catch unreachable;
    std.debug.print("ff in base 16 = {d}\n", .{hex});

    const pi = std.fmt.parseFloat(f64, "3.14159") catch unreachable;
    std.debug.print("pi = {d:.2}\n", .{pi});
    if (std.fmt.parseFloat(f64, "three")) |_| {} else |err| {
        std.debug.print("three -> {t}\n", .{err});
    }
}
```

```console
$ zig run examples/ch09/parse.zig
     42 -> 42
     -7 -> Overflow
   0x1F -> 31
  1_000 -> Overflow
    300 -> Overflow
  12abc -> InvalidCharacter
        -> InvalidCharacter
ff in base 16 = 255
pi = 3.14
three -> InvalidCharacter
```

`parseInt(T, text, base)` returns `error.InvalidCharacter` for anything that isn't a number
(including `""`) and `error.Overflow` when it doesn't fit in `T`: `-7`, 300 and 1000 don't fit a
`u8`. `_` is skipped anywhere, as in Zig literals. The type is part of the validation, so parse
into the type you need. There's no partial parse: `"12abc"` fails as a whole.

## Your own `format` method and `{f}`

Give a type a `format` method with this exact signature, and `{f}` calls it:

`examples/ch09/format_method.zig`

```zig
const std = @import("std");

const Money = struct {
    cents: i64,

    /// Called for the `{f}` specifier.
    pub fn format(m: Money, w: *std.Io.Writer) std.Io.Writer.Error!void {
        const sign = if (m.cents < 0) "-" else "";
        const abs = @abs(m.cents);
        try w.print("{s}${d}.{d:0>2}", .{ sign, abs / 100, abs % 100 });
    }
};

const Line = struct {
    item: []const u8,
    price: Money,

    // A format method can use {f} on its fields.
    pub fn format(line: Line, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("{s}: {f}", .{ line.item, line.price });
    }
};

pub fn main(init: std.process.Init) !void {
    const price: Money = .{ .cents = 1999 };
    std.debug.print("price: {f}\n", .{price});
    std.debug.print("refund: {f}\n", .{Money{ .cents = -5 }});

    // {any} ignores the format method and prints the fields.
    std.debug.print("any: {any}\n", .{price});

    // Works with every writer: stdout, buffers, allocated strings.
    const line: Line = .{ .item = "book", .price = price };
    const text = try init.gpa.print("[{f}]", .{line});
    defer init.gpa.free(text);
    std.debug.print("{s}\n", .{text});
}
```

```console
$ zig run examples/ch09/format_method.zig
price: $19.99
refund: -$0.05
any: .{ .cents = 1999 }
[book: $19.99]
```

The method gets the value and a `*std.Io.Writer` to write to. It returns
`std.Io.Writer.Error!void`, so it fails only as a writer fails, and gets no allocator. Since it
writes to any writer, it works for `std.debug.print`, a file, or `gpa.print`.

`{f}` must be explicit. `{}` and `{any}` ignore the method and print the fields, so the raw data
is always visible.

> **Note:** the signature is fixed. Older Zig passed the format string and options as extra
> parameters (`fn format(self, comptime fmt, options, writer)`); 0.17 doesn't. For several output
> styles, write several methods, or one returning a small wrapper struct with its own `format`.
> `{qf}` calls the method and quotes the result.

## Building seek: options, case folding, and color

This chapter adds real options to `seek`:

- `-i` to ignore case, `-v` to print lines that **don't** match, `-n` to show line numbers;
- `--color WHEN` (`auto`, `always`, `never`) to highlight matches in red;
- `--` to end the options, so you can search for `-v` itself;
- `-h` to list the options.

The `Options` struct from [Chapter 7](07-structs-enums-unions.md) already has fields for these.
Only `src/main.zig` and `src/search.zig` change. Start from your Chapter 8 project (or copy
`project/ch08/`).

### The help text: a multiline literal

At the top of `src/main.zig`, add `Color` next to the other imports, then the help text below
`usage`:

```zig
const Color = search.Color;
```

```zig
const usage = "usage: seek [OPTIONS] PATTERN [PATH ...]\n";

// A multiline string literal: each line starts with `\\`. Nothing inside is
// escaped, and the last line gets no newline (hence the empty final line).
// `++` concatenates arrays at compile time.
const help = usage ++
    \\
    \\options:
    \\  -i            ignore case
    \\  -v            select non-matching lines
    \\  -n            show line numbers
    \\  --color WHEN  highlight matches: auto, always, never
    \\  -h, --help    show this help
    \\  --version     show the version
    \\
;
```

`usage` already ends with `\n`, so the first (empty) `\\` line adds a blank line. The last empty
`\\` line ends the text with a newline. Both sides of `++` are comptime-known arrays, so `help` is
built at compile time, without allocating.

In `run`, `.help` now prints `help` instead of `usage`:

```zig
        .help => {
            try stdout.writeAll(help);
            return .ok;
        },
```

Usage errors keep printing the short `usage`.

### Parsing options with a `while` loop

The old `parseArgs` used a `for` loop. An option with a value (`--color always`) must also consume
the *next* argument, so we switch to a `while` loop with our own index. Two new usage errors cover
a missing or bad value:

```zig
const UsageError = error{ UnknownFlag, MissingValue, InvalidValue, MissingPattern, MissingPath };
```

Add them to the `catch` in `main` too. A long prong list reads better one per line, and `zig fmt`
keeps it that way if it ends with a trailing comma:

```zig
    const status = run(init.gpa, init.io, args, stdout, stderr) catch |err| switch (err) {
        error.UnknownFlag,
        error.MissingValue,
        error.InvalidValue,
        error.MissingPattern,
        error.MissingPath,
        => blk: {
            try stderr.writeAll(usage);
            break :blk .trouble;
        },
        error.OutOfMemory, error.WriteFailed => |e| return e,
    };
```

Now replace `parseArgs` and add two small helpers below it:

```zig
/// Turns the command line into a Command. Options come first; the first
/// argument that isn't an option is PATTERN and the rest are PATHs, so both
/// stay slices of `args`. Problems are reported on `stderr`.
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
        } else if (eql(arg, "--color")) {
            i += 1;
            const value = argAt(args, i) orelse {
                try stderr.print("seek: {s} needs a value\n", .{arg});
                return error.MissingValue;
            };
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
    if (i + 1 >= args.len) return error.MissingPath;
    return .{ .search = .{ .options = options, .pattern = args[i], .paths = args[i + 1 ..] } };
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn argAt(args: []const [:0]const u8, index: usize) ?[]const u8 {
    return if (index < args.len) args[index] else null;
}
```

How it works:

- The loop `break`s at the first argument that isn't an option. Then `i` is PATTERN's index and
  everything after is a PATH. `pattern` and `paths` stay slices of `args`; nothing is copied.
- `--color` advances `i` to read its value. `argAt` returns `null` past the end, and `orelse` makes
  that a usage error.
- `std.meta.stringToEnum(Color, value)` finds the enum tag with that name and returns `?Color`. The
  parser needs no list of valid colors: adding a tag to `Color` is enough.
- `eql` is a two-line helper to keep the `if` chain readable.

The limit: **options must come before PATTERN**. In `seek fox -n file`, the loop stops at `fox`,
so `-n` becomes a PATH. Most Unix tools allow options anywhere; `seek` will in
[Chapter 12](12-comptime.md), when we generate the parser at compile time.

### Choosing the search function once: a function pointer

Now `src/search.zig`. With `-i`, every line is searched case-insensitively. Rather than check
`ignore_case` per line, choose the search function once and call it through a **function pointer**
([Chapter 4](04-functions.md)). Add this after `Options`:

```zig
/// ANSI escape sequences: bold red, then back to normal.
const ansi_match = "\x1b[1;31m";
const ansi_reset = "\x1b[0m";

/// A function that returns where `needle` starts in `haystack`, if anywhere.
/// `std.ascii.findIgnoreCase` already has this shape; `findExact` wraps
/// `std.mem.find` to match it.
const FindFn = *const fn (haystack: []const u8, needle: []const u8) ?usize;

fn findExact(haystack: []const u8, needle: []const u8) ?usize {
    return std.mem.find(u8, haystack, needle);
}
```

`std.mem.find` takes the element type first, so it doesn't fit `FindFn`; `findExact` wraps it.
`std.ascii.findIgnoreCase` already fits.

Add a `find` field to `Searcher`, after `options`:

```zig
    options: Options,
    /// Picked once in `init` according to -i.
    find: FindFn,
```

and set it in `init`:

```zig
            .options = options,
            .find = if (options.ignore_case) &std.ascii.findIgnoreCase else &findExact,
```

`&` takes a function's address. Both branches are `FindFn`, so the `if` expression is too.
[Chapter 14](14-polymorphism.md) replaces this with something more flexible.

### `Match` gets a `format` method

Replace the `Match` struct with this version, plus a `Highlight` struct before it:

```zig
/// How to highlight the pattern inside a line.
pub const Highlight = struct {
    pattern: []const u8,
    find: FindFn,
};

/// One selected line, ready to print with `{f}`.
pub const Match = struct {
    path: []const u8,
    /// Null unless line numbers were requested (-n).
    line_number: ?usize,
    text: []const u8,
    /// Null means "print the text as is".
    highlight: ?Highlight = null,

    /// Called by the `{f}` format specifier: writes `path:[line:]text`.
    pub fn format(match: Match, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("{s}:", .{match.path});
        if (match.line_number) |n| try w.print("{d}:", .{n});
        if (match.highlight) |h| {
            try writeHighlighted(w, match.text, h);
        } else {
            try w.writeAll(match.text);
        }
    }
};
```

The old `write` method becomes `format`, so a match prints with `{f}`. `line_number` is now
optional: `null` means "don't print it", and the `if` with a capture prints it only when set.

### Highlighting with slices

Below `Match`, add the function that wraps each occurrence in color codes:

```zig
/// Writes `text`, wrapping every occurrence of the pattern in ANSI colors.
fn writeHighlighted(w: *std.Io.Writer, text: []const u8, h: Highlight) std.Io.Writer.Error!void {
    var rest = text;
    // An empty pattern matches everywhere but has nothing to color.
    while (h.pattern.len > 0) {
        const start = h.find(rest, h.pattern) orelse break;
        const end = start + h.pattern.len;
        // The format string is comptime-known, so `++` can splice in the
        // escape codes at compile time.
        try w.print("{s}" ++ ansi_match ++ "{s}" ++ ansi_reset, .{ rest[0..start], rest[start..end] });
        rest = rest[end..];
    }
    try w.writeAll(rest);
}
```

Each round finds the next occurrence in `rest`, writes the text before it, then the occurrence
between the escape codes, and moves `rest` past it. When nothing is found, the remainder is
written as is. It's all slicing: no copies, no allocation.

Terminals read `ESC [ 1 ; 31 m` (`\x1b[1;31m` in Zig) as "bold red" and `ESC [ 0 m` as "back to
normal". Both sides of `++` are comptime-known, so the result is one ordinary format string with
two `{s}` placeholders.

Highlighting uses `h.find`, the search function, so with `-i` it's case-insensitive too and colors
`Fox` as it appears in the line.

The `h.pattern.len > 0` check matters: `find` reports an empty pattern at index 0, so the loop
would never advance.

### Selecting lines: `-v` and `-n`

Finally, update `searchText`:

```zig
    /// Prints every selected line of `text` and returns how many there were.
    /// A line is selected when it contains the pattern, or, with -v, when it
    /// doesn't.
    fn searchText(self: *const Searcher, path: []const u8, text: []const u8) std.Io.Writer.Error!usize {
        // A trailing newline ends the last line; it doesn't start a new one.
        const body = if (std.mem.endsWith(u8, text, "\n")) text[0 .. text.len - 1] else text;

        // Inverted matches have nothing to highlight. `auto` behaves like
        // `never` until Chapter 19 teaches seek to detect a terminal.
        const highlight: ?Highlight = if (self.options.color == .always and !self.options.invert)
            .{ .pattern = self.pattern, .find = self.find }
        else
            null;

        var matches: usize = 0;
        var lines = std.mem.splitScalar(u8, body, '\n');
        var line_number: usize = 1;
        while (lines.next()) |line| : (line_number += 1) {
            const found = self.find(line, self.pattern) != null;
            if (found == self.options.invert) continue;
            const match: Match = .{
                .path = path,
                .line_number = if (self.options.line_numbers) line_number else null,
                .text = line,
                .highlight = highlight,
            };
            try self.stdout.print("{f}\n", .{match});
            matches += 1;
        }
        return matches;
    }
```

`if (found == self.options.invert) continue;` covers both cases. Normally `invert` is `false`, so
lines without a match are skipped. With `-v` it's `true`, so lines with a match are skipped.

The highlight is decided once per file. With `-v` there's nothing to highlight (selected lines
don't contain the pattern). `--color auto` should mean "color if stdout is a terminal"; for now it
acts like `never` until [Chapter 19](19-low-level.md) adds terminal detection.

### Checkpoint

```console
$ zig build
$ ./zig-out/bin/seek -h
usage: seek [OPTIONS] PATTERN [PATH ...]

options:
  -i            ignore case
  -v            select non-matching lines
  -n            show line numbers
  --color WHEN  highlight matches: auto, always, never
  -h, --help    show this help
  --version     show the version
$ ./zig-out/bin/seek -i fox testdata/poem.txt
testdata/poem.txt:The quick brown fox
testdata/poem.txt:A Fox is quick and clever;
testdata/poem.txt:Foxes everywhere!
$ ./zig-out/bin/seek -n -i fox testdata/poem.txt
testdata/poem.txt:1:The quick brown fox
testdata/poem.txt:3:A Fox is quick and clever;
testdata/poem.txt:5:Foxes everywhere!
$ ./zig-out/bin/seek -v -n fox testdata/poem.txt
testdata/poem.txt:2:jumps over the lazy dog.
testdata/poem.txt:3:A Fox is quick and clever;
testdata/poem.txt:4:the dog just sleeps.
testdata/poem.txt:5:Foxes everywhere!
```

`-v fox` keeps `A Fox is quick`: without `-i` the search is case-sensitive.

On a terminal, `--color always` shows matches in bold red. `cat -v` makes the escape codes visible
(`^[` is the escape byte):

```console
$ ./zig-out/bin/seek --color always -i fox testdata/poem.txt | cat -v
testdata/poem.txt:The quick brown ^[[1;31mfox^[[0m
testdata/poem.txt:A ^[[1;31mFox^[[0m is quick and clever;
testdata/poem.txt:^[[1;31mFox^[[0mes everywhere!
$ ./zig-out/bin/seek --color always fox testdata/poem.txt | cat -v
testdata/poem.txt:The quick brown ^[[1;31mfox^[[0m
```

Errors in the options:

```console
$ ./zig-out/bin/seek --color sometimes fox testdata/poem.txt
seek: invalid value 'sometimes' for --color
usage: seek [OPTIONS] PATTERN [PATH ...]
$ echo $?
2
$ ./zig-out/bin/seek --color
seek: --color needs a value
usage: seek [OPTIONS] PATTERN [PATH ...]
$ ./zig-out/bin/seek -- -v testdata/poem.txt
$ echo $?
1
```

After `--`, `-v` is the pattern. No line contains `-v`, so the exit status is 1.

The parser's limit, options after the pattern:

```console
$ ./zig-out/bin/seek fox -n testdata/poem.txt
seek: -n: FileNotFound
testdata/poem.txt:The quick brown fox
$ ./zig-out/bin/seek fox --color
seek: --color: FileNotFound
```

`-n` and `--color` became file names. `-n` is the first PATH, so its error comes before the
match from `testdata/poem.txt`. Chapter 12 fixes the parser.

The complete project at this point is in `project/ch09/`.

## Summary

- A string is a `[]const u8`: bytes, usually UTF-8. Literals are `*const [N:0]u8` and coerce to
  slices. Character literals are `comptime_int` code points.
- Multiline literals start each line with `\\` and escape nothing.
- Use `std.unicode.Utf8View` to walk code points; most searching works on bytes directly.
- `std.mem` searches (`find`, `findScalar`, `count`), compares (`eql`, `startsWith`), trims and
  cuts (`trim`, `cut`, `cutPrefix`) without allocating. In 0.17, `indexOf*` became `find*`.
- `split*` keeps empty fields; `tokenize*` skips them. Both return iterators.
- Building new strings needs an allocator (`std.mem.join`, `concat`, `replaceOwned`, `gpa.print`)
  or a buffer (`std.mem.print`).
- `std.ascii` handles case for ASCII letters only (`toLower`, `eqlIgnoreCase`, `findIgnoreCase`).
- Placeholders: `{[arg][spec]:[fill][align][width].[precision]}`. Format strings are checked at
  compile time.
- `std.fmt.parseInt`/`parseFloat` return `InvalidCharacter` or `Overflow`.
- A `format(self, w: *std.Io.Writer) std.Io.Writer.Error!void` method is called by `{f}`.
- `seek` now has `-i`, `-v`, `-n`, `--color` and `--`, a function pointer chosen once for the
  search, and a `Match.format` method that highlights with ANSI escapes.

## Exercises

1. Write `fn titleCase(buf: []u8, text: []const u8) error{NoSpaceLeft}![]u8` that writes `text` into
   `buf` with every word capitalized (`"the QUICK fox"` → `"The Quick Fox"`) and any run of
   whitespace turned into one space. Test it, including an all-whitespace input and a buffer that's
   too small.

<details><summary>Solution</summary>

```zig
const std = @import("std");

/// Writes `text` into `buf` with the first letter of every word upper-cased
/// and runs of whitespace squeezed to one space. Returns the used part of `buf`.
fn titleCase(buf: []u8, text: []const u8) error{NoSpaceLeft}![]u8 {
    var len: usize = 0;
    var words = std.mem.tokenizeAny(u8, text, &std.ascii.whitespace);
    while (words.next()) |word| {
        const space: usize = if (len > 0) 1 else 0;
        if (len + space + word.len > buf.len) return error.NoSpaceLeft;
        if (space == 1) buf[len] = ' ';
        len += space;
        const out = buf[len..][0..word.len];
        for (out, word) |*o, c| o.* = std.ascii.toLower(c);
        out[0] = std.ascii.toUpper(word[0]);
        len += word.len;
    }
    return buf[0..len];
}

test titleCase {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("The Quick Brown Fox", try titleCase(&buf, "  the QUICK\tbrown\n fox "));
    try std.testing.expectEqualStrings("", try titleCase(&buf, "   "));
    var tiny: [4]u8 = undefined;
    try std.testing.expectError(error.NoSpaceLeft, titleCase(&tiny, "hello"));
}
```

```console
$ zig test title.zig
1/1 title.decltest.titleCase...OK
All 1 tests passed.
```

`tokenizeAny` with `std.ascii.whitespace` (an array, hence the `&`) squeezes whitespace for free,
since tokens are never empty. That also makes `word[0]` safe.

</details>

2. Make a `Duration` struct holding `seconds: u64` with a `format` method that prints `5s`, `1m05s`,
   or `1h02m05s` (minutes and seconds zero-padded after the first unit). Test it with
   `std.testing.expectFmt`.

<details><summary>Solution</summary>

```zig
const std = @import("std");

const Duration = struct {
    seconds: u64,

    pub fn format(d: Duration, w: *std.Io.Writer) std.Io.Writer.Error!void {
        const h = d.seconds / 3600;
        const m = d.seconds / 60 % 60;
        const s = d.seconds % 60;
        if (h > 0) {
            try w.print("{d}h{d:0>2}m{d:0>2}s", .{ h, m, s });
        } else if (m > 0) {
            try w.print("{d}m{d:0>2}s", .{ m, s });
        } else {
            try w.print("{d}s", .{s});
        }
    }
};

pub fn main() void {
    for ([_]u64{ 5, 65, 3600, 3725 }) |secs| {
        std.debug.print("{d:>5} -> {f}\n", .{ secs, Duration{ .seconds = secs } });
    }
}

test "format" {
    try std.testing.expectFmt("1h02m05s", "{f}", .{Duration{ .seconds = 3725 }});
}
```

```console
$ zig run duration.zig
    5 -> 5s
   65 -> 1m05s
 3600 -> 1h00m00s
 3725 -> 1h02m05s
$ zig test duration.zig
1/1 duration.test.format...OK
All 1 tests passed.
```

`expectFmt(expected, format, args)` formats into a buffer and compares, so `format` methods are
easy to test.

</details>

3. Write `fn parseSetting(line: []const u8) !Setting` for lines like `"  width = 80 "`, where
   `Setting` is `struct { key: []const u8, value: u32 }`. Trim spaces and tabs around the key and
   the value. Return `error.MissingEquals` if there's no `=`, `error.EmptyKey` if the key is empty,
   and let `parseInt`'s errors through.

<details><summary>Solution</summary>

```zig
const std = @import("std");

const Setting = struct { key: []const u8, value: u32 };

const ParseError = error{ MissingEquals, EmptyKey } || std.fmt.ParseIntError;

/// Parses a line like "  width = 80 ". The key is a slice of `line`.
fn parseSetting(line: []const u8) ParseError!Setting {
    const key, const value = std.mem.cutScalar(u8, line, '=') orelse return error.MissingEquals;
    const k = std.mem.trim(u8, key, " \t");
    if (k.len == 0) return error.EmptyKey;
    return .{ .key = k, .value = try std.fmt.parseInt(u32, std.mem.trim(u8, value, " \t"), 10) };
}

pub fn main() void {
    const lines = [_][]const u8{ "  width = 80 ", "height=24", "depth", "= 3", "size = big", "x = -1" };
    for (lines) |line| {
        if (parseSetting(line)) |s| {
            std.debug.print("{q} -> {s} = {d}\n", .{ line, s.key, s.value });
        } else |err| {
            std.debug.print("{q} -> {t}\n", .{ line, err });
        }
    }
}
```

```console
$ zig run setting.zig
"  width = 80 " -> width = 80
"height=24" -> height = 24
"depth" -> MissingEquals
"= 3" -> EmptyKey
"size = big" -> InvalidCharacter
"x = -1" -> Overflow
```

`cutScalar` returns a 2-tuple that destructures into `key` and `value`. The result's `key` points
into `line`, so it's valid only as long as `line` is. `{q}` shows the spaces in the input.

</details>

4. **seek:** accept `--color=WHEN` as well as `--color WHEN`, the way many tools do. `--color=` with
   nothing after it should be an invalid value, and `--colorful` should still be an unknown flag.

<details><summary>Solution</summary>

In `parseArgs`, replace the `--color` branch:

```zig
        } else if (eql(arg, "--color") or std.mem.startsWith(u8, arg, "--color=")) {
            const value = std.mem.cutPrefix(u8, arg, "--color=") orelse blk: {
                i += 1;
                break :blk argAt(args, i) orelse {
                    try stderr.print("seek: {s} needs a value\n", .{arg});
                    return error.MissingValue;
                };
            };
            options.color = std.meta.stringToEnum(Color, value) orelse {
                try stderr.print("seek: invalid value '{s}' for --color\n", .{value});
                return error.InvalidValue;
            };
        } else {
```

```console
$ ./zig-out/bin/seek --color=always fox testdata/poem.txt | cat -v
testdata/poem.txt:The quick brown ^[[1;31mfox^[[0m
$ ./zig-out/bin/seek --color= fox testdata/poem.txt
seek: invalid value '' for --color
usage: seek [OPTIONS] PATTERN [PATH ...]
$ ./zig-out/bin/seek --colorful fox testdata/poem.txt
seek: unknown flag '--colorful'
usage: seek [OPTIONS] PATTERN [PATH ...]
```

`cutPrefix` gives the value after `=`, or `null` for plain `--color`, in which case the labeled
block reads the next argument. The error message says `--color` instead of using `arg`, which
might be `--color=sometimes`.

</details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-9--strings-text-and-formatting)
