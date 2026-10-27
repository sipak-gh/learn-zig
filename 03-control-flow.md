# Chapter 3 — Control Flow

Zig has few control-flow tools: `if`, `while`, `for`, `switch`, and labeled blocks. Most are
expressions that can produce values. There's no `goto` and no hidden jumps. In `seek`, you'll
read the command line, handle `--version` and `--help`, and return real exit statuses.
[Chapter 2](02-values-and-types.md) gave `seek` its constants; [Chapter 4](04-functions.md) splits
it into functions and runs the first search.

## `if` and `else`

The condition must be a `bool`. `if (count)` with an integer is an error
(`expected type 'bool', found 'u32'`); write `if (count != 0)`.

`examples/ch03/if_else.zig`

```zig
const std = @import("std");

pub fn main() void {
    var temperature: i32 = 18;
    temperature += 0; // a runtime value

    if (temperature > 25) {
        std.debug.print("hot\n", .{});
    } else if (temperature > 15) {
        std.debug.print("mild\n", .{});
    } else {
        std.debug.print("cold\n", .{});
    }

    // `if` is also an expression that produces a value.
    const coat = if (temperature < 20) "yes" else "no";
    std.debug.print("coat: {s}\n", .{coat});

    // Without braces, the body is a single statement.
    if (temperature == 18) std.debug.print("exactly 18\n", .{});
}
```

```console
$ zig run examples/ch03/if_else.zig
mild
coat: yes
exactly 18
```

`if` as an expression replaces C's `cond ? a : b`; Zig has no ternary operator.

An `if` that produces a value needs an `else`. Without it, the "no" branch has type `void`, and
the branches don't match:

```text
no_else.zig:5:18: error: incompatible types: '*const [3:0]u8' and 'void'
    const coat = if (t < 20) "yes";
                 ^~~~~~~~~~~~~~~~~
```

Logical operators are `and`, `or`, and `!` ("not"). `and` and `or` short-circuit.

## `while`

`while` repeats while its condition is `true`. It has two optional extras:

- A **continue expression** after a colon: `while (i < 10) : (i += 1)`. It runs after every
  iteration, even ones cut short by `continue`. The `i++` of a C `for` loop goes here.
- An **`else` branch**, which runs when the condition becomes false, but not after a `break`.

`examples/ch03/while_loops.zig`

```zig
const std = @import("std");

pub fn main() void {
    // The plain form: repeat while the condition holds.
    var n: u32 = 1;
    while (n < 100) {
        n *= 3;
    }
    std.debug.print("first power of 3 >= 100: {d}\n", .{n});

    // A continue expression runs after each iteration, even after `continue`.
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        if (i % 3 != 0) continue;
        std.debug.print("{d} ", .{i});
    }
    std.debug.print("\n", .{});

    // `else` runs when the condition becomes false, but not after `break`.
    var j: u32 = 0;
    const found = while (j < 5) : (j += 1) {
        if (j * j == 9) break true;
    } else false;
    std.debug.print("found a square of 9 below 5: {}\n", .{found});
}
```

```console
$ zig run examples/ch03/while_loops.zig
first power of 3 >= 100: 243
0 3 6 9 
found a square of 9 below 5: true
```

The last loop is an expression. `break true` gives the loop the value `true`; if it ends without
a `break`, the `else` gives `false`. This "search with a fallback" pattern is common.

- `break` leaves the loop; `break value` leaves it with a value.
- `continue` jumps to the next iteration (running the continue expression first).
- `while (true) { ... }` loops forever. Leave it with `break` or `return`.

Another form, `while (it.next()) |item|`, unwraps optional values. You'll use it in
[Chapter 4](04-functions.md); [Chapter 5](05-errors-and-optionals.md) explains it.

## `for`

`for` walks over arrays, slices, and ranges. The `|x|` after the parentheses is a **capture**
that names the current element.

`examples/ch03/for_loops.zig`

