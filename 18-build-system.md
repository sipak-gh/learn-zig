# Chapter 18 — The Build System

Since [Chapter 1](01-getting-started.md), `zig build` has built, run, and tested `seek`. This
chapter opens `build.zig`: a Zig program that describes a graph of steps. It covers step
dependencies, target and optimize options, modules and imports, your own `-D` options and passing
values to the program, package dependencies, and cross-compiling. `seek` gets its version from the
build, its help text moves into a file embedded at compile time, and we build release binaries for
Windows, macOS, and ARM Linux. [Chapter 17](17-json.md) added `--json`;
[Chapter 19](19-low-level.md) covers safety checks, SIMD, and C.

## `build.zig` is a Zig program

`seek`'s `build.zig`, unchanged since [Chapter 1](01-getting-started.md):

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

No separate build language (Makefile, CMake, YAML): it's Zig, with the same types, error handling,
`if`, and `for` as `seek`. `zig build` compiles `build.zig` into a small program, the *build
runner*, and runs it.

`build` doesn't compile anything. Every `b.add…` call creates a **step**, a node in a graph, and
returns a pointer to it. After `build` returns, the runner takes the steps named on the command
line, follows their dependencies, and runs what's needed, in parallel where it can.

### Steps and `dependOn`

`seek`'s build creates these steps:

| Call | Step | Does |
|------|------|------|
| `b.addExecutable(…)` | `compile exe seek` | Compiles `src/main.zig` into an executable. |
| `b.installArtifact(exe)` | `install seek` | Copies it to `zig-out/bin/`; part of the default `install` step. |
| `b.addRunArtifact(exe)` | `run exe seek` | Runs the executable; depends on the compile step. |
| `b.addTest(…)` | `compile test` | Compiles the module in test mode. |
| `b.addRunArtifact(exe_tests)` | `run test` | Runs the test binary and collects results. |
| `b.step("run", "Run seek")` | `run` | A named top-level step that does nothing itself. |
| `b.step("test", "Run unit tests")` | `test` | The same, for tests. |

`a.dependOn(&b.step)` adds an edge: `a` runs after `b`. Named steps (from `b.step`) can be asked
for on the command line; `zig build -l` lists them:

```console
$ zig build -l
  install (default)            Copy build artifacts to prefix path
  uninstall                    Remove build artifacts from prefix path
  run                          Run seek
  test                         Run unit tests
```

`--summary all` prints the part of the graph that ran as a tree, dependencies indented below:

```console
$ zig build --summary all
Build Summary: 4/4 steps succeeded
install success
+- install seek success
   +- compile exe seek debug native success 369ms MaxRSS:160M
      +- options cached

$ zig build run --summary all -- --version
seek 0.1.0
Build Summary: 6/6 steps succeeded
run success
+- run exe seek success 4ms
   +- compile exe seek debug native cached 4ms MaxRSS:40M
   |  +- options cached
   +- install success
      +- install seek cached
         +- compile exe seek debug native (+1 more reused dependencies)

```

