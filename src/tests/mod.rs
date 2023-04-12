use crate::{env::Env, evaluator::prelude, parser::parse, values::Val};

fn check_do(v: Vec<Val>, vs: Vec<Val>) {
    let mut xs: Vec<Val> = vs.into_iter().collect();
    xs.insert(0, Val::Atom(String::from("do")));
    assert_eq!(v, vec![Val::Atom(String::from("do")), Val::List(xs)])
}

#[cfg(test)]
mod parser_tests {
    use crate::{parser::parse, values::Val};

    use super::check_do;

    #[test]
    fn it_can_parse_numbers() {
        let ns = vec!["123.0", "3.14159", "4813"];
        match parse(&ns.join(" ")) {
            Ok(Val::List(v)) => {
                check_do(
                    v,
                    vec![Val::num(123.0), Val::num(3.14159), Val::num(4813.0)],
                );
            }
            Err(e) => panic!("Error: {:?}", e),
            _ => panic!(""),
        }
    }

    #[test]
    fn it_can_parse_booleans() {
        match parse("#t #f #T #F") {
            Ok(Val::List(v)) => {
                check_do(v, vec![Val::t(), Val::f(), Val::t(), Val::f()]);
            }
            Err(e) => panic!("Error: {:?}", e),
            _ => panic!(""),
        }
    }

    #[test]
    fn it_can_parse_atoms() {
        let ns = vec!["+", "hello", "*hello-world*"];
        let t = &ns.join(" ");
        match parse(t) {
            Ok(Val::List(v)) => {
                check_do(
                    v,
                    vec![Val::atom(ns[0]), Val::atom(ns[1]), Val::atom(ns[2])],
                );
            }
            Err(e) => panic!("{:?}", e),
            _ => panic!(""),
        }
    }

    #[test]
    fn it_can_parse_lists() {
        match parse("(+ 1 2 3)") {
            Ok(Val::List(v)) => check_do(
                v,
                vec![Val::List(vec![
                    Val::atom("+"),
                    Val::num(1.0),
                    Val::num(2.0),
                    Val::num(3.0),
                ])],
            ),
            Err(_) => panic!(),
            _ => panic!(),
        }
    }
}

mod evaluator {
    use crate::{env::Env, evaluator::prelude, parser::parse, values::Val};

    use super::check_do;

    #[test]
    fn it_can_eval_constants() {
        let mut env = Env::make();
        prelude::init(&mut env);

        match parse("123 #t #f") {
            Ok(Val::List(v)) => {
                todo!()
            }
            Err(_) => todo!(),
            _ => todo!(),
        }
    }
}
