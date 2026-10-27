# Chapter 10 — Standard Library Containers

Slices have a fixed size. Real programs need collections that grow: files to search, word counts,
a job queue. Zig's standard library has them, and they follow the rule from
[Chapter 8](08-memory-and-allocators.md): no hidden allocations, so every call that might allocate
takes an allocator. This chapter covers `std.ArrayList`, hash maps, sorting, and a tour of priority
queues, deques, `MultiArrayList`, `StaticStringMap` and `BufSet`. Then `seek` keeps its own list of
files and gets `-c` (count), `-l` (list files) and `-m N` (stop after N lines).
[Chapter 9](09-strings-and-formatting.md) covered text; [Chapter 11](11-files-and-io.md) reads
files line by line and walks directories.

## `ArrayList`: a growable array

`std.ArrayList(T)` holds a slice of items plus spare room. When the room runs out, it allocates a
bigger block, copies the items, and frees the old one.

`examples/ch10/array_list.zig`

```zig
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    // An empty list owns no memory yet. Every call that may grow it takes
    // the allocator.
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa);

    try list.append(gpa, 10);
    try list.append(gpa, 20);
    try list.appendSlice(gpa, &.{ 30, 40, 50 });
    show("appended", list);

    // `items` is a plain slice of the elements: index it, loop over it.
    list.items[0] = 11;
    var sum: i32 = 0;
    for (list.items) |x| sum += x;
    std.debug.print("sum {d}, capacity {d}\n", .{ sum, list.capacity });

    try list.insert(gpa, 1, 15); // shifts the rest right
    show("insert(1, 15)", list);
    _ = list.orderedRemove(0); // shifts the rest left: O(n)
    show("orderedRemove(0)", list);
    _ = list.swapRemove(0); // moves the last item into the hole: O(1)
    show("swapRemove(0)", list);

    std.debug.print("pop: {?d}\n", .{list.pop()});
    std.debug.print("last: {?d}\n", .{list.last()});
    show("now", list);

    list.clearRetainingCapacity();
    std.debug.print("cleared: len {d}, capacity {d}\n", .{ list.items.len, list.capacity });
}

fn show(label: []const u8, list: std.ArrayList(i32)) void {
    std.debug.print("{s:<17} {any}\n", .{ label, list.items });
}
```

```console
$ zig run examples/ch10/array_list.zig
appended          { 10, 20, 30, 40, 50 }
sum 151, capacity 33
insert(1, 15)     { 11, 15, 20, 30, 40, 50 }
orderedRemove(0)  { 15, 20, 30, 40, 50 }
swapRemove(0)     { 50, 20, 30, 40 }
pop: 40
last: 30
now               { 50, 20, 30 }
cleared: len 0, capacity 33
```

- **Start with `.empty`, end with `deinit(gpa)`.** `.empty` is a declaration on the type (a decl
  literal, [Chapter 7](07-structs-enums-unions.md)) and costs nothing. Put `defer
  list.deinit(gpa)` right after it.
- **Pass the same allocator every time.** The list doesn't store it. Calls that can grow the list
  (`append`, `appendSlice`, `insert`, ...) take it and return an error union, so they need `try`.
  Calls that only shrink or read (`pop`, `orderedRemove`, `swapRemove`, `items`) don't.
- **`items` is the data**, an ordinary `[]i32`, so everything from
  [Chapter 6](06-arrays-slices-pointers.md) and [Chapter 9](09-strings-and-formatting.md) applies.
  The length is `items.len`; `capacity` is how many fit before the next allocation. The first
  `append` reserved room for 33, so most appends don't allocate.
- `pop` and `last` return optionals: `null` when the list is empty.

> **Zig 0.17:** `getLast()` and `getLastOrNull()` are deprecated. Use `last()`, which returns an
> optional, and `last().?` when you know the list isn't empty. `lastPtr()` gives a `?*T`.

### Why the allocator is a parameter

Up to Zig 0.14, `std.ArrayList` stored its allocator in a field ("managed"), and this chapter's
version was called `ArrayListUnmanaged`. In 0.15 the unmanaged one became the default. Not storing
the allocator makes the struct smaller, shows which calls can allocate, and lets a struct holding
several lists keep one allocator for all. The managed list still exists, deprecated, as
`std.array_list.Managed`. You'll see both styles online; this course uses the unmanaged style.

### Building a string, handing it over

`std.ArrayList(u8)` is Zig's string builder. It even has a `print` method:

`examples/ch10/builder.zig`

```zig
const std = @import("std");

/// Returns "1, 2, 3, ..., n". The caller owns the result.
fn numberList(gpa: std.mem.Allocator, n: usize) ![]u8 {
    // An ArrayList(u8) is a growable string.
    var out: std.ArrayList(u8) = .empty;
    // If anything fails, free what we built so far.
    errdefer out.deinit(gpa);

    for (1..n + 1) |i| {
        if (i > 1) try out.appendSlice(gpa, ", ");
        try out.print(gpa, "{d}", .{i});
    }
    // Hand the memory to the caller. The list is empty afterwards.
    return out.toOwnedSlice(gpa);
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    const text = try numberList(gpa, 12);
    defer gpa.free(text);
    std.debug.print("{s}\n", .{text});

    // If you know the size up front, allocate once.
    var squares: std.ArrayList(u64) = try .initCapacity(gpa, 5);
    defer squares.deinit(gpa);
    for (1..6) |i| squares.appendAssumeCapacity(i * i); // can't fail
    std.debug.print("{any} (capacity {d})\n", .{ squares.items, squares.capacity });
}
```

```console
$ zig run examples/ch10/builder.zig
1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
{ 1, 4, 9, 16, 25 } (capacity 5)
```

`toOwnedSlice` shrinks the memory to fit and returns a plain slice, which the caller frees with
`gpa.free`. That's the usual way to return "a list". Note `errdefer`, not `defer`: on success,
ownership moves to the caller, so we must not free.

