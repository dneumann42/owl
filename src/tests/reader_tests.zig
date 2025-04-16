const r = @import("../reader.zig");
const std = @import("std");
const testing = std.testing;
const expect = testing.expect;

test "Reader can skip whitespace" {
    var reader = r.Reader.init(testing.allocator);
    reader.load("  \n\t X");
    reader.skipWhitespace();
    try expect(reader.chr() == 'X');
}
