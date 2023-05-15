#[cfg(test)]
mod parser_tests {
    use std::collections::HashMap;

    use owl::{
        parser::parse,
        values::{assn, binop, f, id, num, t, unop, Table, Val},
    };

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
        assert_eq!(parsed("3.1415926"), res(num(3.1415926)));
        assert_eq!(parsed("5"), res(num(5)));
    }

    #[test]
    fn it_can_parse_booleans() {
        assert_eq!(parsed("true"), res(t()));
        assert_eq!(parsed("false"), res(f()));
    }

    #[test]
    fn it_can_parse_assignments() {
        assert_eq!(parsed("a = 1"), res(assn(id("a"), num(1))));
    }

    #[test]
    fn it_can_parse_multiple_assignments() {
        assert_eq!(
            parsed(
                "a = 1
                 b = 2"
            ),
            ress(vec![
                Box::from(assn(id("a"), num(1))),
                Box::from(assn(id("b"), num(2)))
            ])
        );
    }

    #[test]
    fn it_can_handle_unary_ops() {
        assert_eq!(parsed("-123"), res(unop("-", num(123))));
        assert_eq!(parsed("#s"), res(unop("#", id("s"))));
        assert_eq!(parsed("not 0"), res(unop("not", num(0))))
    }

    #[test]
    fn it_can_handle_binary_ops() {
        assert_eq!(parsed("1 + 2"), res(binop("+", num(1), num(2))));

        assert_eq!(
            parsed("1 + (2 / 2)"),
            res(binop("+", num(1), binop("/", num(2), num(2))))
        );

        assert_eq!(
            parsed("(3 * (2 - 4)) + (2 / 2)"),
            res(binop(
                "+",
                binop("*", num(3), binop("-", num(2), num(4))),
                binop("/", num(2), num(2))
            ))
        );
    }

    #[test]
    fn it_can_handle_tables() {
        assert_eq!(
            parsed("{ 1 2 3 }"),
            res(Val::Table(Table {
                kv: HashMap::from([]),
                arr: vec![num(1), num(2), num(3)]
            }))
        )
    }
}
