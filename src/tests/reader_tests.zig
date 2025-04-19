const std = @import("std");
const testing = std.testing;
const expect = testing.expect;

const reader = @import("../reader.zig");
const Reader = reader.Reader;

test "read binary expr" {
    var rdr = Reader.init(testing.allocator, "1 + 2");
}
