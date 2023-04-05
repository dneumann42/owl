use pest::Parser;
use pest_derive::Parser;

#[derive(Parser)]
#[grammar = "grammar.pest"]
pub struct OwlParser;

fn main() {
    println!("Hello, world!");
}
