use std::fmt::format;

pub type List = Vec<Box<Val>>;
pub type Do = Vec<Box<Val>>;
pub type Block = Vec<Box<Val>>;
pub type Assignment = (Box<Val>, Box<Val>);
pub type UnOp = (String, Box<Val>);
pub type BinOp = (String, Box<Val>, Box<Val>);

#[derive(Debug, Clone, PartialEq)]
pub enum Val {
    None,
    Num(f64),
    Bool(bool),
    Str(String),
    Ident(String),
    List(List),
    Do(Do),
    Block(Block),
    Assignment(Assignment),
    BinOp(BinOp),
    UnOp(UnOp),
}

impl Val {
    pub fn is_stmt(&self) -> bool {
        match self {
            Val::Assignment(_) => true,
            Val::Block(_) => true,
            _ => false,
        }
    }

    pub fn num<N: Into<f64>>(n: N) -> Val {
        Val::Num(n.into())
    }

    pub fn t() -> Val {
        Val::Bool(true)
    }

    pub fn f() -> Val {
        Val::Bool(false)
    }

    pub fn binop<S: Into<String>>(s: S, ls: Val, rs: Val) -> Val {
        Val::BinOp((s.into(), Box::new(ls), Box::new(rs)))
    }

    pub fn unop<S: Into<String>>(s: S, v: Val) -> Val {
        Val::UnOp((s.into(), Box::from(v)))
    }

    pub fn id<S: Into<String>>(s: S) -> Val {
        Val::Ident(s.into())
    }

    pub fn assn(id: Val, val: Val) -> Val {
        Val::Assignment((Box::from(id), Box::new(val)))
    }
}

pub fn num<N: Into<f64>>(n: N) -> Val {
    Val::num(n)
}

pub fn t() -> Val {
    Val::t()
}

pub fn f() -> Val {
    Val::f()
}

pub fn binop<S: Into<String>>(s: S, ls: Val, rs: Val) -> Val {
    Val::binop(s, ls, rs)
}

pub fn unop<S: Into<String>>(s: S, v: Val) -> Val {
    Val::unop(s, v)
}

pub fn id<S: Into<String>>(s: S) -> Val {
    Val::id(s)
}

pub fn assn(id: Val, val: Val) -> Val {
    Val::assn(id, val)
}

impl ToString for Val {
    fn to_string(&self) -> String {
        match self {
            Val::Num(n) => n.to_string(),
            Val::Bool(b) => b.to_string(),
            Val::UnOp((a, b)) => {
                format!("{}{}", a.to_string(), b.to_string())
            }
            v => format!("{:?}", v),
        }
    }
}

impl From<f64> for Val {
    fn from(value: f64) -> Self {
        Val::Num(value)
    }
}

impl From<bool> for Val {
    fn from(bool: bool) -> Self {
        Val::Bool(bool)
    }
}

impl From<List> for Val {
    fn from(value: List) -> Self {
        Val::List(value)
    }
}

impl From<Assignment> for Val {
    fn from(value: Assignment) -> Self {
        Val::Assignment(value)
    }
}

pub fn is_none(v: &Val) -> bool {
    matches!(v, &Val::None)
}

pub fn not_none(v: &Val) -> bool {
    !is_none(v)
}
