const std = @import("std");

const ast = @import("ast.zig");

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

pub const ReaderErrorKind = error{ NoMatch, MissingClosingParen, MissingClosingBracket, MissingComma, MissingEnd, DotMissingParameter, InvalidFunctionDefinition, InvalidLambda, InvalidIf, InvalidCond, InvalidDictionary, InvalidFor, InvalidUse, Error };

pub const ReaderError = struct {
    kind: ReaderErrorKind,
    start: usize,
    message: ?[]const u8,
};

fn Result(comptime T: type) type {
    return union(enum) {
        ok: T,
        err: ReaderError,

        pub fn noMatch(msg: []const u8) @This() {
            return .{ .err = .{ .kind = ReaderErrorKind.NoMatch, .start = 0, .message = msg } };
        }

        pub fn e(kind: ReaderErrorKind, start: usize) @This() {
            return .{
                .err = .{ .kind = kind, .start = start, .message = null },
            };
        }

        pub fn errMsg(kind: ReaderErrorKind, start: usize, message: []const u8) @This() {
            return .{
                .err = .{ .kind = kind, .start = start, .message = message },
            };
        }

        pub fn fromErr(er: ReaderError) @This() {
            return .{ .err = er };
        }

        pub fn o(value: T) @This() {
            return .{ .ok = value };
        }
    };
}

const R = Result(*ast.Ast);

pub fn getErrorMessage(err: ReaderError) []const u8 {
    return switch (err.kind) {
        error.NoMatch => "No Match",
        error.MissingClosingParen => "Missing closing parenthesis",
        error.MissingClosingBracket => "Missing closing bracket",
        error.MissingComma => "Missing comma",
        error.MissingEnd => "Missing end",
        error.DotMissingParameter => "Dot is missing parameter",
        error.InvalidFunctionDefinition => "Invalid function definition",
        error.InvalidLambda => "Invalid lambda",
        error.InvalidIf => "Invalid if",
        error.InvalidCond => "Invalid cond",
        error.InvalidDictionary => "Invalid dictionary",
        error.InvalidFor => "Invalid for",
        error.InvalidUse => "Invalid use",
        error.Error => "Error",
    };
}

pub const Tokenizer = struct {
    code: []const u8,
    allocator: std.mem.Allocator,

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
        return .{ .allocator = allocator, .code = code };
    }

    pub fn tokenize(self: Tokenizer) !std.ArrayList(Token) {
        var tokens = std.ArrayList(Token).init(self.allocator);
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
                try tokens.append(.{ .kind = TokenKind.number, .start = start, .line = line });
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
                try tokens.append(.{ .kind = kind, .start = start, .line = line });
            } else if (self.readKeywordLexeme(&index)) |_| {
                try tokens.append(.{ .kind = .keyword, .start = start, .line = line });
            } else if (self.readSymbolLexeme(&index)) |_| {
                try tokens.append(.{ .kind = .symbol, .start = start, .line = line });
            } else if (self.readStringLexeme(&index)) |_| {
                try tokens.append(.{ .kind = .string, .start = start, .line = line });
            } else {
                std.debug.panic("Not Implemented", .{});
            }
        }

        return tokens;
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

