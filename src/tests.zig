const std = @import("std");
const r = @import("reader.zig");
const expect = std.testing.expect;

test "skipping whitespace" {
    {
        var reader = r.Reader.init_load(std.testing.allocator, "  \n\t X ");
        reader.skip_whitespace();
        try expect(reader.chr() == 'X');
    }
    {
        var reader = r.Reader.init_load(std.testing.allocator, "  \n\t ");
        reader.skip_whitespace();
        try expect(reader.at_eof());
    }
}
