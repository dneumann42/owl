pub mod env;
pub mod evaluator;
pub mod parser;
mod tests;
pub mod values;

use core::panic;
use std::fs;

use crate::{
    env::Env,
    evaluator::{eval},
    parser::{parse, parse_raw},
};

// struct Owl {
//     env: Env,

// }

fn main() {
    match fs::read_to_string("scripts/repl.owl") {
        Ok(s) => {
            let parse = parse(s.as_str());
            let mut env = Env::make();

            match parse {
                Ok(x) => {
                    println!("{}", eval(x, &mut env).to_string());
                }
                Err(_) => {
                    println!("{:?}", parse);
                    todo!()
                }
            }
        }
        Err(e) => panic!("{:?}", e),
    }
}