`initCapacity` (or `ensureTotalCapacity` / `ensureUnusedCapacity` on an existing list) reserves room
in advance. Then the `*AssumeCapacity` methods can't fail and take no allocator. That saves
allocations and lets you do the fallible work first, then fill the list without error handling.

### Pointers into a list don't survive growth

When the list grows, its items move. Any pointer or slice into the old `items` now points at freed
memory: a dangling pointer, as in [Chapter 6](06-arrays-slices-pointers.md). 0.17 can catch this:
lock the list while you hold pointers, and any call that could move the items panics.

`examples/ch10/stale_pointer.zig`

```zig
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    var list: std.ArrayList(u32) = .empty;
    defer list.deinit(gpa);
    try list.append(gpa, 1);

    // A pointer into `items`...
    const first = &list.items[0];
    std.debug.print("before: {d}, capacity {d}\n", .{ first.*, list.capacity });

    // ...is only valid until the list grows. Lock it to catch mistakes.
    list.lockPointers();
    defer list.unlockPointers();
    for (0..100) |i| try list.append(gpa, @intCast(i));
    std.debug.print("after: {d}\n", .{first.*});
}
```

```console
$ zig run examples/ch10/stale_pointer.zig
before: 1, capacity 33
thread 306827 panic: reached unreachable code
…/lib/std/debug.zig:442:14: 0x1029e99 in assert (std.zig)
    if (!ok) unreachable; // assertion failure
             ^
…/lib/std/debug.zig:1896:15: 0x10437f7 in assertUnlocked (std.zig)
        assert(l.state == .unlocked);
              ^
…/lib/std/array_list.zig:1356:50: 0x11f5a2e in ensureTotalCapacityPrecise (std.zig)
            self.pointer_stability.assertUnlocked();
                                                 ^
…
…/examples/ch10/stale_pointer.zig:16:37: 0x11e892f in main (stale_pointer.zig)
    for (0..100) |i| try list.append(gpa, @intCast(i));
                                    ^
…
```

The first 32 appends fit the existing capacity. The 33rd must grow the list, and the lock turns
that into a panic with a trace pointing at the `append`. Without the lock, the program would read
freed memory, and might even print the right number by luck, which is why this bug is so hard to
find. The check runs only in Debug and ReleaseSafe builds.

The simple fix: don't keep pointers across appends. Store an **index** and look it up again with
`list.items[i]`.

## Hash maps

A hash map stores key/value pairs and finds a key in constant time on average. `std` has two
families, each with two kinds of key:

| | Any key type (`Auto`) | `[]const u8` keys (`String`) |
|---|---|---|
| Fast, no order | `std.AutoHashMapUnmanaged(K, V)` | `std.StringHashMapUnmanaged(V)` |
| Keeps insertion order | `std.array_hash_map.Auto(K, V)` | `std.array_hash_map.String(V)` |

All four start as `.empty`, take the allocator in calls that can allocate, and are freed with
`deinit(gpa)`.

### The basics

`examples/ch10/hash_map.zig`

```zig
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    // HTTP status code -> reason phrase.
    var reasons: std.AutoHashMapUnmanaged(u16, []const u8) = .empty;
    defer reasons.deinit(gpa);

    try reasons.put(gpa, 200, "OK");
    try reasons.put(gpa, 404, "Not Found");
    try reasons.put(gpa, 500, "Server Error");
    try reasons.put(gpa, 500, "Internal Server Error"); // replaces the value

    std.debug.print("count: {d}\n", .{reasons.count()});
    std.debug.print("404: {?s}\n", .{reasons.get(404)});
    std.debug.print("418: {?s}\n", .{reasons.get(418)});
    std.debug.print("contains 200: {}\n", .{reasons.contains(200)});

    // getPtr gives a pointer to the value, to change it in place.
    if (reasons.getPtr(200)) |reason| reason.* = "Fine";

    std.debug.print("removed 404: {}\n", .{reasons.remove(404)});

    // Iteration order is unspecified: don't rely on it.
    var it = reasons.iterator();
    while (it.next()) |entry| {
        std.debug.print("{d} => {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
}
```

```console
$ zig run examples/ch10/hash_map.zig
count: 3
404: Not Found
418: null
contains 200: true
removed 404: true
200 => Fine
500 => Internal Server Error
```

`get` returns `?V`, `getPtr` returns `?*V`, and `remove` returns whether the key was there. The
iterator returns entries with a `key_ptr` and a `value_ptr`. Don't add or remove entries while
iterating; that invalidates the iterator.

`Auto` builds hash and equality functions from the key type at compile time. It works for integers,
enums, pointers, and structs of those. It refuses slices, since it can't know whether you mean
"same address" or "same contents":

`examples/ch10/slice_key.zig`

```zig
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var map: std.AutoHashMapUnmanaged([]const u8, u32) = .empty;
    defer map.deinit(init.gpa);
    try map.put(init.gpa, "one", 1);
}
```

```console
$ zig run examples/ch10/slice_key.zig
…/lib/std/hash_map.zig:15:13: error: std.hash.autoHash does not allow slices here ([]const u8) because the intent is unclear. Consider using std.StringHashMap for hashing the contents of []const u8. Alternatively, consider using std.hash.autoHashStrat or providing your own hash function instead.
…
```

For string keys, use a `String` map, which hashes and compares bytes.

### `getOrPut`: one lookup instead of two

Counting is the classic hash map job. The naive way looks the key up twice (`get`, then `put`).
`getOrPut` does it once: it finds or creates the key's slot and tells you which happened.

`examples/ch10/word_count.zig`