(Taken after this chapter's changes, which add the `options` step. Timings differ.)

- `run` depends on `run exe seek`, which depends on the compile step and, through
  `run_cmd.step.dependOn(b.getInstallStep())`, on `install`. Without that line, `zig build run`
  would run the binary from the cache without copying it to `zig-out/bin`.
- The compile step appears twice but ran once: steps are shared, and results are cached between
  runs. `cached` means the inputs didn't change.
- `run_cmd.addPassthruArgs()` passes everything after `--` to the program. Without it,
  `zig build run -- --version` would ignore `--version`.
- If nothing changed since the last successful test run, `zig build test` doesn't rerun the tests
  and prints nothing. `--summary all` shows the count.

## Target and optimize mode

`b.standardTargetOptions(.{})` and `b.standardOptimizeOption(.{})` add the `-Dtarget`, `-Dcpu`,
and `-Doptimize` options and return what the user picked. `zig build -h` lists a project's options
under "Project-Specific Options":

```console
$ zig build -h | sed -n '/Project-Specific Options/,/^$/p'
Project-Specific Options:
  -Dtarget=[string]            The CPU architecture, OS, and ABI to build for
  -Dcpu=[string]               Target CPU features to add or subtract
  -Dofmt=[string]              Target object format
  -Ddynamic-linker=[string]    Path to interpreter on the target system
  -Doptimize=[enum]            Prioritize performance, safety, or binary size
                                 Supported Values:
                                   debug
                                   safe
                                   fast
                                   small
  -Dversion=[string]           Version string for --version

```

(`-Dversion` is added in this chapter.) The full help, about a hundred lines, also lists general
flags like `--summary`, `--release`, `-j`, and `--prefix`.

### The four optimize modes

| Mode | `-Doptimize=` | Optimized | Safety checks | Debug info | `seek` size |
|------|---------------|-----------|---------------|------------|-------------|
| Debug | `debug` (default) | no | yes | yes | 17.8 MB |
| ReleaseSafe | `safe` | yes | yes | yes | 4.5 MB |
| ReleaseFast | `fast` | yes | no | yes | 4.8 MB |
| ReleaseSmall | `small` | for size | no | no | 200 KB |

Sizes are for `seek` on x86_64 Linux:

```console
$ rm -rf zig-out; zig build && wc -c < zig-out/bin/seek
17787512
$ rm -rf zig-out; zig build -Doptimize=safe && wc -c < zig-out/bin/seek
4534224
$ rm -rf zig-out; zig build -Doptimize=small && wc -c < zig-out/bin/seek
200472
$ rm -rf zig-out; zig build --release=fast && wc -c < zig-out/bin/seek
4761464
```

- Most of a Debug binary is debug info, which maps addresses to the file and line numbers in stack
  traces. `small` drops it.
- `--release=fast` is short for `-Doptimize=fast`. Plain `--release` uses the project's preferred
  release mode, set with `b.standardOptimizeOption(.{ .preferred_optimize_mode = .safe })`; `seek`
  sets none, so plain `--release` asks you to choose.
- "Safety checks" are the checks for *illegal behavior*: integer overflow, out-of-bounds indexing,
  unwrapping `null`, reaching `unreachable`, and more. In `debug` and `safe` they panic with a
  message. In `fast` and `small` the compiler assumes they never happen: faster, smaller code, and
  unpredictable bugs. [Chapter 19](19-low-level.md) catalogs them.

Code can read the mode at compile time: `builtin.mode` is a `std.lang.Optimize`, and
`std.debug.runtime_safety` says whether safety checks are on.

`examples/ch18/modes.zig`

```zig
const std = @import("std");
const builtin = @import("builtin");

pub fn main(init: std.process.Init) !void {
    var buffer: [256]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &buffer);
    const out = &stdout_writer.interface;

    // Both are comptime-known: code can branch on the build mode for free.
    try out.print("mode: {t}\n", .{builtin.mode});
    try out.print("runtime safety: {}\n", .{std.debug.runtime_safety});
    if (builtin.mode == .debug) try out.writeAll("(extra checks could go here)\n");
    try out.flush();
}
```

```console
$ zig run examples/ch18/modes.zig
mode: debug
runtime safety: true
(extra checks could go here)
$ zig run -O safe examples/ch18/modes.zig
mode: safe
runtime safety: true
$ zig run -O fast examples/ch18/modes.zig
mode: fast
runtime safety: false
$ zig run -O small examples/ch18/modes.zig
mode: small
runtime safety: false
```

Since `builtin.mode` is comptime-known, the `if` is free: release builds don't compile the branch.

> **Version note.** Zig 0.17 renamed `std.builtin.OptimizeMode` to `std.lang.Optimize`, with
> lowercase values `debug`, `safe`, `fast`, and `small`. Older tutorials write
> `-Doptimize=ReleaseSafe` and `.ReleaseFast`. The old spellings are still accepted as deprecated
> aliases (`zig build -Doptimize=ReleaseSafe` works), but use the new ones.

A wrong value is an error:

```console
$ zig build -Doptimize=nope 2>&1 | head -1
error: expected -Doptimize to be of type "lang.Optimize"
```

### Which mode to ship

- **`safe`**: the usual choice for a program like `seek`. Fast, and a bug that slips through stops
  the program with a message instead of producing garbage.
- **`fast`**: for well-tested code where you've measured that safety checks cost too much. You can
  also turn checks off for one hot function or block with `@setRuntimeSafety(false)`
  ([Chapter 19](19-low-level.md)) and keep `safe` elsewhere.
- **`small`**: for size-constrained places: embedded devices, WebAssembly, tiny containers.
- **`debug`**: for development. Compiles fastest.

## Modules and imports

A **module** is a root source file plus its settings: target, optimize mode, and named imports.
`b.createModule(.{ .root_source_file = …, .target = …, .optimize = … })` makes one. Executables
and tests have a *root module*; in `seek` both share `exe.root_module`, so tests compile with the
program's exact settings.

`@import` takes one of two kinds of argument:

- **A file path** ending in `.zig`, like `@import("search.zig")`: relative to the importing file,
  and it must stay inside the module's root directory, the folder of the root source file (`src/`
  for `seek`).
- **A module name**, like `@import("std")` or `@import("builtin")`. `std` and `builtin` are always
  there; the build must provide any others.

