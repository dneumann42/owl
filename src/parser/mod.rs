use pest::{
    error::Error,
    iterators::{Pair, Pairs},
    Parser,
};
use pest_derive::Parser;

use crate::values::{is_none, not_none, Val};

#[derive(Parser)]
#[grammar = "parser/owl.pest"]
pub struct OwlParser;

#[derive(Debug, Clone)]
pub enum ParseError {
    Generic(String),
}

// TODO: make these rule handlers return a Result

fn handle_script(r: Pair<Rule>) -> Val {
    Val::Do(
        r.into_inner()
            .into_iter()
            .map(handle_rule)
            .filter(not_none)
            .map(Box::from)
            .collect(),
    )
}

fn handle_expr(r: Pair<Rule>) -> Val {
    r.into_inner().next().map(handle_rule).unwrap_or(Val::None)
}

fn handle_number(r: Pair<Rule>) -> Val {
    r.as_str()
        .parse::<f64>()
        .map(Val::Num)
        .map_err(|e| ParseError::Generic(e.to_string()))
        .unwrap_or(Val::None)
}

fn handle_boolean(r: Pair<Rule>) -> Val {
    if r.as_str() == "true" {
        Val::Bool(true)
    } else {
        Val::Bool(false)
    }
}

fn handle_block(r: Pair<Rule>) -> Val {
    Val::Block(r.into_inner().map(handle_rule).map(Box::from).collect())
}

fn handle_do(r: Pair<Rule>) -> Val {
    Val::Do(r.into_inner().map(handle_rule).map(Box::from).collect())
}

fn handle_ident(r: Pair<Rule>) -> Val {
    Val::Ident(r.as_str().to_owned())
}

fn handle_rule(r: Pair<Rule>) -> Val {
    match r.as_rule() {
        Rule::EOI | Rule::WHITESPACE => Val::None,
        Rule::script => handle_script(r),
        Rule::exp => handle_expr(r),
        Rule::number => handle_number(r),
        Rule::exponent => handle_number(r),
        Rule::boolean => handle_boolean(r),
        Rule::prefix_exp => handle_expr(r),
        Rule::ident => handle_ident(r),
        Rule::block => handle_block(r),
        Rule::doblock => handle_do(r),
        Rule::stmt => r.into_inner().next().map(handle_rule).unwrap_or(Val::None),
        Rule::assignment => {
            let vs: Vec<Pair<Rule>> = r.into_inner().into_iter().collect();
            let ident = handle_ident(vs[0].clone());
            let exp = handle_expr(vs[1].clone());
            Val::Assignment(ident.into(), exp.into())
        }
    }
}

fn handle_rule_pair(r: Pair<Rule>) -> Val {
    handle_rule(r)
}

fn handle_rules(xs: Pairs<Rule>) -> Val {
    xs.map(handle_rule_pair)
        .map(Box::from)
        .next()
        .map(|v| v.as_ref().clone())
        .unwrap_or(Val::None)
}

pub fn parse_raw(code: &str) -> Result<Pairs<Rule>, Error<Rule>> {
    OwlParser::parse(Rule::script, code)
}

pub fn parse(code: String) -> Result<Val, ParseError> {
    parse_raw(code.as_str())
        .map_err(|e| ParseError::Generic(e.to_string()))
        .map(handle_rules)
}