```zig
const std = @import("std");

const text =
    \\the cat sat on the mat
    \\the dog sat on the cat
;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    // Word -> count. For []const u8 keys use a String hash map.
    var counts: std.StringHashMapUnmanaged(usize) = .empty;
    defer counts.deinit(gpa);

    var words = std.mem.tokenizeAny(u8, text, " \n");
    while (words.next()) |word| {
        // One lookup: find the slot for `word`, creating it if needed.
        const gop = try counts.getOrPut(gpa, word);
        if (!gop.found_existing) gop.value_ptr.* = 0;
        gop.value_ptr.* += 1;
    }

    // Copy the entries into a list so we can sort them.
    const Entry = struct { word: []const u8, n: usize };
    var entries: std.ArrayList(Entry) = .empty;
    defer entries.deinit(gpa);
    var it = counts.iterator();
    while (it.next()) |e| try entries.append(gpa, .{ .word = e.key_ptr.*, .n = e.value_ptr.* });

    // Most frequent first; ties in alphabetical order.
    std.mem.sort(Entry, entries.items, {}, struct {
        fn lessThan(_: void, a: Entry, b: Entry) bool {
            if (a.n != b.n) return a.n > b.n;
            return std.mem.lessThan(u8, a.word, b.word);
        }
    }.lessThan);

    for (entries.items) |e| std.debug.print("{s:<4} {d}\n", .{ e.word, e.n });
}
```

```console
$ zig run examples/ch10/word_count.zig
the  4
cat  2
on   2
sat  2
dog  1
mat  1
```

`getOrPut` returns a struct with `found_existing`, `key_ptr` and `value_ptr`. A new key's value is
`undefined`, so set it before use. `std.mem.sort` is covered below.

### Keys are not copied

A map stores the key you give it. For a string, that's a **slice** (pointer and length); the bytes
aren't copied. In `word_count.zig` that was fine: every word was a slice of `text`, which lives for
the whole program. But if the bytes behind a key change or are freed, the map is corrupted:

`examples/ch10/key_lifetime.zig`

```zig
const std = @import("std");

/// Pretends to read the next word into `buf`, like a reader would.
fn readWord(buf: []u8, word: []const u8) []u8 {
    @memcpy(buf[0..word.len], word);
    return buf[0..word.len];
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const input = [_][]const u8{ "red", "tan", "red", "fig" };
    var buf: [16]u8 = undefined;

    // Wrong: the map stores the slice, not the bytes. Every key points into
    // `buf`, which the next word overwrites.
    var bad: std.StringHashMapUnmanaged(void) = .empty;
    defer bad.deinit(gpa);
    for (input) |w| try bad.put(gpa, readWord(&buf, w), {});
    var bad_keys = bad.keyIterator();
    std.debug.print("bad: ", .{});
    while (bad_keys.next()) |k| std.debug.print("[{s}]", .{k.*});
    std.debug.print(" ({d} entries)\n", .{bad.count()});

    // Right: copy the key the first time we see it. The map owns the copies,
    // so free them before the map goes away.
    var good: std.StringHashMapUnmanaged(void) = .empty;
    defer {
        var keys = good.keyIterator();
        while (keys.next()) |k| gpa.free(k.*);
        good.deinit(gpa);
    }
    for (input) |w| {
        const gop = try good.getOrPut(gpa, readWord(&buf, w));
        if (!gop.found_existing) {
            // The new slot is already in the map. If dupe fails, take it out
            // again so `defer` never frees a key we didn't allocate.
            errdefer good.removeByPtr(gop.key_ptr);
            gop.key_ptr.* = try gpa.dupe(u8, gop.key_ptr.*);
        }
    }
    var good_keys = good.keyIterator();
    std.debug.print("good:", .{});
    while (good_keys.next()) |k| std.debug.print("[{s}]", .{k.*});
    std.debug.print(" ({d} entries)\n", .{good.count()});
}
```

```console
$ zig run examples/ch10/key_lifetime.zig
bad: [fig][fig] (2 entries)
good:[fig][red][tan] (3 entries)
```

The `bad` map has two keys that both read `fig` (same buffer), and a word is missing: when `fig`
arrived, a stored key already *looked like* `fig`. With `void` values a map is a set; the `good`
set has the three distinct words.

The rule: **a key must live at least as long as the map**. If it might not, `dupe` it on insert and
free all keys before `deinit`. The pattern above copies only new keys: `getOrPut` with the borrowed
slice, then replace `key_ptr.*` with a copy. That's allowed because an exact copy has the same
hash. The same rule applies to slice values and to anything in an `ArrayList`.

### Insertion order: array hash maps

`std.array_hash_map.Auto` and `String` store entries in arrays, in insertion order, plus an index
for lookups. Iterating is as fast as walking an array, and `keys()` and `values()` are plain
slices:

`examples/ch10/array_hash_map.zig`

```zig
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    // An array hash map remembers insertion order.
    var stock: std.array_hash_map.String(u32) = .empty;
    defer stock.deinit(gpa);

    try stock.put(gpa, "pears", 4);
    try stock.put(gpa, "apples", 7);
    try stock.put(gpa, "kiwis", 0);
    try stock.put(gpa, "plums", 12);

    // keys() and values() are plain slices, in insertion order.
    std.debug.print("{d} entries:\n", .{stock.count()});
    for (stock.keys(), stock.values()) |k, v| std.debug.print("  {s} = {d}\n", .{ k, v });

    // orderedRemove keeps the order (O(n)); swapRemove is O(1) but moves
    // the last entry into the gap.
    _ = stock.orderedRemove("apples");
    _ = stock.swapRemove("pears");
    std.debug.print("after removing: ", .{});
    for (stock.keys()) |k| std.debug.print("{s} ", .{k});
    std.debug.print("\n", .{});
}
```

```console
$ zig run examples/ch10/array_hash_map.zig
4 entries:
  pears = 4
  apples = 7
  kiwis = 0
  plums = 12
after removing: plums kiwis 
```

Use an array hash map when order matters (output that follows the input, JSON objects) or when you
iterate more than you look up. Its `sort` method reorders the entries.

> **Zig 0.17:** the array hash maps moved to `std.array_hash_map.Auto`, `String` and `Custom`.
> The old names (`std.AutoArrayHashMapUnmanaged`, `std.StringArrayHashMapUnmanaged`,
> `std.ArrayHashMapUnmanaged`) are deprecated aliases, and the managed array hash maps are gone.

### Managed maps

The plain hash maps still have managed versions: `std.AutoHashMap(K, V)` and `std.StringHashMap(V)`
store the allocator, so you pass it once to `init`:

`examples/ch10/managed.zig`

