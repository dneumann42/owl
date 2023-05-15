#[cfg(test)]
mod transpiler_tests {
    use std::{fs::File, io::Write};

    use owl::transpiler::ToLua;
    use trim_margin::MarginTrimmable;

    trait XX {
        fn tr(self) -> String;
        fn xx(self) -> String;
    }

    impl XX for &str {
        fn tr(self) -> String {
            self.trim_margin().unwrap().to_owned()
        }

        fn xx(self) -> String {
            format!(
                "
                |(function()
                |return {}
                | end)()",
                self
            )
            .trim_margin()
            .unwrap()
            .to_owned()
        }
    }

    #[test]
    fn it_can_transpile_numbers() {
        let x = "123".to_lua().unwrap();
        assert_eq!(x, "123".xx());

        let x2 = "123 321".to_lua().unwrap();
        assert_eq!(
            x2,
            "
            |(function()
            |local _ = 123
            |return 321
            | end)()"
                .tr()
        )
    }

    #[test]
    fn it_can_transpile_nested_expressions() {
        assert_eq!(
            "(3 * (2 - a)) + (2 / 2)".to_lua().unwrap(),
            "((3 * (2 - a)) + (2 / 2))".xx()
        );
        assert_eq!(
            "(3 * (2 - a)) + 2 / 3.124".to_lua().unwrap(),
            "((3 * (2 - a)) + (2 / 3.124))".xx()
        )
    }

    #[test]
    fn it_can_transpile_tables() {
        assert_eq!("{1 2 3}".to_lua().unwrap(), "{1,2,3,}".xx());

        assert_eq!("{ a = 123 }".to_lua().unwrap(), "{a = 123,}".xx());

        assert_eq!(
            "{ a = 123
               b = test
               1 2 3 }"
                .to_lua()
                .unwrap(),
            "{1,2,3,a = 123,b = test,}".xx()
        );

        assert_eq!(
            "{ a = { b = 420 } }"
                .to_lua()
                .unwrap(),
            "{a = {b = 420,},}".xx()
        );
    }
}
