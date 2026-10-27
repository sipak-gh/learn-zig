# Chapter 16 — Testing

Testing is built into Zig: a test is ordinary Zig code placed next to the code it checks. This
chapter covers `test` blocks, `std.testing`, leak and allocation-failure checks, temporary
directories, in-memory writers, filtering, skipping, and fuzzing. `seek` gets 22 tests, and the
fuzzer finds a real matcher bug that slipped in while this course was written.
[Chapter 15](15-concurrency.md) made the search concurrent; [Chapter 17](17-json.md) adds JSON
output.

## `test` blocks and `zig test`

A `test` block can go anywhere a declaration can (top of a file, inside a struct). Its body is a
function returning `anyerror!void`; returning an error fails the test.

`examples/ch16/basics.zig`

```zig
const std = @import("std");
const testing = std.testing;

/// Returns the largest value in `items`, or null if it is empty.
fn max(items: []const i32) ?i32 {
    if (items.len == 0) return null;
    var best = items[0];
    for (items[1..]) |item| best = @max(best, item);
    return best;
}

// A test named with a string.
test "max finds the largest value" {
    try testing.expect(max(&.{ 3, 9, 2 }).? == 9);
    try testing.expectEqual(9, max(&.{ 3, 9, 2 }));
    try testing.expectEqual(null, max(&.{}));
}

// A test named after a declaration: a "doctest".
test max {
    try testing.expectEqual(-1, max(&.{ -5, -1, -3 }));
}

fn parseAge(text: []const u8) !u8 {
    const age = try std.fmt.parseInt(u8, text, 10);
    if (age > 150) return error.TooOld;
    return age;
}

test "parseAge" {
    try testing.expectEqual(42, try parseAge("42"));
    try testing.expectError(error.TooOld, parseAge("200"));
    try testing.expectError(error.InvalidCharacter, parseAge("4x"));
}

test "strings, slices and formatting" {
    try testing.expectEqualStrings("fox", "the fox"[4..]);
    try testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, &[_]u8{ 1, 2, 3 });
    try testing.expectFmt("[  42]", "[{d:>4}]", .{42});
}
```

```console
$ zig test examples/ch16/basics.zig
1/4 basics.test.max finds the largest value...OK
2/4 basics.decltest.max...OK
3/4 basics.test.parseAge...OK
4/4 basics.test.strings, slices and formatting...OK
All 4 tests passed.
```

- `zig test file.zig` builds the file in **test mode** (a test runner becomes `main`) and runs it.
  The binary goes to Zig's cache, not your folder.
- In a terminal the runner erases each passing `OK` line, so you may see only
  `All 4 tests passed.` Piped or redirected output keeps them.
- Normal builds (`zig build`, `zig run`) skip test blocks, so tests cost your program nothing.
- `test max { … }` is named after the declaration `max` (`decltest.max`). Doc tools show it as a
  usage example of `max`, hence **doctest**. The name must exist: `test nothere {}` fails with
  `error: use of undeclared identifier 'nothere'`.

Tests live in the same file so they can call private (non-`pub`) helpers and stay next to the code
they describe. No framework, no naming convention.

### The `std.testing` helpers

Each helper returns an error on failure, so call it with `try`.

| Helper | Checks |
|--------|--------|
| `expect(ok)` | `ok` is true |
| `expectEqual(expected, actual)` | equal values (`==` for simple types; field by field for structs, unions, arrays, optionals) |
| `expectEqualStrings(expected, actual)` | equal strings; prints a diff on failure |
| `expectEqualSlices(T, expected, actual)` | equal slices of `T` element by element |
| `expectError(err, result)` | `result` is the error `err` |
| `expectFmt(expected, fmt, args)` | formatting `args` with `fmt` gives `expected` |
| `expectApproxEqAbs(a, b, tolerance)` | floats differ by at most `tolerance` |
| `expectStringStartsWith` / `expectStringEndsWith` | prefix / suffix |

Gotchas:

- **Expected goes first**, or the message `expected 8, found 9` lies. Both sides get a common type
  (peer type resolution, as in `if` branches), so a bare `9` or `.never` works on the left.
- `expectEqual` on slices compares pointers and lengths, not contents. Use `expectEqualStrings` or
  `expectEqualSlices`.
- `expectEqual(9, max(…))` compares with a `?i32`, so it means "not null and equal to 9". Check
  for null with `expectEqual(null, …)`.

### What a failure looks like

`examples/ch16/failing_test.zig`

```zig
const std = @import("std");
const testing = std.testing;

fn double(x: i32) i32 {
    return x + x + 1; // bug!
}

test "double" {
    try testing.expectEqual(8, double(4));
}

test "greeting" {
    try testing.expectEqualStrings("hello, fox", "hello, dog");
}

test "this one passes" {
    try testing.expect(true);
}
```

```console
$ zig test examples/ch16/failing_test.zig
1/3 failing_test.test.double...expected 8, found 9
FAIL (TestExpectedEqual)
…/lib/std/testing.zig:93:17: 0x1258504 in expectEqualInner__func_996 (std.zig)
                return error.TestExpectedEqual;
                ^
…/lib/std/testing.zig:57:5: 0x1258586 in expectEqual (failing_test.zig)
    return expectEqualInner(T, expected, actual);
    ^
…/examples/ch16/failing_test.zig:9:5: 0x12585cd in test.double (failing_test.zig)
    try testing.expectEqual(8, double(4));
    ^
2/3 failing_test.test.greeting...
====== expected this output: =========
hello, fox␃

======== instead found this: =========
hello, dog␃

======================================
First difference occurs on line 1:
expected:
hello, fox
       ^ ('\x66')
found:
hello, dog
       ^ ('\x64')
FAIL (TestExpectedEqual)
…/lib/std/testing.zig:696:9: 0x1254835 in expectEqualStrings (std.zig)
        return error.TestExpectedEqual;
        ^
…/examples/ch16/failing_test.zig:13:5: 0x1254963 in test.greeting (failing_test.zig)
    try testing.expectEqualStrings("hello, fox", "hello, dog");
    ^
3/3 failing_test.test.this one passes...OK
1 passed; 0 skipped; 2 failed.
error: the following test command failed with exit code 1:
…/.cache/zig/o/33ccab726e250d401bb8e7060f4c5e02/test --seed=0x237fb065
```

(Paths shortened with `…`; addresses, hashes and the seed differ on your machine.)

- One failure doesn't stop the other tests. The runner prints an **error return trace**: the chain
  of `try`s the error passed through, ending at your test line.
- `expectEqualStrings` ends each string with `␃` (so trailing whitespace shows) and points at the
  first differing byte.
- Any failure makes the command exit with status 1.

