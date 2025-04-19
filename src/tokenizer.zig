const std = @import("std");

pub const TokenKind = enum { number, keyword, symbol, string, boolean, openParen, closeParen, openBracket, closeBracket, openBrace, closeBrace, comma, dot, colon };

pub const Token = struct {
    kind: TokenKind,
    start: usize,
    line: usize,

    fn init(kind: TokenKind, start: usize) Token {
        return .{
            .kind = kind,
            .start = start,
        };
    }
};

pub const Tokenizer = struct {
    code: []const u8,
    allocator: std.mem.Allocator,
    tokens: std.ArrayList(Token),
    tokenized: bool = false,

    pub fn getKeywords() []const []const u8 {
        return comptime &.{ "if", "fun", "fn", "while", "for", "then", "else", "end", "for", "do", "cond", "true", "false", "or", "and", "not" };
    }

    pub fn getKeyword(slice: []const u8) ?[]const u8 {
        for (Tokenizer.getKeywords()) |key| {
            if (std.mem.eql(u8, slice, key)) {
                return key;
            }
        }
        return null;
    }

    pub fn init(allocator: std.mem.Allocator, code: []const u8) Tokenizer {
        return .{ .allocator = allocator, .code = code, .tokens = std.ArrayList(Token).init(allocator) };
    }

    pub fn tokenize(self: *Tokenizer) error{OutOfMemory}!void {
        if (self.tokenized) {
            return;
        }
        defer {
            self.tokenized = true;
        }
        var index: usize = 0;
        var line: usize = 1;

        const T = struct {
            fn skipWS(idx: *usize, ln: *usize, c: []const u8) void {
                while (idx.* < c.len and std.ascii.isWhitespace(c[idx.*])) {
                    if (c[idx.*] == '\n') {
                        ln.* += 1;
                    }
                    idx.* += 1;
                }
                if (idx.* >= c.len) {
                    return;
                }
                if (c[idx.*] != ';') {
                    return;
                }
                idx.* += 1;
                while (idx.* < c.len and c[idx.*] != '\n') {
                    idx.* += 1;
                    if (idx.* < c.len and c[idx.*] == '\n') {
                        ln.* += 1;
                    }
                }
                skipWS(idx, ln, c);
            }
        };

        while (index < self.code.len) {
            T.skipWS(&index, &line, self.code);
            const start = index;
            if (index >= self.code.len) {
                break;
            }
            if (self.readNumberLexeme(&index)) |_| {
                try self.tokens.append(.{ .kind = TokenKind.number, .start = start, .line = line });
            } else if (self.readSpecialCharacter(&index)) |c| {
                const kind = switch (c[0]) {
                    '(' => TokenKind.openParen,
                    ')' => TokenKind.closeParen,
                    '[' => TokenKind.openBracket,
                    ']' => TokenKind.closeBracket,
                    '{' => TokenKind.openBrace,
                    '}' => TokenKind.closeBrace,
                    ',' => TokenKind.comma,
                    '.' => TokenKind.dot,
                    ':' => TokenKind.colon,
                    else => {
                        std.debug.panic("Not Implemented", .{});
                    },
                };
                try self.tokens.append(.{ .kind = kind, .start = start, .line = line });
            } else if (self.readKeywordLexeme(&index)) |_| {
                try self.tokens.append(.{ .kind = .keyword, .start = start, .line = line });
            } else if (self.readSymbolLexeme(&index)) |_| {
                try self.tokens.append(.{ .kind = .symbol, .start = start, .line = line });
            } else if (self.readStringLexeme(&index)) |_| {
                try self.tokens.append(.{ .kind = .string, .start = start, .line = line });
            } else {
                std.debug.panic("Not Implemented", .{});
            }
        }
    }

    pub fn readStringLexeme(self: Tokenizer, index: *usize) ?[]const u8 {
        if (self.code[index.*] != '"') {
            return null;
        }
        const start = index.*;
        index.* += 1;
        while (index.* < self.code.len and self.code[index.*] != '"') {
            index.* += 1;
        }
        if (index.* >= self.code.len) {
            std.log.err("Missing closing quote", .{});
            return null;
        }
        index.* += 1;
        return self.code[start..index.*];
    }

    pub fn readNumberLexeme(self: Tokenizer, index: *usize) ?[]const u8 {
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

    pub fn readNumber(self: Tokenizer, index: usize) ?f64 {
        if (!std.ascii.isDigit(self.code[index])) {
            return null;
        }
        const start = index;
        var it = index + 1;
        while (it < self.code.len and std.ascii.isDigit(self.code[it])) {
            it += 1;
        }
        const substr = self.code[start..it];
        const num = std.fmt.parseFloat(f64, substr) catch |err| {
            std.debug.print("Error parsing float: {}\n", .{err});
            return null;
        };
        return num;
    }

    pub fn readSpecialCharacter(self: Tokenizer, index: *usize) ?[]const u8 {
        if (index.* >= self.code.len) {
            return null;
        }
        if (Tokenizer.validTokenCharacter(self.code[index.*])) {
            index.* += 1;
            return self.code[index.* - 1 .. index.*];
        }
        return null;
    }

    pub fn readKeywordLexeme(self: Tokenizer, index: *usize) ?[]const u8 {
        var space_idx = index.*;
        while (space_idx < self.code.len) {
            const chr = self.code[space_idx];
            if (std.ascii.isWhitespace(chr) or !Tokenizer.validSymbolCharacter(chr)) {
                break;
            }
            space_idx += 1;
        }
        if (Tokenizer.getKeyword(self.code[index.*..space_idx])) |key| {
            const s = self.code[index.* .. index.* + key.len];
            index.* += s.len;
            return s;
        }
        return null;
    }

    pub fn readSymbolLexeme(self: Tokenizer, index: *usize) ?[]const u8 {
        if (index.* >= self.code.len) {
            return null;
        }
        const start = index.*;
        if (isUnaryCharacter(self.code[index.*])) {
            index.* += 1;
            return self.code[start..index.*];
        }
        while (index.* < self.code.len and Tokenizer.validSymbolCharacter(self.code[index.*])) {
            index.* += 1;
        }
        if (start == index.*) {
            return null;
        }
        return self.code[start..index.*];
    }

    pub fn getLexeme(self: Tokenizer, t: Token) ?[]const u8 {
        var index = t.start;
        return switch (t.kind) {
            .number => self.readNumberLexeme(&index),
            .symbol => self.readSymbolLexeme(&index),
            .keyword => self.readKeywordLexeme(&index),
            .string => self.readStringLexeme(&index),
            else => self.readSpecialCharacter(&index),
        };
    }

    pub fn isUnaryCharacter(ch: u8) bool {
        return switch (ch) {
            '-', '+' => true,
            else => false,
        };
    }

    pub fn validTokenCharacter(ch: u8) bool {
        return switch (ch) {
            '(', ')', '{', '}', '[', ']', ',', '.', ':' => true,
            else => false,
        };
    }

    pub fn validSymbolCharacter(ch: u8) bool {
        return switch (ch) {
            '+', '/', '*', '%', '$', '-', '>', '<', '=', '_', '?' => true,
            else => std.ascii.isAlphanumeric(ch),
        };
    }
};
