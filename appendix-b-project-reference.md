# Appendix B — Project Reference

The finished `seek` (version 1.0.0, `project/ch20/`) in one place: how to use and build it, how
the code fits together, and where each idea from the course appears. Line numbers refer to
`project/ch20/`.

## Using seek

```console
$ seek -h
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
```

Command-line rules:

- Flags and paths can be mixed: `seek fox src -n` equals `seek -n fox src`.
- A value follows its flag (`-m 3`, `--color always`) or is attached with `=` (`--max-count=3`).
  Short flags can't be combined: write `-i -n`, not `-in`.
- Everything after `--` is a pattern or path, even if it starts with `-`. A lone `-` is not a flag;
  as a PATH it means standard input.
- With no PATH, `seek` searches `.`, not standard input.
- `-l` wins over `-c`. `-m` counts selected lines, so with `-v` it counts non-matching ones.
- `--color auto` (the default) colors matches only when stdout is a terminal.
- Hidden files and directories (names starting with `.`) are skipped unless `--hidden`. Files with
  a zero byte in their first 8 KiB are binary and skipped silently. Symbolic links inside a
  directory are skipped; a link named on the command line is searched.
- `--glob` matches a file's name (not its path), and only for files found by walking a directory;
  files named on the command line are always searched.
- Output is in path order (argument order, then sorted by path inside each directory), however many
  jobs run.

### Exit status

| Status | Meaning |
|-------:|---------|
| 0 | At least one line was selected (or `--help`/`--version`) |
| 1 | No line was selected; also when writing to stdout fails (`error: WriteFailed`) |
| 2 | Bad usage, or a file or directory couldn't be read (the other files are still searched) |

### Output formats

| Options | Each line looks like |
|---------|----------------------|
| (none) | `path:text` |
| `-n` | `path:line:text` |
| `-c` | `path:count` (for every file, including 0) |
| `-l` | `path` |
| `--json` | `{"path":"…","line":N,"text":"…"}` (`line` is always included) |
| `--json -c` | `{"path":"…","count":N}` |
| `--json -l` | `{"path":"…"}` |
| `--stats` | the normal output, then a summary on **stderr** |

Standard input is shown as `(standard input)`.

### Examples