## Leak detection with `std.testing.allocator`

`std.testing.allocator` is a general-purpose allocator with safety checks. After each test the
runner looks for unfreed memory; a leak fails the run and shows where it was allocated.

`examples/ch16/leak_demo.zig`

```zig
const std = @import("std");
const testing = std.testing;

/// Returns "<name>!" in new memory. The caller owns the result.
fn shout(gpa: std.mem.Allocator, name: []const u8) ![]u8 {
    return gpa.print("{s}!", .{name});
}

test "shout" {
    const gpa = testing.allocator;
    const text = try shout(gpa, "fox");
    // Oops: no `defer gpa.free(text);`
    try testing.expectEqualStrings("fox!", text);
}
```

```console
$ zig test examples/ch16/leak_demo.zig
1/1 leak_demo.test.shout...OK
[SafeAllocator] (err): leaked [addr: 78ea943220a0, len: 4 (0x4) align: 1] allocated at: 
…/lib/std/mem/Allocator.zig:512:27: 0x1254be2 in print__func_958 (std.zig)
    return aw.toOwnedSlice();
                          ^
…/examples/ch16/leak_demo.zig:6:21: 0x12545e6 in shout (leak_demo.zig)
    return gpa.print("{s}!", .{name});
                    ^
…/examples/ch16/leak_demo.zig:11:27: 0x1254960 in test.shout (leak_demo.zig)
    const text = try shout(gpa, "fox");
                          ^
… (test runner and start-up frames)
(additional stack frames may have been skipped...)

All 1 tests passed.
1 errors were logged.
1 tests leaked memory.
error: the following test command failed with exit code 1:
…/test --seed=0xe6fe66d9
```

The test passed (`OK`) but the run fails: `1 tests leaked memory.` Add `defer gpa.free(text);`
after the `try shout(…)` line to fix it.

Always use `testing.allocator` in tests. Code under test takes an `Allocator` parameter
([Chapter 8](08-memory-and-allocators.md)), so the test picks the allocator: a payoff of passing
allocators explicitly.

## Testing every allocation failure

Any allocation can fail with `error.OutOfMemory`; the code must then free what it already
allocated, usually with `errdefer`. Those paths almost never run, so their bugs hide.
`std.testing.checkAllAllocationFailures` runs them all:

1. It calls your function once and counts its allocations (say *N*).
2. It calls it *N* more times; run *i* fails allocation number *i*.
3. Every run must succeed or return `error.OutOfMemory`, and none may leak.

`examples/ch16/alloc_failures.zig`

```zig
const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

/// Two owned copies of strings.
const Pair = struct {
    first: []u8,
    second: []u8,

    fn init(gpa: Allocator, first: []const u8, second: []const u8) Allocator.Error!Pair {
        const a = try gpa.dupe(u8, first);
        // If the second copy fails, nobody else can free the first one.
        errdefer gpa.free(a);
        const b = try gpa.dupe(u8, second);
        return .{ .first = a, .second = b };
    }

    fn deinit(pair: Pair, gpa: Allocator) void {
        gpa.free(pair.first);
        gpa.free(pair.second);
    }
};

/// The code under test. Its first parameter must be the allocator.
fn makePair(gpa: Allocator, first: []const u8, second: []const u8) !void {
    const pair: Pair = try .init(gpa, first, second);
    defer pair.deinit(gpa);
    try testing.expectEqualStrings(first, pair.first);
}

test "Pair.init cleans up when an allocation fails" {
    // Runs makePair once normally, counting allocations, then once more
    // for each allocation with that allocation failing.
    try testing.checkAllAllocationFailures(testing.allocator, makePair, .{ "fox", "dog" });
}
```

```console
$ zig test examples/ch16/alloc_failures.zig
1/1 alloc_failures.test.Pair.init cleans up when an allocation fails...OK
All 1 tests passed.
```

The function you pass must:

- take the `Allocator` as its **first** parameter (the other arguments go in the tuple,
  `.{ "fox", "dog" }`);
- return `!void`;
- allocate the same way on every run.

Now delete the `errdefer gpa.free(a);` line and run again:

```console
$ zig test examples/ch16/alloc_failures.zig
1/1 alloc_failures.test.Pair.init cleans up when an allocation fails...
fail_index: 1/2
allocated bytes: 3
freed bytes: 0
allocations: 1
deallocations: 0
allocation that was made to fail: 
…/lib/std/mem/Allocator.zig:481:40: 0x1070aee in dupe__func_109 (std.zig)
    const new_buf = try allocator.alloc(T, m.len);
                                       ^
…/examples/ch16/alloc_failures.zig:13:31: 0x125a6f3 in init (alloc_failures.zig)
        const b = try gpa.dupe(u8, second);
                              ^
…/examples/ch16/alloc_failures.zig:25:33: 0x12548b4 in makePair (alloc_failures.zig)
    const pair: Pair = try .init(gpa, first, second);
                                ^
… (more frames, then FAIL (MemoryLeakDetected) and a leak report for the first dupe)
0 passed; 0 skipped; 1 failed.
1 errors were logged.
1 tests leaked memory.
error: the following test command failed with exit code 1:
…/test --seed=0xadac0c82
```

There are 2 allocations (`/2`). The run that failed index 1 (counting from 0), the second `dupe`,
leaked the 3 bytes of `"fox"`: 3 allocated, 0 freed. Without this test you'd need a real
out-of-memory situation to see the bug.

## Temporary directories

File system tests shouldn't depend on your project's files or leave files behind.
`std.testing.tmpDir` creates a fresh directory under `.zig-cache/tmp/` and returns a `TmpDir`: work
in its `dir` field (an `Io.Dir`); `cleanup()` deletes it and everything inside. `std.testing.io`
is an `Io` for tests.

`examples/ch16/tmp_dir.zig`

```zig
const std = @import("std");
const testing = std.testing;
const Io = std.Io;

/// Counts the lines of the file at `path` in `dir`.
fn countLines(io: Io, dir: Io.Dir, path: []const u8) !usize {
    var buffer: [256]u8 = undefined;
    const file = try dir.openFile(io, path, .{});
    defer file.close(io);
    var file_reader = file.reader(io, &buffer);
    var lines: usize = 0;
    while (try file_reader.interface.takeDelimiter('\n')) |_| lines += 1;
    return lines;
}

test "countLines" {
    const io = testing.io; // an Io for tests
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup(); // deletes the directory and everything in it

    try tmp.dir.createDirPath(io, "sub");
    try tmp.dir.writeFile(io, .{ .sub_path = "sub/three.txt", .data = "a\nb\nc\n" });
    try testing.expectEqual(3, try countLines(io, tmp.dir, "sub/three.txt"));
    try testing.expectError(error.FileNotFound, countLines(io, tmp.dir, "nope.txt"));
}
```

