const std = @import("std");
const reading = @import("reading.zig");
const allocator = std.testing.allocator;
const expect = std.testing.expect;
const expectEq = std.testing.expectEqual;

test "Can read symbols" {
    var reader = reading.Reader.init(allocator);
    defer reader.deinit();
    const src = "hello";
    try reader.tokenize(src);
    const n = reader.nextToken();
    try expectEq(reading.TokenType.Symbol, n.type);
    try expectEq(0, n.index);
    const lexeme = reading.Reader.readLexeme(src, n);
    try std.testing.expectEqualStrings("hello", lexeme);
}

test "Can skip whitespace" {
    var reader = reading.Reader.init(allocator);
    defer reader.deinit();
    const src = "  \t\r hello";
    try reader.tokenize(src);
    const n = reader.nextToken();
    try expectEq(reading.TokenType.Symbol, n.type);
    const lexeme = reading.Reader.readLexeme(src, n);
    try std.testing.expectEqualStrings("hello", lexeme);
}
