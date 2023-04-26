pub mod prelude;

use std::{env::args, fmt::format};

use crate::{env::Env, values::Val};

pub fn eval_function(ident: &str, args: Vec<Val>, env: &mut Env) -> Val {
    match env.find(ident.to_string()) {
        Some(Val::Fun(_, params, body)) => match params.as_ref() {
            Val::List(ps) => {
                let mut res: Val = Val::None;
                env.push();
                for (idx, x) in ps.iter().enumerate() {
                    let _ = env.set(
                        Val::get_str(x.clone()),
                        args.get(idx).map_or(Val::None, Val::clone),
                    );
                }
                res = eval(body.as_ref().clone(), env);
                env.pop();
                res
            }
            _ => panic!("Never"),
        },
        _ => {
            println!("Undefined identifier: {:?}", ident);
            Val::None
        }
    }
}

pub fn eval_function_definition(args: Vec<Val>, env: &mut Env) -> Val {
    let ident = args[0].clone();
    let params = &args[1];

    let mut body: Vec<Val> = vec![Val::atom("do")];
    for p in &args[2..] {
        body.push(p.clone())
    }

    env.set(
        Val::get_str(ident.clone()),
        Val::Fun(
            Box::new(ident),
            Box::new(params.clone()),
            Box::new(Val::list(body.clone())),
        ),
    )
}

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
        "fun" => eval_function_definition(args, env),
        ident => eval_function(ident, args, env),
    }
}

pub fn eval(val: Val, env: &mut Env) -> Val {
    match val {
        Val::Number(_) | Val::Bool(_) | Val::Str(_) | Val::Fun(_, _, _) | Val::None => val,
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