```console
$ zig test examples/ch16/tmp_dir.zig
1/1 tmp_dir.test.countLines...OK
All 1 tests passed.
```

The key design choice: `countLines` takes the directory as a parameter instead of using
`Io.Dir.cwd()`, so the test can point it at the temporary directory. `seek` needs the same change
below. (`tmpDir` creates `.zig-cache/` in the current directory if missing; it's safe to delete.)

## Writers as test doubles

Code that writes to a `*Io.Writer` ([Chapter 11](11-files-and-io.md)) is easy to test: give it a
writer into memory.

| Writer | Behavior |
|--------|----------|
| `Io.Writer.fixed(&buffer)` | Writes into your buffer, no allocation. `w.buffered()` returns what was written; a full buffer fails with `error.WriteFailed`. |
| `Io.Writer.Allocating` | Grows as needed. `out.writer` is the `Io.Writer`, `out.written()` the bytes. Call `deinit`. |
| `Io.Writer.fixed(&.{})` | No room; every write fails. A handy "discard" writer for code that must not print. |

`examples/ch16/writers.zig`

```zig
const std = @import("std");
const testing = std.testing;
const Io = std.Io;

/// Writes `items` as a bulleted list.
fn writeList(w: *Io.Writer, items: []const []const u8) Io.Writer.Error!void {
    for (items) |item| try w.print("- {s}\n", .{item});
}

test "writeList into a fixed buffer" {
    var buffer: [64]u8 = undefined;
    var w: Io.Writer = .fixed(&buffer);
    try writeList(&w, &.{ "fox", "dog" });
    // `buffered` is what has been written so far.
    try testing.expectEqualStrings("- fox\n- dog\n", w.buffered());
}

test "a fixed buffer that is too small" {
    var buffer: [4]u8 = undefined;
    var w: Io.Writer = .fixed(&buffer);
    try testing.expectError(error.WriteFailed, writeList(&w, &.{"fox"}));
}

test "writeList into an allocating writer" {
    var out: Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try writeList(&out.writer, &.{ "a", "b", "c" });
    try testing.expectEqualStrings("- a\n- b\n- c\n", out.written());
}
```

```console
$ zig test examples/ch16/writers.zig
1/3 writers.test.writeList into a fixed buffer...OK
2/3 writers.test.a fixed buffer that is too small...OK
3/3 writers.test.writeList into an allocating writer...OK
All 3 tests passed.
```

Readers work the same way: `var r: Io.Reader = .fixed("some\ntext\n");` reads from a string.

## Filtering, skipping, and test-only code

`examples/ch16/skip_and_filter.zig`

```zig
const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;

/// True only when this code is compiled by `zig test`.
fn inTest() bool {
    return builtin.is_test;
}

test "is_test" {
    try testing.expect(inTest());
}

test "only on Windows" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    try testing.expect(false); // never reached on Linux or macOS
}

test "math: add" {
    try testing.expectEqual(4, 2 + 2);
}

test "math: multiply" {
    try testing.expectEqual(6, 2 * 3);
}

// An unnamed test always runs, even with --test-filter.
test {
    try testing.expect(true);
}
```

```console
$ zig test examples/ch16/skip_and_filter.zig
1/5 skip_and_filter.test.is_test...OK
2/5 skip_and_filter.test.only on Windows...SKIP
3/5 skip_and_filter.test.math: add...OK
4/5 skip_and_filter.test.math: multiply...OK
5/5 skip_and_filter.test_0...OK
4 passed; 1 skipped; 0 failed.
$ zig test examples/ch16/skip_and_filter.zig --test-filter "math:"
1/3 skip_and_filter.test.math: add...OK
2/3 skip_and_filter.test.math: multiply...OK
3/3 skip_and_filter.test_0...OK
All 3 tests passed.
```

- `--test-filter TEXT` keeps tests whose name **contains** `TEXT`; repeat it for several filters.
  Prefix related names (`"math: …"`) so one filter selects them. Unnamed tests always run.
- Returning `error.SkipZigTest` marks a test skipped, not failed.
- `@import("builtin").is_test` is `true` only in test builds. It's comptime-known, so
  `if (builtin.is_test)` drops the other branch. Use it rarely: code that acts differently under
  test isn't really tested.

## Which tests run: `_ = @import(…)` and `refAllDecls`

Zig only analyzes declarations that something uses ([Chapter 12](12-comptime.md)), and tests
follow that rule. `zig test main.zig` runs the tests in `main.zig` plus those of every file or
struct a **test** refers to. A file used only by `main` doesn't count: in a test build the runner
replaces `main`, so your `main` isn't analyzed.

The fix is a test that refers to everything:

```zig
test {
    _ = @import("cli.zig");
    _ = @import("match.zig");
}
```

`_ = x;` uses `x` and discards it. Nested structs work the same way:

`examples/ch16/ref_decls.zig`

```zig
const std = @import("std");

// A nested struct is a container, just like a file. Its tests are
// compiled only if something refers to the struct.
const Hidden = struct {
    test "inside Hidden" {}
};

pub const Public = struct {
    test "inside Public" {}
};

test "top level" {}

test {
    // References every *public* declaration of this file, so Public's
    // tests are found. Hidden is not public, so its test is not.
    std.testing.refAllDecls(@This());
}
```

```console
$ zig test examples/ch16/ref_decls.zig
1/3 ref_decls.test.top level...OK
2/3 ref_decls.test_0...OK
3/3 ref_decls.Public.test.inside Public...OK
All 3 tests passed.
```

`std.testing.refAllDecls(T)` refers to every **public** declaration of `T`. `Hidden` isn't public,
so its test silently doesn't run. Explicit `_ = Hidden;` lines have no such blind spot, which is
why `seek` lists its files by hand.

## Fuzz testing

Unit tests check the inputs you thought of. A **fuzzer** generates inputs, tracks which code paths
they reach, and keeps mutating those that reach new code, so it finds the inputs you didn't think
of.

A Zig fuzz test is a normal test that calls `std.testing.fuzz`:

```zig
try testing.fuzz(context, testOne, .{ .corpus = &.{ "seed 1", "seed 2" } });
```

- `testOne(context, smith: *std.testing.Smith) !void` runs once per input; it returns an error for
  a bad one.
- `Smith` turns raw fuzzer bytes into values: `smith.value(T)` (any `T`),
  `smith.valueRangeAtMost(T, lo, hi)`, `smith.boolWeighted(…)` (biased bool),
  `smith.slice(&buffer)` (fills a prefix of `buffer`, returns its length).
- `corpus` lists starting inputs; `context` is passed to `testOne` (use `{}` if unused).

You usually can't compute the right answer for a random input without writing the function twice.
Check a **property** instead, something true for every input. Reversing twice gives back the
original:

`examples/ch16/fuzz.zig`

```zig
const std = @import("std");
const testing = std.testing;

/// Reverses `bytes` in place.
fn reverse(bytes: []u8) void {
    if (bytes.len < 2) return;
    var i: usize = 0;
    var j = bytes.len - 1;
    while (i < j) : ({
        i += 1;
        j -= 1;
    }) std.mem.swap(u8, &bytes[i], &bytes[j]);
}

test "fuzz reverse" {
    // The corpus holds starting inputs. `zig test` runs testOne once for
    // each of them (and once with an empty input).
    try testing.fuzz({}, reverseTwice, .{ .corpus = &.{ "fox", "ab" } });
}

/// Property: reversing twice gives back the original bytes.
fn reverseTwice(_: void, smith: *testing.Smith) !void {
    var buffer: [64]u8 = undefined;
    // `slice` fills a prefix of the buffer and returns its length.
    const input = buffer[0..smith.slice(&buffer)];
    var copy: [64]u8 = undefined;
    @memcpy(copy[0..input.len], input);

    reverse(copy[0..input.len]);
    reverse(copy[0..input.len]);
    try testing.expectEqualSlices(u8, input, copy[0..input.len]);
}
```

```console
$ zig test examples/ch16/fuzz.zig
1/1 fuzz.test.fuzz reverse...OK
All 1 tests passed.
1 fuzz tests found.
```

A plain test run doesn't fuzz: it runs `testOne` once per corpus entry plus once with empty input,
which is fast and repeatable. Real fuzzing needs the build system; you'll fuzz `seek` below with
`zig build test --fuzz=100K -Doptimize=safe`. `seek` uses another handy property: "agrees with a
simpler, slower implementation".

## Building seek: a test suite

`seek` has only two tests, in `stats.zig`, and `zig build test` doesn't even run them:

```console
$ zig build test --summary all
Build Summary: 3/3 steps succeeded
test success
+- run test success 3ms MaxRSS:4M
   +- compile test debug native success 302ms MaxRSS:153M
```

No test count means zero tests ran: the step compiles `main.zig` in test mode, and no test refers
to `stats.zig`. This step fixes that and adds tests to every file. Everything is test code except
one small refactor in `search.zig`.

### `src/main.zig`: pull in every file

Add this at the very bottom of `src/main.zig`:

```zig
// `zig build test` compiles main.zig in test mode. Only the tests in files
// that a test refers to are included, so we refer to every file here.
test {
    _ = @import("cli.zig");
    _ = @import("match.zig");
    _ = @import("output.zig");
    _ = @import("search.zig");
    _ = @import("stats.zig");
}
```

### `src/match.zig`: a table, doctests, and a fuzz test

Append to the end of `src/match.zig`:

```zig
const testing = std.testing;

// A test named after a declaration documents it: tools like `zig std`
// show it as an example ("doctest").
test wildcardMatch {
    // Table-driven: an array of anonymous structs, one per case.
    const cases = [_]struct { pattern: []const u8, text: []const u8, expected: bool }{
        .{ .pattern = "", .text = "", .expected = true },
        .{ .pattern = "", .text = "a", .expected = false },
        .{ .pattern = "*", .text = "", .expected = true },
        .{ .pattern = "*", .text = "anything", .expected = true },
        .{ .pattern = "?", .text = "", .expected = false },
        .{ .pattern = "f?x", .text = "fox", .expected = true },
        .{ .pattern = "f?x", .text = "fx", .expected = false },
        .{ .pattern = "*.md", .text = "todo.md", .expected = true },
        .{ .pattern = "*.md", .text = "todo.md.txt", .expected = false },
        .{ .pattern = "a*b*c", .text = "aXbYbZc", .expected = true },
        .{ .pattern = "a*b*c", .text = "acb", .expected = false },
        .{ .pattern = "**x", .text = "x", .expected = true },
        .{ .pattern = "Fox", .text = "fox", .expected = false },
        // Found by the fuzz test below: a `*` in the text is just a byte.
        .{ .pattern = "*x", .text = "*ax", .expected = true },
    };
    for (cases) |case| {
        // Only printed if the check below fails.
        errdefer std.debug.print("pattern \"{s}\", text \"{s}\"\n", .{ case.pattern, case.text });
        try testing.expectEqual(case.expected, wildcardMatch(case.pattern, case.text));
    }
}

test wildcardMatchIgnoreCase {
    try testing.expect(wildcardMatchIgnoreCase("*FOX*", "a fox!"));
    try testing.expect(!wildcardMatchIgnoreCase("fox", "fog"));
}

test "Matcher.find" {
    const literal: Matcher = .init("fox", false, false);
    try testing.expectEqual(Span{ .start = 4, .end = 7 }, literal.find("the fox").?);
    try testing.expectEqual(null, literal.find("the Fox"));

    const ignore_case: Matcher = .init("fox", true, false);
    try testing.expectEqual(Span{ .start = 4, .end = 7 }, ignore_case.find("the FOX").?);

    // A wildcard match always spans the whole line.
    const wildcard: Matcher = .init("the *", false, true);
    try testing.expectEqual(Span{ .start = 0, .end = 7 }, wildcard.find("the fox").?);
    try testing.expectEqual(null, wildcard.find("a fox"));
}

test "fuzz wildcardMatch against std.mem.find" {
    try testing.fuzz({}, fuzzStarPattern, .{ .corpus = &.{ "fox", "a*b?c" } });
}

/// Property: `*` ++ needle ++ `*` matches a text exactly when the text
/// contains the needle (if the needle itself has no wildcards).
fn fuzzStarPattern(_: void, smith: *testing.Smith) !void {
    var text_buffer: [64]u8 = undefined;
    const text = text_buffer[0..smith.slice(&text_buffer)];
    var pattern_buffer: [34]u8 = undefined;
    const needle_len = smith.slice(pattern_buffer[1 .. pattern_buffer.len - 1]);
    const needle = pattern_buffer[1..][0..needle_len];
    std.mem.replaceScalar(u8, needle, '*', '_');
    std.mem.replaceScalar(u8, needle, '?', '_');
    pattern_buffer[0] = '*';
    pattern_buffer[needle_len + 1] = '*';
    const pattern = pattern_buffer[0 .. needle_len + 2];

    const expected = std.mem.find(u8, text, needle) != null;
    try testing.expectEqual(expected, wildcardMatch(pattern, text));
}
```

- **Table-driven tests:** `cases` is an array of an anonymous struct type, one element per case.
  A new case is one line.
- **`errdefer` in the loop** prints the case only when its `try` fails. Otherwise a failure says
  `expected true, found false` and you don't know which row.
- **The fuzz property:** `"*fox*"` matches a text exactly when the text contains `fox`. The
  simple, trusted `std.mem.find` is the reference. The needle sits in `pattern_buffer` between two
  `*`s, with any `*` or `?` replaced, so it's literal.

#### The bug the fuzzer found

The last table row has a story. An earlier draft of `matchWildcard` (from
[Chapter 11](11-files-and-io.md)) checked for a literal match *before* checking for `*`:

```zig
        if (p < pattern.len and (pattern[p] == '?' or eqlByte(ignore_case, pattern[p], text[t]))) {
            p += 1;
            t += 1;
        } else if (p < pattern.len and pattern[p] == '*') {
            star = p;
            star_t = t;
            p += 1; // first, let `*` match nothing
        } else if
```

Every hand-written case passed. The fuzzer was quick:

```console
$ zig build test --fuzz=100K -Doptimize=safe
test
+- run test failure
expected true, found false
failed with error.TestExpectedEqual
error: test 'match.test.fuzz wildcardMatch against std.mem.find' exited with code 1; input saved to '.zig-cache/f/crash'
failed command: ./.zig-cache/o/0accabc612d86fd04fbdb1149c8c5a1b/test --cache-dir=./.zig-cache --seed=0xbf08e8bb --listen=-

======= FUZZING REPORT =======
Step: run test
Fuzz test: "match.test.fuzz wildcardMatch against std.mem.find" (c72b1f40ada04fb7)
Runs: 0 -> 2925
Unique runs: 0 -> 122
Coverage: 0/12454 -> 79/12454 (0.63%)
------------------------------
Values are accumulated across multiple runs when preserving the cache.
==============================
```

The failing input: a text starting with `*` plus random bytes, and a one-byte needle. Shrunk by
hand: `wildcardMatch("*x", "*ax")` returned `false`. The pattern's `*` matched the text's `*` as a
literal byte, so it was never recorded as a star. Checking for `*` first fixes it. The usual
workflow: the fuzzer finds a failure, you shrink it, and the small case becomes a permanent test
(here, the last table row).

### `src/cli.zig`: the parser

Append to the end of `src/cli.zig`:

```zig
const testing = std.testing;

test "parse mixes flags and positionals" {
    const gpa = testing.allocator;
    var diag: Diagnostic = .{};
    const options, const positionals = try parse(Options, gpa, &.{
        "-i", "fox", "--max-count=2", "src", "-n", "--color", "never", "--", "-v",
    }, &diag);
    defer gpa.free(positionals);

    try testing.expect(options.ignore_case);
    try testing.expect(options.line_numbers);
    try testing.expect(!options.invert); // "-v" came after "--"
    try testing.expectEqual(2, options.max_count.?);
    try testing.expectEqual(.never, options.color);
    try testing.expectEqual(3, positionals.len);
    try testing.expectEqualStrings("fox", positionals[0]);
    try testing.expectEqualStrings("src", positionals[1]);
    try testing.expectEqualStrings("-v", positionals[2]);
}

test "parse reports bad flags through the diagnostic" {
    const gpa = testing.allocator;
    const cases = [_]struct { args: []const [:0]const u8, err: Error, flag: []const u8, value: []const u8 }{
        .{ .args = &.{"--frobnicate"}, .err = error.UnknownFlag, .flag = "--frobnicate", .value = "" },
        .{ .args = &.{ "fox", "-m" }, .err = error.MissingValue, .flag = "-m", .value = "" },
        .{ .args = &.{ "-m", "many" }, .err = error.InvalidValue, .flag = "-m", .value = "many" },
        .{ .args = &.{"--color=sometimes"}, .err = error.InvalidValue, .flag = "--color", .value = "sometimes" },
        .{ .args = &.{"--hidden=yes"}, .err = error.InvalidValue, .flag = "--hidden", .value = "yes" },
    };
    for (cases) |case| {
        var diag: Diagnostic = .{};
        try testing.expectError(case.err, parse(Options, gpa, case.args, &diag));
        try testing.expectEqualStrings(case.flag, diag.flag);
        try testing.expectEqualStrings(case.value, diag.value);
    }
}

test "parse and help work for any options struct" {
    const Point = struct {
        x: i32 = 0,
        label: []const u8 = "",
        verbose: bool = false,

        pub const shorts = .{ .verbose = 'v' };
        pub const descriptions = .{ .x = "x coordinate", .label = "a name", .verbose = "talk more" };
    };

    var diag: Diagnostic = .{};
    const point, const positionals = try parse(Point, testing.allocator, &.{ "--x", "-5", "-v", "--label=origin" }, &diag);
    defer testing.allocator.free(positionals);
    try testing.expectEqual(-5, point.x);
    try testing.expectEqualStrings("origin", point.label);
    try testing.expect(point.verbose);

    try testing.expectEqualStrings(
        \\      --x N                      x coordinate
        \\      --label LABEL              a name
        \\  -v, --verbose                  talk more
        \\
    , comptime help(Point));
}
```

- `expectEqual(.never, options.color)`: the enum literal on the left takes its type from the right.
- The second test drives `parse` down its **error path**, where a missing `errdefer` would leak and
  `testing.allocator` would catch it.
- The third test is the payoff of the comptime parser from [Chapter 12](12-comptime.md): it works
  for any struct, so the test invents one. `--x -5` checks that a negative number is a value, not a
  flag.

### `src/output.zig`: printers into a fixed buffer

Append to the end of `src/output.zig`:

```zig
const testing = std.testing;

test "Printer.lines prints every line" {
    // A fixed writer writes into a buffer we provide: no allocation.
    var buffer: [128]u8 = undefined;
    var w: Io.Writer = .fixed(&buffer);
    const printer: Printer = .init(.{ .line_numbers = true }, .init("fox", false, false));
    try printer.line(&w, "a.txt", 3, "the fox");
    try printer.line(&w, "a.txt", 7, "a fox");
    try printer.fileDone(&w, "a.txt", 2);
    try testing.expectEqualStrings("a.txt:3:the fox\na.txt:7:a fox\n", w.buffered());
}

test "Printer.count and Printer.files summarize each file" {
    var buffer: [128]u8 = undefined;
    var w: Io.Writer = .fixed(&buffer);
    const matcher: Matcher = .init("fox", false, false);

    const count: Printer = .init(.{ .count_only = true }, matcher);
    try count.line(&w, "a.txt", 1, "the fox");
    try count.fileDone(&w, "a.txt", 1);
    try count.fileDone(&w, "b.txt", 0);

    // -l wins over -c.
    const files: Printer = .init(.{ .count_only = true, .files_only = true }, matcher);
    try testing.expect(files == .files);
    try files.fileDone(&w, "a.txt", 1);
    try files.fileDone(&w, "b.txt", 0);

    try testing.expectEqualStrings("a.txt:1\nb.txt:0\na.txt\n", w.buffered());
}

test "Match highlights every occurrence" {
    const match: Match = .{
        .path = "p",
        .line_number = null,
        .text = "fox and fox",
        .highlight = .init("fox", false, false),
    };
    try testing.expectFmt("p:" ++ ansi_match ++ "fox" ++ ansi_reset ++ " and " ++
        ansi_match ++ "fox" ++ ansi_reset, "{f}", .{match});
}

test "Match does not loop on empty matches" {
    const match: Match = .{
        .path = "p",
        .line_number = 1,
        .text = "",
        .highlight = .init("*", false, true),
    };
    try testing.expectFmt("p:1:", "{f}", .{match});
}
```

`expectFmt` with `"{f}"` calls `Match.format`, so the test checks exactly what `seek` prints,
escape codes included. The last test guards a classic bug: a pattern that matches the empty string
must not make the highlighter loop forever.

### `src/stats.zig`: the summary

Append to the end of `src/stats.zig`:

```zig
test "Stats.write prints a summary and the top files" {
    const gpa = std.testing.allocator;
    var stats: Stats = .{};
    defer stats.deinit(gpa);
    try stats.record(gpa, "a.txt", 2);
    try stats.record(gpa, "b.txt", 0);
    try stats.record(gpa, "c.txt", 5);

    var out: Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    // A fixed duration keeps the output predictable.
    try stats.write(gpa, &out.writer, .fromMilliseconds(12));
    try std.testing.expectEqualStrings(
        \\--- stats ---
        \\files searched: 3
        \\files matched:  2
        \\matching lines: 7
        \\elapsed:        12ms
        \\top files:
        \\     5  c.txt
        \\     2  a.txt
        \\
    , out.written());
}
```

`write` takes the elapsed time as a parameter instead of reading the clock, which makes its output
testable.

### `src/search.zig`: a directory to search in

`Searcher` opens relative paths with `Io.Dir.cwd()`, so a test could only search the real current
directory. Add a `dir` field right after `io`:

```zig
pub const Searcher = struct {
    gpa: Allocator,
    io: std.Io,
    /// Relative paths are opened from here: the current directory, unless
    /// a test points it at a temporary directory.
    dir: Io.Dir,
    pattern: []const u8,
```

In `init`, set it right after `.io = io,`:

```zig
        return .{
            .gpa = gpa,
            .io = io,
            // Not a field default: on some systems (Windows) the current
            // directory handle is only known at run time.
            .dir = .cwd(),
            .pattern = owned_pattern,
```

Why not a field default (`dir: Io.Dir = .cwd(),`)? Defaults must be comptime-known. On Linux and
macOS the current directory is a constant handle, so it compiles; on Windows it's known only at run
time, so cross-compiling in [Chapter 18](18-build-system.md) would break.

Then replace the three uses of `Io.Dir.cwd()` with `self.dir`. In `addPath`:

```zig
            if (self.dir.statFile(self.io, path, .{})) |stat| {
```

in `addDirectory`:

```zig
        var dir = self.dir.openDir(self.io, root, .{ .iterate = true }) catch |err| {
```

and in `searchFile`:

```zig
        const file: Io.File = if (is_stdin) .stdin() else try self.dir.openFile(self.io, path, .{});
```

Now append the tests to the end of `src/search.zig`:

```zig
const testing = std.testing;

/// Creates a small directory tree in `dir` for the tests below.
fn makeTestTree(dir: Io.Dir) !void {
    const io = testing.io;
    try dir.createDirPath(io, "notes");
    try dir.writeFile(io, .{ .sub_path = "poem.txt", .data = "The quick brown fox\nA Fox is quick\n" });
    try dir.writeFile(io, .{ .sub_path = "notes/todo.md", .data = "- feed the fox\n- walk the dog\n" });
    try dir.writeFile(io, .{ .sub_path = ".secret.txt", .data = "the fox knows\n" });
    try dir.writeFile(io, .{ .sub_path = "data.bin", .data = "fox\x00binary\n" });
}

/// Searches `paths` in a fresh temporary tree and checks stdout and stderr.
fn expectSearch(
    pattern: []const u8,
    options: Options,
    paths: []const []const u8,
    expected_stdout: []const u8,
    expected_stderr: []const u8,
) !void {
    const gpa = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try makeTestTree(tmp.dir);

    // Allocating writers collect the output in memory.
    var stdout: Io.Writer.Allocating = .init(gpa);
    defer stdout.deinit();
    var stderr: Io.Writer.Allocating = .init(gpa);
    defer stderr.deinit();

    var searcher: Searcher = try .init(gpa, testing.io, pattern, options, &stdout.writer, &stderr.writer);
    defer searcher.deinit();
    searcher.dir = tmp.dir;
    for (paths) |path| try searcher.addPath(path);
    try searcher.searchAll();

    try testing.expectEqualStrings(expected_stdout, stdout.written());
    try testing.expectEqualStrings(expected_stderr, stderr.written());
}

test "search walks directories in sorted order and skips hidden and binary files" {
    try expectSearch("fox", .{ .line_numbers = true }, &.{"."},
        \\notes/todo.md:1:- feed the fox
        \\poem.txt:1:The quick brown fox
        \\
    , "");
}

test "search with --hidden, -i and --glob" {
    try expectSearch("FOX", .{ .ignore_case = true, .hidden = true, .glob = "*.txt" }, &.{"."},
        \\.secret.txt:the fox knows
        \\poem.txt:The quick brown fox
        \\poem.txt:A Fox is quick
        \\
    , "");
}

test "search reports a missing file and keeps going" {
    try expectSearch("fox", .{ .count_only = true }, &.{ "poem.txt", "nope.txt", "notes" },
        \\poem.txt:1
        \\notes/todo.md:1
        \\
    , "seek: nope.txt: FileNotFound\n");
}

test "search output does not depend on the number of jobs" {
    for ([_]usize{ 1, 2, 3, 8 }) |jobs| {
        try expectSearch("o", .{ .files_only = true, .jobs = jobs }, &.{ ".", "poem.txt" },
            \\notes/todo.md
            \\poem.txt
            \\poem.txt
            \\
        , "");
    }
}

/// Queues a few files; used with checkAllAllocationFailures below.
fn queueSomeFiles(gpa: Allocator) !void {
    var discard: Io.Writer = .fixed(&.{});
    var searcher: Searcher = try .init(gpa, testing.io, "fox", .{}, &discard, &discard);
    defer searcher.deinit();
    for ([_][]const u8{ "a", "b", "c", "d", "e", "f", "g", "h", "i" }) |path| {
        try searcher.addPath(path);
    }
}

test "Searcher frees everything when an allocation fails" {
    // Runs queueSomeFiles once for every allocation it makes, failing that
    // allocation, and checks that nothing leaks.
    try testing.checkAllAllocationFailures(testing.allocator, queueSomeFiles, .{});
}

test looksBinary {
    var text: Io.Reader = .fixed("just text\n");
    try testing.expect(!try looksBinary(&text));
    var binary: Io.Reader = .fixed("bin\x00ary");
    try testing.expect(try looksBinary(&binary));
}

test "nextLine handles lines longer than the reader's buffer" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var long_line: Io.Writer.Allocating = .init(arena.allocator());

    // Read through a 4-byte buffer: "abcdefgh" doesn't fit.
    var source: Io.Reader = .fixed("ab\nabcdefgh\nend");
    var small_buffer: [4]u8 = undefined;
    var limited = source.limited(.unlimited, &small_buffer);
    const reader = &limited.interface;

    try testing.expectEqualStrings("ab", (try nextLine(reader, &long_line)).?);
    try testing.expectEqualStrings("abcdefgh", (try nextLine(reader, &long_line)).?);
    try testing.expectEqualStrings("end", (try nextLine(reader, &long_line)).?);
    try testing.expectEqual(null, try nextLine(reader, &long_line));
}
```

- **`expectSearch`** is an end-to-end helper: a real directory tree, a real `Searcher`, real
  concurrency, with stdout and stderr captured in `Allocating` writers. Setting
  `searcher.dir = tmp.dir` after `init` is why we refactored.
- **The `jobs` test** searches with 1, 2, 3 and 8 workers. Output must be identical every time, as
  [Chapter 15](15-concurrency.md) promised.
- **`queueSomeFiles`** has the shape `checkAllAllocationFailures` needs (allocator first, returns
  `!void`). It never prints, but uses `.fixed(&.{})` for stdout and stderr so nothing can reach the
  terminal. The paths don't exist; `addPath` queues them without opening them. The test runs it 12
  times (one normal run, then one per allocation), exercising the `errdefer` in `addFile`.
- **`nextLine`** has a slow path for lines longer than the reader's buffer, which a 64 KiB buffer
  never hits in normal tests. `source.limited(.unlimited, &small_buffer)` wraps the reader with a
  4-byte buffer, so an 8-byte line takes the slow path.

### Checkpoint

```console
$ zig build test --summary all
Build Summary: 3/3 steps succeeded; 22/22 tests passed
test success
+- run test 22 pass (22 total) 12ms MaxRSS:6M
   +- compile test debug native success 413ms MaxRSS:164M
```

Timings and memory vary. Results are cached: rerun with no changes and you get `run test cached`
and no count. Change any file to rerun.

The import block counts as a test: 22 = cli 3 + match 4 + output 4 + search 7 + stats 3 + 1.

To test one file without the build system, use `zig test`; `--test-filter` picks tests by name:

```console
$ zig test src/match.zig --test-filter wildcard
1/3 match.decltest.wildcardMatch...OK
2/3 match.decltest.wildcardMatchIgnoreCase...OK
3/3 match.test.fuzz wildcardMatch against std.mem.find...OK
All 3 tests passed.
1 fuzz tests found.
```

`seek` works as before:

```console
$ zig build && ./zig-out/bin/seek -n fox testdata
testdata/notes/log.txt:1:2024-01-01 saw a fox near the barn
testdata/notes/log.txt:3:2024-01-03 fox tracks in the snow
testdata/notes/todo.md:2:- feed the fox
testdata/poem.txt:1:The quick brown fox
```

Now fuzz the matcher for 100,000 runs:

```console
$ zig build test --fuzz=100K -Doptimize=safe
======= FUZZING REPORT =======
Step: run test
Fuzz test: "match.test.fuzz wildcardMatch against std.mem.find" (d0ff56481bf2c6d7)
Runs: 0 -> 100139
Unique runs: 0 -> 137
Coverage: 0/12454 -> 80/12454 (0.64%)
------------------------------
Values are accumulated across multiple runs when preserving the cache.
==============================
```

This took about 30 seconds here; run and coverage numbers vary. About `--fuzz`:

- **Use a release mode.** `-Doptimize=safe` keeps safety checks and adds the coverage
  instrumentation the fuzzer needs. Debug fails with `corrupted coverage file …: pcs_len was zero`.
- **Give a limit.** `--fuzz=100K` (suffixes `K`, `M`, `G`) stops after that many runs. Plain
  `--fuzz` runs until Ctrl-C and starts a web interface with live coverage.
- **Read the output.** A crash doesn't change the exit status (still 0, as in the story above). The
  failing input is saved to `.zig-cache/f/crash`.

Replay the story: swap the two branches in `matchWildcard` as shown above, delete the `"*x"` row,
and fuzz. Then undo both changes.

### Seeing the safety net work

Break things on purpose and watch the tests catch them. Undo each change afterwards.

1. In the test "parse mixes flags and positionals", delete `defer gpa.free(positionals);`:

   ```console
   $ zig build test --summary all
   test
   +- run test 22 pass (22 total); 1 leaks
   error: 'cli.test.parse mixes flags and positionals' leaked 1 allocations:
          [SafeAllocator] (err): leaked [addr: 7f1197d26070, len: 48 (0x30) align: 8] allocated at: 
          …/lib/std/array_list.zig:751:26: 0x12d951e in toOwnedSlice (std.zig)
                      if (gpa.remap(old_memory, self.items.len)) |new_items| {
                                   ^
          …/src/cli.zig:135:52: 0x12df01e in parse__func_1208 (main.zig)
              return .{ options, try positionals.toOwnedSlice(gpa) };
                                                             ^
          …/src/cli.zig:243:49: 0x12e9a4c in test.parse mixes flags and positionals (main.zig)
              const options, const positionals = try parse(Options, gpa, &.{
                                                          ^
          … (test runner and start-up frames)
          (additional stack frames may have been skipped...)
   failed command: ./.zig-cache/o/88b44dbbe52cd3d4439bdee8ceb74e89/test --cache-dir=./.zig-cache --seed=0x3ed3555e --listen=-

   Build Summary: 1/3 steps succeeded (1 failed); 22/22 tests passed
   test transitive failure
   ```

   Every assertion passed (`22/22 tests passed`), but the leak failed the step, and
   `zig build test` exits with status 1.

2. In `Searcher.addFile`, delete `errdefer self.gpa.free(path);`:

   ```console
   $ zig build test --summary all
   test
   +- run test 21 pass, 1 fail (22 total); 1 leaks
   error: 'search.test.Searcher frees everything when an allocation fails' failed:
          fail_index: 2/11
          allocated bytes: 4
          freed bytes: 3
          allocations: 2
          deallocations: 1
          allocation that was made to fail: 
          …/lib/std/array_list.zig:1375:56: 0x12b08e1 in ensureTotalCapacityPrecise (std.zig)
          …
          …/src/search.zig:116:30: 0x12a0504 in addFile (main.zig)
                  try self.files.append(self.gpa, path);
                                       ^
          …/src/search.zig:110:25: 0x12a0159 in addPath (main.zig)
                  try self.addFile(try self.gpa.dupe(u8, path));
                                  ^
          …/src/search.zig:442:29: 0x129dc48 in queueSomeFiles (main.zig)
                  try searcher.addPath(path);
                                      ^
          …
   ```

   A full run makes 11 allocations. Failing allocation 2 (the first `files.append`) leaked:
   `deinit` freed the 3-byte pattern copy `"fox"` but not the 1-byte copy of `"a"`, so 4 bytes were
   allocated and 3 freed. No ordinary test would reach this path.

The complete project at this point is in `project/ch16/`.

## Summary

- `test "name" { … }` blocks sit next to the code and aren't in normal builds. `zig test file.zig`
  runs one file; `zig build test` runs the project's test step.
- `test someDecl { … }` is a doctest documenting `someDecl`.
- `std.testing` checks return errors: `expect`, `expectEqual(expected, actual)`,
  `expectEqualStrings`, `expectEqualSlices`, `expectError`, `expectFmt`. Expected first.
- `std.testing.allocator` fails leaking tests and shows where the memory came from.
- `checkAllAllocationFailures` fails each allocation in turn, testing your `errdefer`s.
- `testing.tmpDir` gives a throwaway directory, `testing.io` an `Io`. Pass directories in; don't
  hard-code `cwd()`.
- `Io.Writer.fixed`, `Io.Writer.Allocating` and `Io.Reader.fixed` make I/O code testable in memory.
- Only reachable tests run. Use `test { _ = @import("file.zig"); }`; `refAllDecls` sees only `pub`
  declarations.
- `--test-filter`, `error.SkipZigTest` and `builtin.is_test` control what runs.
- `std.testing.fuzz` checks a property on generated inputs. `zig build test --fuzz=100K
  -Doptimize=safe` fuzzes; read the output, since the exit status stays 0.

## Exercises

1. Turn `test wildcardMatchIgnoreCase` in `src/match.zig` into a table-driven test (or add a
   separate one) with at least five cases, including `?` and `*`. Make one case wrong on purpose
   and check that the `errdefer` line names it.

   <details><summary>Solution</summary>

   ```zig
   test "wildcardMatchIgnoreCase table" {
       const cases = [_]struct { pattern: []const u8, text: []const u8, expected: bool }{
           .{ .pattern = "FOX", .text = "fox", .expected = true },
           .{ .pattern = "f?X", .text = "FoX", .expected = true },
           .{ .pattern = "*.MD", .text = "todo.md", .expected = true },
           .{ .pattern = "fox", .text = "fog", .expected = false },
           .{ .pattern = "*Z*", .text = "abc", .expected = false },
       };
       for (cases) |case| {
           errdefer std.debug.print("pattern \"{s}\", text \"{s}\"\n", .{ case.pattern, case.text });
           try testing.expectEqual(case.expected, wildcardMatchIgnoreCase(case.pattern, case.text));
       }
   }
   ```

   With a wrong `expected`, you see `expected false, found true` followed by that case's
   `pattern "…", text "…"` line.

   </details>

2. Add an end-to-end test to `src/search.zig` for `-m 1` (`.max_count = 1`): searching `poem.txt`
   for `o` with line numbers must print only the first line.

   <details><summary>Solution</summary>

   ```zig
   test "search stops after -m matches" {
       try expectSearch("o", .{ .max_count = 1, .line_numbers = true }, &.{"poem.txt"},
           \\poem.txt:1:The quick brown fox
           \\
       , "");
   }
   ```

   Both lines of `poem.txt` contain an `o`; only the first is printed.

   </details>

3. In `examples/ch16/ref_decls.zig`, make the test inside `Hidden` run **without** making `Hidden`
   public.

   <details><summary>Solution</summary>

   Refer to it from a test:

   ```zig
   test {
       std.testing.refAllDecls(@This());
       _ = Hidden;
   }
   ```

   The runner now also lists `ref_decls.Hidden.test.inside Hidden`: 4 tests in all.

   </details>

4. Write a second fuzz test for `wildcardMatch` in `src/match.zig`: a pattern without `*` or `?`
   matches a text exactly when they are equal. Run it with `zig test` and with
   `zig build test --fuzz=20K -Doptimize=safe`.

   <details><summary>Solution</summary>

   ```zig
   test "fuzz: a pattern without wildcards matches only itself" {
       try testing.fuzz({}, fuzzLiteral, .{ .corpus = &.{ "fox", "fox\x00fox" } });
   }

   fn fuzzLiteral(_: void, smith: *testing.Smith) !void {
       var a_buffer: [16]u8 = undefined;
       const a = a_buffer[0..smith.slice(&a_buffer)];
       std.mem.replaceScalar(u8, a, '*', '_');
       std.mem.replaceScalar(u8, a, '?', '_');
       var b_buffer: [16]u8 = undefined;
       const b = b_buffer[0..smith.slice(&b_buffer)];
       try testing.expectEqual(std.mem.eql(u8, a, b), wildcardMatch(a, b));
       try testing.expect(wildcardMatch(a, a));
   }
   ```

   ```console
   $ zig test src/match.zig --test-filter wildcards
   1/1 match.test.fuzz: a pattern without wildcards matches only itself...OK
   All 1 tests passed.
   1 fuzz tests found.
   ```

   The fuzz run passes too. Its report names only the first fuzz test, but it fuzzes both. The
   second assertion matters: random `a` and `b` are almost never equal, so without it the "equal"
   case would hardly be tested.

   </details>

5. Why does `queueSomeFiles` take the allocator as a parameter instead of using
   `testing.allocator` directly? What would go wrong?

   <details><summary>Solution</summary>

   `checkAllAllocationFailures` must pass a different allocator on each run, one that fails at a
   chosen allocation. With `testing.allocator` hard-coded, nothing would ever fail, the `errdefer`
   paths would never run, and the test would prove nothing. The same idea runs through all of Zig:
   code that receives its allocator can be tested with any allocator.

   </details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-16--testing)