```zig
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    // A "managed" map stores the allocator, so calls don't take it.
    var ages: std.StringHashMap(u8) = .init(init.gpa);
    defer ages.deinit();

    try ages.put("ada", 36);
    try ages.put("linus", 54);
    std.debug.print("ada: {?d}, count: {d}\n", .{ ages.get("ada"), ages.count() });
}
```

```console
$ zig run examples/ch10/managed.zig
ada: 36, count: 2
```

That's a bit shorter in a small function. The unmanaged style is now the default across `std`, and
it's what you want for maps stored in structs.

## Sorting

`std.mem.sort(T, items, context, lessThan)` sorts a slice in place. `lessThan(context, a, b)`
returns true when `a` goes before `b`. `context` is passed to every call; use `{}` (the `void`
value) if you don't need one.

`examples/ch10/sorting.zig`

```zig
const std = @import("std");

const Player = struct { name: []const u8, score: u32 };

/// Sorts by score, highest first. The context (`void` here) is passed to
/// every comparison; this function doesn't need one.
fn byScoreDesc(_: void, a: Player, b: Player) bool {
    return a.score > b.score;
}

/// A context with data: sort indexes by the values they point at.
const ByValue = struct {
    values: []const f64,
    fn lessThan(ctx: ByValue, a: usize, b: usize) bool {
        return ctx.values[a] < ctx.values[b];
    }
};

pub fn main() void {
    var numbers = [_]i32{ 5, -2, 9, 0, 3 };
    std.mem.sort(i32, &numbers, {}, std.sort.asc(i32));
    std.debug.print("asc:  {any}\n", .{numbers});
    std.mem.sort(i32, &numbers, {}, std.sort.desc(i32));
    std.debug.print("desc: {any}\n", .{numbers});

    var names = [_][]const u8{ "pear", "Apple", "fig", "apple" };
    std.mem.sort([]const u8, &names, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b); // byte order: 'A' < 'a'
        }
    }.lessThan);
    std.debug.print("names:", .{});
    for (names) |n| std.debug.print(" {s}", .{n});
    std.debug.print("\n", .{});

    var players = [_]Player{
        .{ .name = "ann", .score = 70 },
        .{ .name = "bob", .score = 90 },
        .{ .name = "cy", .score = 70 },
        .{ .name = "di", .score = 85 },
    };
    // sort is stable: ann stays before cy.
    std.mem.sort(Player, &players, {}, byScoreDesc);
    for (players) |p| std.debug.print("{s}:{d} ", .{ p.name, p.score });
    std.debug.print("\n", .{});

    const prices = [_]f64{ 2.5, 0.5, 9.0, 1.25 };
    var order = [_]usize{ 0, 1, 2, 3 };
    std.mem.sortUnstable(usize, &order, ByValue{ .values = &prices }, ByValue.lessThan);
    std.debug.print("cheapest first: {any}\n", .{order});
}
```

```console
$ zig run examples/ch10/sorting.zig
asc:  { -2, 0, 3, 5, 9 }
desc: { 9, 5, 3, 0, -2 }
names: Apple apple fig pear
bob:90 di:85 ann:70 cy:70 
cheapest first: { 1, 3, 0, 2 }
```

- `std.sort.asc(T)` and `std.sort.desc(T)` make a `lessThan` for numbers.
- Zig has no closures or lambdas. For an inline comparison, declare a struct containing the
  function and take it: `struct { fn lessThan(...) bool {...} }.lessThan`.
- When the comparison needs data, put it in the context. `ByValue` carries the prices to sort
  indexes by price.
- `std.mem.sort` is **stable** (block sort, `std.sort.block`): equal items keep their order (ann
  before cy). `sortUnstable` uses pattern-defeating quicksort (`std.sort.pdq`, also callable
  directly); it's usually faster but doesn't keep that order.
- `std.mem.lessThan(u8, a, b)` compares strings byte by byte, so upper case sorts before lower
  case. For case-insensitive order, use `std.ascii.lessThanIgnoreCase`.

## More containers

`ArrayList` and the hash maps cover most needs. A few more are worth knowing.

### Priority queues and deques

`examples/ch10/queues.zig`

```zig
const std = @import("std");

const Job = struct { name: []const u8, priority: u8 };

/// Lower priority number = more urgent. Returning .lt means "a comes out first".
fn moreUrgent(_: void, a: Job, b: Job) std.math.Order {
    return std.math.order(a.priority, b.priority);
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    // PriorityQueue: pop always returns the most urgent item.
    var jobs: std.PriorityQueue(Job, void, moreUrgent) = .empty;
    defer jobs.deinit(gpa);
    try jobs.push(gpa, .{ .name = "backup", .priority = 3 });
    try jobs.push(gpa, .{ .name = "fire alarm", .priority = 0 });
    try jobs.push(gpa, .{ .name = "email", .priority = 2 });
    try jobs.push(gpa, .{ .name = "coffee", .priority = 1 });
    std.debug.print("next up: {s}\n", .{jobs.peek().?.name});
    while (jobs.pop()) |job| std.debug.print("  {d} {s}\n", .{ job.priority, job.name });

    // Deque: push and pop at both ends in O(1).
    var line: std.Deque(u32) = .empty;
    defer line.deinit(gpa);
    try line.pushBack(gpa, 1);
    try line.pushBack(gpa, 2);
    try line.pushFront(gpa, 0);
    try line.pushBack(gpa, 3);
    std.debug.print("front {?d}, back {?d}, len {d}\n", .{ line.front(), line.back(), line.len });
    std.debug.print("popFront {?d}, popBack {?d}\n", .{ line.popFront(), line.popBack() });
    var it = line.iterator();
    std.debug.print("left:", .{});
    while (it.next()) |x| std.debug.print(" {d}", .{x});
    std.debug.print("\n", .{});
}
```

```console
$ zig run examples/ch10/queues.zig
next up: fire alarm
  0 fire alarm
  1 coffee
  2 email
  3 backup
front 0, back 3, len 4
popFront 0, popBack 3
left: 1 2
```