```zig
const std = @import("std");

pub fn main() void {
    // An array literal (Chapter 6 covers arrays and slices in depth).
    var scores = [_]u32{ 70, 85, 92 };

    // Iterate over the elements.
    var total: u32 = 0;
    for (scores) |s| {
        total += s;
    }
    std.debug.print("total: {d}\n", .{total});

    // Iterate over a range: 0, 1, 2, 3 (the end is excluded).
    for (0..4) |k| {
        std.debug.print("{d} ", .{k});
    }
    std.debug.print("\n", .{});

    // Several objects at once: here, the elements and a counter from 1.
    for (scores, 1..) |s, rank| {
        std.debug.print("#{d}: {d}\n", .{ rank, s });
    }

    // Capture a pointer with |*s| to change the elements in place.
    for (&scores) |*s| {
        s.* += 5;
    }
    std.debug.print("curved: {any}\n", .{scores});
}
```

```console
$ zig run examples/ch03/for_loops.zig
total: 247
0 1 2 3 
#1: 70
#2: 85
#3: 92
curved: { 75, 90, 97 }
```

| Form | Meaning |
|------|---------|
| `for (items) \|x\|` | each element, as a copy |
| `for (0..n) \|i\|` | the integers `0` to `n - 1` (type `usize`) |
| `for (items, 0..) \|x, i\|` | element and index together |
| `for (a, b) \|x, y\|` | two sequences side by side; lengths must match |
| `for (&items) \|*x\|` | a pointer to each element, to modify it |
| `for (items) \|_\|` | repeat once per element, ignoring it |

Things to know:

- **Captures are constants.** `s += 5` inside `for (scores) |s|` gives
  `error: cannot assign to constant`. To change elements, capture a pointer with `|*s|` and write
  through `s.*`. [Chapter 6](06-arrays-slices-pointers.md) covers pointers.
- **Pointer captures need something addressable.** Loop over `&scores`, not `scores`:

  ```text
  ptr_capture.zig:4:19: error: pointer capture of non pointer type '[3]u32'
      for (scores) |*s| {
                    ^~~
  ptr_capture.zig:4:10: note: consider using '&' here
  ```

- **Unused captures are errors**, like unused variables: `error: unused capture`. Use `|_|`.
- **Lengths must match** in a multi-object loop. For arrays the compiler checks
  (`error: non-matching for loop lengths`); for slices, safe builds check at run time. An open
  range like `0..` or `1..` takes its length from the other objects.
- `for` has `else`, `break`, and `continue` too, with the same rules as `while`.

There's no C-style `for (init; cond; step)`. Use a range `for` or a `while` with a continue
expression.

## Labeled loops and blocks

`break` and `continue` act on the innermost loop. To reach an outer one, give it a **label** and
name it: `break :outer`, `continue :outer`.

A **labeled block** produces a value: `break :label value` leaves the block with that value. Use
one to compute a value with several statements.

`examples/ch03/labeled.zig`

```zig
const std = @import("std");

pub fn main() void {
    // Find the first pair (a, b) with a * b == 12 and a < b.
    outer: for (1..5) |a| {
        for (1..13) |b| {
            if (a >= b) continue; // next b
            if (a * b == 12) {
                std.debug.print("found {d} * {d}\n", .{ a, b });
                break :outer; // leave both loops
            }
        }
    }

    // `continue :outer` jumps to the next iteration of the outer loop.
    rows: for (0..3) |row| {
        for (0..3) |col| {
            if (col > row) continue :rows;
            std.debug.print("({d},{d}) ", .{ row, col });
        }
    }
    std.debug.print("\n", .{});

    // A labeled block is an expression: `break :label value` gives its value.
    var x: i32 = -4;
    x += 0;
    const magnitude = blk: {
        if (x < 0) break :blk -x;
        break :blk x;
    };
    std.debug.print("magnitude: {d}\n", .{magnitude});
}
```

```console
$ zig run examples/ch03/labeled.zig
found 1 * 12
(0,0) (1,0) (1,1) (2,0) (2,1) (2,2) 
magnitude: 4
```

Any identifier can be a label; `blk` is the usual one for blocks. A labeled block must end with a
`break :label`: there's no "last expression is the value" rule.

## `switch`

`switch` picks one prong by value. It's usually an expression.

`examples/ch03/switch.zig`

