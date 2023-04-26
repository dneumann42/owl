use std::{default, ops::Index};

type FnArgs = Val; // List
type FnBody = Val; // Do block

#[derive(Debug, Clone, PartialEq)]
pub enum Val {
    None,
    Number(f64),
    Atom(String),
    Str(String),
    Bool(bool),
    List(Vec<Val>),
    Fun(Box<Val>, Box<FnArgs>, Box<FnBody>),
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

    pub fn get_str(v: Val) -> String {
        match v {
            Val::Str(s) => s,
            Val::Atom(a) => a,
            _ => "".to_string(),
        }
    }

    pub fn len(v: Val) -> usize {
        match v {
            Val::List(xs) => xs.len(),
            Val::Str(s) => s.len(),
            Val::Atom(a) => a.len(),
            _ => 0,
        }
    }

    pub fn index(v: Val, idx: usize) -> Val {
        match v {
            Val::Atom(a) => a
                .chars()
                .nth(idx.into())
                .map_or(Val::None, |v| Val::Str(v.to_string())),
            Val::Str(s) => s
                .chars()
                .nth(idx.into())
                .map_or(Val::None, |v| Val::Str(v.to_string())),
            Val::List(l) => l.get(idx).map_or(Val::None, Val::clone),
            _ => Val::None,
        }
    }

    pub fn num<T: Into<f64>>(s: T) -> Val {
        Val::Number(s.into())
    }

    pub fn str<T: ToString>(s: T) -> Val {
        Val::Str(s.to_string())
    }

    pub fn list(s: Vec<Val>) -> Val {
        Val::List(s)
    }

    pub fn t() -> Val {
        Val::Bool(true)
    }

    pub fn f() -> Val {
        Val::Bool(false)
    }
}
