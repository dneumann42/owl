const r = @import("reader2.zig");
const a = @import("ast.zig");
const std = @import("std");
const testing = std.testing;

test "tokenization" {
    const reader = r.Tokenizer.init(testing.allocator,
        \\132 2 ()  [] {} if fun
        \\ "Hello"
    );
    const tokens = try reader.tokenize();
    defer tokens.deinit();
    try testing.expectEqual(tokens.items[0].kind, r.TokenKind.number);
    try testing.expectEqualStrings(reader.getLexeme(tokens.items[0]).?, "132");
    try testing.expectEqual(tokens.items[0].kind, r.TokenKind.number);
    try testing.expectEqual(tokens.items[1].kind, r.TokenKind.number);
    try testing.expectEqual(tokens.items[2].kind, r.TokenKind.openParen);
    try testing.expectEqual(tokens.items[3].kind, r.TokenKind.closeParen);
    try testing.expectEqual(tokens.items[4].kind, r.TokenKind.openBracket);
    try testing.expectEqual(tokens.items[5].kind, r.TokenKind.closeBracket);
    try testing.expectEqual(tokens.items[6].kind, r.TokenKind.openBrace);
    try testing.expectEqual(tokens.items[7].kind, r.TokenKind.closeBrace);
    try testing.expectEqual(tokens.items[8].kind, r.TokenKind.keyword);
    try testing.expectEqualStrings(reader.getLexeme(tokens.items[8]).?, "if");
    try testing.expectEqual(tokens.items[9].kind, r.TokenKind.keyword);
    try testing.expectEqualStrings(reader.getLexeme(tokens.items[9]).?, "fun");
    try testing.expectEqual(tokens.items[10].kind, r.TokenKind.string);
    try testing.expectEqualStrings(reader.getLexeme(tokens.items[10]).?,
        \\"Hello"
    );
}

test "comments and whitespace" {
    const reader = r.Tokenizer.init(testing.allocator,
        \\1 ;; hello
        \\(
    );
    const tokens = try reader.tokenize();
    defer tokens.deinit();
    try testing.expectEqual(tokens.items[0].kind, r.TokenKind.number);
    try testing.expectEqual(tokens.items[1].kind, r.TokenKind.openParen);
}

test "reading programs" {
    var reader = try r.Reader.init(testing.allocator, "1");
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);
    try testing.expectEqual(program.block.items[0].number.num, 1.0);
}

test "reading number literals" {
    var reader = try r.Reader.init(testing.allocator, "31415926 1 2 3");
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);
    try testing.expectEqual(program.block.items[0].number.num, 31415926);
    try testing.expectEqual(program.block.items[1].number.num, 1);
    try testing.expectEqual(program.block.items[2].number.num, 2);
    try testing.expectEqual(program.block.items[3].number.num, 3);
}

test "reading boolean literals" {
    var reader = try r.Reader.init(testing.allocator, "true false");
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);
    try testing.expectEqual(program.block.items[0].boolean, true);
    try testing.expectEqual(program.block.items[1].boolean, false);
}

test "reading string literals" {
    var reader = try r.Reader.init(testing.allocator,
        \\"Hello, World!" ""
    );
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);
    try testing.expectEqualStrings(program.block.items[0].string, "Hello, World!");
    try testing.expectEqualStrings(program.block.items[1].string, "");
}

test "reading unary operators" {
    var reader = try r.Reader.init(testing.allocator, "not - x");
    defer reader.deinit();
    const aa = reader.readUnaryOperator().success;
    defer a.deinit(aa, testing.allocator);
    const ab = reader.readUnaryOperator().success;
    defer a.deinit(ab, testing.allocator);
    switch (reader.readUnaryOperator()) {
        .success => {
            try testing.expect(false);
        },
        .failure => {},
    }
}

test "reading unary expressions" {
    var reader = try r.Reader.init(testing.allocator, "-123");
    defer reader.deinit();
    const aa_result = reader.readUnary();
    const aa = aa_result.success;
    defer a.deinit(aa, testing.allocator);
    try testing.expectEqualStrings(aa.unexp.op.symbol.lexeme, "-");
    try testing.expectEqual(aa.unexp.value.number.num, 123);
}