```zig
const std = @import("std");

pub fn main() void {
    for ([_]u8{ 'a', 'Z', '7', ' ', '?' }) |c| {
        // switch is an expression; every prong produces a string here.
        const kind = switch (c) {
            'a'...'z' => "lowercase", // a range, inclusive at both ends
            'A'...'Z' => "uppercase",
            '0'...'9' => "digit",
            ' ', '\t', '\n' => "whitespace", // several values
            else => "other", // everything not listed above
        };
        std.debug.print("'{c}' is {s}\n", .{ c, kind });
    }

    // Prongs can run a block of code. No fallthrough, no `break` needed.
    var status: u8 = 2;
    status += 0;
    switch (status) {
        0 => std.debug.print("matched\n", .{}),
        1 => std.debug.print("no match\n", .{}),
        2 => {
            std.debug.print("trouble\n", .{});
            std.debug.print("(status 2)\n", .{});
        },
        else => std.debug.print("unknown status\n", .{}),
    }

    // Without `else`, every possible value must be handled. A u2 has four.
    var bits: u2 = 3;
    bits += 0;
    const name = switch (bits) {
        0 => "zero",
        1 => "one",
        2 => "two",
        3 => "three",
    };
    std.debug.print("bits: {s}\n", .{name});
}
```

```console
$ zig run examples/ch03/switch.zig
'a' is lowercase
'Z' is uppercase
'7' is digit
' ' is whitespace
'?' is other
trouble
(status 2)
bits: three
```

| Prong | Matches |
|-------|---------|
| `5 =>` | one value |
| `1, 3, 5 =>` | any of several values |
| `'a'...'z' =>` | a range; note **three** dots, and both ends included |
| `else =>` | everything else |

The rules:

- **Exhaustive.** Every possible value must be covered, by prongs or by `else`. Remove the `3`
  prong above and the program doesn't compile:

  ```text
  no_three.zig:5:18: error: switch must handle all possibilities
      const name = switch (bits) {
                   ^~~~~~
  ```

  This matters most with enums ([Chapter 7](07-structs-enums-unions.md)): add an enum value and
  the compiler lists every `switch` that forgot it.
- **No overlap.** Each value may appear in one prong only. `'a'` as a vowel and also inside
  `'a'...'z'` gives `error: duplicate switch value '97'` (97 is the code of `a`).
- **No fallthrough.** Exactly one prong runs; there's no `break` to forget.
- **Prong values must be comptime-known.** A runtime variable can't be a case.

### Strings: use `std.mem.eql`, not `==` or `switch`

A string is a slice of bytes, `[]const u8` ([Chapter 6](06-arrays-slices-pointers.md)). `==`
doesn't compare slice contents, and `switch` doesn't accept strings. Both are compile errors:

```text
str_eq.zig:4:17: error: cannot compare strings with ==
    if (args[0] == "--help") std.debug.print("help\n", .{});
        ~~~~~~~~^~~~~~~~~~~
```

```text
str_switch.zig:5:9: error: cannot switch on strings
        "--help" => std.debug.print("help\n", .{}),
        ^~~~~~~~
```

Compare contents with `std.mem.eql(u8, a, b)`. The `u8` says "these are slices of bytes".

`examples/ch03/strings_equal.zig`

```zig
const std = @import("std");

pub fn main() void {
    const flags = [_][]const u8{ "--help", "-v", "--version", "--color" };
    for (flags) |flag| {
        // Strings are compared byte by byte with std.mem.eql, not `==`.
        if (std.mem.eql(u8, flag, "--help") or std.mem.eql(u8, flag, "-h")) {
            std.debug.print("{s}: show help\n", .{flag});
        } else if (std.mem.eql(u8, flag, "--version")) {
            std.debug.print("{s}: show version\n", .{flag});
        } else {
            std.debug.print("{s}: unknown\n", .{flag});
        }
    }
}
```

```console
$ zig run examples/ch03/strings_equal.zig
--help: show help
-v: unknown
--version: show version
--color: unknown
```

An `if`/`else if` chain of `std.mem.eql` calls is fine for a few strings. For many, a
compile-time lookup table (`std.StaticStringMap`) can map strings to enum values to `switch` on.
See [Chapter 10](10-containers.md).

## `unreachable`

`unreachable` tells the compiler "this can't happen". If it happens anyway, that's illegal
behavior: a panic in Debug and ReleaseSafe builds, undefined behavior in ReleaseFast and
ReleaseSmall.

