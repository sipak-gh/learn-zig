# Chapter 20 — Zig's Design Ideals, Idioms, and Next Steps

This last chapter looks back over the course: the Zen of Zig, line by line, tied to code you've
written; the conventions and idioms that make Zig code look like Zig; Zig compared with C, C++,
Rust, and Go; what's still changing before 1.0; and where to learn more. `seek` gets no new code.
It becomes version 1.0.0 and gets a README, and we tour every file, build a release binary, and run
it. [Chapter 19](19-low-level.md) covered the low-level layer. For quick reference later, see
[Appendix A](appendix-a-cheatsheet.md) (syntax) and [Appendix B](appendix-b-project-reference.md)
(`seek`).

## The Zen of Zig

The compiler ships its design ideals as a command:

```console
$ zig zen

 * Communicate intent precisely.
 * Edge cases matter.
 * Favor reading code over writing code.
 * There is an idiomatic way to do it.
 * Runtime crashes are better than bugs.
 * Compile errors are better than runtime crashes.
 * Incremental improvements.
 * Avoid local maximums.
 * Reduce the amount one must remember.
 * Focus on logic, not style.
 * Resource allocation may fail.
 * Resource deallocation must succeed.

Together, we serve the users!
```

The same list closes the language reference. Every line shaped something in this course.

### Communicate intent precisely

Types say what a value may be, so the reader doesn't have to guess.

- `seek`'s exit status is an `enum(u8)` with three named values, not a bare number. `main` turns it
  into a `u8` with `@backingInt` only at the very end.
- `max_count: ?usize = null` says "maybe a limit", with no magic `0` or `-1` for "none".
- Arguments are `[:0]const u8` (the OS gives NUL-terminated strings), but `Searcher` takes
  `[]const u8`: it doesn't need the terminator, so it doesn't ask for one.
- A function that only reads takes `self: *const Searcher`; one that changes state takes
  `*Searcher`. Worker threads get `*const`, so the compiler stops them from writing.

### Edge cases matter

Most of `seek`'s code handles the unusual case.

- An empty pattern matches every line with an empty match. `writeHighlighted` stops on an empty
  match; without that check it loops forever (tested in `output.zig`).
- A line longer than the 64 KiB read buffer takes a slower path in `nextLine` instead of failing.
- `-` means standard input, `--` ends the flags, `-j 0` is treated as `-j 1`.
- The fuzzer found that `*` in the *text* confused the wildcard matcher
  ([Chapter 16](16-testing.md)).

### Favor reading code over writing code

Code is read more often than written, so Zig makes the reader's job easy and the writer's job a bit
longer.

- No hidden allocation: every function that allocates takes an `Allocator`.
- No hidden I/O: every function that touches files or the clock takes an `Io`.
- No hidden control flow: no exceptions, operator overloading, or destructors. `a + b` adds
  numbers; a function call always looks like a call.
- `try` marks every place a function can return early with an error.

### There is an idiomatic way to do it

