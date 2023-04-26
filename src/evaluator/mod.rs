pub mod prelude;

use std::{
    collections::HashSet,
    env::args,
    fmt::format,
    io::{self, BufRead, stdout, Write},
};

use crate::{env::Env, values::Val};

pub fn eval_function(ident: &str, args: &Vec<Val>, env: &mut Env) -> Val {
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

pub fn eval_function_definition(args: &Vec<Val>, env: &mut Env) -> Val {
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

fn add_operator(args: &Vec<Val>, env: &mut Env) -> Val {
    let mut x = 0.0;
    for a in args {
        match eval(a.clone(), env) {
            Val::Number(n) => x += n,
            _ => panic!("Expected number"),
        }
    }
    Val::num(x)
}

fn sub_operator(args: &Vec<Val>, env: &mut Env) -> Val {
    let mut x = Val::get_num(args[0].clone());
    for i in 1..args.len() {
        match eval(args[i].clone(), env) {
            Val::Number(n) => x -= n,
            _ => panic!("Expected number"),
        }
    }
    Val::num(x)
}

fn mul_operator(args: &Vec<Val>, env: &mut Env) -> Val {
    let mut x = 1.0;
    for a in args {
        match eval(a.clone(), env) {
            Val::Number(n) => x *= n,
            _ => panic!("Expected number"),
        }
    }
    Val::num(x)
}

fn div_operator(args: &Vec<Val>, env: &mut Env) -> Val {
    let mut x = Val::get_num(args[0].clone());
    for i in 1..args.len() {
        match eval(args[i].clone(), env) {
            Val::Number(n) => x /= n,
            _ => panic!("Expected number"),
        }
    }
    Val::num(x)
}

fn do_block(args: &Vec<Val>, env: &mut Env) -> Val {
    let mut result = Val::None;
    for a in args {
        result = eval(a.clone(), env);
    }
    result
}

fn echo(args: &Vec<Val>, env: &mut Env) -> Val {
    let mut res = Val::None;
    for a in args {
        res = eval(a.clone(), env);
        print!("{} ", res.to_string());
    }
    res
}

fn read(args: &Vec<Val>, env: &mut Env) -> Val {
    let stdin = io::stdin();

    if args.len() > 0 {
        print!("{}", args[0].to_string());
        stdout().flush().unwrap();
    }

    match stdin.lock().lines().next() {
        Some(x) => match x {
            Ok(s) => Val::Str(s),
            Err(_) => Val::None,
        },
        None => Val::None,
    }
}

enum Intr {
    Ok(Val),
    Invalid,
}

pub fn eval_intrinsic(intr: &String, args: &Vec<Val>, env: &mut Env) -> Val {
    match handle_intrinsic(&intr, args, env) {
        Intr::Ok(v) => v,
        Intr::Invalid => eval_function(&intr, &args, env),
    }
}

fn handle_intrinsic(intr: &String, args: &Vec<Val>, env: &mut Env) -> Intr {
    match intr.as_str() {
        "do" => Intr::Ok(do_block(args, env)),
        "+" => Intr::Ok(add_operator(args, env)),
        "-" => Intr::Ok(sub_operator(args, env)),
        "*" => Intr::Ok(mul_operator(args, env)),
        "/" => Intr::Ok(div_operator(args, env)),
        "fun" => Intr::Ok(eval_function_definition(args, env)),
        "echo" => Intr::Ok(echo(args, env)),
        "read" => Intr::Ok(read(args, env)),
        _ => Intr::Invalid,
    }
}

pub fn head_tail(list: Vec<Val>) -> (Val, Vec<Val>) {
    let mut args: Vec<Val> = vec![];
    for x in 1..list.len() {
        args.push(list[x].clone());
    }
    (list[0].clone(), args)
}

pub fn eval_list(xs: Vec<Val>, env: &mut Env) -> Val {
    return match head_tail(xs) {
        (Val::Atom(atom), args) => eval_intrinsic(&atom, &args, env),
        _ => panic!("Not yet implemented"),
    };
}

pub fn eval(val: Val, env: &mut Env) -> Val {
    match val {
        Val::Number(_) | Val::Bool(_) | Val::Str(_) | Val::Fun(_, _, _) | Val::None => val,
        Val::Atom(v) => env.find(v).map_or(Val::None, |v| v),
        Val::List(xs) => eval_list(xs, env),
    }
}
