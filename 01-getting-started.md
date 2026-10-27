# Chapter 1 — Getting Started

Meet Zig and its single tool, `zig`. You'll run and build programs, print correctly, split code
across files, read compiler errors, and create the `seek` project. Next,
[Chapter 2](02-values-and-types.md) covers values, types, and variables.

## How this course works

- Read the chapters in order ([README](README.md) lists them). Each uses only what came before.
- Every concept has a small program you can run.
- Each chapter adds a feature to `seek`, a `grep`-like search tool.
- Each chapter ends with exercises. Solutions are in collapsible blocks.

You need **exactly Zig 0.17.0** (installing it isn't covered). Zig is pre-1.0, so the language and
especially the standard library change between releases. This code won't compile on older
versions, and newer ones may break it. Check your version:

```console
$ zig version
0.17.0
```

### Conventions

- **Commands.** Type the lines starting with `$ ` (without the `$`). The lines below are output.
- **Example paths.** Each example's path, like `examples/ch01/hello.zig`, appears above it. Run
  examples from the course folder (the one holding `examples/`).
- **Project snapshots.** `project/chNN/` is the complete `seek` project at the end of chapter NN.
- **Shell.** Commands assume a Unix-like shell (Linux, macOS, WSL). On Windows, programs end in
  `.exe`.

## What Zig is

Zig is a compiled, statically typed systems language. Andrew Kelley introduced it in 2016 as a
language "more pragmatic than C". Its website states the goal: a language and toolchain "for
maintaining **robust**, **optimal** and **reusable** software".

| Idea | What it means for you |
|------|-----------------------|
| No hidden control flow | If code doesn't look like a function call, it isn't one. No operator overloading, no exceptions, no property getters. |
| No hidden memory allocations | Code that needs heap memory takes an allocator as a parameter ([Chapter 8](08-memory-and-allocators.md)). |
| No preprocessor, no macros | One language, not two. |
| `comptime` | Ordinary Zig code can run at compile time. It replaces macros, generics, and conditional compilation ([Chapter 12](12-comptime.md)). |
| Safety you can choose | Debug builds catch overflow, out-of-bounds access, and similar bugs at run time. Release builds can drop the checks. |
| A whole toolchain | One `zig` binary compiles, tests, formats, builds projects, cross-compiles, and even compiles C. |

No garbage collector, no runtime: a Zig program does exactly what its code says.

## Your first program

`examples/ch01/hello.zig`

```zig
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Hello, {s}!\n", .{"Zig"});
    try stdout.flush();
}
```

```console
$ zig run examples/ch01/hello.zig
Hello, Zig!
```

Line by line:

- `const std = @import("std");` loads the standard library as `std`. Builtin functions start with
  `@`; `@import` is one.
- `pub fn main(...) !void` is the entry point. `pub` makes it visible to the startup code. `!void`
  means "returns nothing, or an error".
- `init: std.process.Init` gives `main` what it needs from the outside world. Here: `init.io`,
  the I/O interface.
- `var buffer: [1024]u8 = undefined;` reserves 1024 bytes on the stack, not yet filled in.
- The next two lines create a buffered writer for standard output (stdout) and take a pointer to
  its general `Writer` interface.
- `stdout.print("Hello, {s}!\n", .{"Zig"})` formats text into the buffer. `{s}` means "a string";
  `.{"Zig"}` is the argument list.
- `stdout.flush()` sends the buffer to the terminal.
- `try` means: if this call fails, return the error from `main`.

That's a lot for "hello", but every piece has a purpose; this chapter explains why. Details come
later: types and `undefined` in [Chapter 2](02-values-and-types.md), errors and `try` in
[Chapter 5](05-errors-and-optionals.md), pointers (`&`) in
[Chapter 6](06-arrays-slices-pointers.md), and `.{...}` literals in
[Chapter 7](07-structs-enums-unions.md).

## Running and building

The `zig` command does everything. Subcommands you'll use daily:

| Command | What it does |
|---------|--------------|
| `zig run file.zig` | Compile to a temporary place and run it. Arguments after `--` go to the program. |
| `zig build-exe file.zig` | Compile to an executable in the current folder. |
| `zig test file.zig` | Compile and run the `test` blocks in a file. |
| `zig fmt file.zig` | Format the code in place. |
| `zig init` | Create a new project. |
| `zig build` | Build a project described by `build.zig`. |
| `zig version`, `zig help`, `zig zen` | Version, list of commands, design principles. |
| `zig std` | Open the standard library documentation in a browser. |

`zig run` is for trying things; `zig build-exe` makes a program you keep:

```console
$ zig build-exe examples/ch01/hello.zig
$ ./hello
Hello, Zig!
```

The executable lands in the current folder, named after the file. Delete it when done
(`rm hello`).

Zig builds in **Debug** mode by default: no optimizations, all safety checks, full debug info.
`-O` picks another mode:

| Mode (`-O`) | Common name | Optimized | Safety checks | Use it for |
|-------------|-------------|-----------|---------------|------------|
| `debug` (default) | Debug | no | yes | development |
| `safe` | ReleaseSafe | yes | yes | releases where correctness matters most |
| `fast` | ReleaseFast | yes | no | maximum speed |
| `small` | ReleaseSmall | yes | no | smallest binary |

The common names are the traditional ones, still used in docs and in this course's prose.

```console
$ zig build-exe examples/ch01/hello.zig -O small
$ ls -l hello
-rwxr-xr-x 1 you you 148816 Oct 27 11:43 hello
```

The Debug build is about 13 MB, mostly debug info. Your sizes may differ.
[Chapter 18](18-build-system.md) and [Chapter 19](19-low-level.md) cover modes in depth.

## `main` and `std.process.Init`

`main` can take a few shapes:

```zig
pub fn main() void { ... }                                // nothing in, nothing out
pub fn main() !void { ... }                               // may fail
pub fn main(init: std.process.Init) !void { ... }         // full environment
pub fn main(init: std.process.Init.Minimal) !void { ... } // just args and environment
pub fn main(init: std.process.Init) !u8 { ... }           // the u8 is the exit status
```

`std.process.Init` holds what the startup code prepared:

| Field | What it is | Chapter |
|-------|------------|---------|
| `init.io` | The I/O interface. Files, stdout, timers, and threads go through it. | 11, 15 |
| `init.gpa` | A general-purpose allocator. Checks for leaks in Debug builds. | 8 |
| `init.arena` | An arena allocator that lives until the program exits. | 3, 8 |
| `init.minimal.args` | Command-line arguments. | 3 |
| `init.environ_map` | Environment variables. | 11 |

Zig has no hidden global stdout or allocator. `main` receives them and passes them to whatever
needs them. So you can see which code does I/O or allocates, and tests can swap in their own.

If `main` returns an error, the program prints its name (plus a trace in Debug builds) and exits
with status 1. A returned `u8` becomes the exit status.

## Printing: `std.debug.print` vs. stdout

There are two ways to print, to two different places.

`std.debug.print` writes to **standard error** (stderr) immediately, ignores failures, and needs
no setup:

`examples/ch01/debug_print.zig`

```zig
const std = @import("std");

// The simplest `main`: no parameters, returns nothing.
pub fn main() void {
    std.debug.print("Hello, {s}! {d} + {d} = {d}\n", .{ "stderr", 2, 3, 2 + 3 });
}
```

```console
$ zig run examples/ch01/debug_print.zig
Hello, stderr! 2 + 3 = 5
```

`{s}` prints a string, `{d}` a number. Arguments go in `.{ ... }`, in order, and the compiler
checks them against the format string ([Chapter 9](09-strings-and-formatting.md) lists all
specifiers).

Use it for debugging. Real output belongs on **standard output** (stdout), which users redirect
and pipe (`seek fox > found.txt`). stderr is for diagnostics. Mixing them breaks pipelines.

For stdout, build a **buffered writer** as in `hello.zig`. It collects output in `buffer` and
writes it in one system call on `flush()` (or when the buffer fills). System calls are slow, so
buffering makes output fast. It's also why you must flush:

`examples/ch01/no_flush.zig`

```zig
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("You will never see this line.\n", .{});
    // Missing: try stdout.flush();
}
```

```console
$ zig run examples/ch01/no_flush.zig
$
```

Nothing. The text sat in `buffer` and vanished when `main` returned. Zig won't flush for you: that
would be hidden work that could fail with nowhere to report the error.

The two streams are independent. Here stderr appears first, though the stdout line was printed
in between:

`examples/ch01/two_streams.zig`

```zig
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &buffer);
    const stdout = &stdout_writer.interface;

    std.debug.print("debug: starting\n", .{}); // stderr, right away
    try stdout.print("result: 42\n", .{}); // stdout, buffered
    std.debug.print("debug: done\n", .{});
    try stdout.flush(); // "result: 42" is written here
}
```

```console
$ zig run examples/ch01/two_streams.zig
debug: starting
debug: done
result: 42
$ zig run examples/ch01/two_streams.zig 2>/dev/null
result: 42
```

`2>/dev/null` discards stderr, leaving only the real output.

> **Gotcha: `.init` vs. `.initStreaming`.** The `zig init` template and other code use
> `std.Io.File.Writer = .init(...)`. That writer is *positional*: it tracks its own offset and
> writes at 0, 1, 2, …. Fine for a terminal or pipe, but if stdout is a file that already has
> content, it overwrites from the start:
>
> ```console
> $ (echo "a much longer header line that came first"; ./with_init) > out.txt; cat out.txt
> Hello, Zig!
> r header line that came first
> ```
>
> `.initStreaming` just appends, like `echo`. This course uses `.initStreaming` for stdout and
> stderr everywhere.

## Files are structs: `@import` and `pub`

Every `.zig` file is a struct whose members are its top-level declarations (`const`, `var`,
`fn`). `@import("file.zig")` returns that struct, so you reach its contents with a dot, like
`std.debug.print`. (`std` is a file too: `std.zig`.)

Declarations are private to their file unless marked `pub`.

`examples/ch01/greet.zig`

```zig
//! A tiny module. This whole file is a struct with three declarations.
const std = @import("std");

/// Public: other files can use `greet.greeting`.
pub const greeting = "Hello";

/// Public function.
pub fn shout(times: u32) u32 {
    return times * volume;
}

// Private: visible only inside this file.
const volume = 10;

test "shout multiplies by the volume" {
    try std.testing.expect(shout(3) == 30);
}
```

`examples/ch01/use_greet.zig`

```zig
const std = @import("std");
const greet = @import("greet.zig"); // path relative to this file

pub fn main() void {
    std.debug.print("{s}, world!\n", .{greet.greeting});
    std.debug.print("shout(2) = {d}\n", .{greet.shout(2)});
    std.debug.print("greet is a {s} named {s}\n", .{ @typeName(@TypeOf(greet)), @typeName(greet) });
}
```

```console
$ zig run examples/ch01/use_greet.zig
Hello, world!
shout(2) = 20
greet is a type named greet
```

The last line proves `greet` is a *type* (a struct type). Notes:

- `@import("std")` uses a module name; `@import("greet.zig")` uses a path relative to the
  importing file.
- Top-level declarations can come in any order. `shout` uses `volume`, defined below it.
- Comments: `//` is normal, `///` documents the declaration below, `//!` documents the whole file.
  There are no block comments.
- `greet.zig` has no `main`, so you can't `zig run` it. It has a `test` block, so you can test it:

```console
$ zig test examples/ch01/greet.zig
1/1 greet.test.shout multiplies by the volume...OK
All 1 tests passed.
```

Using a private declaration from outside is a compile error:

```zig
std.debug.print("{d}\n", .{greet.volume});
```

```text
private.zig:5:37: error: 'volume' is not marked 'pub'
    std.debug.print("{d}\n", .{greet.volume});
                               ~~~~~^~~~~~~
greet.zig:13:1: note: declared here
const volume = 10;
^~~~~~~~~~~~~~~~~
```

The same rule is why `main` must be `pub`. Without it: `error: 'main' is not marked 'pub'`.

A file can also have top-level fields. Then it's a struct type you create values of, and by
convention its name is capitalized (`Point.zig`). See [Chapter 7](07-structs-enums-unions.md).

## `zig fmt`: one style

`zig fmt` applies the one official style (4-space indents, spaces around operators, consistent
line breaks), so nobody argues about formatting.

```console
$ cat messy.zig
const std=@import("std");
pub fn main() void{
std.debug.print("{d}\n",.{1+2});
}
$ zig fmt --check messy.zig
messy.zig
$ zig fmt messy.zig
messy.zig
$ cat messy.zig
const std = @import("std");
pub fn main() void {
    std.debug.print("{d}\n", .{1 + 2});
}
```

- `zig fmt --check` lists files that need formatting and exits with status 1. Good for CI.
- `zig fmt FILE_OR_DIR` rewrites files in place and lists the ones it changed.

A trailing comma in a list tells `zig fmt` to put one item per line. Without it, the list stays
on one line.

```zig
std.debug.print("{d} {d}\n", .{ 1, 2, });   // before zig fmt
std.debug.print("{d} {d}\n", .{             // after zig fmt
    1,
    2,
});
```

Every file in this course is `zig fmt` clean. Most Zig-aware editors run it on save.

## Reading compiler errors

Zig errors have a fixed shape: `file:line:column: error: message`, the source line, a `^` under
the problem, then `note:` lines with context. Read the first error first.

A typo in a name:

```zig
std.debug.prnt("hi\n", .{});
```

```text
typo.zig:4:14: error: root source file struct 'debug' has no member named 'prnt'
    std.debug.prnt("hi\n", .{});
    ~~~~~~~~~^~~~~
…/lib/std/debug.zig:1:1: note: struct declared here
const std = @import("std.zig");
^~~~~
referenced by:
    callMain [inlined]: …/lib/std/start.zig:788:64
    …
```

"Root source file struct 'debug'": `std.debug` is the file `debug.zig`, and files are structs. The
`referenced by:` lines show how the compiler reached this code (from startup, through `main`).
You can usually skip them.

Ignoring a possible error:

```zig
stdout.print("Hello!\n", .{});
```

```text
notry.zig:8:17: error: error union of type 'error{WriteFailed}!void' is ignored
    stdout.print("Hello!\n", .{});
    ~~~~~~~~~~~~^~~~~~~~~~~~~~~~~
notry.zig:8:17: note: consider using 'try', 'catch', or 'if'
```

Writing can fail (full disk, closed pipe), and Zig won't let you ignore that. Add `try`.

A missing semicolon:

```text
semi.zig:4:33: error: expected ';' after statement
    std.debug.print("hi\n", .{})
                                ^
```

A format string that doesn't match its arguments (`"{s} is {d}\n"` with only `.{"x"}`):

```text
…/lib/std/Io/Writer.zig:803:13: error: too few arguments
            @compileError("too few arguments");
            ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
referenced by:
    print__func_785: …/lib/std/debug.zig:330:39
    main: args.zig:4:20
```

This one points into `std`, because format strings are checked by Zig code running at compile
time. Follow `referenced by` back to *your* line, `args.zig:4:20`.

> **Gotcha: unused code isn't fully checked.** Zig analyzes only code reachable from `main` (or a
> test). A function you never call can hold a type error and still compile. Simple mistakes (an
> unused variable, a missing `;`) are caught everywhere, since they need no type information. Call
> or test new code to get it checked.

