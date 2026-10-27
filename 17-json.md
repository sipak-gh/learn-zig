# Chapter 17 — JSON and Data Serialization

Programs exchange data through formats, and JSON is the most common. This chapter covers
`std.json`: writing Zig values as JSON, its options, parsing JSON into typed structs or a dynamic
`std.json.Value`, custom serialization, and bad input. It also covers ZON, Zig's own data format,
used by `build.zig.zon`. `seek` gets a `--json` flag that prints one JSON object per line.
[Chapter 16](16-testing.md) gave `seek` a test suite; [Chapter 18](18-build-system.md) covers the
build system.

## Writing JSON: `std.json.fmt`

`std.json` serializes values by inspecting their types at compile time
([Chapter 12](12-comptime.md)). No schema, nothing to derive: a struct becomes an object with one
key per field.

`std.json.fmt(value, options)` wraps a value so the `{f}` specifier prints it as JSON, to any
`*Io.Writer`.

`examples/ch17/stringify.zig`

```zig
const std = @import("std");

const Color = enum { red, green };

const Item = struct {
    name: []const u8,
    count: u32,
    price: f64,
    in_stock: bool,
    color: Color,
    tags: []const []const u8,
    note: ?[]const u8 = null,
};

pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &buffer);
    const out = &stdout_writer.interface;

    const item: Item = .{
        .name = "Fox \"Red\" Plush\t\\",
        .count = 3,
        .price = 12.5,
        .in_stock = true,
        .color = .red,
        .tags = &.{ "toy", "soft" },
    };

    // std.json.fmt wraps a value so that `{f}` prints it as JSON.
    try out.print("{f}\n", .{std.json.fmt(item, .{})});

    // Options: pretty-print, and leave out optional fields that are null.
    try out.print("{f}\n", .{std.json.fmt(item, .{
        .whitespace = .indent_2,
        .emit_null_optional_fields = false,
    })});

    // Anonymous structs, tuples, and plain values work too.
    try out.print("{f}\n", .{std.json.fmt(.{ .ok = true, .ids = .{ 1, 2, 3 } }, .{})});
    try out.print("{f}\n", .{std.json.fmt("caf\u{e9} \u{1F98A}", .{ .escape_unicode = true })});

    // Or get the JSON as an allocated string.
    const text = try std.json.Stringify.valueAlloc(init.gpa, item.tags, .{});
    defer init.gpa.free(text);
    try out.print("{s} ({d} bytes)\n", .{ text, text.len });

    try out.flush();
}
```

```console
$ zig run examples/ch17/stringify.zig
{"name":"Fox \"Red\" Plush\t\\","count":3,"price":12.5,"in_stock":true,"color":"red","tags":["toy","soft"],"note":null}
{
  "name": "Fox \"Red\" Plush\t\\",
  "count": 3,
  "price": 12.5,
  "in_stock": true,
  "color": "red",
  "tags": [
    "toy",
    "soft"
  ]
}
{"ok":true,"ids":[1,2,3]}
"caf\u00e9 \ud83e\udd8a"
["toy","soft"] (14 bytes)
```

How Zig types map to JSON:

| Zig | JSON |
|-----|------|
| `bool` | `true` / `false` |
| integers, floats | number |
| `[]const u8` and other byte arrays/slices | string (escaped) |
| other slices, arrays, tuples | array |
| struct (named or anonymous) | object, fields in declaration order |
| `?T` | `null` or the value |
| enum, enum literal, error | string with the name |
| `union(enum)` | object with one key: the active tag |
| `*T` | whatever `T` gives |

Strings are escaped as JSON requires: `"` → `\"`, `\` → `\\`, tab → `\t`.

The options (`std.json.Stringify.Options`), all with defaults:

| Option | Default | Effect |
|--------|---------|--------|
| `whitespace` | `.minified` | `.indent_1` … `.indent_4`, `.indent_8`, `.indent_tab` pretty-print |
| `emit_null_optional_fields` | `true` | `false` leaves out struct fields that are `null` |
| `emit_strings_as_arrays` | `false` | `true` writes byte strings as arrays of numbers |
| `escape_unicode` | `false` | `true` writes non-ASCII characters as `\uXXXX` |
| `emit_nonportable_numbers_as_strings` | `false` | `true` writes integers beyond ±2^53 as strings |

`std.json.Stringify.valueAlloc(gpa, value, options)` returns an allocated `[]u8` you must free.
`std.json.Stringify.value(value, options, writer)` writes straight to a writer, like `fmt` without
a format string.

### Unions, errors, and bytes that aren't text

`examples/ch17/special.zig`

```zig
const std = @import("std");

