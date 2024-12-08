const r = @import("reader2.zig");
const a = @import("ast.zig");
const std = @import("std");
const testing = std.testing;

test "tokenization" {
    const reader = r.Tokenizer.init(testing.allocator, "132 2 ()  [] {} if fun");
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

// test "read program" {
//     const reader = try r.Reader.init(testing.allocator, "1");
//     switch (reader.read()) {
//         .success => |s| {
//             try testing.expectEqual(s.block.items[0].number.num, 1.0);
//         },
//         .failure => {
//             try testing.expect(false);
//         },
//     }
// }

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

// test "reading unary expressions" {
//     var reader = try r.Reader.init(testing.allocator, "-123");
//     defer reader.deinit();
//     const aa_result = reader.readUnary();
//     std.debug.print("{s}\n", .{aa_result.failure.message.?});
//     const aa = aa_result.success;
//     defer a.deinit(aa, testing.allocator);
//     try testing.expectEqualStrings(aa.unexp.op.symbol.lexeme, "-");
//     try testing.expectEqual(aa.unexp.value.number.num, 123);
// }
