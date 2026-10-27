//! Pattern matching helpers.

/// Reports whether all of `text` matches the shell-style wildcard `pattern`:
/// `*` matches any run of bytes (even an empty one), `?` matches exactly one
/// byte, and every other byte matches itself.
///
/// It walks both slices once, remembering the most recent `*`. On a
/// mismatch it backtracks: that `*` swallows one more byte of `text` and
/// matching resumes right after it. That keeps the cost at
/// O(pattern.len * text.len) in the worst case.
pub fn wildcardMatch(pattern: []const u8, text: []const u8) bool {
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
        } else if (p < pattern.len and (pattern[p] == '?' or pattern[p] == text[t])) {
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