const Shape = union(enum) {
    circle: f64,
    square: struct { side: u32 },
    empty,
};

pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &buffer);
    const out = &stdout_writer.interface;

    // A tagged union becomes an object with one field: the active tag.
    const shapes = [_]Shape{ .{ .circle = 1.5 }, .{ .square = .{ .side = 2 } }, .empty };
    try out.print("{f}\n", .{std.json.fmt(shapes, .{})});

    // Bytes that are not valid UTF-8 can't be a JSON string, so they
    // become an array of numbers.
    try out.print("{f}\n", .{std.json.fmt("ok", .{})});
    try out.print("{f}\n", .{std.json.fmt("caf\xe9", .{})});

    // Errors and enum literals become strings.
    try out.print("{f}\n", .{std.json.fmt(.{ error.FileNotFound, .done }, .{})});
    try out.flush();
}
```

```console
$ zig run examples/ch17/special.zig
[{"circle":1.5},{"square":{"side":2}},{"empty":{}}]
"ok"
[99,97,102,233]
["FileNotFound","done"]
```

JSON strings must be valid Unicode, but Zig strings are just bytes
([Chapter 9](09-strings-and-formatting.md)). `"caf\xe9"` is "café" in Latin-1, not UTF-8. Rather
than corrupt the bytes or fail, `std.json` writes an array of numbers. That's valid JSON, but a
reader must expect either form. You'll meet this again in `seek`.

## Reading JSON into a struct: `parseFromSlice`

`std.json.parseFromSlice(T, gpa, text, options)` parses `text` into a `T`, checking the JSON
against the type: names, kinds, and ranges must all fit.

`examples/ch17/parse.zig`

```zig
const std = @import("std");

const Config = struct {
    name: []const u8,
    jobs: u8 = 4, // used when the JSON has no "jobs"
    paths: []const []const u8,
    color: enum { auto, always, never } = .auto,
    max_count: ?usize = null,
};

const input =
    \\{
    \\  "name": "seek \u0021",
    \\  "paths": ["src", "docs"],
    \\  "color": "never",
    \\  "max_count": null
    \\}
;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    const parsed = try std.json.parseFromSlice(Config, gpa, input, .{});
    // Frees everything the parser allocated: strings, the slice of paths...
    defer parsed.deinit();
    const config = parsed.value;

    std.debug.print("name={s} jobs={d} paths={d} first={s}\n", .{
        config.name, config.jobs, config.paths.len, config.paths[0],
    });
    std.debug.print("color={t} max_count={?d}\n", .{ config.color, config.max_count });

    // Unknown fields are an error unless you ask to ignore them.
    const extra =
        \\{"name": "x", "paths": [], "verbose": true}
    ;
    if (std.json.parseFromSlice(Config, gpa, extra, .{})) |p| {
        p.deinit();
    } else |err| {
        std.debug.print("strict: {t}\n", .{err});
    }
    const relaxed = try std.json.parseFromSlice(Config, gpa, extra, .{ .ignore_unknown_fields = true });
    defer relaxed.deinit();
    std.debug.print("relaxed: name={s}\n", .{relaxed.value.name});

    // With your own arena, the "Leaky" variant returns the value directly.
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const numbers = try std.json.parseFromSliceLeaky([]i32, arena.allocator(), "[1, -2, 3]", .{});
    std.debug.print("numbers={any}\n", .{numbers});
}
```

```console
$ zig run examples/ch17/parse.zig
name=seek ! jobs=4 paths=2 first=src
color=never max_count=null
strict: UnknownField
relaxed: name=x
numbers={ 1, -2, 3 }
```

- **Field defaults fill missing keys:** `jobs` isn't in the JSON, so it's 4. A missing field
  *without* a default is an error.
- **Enums parse from their names**, optionals from `null`, slices from arrays.
- **Strict by default:** an unknown key is `error.UnknownField`, a repeated key
  `error.DuplicateField`. `ParseOptions` relaxes this: `.ignore_unknown_fields = true`,
  `.duplicate_field_behavior = .use_first` or `.use_last`.

### Who owns the result: `Parsed(T)`

Parsing allocates: strings with escapes (like `\u0021`) are decoded into new memory, and slices
need room for elements. `parseFromSlice` puts it all in an arena
([Chapter 8](08-memory-and-allocators.md)) and returns a `std.json.Parsed(Config)`:

- `parsed.value` is the `Config`.
- `parsed.deinit()` frees the arena, and with it every string and slice in `value`.

So **`parsed.value` must not outlive `parsed`**. Keeping `config.name` after `deinit` keeps a
dangling pointer. Copy what you need (`gpa.dupe`) before `deinit`.

`parseFromSliceLeaky` skips the `Parsed` wrapper and allocates straight from the allocator you
pass. It's "leaky" because it can't free its own temporary allocations, so pass an arena and free
the arena when done.

### Bad input

Anything that doesn't fit is a normal error value you can `catch` or `switch` on.

`examples/ch17/malformed.zig`

```zig
const std = @import("std");