`examples/ch03/unreachable.zig`

```zig
const std = @import("std");

pub fn main() void {
    for (0..6) |i| {
        // `i % 3` is always 0, 1 or 2; the `else` can't happen.
        const word = switch (i % 3) {
            0 => "fizz",
            1 => "buzz",
            2 => "boom",
            else => unreachable,
        };
        std.debug.print("{d}: {s}\n", .{ i, word });
    }
}
```

```console
$ zig run examples/ch03/unreachable.zig
0: fizz
1: buzz
2: boom
3: fizz
4: buzz
5: boom
```

`i % 3` is a `usize`, so the switch needs an `else` to be exhaustive; `unreachable` documents
that it can't happen. If you're wrong (say you delete the `2` prong), a safe build tells you:

```text
0: fizz
1: buzz
thread 282347 panic: reached unreachable code
…/unreachable_bug.zig:9:21: 0x11e93e7 in main (unreachable_bug.zig)
            else => unreachable,
                    ^
```

Use `unreachable` only for the truly impossible. Anything bad input can cause is an error to
handle ([Chapter 5](05-errors-and-optionals.md)).

## A preview: `inline for`

Some loops must run at compile time, such as a loop over a list of *types*, which don't exist at
run time. `inline for` makes the compiler unroll the loop: one copy of the body per item.

`examples/ch03/inline_for.zig`

```zig
const std = @import("std");

pub fn main() void {
    // A list of types. Types only exist at compile time, so the loop over
    // them must be unrolled by the compiler: `inline for`.
    inline for (.{ u8, i16, u32, f64 }) |T| {
        std.debug.print("{s}: {d} bits\n", .{ @typeName(T), @bitSizeOf(T) });
    }
}
```

```console
$ zig run examples/ch03/inline_for.zig
u8: 8 bits
i16: 16 bits
u32: 32 bits
f64: 64 bits
```

`inline while` exists too. Don't use `inline` to make ordinary loops "faster"; the compiler
already unrolls when it helps. [Chapter 12](12-comptime.md) shows where inline loops belong.

## Building seek: arguments and exit statuses

`seek` now reads its command line. The rules:

| Command line | Behavior | Exit status |
|--------------|----------|-------------|
| contains `--version` anywhere | print `seek 0.1.0` | 0 |
| contains `-h` or `--help` anywhere | print the usage line on stdout | 0 |
| no PATTERN | print the usage line on **stderr** | 2 |
| otherwise | print the pattern and each path | 1 (nothing matched yet) |

Replace `src/main.zig` with:

`src/main.zig`

```zig
const std = @import("std");

const version = "0.1.0";

const exit_ok: u8 = 0; // a line matched (or nothing went wrong)
const exit_no_match: u8 = 1; // nothing matched
const exit_trouble: u8 = 2; // bad usage or an error

const usage = "usage: seek [OPTIONS] PATTERN [PATH ...]\n";

// Returning `u8` from main sets the process exit status.
pub fn main(init: std.process.Init) !u8 {
    // The arena lives as long as the process, so it is a good home for the
    // argument list. args[0] is the program name.
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), init.io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    // --version and --help win wherever they appear on the command line.
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--version")) {
            try stdout.print("seek {s}\n", .{version});
            try stdout.flush();
            return exit_ok;
        }
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try stdout.writeAll(usage);
            try stdout.flush();
            return exit_ok;
        }
    }

    // Without a PATTERN there is nothing to do: complain on stderr.
    if (args.len < 2) {
        try stderr.writeAll(usage);
        try stderr.flush();
        return exit_trouble;
    }

    const pattern = args[1];
    try stdout.print("pattern: {s}\n", .{pattern});
    for (args[2..], 1..) |path, n| {
        try stdout.print("path {d}: {s}\n", .{ n, path });
    }
    try stdout.flush();
    return exit_no_match; // we don't search yet, so nothing can match
}
```

What's new:

- **`main` returns `!u8`.** The `u8` becomes the exit status; the `!` still means "or an error".
  If `main` returns an error, Zig prints it and exits with status 1.