Add a named import in `createModule`:

```zig
.imports = &.{
    .{ .name = "greet", .module = greet_module },
},
```

or later with `exe.root_module.addImport("greet", greet_module)`. You'll see both below. A module
without a `.target` (like a library module) takes the target and mode of whatever imports it.

Importing a name the build didn't provide is a compile error. Here's `seek` from this chapter with
the `addOptions` line missing from `build.zig`:

```console
$ zig build
install
+- install seek
   +- compile exe seek debug native 1 errors
src/main.zig:6:25: error: no module named 'build_options' available within module 'root'
const version = @import("build_options").version;
                        ^~~~~~~~~~~~~~~
referenced by:
    run: src/main.zig:79:42
…
```

`root` is the default name of an executable's root module.

## Your own options: `b.option` and `b.addOptions`

`b.option(T, name, description)` declares a `-D` option and returns `?T`: the command-line value,
or `null` if none was given. Supported types include `bool`, integers, floats, enums,
`[]const u8`, and `[]const []const u8` (a repeatable option). It shows up in `zig build -h`, and
typos are caught:

```console
$ zig build -Dnope=1 2>&1 | head -2
error: invalid option: "nope"
info: available option: "target": The CPU architecture, OS, and ABI to build for
```

A `bool` option can be given as `-Dname` (true), `-Dname=true`, or `-Dname=false`. An enum option
accepts its field names, which `zig build -h` lists, as for `-Doptimize`.

The value lives in the build runner, not your program. To pass it on, put it in an **options
module**:

```zig
const options = b.addOptions();
options.addOption([]const u8, "version", version);
exe.root_module.addOptions("build_options", options);
```

`b.addOptions()` creates a step that writes a Zig source file, and `addOptions("build_options",
options)` makes it importable as `@import("build_options")`. For `seek` the generated file lives in
`.zig-cache/` and contains one line:

```zig
pub const version: []const u8 = "0.1.0";
```

That's the `options` step in the `--summary` trees. When the value changes, the file changes, and
everything importing it recompiles. The constant is comptime-known, so the program can use it
wherever a literal works: in `++`, as an array length, in an `if` that removes code.

### Reading `build.zig.zon` from `build.zig`

`build.zig` can `@import("build.zig.zon")` and get the manifest as a comptime value, so
`@import("build.zig.zon").version` is `"0.1.0"`. The version stays in one place.

Your program can't do this: `build.zig.zon` is outside `src/`, the program module's root
directory. The value must travel through an options module.

## Packages and dependencies

`build.zig.zon` is the package manifest; you saw its fields in [Chapter 1](01-getting-started.md)
and its syntax (ZON) in [Chapter 17](17-json.md). Two matter when other packages are involved:

- **`.fingerprint`**: a random 64-bit ID from `zig init`, tied to `.name`. Together they identify
  the package, so two packages with the same name can't be mixed up. Don't change it or copy it
  into a new project. Let `zig init` make one, or leave it out and use the one Zig suggests:

  ```console
  $ zig build
  build.zig.zon:1:2: error: missing top-level 'fingerprint' field; suggested value: 0x2df8175b083ec3c0
  .{
   ^
  ```

  (Yours will differ.) If you fork a project and publish it as a separate package, give it a new
  fingerprint.
- **`.paths`**: the files that make up the package. Dependents fetch and hash only these. `seek`
  lists `build.zig`, `build.zig.zon`, and `src`.

### A local dependency

`seek` depends only on the standard library and will stay that way. To show dependencies, we'll
build two tiny packages in a folder outside `seek`: a library `greet` and a program `hello` that
uses it. A local folder keeps the example offline; an internet dependency works the same, with a
URL instead of a path.

```
deps/
├── greet/
│   ├── build.zig
│   ├── build.zig.zon
│   └── src/root.zig
└── hello/
    ├── build.zig
    ├── build.zig.zon
    └── src/main.zig
```

`greet/src/root.zig`

```zig
const std = @import("std");

pub fn hello(writer: *std.Io.Writer, name: []const u8) !void {
    try writer.print("hello from greet, {s}!\n", .{name});
}
```

