pub mod prelude;

use std::env::args;

use crate::{env::Env, values::Val};

pub fn eval(val: Val, env: &mut Env) -> Val {
    match val {
        Val::Number(_) | Val::Bool(_) | Val::Fun(_) | Val::None => val,
        Val::Atom(v) => match env.find(v) {
            Some(v) => v,
            None => Val::None,
        },
        Val::List(xs) => {
            if xs.len() >= 1 {
                let mut args: Vec<Val> = vec![];
                for x in 1..xs.len() {
                    let xx = xs[x];
                    args.push(xx);
                }
                return match xs[0] {
                    Val::Atom(atom) => match env.find(atom) {
                        Some(Val::Fun(fun)) => fun(Val::List(args)),
                        None => todo!(),
                        _ => todo!(),
                    },
                    _ => panic!("Expected atom"),
                };
            }
            panic!("Expected values");
        }
    }
}