- **Reading arguments.** `init.minimal.args` holds the raw command line. `toSlice` turns it into
  a slice of strings, which needs memory. `init.arena.allocator()` gives memory that lives until
  the process exits, which suits the argument list. [Chapter 8](08-memory-and-allocators.md)
  explains allocators; for now, "the arena" is "memory freed for you at exit".
- **`args[0]` is the program name.** `args[1]` is the first real argument, `args[1..]` is
  everything from index 1 on, and `args[2..]` is every PATH. Slicing is
  [Chapter 6](06-arrays-slices-pointers.md)'s topic.
- **The argument type.** Each argument is a `[:0]const u8`: a string followed by a zero byte, as
  the OS provides it. It works anywhere a `[]const u8` is expected. Chapter 6 explains the `:0`.
- **`for (args[2..], 1..) |path, n|`** walks the paths with a counter starting at 1.
- **A second writer for stderr.** Errors and usage complaints go to stderr, so they don't mix
  with real output when stdout goes to a file or pipe.
- **Early returns.** `--version` and `--help` are checked first, in their own loop, so they win
  wherever they appear: `seek fox --help` shows help.
- **`usage` is a file-scope constant** because two places print it.

### Seeing the exit status

The shell keeps the last exit status in `$?` (PowerShell: `$LASTEXITCODE`).

```console
$ ./zig-out/bin/seek fox
pattern: fox
$ echo $?
1
```

The checkpoint below writes the status as `[exit N]` after each command.

### `zig build run` and non-zero exit statuses

`zig build run` treats a non-zero exit status as a **failed build step**. `seek` exits with 1
when nothing matches, which is normal, but the build system reports a failure:

```console
$ zig build run -- fox poem.txt
pattern: fox
path 1: poem.txt
run
+- run exe seek failure
error: process exited with code 1
failed command: ./zig-out/bin/seek fox poem.txt

Build Summary: 3/5 steps succeeded (1 failed)
run transitive failure
+- run exe seek failure

[exit 1]
```

From now on, for anything that may exit non-zero, build with `zig build` and run the binary
directly: `./zig-out/bin/seek …` (Windows: `zig-out\bin\seek.exe …`).

### Checkpoint

```console
$ zig build
$ ./zig-out/bin/seek fox poem.txt notes.md
pattern: fox
path 1: poem.txt
path 2: notes.md
[exit 1]
$ ./zig-out/bin/seek fox
pattern: fox
[exit 1]
$ ./zig-out/bin/seek
usage: seek [OPTIONS] PATTERN [PATH ...]
[exit 2]
$ ./zig-out/bin/seek --version
seek 0.1.0
[exit 0]
$ ./zig-out/bin/seek fox --help
usage: seek [OPTIONS] PATTERN [PATH ...]
[exit 0]
```

`poem.txt` and `notes.md` needn't exist yet; `seek` doesn't open them. The complete project at
this point is in `project/ch03/`.

## Summary

- `if` needs a `bool`. `if (c) a else b` is an expression; there's no `?:`.
- `while (cond) : (step) { ... } else { ... }`: the continue expression runs every iteration;
  `else` runs when the loop ends without `break`.
- `for` walks arrays, slices, and ranges (`0..n`, end excluded). Walk several at once with
  `for (a, 0..) |x, i|`. Captures are constants; use `for (&a) |*x|` to modify elements.
- `break value` and `else` make loops into expressions. Labels (`outer:`, `blk:`) let `break`
  and `continue` target outer loops and blocks.
- `switch` must be exhaustive, has no fallthrough, and supports `a, b`, `x...y`, and `else`.
- Strings can't be compared with `==` or used in a `switch`. Use `std.mem.eql(u8, a, b)`.
- `unreachable` asserts "impossible". If reached, safe builds panic.
- `inline for` unrolls a loop at compile time, for things like lists of types.
- `main` can return `u8` to set the exit status. `zig build run` treats non-zero as failure, so
  run `./zig-out/bin/seek` directly.

## Exercises

