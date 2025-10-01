const std = @import("std");
const gc_ = @import("gc.zig");
const Gc = gc_.Gc;
const value = @import("value.zig");
const Value = value.Value;

pub const ReaderError = error{InvalidToken};

pub const TokenType = enum { Terminator, Number, String, Symbol, Keyword, Operator, Eof };

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
            if (index < code.len and code[index] == '\n') {
                try self.tokens.append(self.allocator, Token{ .type = .Terminator, .index = index });
                index += 1;
            }
        }
        try self.tokens.append(self.allocator, Token{ .type = .Terminator, .index = code.len });
        try self.tokens.append(self.allocator, Token{ .type = .Eof, .index = code.len });
    }

    pub fn readLexeme(code: []const u8, tok: Token) []const u8 {
        var index = tok.index;
        while (index < code.len and !std.ascii.isWhitespace(code[index]))
            index += 1;
        return code[tok.index..index];
    }

    pub fn peekToken(self: @This()) Token {
        if (self.atEnd()) return Token{ .type = .Eof, .index = self.tokens.items.len };
        return self.tokens.items[self.index];
    }

    pub fn nextToken(self: *@This()) Token {
        const t = self.peekToken();
        if (t.type != .Eof) self.index += 1;
        return t;
    }

    fn atEnd(self: @This()) bool {
        return self.index >= self.tokens.items.len or self.tokens.items[self.index].type == .Eof;
    }

    fn accept(self: *@This(), ty: TokenType) bool {
        if (self.peekToken().type == ty) {
            _ = self.nextToken();
            return true;
        }
        return false;
    }

    fn precedence(op: []const u8) u32 {
        if (std.mem.eql(u8, op, "|>")) return 10;
        if (std.mem.eql(u8, op, "||")) return 20;
        if (std.mem.eql(u8, op, "&&")) return 30;
        if (std.mem.eql(u8, op, "==") or std.mem.eql(u8, op, "!=")) return 40;
        if (std.mem.eql(u8, op, "<") or std.mem.eql(u8, op, "<=") or std.mem.eql(u8, op, ">") or std.mem.eql(u8, op, ">=")) return 50;
        if (std.mem.eql(u8, op, "+") or std.mem.eql(u8, op, "-")) return 60;
        if (std.mem.eql(u8, op, "*") or std.mem.eql(u8, op, "/") or std.mem.eql(u8, op, "%")) return 70;
        return 0;
    }

    fn isUnary(op: []const u8) bool {
        return std.mem.eql(u8, op, "!") or std.mem.eql(u8, op, "+") or std.mem.eql(u8, op, "-");
    }

    fn boundary(self: @This()) bool {
        const t = self.peekToken().type;
        return t == .Terminator or t == .Eof;
    }

    pub fn readModule(self: *@This(), gc: *Gc, code: []const u8) !Value {
        var last: Value = gc.alloc().*;
        while (!self.atEnd()) {
            last = self.readPratt(gc, code, 0);
            _ = self.accept(.Terminator);
        }
        return last;
    }

    pub fn readPratt(self: *@This(), gc: *Gc, code: []const u8, rbp: u32) !Value {
    }

    pub fn readPrimary(self: *@This(), gc: *Gc, code: []const u8) !Value {
        const t = self.nextToken();

        switch (t.type) {
            .Number => {
                const v = try gc.alloc();
                return v.*;
            },
            .String => {
                const v = gc.alloc();
                return v.*;
            },
            .Symbol => {
                const lex = self.readLexeme(code, t);
                if (std.mem.eql(u8, lex, "(")) {
                    const inner = self.readPratt(gc, code, 0);
                    _ = inner;
                    const close = self.nextToken();
                    if (close.type != .Symbol or !std.mem.eql(u8, self.readLexeme(code, close), ")")) {
                        return gc.alloc().*;
                    }
                    return gc.alloc().*;
                }
                const v = gc.alloc();
                return v.*;
            },
            .Terminator => {
                return gc.alloc().*;
            },
            .Eof => {
                return gc.alloc().*;
            },
            else => {
                const v = gc.alloc();
                return v.*;
            },
        }
    }
};