Paths in this course's error messages are shortened to `…/`. Yours will be full paths.

## The Zen of Zig

`zig zen` prints the language's principles:

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

You've met several already: the explicit `init.io` and required `try` *communicate intent
precisely*; `zig fmt` lets you *focus on logic, not style*; a failing `print` is an *edge case
that matters*. [Chapter 20](20-design-and-next-steps.md) walks through the list with examples from
the course.

## Building seek: create the project

Real programs use the build system, not `zig run`. Create a folder and let `zig init` fill it:

```console
$ mkdir seek
$ cd seek
$ zig init
info: created build.zig
info: created build.zig.zon
info: created src/main.zig
info: created src/root.zig
info: see `zig build --help` for a menu of options
```

The project takes the folder's name. Try it unchanged:

```console
$ zig build run -- hello world
All your codebase are belong to us.
info: arg: ./zig-out/bin/seek
info: arg: hello
info: arg: world
Run `zig build test` to run the tests.
```

`zig build run` compiled the program, copied it to `zig-out/bin/seek`, and ran it. Arguments after
`--` go to the program. The first argument is the program's own path.

### The four generated files

| File | Purpose |
|------|---------|
| `build.zig` | The build script: Zig code describing what to build. |
| `build.zig.zon` | The package manifest: name, version, dependencies. |
| `src/main.zig` | The program. Its `main` uses `init.arena`, `init.minimal.args`, `std.log.info`, and a stdout writer. It has two tests. |
| `src/root.zig` | A small library module that `main.zig` imports as `@import("seek")`, showing how to share code as a package. |

