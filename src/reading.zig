const std = @import("std");

pub const ReaderError = error{InvalidToken};

pub const TokenType = enum {
    Terminator,
    Number,
    String,
    Symbol,
    Keyword,
    Operator,
};

pub const Token = struct {
    type: TokenType,
    index: usize,
};

pub const Reader = struct {
    allocator: std.mem.Allocator,
    index: usize,
    tokens: std.ArrayList(Token),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return Reader{ .index = 0, .allocator = allocator, .tokens = .{} };
    }

    pub fn deinit(self: *@This()) void {
        self.tokens.deinit(self.allocator);
    }

    pub fn tokenize(self: *@This(), code: []const u8) !void {
        var index: usize = 0;
        while (index < code.len) {
            while (index < code.len and std.ascii.isWhitespace(code[index]))
                index += 1;
            if (index >= code.len)
                break;
            var is_number = true;
            const start = index;
            while (index < code.len and !std.ascii.isWhitespace(code[index])) {
                if (!std.ascii.isDigit(code[index]))
                    is_number = false;
                index += 1;
            }
            if (start == index)
                return error.InvalidToken;
            try self.tokens.append(self.allocator, Token{ //
                .type = if (is_number) .Number else .Symbol,
                .index = start,
            });
        }
    }

    pub fn readLexeme(code: []const u8, tok: Token) []const u8 {
        var index = tok.index;
        while (index < code.len and !std.ascii.isWhitespace(code[index])) {
            index += 1;
        }
        return code[tok.index..index];
    }

    pub fn nextToken(self: *@This()) Token {
        if (self.index >= self.tokens.items.len) {
            return Token{ .type = .Terminator, .index = self.tokens.items.len };
        }
        return self.tokens.items[self.index];
    }

    pub fn peekToken(self: @This()) void {
        _ = self;
    }
};
