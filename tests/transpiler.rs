#[cfg(test)]
mod transpiler_tests {
    use std::{fs::File, io::Write};

    use owl::transpiler::ToLua;
    use trim_margin::MarginTrimmable;

    trait XX {
        fn xx(self) -> String;
    }

    impl XX for &str {
        fn xx(self) -> String {
            self.trim_margin().unwrap().to_owned()
        }
    }

    #[test]
    fn it_can_transpile_numbers() {
        let x = "123".to_lua().unwrap();
        assert_eq!(
            x,
            "
            |(function()
            |return 123
            | end)()"
                .xx()
        );

        let x2 = "123 321".to_lua().unwrap();
        assert_eq!(
            x2,
            "
            |(function()
            |local _ = 123
            |return 321
            | end)()"
                .xx()
        )
    }
}
