pub mod env;
pub mod evaluator;
pub mod parser;
mod tests;
pub mod values;

use crate::{
    env::Env,
    evaluator::{eval, prelude},
    parser::{parse, parse_raw},
};

fn main() {
    let script = "
        (+ 1 2 3)
    ";
    let parse = parse(script);
    let mut env = Env::make();
    prelude::init(&mut env);

    match parse {
        Ok(x) => {
            println!("{:?}", eval(x, &mut env));
        }
        Err(_) => todo!(),
    }
}