`std.PriorityQueue(T, Context, compareFn)` is a binary heap. Its compare function returns a
`std.math.Order` (`.lt`, `.eq`, `.gt`), not a bool; `.lt` means "`a` comes out first". `push` and
`pop` are O(log n), `peek` O(1). The compare function is a comptime type parameter, so it's part
of the type and can be inlined.

`std.Deque(T)` is a ring buffer: a queue you can push and pop at both ends. Use it for
first-in-first-out work lists, such as directories still to visit in a breadth-first walk.

### `MultiArrayList`: one array per field

An `ArrayList(Monster)` stores whole structs one after another. A `MultiArrayList(Monster)` stores
each field in its own array:

`examples/ch10/multi_array_list.zig`

```zig
const std = @import("std");

const Monster = struct {
    hp: u32,
    x: f32,
    y: f32,
    name: []const u8,
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    // Stores each field in its own array: all hp values together, all x
    // values together, and so on.
    var monsters: std.MultiArrayList(Monster) = .empty;
    defer monsters.deinit(gpa);

    try monsters.append(gpa, .{ .hp = 10, .x = 0, .y = 0, .name = "slime" });
    try monsters.append(gpa, .{ .hp = 45, .x = 3, .y = 1, .name = "troll" });
    try monsters.append(gpa, .{ .hp = 7, .x = 8, .y = 2, .name = "bat" });

    // items(.hp) is a []u32 holding just that field. A loop over it touches
    // only the memory it needs.
    const hp = monsters.items(.hp);
    var total: u32 = 0;
    for (hp) |h| total += h;
    std.debug.print("{d} monsters, total hp {d}\n", .{ monsters.len, total });

    for (monsters.items(.x)) |*x| x.* += 1; // everyone moves right

    // get(i) puts a whole struct back together.
    const troll = monsters.get(1);
    std.debug.print("{s} at ({d}, {d})\n", .{ troll.name, troll.x, troll.y });
}
```

```console
$ zig run examples/ch10/multi_array_list.zig
3 monsters, total hp 62
troll at (4, 1)
```

This "struct of arrays" layout is a core idea of **data-oriented design**. A loop that reads only
`hp` loads only `hp` values into the CPU cache, not the names and positions beside them. It also
saves padding between fields of different sizes. The Zig compiler stores its syntax tree this way.
`ArrayList` is simpler for everyday code; use `MultiArrayList` for many items and loops that touch
a few fields.

### `StaticStringMap` and `BufSet`

`examples/ch10/lookup.zig`

```zig
const std = @import("std");

const Kind = enum { text, image, code };

/// Built at compile time: no allocation, nothing to free.
const by_extension: std.StaticStringMap(Kind) = .initComptime(.{
    .{ ".txt", .text },
    .{ ".md", .text },
    .{ ".png", .image },
    .{ ".jpg", .image },
    .{ ".zig", .code },
    .{ ".c", .code },
});

pub fn main(init: std.process.Init) !void {
    const files = [_][]const u8{ "notes.md", "logo.png", "main.zig", "data.bin", "notes.md" };

    // BufSet: a set of strings that copies (and later frees) each one.
    var seen: std.BufSet = .init(init.gpa);
    defer seen.deinit();

    for (files) |file| {
        if (seen.contains(file)) {
            std.debug.print("{s}: seen already\n", .{file});
            continue;
        }
        try seen.insert(file);
        const dot = std.mem.findScalarLast(u8, file, '.') orelse file.len;
        if (by_extension.get(file[dot..])) |kind| {
            std.debug.print("{s}: {t}\n", .{ file, kind });
        } else {
            std.debug.print("{s}: unknown\n", .{file});
        }
    }
    std.debug.print("{d} distinct files\n", .{seen.count()});
}
```

```console
$ zig run examples/ch10/lookup.zig
notes.md: text
logo.png: image
main.zig: code
data.bin: unknown
notes.md: seen already
4 distinct files
```

- `std.StaticStringMap(V).initComptime(.{ .{ key, value }, ... })` builds a lookup table **at
  compile time**, in the program's read-only data: nothing to allocate or free. Use it for
  keywords, command names, file extensions. `get` returns `?V`.
- `std.BufSet` is a set of strings that copies each inserted string and frees them all in
  `deinit`, so the key-lifetime problem goes away. It's managed (stores its allocator).
  `std.BufMap` does the same for string-to-string maps.

There's more: `std.EnumMap` and `std.EnumArray` (one slot per enum tag, no hashing), `std.bit_set`,
`std.SinglyLinkedList` and `std.DoublyLinkedList`. Browse `lib/std/` when you need something.

## Building seek: counting and listing

This chapter adds three `grep` options:

- `-c`: print only the number of selected lines per file (`path:count`);
- `-l`: print only the names of files with a selected line (`-l` wins over `-c`);
- `-m N`: stop each file after N selected lines.

Inside, the `Searcher` keeps its own list of files in an `ArrayList`. Only `src/main.zig` and
`src/search.zig` change. Start from your Chapter 9 project (or copy `project/ch09/`).

### The Searcher owns a list of paths

In `src/search.zig`, update the comment on `Searcher` and add a `files` field after `file_arena`:

```zig
/// Searches files for a pattern and remembers how it went.
///
/// Use it in two phases: `addPath` for every path to search, then
/// `searchAll`.
///
/// Memory: the Searcher owns a copy of the pattern and of every path
/// (allocated with `gpa`), plus an arena for file contents that is reset
/// after every file, so memory use stays flat no matter how many files we
/// search. Call `deinit` to free everything.
pub const Searcher = struct {
    gpa: Allocator,
    io: std.Io,
    pattern: []const u8,
    options: Options,
    /// Picked once in `init` according to -i.
    find: FindFn,
    file_arena: std.heap.ArenaAllocator,
    /// The files to search, in order. Each path is owned by the Searcher.
    files: std.ArrayList([]const u8) = .empty,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    matched_any: bool = false,
    had_error: bool = false,
```

The default `= .empty` means `init` doesn't need to change.

`deinit` must free each path, then the list itself:

