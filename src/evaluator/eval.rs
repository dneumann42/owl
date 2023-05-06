use crate::{env::Env, values::Val};

use super::prelude::{
    IAdd, IDef, IDiv, IDo, IEcho, IEval, IFun, IList, IMul, IPlus, IRead, ISet, ISub, Intr,
};

fn handle_intrinsic(intr: &String, args: &Vec<Val>, env: &mut Env) -> Intr {
    Intr::start()
        .intr::<IDo>(intr, args, env)
        .intr::<IPlus>(intr, args, env)
        .intr::<ISub>(intr, args, env)
        .intr::<IMul>(intr, args, env)
        .intr::<IDiv>(intr, args, env)
        .intr::<IDo>(intr, args, env)
        .intr::<IDef>(intr, args, env)
        .intr::<IFun>(intr, args, env)
        .intr::<IRead>(intr, args, env)
        .intr::<IEcho>(intr, args, env)
        .intr::<IEval>(intr, args, env)
        .intr::<IAdd>(intr, args, env)
        .intr::<ISet>(intr, args, env)
        .intr::<IList>(intr, args, env)
}

pub fn eval(val: Val, env: &mut Env) -> Val {
    match val {
        Val::Number(_)
        | Val::Bool(_)
        | Val::Str(_)
        | Val::Fun(_, _, _)
        | Val::Array(_)
        | Val::None => val,
        Val::Atom(v) => env.find(v.clone()).map_or(Val::None, |v| v),
        Val::List(xs) => eval_list(xs, env),
    }
}

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

pub fn eval_intrinsic(intr: &String, args: &Vec<Val>, env: &mut Env) -> Val {
    match handle_intrinsic(&intr, args, env) {
        Intr::Ok(v) => v,
        Intr::Invalid => eval_function(&intr, &args, env),
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