`greet/build.zig`

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    // addModule (not createModule) makes the module visible to packages
    // that depend on this one.
    _ = b.addModule("greet", .{
        .root_source_file = b.path("src/root.zig"),
    });
}
```

`greet/build.zig.zon` (use the fingerprint Zig suggests for you):

```zig
.{
    .name = .greet,
    .version = "0.1.0",
    .fingerprint = 0x2df8175b083ec3c0,
    .minimum_zig_version = "0.17.0",
    .paths = .{ "build.zig", "build.zig.zon", "src" },
}
```

`b.addModule` is `createModule` plus a name other packages can find the module by. The module has
no target or mode of its own, so it takes those of the program that imports it.

The program declares the dependency in its manifest; `.path` points to a folder:

`hello/build.zig.zon`

```zig
.{
    .name = .hello,
    .version = "0.1.0",
    .fingerprint = 0x3610a68675b205ca,
    .minimum_zig_version = "0.17.0",
    .dependencies = .{
        .greet = .{ .path = "../greet" },
    },
    .paths = .{ "build.zig", "build.zig.zon", "src" },
}
```

`b.dependency("greet", .{})` runs `greet`'s `build.zig` and returns a handle. `.module("greet")`
looks up the module `greet` exported with `addModule`:

`hello/build.zig`

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The package named in build.zig.zon, built for our target and mode.
    const greet_dep = b.dependency("greet", .{});

    const exe = b.addExecutable(.{
        .name = "hello",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "greet", .module = greet_dep.module("greet") },
            },
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.addPassthruArgs();
    b.step("run", "Run hello").dependOn(&run_cmd.step);
}
```

The second argument of `b.dependency` is an anonymous struct of `-D` options for the dependency's
`build.zig`; `greet` has none.

`hello/src/main.zig`

```zig
const std = @import("std");
const greet = @import("greet");

pub fn main(init: std.process.Init) !void {
    var buffer: [256]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &buffer);
    const out = &stdout_writer.interface;
    try greet.hello(out, "seek");
    try out.flush();
}
```

```console
$ cd deps/hello
$ zig build run
hello from greet, seek!
```

A `.path` dependency is read from the folder every time, so changes to `greet` show up in `hello`
immediately. Handy for packages developed together in one repository.

### `zig fetch --save`

The other kind of dependency is fetched once and pinned by a hash. `zig fetch --save` adds it to
`build.zig.zon`. It accepts a URL (a `.tar.gz`, a `.zip`, or `git+https://…`) or, as here, a local
path. Remove the `.greet = .{ .path = … }` line, then:

```console
$ zig fetch --save ../greet
$ cat build.zig.zon
.{
    .name = .hello,
    .version = "0.1.0",
    .fingerprint = 0x3610a68675b205ca,
    .minimum_zig_version = "0.17.0",
    .dependencies = .{
        .greet = .{
            .url = "../greet",
            .hash = "greet-0.1.0-wMM-CFQCAACag9LT6FSoD1FsWka3rjGs9VsRg9RxVuSA",
        },
    },
    .paths = .{ "build.zig", "build.zig.zon", "src" },
}
$ ls
build.zig  build.zig.zon  src  zig-pkg
$ ls zig-pkg
greet-0.1.0-wMM-CFQCAACag9LT6FSoD1FsWka3rjGs9VsRg9RxVuSA
$ zig build run
hello from greet, seek!
```

- The hash covers the files in `greet`'s `.paths` and starts with the name and version.
- Zig unpacked a copy into `zig-pkg/` inside the project, and builds use that copy: editing
  `../greet` changes nothing until you fetch again.
- If the content behind a URL changes, the hash no longer matches and the build fails, so a
  dependency can't change under you.
- With a real URL, `zig build` fetches missing packages itself. Run `zig fetch --save` again to
  update.

> **Version note.** Zig 0.17 puts fetched packages in `zig-pkg/` inside the project (as well as the
> global cache). Older versions used only the global cache. Committing `zig-pkg/` makes builds work
> offline; ignoring it keeps the repository small.

## Cross-compiling

Zig ships everything it needs to build for other systems: its own linker, the standard library,
and libc headers and sources for many targets. Nothing to install. Pass `-Dtarget=` with a target
triple, *architecture-os-abi*; omitted parts get defaults:

```console
$ rm -rf zig-out; zig build -Dtarget=x86_64-windows && ls zig-out/bin && file zig-out/bin/seek.exe
seek.exe
seek.pdb
zig-out/bin/seek.exe: PE32+ executable (console) x86-64, for MS Windows
$ rm -rf zig-out; zig build -Dtarget=aarch64-macos -Doptimize=safe && file zig-out/bin/seek
zig-out/bin/seek: Mach-O 64-bit arm64 executable, flags:<NOUNDEFS|DYLDLINK|TWOLEVEL|NO_REEXPORTED_DYLIBS|PIE|HAS_TLV_DESCRIPTORS>
$ rm -rf zig-out; zig build -Dtarget=aarch64-linux-musl -Doptimize=small && file zig-out/bin/seek
zig-out/bin/seek: ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV), statically linked, stripped
$ rm -rf zig-out; zig build
```