const Point = struct { x: u8, y: u8 };

pub fn main(init: std.process.Init) void {
    const inputs = [_][]const u8{
        \\{"x": 1, "y": 2}
        ,
        \\{"x": 1, "y": 300}
        ,
        \\{"x": 1, "y": "two"}
        ,
        \\{"x": 1}
        ,
        \\{"x": 1, "y": 2, "x": 3}
        ,
        \\{"x": 1, "y":
        ,
        \\{"x": 1, "y": 2} trailing
        ,
    };
    for (inputs) |text| {
        if (std.json.parseFromSlice(Point, init.gpa, text, .{})) |parsed| {
            defer parsed.deinit();
            std.debug.print("{s:<26} -> x={d} y={d}\n", .{ text, parsed.value.x, parsed.value.y });
        } else |err| {
            std.debug.print("{s:<26} -> error.{t}\n", .{ text, err });
        }
    }
}
```

```console
$ zig run examples/ch17/malformed.zig
{"x": 1, "y": 2}           -> x=1 y=2
{"x": 1, "y": 300}         -> error.Overflow
{"x": 1, "y": "two"}       -> error.InvalidCharacter
{"x": 1}                   -> error.MissingField
{"x": 1, "y": 2, "x": 3}   -> error.DuplicateField
{"x": 1, "y":              -> error.UnexpectedEndOfInput
{"x": 1, "y": 2} trailing  -> error.SyntaxError
```

`300` doesn't fit in a `u8`, so you get `error.Overflow`, not a wrong value. The type is the
validation.

## Dynamic JSON: `std.json.Value`

When you don't know the shape in advance, parse into `std.json.Value`, a tagged union with one
variant per kind of JSON value: `null`, `bool`, `integer` (`i64`), `float` (`f64`),
`number_string` (numbers too big for either), `string`, `array`, and `object`.

`examples/ch17/dynamic.zig`

```zig
const std = @import("std");

const input =
    \\{"tool": "seek", "version": [1, 0], "ratio": 2.5, "tags": null,
    \\ "authors": [{"name": "Ann"}, {"name": "Bo"}]}
;

pub fn main(init: std.process.Init) !void {
    // std.json.Value can hold any JSON document.
    const parsed = try std.json.parseFromSlice(std.json.Value, init.gpa, input, .{});
    defer parsed.deinit();
    const root = parsed.value;

    // Value is a tagged union: null, bool, integer, float, number_string,
    // string, array, object.
    const object = root.object; // safety-checked: panics if root isn't an object
    std.debug.print("tool: {s}\n", .{object.get("tool").?.string});
    std.debug.print("major: {d}\n", .{object.get("version").?.array.items[0].integer});
    std.debug.print("ratio: {d}\n", .{object.get("ratio").?.float});
    std.debug.print("missing: {}\n", .{object.get("license") == null});

    // Walk all fields in order, switching on the kind of value.
    var it = object.iterator();
    while (it.next()) |entry| {
        const kind: []const u8 = switch (entry.value_ptr.*) {
            .null => "null",
            .bool => "bool",
            .integer, .float, .number_string => "number",
            .string => "string",
            .array => |array| if (array.items.len > 0 and array.items[0] == .object) "array of objects" else "array",
            .object => "object",
        };
        std.debug.print("{s}: {s}\n", .{ entry.key_ptr.*, kind });
    }
}
```

```console
$ zig run examples/ch17/dynamic.zig
tool: seek
major: 1
ratio: 2.5
missing: true
tool: string
version: array
ratio: number
tags: null
authors: array of objects
```

- `.object` is a `std.json.ObjectMap`: a string-keyed array hash map
  ([Chapter 10](10-containers.md)) that keeps keys in input order. `get` returns an optional.
- `.array` is a list; its elements are in `.items`.
- `root.object` on a non-object is checked illegal behavior: a panic in safe builds. With untrusted
  input, check the tag with `switch` or `==` first.

Prefer typed parsing when you can: a struct documents the format, and the parser does the checks.

## Custom serialization: `jsonStringify`

If a type has `pub fn jsonStringify(self, jw: anytype) !void`, `std.json` calls it instead of
writing the fields. `jw` is a `*std.json.Stringify`, a JSON writer:

- `jw.write(value)` writes any value with the normal rules.
- `jw.beginObject()`, `jw.objectField(name)`, `jw.endObject()`; `jw.beginArray()`, `jw.endArray()`.
- `jw.print(fmt, args)` writes raw text as one value; you must keep it valid JSON.

`examples/ch17/custom.zig`

```zig
const std = @import("std");

const Point = struct {
    x: i32,
    y: i32,

    /// Called by std.json instead of the default field-by-field output.
    /// `jw` is a *std.json.Stringify.
    pub fn jsonStringify(self: Point, jw: anytype) !void {
        try jw.print("\"{d},{d}\"", .{ self.x, self.y });
    }
};

const Path = struct {
    name: []const u8,
    points: []const Point,
    secret: []const u8,

    /// Writes only some fields, under different names.
    pub fn jsonStringify(self: Path, jw: anytype) !void {
        try jw.beginObject();
        try jw.objectField("id");
        try jw.write(self.name);
        try jw.objectField("pts");
        try jw.write(self.points);
        try jw.endObject();
    }
};

pub fn main(init: std.process.Init) !void {
    var buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &buffer);
    const out = &stdout_writer.interface;

    const path: Path = .{
        .name = "trail",
        .points = &.{ .{ .x = 1, .y = 2 }, .{ .x = -3, .y = 4 } },
        .secret = "do not print",
    };
    try out.print("{f}\n", .{std.json.fmt(path, .{})});
    try out.flush();
}
```

```console
$ zig run examples/ch17/custom.zig
{"id":"trail","pts":["1,2","-3,4"]}
```

`jw.write(self.points)` writes a slice of `Point`s, each using its own `jsonStringify`. The hook is
found by name at compile time, like `format` for `{f}` ([Chapter 14](14-polymorphism.md)): duck
typing, checked by the compiler.

The parsing side has a matching hook, `pub fn jsonParse(…)`, for types whose JSON form differs from
their fields. You rarely need it; see `std.json.static` in the standard library source.

## ZON: Zig Object Notation

ZON writes data in Zig's own value syntax: anonymous struct and tuple literals, strings, numbers,
enum literals, `true`/`false`/`null`. Every `build.zig.zon` is ZON. Unlike JSON it allows comments
and trailing commas, and `zig fmt` formats it.

`std.zon.parse.fromSlice(T, options)` parses ZON into a `T`; `std.zon.stringify.serialize(value,
options, writer)` writes a value as ZON.

`examples/ch17/zon.zig`

```zig
const std = @import("std");

const Settings = struct {
    name: []const u8,
    jobs: u8 = 4,
    globs: []const []const u8 = &.{},
    color: enum { auto, always, never } = .auto,
};

const good =
    \\.{
    \\    .name = "my search",
    \\    .globs = .{ "*.zig", "*.md" },
    \\    .color = .never, // ZON allows comments
    \\}
;

const bad =
    \\.{ .name = "x", .jobs = 1000 }
;

pub fn main(init: std.process.Init) !void {
    var buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &buffer);
    const out = &stdout_writer.interface;

    var arena: std.heap.ArenaAllocator = .init(init.gpa);
    defer arena.deinit();

    for ([_][:0]const u8{ good, bad }) |source| {
        var diagnostics: std.zon.parse.Diagnostics = undefined;
        const settings = std.zon.parse.fromSlice(Settings, .{
            .gpa = init.gpa,
            .arena = arena.allocator(), // the result lives in the arena
            .source = source,
            .diagnostics = &diagnostics,
        }) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.ParseZon => {
                try out.print("{f}", .{diagnostics.fmt("settings.zon")});
                continue;
            },
        };
        try out.print("name={s} jobs={d} globs={d} color={t}\n", .{
            settings.name, settings.jobs, settings.globs.len, settings.color,
        });

        // And back to ZON text.
        try std.zon.stringify.serialize(settings, .{}, out);
        try out.writeByte('\n');
    }
    try out.flush();
}
```

```console
$ zig run examples/ch17/zon.zig
name=my search jobs=4 globs=2 color=never
.{
    .name = "my search",
    .jobs = 4,
    .globs = .{ "*.zig", "*.md" },
    .color = .never,
}
settings.zon:1:25: error: type 'u8' cannot represent value
```

- The options take two allocators: `gpa` for scratch memory, `arena` for the result. Free the
  arena when you're done with the value.
- `.source` must be a `[:0]const u8`: the ZON parser is Zig's parser, which wants a zero-terminated
  buffer. String literals already are.
- On `error.ParseZon`, `diagnostics` describes the problem with line and column, like a compiler
  error; `diagnostics.fmt(path)` formats it.
- `.ignore_unknown_fields = true` works as in JSON.

ZON can also be imported at compile time: `@import("data.zon")` with a known result type gives the
value with no run-time parsing. `build.zig` uses this in [Chapter 18](18-build-system.md) to read
the version from `build.zig.zon`.

## Building seek: `--json`

`--json` prints **JSON Lines**: one JSON object per line. Each line stands alone, so tools can
stream the output line by line, and `grep` or `head` still work.

| Flags | One line per | Object |
|-------|--------------|--------|
| `--json` | selected line | `{"path":…,"line":…,"text":…}` (always with the line number) |
| `--json -c` | file | `{"path":…,"count":…}` (zero counts too, like `-c`) |
| `--json -l` | file with a match | `{"path":…}` |

Errors stay plain text on stderr. `--color` and `-n` have no effect with `--json`.

### `src/cli.zig`: the flag

Add a `json` field to `Options`, between `color` and `stats`:

```zig
    color: Color = .auto,
    json: bool = false,
    stats: bool = false,
