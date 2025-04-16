const std = @import("std");
const ascii = std.ascii;

pub const ReaderError = error{ Invalid, MissingClosingParenthesis };

pub const AstValue = union(enum) {
    number: f64,
    symbol: []const u8,
    string: []const u8,
    boolean: bool,
    list: std.ArrayList(*Ast),
};

pub const Ast = struct { value: AstValue, index: usize };

pub fn debugPrint(node: *const Ast) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    std.debug.print("{s}\n", .{toString(node, arena.allocator()) catch "error"});
}

pub fn isSymbolCharacter(chr: u8) bool {
    return ascii.isAlphanumeric(chr) or switch (chr) {
        '+', '-', '*', '%', '$', '>', '<', '=' => true,
        else => false,
    };
}

pub fn toString(node: *const Ast, allocator: std.mem.Allocator) ![]const u8 {
    return switch (node.*.value) {
        .boolean => |b| std.fmt.allocPrint(allocator, "{s}", .{if (b) "#t" else "#f"}),
        .number => |n| std.fmt.allocPrint(allocator, "{d}", .{n}),
        .string => |s| std.fmt.allocPrint(allocator, "\"{s}\"", .{s}),
        .symbol => |s| std.fmt.allocPrint(allocator, "{s}", .{s}),
        .list => |xs| {
            var strs = std.ArrayList([]const u8).init(allocator);
            defer strs.deinit();
            try strs.append("(");

            var i: usize = 0;
            for (xs.items) |item| {
                const str = try toString(item, allocator);
                try strs.append(str);
                if (i < xs.items.len - 1) {
                    try strs.append(" ");
                }
                i += 1;
            }

            try strs.append(")");
            return std.mem.join(allocator, "", strs.items);
        },
    };
}

pub const Reader = struct {
    const Self = @This();
    allocator: std.mem.Allocator,

    it: usize,
    code: []const u8,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .code = "",
            .it = 0,
            .allocator = allocator,
        };
    }

    pub fn load(self: *Reader, code: []const u8) void {
        self.it = 0;
        self.code = code;
    }

    pub fn ast(self: *Reader, value: AstValue) error{OutOfMemory}!*Ast {
        const node = try self.allocator.create(Ast);
        node.*.value = value;
        return node;
    }

    pub fn atEof(self: Reader) bool {
        return self.it >= self.code.len;
    }

    pub fn chr(self: Reader) u8 {
        return self.chrN(0);
    }

    pub fn chrN(self: Reader, add: usize) u8 {
        if (self.it + add >= self.code.len) {
            return 0;
        }
        return self.code[self.it + add];
    }

    pub fn next(self: *Reader) void {
        self.nextN(1);
    }

    pub fn nextN(self: *Reader, add: usize) void {
        self.it += add;
    }

    pub fn skipWhitespace(self: *Reader) void {
        while (!self.atEof() and ascii.isWhitespace(self.chr())) {
            self.it += 1;
        }
    }

    pub fn read(self: *Reader) error{ Invalid, InvalidCharacter, MissingClosingParenthesis, OutOfMemory }!*Ast {
        var xs = std.ArrayList(*Ast).init(self.allocator);
        try xs.append(try self.ast(.{ .symbol = "do" }));

        while (!self.atEof()) {
            try xs.append(try self.readNode());
        }

        return self.ast(.{ .list = xs });
    }

    pub fn readNode(self: *Reader) error{ Invalid, InvalidCharacter, MissingClosingParenthesis, OutOfMemory }!*Ast {
        self.skipWhitespace();

        if (self.chr() == '(') {
            self.next();

            var list = std.ArrayList(*Ast).init(self.allocator);
            while (!self.atEof() and self.chr() != ')') {
                const node = try self.readNode();
                try list.append(node);

                self.skipWhitespace();
                if (self.chr() == ')') {
                    self.next();
                    break;
                }
                if (self.atEof()) {
                    return error.MissingClosingParenthesis;
                }
            }

            return self.ast(.{ .list = list });
        }

        if (ascii.isDigit(self.chr())) {
            const start = self.it;
            while (!self.atEof() and ascii.isDigit(self.chr())) {
                self.next();
            }
            const d = try std.fmt.parseFloat(f64, self.code[start..self.it]);
            return self.ast(.{ .number = d });
        }

        if (self.chr() == '#' and self.chrN(1) == 'f') {
            self.nextN(2);
            return self.ast(.{ .boolean = false });
        }

        if (self.chr() == '#' and self.chrN(1) == 't') {
            self.nextN(2);
            return self.ast(.{ .boolean = true });
        }

        if (isSymbolCharacter(self.chr())) {
            const start = self.it;
            while (!self.atEof() and isSymbolCharacter(self.chr())) {
                self.it += 1;
            }
            return self.ast(.{ .symbol = self.code[start..self.it] });
        }

        std.log.err("Failed to match expression", .{});
        return error.Invalid;
    }
};
