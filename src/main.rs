use pest::Parser;
use pest_derive::Parser;

#[derive(Parser)]
#[grammar = "grammar.pest"]
pub struct OwlParser;

fn main() {
    let script = "hello";
    let parse = OwlParser::parse(Rule::script, script);
    println!("{:?}", parse);
}
