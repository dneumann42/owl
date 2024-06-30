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
        const res = reader.read_symbol();
        defer reader.deinit_result(res);
        const v = res.value_or_nothing();
        try expect(std.mem.eql(u8, v.symbol, "hello"));
        try expect(reader.it == 5);
        try expect(reader.at_eof());
    }
    {
        var reader = r.Reader.init_load(std.testing.allocator, "hello ");
        const res = reader.read_symbol();
        defer reader.deinit_result(res);
        const v = res.value_or_nothing();
        try expect(std.mem.eql(u8, v.symbol, "hello"));
        try expect(reader.it == 5);
        try expect(!reader.at_eof());
    }
}

test "reading boolean literals" {
    {
        var reader = r.Reader.init_load(std.testing.allocator, "true");
        const res = reader.read_boolean();
        defer reader.deinit_result(res);
        const b = res.value_or_nothing();
        try expect(b.is_boolean());
        try expect(b.is_true());
    }
    {
        var reader = r.Reader.init_load(std.testing.allocator, "false");
        const res = reader.read_boolean();
        defer reader.deinit_result(res);
        const b = res.value_or_nothing();
        try expect(b.is_boolean());
        try expect(b.is_false());
    }
}

test "reading string literals" {
    var reader = r.Reader.init_load(std.testing.allocator, "\"Hello, World!\"");
    const res = reader.read_string();
    defer reader.deinit_result(res);
    const s = res.value_or_nothing();
    try expect(std.mem.eql(u8, s.string, "Hello, World!"));
}
