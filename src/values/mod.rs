use std::{
    default,
    ops::{Add, Index},
};

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
    Array(Vec<Val>),
    Fun(Box<Val>, Box<FnArgs>, Box<FnBody>),
}

impl ToString for Val {
    fn to_string(&self) -> String {
        match self {
            Val::None => "none".to_string(),
            Val::Number(n) => n.to_string(),
            Val::Atom(a) => a.to_string(),
            Val::Str(s) => s.clone(),
            Val::Bool(true) => "#t".to_string(),
            Val::Bool(false) => "#f".to_string(),
            Val::List(ls) => {
                let mut s = "(".to_string();
                ls.iter().enumerate().for_each(|(i, x)| {
                    s.push_str(&x.to_string());
                    if i < ls.len() - 1 {
                        s.push_str(" ")
                    }
                });
                s.push_str(")");
                s
            }
            Val::Array(ls) => {
                let mut s = "[".to_string();
                ls.iter().for_each(|x| s.push_str(&x.to_string()));
                s.push_str("]");
                s
            }
            Val::Fun(ident, args, _) => {
                format!("fun {}{}", ident.to_string(), args.to_string())
            }
        }
    }
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
