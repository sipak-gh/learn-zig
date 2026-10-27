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
