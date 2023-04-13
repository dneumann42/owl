pub mod prelude;

use std::env::args;

use crate::{env::Env, values::Val};

pub fn eval_intrinsic(intr: String, args: Vec<Val>, env: &mut Env) -> Val {
    match intr.as_str() {
        "do" => {
            let mut result = Val::None;
            for a in args {
                result = eval(a, env);
            }
            result
        }
        "+" => {
            let mut x = 0.0;
            for a in args {
                match eval(a, env) {
                    Val::Number(n) => x += n,
                    _ => panic!("Expected number"),
                }
            }
            Val::num(x)
        }
        "-" => {
            let mut x = Val::get_num(args[0].clone());
            for i in 1..args.len() {
                match eval(args[i].clone(), env) {
                    Val::Number(n) => x -= n,
                    _ => panic!("Expected number"),
                }
            }
            Val::num(x)
        }
        "*" => {
            let mut x = 1.0;
            for a in args {
                match eval(a, env) {
                    Val::Number(n) => x *= n,
                    _ => panic!("Expected number"),
                }
            }
            Val::num(x)
        }
        "/" => {
            let mut x = Val::get_num(args[0].clone());
            for i in 1..args.len() {
                match eval(args[i].clone(), env) {
                    Val::Number(n) => x /= n,
                    _ => panic!("Expected number"),
                }
            }
            Val::num(x)
        }
        _ => Val::None,
    }
}

pub fn eval(val: Val, env: &mut Env) -> Val {
    match val {
        Val::Number(_) | Val::Bool(_) | Val::Str(_) | Val::Fun(_) | Val::None => val,
        Val::Atom(v) => match env.find(v) {
            Some(v) => v,
            None => Val::None,
        },
        Val::List(xs) => {
            if xs.len() >= 1 {
                let first = xs[0].clone();
                let mut args: Vec<Val> = vec![];

                for x in 1..xs.len() {
                    args.push(xs[x].clone());
                }

                return match first {
                    Val::Atom(atom) => match eval_intrinsic(atom, args, env) {
                        Val::None => Val::None,
                        v => v,
                    },
                    _ => {
                        panic!("Not yet implemented");
                    }
                };
            }
            panic!("Expected values");
        }
    }
}