pub const Reader = struct {
    index: usize,
    tokens: std.ArrayList(Token),
    tokenizer: Tokenizer,
    allocator: std.mem.Allocator,

    // reader cleans up allocated
    symbols: std.ArrayList([]const u8),

    // does not own
    code: []const u8,

    pub fn init(allocator: std.mem.Allocator, code: []const u8) !Reader {
        const tokenizer = Tokenizer.init(allocator, code);
        return .{
            .index = 0,
            .tokens = try tokenizer.tokenize(),
            .tokenizer = tokenizer,
            .allocator = allocator,
            .symbols = std.ArrayList([]const u8).init(allocator),
            .code = code,
        };
    }

    pub fn getToken(self: Reader) Token {
        return self.tokens.items[self.index];
    }

    pub fn charIndex(self: Reader) usize {
        if (self.index >= self.tokens.items.len) {
            return 0;
        }
        return self.getToken().start;
    }

    pub fn countLines(self: Reader, index: usize) usize {
        var count: usize = 1;
        for (0..self.code.len - 1) |i| {
            if (i > index) {
                break;
            }
            if (self.code[i] == '\n') {
                count += 1;
            }
        }
        return count;
    }

    pub fn deinit(self: Reader) void {
        self.tokens.deinit();
        self.symbols.deinit();
    }

    pub fn read(self: *Reader) R {
        return self.readProgram();
    }

    fn readProgram(self: *Reader) R {
        const nodes = std.ArrayList(*ast.Ast).init(self.allocator);
        const block = ast.block(self.allocator, nodes, .{}) catch {
            return R.errMsg(ReaderErrorKind.Error, self.charIndex(), "Failed to allocate block");
        };
        while (self.index < self.tokens.items.len) {
            const exp = switch (self.readExpression()) {
                .ok => |v| v,
                .err => |e| {
                    return R.fromErr(e);
                },
            };
            block.block.append(exp) catch {
                return R.errMsg(ReaderErrorKind.Error, self.charIndex(), "Failed to append expression");
            };
        }
        return R.o(block);
    }

    fn readExpression(self: *Reader) R {
        return self.readBinaryLogicalOr();
    }

    fn readBinaryExpression(
        self: *Reader,
        operators: []const []const u8,
        left_parse: fn (self: *Reader) R,
        right_parse: fn (self: *Reader) R,
    ) R {
        var pin = self.index;
        const left = switch (left_parse(self)) {
            .ok => |v| v,
            .err => |e| {
                self.index = pin;
                return R.e(e.kind, e.start);
            },
        };
        pin = self.index;
        const symbol = switch (self.readSymbol(true)) {
            .ok => |v| v,
            .err => |se| {
                switch (se.kind) {
                    error.NoMatch => {
                        // handle non no match errors
                        self.index = pin;
                        return R.o(left);
                    },
                    else => {
                        return R.fromErr(se);
                    },
                }
            },
        };

        var operator_match = false;
        for (operators) |operator| {
            if (std.mem.eql(u8, symbol.symbol, operator)) {
                operator_match = true;
                break;
            }
        }

        if (!operator_match) {
            self.index = pin;
            ast.deinit(symbol, self.allocator);
            return R.o(left);
        }

        const right = switch (right_parse(self)) {
            .ok => |v| v,
            .err => |e| {
                self.index = pin;
                ast.deinit(symbol, self.allocator);
                ast.deinit(left, self.allocator);
                return R.fromErr(e);
            },
        };

        const exp = ast.binexp(self.allocator, left, symbol, right, .{}) catch {
            return R.errMsg(ReaderErrorKind.Error, self.charIndex(), "Failed to allocate binexp");
        };
        return R.o(exp);
    }

    fn readBinaryLogicalOr(self: *Reader) R {
        return self.readBinaryExpression(&[_][]const u8{"or"}, Reader.readBinaryLogicalAnd, Reader.readBinaryLogicalOr);
    }

    fn readBinaryLogicalAnd(self: *Reader) R {
        return self.readBinaryExpression(&[_][]const u8{"and"}, Reader.readEquality, Reader.readBinaryLogicalAnd);
    }

    fn readEquality(self: *Reader) R {
        return self.readBinaryExpression(&[_][]const u8{ "eq", "noteq" }, Reader.readComparison, Reader.readEquality);
    }

    fn readComparison(self: *Reader) R {
        return self.readBinaryExpression(&[_][]const u8{ "<", ">", "<=", ">=" }, Reader.readAdd, Reader.readComparison);
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
            .err => {
                self.index = start;
                return self.readPrimary();
            },
            .ok => |s| s,
        };
        const primary = switch (self.readPrimary()) {
            .err => {
                self.index = start;
                ast.deinit(op, self.allocator);
                return R.noMatch("Read unary primary");
            },
            .ok => |p| p,
        };

        const un = ast.unexp(self.allocator, op, primary, .{}) catch {
            return R.errMsg(ReaderErrorKind.Error, self.charIndex(), "Failed to allocate unexp");
        };

        return R.o(un);
    }

    pub fn tokenMatches(self: *Reader, match: []const u8) ?usize {
        if (self.index >= self.tokens.items.len) {
            return null;
        }
        const token = self.getToken();
        const lexeme = self.tokenizer.getLexeme(token) orelse {
            return null;
        };
        return switch (std.mem.eql(u8, lexeme, match)) {
            true => token.start,
            false => null,
        };
    }

    pub fn isTokenKind(self: *Reader, kind: TokenKind) bool {
        if (self.index >= self.tokens.items.len) {
            return false;
        }
        return self.getToken().kind == kind;
    }

    pub fn readUnaryOperator(self: *Reader) R {
        if (self.index >= self.tokens.items.len) {
            return R.noMatch("Read unary operator");
        }
        const token = self.getToken();
        const lexeme = self.tokenizer.getLexeme(token) orelse {
            return R.noMatch("Read unary operator lexeme");
        };
        if (std.mem.eql(u8, lexeme, "-") or std.mem.eql(u8, lexeme, "~") or std.mem.eql(u8, lexeme, "'") or std.mem.eql(u8, lexeme, "not")) {
            self.index += 1;
            const new_sym = ast.symAlloc(self.allocator, lexeme, .{}) catch {
                return R.errMsg(ReaderErrorKind.Error, token.start, "Failed to allocate symbol.");
            };
            return R.o(new_sym);
        }
        return R.noMatch("Lexeme is not a unary operator");
    }

    pub fn readPrimary(self: *Reader) R {
        if (self.tokenMatches("(")) |start| {
            self.index += 1;
            const exp = switch (self.readExpression()) {
                .ok => |v| v,
                .err => |e| {
                    return R.e(e.kind, e.start);
                },
            };

            if (self.tokenMatches(")")) |_| {} else {
                return R.errMsg(ReaderErrorKind.MissingClosingParen, start, "Missing closing parenthesis");
            }
            self.index += 1;
            return R.o(exp);
        }

        switch (self.readUse()) {
            .ok => |v| {
                return R.o(v);
            },
            .err => |e| {
                if (e.kind != ReaderErrorKind.NoMatch) {
                    return R.fromErr(e);
                }
            },
        }

        switch (self.readDefinition()) {
            .ok => |v| {
                return R.o(v);
            },
            .err => |e| {
                if (e.kind != ReaderErrorKind.NoMatch) {
                    return R.fromErr(e);
                }
            },
        }

        switch (self.readAssignment()) {
            .ok => |v| {
                return R.o(v);
            },
            .err => |e| {
                if (e.kind != ReaderErrorKind.NoMatch) {
                    return R.fromErr(e);
                }
            },
        }

        switch (self.readDoBlock()) {
            .ok => |v| {
                return R.o(v);
            },
            .err => |e| {
                if (e.kind != ReaderErrorKind.NoMatch) {
                    return R.fromErr(e);
                }
            },
        }

        switch (self.readFunctionDefinition()) {
            .ok => |v| {
                return R.o(v);
            },
            .err => |e| {
                if (e.kind != ReaderErrorKind.NoMatch) {
                    return R.fromErr(e);
                }
            },
        }

        switch (self.readLambda()) {
            .ok => |v| {
                return R.o(v);
            },
            .err => |e| {
                if (e.kind != ReaderErrorKind.NoMatch) {
                    return R.fromErr(e);
                }
            },
        }

        switch (self.readIf()) {
            .ok => |v| {
                return R.o(v);
            },
            .err => |e| {
                if (e.kind != ReaderErrorKind.NoMatch) {
                    return R.fromErr(e);
                }
            },
        }

        switch (self.readCond()) {
            .ok => |v| {
                return R.o(v);
            },
            .err => |e| {
                if (e.kind != ReaderErrorKind.NoMatch) {
                    return R.fromErr(e);
                }
            },
        }

        switch (self.readWhile()) {
            .ok => |v| {
                return R.o(v);
            },
            .err => |e| {
                if (e.kind != ReaderErrorKind.NoMatch) {
                    return R.fromErr(e);
                }
            },
        }

        switch (self.readFor()) {
            .ok => |v| {
                return R.o(v);
            },
            .err => |e| {
                if (e.kind != ReaderErrorKind.NoMatch) {
                    return R.fromErr(e);
                }
            },
        }

        return R.noMatch("Primary");
    }

    pub fn readDoBlock(self: *Reader) R {
        if (self.tokenMatches("do") == null) {
            return R.noMatch("Not a do block");
        }
        self.index += 1;
        const block = switch (self.readBlockTillEnd()) {
            .err => |e| {
                return R.fromErr(e);
            },
            .ok => |v| v,
        };
        return R.o(block);
    }

    pub fn readUse(self: *Reader) R {
        if (self.tokenMatches("use") == null) {
            return R.noMatch("Not a use");
        }
        self.index += 1;
        switch (self.readSymbol(false)) {
            .ok => |s| {
                return R.o(ast.use(self.allocator, s.symbol, .{}) catch {
                    return R.errMsg(ReaderErrorKind.Error, self.charIndex(), "Failed to allocate definition");
                });
            },
            .err => {
                return R.errMsg(ReaderErrorKind.InvalidUse, self.charIndex(), "Use expects a module name");
            },
        }
    }

    pub fn readDefinition(self: *Reader) R {
        const start = self.index;
        const sym = switch (self.readSymbol(false)) {
            .err => |e| {
                return R.fromErr(e);
            },
            .ok => |v| v,
        };

        if (self.isTokenKind(TokenKind.colon)) {
            self.index += 1;
            if (self.tokenMatches("=") == null) {
                self.index = start;
                ast.deinit(sym, self.allocator);
                return R.noMatch("Not a definition");
            }
            self.index += 1;
        } else {
            self.index = start;
            ast.deinit(sym, self.allocator);
            return R.noMatch("Not a definition");
        }

        const exp = switch (self.readExpression()) {
            .err => |e| {
                self.index = start;
                ast.deinit(sym, self.allocator);
                return R.fromErr(e);
            },
            .ok => |v| v,
        };
        return R.o(ast.define(self.allocator, sym, exp, .{}) catch {
            return R.errMsg(ReaderErrorKind.Error, self.charIndex(), "Failed to allocate definition");
        });
    }

    pub fn readAssignment(self: *Reader) R {
        const sym = switch (self.readDotCall()) {
            .err => |e| {
                return R.fromErr(e);
            },
            .ok => |v| v,
        };
        const start = self.index;
        if (self.tokenMatches("=") == null) {
            return R.o(sym);
        }
        self.index += 1;
        const exp = switch (self.readExpression()) {
            .err => |e| {
                self.index = start;
                ast.deinit(sym, self.allocator);
                return R.fromErr(e);
            },
            .ok => |v| v,
        };
        return R.o(ast.assign(self.allocator, sym, exp, .{}) catch {
            return R.errMsg(ReaderErrorKind.Error, self.charIndex(), "Failed to allocate definition");
        });
    }

    pub fn readFunctionDefinition(self: *Reader) R {
        if (self.tokenMatches("fun") == null) {
            return R.noMatch("Not a function definition");
        }
        const start = self.index;
        self.index += 1;

        const sym: ?*ast.Ast = switch (self.readSymbol(false)) {
            .err => null,
            .ok => |s| s,
        };

        if (!self.isTokenKind(TokenKind.openParen)) {
            self.index = start;
            return R.e(ReaderErrorKind.InvalidFunctionDefinition, 0);
        }
        self.index += 1;
        const args = self.readArgList() catch |e| return R.e(e, 0);
        const body = switch (self.readBlockTillEnd()) {
            .err => |e| {
                return R.fromErr(e);
            },
            .ok => |v| v,
        };
        return R.o(ast.func(self.allocator, sym, args, body, .{}) catch {
            return R.errMsg(ReaderErrorKind.Error, self.charIndex(), "Failed to allocate func");
        });
    }

    pub fn readLambda(self: *Reader) R {
        const start = self.index;
        if (self.tokenMatches("fn") == null) {
            return R.noMatch("Not a lambda");
        }
        self.index += 1;
        if (!self.isTokenKind(TokenKind.openParen)) {
            self.index = start;
            return R.e(ReaderErrorKind.InvalidLambda, 0);
        }
        self.index += 1;
        const args = self.readArgList() catch |e| return R.e(e, 0);
        const exp = switch (self.readExpression()) {
            .ok => |v| v,
            .err => |e| {
                return R.fromErr(e);
            },
        };
        return R.o(ast.func(self.allocator, null, args, exp, .{}) catch {
            return R.errMsg(ReaderErrorKind.Error, self.charIndex(), "Failed to allocate func");
        });
    }

    pub fn readIf(self: *Reader) R {
        if (self.tokenMatches("if") == null) {
            return R.noMatch("Not an if");
        }

        var elseBranch: ?*ast.Ast = null;
        var branches = std.ArrayList(ast.Branch).init(self.allocator);
        var first = true;

        while (self.index < self.tokens.items.len) {
            if (self.tokenMatches("else")) |_| {
                self.index += 1;
                elseBranch = switch (self.readBlockTillEnd()) {
                    .err => |e| {
                        return R.fromErr(e);
                    },
                    .ok => |v| v,
                };
                break;
            }

            if (self.tokenMatches("end")) |_| {
                self.index += 1;
                break;
            }

            if (self.tokenMatches("elif") == null and !first) {
                return R.errMsg(ReaderErrorKind.InvalidIf, self.charIndex(), "Missing elif");
            }

            self.index += 1;
            first = false;

            const elifCond = switch (self.readExpression()) {
                .ok => |v| v,
                .err => |e| {
                    return R.fromErr(e);
                },
            };

            if (self.tokenMatches("then") == null) {
                return R.errMsg(ReaderErrorKind.InvalidIf, self.charIndex(), "If missing then");
            }
            self.index += 1;

            var blockBody = std.ArrayList(*ast.Ast).init(self.allocator);
            while (self.index < self.tokens.items.len) {
                if (self.tokenMatches("elif") != null or //
                    self.tokenMatches("else") != null or //
                    self.tokenMatches("end") != null)
                {
                    const branch = ast.Branch{
                        .check = elifCond, //
                        .then = ast.block(self.allocator, blockBody, .{}) catch { //
                            return R.errMsg(ReaderErrorKind.Error, self.charIndex(), "Failed to allocate block");
                        },
                    };
                    branches.append(branch) catch {
                        return R.errMsg(ReaderErrorKind.Error, self.charIndex(), "Failed to append item");
                    };
                    break;
                }

                switch (self.readExpression()) {
                    .err => |e| {
                        return R.fromErr(e);
                    },
                    .ok => |v| {
                        blockBody.append(v) catch {
                            return R.errMsg(ReaderErrorKind.Error, self.charIndex(), "Failed to append block body");
                        };
                    },
                }
            }
        }

        return R.o(ast.ifx(self.allocator, branches, elseBranch, .{}) catch {
            return R.errMsg(ReaderErrorKind.Error, self.charIndex(), "Failed to allocate if");
        });
    }

    pub fn readWhile(self: *Reader) R {
        if (self.tokenMatches("while") == null) {
            return R.noMatch("Not a while");
        }
        self.index += 1;
        const cond = switch (self.readExpression()) {
            .ok => |v| v,
            .err => |e| {
                return R.fromErr(e);
            },
        };
        if (self.tokenMatches("do") == null) {
            return R.errMsg(ReaderErrorKind.InvalidCond, self.charIndex(), "Condition is missing do");
        }
        self.index += 1;
        const block = switch (self.readBlockTillEnd()) {
            .err => |e| {
                return R.fromErr(e);
            },
            .ok => |v| v,
        };
        return R.o(ast.whilex(self.allocator, cond, block, .{}) catch {
            return R.errMsg(ReaderErrorKind.Error, self.charIndex(), "Failed to allocate while");
        });
    }

    pub fn readFor(self: *Reader) R {
        if (self.tokenMatches("for") == null) {
            return R.noMatch("Not a if");
        }
        self.index += 1;
        const variable = switch (self.readSymbol(false)) {
            .ok => |s| s,
            .err => {
                return R.errMsg(ReaderErrorKind.InvalidFor, self.charIndex(), "for expects symbol for variable");
            },
        };

        if (self.tokenMatches("in") == null) {
            return R.errMsg(ReaderErrorKind.InvalidFor, self.charIndex(), "For is missing 'in' keyword");
        }
        self.index += 1;

        const iterable = switch (self.readExpression()) {
            .ok => |v| v,
            .err => |e| {
                return R.fromErr(e);
            },
        };

        if (self.tokenMatches("do") == null) {
            return R.errMsg(ReaderErrorKind.InvalidCond, self.charIndex(), "Condition is missing do");
        }
        self.index += 1;
        const block = switch (self.readBlockTillEnd()) {
            .err => |e| {
                return R.fromErr(e);
            },
            .ok => |v| v,
        };
        return R.o(ast.forx(self.allocator, variable, iterable, block, .{}) catch {
            return R.errMsg(ReaderErrorKind.Error, self.charIndex(), "Failed to allocate for");
        });
    }

    pub fn readCond(self: *Reader) R {
        if (self.tokenMatches("cond") == null) {
            return R.noMatch("Not a condition");
        }

        var branches = std.ArrayList(ast.Branch).init(self.allocator);

        self.index += 1;
        while (self.index < self.tokens.items.len) {
            const cond = switch (self.readExpression()) {
                .ok => |v| v,
                .err => |e| {
                    return R.fromErr(e);
                },
            };

            if (self.tokenMatches("do") == null) {
                return R.errMsg(ReaderErrorKind.InvalidCond, self.charIndex(), "Condition is missing do");
            }
            self.index += 1;
            const block = switch (self.readBlockTillEnd()) {
                .err => |e| {
                    return R.fromErr(e);
                },
                .ok => |v| v,
            };

            branches.append(ast.Branch{ .check = cond, .then = block }) catch {
                return R.errMsg(ReaderErrorKind.Error, self.charIndex(), "Failed to append branch");
            };

            if (self.tokenMatches("end")) |_| {
                self.index += 1;
                break;
            }
            if (self.index >= self.tokens.items.len) {
                return R.errMsg(ReaderErrorKind.InvalidCond, self.charIndex(), "Condition is missing end");
            }
        }

        return R.o(ast.ifx(self.allocator, branches, null, .{}) catch {
            return R.errMsg(ReaderErrorKind.Error, self.charIndex(), "Failed to allocate if");
        });
    }

    // this is a terminal that can yield a literal
    pub fn readDotCall(self: *Reader) R {
        var callable = switch (self.readCallable()) {
            .ok => |v| v,
            .err => |e| {
                if (e.kind != ReaderErrorKind.NoMatch) {
                    return R.fromErr(e);
                }
                return R.noMatch("Not a callable");
            },
        };
        if (!self.isTokenKind(TokenKind.dot) and self.tokenMatches("(") == null) {
            return R.o(callable);
        }
        while (self.isTokenKind(TokenKind.dot) or self.tokenMatches("(") != null) {
            if (self.isTokenKind(TokenKind.dot)) {
                self.index += 1;
                const sym = switch (self.readSymbol(false)) {
                    .err => {
                        return R.e(ReaderErrorKind.DotMissingParameter, 0);
                    },
                    .ok => |s| s,
                };
                callable = ast.dot(self.allocator, callable, sym, .{}) catch {
                    return R.errMsg(ReaderErrorKind.Error, self.charIndex(), "Failed to allocate dot.");
                };
            } else if (self.tokenMatches("(")) |idx| {
                self.index += 1;
                const args = self.readArgList() catch |e| return R.e(e, idx);
                callable = ast.call(self.allocator, callable, args, .{}) catch {
                    return R.errMsg(ReaderErrorKind.Error, self.charIndex(), "Failed to allocate call.");
                };
            }
        }

        return R.o(callable);
    }

    pub fn readArgList(self: *Reader) ReaderErrorKind!std.ArrayList(*ast.Ast) {
        var args = std.ArrayList(*ast.Ast).init(self.allocator);
        while (self.index < self.tokens.items.len) {
            if (self.tokenMatches(")")) |_| {
                self.index += 1;
                break;
            }
            const exp = switch (self.readExpression()) {
                .ok => |s| s,
                .err => {
                    return args;
                },
            };
            if (self.index >= self.tokens.items.len) {
                return error.MissingClosingParen;
            }
            args.append(exp) catch {
                ast.deinit(exp, self.allocator);
                return args;
            };
            if (self.tokenMatches(")")) |_| {
                self.index += 1;
                break;
            }
            if (!self.isTokenKind(TokenKind.comma)) {
                return error.MissingComma;
            }
            self.index += 1;
        }
        return args;
    }

    pub fn readBlockTillEnd(self: *Reader) R {
        const start_index = self.charIndex();
        var args = std.ArrayList(*ast.Ast).init(self.allocator);

        if (self.tokenMatches("end")) |_| {
            self.index += 1;
            return R.o(ast.block(self.allocator, args, .{}) catch {
                std.debug.panic("Failed to allocate block", .{});
                return R.e(ReaderErrorKind.Error, 0);
            });
        }

        while (self.index < self.tokens.items.len) {
            const exp = switch (self.readExpression()) {
                .err => |e| {
                    return R.fromErr(e);
                },
                .ok => |v| v,
            };

            args.append(exp) catch unreachable;

            if (self.tokenMatches("end")) |_| {
                self.index += 1;
                break;
            }

            if (self.index >= self.tokens.items.len) {
                return R.e(ReaderErrorKind.MissingEnd, start_index);
            }
        }

        return R.o(ast.block(self.allocator, args, .{}) catch {
            return R.e(ReaderErrorKind.Error, start_index);
        });
    }

    pub fn readCallable(self: *Reader) R {
        switch (self.readLiteral()) {
            .err => |e| {
                if (e.kind != ReaderErrorKind.NoMatch) {
                    return R.fromErr(e);
                }
            },
            .ok => |v| {
                return R.o(v);
            },
        }
        switch (self.readSymbol(false)) {
            .err => |e| {
                if (e.kind != ReaderErrorKind.NoMatch) {
                    return R.fromErr(e);
                }
            },
            .ok => |v| {
                return R.o(v);
            },
        }
        return R.e(ReaderErrorKind.NoMatch, 0);
    }

    pub fn readLiteral(self: *Reader) R {
        if (self.tokenMatches("(")) |start| {
            self.index += 1;
            const exp = switch (self.readExpression()) {
                .ok => |v| v,
                .err => |e| {
                    return R.e(e.kind, e.start);
                },
            };

            if (self.tokenMatches(")")) |_| {} else {
                return R.errMsg(ReaderErrorKind.MissingClosingParen, start, "Missing closing parenthesis");
            }
            self.index += 1;
            return R.o(exp);
        }

        switch (self.readNumber()) {
            .err => |e| {
                if (e.kind != ReaderErrorKind.NoMatch) {
                    return R.fromErr(e);
                }
            },
            .ok => |v| {
                return R.o(v);
            },
        }
        switch (self.readBoolean()) {
            .err => |e| {
                if (e.kind != ReaderErrorKind.NoMatch) {
                    return R.fromErr(e);
                }
            },
            .ok => |v| {
                return R.o(v);
            },
        }
        switch (self.readString()) {
            .err => |e| {
                if (e.kind != ReaderErrorKind.NoMatch) {
                    return R.fromErr(e);
                }
            },
            .ok => |v| {
                return R.o(v);
            },
        }
        switch (self.readList()) {
            .err => |e| {
                if (e.kind != ReaderErrorKind.NoMatch) {
                    return R.fromErr(e);
                }
            },
            .ok => |v| {
                return R.o(v);
            },
        }
        switch (self.readDictionary()) {
            .err => |e| {
                if (e.kind != ReaderErrorKind.NoMatch) {
                    return R.fromErr(e);
                }
            },
            .ok => |v| {
                return R.o(v);
            },
        }
        return R.noMatch("Literal");
    }

    pub fn readDictionary(self: *Reader) R {
        if (!self.isTokenKind(TokenKind.openBrace)) {
            return R.noMatch("Not a dictionary literal");
        }
        self.index += 1;
        var pairs = std.ArrayList(ast.KV).init(self.allocator);

        if (self.isTokenKind(TokenKind.closeBrace)) {
            self.index += 1;
            return R.o(ast.dict(self.allocator, pairs, .{}) catch {
                return R.errMsg(ReaderErrorKind.Error, self.charIndex(), "Failed to allocate dictionary");
            });
        }

        while (self.index < self.tokens.items.len) {
            // handle :<sym>
            if (self.isTokenKind(TokenKind.colon)) {
                self.index += 1;
                const sym = switch (self.readSymbol(false)) {
                    .ok => |v| v,
                    .err => {
                        return R.errMsg(ReaderErrorKind.InvalidDictionary, self.charIndex(), "Expected symbol");
                    },
                };
                const sym_value = ast.symAlloc(self.allocator, sym.symbol, .{}) catch {
                    return R.errMsg(ReaderErrorKind.Error, self.charIndex(), "Failed to allocate value");
                };
                pairs.append(ast.KV{ .key = sym, .value = sym_value }) catch {
                    return R.errMsg(ReaderErrorKind.Error, self.charIndex(), "Failed to append dictionary key value");
                };
            } else {
                const sym = switch (self.readSymbol(false)) {
                    .ok => |v| v,
                    .err => {
                        return R.errMsg(ReaderErrorKind.InvalidDictionary, self.charIndex(), "Expected symbol");
                    },
                };

                if (!self.isTokenKind(TokenKind.colon)) {
                    return R.errMsg(ReaderErrorKind.InvalidDictionary, self.charIndex(), "Expected colon after key");
                }
                self.index += 1;

                const value = switch (self.readExpression()) {
                    .ok => |v| v,
                    .err => |e| {
                        return R.fromErr(e);
                    },
                };

                pairs.append(ast.KV{ .key = sym, .value = value }) catch {
                    return R.errMsg(ReaderErrorKind.Error, self.charIndex(), "Failed to append dictionary key value");
                };
            }

            if (self.isTokenKind(TokenKind.comma)) {
                self.index += 1;
            }

            if (self.isTokenKind(TokenKind.closeBrace)) {
                self.index += 1;
                break;
            } else if (self.index >= self.tokens.items.len) {
                return R.errMsg(ReaderErrorKind.InvalidDictionary, self.charIndex(), "Missing closing brace '}'");
            }
        }

        return R.o(ast.dict(self.allocator, pairs, .{}) catch {
            return R.errMsg(ReaderErrorKind.Error, self.charIndex(), "Failed to allocate dictionary");
        });
    }

    pub fn readList(self: *Reader) R {
        if (!self.isTokenKind(TokenKind.openBracket)) {
            return R.noMatch("Not a list");
        }
        self.index += 1;
        var xs = std.ArrayList(*ast.Ast).init(self.allocator);
        if (self.isTokenKind(TokenKind.closeBracket)) {
            self.index += 1;
            return R.o(ast.list(self.allocator, xs, .{}) catch {
                return R.errMsg(ReaderErrorKind.Error, self.charIndex(), "Failed to alloc list");
            });
        }
        while (self.index < self.tokens.items.len) {
            const exp = switch (self.readExpression()) {
                .ok => |v| v,
                .err => |e| {
                    return R.fromErr(e);
                },
            };
            xs.append(exp) catch {
                return R.errMsg(ReaderErrorKind.Error, self.charIndex(), "Failed to append");
            };
            if (self.isTokenKind(TokenKind.comma)) {
                self.index += 1;
            }
            if (self.isTokenKind(TokenKind.closeBracket)) {
                self.index += 1;
                break;
            } else if (self.index >= self.tokens.items.len) {
                return R.e(ReaderErrorKind.MissingClosingBracket, 0);
            }
        }
        return R.o(ast.list(self.allocator, xs, .{}) catch {
            return R.errMsg(ReaderErrorKind.Error, self.charIndex(), "Failed to alloc list");
        });
    }

    pub fn readNumber(self: *Reader) R {
        const tok = self.getToken();
        if (tok.kind != TokenKind.number) {
            return R.noMatch("Number");
        }
        const num = self.tokenizer.readNumber(tok.start) orelse {
            return R.noMatch("Number lexeme");
        };
        self.index += 1;
        return R.o(ast.num(self.allocator, num, .{}) catch {
            return R.errMsg(ReaderErrorKind.Error, tok.start, "Failed to alloc number node");
        });
    }

    pub fn readString(self: *Reader) R {
        const tok = self.getToken();
        if (tok.kind != TokenKind.string) {
            return R.noMatch("String");
        }
        const lexeme = self.tokenizer.getLexeme(tok) orelse {
            return R.errMsg(ReaderErrorKind.Error, tok.start, "Failed to get lexeme");
        };
        self.index += 1;
        const slice = convertEscapeSequences(self.allocator, lexeme[1 .. lexeme.len - 1]) catch {
            return R.errMsg(ReaderErrorKind.Error, tok.start, "Failed to get lexeme");
        };
        return R.o(ast.str(self.allocator, slice, .{}) catch {
            return R.errMsg(ReaderErrorKind.Error, tok.start, "Failed to alloc string");
        });
    }

    pub fn readBoolean(self: *Reader) R {
        const tok = self.getToken();
        if (tok.kind != TokenKind.keyword) {
            return R.noMatch("Not a boolean keyword");
        }
        var index = tok.start;
        const lexeme = self.tokenizer.readKeywordLexeme(&index) orelse {
            return R.noMatch("Not a keyword lexeme");
        };
        if (std.mem.eql(u8, lexeme, "true")) {
            self.index += 1;
            return R.o(ast.T(self.allocator, .{}) catch {
                return R.errMsg(ReaderErrorKind.Error, tok.start, "Failed to alloc boolean");
            });
        }
        if (std.mem.eql(u8, lexeme, "false")) {
            self.index += 1;
            return R.o(ast.F(self.allocator, .{}) catch {
                return R.errMsg(ReaderErrorKind.Error, tok.start, "Failed to alloc boolean");
            });
        }
        return R.noMatch("Not a boolean");
    }

    pub fn readSymbol(self: *Reader, readKeywords: bool) R {
        if (self.index >= self.tokens.items.len) {
            return R.noMatch("Symbol");
        }
        const sym = self.getToken();
        if (!readKeywords and sym.kind == TokenKind.keyword) {
            return R.noMatch("Unexpected keyword");
        }
        if (sym.kind != TokenKind.keyword and sym.kind != TokenKind.symbol) {
            return R.noMatch("Not a symbol or keyword");
        }
        const lexeme = self.tokenizer.getLexeme(sym) orelse {
            return R.errMsg(ReaderErrorKind.Error, sym.start, "Failed to get lexeme");
        };
        const symbol = ast.symAlloc(self.allocator, lexeme, .{ .line = sym.line }) catch {
            return R.errMsg(ReaderErrorKind.Error, sym.start, "Error allocating symbol");
        };
        self.symbols.append(symbol.symbol) catch unreachable;
        self.index += 1;
        return R.o(symbol);
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