With `project/ch20/testdata` ([described below](#test-data)) and a `safe` build:

```console
$ seek fox testdata
testdata/notes/log.txt:2024-01-01 saw a fox near the barn
testdata/notes/log.txt:2024-01-03 fox tracks in the snow
testdata/notes/todo.md:- feed the fox
testdata/poem.txt:The quick brown fox
$ seek -i -n fox testdata
testdata/notes/log.txt:1:2024-01-01 saw a fox near the barn
testdata/notes/log.txt:3:2024-01-03 fox tracks in the snow
testdata/notes/todo.md:2:- feed the fox
testdata/poem.txt:1:The quick brown fox
testdata/poem.txt:3:A Fox is quick and clever;
testdata/poem.txt:5:Foxes everywhere!
$ seek -m 1 fox testdata
testdata/notes/log.txt:2024-01-01 saw a fox near the barn
testdata/notes/todo.md:- feed the fox
testdata/poem.txt:The quick brown fox
$ seek -W '*the*dog*' testdata
testdata/notes/todo.md:- walk the dog
testdata/poem.txt:jumps over the lazy dog.
testdata/poem.txt:the dog just sleeps.
$ seek -c --glob '*.txt' fox testdata
testdata/notes/log.txt:2
testdata/poem.txt:1
$ seek --hidden -l fox testdata
testdata/.secret.txt
testdata/notes/log.txt
testdata/notes/todo.md
testdata/poem.txt
$ seek --json fox testdata/poem.txt
{"path":"testdata/poem.txt","line":1,"text":"The quick brown fox"}
$ seek --json -c fox testdata
{"path":"testdata/notes/log.txt","count":2}
{"path":"testdata/notes/todo.md","count":1}
{"path":"testdata/poem.txt","count":1}
$ seek --color always fox testdata/poem.txt | cat -v
testdata/poem.txt:The quick brown ^[[1;31mfox^[[0m
$ printf 'one fox\n' | seek fox -
(standard input):one fox
$ cd testdata && seek -l fox
notes/log.txt
notes/todo.md
poem.txt
```

Errors:

```console
$ seek zebra testdata; echo "exit $?"
exit 1
$ seek fox nope.txt testdata/poem.txt; echo "exit $?"
seek: nope.txt: FileNotFound
testdata/poem.txt:The quick brown fox
exit 2
$ seek --nope x
seek: unknown flag '--nope'
usage: seek [OPTIONS] PATTERN [PATH ...]
$ seek -m
seek: -m needs a value
usage: seek [OPTIONS] PATTERN [PATH ...]
$ seek --color sometimes x
seek: invalid value 'sometimes' for --color
usage: seek [OPTIONS] PATTERN [PATH ...]
$ seek --hidden=yes x
seek: invalid value 'yes' for --hidden
usage: seek [OPTIONS] PATTERN [PATH ...]
$ seek
usage: seek [OPTIONS] PATTERN [PATH ...]
```

All these usage errors exit with status 2. [Chapter 20](20-design-and-next-steps.md#checkpoint)
has more sessions, including `--stats` and `seek` searching its own source.

## Building and testing

In `project/ch20/` (or your own copy):

| Command | Does |
|---------|------|
| `zig build` | Debug build → `zig-out/bin/seek` |
| `zig build -Doptimize=safe` | The release build: optimized, safety checks kept |
| `zig build -Doptimize=fast` | Fastest, no safety checks |
| `zig build -Dversion=1.2.3` | Override the version `--version` prints (default: from `build.zig.zon`) |
| `zig build -Dtarget=x86_64-windows` | Cross-compile (→ `zig-out/bin/seek.exe`) |
| `zig build run -- -n fox testdata` | Build, install, and run with arguments |
| `zig build test --summary all` | Run all 25 tests |
| `zig build bench` | Time the zero-byte scanners (always built with `.fast`) |
| `zig build -l` | List the steps |

```console
$ zig build -l
  install (default)            Copy build artifacts to prefix path
  uninstall                    Remove build artifacts from prefix path
  run                          Run seek
  test                         Run unit tests
  bench                        Time the zero-byte scanners
$ zig build bench
scanning 64 MiB, best of 20 runs
scalar loop             10.34 ms     6.0 GiB/s
@Vector                  3.66 ms    17.1 GiB/s
std.mem.findScalar       3.44 ms    18.2 GiB/s
```

Your timings will differ. `zig test FILE` runs the tests of one file and the files it imports:
`zig test src/match.zig` runs 4 tests, `zig test src/output.zig` 13.

## Architecture

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

Imports point one way: `main` → `cli`, `search`; `search` → `match`, `output`, `stats`, `bytes`;
`output` → `match`, `cli`. `match`, `stats`, and `bytes` import only `std`, so each can be tested
alone.

### Who owns what

| Memory | Allocated with | Owner | Freed by |
|--------|----------------|-------|----------|
| `args` | `init.arena` | the process | exit |
| `positionals` (from `cli.parse`) | `gpa` | `run` | `defer gpa.free(positionals)` (`main.zig:72`) |
| The pattern copy | `gpa` | `Searcher` | `Searcher.deinit` |
| Every queued path | `gpa` | `Searcher.files` | `Searcher.deinit` (`addFile` frees it if `append` fails) |
| One `FileResult` per file, each with an `Io.Writer.Allocating` | `gpa` | `searchAll` | `searchAll`'s `defer`s; each output is freed as soon as it's printed |
| Long lines | each worker's `ArenaAllocator` | that worker | `arena.reset` after every file, `arena.deinit` at the end |
| `Stats.matches_per_file` | `gpa` | `Searcher.stats` | `Stats.deinit`; keys point into `Searcher.files` |
| `topN` result | `gpa` | `Stats.write` | `defer gpa.free(top)` |

### Threads

`searchAll` starts up to `jobs` workers with `Io.Group.concurrent`. Workers only *read* the
`Searcher` (`*const Searcher`). Each takes the next file index with `fetchAdd` on a
`std.atomic.Value(usize)`, writes into that file's `FileResult`, and calls `done.set`. The main
thread waits on `results[0].done`, `results[1].done`, … in order, prints each buffered output, and
records statistics, so output and `Stats` need no locks. If printing fails, `defer
group.cancel(io)` stops the workers before `results` is freed. If no worker can start, the main
thread searches everything itself.

## File map

| File | Lines | Key declarations |
|------|------:|------------------|
| `src/main.zig` | 122 | `usage_text` (`@embedFile`, :10), `usage` (:14), `help` (:17), `ExitCode` (:20), `main` (:26), `run` (:55), the test block importing every file (:115) |
| `src/cli.zig` | 301 | `Color` (:12), `Options` with `shorts` and `descriptions` (:16), `Error` (:66), `Diagnostic` (:69), `parse` (:78), `isFlag` (:141), `parseValue` (:153), `unsupported` (:163), `kebab` (:168), `valueName` (:181), `help` (:206), `validate` (:228); 3 tests |
| `src/match.zig` | 179 | `Span` (:7), `Matcher` union (:14) with `init` (:29) and `find` (:36), `wildcardMatch` (:60), `wildcardMatchIgnoreCase` (:65), `matchWildcard` (:77), `eqlByte` (:106); 4 tests including a fuzz test (:159) |
| `src/search.zig` | 476 | `read_buffer_len` (:16), `binary_probe_len` (:19), `FileResult` (:23), `Searcher` (:42): `init` (:63), `deinit` (:93), `addPath` (:103), `addFile` (:115), `addDirectory` (:123), `searchAll` (:179), `worker` (:230), `searchFile` (:258), `searchReader` (:282), `reportError` (:311); `displayName` (:320), `pathLessThan` (:324), `looksBinary` (:330), `nextLine` (:343); 7 tests |
| `src/output.zig` | 219 | `Printer` union (:15) with `Json`, `Lines`, `init` (:34), `line` (:52), `fileDone` (:71); `JsonLine` (:86), `writeJson` (:94), `Match` with `format` (:99, :108), `writeHighlighted` (:120); 6 tests |
| `src/stats.zig` | 170 | `Counter(K)` (:15) with `add`, `get`, `topN`; `Stats` (:75) with `record` (:88) and `write` (:96); 3 tests |
| `src/bytes.zig` | 52 | `vector_len` (:8), `containsZeroScalar` (:11), `containsZero` (:20); 1 test |
| `src/usage.txt` | 5 | The top of `--help` |
| `bench/bench.zig` | 60 | `main` (:10), `stdFind` (:31), `measure` (:35) |
| `build.zig` | 66 | The `version` option, `build_options`, steps `install`, `run`, `test`, `bench` |
| `build.zig.zon` | 14 | `.name = .seek`, `.version = "1.0.0"`, `.minimum_zig_version = "0.17.0"`, `.paths` |
| `README.md` | 52 | Build commands, examples, source map |

Total: 1716 lines, 1519 of them in the seven `.zig` files in `src/`; 25 tests.

### Test data

```text
testdata/
├── .secret.txt      the fox knows a secret              (hidden: needs --hidden)
├── data.bin         "fox\0binary\n"                     (binary: always skipped)
├── notes/
│   ├── log.txt      3 dated lines, 2 with "fox"
│   └── todo.md      "# TODO" and 3 list items
└── poem.txt         5 lines: fox, Fox, Foxes, and 2 dogs
```

The tests in `search.zig` don't use this directory: `makeTestTree` (:364) builds a similar tree
in a `std.testing.tmpDir`, so they don't depend on the current directory.

## Milestones

What each chapter added to `seek` (snapshots in `project/chNN/`):

| Ch | `seek` gained |
|---:|---------------|
| 1 | The project (`zig init`), a usage message |
| 2 | Version and exit codes |
| 3 | Command-line argument handling |
| 4 | The first real search: one file, literal pattern |
| 5 | Error sets, error messages, and exit status 2 |
| 6 | Patterns and paths as slices |
| 7 | `Options`, `Match`, `Searcher` structs; decl literals |
| 8 | Owned memory, `deinit`, leak checking |
| 9 | `-i`, `-n`, `-v`, highlighting, `Match.format` |
| 10 | `-c`, `-l`, `-m` |
| 11 | Streaming reads, recursive directories, `--hidden`, `--glob`, standard input |
| 12 | The comptime flag parser and generated `--help` |
| 13 | `Counter(K)` and `--stats` |
| 14 | `Matcher` and `Printer` tagged unions, `-W` |
| 15 | Concurrent search with `-j`, ordered output |
| 16 | The full test suite: temporary directories, allocation-failure tests, fuzzing |
| 17 | `--json` |
| 18 | `-Dversion`, `usage.txt` with `@embedFile`, release builds |
| 19 | SIMD binary detection, `zig build bench`, `--color auto` |
| 20 | Version 1.0.0 and a README |

## Concept → code map

Where each idea from the course appears in the finished code. `file:line` is in
`project/ch20/src/` unless it starts with `bench/`.

| Ch | Concept | Where |
|---:|---------|-------|
| 1 | `pub fn main(init: std.process.Init) !u8` | `main.zig:26`, `bench/bench.zig:10` |
| 1 | Buffered stdout/stderr writers and `flush` | `main.zig:30–36`, `main.zig:49–50` |
| 2 | Enum with an explicit tag type for exit codes | `ExitCode`, `main.zig:20` |
| 2 | Optional integers with defaults (`?usize = null`) | `Options.max_count`, `Options.jobs`, `cli.zig:23`, `cli.zig:29` |
| 2 | `@max`, `@min` | `search.zig:87`, `search.zig:196` |
| 3 | `while` with a continue expression | `cli.zig:93`, `search.zig:298` |
| 3 | `for` over two slices at once | `search.zig:205`, `cli.zig:114` (an `inline for`) |
| 3 | Labeled block with `break :blk` | `main.zig:45`, `cli.zig:127` |
| 3 | `switch` on a tagged union with captures | `Matcher.find`, `match.zig:37` |
| 4 | Function as a comptime parameter | `measure(…, comptime scan: fn ([]const u8) bool, …)`, `bench/bench.zig:39` |
| 4 | `defer` for cleanup | `main.zig:72`, `main.zig:96`, `search.zig:127` |
| 5 | Error sets and merged error sets (`\|\|`) | `cli.Error` (`cli.zig:66`), `search.zig:103` |
| 5 | `catch \|err\| switch (err)` mapping errors to exit codes | `main.zig:38–48` |
| 5 | `errdefer` | `cli.zig:90`, `search.zig:117`, `stats.zig:55` |
| 5 | `if (…) \|value\| … else \|err\|` | `search.zig:107`, `search.zig:242` |
| 5 | `orelse return null`, `orelse break` | `match.zig:39`, `search.zig:136` |
| 5 | Error names in messages with `{t}` | `reportError`, `search.zig:314` |
| 6 | Slicing a comptime string | `usage`, `main.zig:14` |
| 6 | Sentinel-terminated arguments `[]const [:0]const u8` | `run`, `main.zig:58` |
| 6 | Array to vector via `bytes[i..][0..len].*` | `bytes.zig:28` |
| 7 | Struct with defaults: `.{}` is a complete value | `Options`, `cli.zig:16` |
| 7 | Decl literals: `.init(…)`, `.empty`, `.cwd()` | `main.zig:95`, `search.zig:56`, `search.zig:80` |
| 7 | Methods and `self.* = undefined` in `deinit` | `Searcher.deinit`, `search.zig:93–99` |
| 7 | Destructuring a returned tuple | `main.zig:63`, `cli.zig:106` |
| 8 | Explicit allocator parameters (`gpa`) everywhere | `Searcher.init`, `search.zig:63` |
| 8 | Arena per worker, `reset(.retain_capacity)` | `worker`, `search.zig:231`, `search.zig:249` |
| 8 | `gpa.dupe` to take ownership | `search.zig:73`, `search.zig:111` |
| 9 | `std.mem.find`, `std.ascii.findIgnoreCase` | `match.zig:39`, `match.zig:43` |
| 9 | `std.mem.cutScalar`, `cutPrefix`, `replaceScalar` | `cli.zig:106`, `cli.zig:142`, `cli.zig:171` |
| 9 | A `format` method for `{f}` | `Match.format`, `output.zig:108` |
| 9 | ANSI colors spliced into a format string with `++` | `writeHighlighted`, `output.zig:128` |
| 10 | `std.ArrayList` with `.empty` and `toOwnedSlice` | `cli.zig:89`, `cli.zig:137` |
| 10 | Unmanaged hash maps, `getOrPut` | `Counter`, `stats.zig:21–23`, `stats.zig:40` |
| 10 | `std.mem.sort` with a context and `lessThan` | `search.zig:170`, `stats.zig:60` |
| 11 | File readers: positional vs. streaming | `searchFile`, `search.zig:267` |
| 11 | `Io.Reader.peek`, `takeDelimiter`, `streamDelimiterEnding` | `looksBinary` (`search.zig:331`), `nextLine` (`search.zig:343`) |
| 11 | `Io.Writer.Allocating` | `FileResult.output`, `search.zig:25`; `nextLine` |
| 11 | `walkSelectively` and `enter` | `addDirectory`, `search.zig:131–139` |
| 11 | `statFile`, `openDir`, `openFile` | `search.zig:107`, `search.zig:124`, `search.zig:260` |
| 12 | `inline for` over struct fields | `cli.parse`, `cli.zig:114` |
| 12 | `@typeInfo`, `@field`, `@hasField` | `cli.zig:86`, `cli.zig:122`, `cli.zig:145` |
| 12 | `comptime` blocks building strings | `kebab` (`cli.zig:168`), `valueName`, `help` (`cli.zig:206`) |
| 12 | `@compileError` for misuse | `validate`, `cli.zig:228`; `stats.zig:18` |
| 12 | `std.fmt.comptimePrint`, `std.meta.stringToEnum` | `cli.zig:213`, `cli.zig:156` |
| 13 | A type function returning `struct`, `@This()` | `Counter(K)`, `stats.zig:15`, `stats.zig:27` |
| 13 | Choosing an implementation at compile time | `Counter`'s `Map`, `stats.zig:20–23` |
| 13 | `anytype` | `writeJson`, `output.zig:94` |
| 13 | One function compiled twice via a `comptime bool` | `matchWildcard`, `match.zig:77` |
| 14 | Tagged unions as closed polymorphism | `Matcher` (`match.zig:14`), `Printer` (`output.zig:15`) |
| 14 | An interface with a vtable: `std.Io.Writer`, `std.Io.Reader` | every `*Io.Writer` parameter |
| 15 | `Io.Group.concurrent` and `cancel` | `searchAll`, `search.zig:187–199` |
| 15 | `std.atomic.Value` and `fetchAdd(.monotonic)` | `search.zig:186`, `search.zig:238` |
| 15 | `Io.Event` to publish a result | `FileResult.done` (`search.zig:29`), `search.zig:207`, `search.zig:252` |
| 16 | Tests next to the code; `test` blocks named after functions | `match.zig:114`, `bytes.zig:37` |
| 16 | Table-driven tests with `errdefer` printing the failing case | `match.zig:114–138` |
| 16 | `std.testing.tmpDir` and end-to-end tests | `makeTestTree`, `expectSearch`, `search.zig:364–400` |
| 16 | `checkAllAllocationFailures` | `search.zig:448–452` |
| 16 | Fuzz testing with `std.testing.fuzz` | `match.zig:159–179` |
| 16 | Referencing every file so `zig build test` finds all tests | `main.zig:115` |
| 17 | `std.json.fmt` to write JSON | `writeJson`, `output.zig:95` |
| 17 | `std.json.parseFromSlice` in a test | `output.zig:178` |
| 18 | `b.option`, `b.addOptions`, `@import("build_options")` | `build.zig`, `main.zig:6` |
| 18 | `@import("build.zig.zon")` for the default version | `build.zig` |
| 18 | A second executable and a named module | the `bench` step in `build.zig` |
| 18 | `@embedFile` | `main.zig:10` |
| 19 | `@Vector`, `@splat`, `@reduce` | `containsZero`, `bytes.zig:20–34` |
| 19 | `std.simd.suggestVectorLength` | `bytes.zig:8` |
| 19 | `isTty` for `--color auto` | `main.zig:91` |
| 19 | Monotonic time: `Io.Clock.awake` | `main.zig:100`, `bench/bench.zig:44` |
| 19 | `std.mem.doNotOptimizeAway` | `bench/bench.zig:49` |
| 19 | `@backingInt` of an enum | `main.zig:51` |
| 20 | Naming: `TitleCase` types, `camelCase` functions, `snake_case` fields and constants | everywhere |

Sources for this appendix: [REFERENCES.md](REFERENCES.md#appendix-b--project-reference)
