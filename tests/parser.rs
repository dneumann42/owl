#[cfg(test)]
mod parser_tests {
    use owl::{parser::parse, values::Val};

    fn res(v: Val) -> Val {
        Val::Do(vec![Box::from(Val::Block(vec![Box::from(v)]))])
    }

    fn ress(v: Vec<Box<Val>>) -> Val {
        Val::Do(vec![Box::from(Val::Block(v))])
    }

    fn parsed(code: &str) -> Val {
        parse(code.to_string()).unwrap()
    }

    #[test]
    fn it_can_parse_numbers() {
        assert_eq!(parsed("3.1415926"), res(Val::Num(3.1415926)));
        assert_eq!(parsed("5"), res(Val::Num(5.0)));
    }

    #[test]
    fn it_can_parse_booleans() {
        assert_eq!(parsed("true"), res(Val::Bool(true)));
        assert_eq!(parsed("false"), res(Val::Bool(false)));
    }

    #[test]
    fn it_can_parse_assignments() {
        assert_eq!(
            parsed("a = 1"),
            res(Val::Assignment(
                Box::from(Val::Ident("a".to_string())),
                Box::from(Val::Num(1.0))
            ))
        );
    }

    #[test]
    fn it_can_parse_multiple_assignments() {
        assert_eq!(
            parsed(
                "a = 1
                 b = 2"
            ),
            ress(vec![
                Box::from(Val::Assignment(
                    Box::from(Val::Ident("a".to_string())),
                    Box::from(Val::Num(1.0))
                )),
                Box::from(Val::Assignment(
                    Box::from(Val::Ident("b".to_string())),
                    Box::from(Val::Num(2.0))
                ))
            ])
        );
    }
}
