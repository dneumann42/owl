const std = @import("std");
const ast = @import("ast.zig");

pub const TokenKind = enum { number, keyword, symbol, openParen, closeParen, openBracket, closeBracket, openBrace, closeBrace };

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

pub const ReaderErrorKind = error{ NoMatch, MissingClosingParen, Error };
pub const ReaderError = struct {
    kind: ReaderErrorKind,
    start: usize,
    message: ?[]const u8,
};

fn Result(comptime T: type) type {
    return union(enum) {
        success: T,
        failure: ReaderError,
        pub fn err(kind: ReaderErrorKind, start: usize) @This() {
            return .{
                .failure = .{ .kind = kind, .start = start, .message = null },
            };
        }
        pub fn errMsg(kind: ReaderErrorKind, start: usize, message: []const u8) @This() {
            return .{
                .failure = .{ .kind = kind, .start = start, .message = message },
            };
        }
        pub fn ok(value: T) @This() {
            return .{ .success = value };
        }
    };
}

const R = Result(*ast.Ast);

pub const Tokenizer = struct {
    code: []const u8,
    allocator: std.mem.Allocator,

    pub fn getKeywords() []const []const u8 {
        return comptime &.{ "if", "fun", "fn", "then", "else", "for", "do", "cond" };
    }

    pub fn getKeyword(slice: []const u8) ?[]const u8 {
        for (Tokenizer.getKeywords()) |key| {
            if (std.mem.startsWith(u8, slice, key)) {
                return key;
            }
        }
        return null;
    }

    pub fn init(allocator: std.mem.Allocator, code: []const u8) Tokenizer {
        return .{ .allocator = allocator, .code = code };
    }

    pub fn tokenize(self: Tokenizer) !std.ArrayList(Token) {
        var tokens = std.ArrayList(Token).init(self.allocator);
        var index: usize = 0;

        const T = struct {
            fn skipWS(idx: *usize, c: []const u8) void {
                while (idx.* < c.len and std.ascii.isWhitespace(c[idx.*])) {
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
                }
                skipWS(idx, c);
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
            } else if (self.readSymbolLexeme(&index)) |_| {
                try tokens.append(.{ .kind = TokenKind.symbol, .start = start });
            } else {
                std.debug.panic("Not Implemented", .{});
            }
        }

        return tokens;
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
        if (Tokenizer.getKeyword(self.code[index.*..])) |key| {
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
            TokenKind.number => self.readNumberLexeme(&index),
            TokenKind.keyword => self.readKeywordLexeme(&index),
            TokenKind.symbol => self.readSymbolLexeme(&index),
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

pub const Reader = struct {
    index: usize,
    tokens: std.ArrayList(Token),
    tokenizer: Tokenizer,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, code: []const u8) !Reader {
        const tokenizer = Tokenizer.init(allocator, code);
        return .{
            .index = 0,
            .tokens = try tokenizer.tokenize(),
            .tokenizer = tokenizer,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Reader) void {
        self.tokens.deinit();
    }

    pub fn read(self: Reader) R {
        return self.readProgram();
    }

    fn readProgram(self: Reader) R {
        const nodes = std.ArrayList(*ast.Ast).init(self.allocator);
        const block = ast.block(self.allocator, nodes) catch {
            return R.errMsg(ReaderErrorKind.Error, 0, "Failed to allocate block");
        };
        return R.ok(block);
    }

    fn readExpression(self: Reader) R {
        return self.readBinaryLogicalOr();
    }

    fn readBinaryExpression(
        self: Reader,
        operators: []const []const u8,
        left_parse: fn (self: *Reader) R,
        right_parse: fn (self: *Reader) R,
    ) R {
        var pin = self.index;
        const left = switch (left_parse(self)) {
            .success => |v| v,
            .failure => |e| {
                self.index = pin;
                return e;
            },
        };

        pin = self.it;
        const symbol = self.readSymbol(false) catch {
            self.it = pin;
            return left;
        };

        var operator_match = false;
        for (operators) |operator| {
            if (std.mem.eql(u8, symbol.symbol, operator)) {
                operator_match = true;
                break;
            }
        }

        if (!operator_match) {
            self.it = pin;
            return left;
        }

        const right = switch (right_parse(self)) {
            .success => |v| v,
            .failure => |e| {
                self.it = pin;
                return e;
            },
        };

        return ast.binexp(self.allocator, left, right);
    }

    fn readBinaryLogicalOr(self: Reader) R {
        return self.readBinaryExpression([_][]const u8{"or"}, Reader.readBinaryLogicalAnd, Reader.readBinaryLogicalOr);
    }

    fn readBinaryLogicalAnd(self: *Reader) R {
        return self.readBinaryExpression([_][]const u8{"and"}, Reader.readEquality, Reader.readBinaryLogicalAnd);
    }

    fn readEquality(self: *Reader) R {
        return self.readBinaryExpression(&[_][]const u8{ "eql", "noteql" }, Reader.readComparison, Reader.readEquality);
    }

    fn readComparison(self: *Reader) R {
        return self.readBinaryExpression(&[_][]const u8{ "<", ">", "<=", ">=" }, self.readAdd, self.readComparison);
    }

    fn readAdd(self: *Reader) R {
        return self.readBinaryExpression(&[_][]const u8{ "+", "-" }, Reader.readMultiply, Reader.readAdd);
    }

    fn readMultiply(self: *Reader) R {
        return self.readBinaryExpression(&[_][]const u8{ "*", "/" }, Reader.readUnary, Reader.readMultiply);
    }

    pub fn readUnary(self: *Reader) R {
        const start = self.index;
        const op = switch (self.readUnaryOperator()) {
            .failure => {
                self.index = start;
                return self.readPrimary();
            },
            .success => |s| s,
        };
        const primary = switch (self.readPrimary()) {
            .failure => {
                self.index = start;
                return R.err(ReaderErrorKind.NoMatch);
            },
            .success => |p| p,
        };
        return ast.unexp(self.allocator, op, primary);
    }

    pub fn tokenMatches(self: *Reader, match: []const u8) ?usize {
        if (self.index >= self.tokens.items.len) {
            return false;
        }
        const token = self.tokens.items[self.index];
        const lexeme = self.tokenizer.getLexeme(token) orelse {
            return false;
        };
        return switch (std.mem.eql(u8, lexeme, match)) {
            true => token.start,
            false => null,
        };
    }

    pub fn readUnaryOperator(self: *Reader) R {
        if (self.index >= self.tokens.items.len) {
            return R.err(ReaderErrorKind.NoMatch, 0);
        }
        const token = self.tokens.items[self.index];
        const lexeme = self.tokenizer.getLexeme(token) orelse {
            return R.err(ReaderErrorKind.NoMatch, 0);
        };
        if (std.mem.eql(u8, lexeme, "-") //
        or std.mem.eql(u8, lexeme, "~") //
        or std.mem.eql(u8, lexeme, "'") //
        or std.mem.eql(u8, lexeme, "not")) {
            self.index += 1;
            const new_sym = ast.sym(self.allocator, lexeme) catch {
                return R.errMsg(ReaderErrorKind.Error, token.start, "Failed to allocate symbol.");
            };
            return R.ok(new_sym);
        }
        return R.err(ReaderErrorKind.NoMatch, 0);
    }

    pub fn readPrimary(self: *Reader) R {
        switch (self.readDefinition()) {
            .success => |v| {
                return v;
            },
            .failure => {},
        }

        switch (self.readAssignment()) {
            .success => |v| {
                return v;
            },
            .failure => {},
        }

        switch (self.readDotCall()) {
            .success => |v| {
                return v;
            },
            .failure => {},
        }

        if (self.index >= self.tokens.items.len) {
            return R.err(ReaderErrorKind.NoMatch, 0);
        }

        // Nested expressions
        if (self.tokenMatches("(")) |start| {
            self.index += 1;
            const exp = switch (self.readExpression()) {
                .success => |v| v,
                .failure => |e| {
                    return e;
                },
            };
            if (!self.tokenMatches(")")) {
                return R.errMsg(ReaderErrorKind.MissingClosingParen, start, "Missing closing parenthesis");
            }
            return R.ok(exp);
        }

        return R.err(ReaderErrorKind.NoMatch, 0);
    }

    pub fn readDefinition(self: *Reader) R {
        _ = self;
        std.debug.panic("Not Implemented", .{});
    }

    pub fn readAssignment(self: *Reader) R {
        _ = self;
        std.debug.panic("Not Implemented", .{});
    }

    pub fn readDotCall(self: *Reader) R {
        _ = self;
        std.debug.panic("Not Implemented", .{});
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
