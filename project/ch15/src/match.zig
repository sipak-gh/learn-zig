//! Pattern matching: the line matchers behind PATTERN, and the wildcard
//! matcher shared by -W and --glob.

const std = @import("std");

/// Where a match was found in a line: `line[start..end]`.
pub const Span = struct {
    start: usize,
    end: usize,
};

/// The ways seek can match a line. A tagged union is a closed set: every
/// `switch` on it must handle every kind, and the compiler checks that.
pub const Matcher = union(enum) {
    /// The line contains the pattern.
    literal: []const u8,
    /// The line contains the pattern, ignoring ASCII case (-i).
    ignore_case: []const u8,
    /// The whole line matches a wildcard pattern (-W).
    wildcard: Wildcard,

    pub const Wildcard = struct {
        pattern: []const u8,
        ignore_case: bool,
    };

    /// Picks the matcher for the command-line options. The matcher refers
    /// to `pattern`, it doesn't copy it.
    pub fn init(pattern: []const u8, ignore_case: bool, wildcard: bool) Matcher {
        if (wildcard) return .{ .wildcard = .{ .pattern = pattern, .ignore_case = ignore_case } };
        if (ignore_case) return .{ .ignore_case = pattern };
        return .{ .literal = pattern };
    }

    /// Returns the first match in `line`, if any.
    pub fn find(matcher: Matcher, line: []const u8) ?Span {
        switch (matcher) {
            .literal => |needle| {
                const start = std.mem.find(u8, line, needle) orelse return null;
                return .{ .start = start, .end = start + needle.len };
            },
            .ignore_case => |needle| {
                const start = std.ascii.findIgnoreCase(line, needle) orelse return null;
                return .{ .start = start, .end = start + needle.len };
            },
            .wildcard => |w| {
                const matched = if (w.ignore_case)
                    wildcardMatchIgnoreCase(w.pattern, line)
                else
                    wildcardMatch(w.pattern, line);
                return if (matched) .{ .start = 0, .end = line.len } else null;
            },
        }
    }
};

/// Reports whether all of `text` matches the shell-style wildcard `pattern`:
/// `*` matches any run of bytes (even an empty one), `?` matches exactly one
/// byte, and every other byte matches itself.
pub fn wildcardMatch(pattern: []const u8, text: []const u8) bool {
    return matchWildcard(false, pattern, text);
}

/// Like `wildcardMatch`, but ignores ASCII case.
pub fn wildcardMatchIgnoreCase(pattern: []const u8, text: []const u8) bool {
    return matchWildcard(true, pattern, text);
}

/// The matcher behind both functions above. `ignore_case` is a comptime
/// parameter, so the compiler generates two specialized copies and the
/// check below costs nothing at run time.
///
/// It walks both slices once, remembering the most recent `*`. On a
/// mismatch it backtracks: that `*` swallows one more byte of `text` and
/// matching resumes right after it. That keeps the cost at
/// O(pattern.len * text.len) in the worst case.
fn matchWildcard(comptime ignore_case: bool, pattern: []const u8, text: []const u8) bool {
    var p: usize = 0; // position in pattern
    var t: usize = 0; // position in text
    var star: ?usize = null; // index of the last `*` seen in pattern
    var star_t: usize = 0; // where in text that `*` started matching

    while (t < text.len) {
        if (p < pattern.len and pattern[p] == '*') {
            // Look for `*` before comparing bytes, or a `*` in the pattern
            // would match a `*` in the text literally.
            star = p;
            star_t = t;
            p += 1; // first, let `*` match nothing
        } else if (p < pattern.len and (pattern[p] == '?' or eqlByte(ignore_case, pattern[p], text[t]))) {
            p += 1;
            t += 1;
        } else if (star) |s| {
            p = s + 1;
            star_t += 1; // let `*` match one more byte
            t = star_t;
        } else {
            return false;
        }
    }
    // Trailing `*`s match the empty rest of the text.
    while (p < pattern.len and pattern[p] == '*') p += 1;
    return p == pattern.len;
}

fn eqlByte(comptime ignore_case: bool, a: u8, b: u8) bool {
    return if (ignore_case) std.ascii.toLower(a) == std.ascii.toLower(b) else a == b;
}
