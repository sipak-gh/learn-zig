const std = @import("std");

// A nested struct is a container, just like a file. Its tests are
// compiled only if something refers to the struct.
const Hidden = struct {
    test "inside Hidden" {}
};

pub const Public = struct {
    test "inside Public" {}
};

test "top level" {}

test {
    // References every *public* declaration of this file, so Public's
    // tests are found. Hidden is not public, so its test is not.
    std.testing.refAllDecls(@This());
}