We can't run these here, but `file` confirms them: a Windows executable (debug info in
`seek.pdb`), a macOS executable for Apple silicon, and a static Linux binary for ARM servers or a
Raspberry Pi. The last command restores the native build.

`zig targets` prints every architecture, OS, and ABI Zig knows, as ZON. It's long:

```console
$ zig targets | head -c 120; echo
.{
    .arch = .{
        "aarch64",
        "aarch64_be",
        "alpha",
        "amdgcn",
        "arc",
        "ar
error: WriteFailed
```

The `error: WriteFailed` is `zig` noticing that `head` closed the pipe. (`seek` does the same;
[Chapter 20](20-design-and-next-steps.md) comes back to it.)

### Cross-compiling finds portability bugs

In [Chapter 16](16-testing.md), `Searcher.init` set `.dir = .cwd()` with the comment "Not a field
default: on some systems (Windows) the current directory handle is only known at run time". Here's
what a field default does. Change the field in `src/search.zig` to

```zig
    dir: Io.Dir = .cwd(),
```

and remove the `.dir = .cwd(),` line from `init`. The native Linux build still works. Windows
doesn't:

```console
$ zig build -Dtarget=x86_64-windows
install
+- install seek
   +- compile exe seek debug x86_64-windows 1 errors
…/lib/std/os/windows.zig:3717:20: error: unable to evaluate comptime expression
            return asm (
                   ^~~
…/lib/std/Io/Dir.zig:90:52: note: called at comptime from here
        .windows => .{ .handle = std.os.windows.peb().ProcessParameters.CurrentDirectory.Handle },
                                 ~~~~~~~~~~~~~~~~~~^~
src/search.zig:46:23: note: called at comptime from here
    dir: Io.Dir = .cwd(),
                  ~~~~^~
src/search.zig:46:23: note: struct field default value must be comptime-known
referenced by:
    init: src/search.zig:74:17
    run: src/main.zig:88:39
    5 reference(s) hidden; use '-freference-trace=7' to see all references
error: 1 compilation errors
failed command: …
```

A field default must be comptime-known. On Linux, `Io.Dir.cwd()` returns the constant `AT_FDCWD`;
on Windows it reads the handle from the process environment block at run time. Undo the change. A
cross-compile catches such problems without a Windows machine.

## `@embedFile` in a project

[Chapter 12](12-comptime.md) introduced `@embedFile`: it reads a file at compile time and gives its
bytes as a constant. Its type is `*const [N:0]u8`, like a string literal's, so you can slice it and
concatenate it with `++`, all at compile time:

`examples/ch18/banner.txt`

```
seek: find lines that match
(embedded at compile time)
```

`examples/ch18/embed.zig`

```zig
const std = @import("std");

// The path is relative to this source file. The bytes become part of the
// executable; banner.txt is not needed at run time.
const banner = @embedFile("banner.txt");

// Everything below runs at compile time: banner is comptime-known.
const first_line = banner[0 .. std.mem.findScalar(u8, banner, '\n').? + 1];
const line_count = std.mem.countScalar(u8, banner, '\n');
const shouted = "== " ++ first_line;

pub fn main(init: std.process.Init) !void {
    var buffer: [256]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &buffer);
    const out = &stdout_writer.interface;

    try out.print("type: {s}\n", .{@typeName(@TypeOf(banner))});
    try out.print("lines: {d}\n", .{line_count});
    try out.writeAll(shouted);
    try out.writeAll(banner);
    try out.flush();
}
```

```console
$ zig run examples/ch18/embed.zig
type: *const [55:0]u8
lines: 2
== seek: find lines that match
seek: find lines that match
(embedded at compile time)
```

Top-level declarations are evaluated at compile time, so `first_line`, `line_count`, and `shouted`
are constants in the binary; nothing is computed at startup.

The build tracks embedded files: change `banner.txt` and the next build recompiles. Two errors to
know:

- A missing file: `error: failed opening "usage.md": FileNotFound`.
- A path outside the module's root directory is refused, as with `@import`:

  ```console
  $ zig build
  …
  src/main.zig:10:31: error: embed of file outside package path: '../README'
  const usage_text = @embedFile("../README");
                                ^~~~~~~~~~~
  ```

  Keep embedded files inside `src/` (or wherever the root source file is).

## `zig cc`: a C compiler in the box

Zig contains Clang, so `zig` is also a C and C++ compiler. `zig cc` and `zig c++` accept the usual
`cc` flags, and with `-target` they cross-compile C as easily as Zig:

```console
$ cat hello.c
#include <stdio.h>
int main(void) { printf("hello from C\n"); return 0; }
$ zig cc -o hello hello.c && ./hello
hello from C
$ zig cc -target aarch64-linux-musl -o hello-arm hello.c && file hello-arm
hello-arm: ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV), statically linked, with debug_info, not stripped
```

