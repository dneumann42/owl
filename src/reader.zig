const std = @import("std");

const tokenizer = @import("tokenizer.zig");
const Token = tokenizer.Token;
const TokenKind = tokenizer.TokenKind;
const Tokenizer = tokenizer.Tokenizer;

const ast = @import("ast.zig");
const Node = ast.Node;
const Ast = ast.Ast;

pub fn debugPrint(node: *const Ast) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    std.debug.print("{s}\n", .{ast.toString(node, arena.allocator()) catch "error"});
}

const ReaderError = error{ NoMatch, Error, UnexpectedKeyword, MissingClosingParen, MissingEnd, InvalidFunctionDefinition, OutOfMemory };

pub const Reader = struct {
    const Self = @This();

    arenaAllocator: std.heap.ArenaAllocator,
    code: []const u8,

    it: usize = 0,
    errorMessage: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, code: []const u8) Reader {
        return Self{
            .arenaAllocator = std.heap.ArenaAllocator.init(allocator),
            .code = code,
        };
    }

    pub fn deinit(self: Self) void {
        self.arenaAllocator.deinit();
    }

    pub fn read(self: *Self) !*Ast {
        var tz = Tokenizer.init(self.arenaAllocator.allocator(), self.code);
        try tz.tokenize();
        return self.readProgram(tz);
    }

    pub fn tokenCount(tz: Tokenizer) usize {
        return tz.tokens.items.len;
    }

    pub fn token(self: Self, tz: Tokenizer) Token {
        return tz.tokens.items[self.it];
    }

    pub fn isTokenKind(self: Self, tz: Tokenizer, kind: TokenKind) bool {
        return self.token(tz).kind == kind;
    }

    pub fn readProgram(self: *Self, tz: Tokenizer) ReaderError!*Ast {
        var prog = try ast.program(self.arenaAllocator.allocator(), .{});
        while (self.it < Self.tokenCount(tz)) {
            try prog.node.program.append(try self.readExpr(tz));
        }
        return prog;
    }

    pub fn readExpr(self: *Self, tz: Tokenizer) ReaderError!*Ast {
        return self.readBinaryLOr(tz);
    }

    pub fn readBinaryExpr( //
        self: *Self,
        tz: Tokenizer,
        ops: []const []const u8,
        left: fn (self: *Self, tz: Tokenizer) ReaderError!*Ast,
        right: fn (self: *Self, tz: Tokenizer) ReaderError!*Ast,
    ) ReaderError!*Ast {
        var pin = self.it;
        const lv = try left(self, tz);
        pin = self.it;
        const sym = self.readSymbol(tz, true) catch |e| switch (e) {
            error.NoMatch => {
                self.it = pin;
                return lv;
            },
            else => return e,
        };
        var operator_match = false;
        for (ops) |op| {
            if (std.mem.eql(u8, sym.node.symbol, op)) {
                operator_match = true;
                break;
            }
        }
        if (!operator_match) {
            self.it = pin;
            return lv;
        }
        const rv = right(self, tz) catch |e| return e;
        return ast.binexp(self.arenaAllocator.allocator(), lv, sym, rv, .{});
    }

    pub fn readBinaryLOr(self: *Self, tz: Tokenizer) ReaderError!*Ast {
        return self.readBinaryExpr(tz, &[_][]const u8{"or"}, Self.readBinaryLAnd, Self.readBinaryLOr);
    }
    pub fn readBinaryLAnd(self: *Self, tz: Tokenizer) ReaderError!*Ast {
        return self.readBinaryExpr(tz, &[_][]const u8{"and"}, Self.readEquality, Self.readBinaryLAnd);
    }
    pub fn readEquality(self: *Self, tz: Tokenizer) ReaderError!*Ast {
        return self.readBinaryExpr(tz, &[_][]const u8{ "eq", "not-eq" }, Self.readComparison, Self.readEquality);
    }
    pub fn readComparison(self: *Self, tz: Tokenizer) ReaderError!*Ast {
        return self.readBinaryExpr(tz, &[_][]const u8{ "<", ">", "<=", ">=" }, Self.readAdd, Self.readComparison);
    }
    pub fn readAdd(self: *Self, tz: Tokenizer) ReaderError!*Ast {
        return self.readBinaryExpr(tz, &[_][]const u8{ "+", "-" }, Self.readMultiply, Self.readAdd);
    }
    pub fn readMultiply(self: *Self, tz: Tokenizer) ReaderError!*Ast {
        return self.readBinaryExpr(tz, &[_][]const u8{ "*", "/" }, Self.readUnary, Self.readMultiply);
    }

    pub fn readUnary(self: *Self, tz: Tokenizer) ReaderError!*Ast {
        const start = self.it;
        const op = self.readUnaryOperator(tz) catch {
            self.it = start;
            return self.readPrimary(tz);
        };
        const primary = self.readPrimary(tz) catch return error.Error;
        return ast.unexp(self.arenaAllocator.allocator(), op, primary, .{});
    }

    pub fn tokenMatches(self: *Reader, tz: Tokenizer, match: []const u8) ?usize {
        if (self.it >= Self.tokenCount(tz)) {
            return null;
        }
        const tok = self.token(tz);
        const lexeme = tz.getLexeme(tok) orelse return null;
        return switch (std.mem.eql(u8, lexeme, match)) {
            true => tok.start,
            false => null,
        };
    }

    const ParseResult = union(enum) { ok: *Ast, err: ReaderError, noMatch: bool };

    pub fn parseResult(result: ReaderError!*Ast) ParseResult {
        const ok = result catch |e| switch (e) {
            error.NoMatch => return .{ .noMatch = true },
            else => return .{ .err = e },
        };
        return .{ .ok = ok };
    }

    pub fn readUnaryOperator(self: *Self, tz: Tokenizer) ReaderError!*Ast {
        if (self.it >= Self.tokenCount(tz))
            return error.NoMatch;
        const tok = self.token(tz);
        const lexeme = tz.getLexeme(tok) orelse return error.Error;
        if (std.mem.eql(u8, lexeme, "-") or std.mem.eql(u8, lexeme, "~") or std.mem.eql(u8, lexeme, "'") or std.mem.eql(u8, lexeme, "not")) {
            self.it += 1;
            return ast.symAlloc(self.arenaAllocator.allocator(), lexeme, .{}) catch return error.Error;
        }
        return error.NoMatch;
    }

    pub fn readPrimary(self: *Self, tz: Tokenizer) ReaderError!*Ast {
        if (self.tokenMatches(tz, "(")) |_| {
            self.it += 1;
            const exp = try self.readExpr(tz);
            if (self.tokenMatches(tz, ")")) |_| {} else return error.MissingClosingParen;
            self.it += 1;
            return exp;
        }
        switch (Self.parseResult(self.readUse(tz))) {
            .err => |e| return e,
            .ok => |o| return o,
            else => {},
        }
        switch (Self.parseResult(self.readDefinition(tz))) {
            .err => |e| return e,
            .ok => |o| return o,
            else => {},
        }
        switch (Self.parseResult(self.readAssignment(tz))) {
            .err => |e| return e,
            .ok => |o| return o,
            else => {},
        }
        switch (Self.parseResult(self.readDoBlock(tz))) {
            .err => |e| return e,
            .ok => |o| return o,
            else => {},
        }
        switch (Self.parseResult(self.readFunctionDefinition(tz))) {
            .err => |e| return e,
            .ok => |o| return o,
            else => {},
        }
        return error.NoMatch;
    }

    pub fn readUse(self: *Self, tz: Tokenizer) ReaderError!*Ast {
        if (self.tokenMatches(tz, "use") == null)
            return error.NoMatch;
        self.it += 1;
        const sym = try self.readSymbol(tz, false);
        return ast.use(self.arenaAllocator.allocator(), sym.node.symbol, .{});
    }

    pub fn readDefinition(self: *Self, tz: Tokenizer) ReaderError!*Ast {
        const allocator = self.arenaAllocator.allocator();
        const start = self.it;
        const sym = try self.readSymbol(tz, false) catch |e| switch (e) {
            .NoMatch => {
                self.it = start;
                return .NoMatch;
            },
            else => return e,
        };
        if (self.isTokenKind(tz, TokenKind.colon)) {
            self.it += 1;
            if (self.tokenMatches("=") == null) {
                self.it = start;
                ast.deinit(sym, allocator);
                return error.NoMatch;
            }
            self.it += 1;
        } else {
            self.it = start;
            ast.deinit(sym, allocator);
            return error.NoMatch;
        }
        const exp = try self.readExpression();
        return ast.define(allocator, sym, exp, .{});
    }

    pub fn readAssignment(self: *Self, tz: Tokenizer) ReaderError!*Ast {
        const sym = try self.readDotCall();
        const start = self.it;
        if (self.tokenMatches(tz, "=") == null)
            return sym;
        self.index += 1;
        const exp = self.readExpr(tz) catch |e| {
            self.it = start;
            return e;
        };
        return ast.assign(self.arenaAllocator.allocator(), sym, exp, .{});
    }

    pub fn readDoBlock(self: *Self, tz: Tokenizer) ReaderError!*Ast {
        if (self.tokenMatches(tz, "do") == null)
            return error.NoMatch;
        self.index += 1;
        return self.readBlockTillEnd();
    }

    pub fn readBlockTillEnd(self: *Self, tz: Tokenizer) ReaderError!*Ast {
        const allocator = self.arenaAllocator.allocator();
        var args = std.ArrayList(*ast.Ast).init(allocator);
        if (self.tokenMatches(tz, "end")) |_| {
            self.it += 1;
            return ast.block(allocator, args, .{});
        }
        while (self.it < Self.tokenCount(tz)) {
            const exp = try self.readExpr(tz);
            try args.append(exp);
            if (self.tokenMatches(tz, "end")) |_| {
                self.it += 1;
                break;
            }
            if (self.it >= Self.tokenCount(tz))
                return error.MissingEnd;
        }
        return ast.block(allocator, args, .{});
    }

    pub fn readFunctionDefinition(self: *Self, tz: Tokenizer) ReaderError!*Ast {
        if (self.tokenMatches(tz, "fun") == null)
            return error.NoMatch;

        const start = self.it;
        self.it += 1;

        const sym: *ast.Ast = try self.readSymbol(tz, false);

        if (!self.isTokenKind(tz, TokenKind.openParen)) {
            self.it = start;
            return error.InvalidFunctionDefinition;
        }
        self.index += 1;
        const args = try self.readArgList();
        const body = try self.readBlockTillEnd();
        return ast.func(self.allocator, sym, args, body, .{});
    }

    pub fn readArgList(self: *Self, tz: Tokenizer) ReaderError!*Ast {
        _ = self;
        _ = tz;
    }

    pub fn readSymbol(self: *Self, tz: Tokenizer, readKeywords: bool) ReaderError!*Ast {
        if (self.it > Self.tokenCount(tz))
            return error.NoMatch;
        const sym = self.token(tz);
        if (!readKeywords and sym.kind == TokenKind.keyword)
            return error.UnexpectedKeyword;
        if (sym.kind != TokenKind.keyword and sym.kind != TokenKind.symbol)
            return error.NoMatch;
        const lexeme = tz.getLexeme(sym) orelse return error.Error;
        const symbol = try ast.symAlloc(self.arenaAllocator.allocator(), lexeme, .{});
        self.it += 1;
        return symbol;
    }
};