`zig build` also creates two folders. Don't edit or commit them:

- `.zig-cache/` holds compiled pieces, so the next build is fast.
- `zig-out/` holds the results, like `zig-out/bin/seek`.

`seek` is one program, not a library, so trim the template.

### Step 1: delete the library

```console
$ rm src/root.zig
```

### Step 2: replace `build.zig`

The template wires up the library module and two sets of tests. Replace the whole file with:

`build.zig`

```zig
const std = @import("std");

// `zig build` runs this function to construct the build graph. Nothing is
// compiled here; we only describe *what* should be built and how.
pub fn build(b: *std.Build) void {
    // `-Dtarget=...` and `-Doptimize=...` on the command line.
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "seek",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    // `zig build` (the default "install" step) copies the binary to zig-out/bin.
    b.installArtifact(exe);

    // `zig build run -- ARGS` builds, installs, then runs seek with ARGS.
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    const run_step = b.step("run", "Run seek");
    run_step.dependOn(&run_cmd.step);

    // `zig build test` compiles and runs every `test` block reachable from main.zig.
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_tests.step);
}
```

The build script is a plain Zig program with a `pub fn build`. It compiles nothing itself; it adds
**steps** to a graph, and `zig build` runs the ones you ask for:

- **The executable**: `seek`, from `src/main.zig`, for the target and mode given on the command
  line (`-Dtarget=...`, `-Doptimize=...`; default: this machine, Debug).
