# Learn Zig by Building `seek`

This course teaches Zig from first principles while you build one real program: **`seek`**, a
small, fast, concurrent command-line search tool in the spirit of `grep`.

It borrows from two classics. As in *Go by Example*, every idea comes with a small runnable program
and its exact output. As in *The Rust Programming Language*, the chapters are a narrative that
explains why the language works the way it does, and each one adds a feature to the project.

By the end you will know Zig's syntax, type system, memory model, `comptime`, standard library,
build system, and design ideals well enough to write idiomatic Zig on your own.

## Requirements

- **Exactly Zig 0.17.0.** Zig hasn't reached 1.0; its standard library and parts of the language
  change between releases. Every example was verified with Zig 0.17.0, and older or newer versions
  *will* break some of the code.
- A terminal and any text editor. Zig support via `zls` (the version matching 0.17.0) helps.
- Familiarity with *some* programming language. C helps but isn't required.

Installation is not covered. If `zig version` prints `0.17.0`, you're ready.

## How to use this course

- **Read in order.** Each chapter uses only what earlier chapters taught.
- **Type the code.** You learn more by typing the examples and project steps than by copying them.
- **Run everything.** Commands appear as `$ command` lines, followed by the output you should see.
- **Use the snapshots when stuck.** `project/chNN/` is the complete `seek` project at the end of
  chapter NN. Compare your code with it (for example `diff -r myseek/src project/ch09/src`).
- **Run the examples.** `examples/chNN/<name>.zig` holds every example program from chapter NN:
  `zig run examples/chNN/<name>.zig`, or `zig test …` for test examples.
- **Do the exercises** at the end of each chapter before opening the collapsed solutions.

## Table of contents

| #  | Chapter | You'll learn | `seek` milestone |
|----|---------|--------------|------------------|
| 1  | [Getting Started](01-getting-started.md) | `zig` commands, `zig init`, files as structs, `main` | Create the project, print usage |
| 2  | [Values, Types, and Variables](02-values-and-types.md) | `const`/`var`, integers, floats, coercion, overflow | Version and exit codes |
| 3  | [Control Flow](03-control-flow.md) | `if`, `while`, `for`, `switch`, labeled blocks | Handle command-line arguments |
| 4  | [Functions](04-functions.md) | Parameters, function pointers, `defer` | First real search |
| 5  | [Errors and Optionals](05-errors-and-optionals.md) | Error sets, `try`/`catch`, `errdefer`, `?T` | Robust errors, exit status |
| 6  | [Arrays, Slices, and Pointers](06-arrays-slices-pointers.md) | Arrays, slices, sentinels, pointer kinds | Patterns and paths |
| 7  | [Structs, Enums, and Unions](07-structs-enums-unions.md) | Methods, decl literals, tagged unions | `Options`, `Match`, `Searcher` |
| 8  | [Memory and Allocators](08-memory-and-allocators.md) | Explicit allocation, arenas, leak detection | Leak-free memory management |
| 9  | [Strings, Text, and Formatting](09-strings-and-formatting.md) | `[]const u8`, `std.mem`, `std.fmt`, `{f}` | `-i`, `-n`, `-v`, highlighting |
| 10 | [Standard Library Containers](10-containers.md) | `ArrayList`, hash maps, sorting | `-c`, `-l`, `-m` |
| 11 | [Files, Directories, and I/O](11-files-and-io.md) | `std.Io`, readers, writers, directory walking | Streaming, recursion, `--hidden`, `--glob`, stdin |
| 12 | [Comptime](12-comptime.md) | Compile-time execution, reflection, `inline for` | A flag parser generated at compile time |
| 13 | [Generic Programming](13-generics.md) | `comptime T: type`, `anytype`, type functions | Generic `Counter`, `--stats` |
| 14 | [Interfaces and Polymorphism](14-polymorphism.md) | Tagged unions, vtables, `@fieldParentPtr` | `Matcher`, printers, `-W` |
| 15 | [Concurrency](15-concurrency.md) | `std.Io` futures, groups, queues, atomics | Concurrent search (`-j`), ordered output |
| 16 | [Testing](16-testing.md) | `test` blocks, `std.testing`, leak checks, fuzzing | A full test suite |
| 17 | [JSON and Data Serialization](17-json.md) | `std.json` serialization and parsing, ZON | `--json` output |
| 18 | [The Build System](18-build-system.md) | `build.zig`, options, modules, cross-compiling | `-Dversion`, embedded `--help` text |
| 19 | [Safety, Undefined Behavior, and Talking to C](19-low-level.md) | Illegal behavior, SIMD, bit tricks, C interop | Vectorized binary detection, `zig build bench`, `--color auto` |
| 20 | [Zig's Design Ideals, Idioms, and Next Steps](20-design-and-next-steps.md) | The Zen of Zig, idioms, conventions | Version 1.0.0, a README, a tour of the code |
| A  | [Cheat Sheet](appendix-a-cheatsheet.md) | Syntax quick reference | |
| B  | [Project Reference](appendix-b-project-reference.md) | `seek` usage, architecture, concept map | |

References: [REFERENCES.md](REFERENCES.md) lists the sources behind each chapter, with archived
(Wayback Machine) copies of every link.

## What you'll build

By Chapter 20, `seek` searches directory trees concurrently, with case-insensitive, inverted, and
wildcard matching, file-name globs, JSON output, colored highlighting, and statistics. Its
command-line parser is generated at compile time from a plain struct, it has a leak-checked test
suite, and it depends only on the Zig standard library. A real run of the finished project:

```console
$ cd project/ch20
$ zig build -Doptimize=safe
$ ./zig-out/bin/seek --version
seek 1.0.0
$ ./zig-out/bin/seek -i -n fox testdata
testdata/notes/log.txt:1:2024-01-01 saw a fox near the barn
testdata/notes/log.txt:3:2024-01-03 fox tracks in the snow
testdata/notes/todo.md:2:- feed the fox
testdata/poem.txt:1:The quick brown fox
testdata/poem.txt:3:A Fox is quick and clever;
testdata/poem.txt:5:Foxes everywhere!
$ ./zig-out/bin/seek --json -c fox testdata
{"path":"testdata/notes/log.txt","count":2}
{"path":"testdata/notes/todo.md","count":1}
{"path":"testdata/poem.txt","count":1}
```

[Appendix B](appendix-b-project-reference.md) has the full usage, architecture, and a map from
each chapter's ideas to the code.