Many projects that never use Zig use `zig cc` as a drop-in cross-compiler. `build.zig` can also
compile C files into a Zig program; [Chapter 19](19-low-level.md) shows how.

## Building seek: version from the build, embedded help

Two changes:

- `--version` prints a version from the build: `-Dversion=…` sets it, defaulting to `.version` in
  `build.zig.zon`.
- The top of `--help` moves into its own file, `src/usage.txt`, which `main.zig` embeds. It gains a
  line about the exit status.

### `build.zig`: the `version` option

Add the option and the options module after `standardOptimizeOption`:

```zig
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // A project-specific option: `zig build -Dversion=1.2.3`. Without it,
    // the version comes from build.zig.zon, which build.zig can @import.
    const version = b.option([]const u8, "version", "Version string for --version") orelse
        @import("build.zig.zon").version;

    // Values computed here become a module that the program imports as
    // @import("build_options").
    const options = b.addOptions();
    options.addOption([]const u8, "version", version);
```

`b.option` returns `?[]const u8`; `orelse` supplies the default. Give the module to the executable
right after `addExecutable`:

```zig
    exe.root_module.addOptions("build_options", options);
    // `zig build` (the default "install" step) copies the binary to zig-out/bin.
    b.installArtifact(exe);
```

The tests share the root module, so they can import `build_options` too. Update the comment above
the test step:

```zig
    // `zig build test` builds main.zig in test mode and runs its tests. The
    // tests share the executable's module, build_options included.
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
```

The complete `build.zig`:

`build.zig`

```zig
const std = @import("std");

// `zig build` runs this function to construct the build graph. Nothing is
// compiled here; we only describe *what* should be built and how.
pub fn build(b: *std.Build) void {
    // `-Dtarget=...` and `-Doptimize=...` on the command line.
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // A project-specific option: `zig build -Dversion=1.2.3`. Without it,
    // the version comes from build.zig.zon, which build.zig can @import.
    const version = b.option([]const u8, "version", "Version string for --version") orelse
        @import("build.zig.zon").version;

    // Values computed here become a module that the program imports as
    // @import("build_options").
    const options = b.addOptions();
    options.addOption([]const u8, "version", version);

    const exe = b.addExecutable(.{
        .name = "seek",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addOptions("build_options", options);
    // `zig build` (the default "install" step) copies the binary to zig-out/bin.
    b.installArtifact(exe);

    // `zig build run -- ARGS` builds, installs, then runs seek with ARGS.
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    const run_step = b.step("run", "Run seek");
    run_step.dependOn(&run_cmd.step);

    // `zig build test` builds main.zig in test mode and runs its tests. The
    // tests share the executable's module, build_options included.
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_tests.step);
}
```

`build.zig.zon` doesn't change; `.version` is still `"0.1.0"`.

### `src/usage.txt`: the help text

Create `src/usage.txt` with these five lines (end the last with a newline):

`src/usage.txt`

```
usage: seek [OPTIONS] PATTERN [PATH ...]

Search each PATH (default: .) for lines containing PATTERN.
Directories are searched recursively; - means standard input.
Exit status: 0 if a line was selected, 1 if not, 2 if there was trouble.
```

A text file is easier to edit than a multiline string literal, even for someone who doesn't know
Zig.

### `src/main.zig`: use both

At the top of `src/main.zig`, replace the `version`, `usage`, and `help` constants:

```zig
const version = "0.1.0";

const usage = "usage: seek [OPTIONS] PATTERN [PATH ...]\n";

// cli.help runs at compile time, so `help` is one constant string.
const help = usage ++
    \\
    \\Search each PATH (default: .) for lines containing PATTERN.
    \\Directories are searched recursively; - means standard input.
    \\
    \\options:
    \\
++ cli.help(Options);
```

with:

```zig
const version = @import("build_options").version;

/// The text at the top of --help, kept in its own file and embedded into
/// the executable at compile time.
const usage_text = @embedFile("usage.txt");

/// The first line of usage.txt, printed after usage errors. Slicing a
/// comptime-known string at the top level happens at compile time.
const usage = usage_text[0 .. std.mem.findScalar(u8, usage_text, '\n').? + 1];

// cli.help runs at compile time, so `help` is one constant string.
const help = usage_text ++ "\noptions:\n" ++ cli.help(Options);
```

Nothing else in `main.zig` changes: `version`, `usage`, and `help` are still comptime-known strings
used as before. `usage` is the file's first line including its `\n`, the same text as the old
constant. If someone deleted every newline from `usage.txt`, `findScalar` would return `null` and
`.?` would fail **at compile time**, before the bug could reach users.