```zig
    pub fn deinit(self: *Searcher) void {
        for (self.files.items) |path| self.gpa.free(path);
        self.files.deinit(self.gpa);
        self.file_arena.deinit();
        self.gpa.free(self.pattern);
        self.* = undefined; // catch use-after-deinit in safe builds
    }
```

Add `addPath` and `searchAll` after `deinit`, and rename `searchPath` to `searchFile`, now private
(no `pub`) because `main` goes through `searchAll`:

```zig
    /// Queues `path` for searching. The Searcher keeps its own copy.
    pub fn addPath(self: *Searcher, path: []const u8) Allocator.Error!void {
        const owned = try self.gpa.dupe(u8, path);
        // If append fails, nobody else will ever free `owned`.
        errdefer self.gpa.free(owned);
        try self.files.append(self.gpa, owned);
    }

    /// Searches every queued file, in order.
    pub fn searchAll(self: *Searcher) std.Io.Writer.Error!void {
        for (self.files.items) |path| try self.searchFile(path);
    }

    /// Searches one file. Problems are reported, not returned: a file we
    /// cannot read must not stop the whole search.
    fn searchFile(self: *Searcher, path: []const u8) std.Io.Writer.Error!void {
```

`addPath` is the **ownership hand-off** pattern from [Chapter 8](08-memory-and-allocators.md):

1. `dupe` makes a copy we own.
2. `errdefer` frees it if anything below fails, since nobody else knows about it yet.
3. Once `append` succeeds, the copy belongs to `files` and `deinit` frees it. The `errdefer`
   doesn't run, because the function returns normally.

Copying looks unnecessary now, since the paths come from `args`, which live until exit. But in
[Chapter 11](11-files-and-io.md), `seek` walks directories and builds paths in a temporary buffer.
Those *must* be copied, and since `addPath` already does, nothing else needs to change.

In `run` in `src/main.zig`, queue every path, then search:

```zig
            for (cmd.paths) |path| try searcher.addPath(path);
            try searcher.searchAll();
```

`addPath` can fail with `error.OutOfMemory`, which `run` already returns.

### `-c`, `-l` and `-m` in `searchText`

`searchText` now counts selected lines whether or not it prints them, and stops at a limit:

```zig
    /// Returns how many lines of `text` are selected, printing them unless
    /// -c or -l asked for a summary instead. A line is selected when it
    /// contains the pattern, or, with -v, when it doesn't. Stops early at the
    /// -m limit.
    fn searchText(self: *const Searcher, path: []const u8, text: []const u8) std.Io.Writer.Error!usize {
        // A trailing newline ends the last line; it doesn't start a new one.
        const body = if (std.mem.endsWith(u8, text, "\n")) text[0 .. text.len - 1] else text;

        // Inverted matches have nothing to highlight. `auto` behaves like
        // `never` until Chapter 19 teaches seek to detect a terminal.
        const highlight: ?Highlight = if (self.options.color == .always and !self.options.invert)
            .{ .pattern = self.pattern, .find = self.find }
        else
            null;

        // For -l, one selected line answers the question.
        const limit: usize = if (self.options.files_only) 1 else self.options.max_count orelse std.math.maxInt(usize);
        const print_lines = !self.options.count_only and !self.options.files_only;

        var matches: usize = 0;
        var lines = std.mem.splitScalar(u8, body, '\n');
        var line_number: usize = 1;
        while (matches < limit) : (line_number += 1) {
            const line = lines.next() orelse break;
            const found = self.find(line, self.pattern) != null;
            if (found == self.options.invert) continue;
            matches += 1;
            if (!print_lines) continue;
            const match: Match = .{
                .path = path,
                .line_number = if (self.options.line_numbers) line_number else null,
                .text = line,
                .highlight = highlight,
            };
            try self.stdout.print("{f}\n", .{match});
        }
        return matches;
    }
```

What changed:

- `limit` is the most lines we want. `-l` needs one: once a file has a selected line, its name is
  printed and the rest doesn't matter. Otherwise it's `-m N`, or with no `-m`, the largest `usize`
  (`std.math.maxInt(usize)`), meaning "no limit". `max_count` is a `?usize`, so `orelse` supplies
  that default.
- The loop condition is now `matches < limit`, and the line is fetched inside with
  `lines.next() orelse break`. The old `while (lines.next()) |line|` couldn't check the limit before
  reading.
- `matches += 1` moved before the `print_lines` check, so `-c` and `-l` count without printing.

### Printing the summary in `searchFile`

After `searchText` returns, `searchFile` prints the summary for `-l` or `-c`:

```zig
        const matches = try self.searchText(path, contents);
        if (matches > 0) self.matched_any = true;

        // -l wins over -c, like in grep.
        if (self.options.files_only) {
            if (matches > 0) try self.stdout.print("{s}\n", .{path});
        } else if (self.options.count_only) {
            try self.stdout.print("{s}:{d}\n", .{ path, matches });
        }
```

Like `grep`, `-c` prints a line for every file it could read, even with a count of 0.

### Parsing `-c`, `-l` and `-m N`

Back in `src/main.zig`, document the new options in `help`:

```zig
    \\  -n            show line numbers
    \\  -c            print only a count of selected lines per file
    \\  -l            print only the names of files with selected lines
    \\  -m N          stop after N selected lines per file
    \\  --color WHEN  highlight matches: auto, always, never
```

Two options now take a value, `-m` and `--color`. Instead of repeating the "move to the next
argument, complain if there isn't one" code, put it in a function. It must advance `parseArgs`'s
loop index, so it takes a **pointer** to it. Add it below `parseArgs`:

```zig
/// Returns the value that follows the flag at `args[i.*]` and advances `i`
/// past it. Takes a pointer so it can move the caller's loop index.
fn takeValue(args: []const [:0]const u8, i: *usize, stderr: *std.Io.Writer) (UsageError || std.Io.Writer.Error)![]const u8 {
    const flag = args[i.*];
    i.* += 1;
    return argAt(args, i.*) orelse {
        try stderr.print("seek: {s} needs a value\n", .{flag});
        return error.MissingValue;
    };
}
```

