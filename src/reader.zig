// Version 1 of the reader

const v = @import("values.zig");
const std = @import("std");
const gc = @import("gc.zig");
const ascii = std.ascii;
const print = std.debug.print;

const ParseError = error{ NoMatch, DefMissingIdentifier, DefMissingValue, Invalid, MemoryError, InvalidRecord, InvalidKeyValue, MissingClosingBrace, MissingClosingBracket, MissingComma, MissingEnd, MissingElif, DotMissingIdentifer, CallMissingParameters };

const ExpressionBlockPair = struct {
    expression: *v.Value,
    block: *v.Value,
    // used to check if we continue reading the chain
    // example: 'elif' keeps reading, 'end' will not
    terminalKeyboard: []const u8,
};

pub const Reader = struct {
    gc: *gc.Gc,
    code: []const u8,
    it: usize,
    end: usize,

    pub fn init(g: *gc.Gc) Reader {
        return Reader{ .gc = g, .code = "", .it = 0, .end = 0 };
    }

    pub fn deinit(self: *Reader, val: *v.Value) void {
        switch (val.*) {
            .cons => {
                var it: ?*v.Value = val;
                while (it != null) {
                    if (it) |value| {
                        it = value.cons.cdr;
                        if (value.cons.car) |idx_value| {
                            self.deinit(idx_value);
                        }
                    }
                }
            },
            else => {},
        }
    }

    pub fn load(self: *Reader, code: []const u8) void {
        self.code = code;
        self.it = 0;
        self.end = code.len;
    }

    pub fn initLoad(g: *gc.Gc, code: []const u8) Reader {
        var reader = Reader.init(g);
        reader.load(code);
        return reader;
    }

    pub fn skipWhitespace(self: *Reader) void {
        while (!self.atEof() and ascii.isWhitespace(self.chr())) {
            self.next();
        }
    }

    pub fn skipComment(self: *Reader) void {
        self.skipWhitespace();
        if (self.chr() != ';') {
            return;
        }
        while (!self.atEof() and self.chr() != '\n') {
            self.next();
        }
        self.skipComment();
    }

    pub fn next(self: *Reader) void {
        self.it += 1;
    }

    pub fn chr(self: *Reader) u8 {
        if (self.atEof())
            return 0;
        return self.code[self.it];
    }

    pub fn atEof(self: *Reader) bool {
        return self.it >= self.end;
    }

    // program = {expression};
    pub fn readProgram(self: *Reader) ParseError!*v.Value {
        const start = self.it;
        var it: ?*v.Value = v.cons(self.gc, self.gc.create(.{ .symbol = "do" }) catch null, null);
        while (!self.atEof() and it != null) {
            const expr = self.readExpression() catch {
                self.it = start;
                break;
            };
            it = v.cons(self.gc, expr, it);
            self.skipWhitespace();
            if (self.atEof())
                break;
        }

        if (it) |xs| {
            return xs.reverse();
        }
        return error.NoMatch;
    }

    // expression = logical_or
    pub fn readExpression(self: *Reader) ParseError!*v.Value {
        self.skipComment();
        return self.readBinaryLogicalOr();
    }

    pub fn readBinaryExpression2(
        self: *Reader,
        operators: []const []const u8,
        left_parse: fn (self: *Reader) ParseError!*v.Value,
        right_parse: fn (self: *Reader) ParseError!*v.Value,
    ) ParseError!*v.Value {
        var pin = self.it;

        const left_value = left_parse(self) catch {
            self.it = pin;
            return error.NoMatch;
        };

        self.skipWhitespace();
        pin = self.it;
        const symbol = self.readSymbol(false) catch {
            self.it = pin;
            return left_value;
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
            return left_value;
        }

        self.skipWhitespace();
        const right_value = right_parse(self) catch {
            self.it = pin;
            return left_value;
        };

        switch (right_value.*) {
            v.Value.cons => {
                var op = v.cons(self.gc, null, null);
                op.cons.car = symbol;
                op.cons.cdr = v.cons(self.gc, left_value, v.cons(self.gc, right_value, null));
                return op;
            },
            else => {},
        }

        return v.cons(self.gc, symbol, v.cons(self.gc, left_value, v.cons(self.gc, right_value, null)));
    }

    pub fn readBinaryExpression(
        self: *Reader,
        operator: []const u8,
        left_parse: fn (self: *Reader) ParseError!*v.Value,
        right_parse: fn (self: *Reader) ParseError!*v.Value,
    ) ParseError!*v.Value {
        return readBinaryExpression2(self, &[_][]const u8{operator}, left_parse, right_parse);
    }

    // logical_or = logical_and, {"or", logical_or};
    pub fn readBinaryLogicalOr(self: *Reader) ParseError!*v.Value {
        return self.readBinaryExpression2(&[_][]const u8{"or"}, Reader.readBinaryLogicalAnd, Reader.readBinaryLogicalOr);
    }

    // logical_and = equality, {"and", logical_and};
    pub fn readBinaryLogicalAnd(self: *Reader) ParseError!*v.Value {
        return self.readBinaryExpression2(&[_][]const u8{"and"}, Reader.readEquality, Reader.readBinaryLogicalAnd);
    }

    // equality = comparison, {("==" | "!="), equality};
    pub fn readEquality(self: *Reader) ParseError!*v.Value {
        if (self.readBinaryExpression2(&[_][]const u8{ "eq", "not-eq" }, Reader.readComparison, Reader.readEquality)) |n| {
            return n;
        } else |_| {}

        return error.NoMatch;
    }

    // comparison = additive, {("<" | ">" | "<=" | ">="), comparison};
    pub fn readComparison(self: *Reader) ParseError!*v.Value {
        if (self.readBinaryExpression2(&[_][]const u8{ "<", ">", "<=", ">=" }, Reader.readAdditive, Reader.readComparison)) |n| {
            return n;
        } else |_| {}

        return error.NoMatch;
    }

    // additive = multiplicative, {("+" | "-"), additive}
    pub fn readAdditive(self: *Reader) ParseError!*v.Value {
        if (self.readBinaryExpression2(&[_][]const u8{ "+", "-" }, Reader.readMultiplicative, Reader.readAdditive)) |n| {
            return n;
        } else |_| {}

        return error.NoMatch;
    }

    // multiplicative = unary, {("*" | "/"), multiplicative};
    pub fn readMultiplicative(self: *Reader) ParseError!*v.Value {
        if (self.readBinaryExpression2(&[_][]const u8{ "*", "/" }, Reader.readUnary, Reader.readMultiplicative)) |n| {
            return n;
        } else |_| {}

        return error.NoMatch;
    }

    // unary = unary_operator, primary
    //       | primary;
    pub fn readUnary(self: *Reader) ParseError!*v.Value {
        const start = self.it;
        const op = self.readUnaryOperator() catch {
            self.it = start;
            return self.readPrimary();
        };
        const primary = self.readPrimary() catch {
            self.it = start;
            return error.NoMatch;
        };

        return v.cons(self.gc, op, v.cons(self.gc, primary, null));
    }

    // unary_operator = "-" | "not" | "~" | "'";
    pub fn readUnaryOperator(self: *Reader) ParseError!*v.Value {
        if (self.chr() == '-' or self.chr() == '~' or self.chr() == '\'') {
            const slice = self.code[self.it .. self.it + 1];
            const val = self.gc.create(.{ .symbol = slice }) catch |err| {
                std.debug.panic("Panicked at Error: {any}", .{err});
            };
            self.next();
            return val;
        }

        const pin = self.it;
        const symbol = self.readSymbol(false) catch {
            self.it = pin;
            return error.NoMatch;
        };

        if (!std.mem.eql(u8, symbol.symbol, "not")) {
            self.it = pin;
            return error.NoMatch;
        }

        return symbol;
    }

    // primary = literal
    //         | function_call
    //         | definition
    //         | assignment
    //         | symbol
    //         | list_comprehension
    //         | dict_comprehension
    //         | "(", expression, ")"
    //         | block
    //         | if_expression
    //         | for_expression
    //         | return_expression
    //         | function_definition;
    pub fn readPrimary(self: *Reader) ParseError!*v.Value {
        // if (self.readLiteral()) |value| {
        //     return value;
        // } else |_| {}

        // if (self.readFunctionCall()) |value| {
        //     return value;
        // } else |_| {}

        if (self.readDefinition()) |value| {
            return value;
        } else |_| {}

        if (self.readAssignment()) |value| {
            return value;
        } else |_| {}

        if (self.readDotCall()) |value| {
            return value;
        } else |_| {}

        self.skipWhitespace();
        if (self.chr() == '(') {
            self.next();
            const expr = try self.readExpression();
            self.skipWhitespace();
            if (self.chr() == ')') {
                self.next();
                return expr;
            }
        }

        if (self.readBlock()) |value| {
            return value;
        } else |_| {}

        if (self.readIfExpression()) |value| {
            return value;
        } else |_| {}

        if (self.readCondExpression()) |value| {
            return value;
        } else |_| {}

        // NOTE: we need to check if readSymbol returns a language keyword like 'fun',
        // so we can get to this point
        if (self.readFunctionDefinition()) |value| {
            return value;
        } else |_| {}
        if (self.readFunctionDefinitionAnon()) |value| {
            return value;
        } else |_| {}
        if (self.readLambdaDefinition()) |value| {
            return value;
        } else |_| {}

        // WIP
        return error.NoMatch;
    }

    // Yields no match if the next expression is not
    // a symbol that matches the 'sym' string
    pub fn expectKeyword(self: *Reader, sym: []const u8) ParseError!*v.Value {
        self.skipWhitespace();
        const start = self.it;
        const symbol = self.readSymbol(true) catch {
            self.it = start;
            return error.NoMatch;
        };
        if (!std.mem.eql(u8, symbol.symbol, sym)) {
            self.it = start;
            return error.NoMatch;
        }
        return symbol;
    }

    pub fn nextKeyword(self: *Reader, sym: []const u8) bool {
        const start = self.it;
        self.skipWhitespace();
        const symbol = self.readSymbol(true) catch {
            self.it = start;
            return false;
        };
        self.it = start;
        return std.mem.eql(u8, symbol.symbol, sym);
    }

    // function_definition = "fun", identifier, parameter_list, ["->" type], block;
    pub fn readFunctionDefinition(self: *Reader) ParseError!*v.Value {
        const start = self.it;
        _ = try self.expectKeyword("fun");

        self.skipWhitespace();
        const literal = self.readSymbol(false) catch {
            self.it = start;
            return error.NoMatch;
        };

        const params = self.readParameterList() catch {
            self.it = start;
            return error.NoMatch;
        };

        const body = self.readBlockTillEnd() catch {
            self.it = start;
            return error.NoMatch;
        };

        return self.gc.create(.{ .function = .{ .name = literal, .body = body, .params = params, .env = self.gc.env() } }) catch {
            return error.NoMatch;
        };
    }

    // function_definition = "fun", parameter_list, ["->" type], block;
    pub fn readFunctionDefinitionAnon(self: *Reader) ParseError!*v.Value {
        const start = self.it;
        _ = try self.expectKeyword("fun");
        self.skipWhitespace();

        const params = self.readParameterList() catch {
            self.it = start;
            return error.NoMatch;
        };

        const body = self.readBlockTillEnd() catch {
            self.it = start;
            return error.NoMatch;
        };

        return self.gc.create(.{ .function = .{
            .name = null,
            .body = body,
            .params = params,
            .env = self.gc.env(),
        } }) catch {
            return error.NoMatch;
        };
    }

    pub fn readLambdaDefinition(self: *Reader) ParseError!*v.Value {
        const start = self.it;
        _ = try self.expectKeyword("fn");
        self.skipWhitespace();

        if (self.chr() != '(') {
            self.it = start;
            // TODO: return proper error, same with rest of no matches
            return error.NoMatch;
        }
        const params = self.readParameterList() catch {
            self.it = start;
            return error.NoMatch;
        };
        const body = self.readExpression() catch {
            self.it = start;
            return error.NoMatch;
        };
        return self.gc.create(.{ .function = .{ .name = null, .body = body, .params = params, .env = self.gc.env() } }) catch {
            self.it = start;
            return error.NoMatch;
        };
    }

    // parameter_list = "(", [parameter, {",", parameter}], ")";
    pub fn readParameterList(self: *Reader) ParseError!*v.Value {
        self.skipWhitespace();

        var it: ?*v.Value = null;
        var first = true;

        self.next(); // skips the '('

        while (!self.atEof()) {
            self.skipWhitespace();

            if (self.chr() == ')') {
                self.next();
                break;
            }

            if (self.chr() == ',' and !first) {
                self.next();
            } else if (!first) {
                std.log.err("Expected ',' but got '{c}'\n", .{self.chr()});
                return error.MissingComma;
            }

            const start = self.it;
            const expr = self.readExpression() catch {
                self.it = start;
                return error.Invalid;
            };

            it = v.cons(self.gc, expr, it);
            first = false;
        }

        if (it) |list| {
            return list.reverse();
        }

        return v.cons(self.gc, null, null);
    }

    // parameter = identifier, ":", type;
    pub fn readParameter() v.Value {}

    // type = simple_type | list_type | dict_type;
    pub fn readType() v.Value {}

    // simple_type = "int" | "float" | "str" | "bool";
    pub fn readSimpleType() v.Value {}

    // list_type = "list", "[", type, "]";
    pub fn readListType() v.Value {}

    // dict_type = "dict", "[", type, ",", type, "]";
    pub fn readDictType() v.Value {}

    pub fn readBlockTillEnd(self: *Reader) ParseError!*v.Value {
        var it: ?*v.Value = v.cons(self.gc, self.gc.create(.{ .symbol = "do" }) catch unreachable, null);
        const start = self.it;

        while (!self.atEof() and it != null) {
            self.skipComment();

            if (self.atEof()) {
                std.debug.print("Missing closing 'end'.\n", .{});
                return error.NoMatch;
            }

            const expr = self.readExpression() catch |e| {
                self.it = start;
                return e;
            };

            switch (expr.*) {
                v.Value.symbol => {
                    if (std.mem.eql(u8, expr.symbol, "end")) {
                        break;
                    }
                },
                else => {
                    it = v.cons(self.gc, expr, it);
                },
            }
        }

        if (it) |xs| {
            return xs.reverse();
        }

        return error.NoMatch;
    }

    // block = "do", {expression}, "end";
    pub fn readBlock(self: *Reader) ParseError!*v.Value {
        const start = self.it;
        _ = try self.expectKeyword("do");
        return self.readBlockTillEnd() catch {
            self.it = start;
            return error.NoMatch;
        };
    }

    // definition = identifier, [":=", [":" type "="]], expression;
    pub fn readDefinition(self: *Reader) ParseError!*v.Value {
        self.skipWhitespace();
        const start = self.it;
        const symbol = self.readSymbol(false) catch {
            return error.NoMatch;
        };

        self.skipWhitespace();
        if (self.chr() != ':') {
            self.it = start;
            return error.NoMatch;
        }
        self.next();
        if (self.chr() != '=') {
            self.it = start;
            return error.NoMatch;
        }
        self.next();

        // TODO: [":", type]

        const expression = self.readExpression() catch {
            return error.DefMissingValue;
        };

        return v.cons(self.gc, self.gc.sym("def"), v.cons(self.gc, symbol, v.cons(self.gc, expression, null)));
    }

    // assignment = expression, "=", expression
    pub fn readAssignment(self: *Reader) ParseError!*v.Value {
        self.skipComment();
        const start = self.it;
        const left = self.readSymbol(false) catch {
            return error.NoMatch;
        };
        self.skipWhitespace();
        if (self.chr() != '=') {
            self.it = start;
            return error.NoMatch;
        }
        self.next();
        const expression = self.readExpression() catch {
            return error.DefMissingValue;
        };

        return v.cons(self.gc, self.gc.sym("set"), v.cons(self.gc, left, v.cons(self.gc, expression, null)));
    }

    // if_expression = "if", expression, "then", expression, (["elif", expression, "then", expression] | ["else", expression]), "end";
    pub fn readIfExpression(self: *Reader) ParseError!*v.Value {
        const start = self.it;
        const condsym = self.gc.sym("cond");

        var list = v.cons(self.gc, condsym, null);

        _ = self.expectKeyword("if") catch |e| {
            self.it = start;
            return e;
        };

        const if_cond = try self.readExpression();

        _ = try self.expectKeyword("then");

        var if_exp_do = v.cons(self.gc, self.gc.sym("do"), null);
        while (!self.atEof()) {
            const exp = try self.readExpression();
            if_exp_do = v.cons(self.gc, exp, if_exp_do);
            if (self.nextKeyword("elif") or self.nextKeyword("else") or self.nextKeyword("end")) {
                break;
            }
        }

        list = v.cons(self.gc, v.cons(self.gc, if_cond, if_exp_do.reverse()), list);

        while (!self.atEof()) {
            if (self.nextKeyword("else")) {
                _ = try self.readSymbol(true);

                var xs = v.cons(self.gc, self.gc.sym("do"), null);
                while (!self.atEof()) {
                    const exp = try self.readExpression();
                    xs = v.cons(self.gc, exp, xs);
                    if (self.nextKeyword("end")) {
                        break;
                    }
                }

                _ = self.expectKeyword("end") catch |e| {
                    if (e == error.NoMatch) {
                        return error.MissingEnd;
                    }
                    return e;
                };

                list = v.cons(self.gc, v.cons(self.gc, self.gc.T(), xs.reverse()), list);
                return list.reverse();
            }

            if (self.nextKeyword("end")) {
                _ = try self.readSymbol(true);
                return list.reverse();
            }

            _ = self.expectKeyword("elif") catch |e| {
                if (e == error.NoMatch) {
                    return error.MissingElif;
                }
                return e;
            };

            const cond = try self.readExpression();
            _ = try self.expectKeyword("then");

            var xs = v.cons(self.gc, self.gc.sym("do"), null);
            while (!self.atEof()) {
                const exp = try self.readExpression();
                xs = v.cons(self.gc, exp, xs);
                if (self.nextKeyword("elif") or self.nextKeyword("else") or self.nextKeyword("end")) {
                    break;
                }
            }
            list = v.cons(self.gc, v.cons(self.gc, cond, xs.reverse()), list);
        }

        return list.reverse();
    }

    pub fn readCondExpression(self: *Reader) ParseError!*v.Value {
        const condsym = try self.expectKeyword("cond");

        var list = v.cons(self.gc, condsym, null);

        while (!self.atEof()) {
            const condition = try self.readExpression();
            const block = try self.readExpression();

            list = v.cons(self.gc, v.cons(self.gc, condition, block), list);

            const s = self.expectKeyword("end") catch self.gc.nothing();
            switch (s.*) {
                .nothing => {
                    continue;
                },
                else => {
                    break;
                },
            }
        }

        return list.reverse();
    }

    // for_expression = "for", identifier, "in", expression, "do", expression;
    pub fn readForExpression() v.Value {}

    // return_expression = "return", expression;
    pub fn readReturnExpression() v.Value {}

    // function_call = symbol, parameter_list;
    pub fn readFunctionCall(self: *Reader) ParseError!*v.Value {
        self.skipWhitespace();
        const start = self.it;

        const symbol = self.readSymbol(false) catch {
            self.it = start;
            return error.NoMatch;
        };
        self.skipWhitespace();
        if (self.atEof() or self.chr() != '(') {
            self.it = start;
            return error.NoMatch;
        }

        const args = self.readParameterList() catch {
            self.it = start;
            return error.NoMatch;
        };

        return v.cons(self.gc, symbol, args);
    }

    // dot_call_chain = callable, []
    pub fn readDotCall(self: *Reader) ParseError!*v.Value {
        // starting node
        const start = self.it;
        var callable = self.readCallable() catch {
            self.it = start;
            return error.NoMatch;
        };

        self.skipWhitespace();
        if (self.chr() != '.' and self.chr() != '(') {
            return callable;
        }

        while (self.chr() == '.' or self.chr() == '(') {
            if (self.chr() == '.') {
                self.next();
                const sym = self.readSymbol(false) catch {
                    return error.DotMissingIdentifer;
                };
                callable = v.cons(self.gc, self.gc.sym("."), v.cons(self.gc, callable, v.cons(self.gc, sym, null)));
            } else if (self.chr() == '(') {
                const args = self.readParameterList() catch {
                    return error.CallMissingParameters;
                };
                callable = v.cons(self.gc, callable, args);
            }
        }

        return callable;
    }

    // callable = symbol | literal, {"(", expression, ")"};
    pub fn readCallable(self: *Reader) ParseError!*v.Value {
        if (self.readLiteral()) |value| {
            return value;
        } else |_| {}
        if (self.readSymbol(false)) |value| {
            return value;
        } else |_| {}
        // TODO: handle paren wrapped expression
        return error.NoMatch;
    }

    // literal = number | string | boolean | list | dictionary;
    pub fn readLiteral(self: *Reader) ParseError!*v.Value {
        self.skipWhitespace();
        const start = self.it;
        return self.readNumber() catch
            self.readString() catch
            self.readBoolean() catch
            self.readList() catch
            self.readDictionary() catch {
            self.it = start;
            return error.NoMatch;
        };
    }

    // number = float = digit, {digit}, ".", digit, {digit};
    pub fn readNumber(self: *Reader) ParseError!*v.Value {
        // for now I just read integers
        if (!ascii.isDigit(self.chr())) {
            return error.NoMatch;
        }
        const start = self.it;
        while (!self.atEof() and ascii.isDigit(self.chr())) {
            self.next();
        }
        if (start == self.it) {
            return error.NoMatch;
        }
        const slice = self.code[start..self.it];
        const number: f64 = std.fmt.parseFloat(f64, slice) catch |err| {
            std.debug.panic("Panicked at Error: {any}", .{err});
        };
        return self.gc.create(.{ .number = number }) catch |err| {
            std.debug.panic("Panicked at Error: {any}", .{err});
        };
    }

    // string = '"', {any_character}, '"';
    pub fn readString(self: *Reader) ParseError!*v.Value {
        if (self.chr() != '"') {
            return error.NoMatch;
        }
        const start = self.it + 1;
        while (!self.atEof()) {
            self.next();
            if (self.chr() == '"') {
                self.next();
                break;
            }
        }
        const s = self.code[start .. self.it - 1];
        const buffer = convertEscapeSequences(self.gc.allocator, s) catch unreachable;
        return self.gc.create(.{ .string = buffer }) catch |err| {
            std.debug.panic("Panicked at Error: {any}", .{err});
        };
    }

    // boolean = "true" | "false";
    pub fn makeBoolean(self: *Reader, b: bool) *v.Value {
        return self.gc.create(.{ .boolean = b }) catch |err| {
            std.debug.panic("Panicked at Error: {any}", .{err});
        };
    }
    pub fn readBoolean(self: *Reader) ParseError!*v.Value {
        const start = self.it;
        const sym = self.readSymbol(false) catch |err| switch (err) {
            else => {
                self.it = start;
                return error.NoMatch;
            },
        };
        defer self.deinit(sym);
        return switch (sym.*) {
            .symbol => |s| if (std.mem.eql(u8, s, "true"))
                self.makeBoolean(true)
            else if (std.mem.eql(u8, s, "false"))
                self.makeBoolean(false)
            else {
                self.it = start;
                return error.NoMatch;
            },
            else => {
                self.it = start;
                return error.NoMatch;
            },
        };
    }

    // list = "[", [expression, {",", expression}], "]";
    pub fn readList(self: *Reader) ParseError!*v.Value {
        if (self.chr() != '[') {
            return error.NoMatch;
        }

        self.next();
        self.skipWhitespace();

        if (self.chr() == ']') {
            self.next();
            return v.cons(self.gc, self.gc.sym("list"), null);
        }

        var it: ?*v.Value = null;
        while (!self.atEof()) {
            const val = try self.readExpression();
            it = v.cons(self.gc, val, it);

            self.skipComment();
            if (self.chr() == ']') {
                self.next();
                break;
            } else if (self.chr() == ',') {
                self.next();
            } else if (self.atEof()) {
                return error.MissingClosingBracket;
            } else {
                return error.MissingComma;
            }
        }

        if (it) |xs| {
            return v.cons(self.gc, self.gc.sym("list"), xs);
        }

        return v.cons(self.gc, self.gc.sym("list"), null);
    }

    // dictionary = "{", [key_value_pair, {",", key_value_pair}], "}";
    pub fn readDictionary(self: *Reader) ParseError!*v.Value {
        if (self.chr() != '{') {
            return error.NoMatch;
        }
        self.next();

        var it: ?*v.Value = v.cons(self.gc, self.gc.sym("dict"), null);
        while (!self.atEof()) {
            const kv = self.readKeyValuePair() catch |err| {
                switch (err) {
                    error.NoMatch => break,
                    else => return err,
                }
            };

            it = v.cons(self.gc, kv, it);

            self.skipWhitespace();

            if (self.chr() == '}') {
                self.next();
                break;
            }

            if (self.atEof()) {
                return error.MissingClosingBrace;
            }
        }

        if (it) |xs| {
            const list = xs.reverse();

            var map = v.Dictionary.init(self.gc) catch return error.MemoryError;

            var it2: ?*v.Value = list.cons.cdr;
            while (it2 != null) : (it2 = it2.?.cons.cdr) {
                const pair = it2.?.cons.car orelse continue;
                const key = pair.cons.car orelse unreachable;
                const value = pair.cons.cdr orelse unreachable;
                map.put(key, value) catch return error.MemoryError;
            }

            // TODO: dictionaries have both keys and values that need to be evaluated
            // I could add a flag marking it as evaluated or have this function
            // return the `dict` special form instead
            return v.cons(self.gc, self.gc.sym("dict"), self.gc.create(.{ .dictionary = map }) catch return error.MemoryError);
        }

        return error.NoMatch;
    }

    // key_value_pair = (((".", symbol) | string)) | ("[", expression, "]")), expression, ("," | "\n");
    pub fn readKeyValuePair(self: *Reader) ParseError!*v.Value {
        self.skipComment();

        const start = self.it;

        // TODO: handle ("[", expression, "]")
        if (self.chr() != '.') {
            return error.NoMatch;
        }

        self.next();

        // I may be able to read owl keywords also, allow for owl keyword dictionary keys
        const key = self.readSymbol(false) catch self.readString() catch {
            self.it = start;
            return error.NoMatch;
        };

        const value = self.readExpression() catch {
            self.it = start;
            return error.NoMatch;
        };

        self.skipWhitespace();
        if (self.chr() == '\n') {
            self.skipWhitespace();
        } else if (self.chr() == ',') {
            self.next();
        }

        return v.cons(self.gc, key, value);
    }

    // symbol
    pub fn isOwlKeyword(sym: []const u8) bool {
        if (std.mem.eql(u8, sym, "fun")) return true;
        if (std.mem.eql(u8, sym, "fn")) return true;
        if (std.mem.eql(u8, sym, "if")) return true;
        if (std.mem.eql(u8, sym, "then")) return true;
        if (std.mem.eql(u8, sym, "else")) return true;
        if (std.mem.eql(u8, sym, "for")) return true;
        if (std.mem.eql(u8, sym, "do")) return true;
        if (std.mem.eql(u8, sym, "cond")) return true;
        return false;
    }

    pub fn readSymbol(reader: *Reader, readkeywords: bool) ParseError!*v.Value {
        const start = reader.it;
        if (ascii.isDigit(reader.chr())) {
            return error.NoMatch;
        }
        while (!reader.atEof() and !ascii.isWhitespace(reader.chr()) and Reader.validSymbolCharacter(reader.chr())) {
            reader.next();
        }
        if (reader.it == start) {
            return error.NoMatch;
        }
        const sym = reader.code[start..reader.it];
        if (!readkeywords and isOwlKeyword(sym)) {
            reader.it = start;
            return error.NoMatch;
        }
        return reader.gc.create(.{ .symbol = sym }) catch |err| {
            std.debug.panic("Panicked at Error: {any}", .{err});
        };
    }

    pub fn validSymbolCharacter(ch: u8) bool {
        return switch (ch) {
            '+', '/', '*', '%', '$', '-', '>', '<', '=' => true,
            else => ascii.isAlphanumeric(ch),
        };
    }
};

pub fn read(allocator: std.mem.Allocator, code: []const u8) v.Value {
    return Reader.initLoad(allocator, code).readProgram();
}

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