### Checkpoint

```console
$ zig build test --summary all
Build Summary: 4/4 steps succeeded; 24/24 tests passed
test success
+- run test 24 pass (24 total) 12ms MaxRSS:6M
   +- compile test debug native success 384ms MaxRSS:169M
      +- options success

$ zig build && ./zig-out/bin/seek --version
seek 0.1.0
$ ./zig-out/bin/seek -h
usage: seek [OPTIONS] PATTERN [PATH ...]

Search each PATH (default: .) for lines containing PATTERN.
Directories are searched recursively; - means standard input.
Exit status: 0 if a line was selected, 1 if not, 2 if there was trouble.

options:
  -i, --ignore-case              ignore case when matching
  -v, --invert                   select lines that do NOT match
  -W, --wildcard                 PATTERN is a wildcard (* and ?) matched against the whole line
  -n, --line-numbers             print line numbers
  -c, --count-only               print only a count of selected lines per file
  -l, --files-only               print only names of files with selected lines
  -m, --max-count N              stop after N selected lines per file
      --hidden                   search hidden files and directories
      --glob GLOB                only search files whose name matches GLOB (* and ?)
      --color auto|always|never  highlight matches
      --json                     print results as JSON Lines (one object per line)
      --stats                    print statistics to stderr when done
  -j, --jobs N                   search N files at a time (default: number of CPUs)
  -h, --help                     show this help
      --version                  show the version
$ ./zig-out/bin/seek --nope; echo "exit $?"
seek: unknown flag '--nope'
usage: seek [OPTIONS] PATTERN [PATH ...]
exit 2
$ zig build -Dversion=2.0.0-beta && ./zig-out/bin/seek --version
seek 2.0.0-beta
$ zig build && ./zig-out/bin/seek --version
seek 0.1.0
$ zig build run -- -n fox testdata/poem.txt
testdata/poem.txt:1:The quick brown fox
```

(Timings differ.) The test count is unchanged: no new behavior, and the compiler checks the help
text. `-Dversion` isn't sticky: the next `zig build` without it returns to the `build.zig.zon`
version (and recompiles, since the options file changed).

Release builds and cross-compiles work as shown earlier. Finish with a plain `zig build` so
`zig-out/bin/seek` is the native Debug binary again.

The complete project at this point is in `project/ch18/`.

## Summary

- `build.zig` is Zig. `build` creates steps in a graph; `zig build STEP` runs a step and its
  dependencies, caching results. `dependOn` adds edges, `b.step` makes named steps, `zig build -l`
  lists them, `--summary all` shows what ran.
- `standardTargetOptions` and `standardOptimizeOption` add `-Dtarget` and `-Doptimize`. Modes are
  `debug`, `safe`, `fast`, and `small` (lowercase in 0.17); `safe` keeps safety checks, `fast` and
  `small` drop them. `builtin.mode` tells code which one it is.
- A module is a root source file plus target, mode, and named imports. `@import("x.zig")` imports
  files inside the module's directory; `@import("name")` imports modules the build provides.
- `b.option(T, name, help)` declares a `-D` option. `b.addOptions()` plus
  `root_module.addOptions("build_options", …)` passes build-time values to the program as comptime
  constants.
- `build.zig.zon`: `.fingerprint` identifies the package, `.paths` lists its files,
  `.dependencies` lists other packages by `.path` or by `.url` and `.hash`. `zig fetch --save` adds
  a dependency; `b.dependency(name, .{}).module(name)` uses one; `b.addModule` exports one.
- `-Dtarget=arch-os-abi` cross-compiles with nothing to install; `zig targets` lists targets.
- `@embedFile` embeds a file from inside the module's directory as a comptime string.
- `zig cc` is a cross-compiling C compiler.

## Exercises

1. Make `seek --version` also print the build mode, like `seek 0.1.0 (safe)`.

   <details><summary>Solution</summary>

   The mode is `@import("builtin").mode`, and `{t}` prints an enum's tag name. In `run` in
   `src/main.zig`:

   ```zig
   if (options.version) {
       try stdout.print("seek {s} ({t})\n", .{ version, @import("builtin").mode });
       return .ok;
   }
   ```

   ```console
   $ zig build && ./zig-out/bin/seek --version
   seek 0.1.0 (debug)
   $ zig build -Doptimize=safe && ./zig-out/bin/seek --version
   seek 0.1.0 (safe)
   ```

   No build option needed: every module can import `builtin`.

   </details>

