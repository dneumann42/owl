use std::io::{self, stdout, BufRead, Write};

use crate::{env::Env, parser::parse, values::Val};

use super::{eval::eval, intrinsic::Intrinsic};

pub struct IDo;
pub struct IPlus;
pub struct ISub;
pub struct IMul;
pub struct IDiv;
pub struct IEcho;
pub struct IRead;
pub struct IDef;
pub struct IFun;
pub struct IEval;
pub struct IAdd;
pub struct ISet;
pub struct IList;

pub enum Intr {
    Ok(Val),
    Invalid,
}

impl Intr {
    pub fn start() -> Self {
        Intr::Invalid
    }

    pub fn intr<I: Intrinsic>(&self, intr: &String, args: &Vec<Val>, env: &mut Env) -> Intr {
        match self {
            Intr::Ok(v) => Intr::Ok(v.clone()),
            Intr::Invalid => {
                if intr == &I::name() {
                    Intr::Ok(I::eval(args, env))
                } else {
                    Intr::Invalid
                }
            }
        }
    }
}

impl Intrinsic for IDo {
    fn name() -> String {
        "do".to_string()
    }

    fn eval(args: &Vec<Val>, env: &mut Env) -> Val {
        let mut result = Val::None;
        for a in args {
            result = super::eval::eval(a.clone(), env);
        }
        result
    }
}

impl Intrinsic for IPlus {
    fn name() -> String {
        "+".to_string()
    }

    fn eval(args: &Vec<Val>, env: &mut Env) -> Val {
        let mut x = 0.0;
        for a in args {
            match eval(a.clone(), env) {
                Val::Number(n) => x += n,
                _ => panic!("Expected number"),
            }
        }
        Val::num(x)
    }
}

impl Intrinsic for ISub {
    fn name() -> String {
        "-".to_string()
    }

    fn eval(args: &Vec<Val>, env: &mut Env) -> Val {
        let mut x = Val::get_num(args[0].clone());
        for i in 1..args.len() {
            match eval(args[i].clone(), env) {
                Val::Number(n) => x -= n,
                _ => panic!("Expected number"),
            }
        }
        Val::num(x)
    }
}

impl Intrinsic for IMul {
    fn name() -> String {
        "*".to_string()
    }

    fn eval(args: &Vec<Val>, env: &mut Env) -> Val {
        let mut x = 1.0;
        for a in args {
            match eval(a.clone(), env) {
                Val::Number(n) => x *= n,
                _ => panic!("Expected number"),
            }
        }
        Val::num(x)
    }
}

impl Intrinsic for IDiv {
    fn name() -> String {
        "/".to_string()
    }

    fn eval(args: &Vec<Val>, env: &mut Env) -> Val {
        let mut x = Val::get_num(args[0].clone());
        for i in 1..args.len() {
            match eval(args[i].clone(), env) {
                Val::Number(n) => x /= n,
                _ => panic!("Expected number"),
            }
        }
        Val::num(x)
    }
}

impl Intrinsic for IEcho {
    fn name() -> String {
        "echo".to_string()
    }

    fn eval(args: &Vec<Val>, env: &mut Env) -> Val {
        let mut res = Val::None;
        for a in args {
            res = eval(a.clone(), env);
            print!("{} ", res.to_string());
        }
        println!();
        res
    }
}

impl Intrinsic for IRead {
    fn name() -> String {
        "read".to_string()
    }

    fn eval(args: &Vec<Val>, env: &mut Env) -> Val {
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
}

impl Intrinsic for IFun {
    fn name() -> String {
        "fun".to_string()
    }

    fn eval(args: &Vec<Val>, env: &mut Env) -> Val {
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
}

impl Intrinsic for IDef {
    fn name() -> String {
        "def".to_string()
    }

    fn eval(args: &Vec<Val>, env: &mut Env) -> Val {
        let ident = args[0].clone();
        let value = &args[1];
        let v = eval(value.clone(), env);
        env.set(Val::get_str(ident.clone()), v)
    }
}

impl Intrinsic for IEval {
    fn name() -> String {
        "eval".to_string()
    }

    fn eval(args: &Vec<Val>, env: &mut Env) -> Val {
        match eval(args[0].clone(), env) {
            Val::Str(s) => {
                let parse = parse(s.as_str());
                let mut env = Env::make();
                match parse {
                    Ok(x) => eval(x, &mut env),
                    Err(_) => {
                        todo!()
                    }
                }
            }
            v => {
                println!("{:?}", v);
                panic!("Expected string");
            }
        }
    }
}

impl Intrinsic for IAdd {
    fn name() -> String {
        "add".to_string()
    }

    fn eval(args: &Vec<Val>, env: &mut Env) -> Val {
        match env.find(args[0].to_string()) {
            Some(Val::Array(xs)) => {
                let mut rs = xs;
                let mut ars = args[1..].to_vec().clone();

                for i in 0..ars.len() {
                    ars[i] = eval(ars[i].clone(), env)
                }

                rs.append(&mut ars);
                env.set(args[0].to_string(), Val::Array(rs.clone()))
            }
            _ => {
                todo!()
            }
        }
    }
}

impl Intrinsic for ISet {
    fn name() -> String {
        "set".to_string()
    }

    fn eval(args: &Vec<Val>, env: &mut Env) -> Val {
        let ident = args[0].clone();
        let value = &args[1];
        let v = eval(value.clone(), env);
        env.set(Val::get_str(ident.clone()), v)
    }
}

impl Intrinsic for IList {
    fn name() -> String {
        "list".to_string()
    }

    fn eval(args: &Vec<Val>, env: &mut Env) -> Val {
        Val::list(args.clone())
    }
}