```

and its help text in `descriptions`, after `.color`:

```zig
        .color = "highlight matches",
        .json = "print results as JSON Lines (one object per line)",
        .stats = "print statistics to stderr when done",
```

That's all: the comptime parser from [Chapter 12](12-comptime.md) generates `--json` and its help
line from the field.

### `src/output.zig`: a JSON printer

`Printer` is a tagged union of output modes. Add a fourth variant after `files`. JSON has the same
three sub-modes as text, so its payload is a small enum:

```zig
    /// -l: print the names of files with a selected line.
    files,
    /// --json: print JSON Lines, one object per line. Like the text modes,
    /// it can report every line, a count per file (-c) or file names (-l).
    json: Json,

    pub const Json = enum { lines, count, files };
```

In `init`, check `--json` first:

```zig
    pub fn init(options: Options, matcher: Matcher) Printer {
        if (options.json) {
            return .{ .json = if (options.files_only) .files else if (options.count_only) .count else .lines };
        }
        // -l wins over -c, like in grep.
        if (options.files_only) return .files;
```

(the rest of `init` is unchanged). Now `switch (printer)` in `line` and `fileDone` no longer
compiles: the switches don't handle `.json`. That's exhaustive switching doing its job. Replace
both functions:

```zig
    /// Called for every selected line.
    pub fn line(printer: Printer, w: *Io.Writer, path: []const u8, line_number: usize, text: []const u8) Io.Writer.Error!void {
        switch (printer) {
            .lines => |lines| {
                const match: Match = .{
                    .path = path,
                    .line_number = if (lines.line_numbers) line_number else null,
                    .text = text,
                    .highlight = lines.highlight,
                };
                try w.print("{f}\n", .{match});
            },
            .json => |json| if (json == .lines) {
                try writeJson(w, JsonLine{ .path = path, .line = line_number, .text = text });
            },
            .count, .files => {},
        }
    }

    /// Called once a file has been searched, with its number of selected lines.
    pub fn fileDone(printer: Printer, w: *Io.Writer, path: []const u8, matches: usize) Io.Writer.Error!void {
        switch (printer) {
            .lines => {},
            .count => try w.print("{s}:{d}\n", .{ path, matches }),
            .files => if (matches > 0) try w.print("{s}\n", .{path}),
            .json => |json| switch (json) {
                .lines => {},
                .count => try writeJson(w, .{ .path = path, .count = matches }),
                .files => if (matches > 0) try writeJson(w, .{ .path = path }),
            },
        }
    }
};
```

After the `Printer` union (between its closing `};` and `/// One selected line, ready to print
with {f}.`), add the line type and a helper:

```zig
/// One selected line in --json output.
pub const JsonLine = struct {
    path: []const u8,
    line: usize,
    text: []const u8,
};

