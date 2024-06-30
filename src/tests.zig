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

test "reading symbols" {
    {
        var reader = r.Reader.init_load(std.testing.allocator, "hello");
        const val = try reader.read_symbol();
        defer reader.deinit(val);
        try expect(std.mem.eql(u8, val.symbol, "hello"));
        try expect(reader.it == 5);
        try expect(reader.at_eof());
    }
    {
        var reader = r.Reader.init_load(std.testing.allocator, "hello ");
        const val = try reader.read_symbol();
        defer reader.deinit(val);
        try expect(std.mem.eql(u8, val.symbol, "hello"));
        try expect(reader.it == 5);
        try expect(!reader.at_eof());
    }
}

test "reading boolean literals" {
    {
        var reader = r.Reader.init_load(std.testing.allocator, "true");
        const val = try reader.read_boolean();
        defer reader.deinit(val);
        try expect(val.is_boolean());
        try expect(val.is_true());
    }
    {
        var reader = r.Reader.init_load(std.testing.allocator, "false");
        const val = try reader.read_boolean();
        defer reader.deinit(val);
        try expect(val.is_boolean());
        try expect(val.is_false());
    }
}

test "reading string literals" {
    var reader = r.Reader.init_load(std.testing.allocator, "\"Hello, World!\"");
    const val = try reader.read_string();
    defer reader.deinit(val);
    try expect(std.mem.eql(u8, val.string, "Hello, World!"));
}

test "reading numbers" {
    var reader = r.Reader.init_load(std.testing.allocator, "123");
    const val = try reader.read_number();
    defer reader.deinit(val);
    try expect(val.number == 123.0);
}
