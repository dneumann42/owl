const std = @import("std");

pub const TokenKind = enum { number, keyword, openParen, closeParen, openBracket, closeBracket, openBrace, closeBrace };

pub const Token = struct {
    kind: TokenKind,
    start: usize,

    fn init(kind: TokenKind, start: usize) Token {
        return .{
            .kind = kind,
            .start = start,
        };
    }
};

pub const Reader = struct {
    code: []const u8,
    allocator: std.mem.Allocator,

    pub fn getKeywords() []const []const u8 {
        return comptime &.{ "if", "fun", "fn", "then", "else", "for", "do", "cond" };
    }

    pub fn getKeyword(slice: []const u8) ?[]const u8 {
        for (Reader.getKeywords()) |key| {
            if (std.mem.startsWith(u8, slice, key)) {
                return key;
            }
        }
        return null;
    }

    pub fn init(allocator: std.mem.Allocator, code: []const u8) Reader {
        return .{ .allocator = allocator, .code = code };
    }

    pub fn tokenize(self: Reader) !std.ArrayList(Token) {
        var tokens = std.ArrayList(Token).init(self.allocator);
        var index: usize = 0;

        const T = struct {
            fn skipWS(idx: *usize, c: []const u8) void {
                while (idx.* < c.len and std.ascii.isWhitespace(c[idx.*])) {
                    idx.* += 1;
                }
            }
        };

        while (index < self.code.len) {
            T.skipWS(&index, self.code);
            const start = index;
            if (self.readNumberLexeme(&index)) |_| {
                try tokens.append(.{ .kind = TokenKind.number, .start = start });
            } else if (self.readSpecialCharacter(&index)) |c| {
                const kind = switch (c[0]) {
                    '(' => TokenKind.openParen,
                    ')' => TokenKind.closeParen,
                    '[' => TokenKind.openBracket,
                    ']' => TokenKind.closeBracket,
                    '{' => TokenKind.openBrace,
                    '}' => TokenKind.closeBrace,
                    else => {
                        std.debug.panic("Not Implemented", .{});
                    },
                };
                try tokens.append(.{ .kind = kind, .start = start });
            } else if (self.readKeywordLexeme(&index)) |_| {
                try tokens.append(.{ .kind = TokenKind.keyword, .start = start });
            } else {
                std.debug.panic("Not Implemented", .{});
            }
        }

        return tokens;
    }

    pub fn readNumberLexeme(self: Reader, index: *usize) ?[]const u8 {
        if (!std.ascii.isDigit(self.code[index.*])) {
            return null;
        }
        const start = index.*;
        index.* += 1;
        while (index.* < self.code.len and std.ascii.isDigit(self.code[index.*])) {
            index.* += 1;
        }
        return self.code[start..index.*];
    }

    pub fn readSpecialCharacter(self: Reader, index: *usize) ?[]const u8 {
        if (index.* >= self.code.len) {
            return null;
        }
        if (Reader.validTokenCharacter(self.code[index.*])) {
            index.* += 1;
            return self.code[index.* - 1 .. index.*];
        }
        return null;
    }

    pub fn readKeywordLexeme(self: Reader, index: *usize) ?[]const u8 {
        if (Reader.getKeyword(self.code[index.*..])) |key| {
            const s = self.code[index.* .. index.* + key.len];
            index.* += s.len;
            return s;
        }
        return null;
    }

    pub fn getLexeme(self: Reader, t: Token) ?[]const u8 {
        var index = t.start;
        return switch (t.kind) {
            TokenKind.number => self.readNumberLexeme(&index),
            TokenKind.keyword => self.readKeywordLexeme(&index),
            else => self.readSpecialCharacter(&index),
        };
    }

    pub fn validTokenCharacter(ch: u8) bool {
        return switch (ch) {
            '(', ')', '{', '}', '[', ']' => true,
            else => false,
        };
    }

    pub fn validSymbolCharacter(ch: u8) bool {
        return switch (ch) {
            '+', '/', '*', '%', '$', '-', '>', '<', '=' => true,
            else => std.ascii.isAlphanumeric(ch),
        };
    }
};

pub fn convertEscapeSequences(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    var i: usize = 0;
    while (i < input.len) {
        if (i + 3 < input.len and
            input[i] == '\\' and
            input[i + 1] == 'x' and
            input[i + 2] == '1' and
            input[i + 3] == 'b')
        {
            try result.append(0x1B);
            i += 4;
        } else if (i + 1 < input.len and input[i] == '\\' and input[i + 1] == 'n') {
            try result.append(0x0A);
            i += 2;
        } else if (i + 1 < input.len and input[i] == '\\' and input[i + 1] == 't') {
            try result.append(0x09);
            i += 2;
        } else {
            try result.append(input[i]);
            i += 1;
        }
    }
    return result.toOwnedSlice();
}
