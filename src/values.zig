pub const ValueType = enum { number, string, symbol, boolean, list };

pub const Cons = struct { car: *Value, cdr: *Value };

pub const Value = union(ValueType) {
    number: f64,
    string: *const []u8,
    symbol: *const []u8, // TODO intern
    boolean: bool,
    list: Cons,
};
