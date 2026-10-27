//! Byte-scanning helpers: a plain loop and a SIMD version of the same check.

const std = @import("std");
const testing = std.testing;

/// How many bytes one vector holds on the target CPU (for example 16 with
/// SSE2, 32 with AVX2), or null if the CPU has no suitable vector unit.
const vector_len = std.simd.suggestVectorLength(u8);

/// Reports whether `bytes` contains a zero byte, one byte at a time.
pub fn containsZeroScalar(bytes: []const u8) bool {
    for (bytes) |byte| {
        if (byte == 0) return true;
    }
    return false;
}

/// Reports whether `bytes` contains a zero byte, checking a whole vector of
/// bytes per step.
pub fn containsZero(bytes: []const u8) bool {
    const len = vector_len orelse return containsZeroScalar(bytes);
    const Chunk = @Vector(len, u8);
    const zeros: Chunk = @splat(0);

    var i: usize = 0;
    while (i + len <= bytes.len) : (i += len) {
        // A fixed-size array coerces to a vector of the same length.
        const chunk: Chunk = bytes[i..][0..len].*;
        // `==` compares lane by lane, giving a @Vector(len, bool);
        // @reduce(.Or, ...) asks "is any lane true?".
        if (@reduce(.Or, chunk == zeros)) return true;
    }
    // Fewer than `len` bytes are left over.
    return containsZeroScalar(bytes[i..]);
}

test containsZero {
    // Try every length up to a few vectors, with the zero at every position,
    // so the vector loop and the leftover tail both get checked.
    var buffer: [200]u8 = undefined;
    for (0..buffer.len) |len| {
        const bytes = buffer[0..len];
        @memset(bytes, 'a');
        try testing.expect(!containsZero(bytes));
        for (0..len) |zero_at| {
            bytes[zero_at] = 0;
            try testing.expect(containsZero(bytes));
            try testing.expectEqual(containsZeroScalar(bytes), containsZero(bytes));
            bytes[zero_at] = 'a';
        }
    }
}
