# Chapter 13 — Generic Programming

[Chapter 12](12-comptime.md) showed that types are ordinary comptime values. A function that takes a type is a generic function; a function that *returns* a type is a generic type. With these two ideas you can build containers like `std.ArrayList`, state what a type must provide, and give clear errors when it doesn't. seek gets a `--stats` summary built on a generic `Counter(K)`.

## Generic functions: `comptime T: type`

A generic function takes the type as a `comptime` parameter, which later parameters and the return type can use:

`examples/ch13/generic_fn.zig`

```zig
const std = @import("std");

/// The type is an explicit comptime parameter.
fn max(comptime T: type, a: T, b: T) T {
    return if (a > b) a else b;
}

/// The type is inferred from the first argument.
fn larger(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return if (a > b) a else b;
}

/// Works for anything with a `len` field and indexing: arrays, slices,
/// and pointers to arrays.
fn first(items: anytype) @TypeOf(items[0]) {
    return items[0];
}

pub fn main() void {
    std.debug.print("max(u8, 3, 7) = {d}\n", .{max(u8, 3, 7)});
    std.debug.print("max(f64, 2.5, -1) = {d}\n", .{max(f64, 2.5, -1)});

    const a: i32 = -4;
    std.debug.print("larger(a, 10) = {d}\n", .{larger(a, 10)});
    std.debug.print("@TypeOf(larger(a, 10)) = {s}\n", .{@typeName(@TypeOf(larger(a, 10)))});

    const array = [_]u16{ 10, 20, 30 };
    const slice: []const u16 = &array;
    std.debug.print("first: {d} {d} {c}\n", .{ first(array), first(slice), first("zig") });
}
```

```console
$ zig run examples/ch13/generic_fn.zig
max(u8, 3, 7) = 7
max(f64, 2.5, -1) = 2.5
larger(a, 10) = 10
@TypeOf(larger(a, 10)) = i32
first: 10 10 z
```

Things to notice:

- `max(u8, 3, 7)` and `max(f64, 2.5, -1)` are two different functions in the program: the compiler makes one copy of `max` per distinct `T`. This is **monomorphization**, as in C++ templates and Rust generics. It costs code size, but each copy is as fast as hand-written code.
- `larger` uses `anytype`: the parameter's type is whatever the caller passes. `@TypeOf(a)` names it, so `b` and the result share `a`'s type. The `10` coerces to `i32`.
- `first` works with an array, a slice, and a string literal; the body only needs `items[0]` to compile.

Generic code is type-checked once per instantiation, with the real types. An instantiation that makes no sense is a compile error. `max(bool, true, false)` gives:

```text
generic_fn.zig:5:18: error: operator > not allowed for type 'bool'
```

The error points into `max`, not at your call. We'll come back to that.

## `anytype` and duck typing

With `anytype`, a function accepts any value that supports the operations in its body: **duck typing**, checked at compile time:

`examples/ch13/duck.zig`

```zig
const std = @import("std");

const Dog = struct {
    name: []const u8,
    pub fn speak(self: Dog) []const u8 {
        _ = self;
        return "woof";
    }
};

const Robot = struct {
    id: u32,
    pub fn speak(self: Robot) []const u8 {
        return if (self.id % 2 == 0) "beep" else "boop";
    }
};

/// Accepts any value with a `speak` method that returns a string.
fn introduce(thing: anytype) void {
    std.debug.print("{s} says {s}\n", .{ @typeName(@TypeOf(thing)), thing.speak() });
}

pub fn main() void {
    introduce(Dog{ .name = "Rex" });
    introduce(Robot{ .id = 7 });
}
```

```console
$ zig run examples/ch13/duck.zig
duck.Dog says woof
duck.Robot says boop
```

`Dog` and `Robot` share only a method named `speak`, and that is enough. Pass a `u32` and the compiler stops you:

```text
duck.zig:20:74: error: no field or member function named 'speak' in 'u32'
    std.debug.print("{s} says {s}\n", .{ @typeName(@TypeOf(thing)), thing.speak() });
                                                                    ~~~~~^~~~~~
referenced by:
    main: duck.zig:26:14
```

The "referenced by" trace leads from the error back to your call.