The standard library repeats a few patterns, and `seek` follows them: `.init(…)` and `.deinit()`,
`.empty`, `*Io.Writer` for output, tagged unions for closed sets of variants. Once you've seen one
`std` type you can guess how the next works. See [Idioms](#idioms) below.

### Runtime crashes are better than bugs

In `debug` and `safe` builds an overflow, a bad index, or a `null` unwrap stops the program with a
stack trace ([Chapter 19](19-low-level.md)). `init.gpa` reports every leak at exit
([Chapter 8](08-memory-and-allocators.md)). `Searcher.deinit` sets `self.* = undefined`, so a use
after `deinit` reads obvious garbage rather than stale data that looks fine. A crash points at the
bug; a wrong answer hides it.

### Compile errors are better than runtime crashes

Better still is a bug the compiler rejects. You saw several:

- Adding `error.Canceled` to `run`'s error set broke the exhaustive `switch` in `main`
  ([Chapter 19](19-low-level.md)).
- A typo in `Options.shorts` is a `@compileError` from `cli.validate`
  ([Chapter 12](12-comptime.md)).
- `dir: Io.Dir = .cwd()` as a field default compiled for Linux but not Windows
  ([Chapter 18](18-build-system.md)).
- Adding a variant to `Printer` makes every `switch` that forgets it fail to compile
  (Exercise 2 below).

### Incremental improvements, and avoid local maximums

`seek` grew one chapter at a time, and every snapshot built and passed its tests. Small steps are
easy to check.

But small steps can lead to a design that's good locally and bad overall; then you step back and
rework it. In [Chapter 9](09-strings-and-formatting.md) `seek` chose a search function through a
function pointer. That worked for two matchers but not for `-W`, which needs extra data (the
pattern and a case flag), so [Chapter 14](14-polymorphism.md) replaced it with the `Matcher` tagged
union. Zig itself works this way: features get removed when a better design appears (see
[Zig before 1.0](#zig-before-10)).

### Reduce the amount one must remember

- One `Searcher` owns the pattern, paths, and stats; one `deinit` frees them all.
- Every `Options` field has a default, so `.{}` is always a complete value and a new flag needs one
  line in one struct.
- `@embedFile("usage.txt")` keeps the help text in one place.
- Error sets are inferred: you write `!void` and the compiler collects the errors.

### Focus on logic, not style

`zig fmt` decides indentation, spacing, and line breaks. Every example and snapshot in this course
passes `zig fmt --check`. Nobody argues about braces, and diffs show only real changes. A trailing
comma in a list tells `zig fmt` to put one item per line.

### Resource allocation may fail; resource deallocation must succeed

These two lines explain the shape of every Zig API that owns memory:

- Allocation returns an error union (`Allocator.Error!T`), and `seek` handles it everywhere with
  `try`. `checkAllAllocationFailures` proved every failure path frees what it should
  ([Chapter 16](16-testing.md)).
- `deinit` returns `void`. Freeing can't fail, so cleanup in `defer` never needs error handling,
  and `defer` and `errdefer` can always run. That's what makes them reliable.

"Together, we serve the users!" is the point: a program that handles its edge cases, fails loudly,
and never leaks is one its users can trust.

## Naming conventions

The compiler doesn't enforce names, but the language reference's style guide and the whole standard
library follow one scheme:

| What | Style | Examples from `seek` |
|------|-------|----------------------|
| Types, type aliases | `TitleCase` | `Searcher`, `Options`, `Matcher`, `ExitCode` |
| Functions that return a `type` | `TitleCase` | `Counter(K)` |
| Other functions and methods | `camelCase` | `searchAll`, `addPath`, `wildcardMatch` |
| Variables holding functions | `camelCase` | `const checkFrost = Reading.isFreezing;` |
| Everything else: variables, constants, fields, parameters | `snake_case` | `line_numbers`, `max_count`, `read_buffer_len` |
| Namespaces (structs with no fields, never instantiated) | `snake_case` | `std.mem`, `std.json`, `cli` |

`examples/ch20/naming.zig`

```zig
//! Zig's naming conventions in one file. The file has no top-level
//! fields, so it is a namespace and its name is snake_case.

const std = @import("std");

/// TitleCase: types and type aliases.
const Celsius = f32;

/// snake_case: constants and variables, even comptime-known ones.
const freezing_point: Celsius = 0;

const Reading = struct {
    // snake_case: fields.
    station_name: []const u8,
    temperature: Celsius,

    // camelCase: functions and methods.
    pub fn isFreezing(reading: Reading) bool {
        return reading.temperature <= freezing_point;
    }
};

/// TitleCase: a function that returns a type.
fn Pair(comptime T: type) type {
    return struct { first: T, second: T };
}

/// camelCase: every other function. Acronyms are ordinary words:
/// `parseCsvLine`, not `parseCSVLine`.
fn parseCsvLine(line: []const u8) Reading {
    var fields = std.mem.splitScalar(u8, line, ',');
    const station_name = fields.first();
    const temperature = std.fmt.parseFloat(Celsius, fields.next().?) catch 0;
    return .{ .station_name = station_name, .temperature = temperature };
}

pub fn main() void {
    const readings: Pair(Reading) = .{
        .first = parseCsvLine("Oslo,-3.5"),
        .second = parseCsvLine("Lisbon,14"),
    };
    // A variable holding a function is callable, so it is camelCase too.
    const checkFrost = Reading.isFreezing;
    for ([_]Reading{ readings.first, readings.second }) |reading| {
        std.debug.print("{s}: {d} freezing={}\n", .{ reading.station_name, reading.temperature, checkFrost(reading) });
    }
    std.debug.print("{s}\n", .{@typeName(Pair(Reading))});
}
```

```console
$ zig run examples/ch20/naming.zig
Oslo: -3.5 freezing=true
Lisbon: 14 freezing=false
naming.Pair(naming.Reading)
```

- **No `SCREAMING_CASE` for constants.** A constant is just a value: `read_buffer_len`, not
  `READ_BUFFER_LEN`. Keep an established outside name (`ENOENT`) when there is one.
- **Acronyms are words**: `XmlParser`, `readU32Be`, `parseCsvLine`.
- **File names**: a file is a struct ([Chapter 1](01-getting-started.md)). With top-level fields it
  *is* a type and is named like one (`Searcher.zig` would hold `Searcher`'s fields at the top
  level). Otherwise it's a namespace in `snake_case`, like all of `seek`'s files: `search.zig` holds
  `Searcher`, `stats.zig` holds `Stats` and `Counter`. Directories are `snake_case`.
- **Don't repeat the namespace.** Readers see the qualified name: `std.json.Value`, not
  `std.json.JsonValue`; `output.Printer`, not `output.OutputPrinter`.
- **Avoid words that say nothing**: `Data`, `Value`, `Context`, `Manager`, `State`, `utils`,
  `misc`. Every type is data; say *which* data.
- **No `_private` prefixes.** Zig has no private fields; document how a field must be used.
  Declarations (`const`, `fn`) are private unless marked `pub`.

## Idioms

`examples/ch20/idioms.zig` packs the idioms `seek` uses into one small type, explained below.

`examples/ch20/idioms.zig`

```zig
//! The idioms that recur in seek, in one small type.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

/// A list of song titles. It owns a copy of every title.
const Playlist = struct {
    titles: std.ArrayList([]const u8),
    total_seconds: u32 = 0,

    /// A declaration of type Playlist, so `.empty` works as a decl literal.
    pub const empty: Playlist = .{ .titles = .empty };

    /// A function returning Playlist, so `.initCapacity(…)` works too.
    pub fn initCapacity(gpa: Allocator, n: usize) Allocator.Error!Playlist {
        // Result location: the struct is built directly in the caller's
        // variable, and `.initCapacity` is inferred from the field's type.
        return .{ .titles = try .initCapacity(gpa, n) };
    }

    /// The allocator is a parameter, not a hidden global, and every
    /// method that allocates says so in its signature.
    pub fn deinit(playlist: *Playlist, gpa: Allocator) void {
        for (playlist.titles.items) |title| gpa.free(title);
        playlist.titles.deinit(gpa);
        playlist.* = undefined;
    }

    pub fn add(playlist: *Playlist, gpa: Allocator, title: []const u8, seconds: u32) Allocator.Error!void {
        const owned = try gpa.dupe(u8, title);
        // If append fails, nobody else will free `owned`.
        errdefer gpa.free(owned);
        try playlist.titles.append(gpa, owned);
        playlist.total_seconds += seconds;
    }

    /// A concrete interface type instead of `anytype`: the signature says
    /// exactly what `w` must be, and the function is compiled once.
    pub fn write(playlist: Playlist, w: *Io.Writer) Io.Writer.Error!void {
        for (playlist.titles.items, 1..) |title, n| try w.print("{d}. {s}\n", .{ n, title });
        try w.print("total: {d}:{d:0>2}\n", .{ playlist.total_seconds / 60, playlist.total_seconds % 60 });
    }
};

test "decl literals, init/deinit, explicit allocator" {
    const gpa = std.testing.allocator;
    var playlist: Playlist = try .initCapacity(gpa, 2);
    defer playlist.deinit(gpa);
    try playlist.add(gpa, "Intro", 90);
    try playlist.add(gpa, "Theme", 155);

    var buffer: [64]u8 = undefined;
    var w: Io.Writer = .fixed(&buffer);
    try playlist.write(&w);
    try std.testing.expectEqualStrings("1. Intro\n2. Theme\ntotal: 4:05\n", w.buffered());
}

fn fillPlaylist(gpa: Allocator) !void {
    var playlist: Playlist = .empty;
    defer playlist.deinit(gpa);
    try playlist.add(gpa, "Intro", 90);
    try playlist.add(gpa, "Theme", 155);
    try playlist.add(gpa, "Outro", 60);
}

test "errdefer: no leak, whichever allocation fails" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, fillPlaylist, .{});
}
```

```console
$ zig test examples/ch20/idioms.zig
1/2 idioms.test.decl literals, init/deinit, explicit allocator...OK
2/2 idioms.test.errdefer: no leak, whichever allocation fails...OK
All 2 tests passed.
```

### Decl literals

Write the type once, on the left, and let `.name` find the declaration in that type
([Chapter 7](07-structs-enums-unions.md)):

```zig
var playlist: Playlist = .empty;                   // Playlist.empty
var playlist: Playlist = try .initCapacity(gpa, 2); // Playlist.initCapacity(gpa, 2)
```

`seek` uses them everywhere: `var searcher: Searcher = try .init(…)`,
`var group: Io.Group = .init`, `.initStreaming(.stdout(), …)`. Two naming conventions:

- `.empty` (or `.init` without parentheses) is a constant for a ready-to-use value that owns
  nothing yet. `std.ArrayList` and the unmanaged hash maps have `.empty`.
- `.init(…)` is a function, for when creating the value needs arguments or can fail.

### `init` and `deinit` in pairs

Every type that owns a resource has a `deinit`. Call it with `defer` on the line right after
creating the value, so the pair is visible at a glance:

```zig
var searcher: Searcher = try .init(gpa, io, pattern, options, stdout, stderr);
defer searcher.deinit();
```

`deinit` takes a pointer (`*Playlist`), frees what the value owns, and ends with
`self.* = undefined`. In `debug` and `safe` builds that fills the value with `0xaa` bytes, so a use
after `deinit` looks obviously wrong.

### Explicit allocators and `Io`

A function that allocates takes an `Allocator`; one that does I/O takes an `Io`. Most `std`
containers don't even store the allocator: you pass it to every method that allocates
(`titles.append(gpa, …)`, `titles.deinit(gpa)`). It costs a parameter and buys:

- Signatures that say what a function can do. `Matcher.find` takes neither, so it can't allocate,
  read files, or block.
- Caller-chosen strategy. `seek`'s workers give `searchReader` an arena reset after each file; the
  tests pass `std.testing.allocator` and a temporary directory.
- Tests that inject failures (`checkAllAllocationFailures`) and fake I/O.

`seek` stores `gpa` and `io` in the `Searcher` because almost every method needs them. That's fine:
the `init` call still shows them.

### Result location

`return .{ … }` builds the struct directly where the caller wants it, with the type inferred from
the return type ([Chapter 7](07-structs-enums-unions.md)). Nested literals work the same way: in
`.{ .titles = try .initCapacity(gpa, n) }`, `.initCapacity` is looked up in the type of `titles`.
Remember Chapter 7's gotcha: in `x = .{ .a = x.b, .b = x.a }` the first field is written before
the second is read, so it doesn't swap.

### `anytype` only where you need it

`anytype` accepts anything and checks it only when the function is compiled for that type
([Chapter 13](13-generics.md)). The signature tells the reader nothing, and every new type compiles
a new copy. Prefer:

- A concrete type, or an interface type like `*Io.Writer` (`Playlist.write`, `Printer.line`).
- `comptime T: type` when the code really is generic (`Counter(K)`, `cli.parse(T)`).

`seek` has one `anytype`: the private helper `writeJson(w, value: anytype)` in `output.zig`, which
passes `value` to the also-generic `std.json.fmt`. Private and tiny is the right place for it.

### `errdefer` discipline

Use `errdefer` when a function has acquired something and a later step can still fail. The caller
then gets a complete result or an error with nothing leaked.

- `Playlist.add` and `Searcher.addFile`: the copied string is freed if `append` fails.
- `cli.parse`: the positional list is freed if a later flag is bad.
- `Counter.topN`: the entries are freed if `toOwnedSlice` fails.

`checkAllAllocationFailures` runs `fillPlaylist` once per allocation, failing a different one each
time. Delete the `errdefer` line and it reports the leak, pointing at the failed allocation
(trimmed):

```console
$ zig test idioms.zig
1/2 idioms.test.decl literals, init/deinit, explicit allocator...OK
2/2 idioms.test.errdefer: no leak, whichever allocation fails...
fail_index: 1/4
allocated bytes: 5
freed bytes: 0
allocations: 1
deallocations: 0
allocation that was made to fail: 
…/std/array_list.zig:1375:56: 0x1257371 in ensureTotalCapacityPrecise (std.zig)
…
idioms.zig:33:35: 0x12568d2 in add (idioms.zig)
        try playlist.titles.append(gpa, owned);
                                  ^
…
1 passed; 0 skipped; 1 failed.
1 errors were logged.
1 tests leaked memory.
```

The 5 leaked bytes are `"Intro"`, copied before `append` failed.

### Comptime generics instead of macros

For the same code over several types, write a function that takes or returns a `type`:
`Counter(K)` picks a hash map at compile time, and `cli.parse(T)` turns any options struct into a
flag parser. No preprocessor or template language: ordinary Zig, run by the compiler
([Chapter 12](12-comptime.md), [Chapter 13](13-generics.md)).

## Zig compared with C, C++, Rust, and Go

| | C | C++ | Rust | Go | Zig |
|-|---|-----|------|----|-----|
| Memory | `malloc`/`free` | RAII, destructors, smart pointers | ownership and borrow checker | garbage collector | explicit allocators, `defer`/`errdefer` |
| Errors | return codes, `errno` | exceptions | `Result<T, E>` and `?` | `error` values, `if err != nil` | error unions, `try`, return traces |
| Generics | macros, `void *` | templates | traits and generics | type parameters | `comptime` parameters and type functions |
| Metaprogramming | preprocessor | templates, `constexpr` | macros | code generation | `comptime`: ordinary Zig run by the compiler |
| Hidden control flow | macros | operator overloading, exceptions, destructors | operator overloading, `Drop` | `panic`/`recover`, `defer` | none |
| Safety checks | none by default | none by default | compile-time ownership; overflow checked in debug builds | bounds and `nil` checks, data race detector (`-race`) | bounds, overflow, `null`, casts in `debug`/`safe` builds |
| Concurrency | threads (library) | threads, atomics | threads, `async`; data races rejected at compile time | goroutines, channels | `std.Io` (async, groups, queues), threads, atomics |
| Talking to C | — | `extern "C"` | `extern` blocks, bindgen | cgo | `extern`, `export`, C translation, `zig cc` |
| Build tool | make, CMake, … | make, CMake, … | Cargo | `go` tool | `zig build`, written in Zig |

In practice:

- **From C:** the same control (pointers, layout, no runtime), plus slices with lengths, error
  unions instead of `errno`, `defer`, real generics, safety checks you can turn off, and a build
  system and cross-compiler in one binary. Zig can compile your C code and call it directly
  ([Chapter 19](19-low-level.md)).
- **From C++:** no exceptions, destructors, operator overloading, or inheritance; what you read is
  what runs. Generics are plain functions evaluated at compile time, not a separate template
  language.
- **From Rust:** no borrow checker. Use after free, double free, and data races are *your* job;
  safe builds and the `SafeAllocator` catch many of them at run time, not compile time. In return,
  the language is much smaller and comptime replaces traits and macros.
- **From Go:** no garbage collector or runtime scheduler. You manage memory, and concurrency goes
  through `std.Io` ([Chapter 15](15-concurrency.md)). Errors are values, as in Go: `try` is
  `if err != nil { return err }` in one word, with a free return trace.

## Zig before 1.0

Zig isn't 1.0 yet. The language is close to final, but each release still changes things, the
standard library most. This course targets **exactly Zig 0.17.0**; code for 0.15 or 0.16 often
doesn't compile, and this course's code may not compile on 0.18.

The last three releases show the pace:

- **0.15** replaced the old readers and writers with the buffered `std.Io.Reader` and
  `std.Io.Writer` interfaces, and removed `usingnamespace`.
- **0.16** made I/O an interface, `std.Io`, passed to every function that does I/O; gave `main` its
  `std.process.Init` parameter; and replaced `@Type` with `@Int`, `@Struct`, `@Enum`, and friends.
- **0.17** made the changes below.

| Change in 0.17 | Instead write |
|--------|---------------|
| `@cImport` removed | `extern fn`, or the C translation in the build system ([Chapter 19](19-low-level.md)) |
| Array multiplication `[1]u8{0} ** 4` removed | `const zeros: [4]u8 = @splat(0);` |
| `errdefer \|err\|` capture removed | a wrapper function that `catch`es the error |
| `std.heap.DebugAllocator` deprecated | `std.heap.SafeAllocator` |
| `std.fmt.allocPrint(gpa, …)` deprecated | `gpa.print(…)` |
| `OptimizeMode` with `.ReleaseSafe` etc. renamed | `std.lang.Optimize` with `.safe` etc. |

Removed syntax doesn't always give a helpful error. Old code using `**`:

```text
old.zig:4:28: error: binary operator '*' has whitespace on one side, but not the other
    const zeros = [1]u8{0} ** 4;
                           ^
```

Deprecated names usually keep working for a release or two, but not everywhere. Comparing against
an old enum name fails even though the alias exists:

```text
old3.zig:4:37: error: no field named 'ReleaseSafe' in enum 'lang.Optimize'
    if (@import("builtin").mode == .ReleaseSafe) std.debug.print("safe\n", .{});
                                   ~^~~~~~~~~~~
```

### Reading release notes

Every release has notes at `https://ziglang.org/download/<version>/release-notes.html`. When you
upgrade:

1. Read **Language Changes** completely. It's short, and each entry has an upgrade guide with a
   diff.
2. Skim **Standard Library**, especially **Deprecations**, for the APIs you use.
3. Read **Build System** if your `build.zig` does more than the basics.
4. Build, then fix errors one at a time. Most are renames the notes describe.

The notes end with a **Roadmap**: completing and stabilizing the language, the compiler's own
backends, the linker, package management, and a standard library audit.

### Reading the standard library source

For API questions, the `std` source is the most reliable answer: it's exactly the code you compile
against, and it ships with the compiler. `zig env` prints where:

```console
$ zig env
.{
    .zig_exe = "…/zig-x86_64-linux-0.17.0/zig",
    .lib_dir = "…/zig-x86_64-linux-0.17.0/lib",
    .std_dir = "…/zig-x86_64-linux-0.17.0/lib/std",
    .global_cache_dir = "…/.cache/zig",
    .version = "0.17.0",
    …
```

Finding your way:

- The layout follows the names: `std.mem` is `std/mem.zig`, `std.Io.Writer` is
  `std/Io/Writer.zig`, `std.json` is `std/json.zig` plus `std/json/`.
- Search for the declaration: `grep -n "pub fn findScalar" std/mem.zig`.
- Read the doc comments (`///`) and the `test` blocks below a function; the tests are working
  examples.
- Search for `Deprecated` to find the new name of an old function:

```console
$ cd …/zig-x86_64-linux-0.17.0/lib
$ grep -n -B1 'pub const ReleaseSafe' std/lang.zig
126-    /// Deprecated, to be removed after 0.18.0
127:    pub const ReleaseSafe: @This() = .safe;
$ grep -n -A3 'pub fn allocPrint(' std/fmt.zig
625:pub fn allocPrint(gpa: Allocator, comptime fmt: []const u8, args: anytype) Allocator.Error![]u8 {
626-    return gpa.print(fmt, args);
627-}
628-
```

`zig std` starts a local web server with searchable docs generated from the same source and opens
it in your browser. With ZLS, the Zig language server, your editor can jump to `std` definitions.

## Where to go next

- **The language reference** for your version: `https://ziglang.org/documentation/0.17.0/`, also
  shipped with the compiler as `doc/langref.html`. It's one long page; read it end to end once.
- **The standard library docs**: `https://ziglang.org/documentation/0.17.0/std/` or `zig std`.
- **The standard library source**: the best collection of idiomatic Zig there is. Read next:
  `std/array_list.zig`, `std/hash_map.zig`, `std/Io/Writer.zig`, `std/json/`.
- **The compiler repository**: `https://codeberg.org/ziglang/zig`, whose issue tracker is where
  language proposals are discussed and decided.
- **ziglang.org/learn**: a language overview, the design rationale, code samples, and a build
  system guide.
- **The community**: the Ziggit forum (`https://ziggit.dev`) is a good place to ask questions.
- **Build something.** Ideas:
  - Extend `seek`: regular expressions, context lines (`-A`/`-B`), `.gitignore` support, searching
    compressed files with `std.compress`.
  - Write a small HTTP client or server with `std.http`.
  - Write a C library in Zig with `export`, or cross-compile an existing C project with `zig cc`.
  - Port a small tool you use every day.

## Building seek: version 1.0.0

`seek` is finished. This step changes no code: it sets the version to 1.0.0 and adds a README.
Then we tour the code, build a release binary, and run it.

### `build.zig.zon`

Change `.version` and add `README.md` to `.paths`:

```zig
.{
    .name = .seek,
    .version = "1.0.0",
    .fingerprint = 0xd438fe97ff756a7e, // Changing this has security and trust implications.
    .minimum_zig_version = "0.17.0",
    .dependencies = .{},
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
        "bench",
        "README.md",
    },
}
```

Keep your own fingerprint, generated for your project in [Chapter 18](18-build-system.md).
`build.zig` reads `.version` from this file, so `--version` changes with no code change. `.paths`
lists the files in the package when someone depends on `seek`; it doesn't affect your own builds.

### `README.md` (new)

````markdown
# seek

A small, fast, grep-like search tool, written in Zig 0.17.0 while working
through *Learn Zig by Building seek*.

```
usage: seek [OPTIONS] PATTERN [PATH ...]
```

seek prints every line under PATH that contains PATTERN. Directories are
searched recursively (hidden files and binary files are skipped), several
files are searched in parallel, and the output is always in sorted path order.

## Build

```sh
zig build                       # debug build: zig-out/bin/seek
zig build -Doptimize=safe       # optimized, with safety checks kept
zig build -Dversion=1.2.3       # override the version that --version prints
zig build -Dtarget=x86_64-windows
zig build test                  # run the tests
zig build bench                 # time the zero-byte scanners
```

## Examples

```sh
seek fox testdata                   # lines containing "fox"
seek -i -n fox testdata             # ignore case, show line numbers
seek -W '*the*dog*' testdata        # wildcard matched against the whole line
seek -c --glob '*.txt' fox .        # count matches in .txt files only
seek --json -l fox testdata         # JSON Lines: one object per file
seek --stats -j 4 fox testdata      # 4 worker threads, summary on stderr
```

Run `seek --help` for every option.

Exit status: 0 if a line was selected, 1 if not, 2 if there was trouble.

## Source map

| File             | What it does                                            |
|------------------|---------------------------------------------------------|
| `src/main.zig`   | entry point: arguments → `run` → exit code              |
| `src/cli.zig`    | `Options` and the comptime-generated flag parser & help |
| `src/match.zig`  | `Matcher` (literal, ignore-case, wildcard)              |
| `src/search.zig` | `Searcher`: path walking, worker threads, ordered output |
| `src/output.zig` | `Printer`: text, count, file-name and JSON output       |
| `src/stats.zig`  | generic `Counter` and the `--stats` summary             |
| `src/bytes.zig`  | SIMD zero-byte scan for binary detection                |
| `src/usage.txt`  | the top of `--help`, embedded with `@embedFile`         |
| `bench/bench.zig`| `zig build bench`                                       |
````

### A tour of the code

How a run flows through the files:

```text
main.zig   main(init)          stdout/stderr writers, exit code
  │
  └─ run(gpa, io, args, …)
       ├─ cli.parse(Options, …)        cli.zig     flags → Options + positionals
       ├─ Searcher.init(…)             search.zig  copies the pattern
       │    ├─ Matcher.init(…)         match.zig   literal | ignore_case | wildcard
       │    └─ Printer.init(…)         output.zig  lines | count | files | json
       ├─ searcher.addPath(path) …     search.zig  walk directories, skip hidden, --glob, sort
       ├─ searcher.searchAll()         search.zig
       │    ├─ N × worker()            (Io.Group)  take the next file index (atomic counter)
       │    │    └─ searchFile → searchReader
       │    │         ├─ looksBinary   bytes.zig   SIMD scan for a zero byte
       │    │         ├─ nextLine                  split on '\n', long lines too
       │    │         ├─ Matcher.find
       │    │         └─ Printer.line / fileDone → that file's own output buffer
       │    └─ main thread: wait for file 0, 1, 2, … in order → stdout, stats.record
       └─ stats.write(…)               stats.zig   --stats summary → stderr
```

The files, in reading order:

| File | Lines | What to look at |
|------|------:|-----------------|
| `src/main.zig` | 122 | `main` sets up buffered writers and maps errors to exit codes; `run` is the whole program in about 60 lines. `help` is one string built at compile time from `usage.txt` and `cli.help(Options)`. |
| `src/cli.zig` | 301 | `Options` is the single source of truth for flags. `parse` loops over the fields with `inline for`; `validate` turns mistakes in `shorts` and `descriptions` into compile errors. |
| `src/match.zig` | 179 | `Matcher` is a tagged union; `find` returns a `?Span`. `matchWildcard` is one function compiled twice (`comptime ignore_case`). Table-driven tests and a fuzz test. |
| `src/search.zig` | 476 | `Searcher` owns everything. `addPath`/`addDirectory` build a sorted list of files; `searchAll` and `worker` search in parallel and print in order; `nextLine` handles lines longer than the buffer. End-to-end tests use a temporary directory. |
| `src/output.zig` | 219 | `Printer` is a tagged union of output modes. `Match.format` makes `{f}` work; `writeHighlighted` adds color; `writeJson` uses `std.json`. Tests use a fixed `Io.Writer`. |
| `src/stats.zig` | 170 | `Counter(K)` is a type function that chooses a hash map at compile time; `Stats` uses `Counter([]const u8)` for the top files. |
| `src/bytes.zig` | 52 | `containsZero` checks a `@Vector` of bytes per step; `containsZeroScalar` is the plain version. |
| `src/usage.txt` | 5 | The top of `--help`, embedded with `@embedFile`. |
| `bench/bench.zig` | 60 | Times the zero-byte scanners on 64 MiB with the `awake` clock. |
| `build.zig` | 66 | `seek`, `run`, `test`, and `bench` steps; the `version` option becomes `@import("build_options")`. |
| `build.zig.zon` | 14 | Package name, version, fingerprint, minimum Zig version. |

That's 1716 lines including the README; the seven `.zig` files in `src/` hold 1519 of them, with 25
tests. [Appendix B](appendix-b-project-reference.md) maps every concept in the course to where it
appears in this code.

### Checkpoint

```console
$ zig build test --summary all
Build Summary: 4/4 steps succeeded; 25/25 tests passed
test success
+- run test 25 pass (25 total) 19ms MaxRSS:6M
   +- compile test debug native success 403ms MaxRSS:168M
      +- options success

$ zig build
$ ./zig-out/bin/seek --version
seek 1.0.0
```

Now the release build. `safe` keeps every safety check and optimizes the rest, the right default
for a tool like `seek`: fast, and a bug still stops with a message instead of printing wrong
results.

```console
$ rm -rf zig-out
$ zig build -Doptimize=safe
$ ./zig-out/bin/seek --version
seek 1.0.0
$ wc -c < zig-out/bin/seek
4536736
```

A sample session with the release binary, first on the test data:

```console
$ ./zig-out/bin/seek fox testdata
testdata/notes/log.txt:2024-01-01 saw a fox near the barn
testdata/notes/log.txt:2024-01-03 fox tracks in the snow
testdata/notes/todo.md:- feed the fox
testdata/poem.txt:The quick brown fox
$ ./zig-out/bin/seek -i -n fox testdata
testdata/notes/log.txt:1:2024-01-01 saw a fox near the barn
testdata/notes/log.txt:3:2024-01-03 fox tracks in the snow
testdata/notes/todo.md:2:- feed the fox
testdata/poem.txt:1:The quick brown fox
testdata/poem.txt:3:A Fox is quick and clever;
testdata/poem.txt:5:Foxes everywhere!
$ ./zig-out/bin/seek -W '*the*dog*' testdata
testdata/notes/todo.md:- walk the dog
testdata/poem.txt:jumps over the lazy dog.
testdata/poem.txt:the dog just sleeps.
$ ./zig-out/bin/seek -c --glob '*.txt' fox testdata
testdata/notes/log.txt:2
testdata/poem.txt:1
$ ./zig-out/bin/seek --json -l fox testdata
{"path":"testdata/notes/log.txt"}
{"path":"testdata/notes/todo.md"}
{"path":"testdata/poem.txt"}
$ ./zig-out/bin/seek --hidden -l fox testdata
testdata/.secret.txt
testdata/notes/log.txt
testdata/notes/todo.md
testdata/poem.txt
$ ./zig-out/bin/seek zebra testdata; echo "exit $?"
exit 1
$ ./zig-out/bin/seek fox nope.txt testdata/poem.txt; echo "exit $?"
seek: nope.txt: FileNotFound
testdata/poem.txt:The quick brown fox
exit 2
```

Then on its own source. Where does `seek` use `errdefer`, how many public functions does each file
have, and where is that one `anytype`?

```console
$ ./zig-out/bin/seek -n errdefer src
src/cli.zig:90:    errdefer positionals.deinit(gpa);
src/match.zig:135:        errdefer std.debug.print("pattern \"{s}\", text \"{s}\"\n", .{ case.pattern, case.text });
src/search.zig:117:        errdefer self.gpa.free(path);
src/stats.zig:55:            errdefer entries.deinit(gpa);
$ ./zig-out/bin/seek -c --glob '*.zig' 'pub fn' src
src/bytes.zig:2
src/cli.zig:2
src/main.zig:1
src/match.zig:4
src/output.zig:4
src/search.zig:4
src/stats.zig:8
$ ./zig-out/bin/seek --stats -l anytype src
src/output.zig
--- stats ---
files searched: 8
files matched:  1
matching lines: 1
elapsed:        1.072ms
top files:
     1  src/output.zig
$ ./zig-out/bin/seek --json -n -m 1 Searcher src/main.zig
{"path":"src/main.zig","line":4,"text":"const Searcher = @import(\"search.zig\").Searcher;"}
```

The `elapsed` time and binary size differ on your machine. The `--stats` summary goes to stderr,
after the results.

### Design choices and known limitations

All deliberate; some match `grep`, some are left as exercises.

```console
$ ./zig-out/bin/seek -c dog testdata
testdata/notes/log.txt:0
testdata/notes/todo.md:1
testdata/poem.txt:2
$ ./zig-out/bin/seek fox testdata/poem.txt testdata/poem.txt
testdata/poem.txt:The quick brown fox
testdata/poem.txt:The quick brown fox
$ ./zig-out/bin/seek '' testdata/notes/todo.md
testdata/notes/todo.md:# TODO
testdata/notes/todo.md:- feed the fox
testdata/notes/todo.md:- walk the dog
testdata/notes/todo.md:- fix the fence
$ ./zig-out/bin/seek -n '-' testdata/notes/todo.md
testdata/notes/todo.md:2:- feed the fox
testdata/notes/todo.md:3:- walk the dog
testdata/notes/todo.md:4:- fix the fence
$ ./zig-out/bin/seek -n -- '- f' testdata/notes/todo.md
testdata/notes/todo.md:2:- feed the fox
testdata/notes/todo.md:4:- fix the fence
$ printf 'a fox\r\nno\r\n' | ./zig-out/bin/seek fox - | cat -v
(standard input):a fox^M
```

- `-c` prints a count for every file, zero included, like `grep -c`.
- A path given twice is searched twice.
- The empty pattern matches every line.
- A lone `-` is a valid pattern: only arguments starting with `-` *and* longer than one character
  are flags. A pattern like `- f` needs `--` first.
- `seek` splits lines on `\n` only, so Windows (CRLF) files keep their `\r`.

When stdout can't be written (a full disk, or a pipe whose reader has gone away), `main` returns
`error.WriteFailed`. A `debug` build prints a return trace; `safe` prints just the error line.
Either way the exit status is 1, not the 2 that `seek` uses for trouble it reports itself:

```console
$ ./zig-out/bin/seek fox testdata/poem.txt > /dev/full; echo "exit $?"
error: WriteFailed
exit 1
```

Exercise 1 fixes that.

The complete project at this point is in `project/ch20/`.

## Summary

- The Zen of Zig (`zig zen`) explains the language: precise types, handled edge cases, readable
  code, loud failures, compile errors before crashes, and allocation that may fail but
  deallocation that can't.
- Names: `TitleCase` for types and type functions, `camelCase` for other functions, `snake_case`
  for everything else, including constants and namespaces. Acronyms are words. Don't repeat the
  namespace in a name.
- Idioms: decl literals (`.empty`, `.init(…)`), `init`/`deinit` pairs with `defer`, allocators and
  `Io` as parameters, `return .{ … }`, interfaces or `comptime T` instead of `anytype`, `errdefer`
  right after each acquisition.
- Compared with C, C++, Rust, and Go: no hidden control flow or allocation, no GC, no borrow
  checker, comptime instead of macros and templates, runtime safety checks chosen per build.
- Before 1.0, every release changes things. Read the release notes' Language Changes and
  Deprecations, and answer API questions from the `std` source (`zig env` shows where).
- `seek` 1.0.0: 1519 lines of Zig in seven files, 25 tests, built with `-Doptimize=safe`.

## Exercises

1. Make `seek` exit with status 2, without a return trace, when stdout can't be written:
   `seek fox testdata/poem.txt > /dev/full` and `seek fox big.txt | head -2` should both end with
   `exit 2`. Only `main` needs to change.

   <details><summary>Solution</summary>

   `run` can return `error.WriteFailed`, and so can the final `stdout.flush()`. Handle both in
   `main` (`src/main.zig`):

   ```zig
       const status = run(init.gpa, init.io, args[1..], stdout, stderr) catch |err| switch (err) {
           error.UnknownFlag,
           error.MissingValue,
           error.InvalidValue,
           error.MissingPattern,
           => blk: {
               try stderr.writeAll(usage);
               break :blk .trouble;
           },
           // stdout is gone (a full disk, a closed pipe): there is nobody to
           // print to, so just report trouble.
           error.WriteFailed => return @backingInt(ExitCode.trouble),
           error.OutOfMemory, error.Canceled => |e| return e,
       };
       stdout.flush() catch return @backingInt(ExitCode.trouble);
       try stderr.flush();
       return @backingInt(status);
   ```

   ```console
   $ ./zig-out/bin/seek fox testdata/poem.txt > /dev/full; echo "exit $?"
   exit 2
   $ seq 1 200000 | sed 's/$/ fox/' > big.txt
   $ ./zig-out/bin/seek fox big.txt | head -2; echo "exit ${PIPESTATUS[0]}"
   big.txt:1 fox
   big.txt:2 fox
   exit 2
   ```

   `head` exits after two lines, so `seek`'s next write fails. (`PIPESTATUS[0]` is bash's exit
   status of the first command in the pipe.)

   </details>

2. Add `-q`/`--quiet`: print nothing, only set the exit status (0 if any line matched). Add a
   `quiet` variant to `Printer` *first* and build, and let the compiler tell you what else to
   change.

   <details><summary>Solution</summary>

   In `src/cli.zig`, add the field after `files_only`, its short flag, and its description:

   ```zig
       files_only: bool = false,
       quiet: bool = false,
       max_count: ?usize = null,
   ```

   ```zig
           .files_only = 'l',
           .quiet = 'q',
   ```

   ```zig
           .files_only = "print only names of files with selected lines",
           .quiet = "print nothing; only set the exit status",
   ```

   In `src/output.zig`, add the variant and choose it first in `init`:

   ```zig
       /// -l: print the names of files with a selected line.
       files,
       /// -q: print nothing.
       quiet,
   ```

   ```zig
       pub fn init(options: Options, matcher: Matcher) Printer {
           if (options.quiet) return .quiet;
   ```

   Now `zig build` lists every `switch` that forgot the new variant:

   ```text
   src/output.zig:56:9: error: switch must handle all possibilities
           switch (printer) {
           ^~~~~~
   src/output.zig:23:5: note: unhandled enumeration value: 'quiet'
       quiet,
       ^~~~~
   …
   src/output.zig:75:9: error: switch must handle all possibilities
           switch (printer) {
           ^~~~~~
   src/output.zig:23:5: note: unhandled enumeration value: 'quiet'
       quiet,
       ^~~~~
   ```

   Handle it in `line` and `fileDone`:

   ```zig
               .count, .files, .quiet => {},
   ```

   ```zig
               .lines, .quiet => {},
   ```

   One selected line per file answers the question, so in `searchReader` (`src/search.zig`) stop
   early like `-l` does:

   ```zig
           const limit: usize = if (self.options.files_only or self.options.quiet) 1 else self.options.max_count orelse std.math.maxInt(usize);
   ```

   ```console
   $ ./zig-out/bin/seek -q fox testdata; echo "exit $?"
   exit 0
   $ ./zig-out/bin/seek -q zebra testdata; echo "exit $?"
   exit 1
   $ ./zig-out/bin/seek -q fox nope testdata/poem.txt; echo "exit $?"
   seek: nope: FileNotFound
   exit 2
   $ ./zig-out/bin/seek -h | grep quiet
     -q, --quiet                    print nothing; only set the exit status
   ```

   Errors still go to stderr, as with `grep -q`. The flag parser and `--help` needed no change:
   they're generated from `Options`.

   </details>

3. Rename these declarations to follow Zig's conventions, and say why:
   `const MAX_DEPTH = 8;`, `fn Parse_Header(...) Header`, `const json_parser = struct { depth: u8 };`,
   `fn makeList(comptime T: type) type`, `const HTTPClient = struct { ... };`,
   `std.json.JsonValue`.

   <details><summary>Solution</summary>

   | Before | After | Rule |
   |--------|-------|------|
   | `MAX_DEPTH` | `max_depth` | a constant is a value: `snake_case` |
   | `Parse_Header` | `parseHeader` | a function that doesn't return a type: `camelCase` |
   | `json_parser` | `JsonParser` | a struct with fields is a type: `TitleCase` |
   | `makeList` | `List` (or `MakeList`) | returns a `type`: `TitleCase`; the noun reads better |
   | `HTTPClient` | `HttpClient` | acronyms are ordinary words |
   | `std.json.JsonValue` | `std.json.Value` | don't repeat the namespace |

   </details>

4. Old Zig code (0.15 or earlier) uses `std.mem.indexOfScalar` and `std.fmt.allocPrint`. Using
   only the `std` source that came with your compiler, find out: do they still compile in 0.17.0,
   and what should new code use instead?

   <details><summary>Solution</summary>

   ```console
   $ cd …/zig-x86_64-linux-0.17.0/lib
   $ grep -n -B1 'pub const indexOfScalar =' std/mem.zig
   1283-/// Deprecated in favor of `findScalar`.
   1284:pub const indexOfScalar = findScalar;
   $ grep -n -B1 'pub fn allocPrint(' std/fmt.zig
   624-/// Deprecated in favor of `Allocator.print`.
   625:pub fn allocPrint(gpa: Allocator, comptime fmt: []const u8, args: anytype) Allocator.Error![]u8 {
   ```

   Both still compile as deprecated aliases. New code should use `std.mem.findScalar` and
   `gpa.print(fmt, args)`. Deprecated names are removed in a later release, so update them when
   you see them.

   </details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-20--zigs-design-ideals-idioms-and-next-steps)
