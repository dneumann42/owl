const r = @import("reader2.zig");
const std = @import("std");
const testing = std.testing;

test "tokenization" {
    const reader = r.Reader.init(testing.allocator, "132 2 ()  [] {} if fun");
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