`anytype` costs **documentation**: `fn introduce(thing: anytype) void` says nothing about what `thing` needs, so readers must read the body. Prefer `comptime T: type` when the type is the point. When you use `anytype`, state the requirements in the doc comment, as `introduce` does, or check them in code (see [Constraints](#constraints-and-good-error-messages)).

The standard library uses `anytype` mostly where the set of types is open-ended: `std.debug.print` takes `args: anytype` because any tuple may be printed.

## Generic types: functions that return `type`

Zig has no special syntax for generic types. A generic type is a function with comptime parameters that **returns a `type`**, usually an anonymous `struct`:

`examples/ch13/stack.zig`

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

/// A generic type is a function that takes types and returns a type.
fn Stack(comptime T: type) type {
    return struct {
        // The struct has no name of its own; @This() refers to it.
        const Self = @This();

        items: std.ArrayList(T) = .empty,

        pub fn deinit(self: *Self, gpa: Allocator) void {
            self.items.deinit(gpa);
        }

        pub fn push(self: *Self, gpa: Allocator, value: T) Allocator.Error!void {
            try self.items.append(gpa, value);
        }

        pub fn pop(self: *Self) ?T {
            return self.items.pop();
        }

        pub fn peek(self: Self) ?T {
            if (self.items.items.len == 0) return null;
            return self.items.items[self.items.items.len - 1];
        }
    };
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var numbers: Stack(u32) = .{};
    defer numbers.deinit(gpa);
    for ([_]u32{ 1, 2, 3 }) |n| try numbers.push(gpa, n);
    std.debug.print("peek: {?d}\n", .{numbers.peek()});
    while (numbers.pop()) |n| std.debug.print("pop: {d}\n", .{n});
    std.debug.print("empty: {?d}\n", .{numbers.pop()});

    var words: Stack([]const u8) = .{};
    defer words.deinit(gpa);
    try words.push(gpa, "hello");
    std.debug.print("word: {?s}\n", .{words.peek()});

    // The same arguments give the same type: Stack(u32) is computed once.
    std.debug.print("Stack(u32) == Stack(u32): {}\n", .{Stack(u32) == Stack(u32)});
    std.debug.print("Stack(u32) == Stack(i32): {}\n", .{Stack(u32) == Stack(i32)});
    std.debug.print("name: {s}\n", .{@typeName(Stack(u32))});
}
```

```console
$ zig run examples/ch13/stack.zig
peek: 3
pop: 3
pop: 2
pop: 1
empty: null
word: hello
Stack(u32) == Stack(u32): true
Stack(u32) == Stack(i32): false
name: stack.Stack(u32)
```

Things to notice:

- The returned `struct { ... }` has no name. **`@This()`** returns the innermost struct, enum, or union it appears in, so `const Self = @This();` names the type for method signatures. `Self` is a convention, not a keyword.
- `T` is in scope inside the struct, for fields, methods, and nested declarations.
- Calling `Stack(u32)` twice gives the **same** type. The compiler caches comptime calls by their arguments, so the type is created once and all `Stack(u32)` values are compatible.
- `@typeName` shows the call that made the type: `stack.Stack(u32)`.
- `var numbers: Stack(u32) = .{};` reads like any other type: a generic type is a type expression that happens to be a function call.

The struct can also hold **comptime-only** declarations. `pub const Entry = struct { key: K, count: usize };` inside a generic type gives each instantiation its own `Entry` type; seek's `Counter` uses this below.

## How `std.ArrayList` is built

You have used `std.ArrayList(T)` since [Chapter 10](10-containers.md). Now you can read it. In `lib/std/std.zig`:

```zig
pub fn ArrayList(comptime T: type) type {
    return array_list.Aligned(T, null);
}
```

It forwards to `array_list.Aligned(T, alignment)`, a generic type with two comptime parameters. The start of it (`lib/std/array_list.zig`, comments shortened):

```zig
pub fn Aligned(comptime T: type, comptime alignment: ?mem.Alignment) type {
    if (alignment) |a| {
        if (a.toByteUnits() == @alignOf(T)) {
            return Aligned(T, null);
        }
    }
    return struct {
        const Self = @This();
        /// Contents of the list. This field is intended to be accessed
        /// directly.
        items: Slice,
        /// How many T values this list can hold without allocating
        /// additional memory.
        capacity: usize,

        /// Used to detect memory safety violations.
        pointer_stability: debug.SafetyLock,

        /// An ArrayList containing no elements.
        pub const empty: Self = .{
            .items = &.{},
            .capacity = 0,
            .pointer_stability = .{},
        };

        pub const Slice = if (alignment) |a| ([]align(a.toByteUnits()) T) else []T;
        // ... methods ...
    };
}
```

Some comptime tricks are already visible:

- Before building a struct, `Aligned` checks its arguments. If the requested alignment is the natural one, it returns `Aligned(T, null)`, so both spellings give the same type.
- `Slice` is chosen with a comptime `if`.
- `empty` is a declaration of type `Self`, which is why `var list: std.ArrayList(u8) = .empty;` works.

The core idea fits in a page. This cut-down version keeps the two main fields, `items` and `capacity`:

`examples/ch13/mini_list.zig`

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

/// A cut-down std.ArrayList: the same fields and the same growth idea.
fn List(comptime T: type) type {
    return struct {
        const Self = @This();

        /// The elements in use. `items.len` is the length of the list.
        items: []T,
        /// How many elements fit before we must allocate again.
        capacity: usize,

        pub const empty: Self = .{ .items = &.{}, .capacity = 0 };

        pub fn deinit(self: *Self, gpa: Allocator) void {
            gpa.free(self.allocatedSlice());
            self.* = undefined;
        }

        /// All the memory we own, used or not.
        fn allocatedSlice(self: Self) []T {
            return self.items.ptr[0..self.capacity];
        }

        pub fn append(self: *Self, gpa: Allocator, value: T) Allocator.Error!void {
            if (self.items.len == self.capacity) try self.grow(gpa);
            self.items.len += 1;
            self.items[self.items.len - 1] = value;
        }

        fn grow(self: *Self, gpa: Allocator) Allocator.Error!void {
            // Start with at least one cache line of elements; this is
            // computed at compile time from the size of T.
            const min_capacity = comptime @max(1, 64 / @sizeOf(T));
            const new_capacity = @max(min_capacity, self.capacity * 2);
            const new_memory = try gpa.alloc(T, new_capacity);
            @memcpy(new_memory[0..self.items.len], self.items);
            gpa.free(self.allocatedSlice());
            self.items = new_memory[0..self.items.len];
            self.capacity = new_capacity;
        }
    };
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var bytes: List(u8) = .empty;
    defer bytes.deinit(gpa);
    var points: List([3]f64) = .empty;
    defer points.deinit(gpa);

    for (0..100) |i| {
        try bytes.append(gpa, @intCast(i));
        try points.append(gpa, .{ 0, 0, @floatFromInt(i) });
    }
    std.debug.print("bytes:  len {d}, capacity {d}\n", .{ bytes.items.len, bytes.capacity });
    std.debug.print("points: len {d}, capacity {d}\n", .{ points.items.len, points.capacity });
    std.debug.print("last point: {any}\n", .{points.items[99]});
}
```

```console
$ zig run examples/ch13/mini_list.zig
bytes:  len 100, capacity 128
points: len 100, capacity 128
last point: { 0, 0, 99 }
```

`items.len` is the number of elements in use; `items.ptr` points to a block of `capacity` elements. Appending into spare capacity only bumps `items.len`. When the block is full, `grow` allocates a bigger one, copies, and frees the old one. Growing by doubling makes `append` cheap on average.

`min_capacity` is computed at compile time from `@sizeOf(T)`: 64 elements for `u8`, 2 for a 24-byte `[3]f64`. The real `ArrayList` does the same in `growCapacity` with `std.atomic.cache_line`, and first tries `gpa.remap` to grow the block in place without copying.

## Constraints and good error messages

The error from `max(bool, true, false)` pointed into `max`'s body. In a large generic function, the reader must then work out which requirement their type broke. A comptime check at the top gives one clear message instead: inspect the type with `@typeInfo` and reject it with `@compileError`:

`examples/ch13/constraints.zig`

```zig
const std = @import("std");

fn isNumber(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .int, .float, .comptime_int, .comptime_float => true,
        else => false,
    };
}

/// Adds up a slice of numbers.
fn sum(comptime T: type, values: []const T) T {
    if (!comptime isNumber(T)) @compileError("sum: expected a number type, found " ++ @typeName(T));
    var total: T = 0;
    for (values) |v| total += v;
    return total;
}

/// Averages anything that coerces to a slice of floats or ints.
fn mean(values: anytype) f64 {
    const Values = @TypeOf(values);
    const Elem = switch (@typeInfo(Values)) {
        .pointer => |info| switch (info.size) {
            .slice => info.child,
            .one => @typeInfo(info.child).array.child, // pointer to array
            else => @compileError("mean: unsupported pointer " ++ @typeName(Values)),
        },
        .array => |info| info.child,
        else => @compileError("mean: expected an array or slice, found " ++ @typeName(Values)),
    };
    if (!comptime isNumber(Elem)) @compileError("mean: elements must be numbers, found " ++ @typeName(Elem));

    var total: f64 = 0;
    for (values) |v| total += switch (@typeInfo(Elem)) {
        .int => @floatFromInt(v),
        else => v,
    };
    return total / @as(f64, @floatFromInt(values.len));
}

pub fn main() void {
    const ints = [_]i32{ 4, 8, 15, 16, 23, 42 };
    const floats = [_]f32{ 0.5, 1.5 };
    std.debug.print("sum = {d}\n", .{sum(i32, &ints)});
    std.debug.print("mean(ints) = {d}\n", .{mean(ints)});
    std.debug.print("mean(&floats) = {d}\n", .{mean(&floats)});
    std.debug.print("mean(slice) = {d}\n", .{mean(@as([]const i32, ints[0..2]))});
}
```

```console
$ zig run examples/ch13/constraints.zig
sum = 108
mean(ints) = 18
mean(&floats) = 1
mean(slice) = 6
```

Bad calls now fail with a message written for the caller:

```text
constraints.zig:12:32: error: sum: expected a number type, found bool
constraints.zig:28:17: error: mean: expected an array or slice, found u8
constraints.zig:30:35: error: mean: elements must be numbers, found bool
```

These came from `sum(bool, &.{ true, false })`, `mean(@as(u8, 3))`, and `mean([_]bool{true})`, each followed by a "referenced by" trace to the bad call.

**Why `comptime isNumber(T)`?** Without the `comptime` keyword, *every* call fails, even `sum(i32, &ints)`:

```text
constraints.zig:12:23: error: sum: expected a number type, found i32
    if (!isNumber(T)) @compileError("sum: expected a number type, found " ++ @typeName(T));
                      ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
```

A function call runs at compile time only when something forces it to; comptime arguments are not enough. `isNumber(T)` is an ordinary run-time call returning a run-time `bool`. With a run-time condition, the compiler compiles both branches of the `if`, and compiling `@compileError` is the error. `comptime isNumber(T)` makes the result comptime-known, so the branch not taken is never analyzed.

Expressions made only of builtins on types don't have this problem: `@typeInfo(T) != .int`, `T == []const u8`, and `@hasDecl(T, "write")` are already comptime-known. That is why `maxOf` in [Chapter 12](12-comptime.md) needed no `comptime` keyword.

Write a constraint check when:

- the function is public and the requirement isn't obvious from the signature;
- the natural error would appear deep in the body or in another generic function;
- a type would compile but behave wrongly (for example, comparing slices by pointer).

## Comptime interfaces: requiring declarations

Duck typing checks one operation at a time, as the body uses them. Sometimes you want to state a whole contract up front: "a `Sink` has a `write` method with this exact signature". `@hasDecl` checks that a declaration exists, and `@TypeOf(T.write)` gives its function type to compare with `==`:

`examples/ch13/comptime_interface.zig`

```zig
const std = @import("std");

/// The "interface": a Sink must have `pub fn write(self: *Sink, line: []const u8) void`.
fn requireSink(comptime T: type) void {
    if (!@hasDecl(T, "write")) {
        @compileError(@typeName(T) ++ " is not a Sink: it has no pub fn write");
    }
    const Expected = fn (*T, []const u8) void;
    if (@TypeOf(T.write) != Expected) {
        @compileError(@typeName(T) ++ ".write must be " ++ @typeName(Expected) ++
            ", found " ++ @typeName(@TypeOf(T.write)));
    }
}

/// A logger that numbers its lines and sends them to any Sink.
fn Logger(comptime Sink: type) type {
    comptime requireSink(Sink);
    return struct {
        const Self = @This();

        sink: *Sink,
        count: usize = 0,

        pub fn log(self: *Self, line: []const u8) void {
            self.count += 1;
            var buffer: [256]u8 = undefined;
            const text = std.mem.print(&buffer, "[{d}] {s}", .{ self.count, line }) catch line;
            self.sink.write(text);
        }
    };
}

const PrintSink = struct {
    pub fn write(_: *PrintSink, line: []const u8) void {
        std.debug.print("{s}\n", .{line});
    }
};

const ByteCounter = struct {
    bytes: usize = 0,
    pub fn write(self: *ByteCounter, line: []const u8) void {
        self.bytes += line.len;
    }
};

pub fn main() void {
    var printer: PrintSink = .{};
    var log_to_screen: Logger(PrintSink) = .{ .sink = &printer };
    log_to_screen.log("starting");
    log_to_screen.log("done");

    var counter: ByteCounter = .{};
    var log_to_counter: Logger(ByteCounter) = .{ .sink = &counter };
    log_to_counter.log("hello");
    log_to_counter.log("world");
    std.debug.print("counted {d} bytes\n", .{counter.bytes});
}
```

```console
$ zig run examples/ch13/comptime_interface.zig
[1] starting
[2] done
counted 18 bytes
```

`Logger(Sink)` runs `requireSink` once, when the type is created. If `ByteCounter.write` returns `usize` instead of `void`, the error names the problem and the type that caused it:

```text
comptime_interface.zig:10:9: error: comptime_interface.ByteCounter.write must be fn (*comptime_interface.ByteCounter, []const u8) void, found fn (*comptime_interface.ByteCounter, []const u8) usize
        @compileError(@typeName(T) ++ ".write must be " ++ @typeName(Expected) ++
        ^~~~~~~~~~~~~
comptime_interface.zig:17:25: note: called at comptime here
    comptime requireSink(Sink);
             ~~~~~~~~~~~^~~~~~
comptime_interface.zig:54:31: note: called at comptime here
    var log_to_counter: Logger(ByteCounter) = .{ .sink = &counter };
```

`@hasDecl` only works on container types. `Logger(u8)` fails inside `requireSink` with `expected struct, enum, union, or opaque; found 'u8'`, which is still clear.

This is a **comptime interface**: checked and resolved at compile time, free at run time. Each `Logger(Sink)` is a separate type that calls `sink.write` directly. The price: `Logger(PrintSink)` and `Logger(ByteCounter)` are different types, so they can't share an array. That needs run-time polymorphism.

## Type erasure: a preview

To store values of different types together, hide (**erase**) their types behind a common one. The pointer becomes `*anyopaque`, a pointer to "something". It has no methods, so we also store a function pointer that knows the real type, generated by a generic `init`:

`examples/ch13/type_erasure.zig`

```zig
const std = @import("std");

/// Anything with a `run` method, with its concrete type erased.
const Task = struct {
    ptr: *anyopaque,
    runFn: *const fn (ptr: *anyopaque) void,

    /// `object` must be a pointer to a value with `pub fn run(self: *T) void`.
    fn init(object: anytype) Task {
        const T = @typeInfo(@TypeOf(object)).pointer.child;
        // One wrapper function is generated per T. It knows the real type
        // and turns the *anyopaque back into a *T.
        const gen = struct {
            fn run(ptr: *anyopaque) void {
                const self: *T = @ptrCast(@alignCast(ptr));
                self.run();
            }
        };
        return .{ .ptr = object, .runFn = gen.run };
    }

    fn run(task: Task) void {
        task.runFn(task.ptr);
    }
};

const Greeter = struct {
    name: []const u8,
    pub fn run(self: *Greeter) void {
        std.debug.print("hello, {s}\n", .{self.name});
    }
};

const Counter = struct {
    count: u32 = 0,
    pub fn run(self: *Counter) void {
        self.count += 1;
        std.debug.print("count is now {d}\n", .{self.count});
    }
};

pub fn main() void {
    var greeter: Greeter = .{ .name = "Zig" };
    var counter: Counter = .{};

    // Different types, one array: every element is just a Task.
    const tasks = [_]Task{ .init(&greeter), .init(&counter), .init(&counter) };
    for (tasks) |task| task.run();
    std.debug.print("@sizeOf(Task) = {d}\n", .{@sizeOf(Task)});
}
```

```console
$ zig run examples/ch13/type_erasure.zig
hello, Zig
count is now 1
count is now 2
@sizeOf(Task) = 16
```

Things to notice:

- `gen` is a struct inside `init` that only holds a function. Each `T` gets its own `gen.run`, which captures `T` from its comptime surroundings.
- `@ptrCast(@alignCast(ptr))` turns the `*anyopaque` back into `*T`. `@alignCast` checks alignment in safe builds. Nothing checks that `ptr` really points to a `T`; that holds by construction, since only `init` sets both fields together.
- A `Task` is two pointers (16 bytes), whatever it wraps. It doesn't own the object: `greeter` and `counter` must outlive the tasks.

`std.mem.Allocator` works this way: a context pointer plus a table of functions. [Chapter 14](14-polymorphism.md) covers it properly, with Zig's other kinds of polymorphism.

## Measuring time with `std.Io.Clock`

seek's `--stats` will report how long the search took. Time, like files, comes from `std.Io`:

`examples/ch13/timing.zig`

```zig
const std = @import("std");
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    // `awake` is monotonic: right for measuring how long something takes.
    const start = Io.Clock.awake.now(io);
    try io.sleep(.fromMilliseconds(20), .awake);
    const elapsed = start.untilNow(io, .awake);
    std.debug.print("slept for about {d} ms\n", .{elapsed.toMilliseconds()});

    // {f} calls Duration.format, which picks a unit.
    const examples = [_]Io.Duration{ .fromNanoseconds(750), .fromMicroseconds(1500), .fromSeconds(90) };
    for (examples) |d| std.debug.print("{f}\n", .{d});
}
```

```console
$ zig run examples/ch13/timing.zig
slept for about 20 ms
750ns
1.5ms
1m30s
```

- `Io.Clock` is an enum of clocks. `.awake` is **monotonic**: it never jumps backwards when someone sets the system time, so the difference between two readings is reliable. `.real` is wall-clock time (since 1970): right for timestamps, wrong for durations. `.boot` is like `.awake` but also counts time suspended, where the OS supports it.
- `clock.now(io)` returns an `Io.Timestamp`; `timestamp.untilNow(io, clock)` returns the `Io.Duration` since then. Use the same clock for both.
- A `Duration` holds nanoseconds in an `i96`. Its `format` method picks a readable unit, so print it with `{f}`; use `toMilliseconds` and friends for numbers.
- `io.sleep(duration, clock)` pauses. It can return `error.Canceled` ([Chapter 15](15-concurrency.md)), hence the `try`.

The exact sleep time varies slightly between runs.

## Building seek: `--stats` with a generic `Counter`

The new `--stats` flag prints a summary to **stderr** after the results: files searched and matched, lines matched, time taken, and the five files with the most matching lines. Because it goes to stderr, `seek --stats ... > results.txt` still gives a clean result file.

Counting how often each key was seen is a common job, so it gets a reusable generic type, `Counter(K)`. seek uses `K = []const u8` (file paths); the tests use `u8`.

### `src/stats.zig` (new)

Create `src/stats.zig`:

```zig
//! Statistics for --stats, built on a generic counter.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

/// Returns a type that counts how often each key of type `K` was seen.
///
/// Strings need a different hash map than numbers: `AutoHashMap` refuses
/// slices (should it hash the pointer or the bytes?), so for `[]const u8`
/// we pick `StringHashMap`, which hashes the bytes. The choice happens at
/// compile time; each `Counter(K)` contains only the code it needs.
///
/// Keys are not copied: they must outlive the counter.
pub fn Counter(comptime K: type) type {
    const is_string = K == []const u8;
    if (!is_string and @typeInfo(K) != .int) {
        @compileError("Counter: keys must be integers or []const u8, not " ++ @typeName(K));
    }
    const Map = if (is_string)
        std.StringHashMapUnmanaged(usize)
    else
        std.AutoHashMapUnmanaged(K, usize);

    return struct {
        // Inside the anonymous struct, @This() is the only way to name it.
        const Self = @This();

        pub const Entry = struct { key: K, count: usize };

        map: Map = .empty,

        pub fn deinit(self: *Self, gpa: Allocator) void {
            self.map.deinit(gpa);
            self.* = undefined;
        }

        /// Adds `n` to the count for `key`.
        pub fn add(self: *Self, gpa: Allocator, key: K, n: usize) Allocator.Error!void {
            const result = try self.map.getOrPut(gpa, key);
            if (!result.found_existing) result.value_ptr.* = 0;
            result.value_ptr.* += n;
        }

        /// Returns the count for `key` (zero if it was never added).
        pub fn get(self: Self, key: K) usize {
            return self.map.get(key) orelse 0;
        }

        /// Returns at most `n` entries, highest count first. Equal counts
        /// are ordered by key, so the result never depends on the order of
        /// the hash map. The caller owns the returned slice.
        pub fn topN(self: Self, gpa: Allocator, n: usize) Allocator.Error![]Entry {
            var entries: std.ArrayList(Entry) = try .initCapacity(gpa, self.map.count());
            errdefer entries.deinit(gpa);
            var it = self.map.iterator();
            while (it.next()) |kv| {
                entries.appendAssumeCapacity(.{ .key = kv.key_ptr.*, .count = kv.value_ptr.* });
            }
            std.mem.sort(Entry, entries.items, {}, entryLessThan);
            entries.shrinkRetainingCapacity(@min(n, entries.items.len));
            return entries.toOwnedSlice(gpa);
        }

        fn entryLessThan(_: void, a: Entry, b: Entry) bool {
            if (a.count != b.count) return a.count > b.count;
            // `is_string` is comptime-known, so only one branch is compiled:
            // `<` on two slices would not compile.
            return if (is_string) std.mem.lessThan(u8, a.key, b.key) else a.key < b.key;
        }
    };
}

/// What --stats reports.
pub const Stats = struct {
    files_searched: usize = 0,
    files_matched: usize = 0,
    lines_matched: usize = 0,
    matches_per_file: Counter([]const u8) = .{},

    pub fn deinit(self: *Stats, gpa: Allocator) void {
        self.matches_per_file.deinit(gpa);
        self.* = undefined;
    }

    /// Records that `path` was searched and had `matches` selected lines.
    /// `path` must outlive the Stats.
    pub fn record(self: *Stats, gpa: Allocator, path: []const u8, matches: usize) Allocator.Error!void {
        self.files_searched += 1;
        if (matches == 0) return;
        self.files_matched += 1;
        self.lines_matched += matches;
        try self.matches_per_file.add(gpa, path, matches);
    }

    pub fn write(self: Stats, gpa: Allocator, w: *Io.Writer, elapsed: Io.Duration) (Allocator.Error || Io.Writer.Error)!void {
        try w.print(
            \\--- stats ---
            \\files searched: {d}
            \\files matched:  {d}
            \\matching lines: {d}
            \\elapsed:        {f}
            \\
        , .{ self.files_searched, self.files_matched, self.lines_matched, elapsed });

        const top = try self.matches_per_file.topN(gpa, 5);
        defer gpa.free(top);
        if (top.len == 0) return;
        try w.writeAll("top files:\n");
        for (top) |entry| try w.print("{d:>6}  {s}\n", .{ entry.count, entry.key });
    }
};

test "Counter counts integers" {
    const gpa = std.testing.allocator;
    var counter: Counter(u8) = .{};
    defer counter.deinit(gpa);

    for ("hello world") |byte| try counter.add(gpa, byte, 1);
    try std.testing.expectEqual(3, counter.get('l'));
    try std.testing.expectEqual(0, counter.get('z'));

    const top = try counter.topN(gpa, 2);
    defer gpa.free(top);
    try std.testing.expectEqual(2, top.len);
    try std.testing.expectEqual('l', top[0].key); // 3 times
    try std.testing.expectEqual('o', top[1].key); // 2 times
}

test "Counter counts strings and breaks ties by key" {
    const gpa = std.testing.allocator;
    var counter: Counter([]const u8) = .{};
    defer counter.deinit(gpa);

    try counter.add(gpa, "b.txt", 2);
    try counter.add(gpa, "a.txt", 2);
    try counter.add(gpa, "c.txt", 5);

    const top = try counter.topN(gpa, 10);
    defer gpa.free(top);
    try std.testing.expectEqual(3, top.len);
    try std.testing.expectEqualStrings("c.txt", top[0].key);
    try std.testing.expectEqualStrings("a.txt", top[1].key);
    try std.testing.expectEqualStrings("b.txt", top[2].key);
}
```

Walk through `Counter`:

- **The map is chosen at compile time.** `std.AutoHashMapUnmanaged(K, V)` hashes keys by their bytes, which works for integers. For a slice it refuses to guess whether you mean the pointer or the text:

  ```text
  .../lib/std/hash_map.zig:15:13: error: std.hash.autoHash does not allow slices here ([]const u8) because the intent is unclear. Consider using std.StringHashMap for hashing the contents of []const u8. Alternatively, consider using std.hash.autoHashStrat or providing your own hash function instead.
  ```

  So `Counter` picks `std.StringHashMapUnmanaged(usize)` for strings. `Map` is a comptime `const` holding a type, used by the field `map: Map = .empty`. `Counter(u8)` contains no string code and `Counter([]const u8)` no integer code.
- **The constraint check** runs first. `@typeInfo(K) != .int` is comptime-known (a builtin on a type), so it needs no `comptime` keyword.
- **`add`** uses `getOrPut`: one lookup that returns a pointer to the value slot whether or not the key existed. `found_existing` says whether the slot needs initializing. That's one hash lookup instead of a `get` plus a `put`.
- **`get`** returns `self.map.get(key) orelse 0`: an absent key has count zero.
- **`topN`** copies the entries into an `ArrayList`. `initCapacity` allocates exactly enough room once, so `appendAssumeCapacity` can't fail. `std.mem.sort` takes the element type, a context value (`{}`, unused here), and a "less than" function. `shrinkRetainingCapacity` cuts the list to `n` entries, and `toOwnedSlice` hands the memory to the caller. The `errdefer` frees the list if `toOwnedSlice` fails.
- **`entryLessThan`** sorts by count, highest first, and breaks ties by key. Hash map order is unpredictable; the tie-break makes the output the same on every run. Slices need `std.mem.lessThan`, since `<` doesn't compile for them. Because `is_string` is comptime-known, only the branch for the current `K` is compiled.
- **`Entry`** is declared inside the generic struct, so `Counter(u8).Entry` has `key: u8` and `Counter([]const u8).Entry` has `key: []const u8`.

`Counter` doesn't copy keys. That is fine for seek: the `Searcher` owns every path until the end, and stdin's name is a string literal. The doc comment says so, because a generic type can't enforce lifetimes for you.

`Stats` is a plain struct with a `Counter([]const u8)` field. `write` uses a multiline string literal as the format string; `{f}` formats the `Io.Duration`, and `{d:>6}` right-aligns counts in a 6-character column.

The two `test` blocks use `std.testing.allocator`, which fails the test on any leak. `expectEqual(3, counter.get('l'))` puts the expected value first. [Chapter 16](16-testing.md) covers testing in full.

### `src/cli.zig`

Add the option, between `color` and `help`:

```zig
    color: Color = .auto,
    stats: bool = false,
    help: bool = false,
```

and its description:

```zig
        .color = "highlight matches",
        .stats = "print statistics to stderr when done",
        .help = "show this help",
```

That's all: the parser and `--help` from Chapter 12 pick it up automatically.

### `src/search.zig`

Import `Stats` at the top:

```zig
const Options = @import("cli.zig").Options;
const Stats = @import("stats.zig").Stats;
```

Add a field to `Searcher`, after `stderr`:

```zig
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    stats: Stats = .{},
    matched_any: bool = false,
```

Free it first in `deinit`:

```zig
    pub fn deinit(self: *Searcher) void {
        self.stats.deinit(self.gpa);
        for (self.files.items) |path| self.gpa.free(path);
```

And record every searched file in `searchFile`, right after the binary check:

```zig
        // Binary files are skipped silently.
        const matches = result orelse return;
        if (matches > 0) self.matched_any = true;
        // `name` is either a path owned by the Searcher or a string
        // literal, so it lives as long as the stats.
        try self.stats.record(self.gpa, name, matches);
```

Binary files return before `record`, so they don't count as searched. With `-l`, a file's search stops at the first selected line, so each matching file counts one line.

### `src/main.zig`

Time the search and print the summary. Around the search loop in `run`:

```zig
    // The awake clock is monotonic: it never jumps when the system time is
    // adjusted, which makes it the right clock for measuring durations.
    const start = std.Io.Clock.awake.now(io);
    for (paths) |path| try searcher.addPath(path);
    try searcher.searchAll();

    if (options.stats) {
        try stdout.flush(); // results first, then the summary
        try searcher.stats.write(gpa, stderr, start.untilNow(io, .awake));
    }
```

Both writers are buffered. `main` flushes stdout before stderr when `run` returns, but a buffer also drains whenever it fills. Without the explicit `flush`, a long summary could reach the terminal before the last results.

### Checkpoint

The elapsed times will differ on your machine.

```console
$ zig build
$ ./zig-out/bin/seek --stats fox testdata
testdata/notes/log.txt:2024-01-01 saw a fox near the barn
testdata/notes/log.txt:2024-01-03 fox tracks in the snow
testdata/notes/todo.md:- feed the fox
testdata/poem.txt:The quick brown fox
--- stats ---
files searched: 3
files matched:  3
matching lines: 4
elapsed:        278.854us
top files:
     2  testdata/notes/log.txt
     1  testdata/notes/todo.md
     1  testdata/poem.txt
$ ./zig-out/bin/seek --stats -i -c fox testdata
testdata/notes/log.txt:2
testdata/notes/todo.md:1
testdata/poem.txt:3
--- stats ---
files searched: 3
files matched:  3
matching lines: 6
elapsed:        246.35us
top files:
     3  testdata/poem.txt
     2  testdata/notes/log.txt
     1  testdata/notes/todo.md
```

In the first run, `notes/todo.md` and `poem.txt` tie with one match; the name breaks the tie. With no matches there is no "top files" list, and the exit status is still 1:

```console
$ ./zig-out/bin/seek --stats zebra testdata; echo "exit $?"
--- stats ---
files searched: 3
files matched:  0
matching lines: 0
elapsed:        188.453us
exit 1
```

The summary is on stderr, so it can be thrown away separately:

```console
$ ./zig-out/bin/seek --stats fox testdata 2>/dev/null
testdata/notes/log.txt:2024-01-01 saw a fox near the barn
testdata/notes/log.txt:2024-01-03 fox tracks in the snow
testdata/notes/todo.md:- feed the fox
testdata/poem.txt:The quick brown fox
```

A path given twice is searched twice, adding to one `Counter` entry. The binary file isn't counted:

```console
$ ./zig-out/bin/seek --stats fox testdata/poem.txt testdata/poem.txt testdata/data.bin
testdata/poem.txt:The quick brown fox
testdata/poem.txt:The quick brown fox
--- stats ---
files searched: 2
files matched:  2
matching lines: 2
elapsed:        146.41us
top files:
     2  testdata/poem.txt
```

### Running the tests

`stats.zig` has seek's first `test` blocks. Run them with `zig test` on the file:

```console
$ zig test src/stats.zig
1/2 stats.test.Counter counts integers...OK
2/2 stats.test.Counter counts strings and breaks ties by key...OK
All 2 tests passed.
```

You might expect `zig build test` to run them too. It doesn't:

```console
$ zig build test --summary all
Build Summary: 3/3 steps succeeded
test success
+- run test success 3ms MaxRSS:4M
   +- compile test debug native success 311ms MaxRSS:154M
```

"success", but no test count: no tests ran. The test step's root file is `main.zig`. A test build only analyzes code that something in the build uses, and it doesn't use `main` (the test runner replaces it). `main.zig` has no tests, so nothing pulls in `search.zig` or `stats.zig`, and their tests are never seen. Until [Chapter 16](16-testing.md) explains the rule and fixes it with a small `test` block in `main.zig`, run `zig test src/stats.zig` by hand.

### The constraint at work

Create a scratch file `src/bad.zig` next to `stats.zig`:

```zig
const Counter = @import("stats.zig").Counter;

test {
    var c: Counter(f64) = .{};
    _ = &c;
}
```

```console
$ zig test src/bad.zig
stats.zig:18:9: error: Counter: keys must be integers or []const u8, not f64
        @compileError("Counter: keys must be integers or []const u8, not " ++ @typeName(K));
        ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
bad.zig:4:19: note: called at comptime here
    var c: Counter(f64) = .{};
           ~~~~~~~^~~~~
```

Hashing floats is a bad idea (`0.0` and `-0.0` are equal but have different bits, and `nan` isn't equal to itself), and the message says so before any hash map code runs. Delete `bad.zig` afterwards.

The complete project at this point is in `project/ch13/`.

## Summary

- A generic function takes `comptime T: type`. The compiler creates one copy per distinct type (monomorphization).
- `anytype` accepts any value whose type supports what the body does. The signature doesn't document it: state the needs in a doc comment or check them.
- A generic type is a function that returns a `type`, usually an anonymous `struct`. `@This()` names it from inside. The same arguments always give the same type.
- `std.ArrayList(T)` is ordinary Zig: `items` (a slice of the used part), `capacity`, and methods that grow the block.
- Check requirements at the top of a generic function with `@typeInfo`, `@hasDecl`, and `@compileError`. Write `comptime f(T)` when the check calls a function: comptime arguments alone don't make a call comptime.
- A comptime interface (required declarations with exact signatures) costs nothing at run time, but each instantiation is a distinct type.
- Type erasure (`*anyopaque` plus generated function pointers) lets different types share one run-time type. [Chapter 14](14-polymorphism.md) covers it.
- `Io.Clock.awake.now(io)` and `untilNow` measure durations; `{f}` prints an `Io.Duration`.
- seek has `--stats`, built on `Counter(K)`, which chooses its hash map at compile time.
- `zig build test` doesn't run `stats.zig`'s tests yet; use `zig test src/stats.zig` until [Chapter 16](16-testing.md).

## Exercises

1. **A generic pair.** Write `fn Pair(comptime A: type, comptime B: type) type` with fields `first: A` and `second: B`, and a method `swap` that returns a `Pair(B, A)`. Print a swapped pair, its type name, and whether swapping twice gives back the original type.

   <details><summary>Solution</summary>

   ```zig
   const std = @import("std");

   fn Pair(comptime A: type, comptime B: type) type {
       return struct {
           first: A,
           second: B,

           pub fn swap(self: @This()) Pair(B, A) {
               return .{ .first = self.second, .second = self.first };
           }
       };
   }

   pub fn main() void {
       const p: Pair(u8, []const u8) = .{ .first = 42, .second = "answer" };
       const q = p.swap();
       std.debug.print("{s} {d}\n", .{ q.first, q.second });
       std.debug.print("{s}\n", .{@typeName(@TypeOf(q))});
       std.debug.print("{}\n", .{@TypeOf(q.swap()) == @TypeOf(p)});
   }
   ```

   ```console
   $ zig run pair.zig
   answer 42
   pair.Pair([]const u8,u8)
   true
   ```

   `@This()` names the current instantiation; `Pair(B, A)` names another. Swapping twice gives `Pair(A, B)` again, and since comptime calls are cached, that is exactly `p`'s type.

   </details>

2. **A ring buffer.** Write `fn Ring(comptime T: type, comptime capacity: usize) type`: a fixed-size buffer that keeps the last `capacity` values pushed and overwrites the oldest. Give it `push`, `len`, and `get(i)` (the i-th oldest value still stored). It must not allocate. Make `Ring(u32, 0)` a compile error.

   <details><summary>Solution</summary>

   ```zig
   const std = @import("std");

   /// Keeps the last `capacity` values pushed; older ones are overwritten.
   fn Ring(comptime T: type, comptime capacity: usize) type {
       if (capacity == 0) @compileError("Ring: capacity must be at least 1");
       return struct {
           const Self = @This();

           buffer: [capacity]T = undefined,
           /// Total number of values ever pushed.
           pushed: usize = 0,

           pub fn push(self: *Self, value: T) void {
               self.buffer[self.pushed % capacity] = value;
               self.pushed += 1;
           }

           pub fn len(self: Self) usize {
               return @min(self.pushed, capacity);
           }

           /// The i-th oldest value still stored.
           pub fn get(self: Self, i: usize) T {
               std.debug.assert(i < self.len());
               const oldest = self.pushed - self.len();
               return self.buffer[(oldest + i) % capacity];
           }
       };
   }

   pub fn main() void {
       var last3: Ring(u32, 3) = .{};
       for (1..6) |n| last3.push(@intCast(n));
       for (0..last3.len()) |i| std.debug.print("{d} ", .{last3.get(i)});
       std.debug.print("\n@sizeOf(Ring(u32, 3)) = {d}\n", .{@sizeOf(Ring(u32, 3))});
   }
   ```

   ```console
   $ zig run ring.zig
   3 4 5 
   @sizeOf(Ring(u32, 3)) = 24
   ```

   `capacity` is a comptime parameter, so `buffer` can be an array and the whole ring lives inline: 3 × 4 bytes of buffer plus an 8-byte `usize`, padded for alignment. `Ring(u32, 0)` fails with `error: Ring: capacity must be at least 1`.

   </details>

3. **Enum keys.** Extend seek's `Counter` so that enum types work as keys, and add a test that counts `enum { red, green, blue }` values. Equal counts should be ordered by the enums' declaration order. (Hint: relax the check first and read the error you get.)

   <details><summary>Solution</summary>

   After relaxing only the check, the error points at the comparison:

   ```text
   stats.zig:70:81: error: operator < not allowed for type 'stats.test.Counter counts enum values.Color'
   ```

   `AutoHashMap` already hashes enums. Only the check and the tie-break need to change:

   ```zig
       const is_string = K == []const u8;
       const is_enum = @typeInfo(K) == .@"enum";
       if (!is_string and !is_enum and @typeInfo(K) != .int) {
           @compileError("Counter: keys must be integers, enums or []const u8, not " ++ @typeName(K));
       }
   ```

   ```zig
               return if (is_string)
                   std.mem.lessThan(u8, a.key, b.key)
               else if (is_enum)
                   @backingInt(a.key) < @backingInt(b.key)
               else
                   a.key < b.key;
   ```

   `@backingInt` returns an enum value's integer, which follows declaration order for an enum without explicit values. The test:

   ```zig
   test "Counter counts enum values" {
       const Color = enum { red, green, blue };
       const gpa = std.testing.allocator;
       var counter: Counter(Color) = .{};
       defer counter.deinit(gpa);

       for ([_]Color{ .blue, .red, .blue, .green }) |c| try counter.add(gpa, c, 1);
       try std.testing.expectEqual(2, counter.get(.blue));

       const top = try counter.topN(gpa, 3);
       defer gpa.free(top);
       try std.testing.expectEqual(.blue, top[0].key);
       try std.testing.expectEqual(.red, top[1].key); // ties: declaration order
       try std.testing.expectEqual(.green, top[2].key);
   }
   ```

   ```console
   $ zig test src/stats.zig
   1/3 stats.test.Counter counts integers...OK
   2/3 stats.test.Counter counts strings and breaks ties by key...OK
   3/3 stats.test.Counter counts enum values...OK
   All 3 tests passed.
   ```

   </details>

4. **Find the bug.** This program should print `5`. Instead it doesn't compile. Why, and what is the smallest fix?

   ```zig
   const std = @import("std");

   fn isSigned(comptime T: type) bool {
       return switch (@typeInfo(T)) {
           .int => |info| info.signedness == .signed,
           else => false,
       };
   }

   fn abs(x: anytype) @TypeOf(x) {
       if (!isSigned(@TypeOf(x))) @compileError("abs: needs a signed integer");
       return if (x < 0) -x else x;
   }

   pub fn main() void {
       std.debug.print("{d}\n", .{abs(@as(i32, -5))});
   }
   ```

   ```text
   abs.zig:11:32: error: abs: needs a signed integer
   ```

   <details><summary>Solution</summary>

   `isSigned(@TypeOf(x))` is a run-time call. Its argument is comptime-known, but nothing forces the call to happen at compile time, so it returns a run-time `bool`. An `if` with a run-time condition compiles both branches, and compiling `@compileError` fails for any type. The fix is one word:

   ```zig
       if (!comptime isSigned(@TypeOf(x))) @compileError("abs: needs a signed integer");
   ```

   Now `abs(@as(i32, -5))` prints `5`, and `abs(@as(u32, 5))` still fails with the message, as intended.

   </details>

5. **Top extensions.** Make `--stats` also print the file extensions with the most matching lines, using a second `Counter`. Files without an extension (including stdin) count as `(none)`. Use `std.fs.path.extension`.

   <details><summary>Solution</summary>

   In `src/stats.zig`, add a field and free it:

   ```zig
       matches_per_file: Counter([]const u8) = .{},
       matches_per_ext: Counter([]const u8) = .{},

       pub fn deinit(self: *Stats, gpa: Allocator) void {
           self.matches_per_file.deinit(gpa);
           self.matches_per_ext.deinit(gpa);
           self.* = undefined;
       }
   ```

   Count in `record`:

   ```zig
           try self.matches_per_file.add(gpa, path, matches);
           // The extension is a slice of `path`, so it lives just as long.
           const ext = std.fs.path.extension(path);
           try self.matches_per_ext.add(gpa, if (ext.len == 0) "(none)" else ext, matches);
   ```

   And print at the end of `write`:

   ```zig
           const top_ext = try self.matches_per_ext.topN(gpa, 5);
           defer gpa.free(top_ext);
           try w.writeAll("top extensions:\n");
           for (top_ext) |entry| try w.print("{d:>6}  {s}\n", .{ entry.count, entry.key });
   ```

   No new type is needed: it's the same `Counter([]const u8)` as the existing field. `std.fs.path.extension` returns a slice of its argument (including the dot), so the key needs no copying.

   ```console
   $ ./zig-out/bin/seek --stats -i fox testdata
   testdata/notes/log.txt:2024-01-01 saw a fox near the barn
   testdata/notes/log.txt:2024-01-03 fox tracks in the snow
   testdata/notes/todo.md:- feed the fox
   testdata/poem.txt:The quick brown fox
   testdata/poem.txt:A Fox is quick and clever;
   testdata/poem.txt:Foxes everywhere!
   --- stats ---
   files searched: 3
   files matched:  3
   matching lines: 6
   elapsed:        261.752us
   top files:
        3  testdata/poem.txt
        2  testdata/notes/log.txt
        1  testdata/notes/todo.md
   top extensions:
        5  .txt
        1  .md
   $ echo fox | ./zig-out/bin/seek --stats fox - 2>&1 | grep -v elapsed
   (standard input):fox
   --- stats ---
   files searched: 1
   files matched:  1
   matching lines: 1
   top files:
        1  (standard input)
   top extensions:
        1  (none)
   ```

   </details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-13--generic-programming)
