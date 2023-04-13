#[derive(Debug, Clone, PartialEq)]
pub enum Val {
    None,
    Number(f64),
    Atom(String),
    Str(String),
    Bool(bool),
    List(Vec<Val>),
    Fun(fn(Val) -> Val),
}

impl Val {
    pub fn atom<T>(s: T) -> Val
    where
        String: From<T>,
    {
        Val::Atom(String::from(s))
    }

    pub fn get_num(v: Val) -> f64 {
        match v {
            Val::Number(n) => n,
            _ => 0.0,
        }
    }

    pub fn num(s: f64) -> Val {
        Val::Number(s)
    }

    pub fn t() -> Val {
        Val::Bool(true)
    }

    pub fn f() -> Val {
        Val::Bool(false)
    }
}
