use std::vec;

use pest::{
    error::Error,
    iterators::{Pair, Pairs},
    Parser,
};
use pest_derive::Parser;

use crate::values::Val;

#[derive(Parser)]
#[grammar = "parser/grammar.pest"]
pub struct OwlParser;

#[derive(Debug, Clone)]
pub enum ParseError {
    Generic(String),
}

fn handle_rule(r: Pair<Rule>) -> Val {
    match r.as_rule() {
        Rule::script => {
            let mut rs: Vec<Val> = vec![Val::Atom(String::from("do"))];
            for sub_rule in r.into_inner() {
                rs.push(handle_rule(sub_rule))
            }
            Val::List(
                rs.into_iter()
                    .filter(|x| *x != Val::None)
                    .map(Box::new)
                    .collect(),
            )
        }
        Rule::list => {
            let mut rs: Vec<Box<Val>> = vec![];
            for sub_rule in r.into_inner() {
                rs.push(Box::new(handle_rule(sub_rule)))
            }
            Val::List(rs)
        }
        Rule::expr => {
            for x in r.into_inner() {
                return handle_rule(x);
            }
            Val::None
        }
        Rule::boolean => match r.as_str().to_lowercase().as_str() {
            "#t" => Val::Bool(true),
            "#f" => Val::Bool(false),
            _ => panic!("never"),
        },
        Rule::atom => Val::Atom(r.as_str().to_owned()),
        Rule::number => match r.as_str().parse::<f64>() {
            Ok(v) => Val::Number(v),
            Err(e) => {
                println!("Error when parsing: {:?}", e);
                Val::None
            }
        },
        Rule::EOI => Val::None,
        e => panic!("Invalid rule: {:?}", e),
    }
}

fn handle_rule_pair(r: Pair<Rule>) -> Box<Val> {
    Box::new(handle_rule(r))
}

fn handle_rules(xs: Pairs<Rule>) -> Val {
    let mut a: Vec<Box<_>> = xs.map(handle_rule_pair).collect();
    a.insert(0, Box::new(Val::Atom(String::from("do"))));
    Val::List(a)
}

pub fn parse_raw(code: &'static str) -> Result<Pairs<Rule>, Error<Rule>> {
    OwlParser::parse(Rule::script, code)
}

pub fn parse(code: &'static str) -> Result<Val, ParseError> {
    match parse_raw(code) {
        Ok(r) => Ok(handle_rules(r)),
        Err(_) => Err(ParseError::Generic(String::from("Hello"))),
    }
}