1. Print FizzBuzz for 1 to 15: "Fizz" for multiples of 3, "Buzz" for multiples of 5,
   "FizzBuzz" for both, and the number otherwise.

   <details><summary>Solution</summary>

   ```zig
   const std = @import("std");

   pub fn main() void {
       for (1..16) |n| {
           if (n % 15 == 0) {
               std.debug.print("FizzBuzz\n", .{});
           } else if (n % 3 == 0) {
               std.debug.print("Fizz\n", .{});
           } else if (n % 5 == 0) {
               std.debug.print("Buzz\n", .{});
           } else {
               std.debug.print("{d}\n", .{n});
           }
       }
   }
   ```

   ```console
   $ zig run fizzbuzz.zig
   1
   2
   Fizz
   4
   Buzz
   Fizz
   7
   8
   Fizz
   Buzz
   11
   Fizz
   13
   14
   FizzBuzz
   ```

   The range is `1..16` because the end is excluded. `n` is a `usize`, which is unsigned, so `%`
   works without `@rem` or `@mod`.

   </details>

2. Count the vowels, consonants, and other characters in `"Hello, World 42!"` using `switch`.
   Watch out for overlapping prongs.

   <details><summary>Solution</summary>

   ```zig
   const std = @import("std");

   pub fn main() void {
       const text = "Hello, World 42!";
       var vowels: u32 = 0;
       var consonants: u32 = 0;
       var others: u32 = 0;
       for (text) |c| {
           switch (c) {
               'a'...'z', 'A'...'Z' => switch (std.ascii.toLower(c)) {
                   'a', 'e', 'i', 'o', 'u' => vowels += 1,
                   else => consonants += 1,
               },
               else => others += 1,
           }
       }
       std.debug.print("vowels={d} consonants={d} others={d}\n", .{ vowels, consonants, others });
   }
   ```

   ```console
   $ zig run vowels.zig
   vowels=3 consonants=7 others=6
   ```

   One switch with a vowel prong *and* `'a'...'z'` fails with `duplicate switch value`, because
   the letters overlap. A nested `switch` keeps each value in exactly one prong. `for (text)`
   works on a string literal because the literal is a pointer to an array.

   </details>

3. Find the index of a number in `[_]i32{ 4, 8, 15, 16, 23, 42 }` with a `for` loop used as an
   expression. If it's missing, the loop should produce `items.len`. Try 15 and 7.

   <details><summary>Solution</summary>

   ```zig
   const std = @import("std");

   pub fn main() void {
       const items = [_]i32{ 4, 8, 15, 16, 23, 42 };
       for ([_]i32{ 15, 7 }) |target| {
           const index = for (items, 0..) |x, i| {
               if (x == target) break i;
           } else items.len;
           if (index == items.len) {
               std.debug.print("{d}: not found\n", .{target});
           } else {
               std.debug.print("{d}: at index {d}\n", .{ target, index });
           }
       }
   }
   ```

   ```console
   $ zig run find.zig
   15: at index 2
   7: not found
   ```

   `break i` gives the loop its value; `else items.len` covers "never broke".
   [Chapter 5](05-errors-and-optionals.md) shows a cleaner "maybe a value" type: `?usize`.

   </details>

4. The Collatz rule: if `n` is even, halve it; otherwise, make it `3n + 1`. Count the steps from
   27 to 1. Use a `while` with a continue expression and an `if` expression.

   <details><summary>Solution</summary>

   ```zig
   const std = @import("std");

   pub fn main() void {
       var n: u64 = 27;
       var steps: u32 = 0;
       while (n != 1) : (steps += 1) {
           n = if (n % 2 == 0) n / 2 else 3 * n + 1;
       }
       std.debug.print("27 reaches 1 after {d} steps\n", .{steps});
   }
   ```

   ```console
   $ zig run collatz.zig
   27 reaches 1 after 111 steps
   ```

   </details>

5. Make `seek` accept `-V` as a short form of `--version`.

   <details><summary>Solution</summary>

   Change the first check in the `for (args[1..])` loop:

   ```zig
   if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-V")) {
   ```

   ```console
   $ zig build
   $ ./zig-out/bin/seek fox -V
   seek 0.1.0
   [exit 0]
   $ ./zig-out/bin/seek -v
   pattern: -v
   [exit 1]
   ```

   Lowercase `-v` isn't an option yet, so it's taken as the PATTERN; `seek` rejects unknown flags
   from [Chapter 5](05-errors-and-optionals.md) on. Undo this change before Chapter 4 so your code
   matches the snapshots.

   </details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-3--control-flow)