/// Writes `value` as one line of JSON. std.json serializes structs (even
/// anonymous ones) field by field and escapes strings as needed.
fn writeJson(w: *Io.Writer, value: anytype) Io.Writer.Error!void {
    try w.print("{f}\n", .{std.json.fmt(value, .{})});
}
```

- `JsonLine` is a named, `pub` struct because tests (and other programs) parse it back.
- The `-c` and `-l` objects are anonymous structs (`.{ .path = path, .count = matches }`). Each
  call creates a new struct type at compile time, which `std.json` handles like any other.
- `writeJson` takes `value: anytype` because it receives three different types. That's the right
  place for `anytype`: a private helper whose callers are all in view. (Public APIs are clearer
  with concrete types; see [Chapter 13](13-generics.md).)
- Output field order is declaration order: `path`, `line`, `text`.

Add two tests after the test "Printer.count and Printer.files summarize each file":

```zig
test "Printer.json writes JSON Lines that parse back" {
    const gpa = testing.allocator;
    var out: Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    const printer: Printer = .init(.{ .json = true }, .init("fox", false, false));
    try printer.line(&out.writer, "a.txt", 2, "say \"fox\"\tnow");
    try testing.expectEqualStrings(
        \\{"path":"a.txt","line":2,"text":"say \"fox\"\tnow"}
        \\
    , out.written());

    // Parsing allocates; `parsed.deinit()` frees it all at once.
    const parsed = try std.json.parseFromSlice(JsonLine, gpa, out.written(), .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("say \"fox\"\tnow", parsed.value.text);
    try testing.expectEqual(2, parsed.value.line);
}

test "Printer.json with -c and -l" {
    var buffer: [128]u8 = undefined;
    var w: Io.Writer = .fixed(&buffer);
    const matcher: Matcher = .init("fox", false, false);
    const count: Printer = .init(.{ .json = true, .count_only = true }, matcher);
    try count.fileDone(&w, "a.txt", 3);
    const files: Printer = .init(.{ .json = true, .files_only = true }, matcher);
    try files.fileDone(&w, "a.txt", 3);
    try files.fileDone(&w, "b.txt", 0);
    try testing.expectEqualStrings(
        \\{"path":"a.txt","count":3}
        \\{"path":"a.txt"}
        \\
    , w.buffered());
}
```

The first test is a **round trip**: write JSON, parse it back, compare. It proves the escaping is
right without reasoning about escape rules.

### `src/search.zig`: keep `-l` fast

With `-l`, `searchReader` stops reading a file after the first selected line. It decided this by
checking the printer:

```zig
        const limit: usize = if (self.printer == .files) 1 else self.options.max_count orelse std.math.maxInt(usize);
```

With `--json -l` the printer is `.json`, not `.files`, so `seek` would read every file to the
end: right output, slower, and no test would notice. Ask the option instead. Replace the comment
and the `limit` line with:

```zig
        // For -l, one selected line answers the question (with or without
        // --json).
        const limit: usize = if (self.options.files_only) 1 else self.options.max_count orelse std.math.maxInt(usize);
```

### Checkpoint

```console
$ zig build test --summary all
Build Summary: 3/3 steps succeeded; 24/24 tests passed
test success
+- run test 24 pass (24 total) 13ms MaxRSS:6M
   +- compile test debug native success 381ms MaxRSS:166M
$ zig build
$ ./zig-out/bin/seek --json fox testdata
{"path":"testdata/notes/log.txt","line":1,"text":"2024-01-01 saw a fox near the barn"}
{"path":"testdata/notes/log.txt","line":3,"text":"2024-01-03 fox tracks in the snow"}
{"path":"testdata/notes/todo.md","line":2,"text":"- feed the fox"}
{"path":"testdata/poem.txt","line":1,"text":"The quick brown fox"}
$ ./zig-out/bin/seek --json -c fox testdata
{"path":"testdata/notes/log.txt","count":2}
{"path":"testdata/notes/todo.md","count":1}
{"path":"testdata/poem.txt","count":1}
$ ./zig-out/bin/seek --json -l -i fox testdata
{"path":"testdata/notes/log.txt"}
{"path":"testdata/notes/todo.md"}
{"path":"testdata/poem.txt"}
$ ./zig-out/bin/seek --json -v -n fox testdata/poem.txt
{"path":"testdata/poem.txt","line":2,"text":"jumps over the lazy dog."}
{"path":"testdata/poem.txt","line":3,"text":"A Fox is quick and clever;"}
{"path":"testdata/poem.txt","line":4,"text":"the dog just sleeps."}
{"path":"testdata/poem.txt","line":5,"text":"Foxes everywhere!"}
$ ./zig-out/bin/seek --json zebra testdata; echo "exit $?"
exit 1
$ ./zig-out/bin/seek --json -W -i '*fox' testdata nope.txt; echo "exit $?"
{"path":"testdata/notes/todo.md","line":2,"text":"- feed the fox"}
{"path":"testdata/poem.txt","line":1,"text":"The quick brown fox"}
seek: nope.txt: FileNotFound
exit 2
```

(Test timings differ.) Escaping works on real input. This `printf` sends a line with double quotes,
a tab, and a trailing backslash:

```console
$ printf 'say "hi"\tto the fox\\\n' | ./zig-out/bin/seek --json fox -
{"path":"(standard input)","line":1,"text":"say \"hi\"\tto the fox\\"}
```

A line that isn't valid UTF-8 (`\xff` is a lone byte) gets the array form from earlier:

```console
$ printf 'a fox \xff here\n' | ./zig-out/bin/seek --json fox -
{"path":"(standard input)","line":1,"text":[97,32,102,111,120,32,255,32,104,101,114,101]}
```

That's still valid JSON. `seek` searches bytes, not text, so Latin-1 or broken encodings produce
such lines. A program reading `seek --json` should accept a string or an array of byte values for
`"text"`.

`--help` picked up the flag on its own:

```console
$ ./zig-out/bin/seek -h | grep json
      --json                     print results as JSON Lines (one object per line)
```

The complete project at this point is in `project/ch17/`.

## Summary

- `std.json.fmt(value, options)` with `{f}` writes any value as JSON: structs → objects, slices →
  arrays, enums and errors → strings, tagged unions → one-key objects.
- Options: `whitespace` (pretty output), `emit_null_optional_fields`, `escape_unicode`, and more.
  `Stringify.valueAlloc` returns an allocated string.
- Bytes that aren't valid UTF-8 become an array of numbers.
- `std.json.parseFromSlice(T, gpa, text, .{})` parses and validates against `T`. It's strict:
  unknown, missing, duplicate, or out-of-range values are errors.
- The result is a `Parsed(T)` whose `value` lives in an arena that `deinit` frees in one go; copy
  what must outlive it. `parseFromSliceLeaky` takes your own arena.
- `std.json.Value` is a tagged union for JSON of unknown shape.
- A `jsonStringify(self, jw)` method customizes output.
- ZON is Zig-syntax data: `std.zon.parse.fromSlice` and `std.zon.stringify.serialize`.
- JSON Lines (one object per line) suits command-line tools.

## Exercises

1. Write a program that reads `seek --json` output from standard input and prints `path:line` for
   each object. Parse each line into a struct.

   <details><summary>Solution</summary>

   ```zig
   const std = @import("std");

   const JsonLine = struct { path: []const u8, line: usize, text: []const u8 };

   pub fn main(init: std.process.Init) !void {
       var in_buffer: [64 * 1024]u8 = undefined;
       var stdin_reader: std.Io.File.Reader = .initStreaming(.stdin(), init.io, &in_buffer);
       const in = &stdin_reader.interface;
       var out_buffer: [4096]u8 = undefined;
       var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &out_buffer);
       const out = &stdout_writer.interface;

       while (try in.takeDelimiter('\n')) |line| {
           const parsed = try std.json.parseFromSlice(JsonLine, init.gpa, line, .{});
           defer parsed.deinit();
           try out.print("{s}:{d}\n", .{ parsed.value.path, parsed.value.line });
       }
       try out.flush();
   }
   ```

   ```console
   $ ./zig-out/bin/seek --json -i fox testdata | zig run locations.zig
   testdata/notes/log.txt:1
   testdata/notes/log.txt:3
   testdata/notes/todo.md:2
   testdata/poem.txt:1
   testdata/poem.txt:3
   testdata/poem.txt:5
   ```

   Each line is parsed and freed before the next, so memory use stays flat. A line whose `"text"`
   is a byte array (invalid UTF-8) still parses: a `[]const u8` field accepts an array of numbers
   too.

   </details>

2. Add a test to `src/output.zig` that checks what `--json` prints for the line `"fox\xff"`.

   <details><summary>Solution</summary>

   ```zig
   test "Printer.json writes invalid UTF-8 as an array of bytes" {
       var buffer: [128]u8 = undefined;
       var w: Io.Writer = .fixed(&buffer);
       const printer: Printer = .init(.{ .json = true }, .init("fox", false, false));
       try printer.line(&w, "a.txt", 1, "fox\xff");
       try testing.expectEqualStrings(
           \\{"path":"a.txt","line":1,"text":[102,111,120,255]}
           \\
       , w.buffered());
   }
   ```

   `zig build test --summary all` now reports `25/25 tests passed`.

   </details>

3. Write a program that reads `build.zig.zon` from the current directory and prints the version.
   Hint: the ZON parser needs a zero-terminated buffer; `Io.Dir.readFileAllocOptions` can add the
   terminator. Parse into a struct with only a `version` field.

   <details><summary>Solution</summary>

   ```zig
   const std = @import("std");

   pub fn main(init: std.process.Init) !void {
       var arena: std.heap.ArenaAllocator = .init(init.gpa);
       defer arena.deinit();
       const source = try std.Io.Dir.cwd().readFileAllocOptions(init.io, "build.zig.zon", arena.allocator(), .limited(64 * 1024), .of(u8), 0);

       var diagnostics: std.zon.parse.Diagnostics = undefined;
       const Manifest = struct { version: []const u8 };
       const manifest = std.zon.parse.fromSlice(Manifest, .{
           .gpa = init.gpa,
           .arena = arena.allocator(),
           .source = source,
           .diagnostics = &diagnostics,
           .ignore_unknown_fields = true,
       }) catch |err| switch (err) {
           error.OutOfMemory => return err,
           error.ParseZon => diagnostics.fatal("build.zig.zon"),
       };
       std.debug.print("version {s}\n", .{manifest.version});
   }
   ```

   Run from the `seek` project folder:

   ```console
   $ zig run version.zig
   version 0.1.0
   ```

   The last two arguments of `readFileAllocOptions` are the alignment (`.of(u8)`) and the sentinel
   (`0`), so it returns a `[:0]u8`. `.ignore_unknown_fields = true` skips `.name`, `.fingerprint`,
   and the rest. `diagnostics.fatal` prints the error and exits.

   </details>

4. Before this chapter's `search.zig` change, would `seek --json -l fox testdata` have printed
   anything different? What would have been different?

   <details><summary>Solution</summary>

   Same output: `fileDone` prints `{"path":…}` once per file with `matches > 0`, whether `matches`
   is 1 or 10. The difference is work. With the old check (`self.printer == .files`), the `.json`
   printer got no limit, so `seek` read every matching file to the end instead of stopping at the
   first selected line. Output-only tests can't see that. That's why the condition should ask the
   user's intent (`options.files_only`), not an implementation detail (which printer was chosen).

   </details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-17--json-and-data-serialization)