Then, in `parseArgs`, add the three flags and use `takeValue` for `--color` too:

```zig
        } else if (eql(arg, "-n")) {
            options.line_numbers = true;
        } else if (eql(arg, "-c")) {
            options.count_only = true;
        } else if (eql(arg, "-l")) {
            options.files_only = true;
        } else if (eql(arg, "-m")) {
            const value = try takeValue(args, &i, stderr);
            options.max_count = std.fmt.parseInt(usize, value, 10) catch {
                try stderr.print("seek: invalid value '{s}' for {s}\n", .{ value, arg });
                return error.InvalidValue;
            };
        } else if (eql(arg, "--color")) {
            const value = try takeValue(args, &i, stderr);
            // Turn "always" into Color.always; null if no tag has that name.
            options.color = std.meta.stringToEnum(Color, value) orelse {
                try stderr.print("seek: invalid value '{s}' for {s}\n", .{ value, arg });
                return error.InvalidValue;
            };
        } else {
```

`&i` passes the loop variable's address, so after `takeValue` does `i.* += 1`, the loop continues
past the value. `parseInt` into a `usize` rejects anything but a non-negative whole number,
including `-1` and `many`. Which error doesn't matter, so a bare `catch` (no `|err|`) is enough.

### Checkpoint

```console
$ zig build
$ ./zig-out/bin/seek -c fox testdata/poem.txt testdata/notes/todo.md testdata/notes/log.txt
testdata/poem.txt:1
testdata/notes/todo.md:1
testdata/notes/log.txt:2
$ ./zig-out/bin/seek -c -i fox testdata/poem.txt
testdata/poem.txt:3
$ ./zig-out/bin/seek -l fox testdata/poem.txt testdata/notes/todo.md testdata/notes/log.txt
testdata/poem.txt
testdata/notes/todo.md
testdata/notes/log.txt
$ ./zig-out/bin/seek -l -c dog testdata/poem.txt testdata/notes/todo.md testdata/notes/log.txt
testdata/poem.txt
testdata/notes/todo.md
$ ./zig-out/bin/seek -m 1 -n fox testdata/notes/log.txt
testdata/notes/log.txt:1:2024-01-01 saw a fox near the barn
```

`-l -c` printed names only: `-l` wins. `log.txt` has no dog, so it isn't listed.

`-m 0` selects nothing, so the exit status means "no match". Bad values are usage errors:

```console
$ ./zig-out/bin/seek -m 0 fox testdata/poem.txt
$ echo $?
1
$ ./zig-out/bin/seek -m many fox testdata/poem.txt
seek: invalid value 'many' for -m
usage: seek [OPTIONS] PATTERN [PATH ...]
$ echo $?
2
$ ./zig-out/bin/seek -m
seek: -m needs a value
usage: seek [OPTIONS] PATTERN [PATH ...]
```

With `-c`, files without matches still get a line. A missing file is still reported (after the
counts, since `reportError` flushes stdout first) and the exit status is 2:

```console
$ ./zig-out/bin/seek -c dog testdata/poem.txt testdata/notes/log.txt nope.txt
testdata/poem.txt:2
testdata/notes/log.txt:0
seek: nope.txt: FileNotFound
$ echo $?
2
```

No leak report appears, so every copied path was freed.

The complete project at this point is in `project/ch10/`.

## Summary

- `std.ArrayList(T)` starts as `.empty` and is freed with `deinit(gpa)`. Calls that can grow it
  take the allocator. `items` is a plain slice; `pop` and `last` return optionals.
- `toOwnedSlice` hands the memory to the caller; `initCapacity` plus `appendAssumeCapacity`
  allocates once. Growing moves the items, so don't keep pointers into a list you append to
  (`lockPointers` catches it).
- Hash maps: `AutoHashMapUnmanaged(K, V)` for most keys, `StringHashMapUnmanaged(V)` for strings,
  `std.array_hash_map.Auto`/`String` to keep insertion order. `put`, `get`, `getPtr`, `remove`,
  `iterator`, and `getOrPut` for "insert or update" with one lookup.
- Maps don't copy keys. A key must outlive the map; `dupe` it if it might not, and free the keys
  before `deinit`.
- `std.mem.sort` is stable and takes a context plus a `lessThan` function; `std.sort.asc`/`desc`
  cover numbers. Inline comparisons go in a `struct { fn ... }`.
- `PriorityQueue` (heap), `Deque` (ring buffer), `MultiArrayList` (one array per field),
  `StaticStringMap` (comptime lookup table), `BufSet` (set of owned strings).
- `seek` now keeps owned copies of its paths in an `ArrayList` and supports `-c`, `-l` and `-m N`.

## Exercises

1. Write `fn unique(gpa: std.mem.Allocator, words: []const []const u8) ![][]const u8` that returns
   the distinct words in the order they first appear. Use a hash map as a set and an `ArrayList` for
   the result. Test it with `std.testing.allocator`, including an empty input.

<details><summary>Solution</summary>

```zig
const std = @import("std");

/// Returns the distinct words in the order they first appear. The result
/// borrows the strings from `words`; the caller frees only the outer slice.
fn unique(gpa: std.mem.Allocator, words: []const []const u8) ![][]const u8 {
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer seen.deinit(gpa);
    var out: std.ArrayList([]const u8) = .empty;
    errdefer out.deinit(gpa);

    for (words) |w| {
        const gop = try seen.getOrPut(gpa, w);
        if (!gop.found_existing) try out.append(gpa, w);
    }
    return out.toOwnedSlice(gpa);
}

test unique {
    const gpa = std.testing.allocator;
    const result = try unique(gpa, &.{ "b", "a", "b", "c", "a" });
    defer gpa.free(result);
    try std.testing.expectEqual(3, result.len);
    try std.testing.expectEqualStrings("b", result[0]);
    try std.testing.expectEqualStrings("a", result[1]);
    try std.testing.expectEqualStrings("c", result[2]);

    const none = try unique(gpa, &.{});
    defer gpa.free(none);
    try std.testing.expectEqual(0, none.len);
}
```

