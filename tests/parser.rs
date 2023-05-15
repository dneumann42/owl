#[cfg(test)]
mod parser_tests {
    use owl::{parser::parse, values::Val};

    fn res(v: Val) -> Val {
        Val::Do(vec![Box::from(v)])
    }

    fn ress(v: Vec<Box<Val>>) -> Val {
        Val::Do(v)
    }

    fn parsed(code: &str) -> Val {
        parse(&code.to_string()).unwrap()
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
            res(Val::Assignment((
                Box::from(Val::Ident("a".to_string())),
                Box::from(Val::Num(1.0))
            )))
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
                Box::from(Val::Assignment((
                    Box::from(Val::Ident("a".to_string())),
                    Box::from(Val::Num(1.0))
                ))),
                Box::from(Val::Assignment((
                    Box::from(Val::Ident("b".to_string())),
                    Box::from(Val::Num(2.0))
                )))
            ])
        );
    }

    #[test]
    fn it_can_handle_unary_ops() {
        assert_eq!(
            parsed("-123"),
            res(Val::UnOp(("-".to_string(), Box::new(Val::Num(123.0)))))
        );

        assert_eq!(
            parsed("#s"),
            res(Val::UnOp((
                "#".to_string(),
                Box::new(Val::Ident("s".to_owned()))
            )))
        );

        assert_eq!(
            parsed("not 0"),
            res(Val::UnOp(("not".to_string(), Box::new(Val::Num(0.0)))))
        )
    }

    #[test]
    fn it_can_handle_binary_ops() {
        assert_eq!(
            parsed("1 + 2"),
            res(Val::BinOp((
                "+".to_string(),
                Box::new(Val::Num(1.0)),
                Box::new(Val::Num(2.0))
            )))
        )
    }
}