- **`install`** (default step): copy the executable into `zig-out/bin/`.
- **`run`**: install, then run the program with the arguments after `--`.
- **`test`**: compile and run the `test` blocks in `src/main.zig`.

List the steps with `zig build -l`:

```console
$ zig build -l
  install (default)            Copy build artifacts to prefix path
  uninstall                    Remove build artifacts from prefix path
  run                          Run seek
  test                         Run unit tests
```

[Chapter 18](18-build-system.md) covers the build system in depth.

### Step 3: edit `build.zig.zon`

`.zon` (Zig Object Notation) is Zig's syntax for data. Remove the comments and set the version to
`0.1.0`. Keep **your own** `.fingerprint` line:

`build.zig.zon`

```zig
.{
    .name = .seek,
    .version = "0.1.0",
    .fingerprint = 0xd438fe97ff756a7e, // Changing this has security and trust implications.
    .minimum_zig_version = "0.17.0",
    .dependencies = .{},
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
    },
}
```

| Field | Meaning |
|-------|---------|
| `.name` | Package name, written `.seek`: an enum literal, not a string. |
| `.version` | Package version ([semantic versioning](https://semver.org)). |
| `.fingerprint` | A unique package ID, generated by `zig init` and tied to the name. Yours differs from the one above; keep yours. |
| `.minimum_zig_version` | Older compilers refuse to build the package. |
| `.dependencies` | Other packages needed. None. |
| `.paths` | Files that belong to the package when someone depends on it. |

### Step 4: replace `src/main.zig`

`src/main.zig`

```zig
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    // Program output goes to stdout through a buffered writer. The buffer
    // lives on the stack; nothing reaches the terminal until we flush.
    // "Streaming" means: just append, the way a terminal or pipe works. (The
    // plain `.init` would write at explicit file offsets, starting at 0,
    // which can overwrite earlier output when stdout is redirected to a file.)
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("usage: seek [OPTIONS] PATTERN [PATH ...]\n", .{});
    try stdout.flush(); // Don't forget to flush!
}
```

Compared with the template, we dropped the library import, argument logging, and tests, and
switched the writer from `.init` to `.initStreaming` (see the gotcha in
[Printing](#printing-stddebugprint-vs-stdout)). The usage line is the interface `seek` will grow
into: options, a pattern, then zero or more paths.

### Checkpoint

```console
$ zig build run
usage: seek [OPTIONS] PATTERN [PATH ...]
$ ./zig-out/bin/seek
usage: seek [OPTIONS] PATTERN [PATH ...]
$ zig build test
$ zig fmt --check .
```

`zig build test` prints nothing: no tests yet, and success is silent (add `--summary all` to see
what ran). `zig fmt --check .` prints nothing when every file is formatted.

If you use git, ignore the build folders:

```console
$ printf '.zig-cache/\nzig-out/\n' > .gitignore
```

The complete project at this point is in `project/ch01/`.

## Summary

- Zig targets robust, optimal, reusable software: no hidden control flow, no hidden allocations,
  no macros, and `comptime` for metaprogramming. This course needs exactly Zig 0.17.0.
- `zig run` tries a file, `zig build-exe` makes an executable, `zig test` runs tests, `zig fmt`
  formats, `zig init` + `zig build` manage projects.
- Debug is the default mode. `-O safe|fast|small` (or `-Doptimize=` for `zig build`) changes it.
- `pub fn main(init: std.process.Init) !void` receives I/O, allocators, and arguments explicitly.
  Return `u8` to set the exit status.
- `std.debug.print` writes to stderr, unbuffered. Real output goes to a buffered stdout writer.
  Always `flush()`.
- Every file is a struct. `@import` returns it; only `pub` declarations are visible outside.
- Compile errors read `file:line:col: error: message` plus notes. Possible errors must be handled
  (`try`).
- `zig build` uses `build.zig` (a Zig program that builds a step graph) and `build.zig.zon` (the
  manifest).

## Exercises

1. Change `examples/ch01/hello.zig` to print `Hello, <your name>! 6 * 7 = 42`, computing `42` in
   the code. Use one `print` call with `{s}` and `{d}`.

   <details><summary>Solution</summary>

   ```zig
   const std = @import("std");

   pub fn main(init: std.process.Init) !void {
       var buffer: [1024]u8 = undefined;
       var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &buffer);
       const stdout = &stdout_writer.interface;

       try stdout.print("Hello, {s}! 6 * 7 = {d}\n", .{ "Ada", 6 * 7 });
       try stdout.flush();
   }
   ```

   ```console
   $ zig run hello.zig
   Hello, Ada! 6 * 7 = 42
   ```

   </details>

2. Make `volume` in `greet.zig` usable from `use_greet.zig`, and print it there.

   <details><summary>Solution</summary>

   In `greet.zig`, add `pub`:

   ```zig
   pub const volume = 10;
   ```

   In `use_greet.zig`'s `main`, add:

   ```zig
   std.debug.print("volume = {d}\n", .{greet.volume});
   ```

   ```console
   $ zig run use_greet.zig
   Hello, world!
   shout(2) = 20
   greet is a type named greet
   volume = 10
   ```

   </details>

3. In `seek`'s `src/main.zig`, add `std.debug.print("debug: seek started\n", .{});` as the first
   line of `main`. After `zig build`, predict the output of `./zig-out/bin/seek` and
   `./zig-out/bin/seek 2>/dev/null`, then check. Remove the line afterwards so your code matches
   the snapshots.

   <details><summary>Solution</summary>

   ```console
   $ ./zig-out/bin/seek
   debug: seek started
   usage: seek [OPTIONS] PATTERN [PATH ...]
   $ ./zig-out/bin/seek 2>/dev/null
   usage: seek [OPTIONS] PATTERN [PATH ...]
   ```

   The debug line goes to stderr, which `2>/dev/null` discards.

   </details>

4. Build `seek` with `zig build -Doptimize=small` and compare the size of `zig-out/bin/seek` with
   a normal `zig build`.

   <details><summary>Solution</summary>

   ```console
   $ zig build && ls -l zig-out/bin/seek
   -rwxr-xr-x 1 you you 13358136 Oct 27 11:47 zig-out/bin/seek
   $ zig build -Doptimize=small && ls -l zig-out/bin/seek
   -rwxr-xr-x 1 you you 148800 Oct 27 11:47 zig-out/bin/seek
   ```

   Exact numbers vary; the small build is far smaller. The Debug binary carries debug info and
   safety checks.

   </details>

5. Delete the `try` before `stdout.flush()` in `seek`'s `main.zig` and run `zig build`. What does
   the compiler say, and why?

   <details><summary>Solution</summary>

   ```console
   $ zig build
   install
   +- install seek
      +- compile exe seek debug native 1 errors
   src/main.zig:14:17: error: error union of type 'error{WriteFailed}!void' is ignored
       stdout.flush(); // Don't forget to flush!
       ~~~~~~~~~~~~^~
   src/main.zig:14:17: note: consider using 'try', 'catch', or 'if'
   …
   Build Summary: 0/3 steps succeeded (1 failed)
   …
   ```

   `flush` really writes to the terminal or file, which can fail, and Zig won't let you ignore an
   error silently. Put the `try` back.

   </details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-1--getting-started)