```console
$ zig test unique.zig
1/1 unique.decltest.unique...OK
All 1 tests passed.
```

The set borrows its keys from `words`, which is fine: it's freed before `unique` returns. A
`std.array_hash_map.String(void)` alone would also work, since it keeps insertion order: return a
copy of its `keys()`.

</details>

2. Group the words of `"the quick brown fox jumps over the lazy dog"` by length: a map from length
   to an `ArrayList` of words. Print the groups sorted by length. Make sure every inner list is
   freed.

<details><summary>Solution</summary>

```zig
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const text = "the quick brown fox jumps over the lazy dog";

    // Word length -> the words with that length, in first-seen order.
    var groups: std.array_hash_map.Auto(usize, std.ArrayList([]const u8)) = .empty;
    defer {
        // Free the inner lists first, then the map.
        for (groups.values()) |*list| list.deinit(gpa);
        groups.deinit(gpa);
    }

    var words = std.mem.tokenizeScalar(u8, text, ' ');
    while (words.next()) |word| {
        const gop = try groups.getOrPut(gpa, word.len);
        if (!gop.found_existing) gop.value_ptr.* = .empty;
        try gop.value_ptr.append(gpa, word);
    }

    // Sort the map by key, then print.
    const Ctx = struct {
        keys: []const usize,
        pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
            return ctx.keys[a] < ctx.keys[b];
        }
    };
    groups.sort(Ctx{ .keys = groups.keys() });

    for (groups.keys(), groups.values()) |len, list| {
        std.debug.print("{d}:", .{len});
        for (list.items) |w| std.debug.print(" {s}", .{w});
        std.debug.print("\n", .{});
    }
}
```

```console
$ zig run by_length.zig
3: the fox the dog
4: over lazy
5: quick brown jumps
```

`gop.value_ptr.append(...)` works because `value_ptr` is a `*ArrayList`, and methods can be called
through a pointer. The `defer` loop uses `|*list|` because `deinit` needs a pointer. An array hash
map's `sort` passes two **indexes** to the context's `lessThan`, so the context carries the keys.

</details>

3. Write `fn topK(gpa, values: []const u32, k: usize) ![]u32` that returns the `k` largest values,
   largest first, without sorting the whole input. Hint: keep a `PriorityQueue` of at most `k` items
   whose smallest item comes out first.

<details><summary>Solution</summary>

```zig
const std = @import("std");

fn order(_: void, a: u32, b: u32) std.math.Order {
    return std.math.order(a, b);
}

/// Returns the `k` largest values, largest first. The caller owns the result.
fn topK(gpa: std.mem.Allocator, values: []const u32, k: usize) ![]u32 {
    // A min-heap of at most k items: its smallest is the one to beat.
    var heap: std.PriorityQueue(u32, void, order) = .empty;
    defer heap.deinit(gpa);
    for (values) |v| {
        if (heap.count() < k) {
            try heap.push(gpa, v);
        } else if (k > 0 and v > heap.peek().?) {
            _ = heap.pop();
            try heap.push(gpa, v);
        }
    }
    const out = try gpa.alloc(u32, heap.count());
    // Pops come out smallest first, so fill from the back.
    var i = out.len;
    while (heap.pop()) |v| {
        i -= 1;
        out[i] = v;
    }
    return out;
}

test topK {
    const gpa = std.testing.allocator;
    const top = try topK(gpa, &.{ 5, 1, 9, 3, 7, 9, 2 }, 3);
    defer gpa.free(top);
    try std.testing.expectEqualSlices(u32, &.{ 9, 9, 7 }, top);

    const none = try topK(gpa, &.{ 1, 2 }, 0);
    defer gpa.free(none);
    try std.testing.expectEqual(0, none.len);

    const all = try topK(gpa, &.{ 1, 2 }, 5);
    defer gpa.free(all);
    try std.testing.expectEqualSlices(u32, &.{ 2, 1 }, all);
}
```

```console
$ zig test top_k.zig
1/1 top_k.decltest.topK...OK
All 1 tests passed.
```

The heap never holds more than `k` items: O(n log k) time, O(k) memory. The `k > 0` check stops
`peek().?` from unwrapping `null` when `k` is 0.

</details>

4. **seek:** `seek fox poem.txt poem.txt` searches the file twice. Make `addPath` skip paths that are
   already queued, using a hash map so it stays fast with thousands of paths. Make sure nothing
   leaks.

<details><summary>Solution</summary>

Add a field to `Searcher`, after `files`:

```zig
    /// The paths in `files`, for spotting duplicates. The keys borrow the
    /// strings owned by `files`.
    seen: std.StringHashMapUnmanaged(void) = .empty,
```

Free it in `deinit` (the keys belong to `files`, so the map frees only itself):

```zig
        self.seen.deinit(self.gpa);
        for (self.files.items) |path| self.gpa.free(path);
```

And check it in `addPath`:

```zig
    pub fn addPath(self: *Searcher, path: []const u8) Allocator.Error!void {
        const gop = try self.seen.getOrPut(self.gpa, path);
        if (gop.found_existing) return; // already queued
        errdefer self.seen.removeByPtr(gop.key_ptr);

        const owned = try self.gpa.dupe(u8, path);
        // If append fails, nobody else will ever free `owned`.
        errdefer self.gpa.free(owned);
        try self.files.append(self.gpa, owned);
        // Point the key at our copy, which lives as long as the map.
        gop.key_ptr.* = owned;
    }
```

```console
$ ./zig-out/bin/seek -c fox testdata/poem.txt testdata/poem.txt testdata/notes/log.txt testdata/poem.txt
testdata/poem.txt:1
testdata/notes/log.txt:2
```

The map's key starts as the caller's `path` and switches to our copy at the end, once it's safely
in `files`. If `dupe` or `append` fails, the `errdefer`s undo both steps in reverse order, so the
map never holds a dead key. Paths are compared as strings, so `poem.txt` and `./poem.txt` still
differ.

</details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-10--standard-library-containers)
