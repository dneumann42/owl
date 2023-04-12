pub mod parser;
pub mod values;

use crate::parser::{parse, parse_raw};

fn main() {
    let script = "
        (+ 1 2 3)
    ";
    let parse = parse(script);
    println!("{:?}", parse);
}