2. Add a `bool` option `-Dstrip` that leaves debug info out of the binary. (`createModule` has a
   `.strip` field of type `?bool`.) Compare the sizes of `zig build`, `zig build -Dstrip`, and
   `zig build -Doptimize=safe -Dstrip`.

   <details><summary>Solution</summary>

   In `build.zig`, before `addExecutable`:

   ```zig
   // `zig build -Dstrip=true` leaves debug info out of the binary.
   const strip = b.option(bool, "strip", "Omit debug information");
   ```

   and in `createModule`:

   ```zig
           .optimize = optimize,
           .strip = strip,
   ```

   `strip` is a `?bool`, and `null` means "the default for the mode", so it can be passed as is.

   ```console
   $ rm -rf zig-out; zig build && wc -c < zig-out/bin/seek
   17788813
   $ rm -rf zig-out; zig build -Dstrip && wc -c < zig-out/bin/seek
   4142626
   $ zig build -Doptimize=safe -Dstrip && wc -c < zig-out/bin/seek
   445928
   ```

   About three quarters of the Debug binary is debug info. A stripped `safe` build keeps every
   safety check at about 450 KB, but a panic's stack trace then shows addresses instead of file
   and line numbers.

   </details>

3. Add a step `zig build cross` that builds `seek` in `safe` mode for `x86_64-windows`,
   `aarch64-macos`, and `aarch64-linux-musl`, into `zig-out/<target>/`. Plain `zig build` should
   still build only the native binary. Hints: `std.Target.Query.parse(.{ .arch_os_abi = triple })`
   turns a string into a target query, `b.resolveTargetQuery(query)` turns that into a target, and
   `b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .{ .custom = "dir" } } })` installs to
   `zig-out/dir`.

   <details><summary>Solution</summary>

   At the end of `build`, after the test step:

   ```zig
   // `zig build cross` builds a safe release for three other systems into
   // zig-out/<target>/.
   const cross_step = b.step("cross", "Build release binaries for other systems");
   const triples = [_][]const u8{ "x86_64-windows", "aarch64-macos", "aarch64-linux-musl" };
   for (triples) |triple| {
       const query = std.Target.Query.parse(.{ .arch_os_abi = triple }) catch
           @panic("bad target triple");
       const cross_exe = b.addExecutable(.{
           .name = "seek",
           .root_module = b.createModule(.{
               .root_source_file = b.path("src/main.zig"),
               .target = b.resolveTargetQuery(query),
               .optimize = .safe,
           }),
       });
       cross_exe.root_module.addOptions("build_options", options);
       const install = b.addInstallArtifact(cross_exe, .{
           .dest_dir = .{ .override = .{ .custom = triple } },
       });
       cross_step.dependOn(&install.step);
   }
   ```

   `b.installArtifact` would attach the install to the default step; `b.addInstallArtifact` only
   creates the step, which we attach to `cross`. `build` can't return an error, so a bad triple (a
   bug in `build.zig`) panics. The three compilations run in parallel.

   ```console
   $ zig build -l | grep cross
     cross                        Build release binaries for other systems
   $ rm -rf zig-out; zig build cross && find zig-out -type f | sort
   zig-out/aarch64-linux-musl/seek
   zig-out/aarch64-macos/seek
   zig-out/x86_64-windows/seek.exe
   zig-out/x86_64-windows/seek.pdb
   $ file zig-out/*/seek*
   zig-out/aarch64-linux-musl/seek: ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV), statically linked, with debug_info, not stripped
   zig-out/aarch64-macos/seek:      Mach-O 64-bit arm64 executable, flags:<NOUNDEFS|DYLDLINK|TWOLEVEL|NO_REEXPORTED_DYLIBS|PIE|HAS_TLV_DESCRIPTORS>
   zig-out/x86_64-windows/seek.exe: PE32+ executable (console) x86-64, for MS Windows
   zig-out/x86_64-windows/seek.pdb: MSVC program database ver 7.00, 4096*696 bytes
   ```

   </details>

4. What happens if you put `@import("../build.zig.zon").version` directly in `src/main.zig`
   instead of going through `build_options`? Why?

   <details><summary>Solution</summary>

   It doesn't compile:

   ```console
   $ zig build
   …
   src/main.zig:6:25: error: import of file outside module path
   const version = @import("../build.zig.zon").version;
                           ^~~~~~~~~~~~~~~~~~
   ```

   `build.zig.zon` is one folder above `src/`, the program module's root directory, and a module
   can only import (or embed) files inside its root directory. (Without the `../`, Zig looks for
   `src/build.zig.zon` and reports `FileNotFound`.) `build.zig` is in the project's root folder, so
   it can import the manifest, and the options module carries the value across. A bonus:
   `-Dversion` can override it.

   </details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-18--the-build-system)
