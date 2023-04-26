use core::panic;

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

    #[test]
    fn it_can_eval_constants() {
        let mut env = Env::make();
        prelude::init(&mut env);

        match parse("123 #t #f \"Hello, World!\"") {
            Ok(Val::List(v)) => match &v[1] {
                Val::List(vs) => {
                    assert_eq!(vs[1], Val::num(123));
                    assert_eq!(vs[2], Val::t());
                    assert_eq!(vs[3], Val::f());
                    assert_eq!(vs[4], Val::str("Hello, World!"));
                }
                _ => todo!(),
            },
            Err(_) => todo!(),
            _ => todo!(),
        }
    }
}

trait HasName {
    fn get_name(self) -> String;
    fn from_name<S>(t: S) -> Option<Self>
    where
        Self: Sized,
        S: Into<String>;
}

trait HasSysPath {
    fn get_path(self) -> String;
}

trait OSName {
    fn get_os_name(self) -> String;
}

const WINDOWS_NAME: &str = "Windows";
const MAC_OS_X: &str = "Mac OS X";

enum OperatingSystem {
    Windows,
    MacOSX,
}

impl HasSysPath for OperatingSystem {
    fn get_path(self) -> String {
        match self {
            OperatingSystem::Windows => "Blah".to_string(),
            OperatingSystem::MacOSX => "Mac Blah".to_string(),
        }
    }
}

impl HasName for OperatingSystem {
    fn get_name(self: Self) -> String {
        match self {
            OperatingSystem::Windows => WINDOWS_NAME.to_string(),
            OperatingSystem::MacOSX => MAC_OS_X.to_string(),
        }
    }

    fn from_name<S>(s: S) -> Option<Self>
    where
        Self: Sized,
        S: Into<String>,
    {
        match s.into().as_str() {
            WINDOWS_NAME => Some(OperatingSystem::Windows),
            MAC_OS_X => Some(OperatingSystem::MacOSX),
            _ => None,
        }
    }
}

struct MockOS {}
impl OSName for MockOS {
    fn get_os_name(self) -> String {
        "Windows".to_string()
    }
}

impl OperatingSystem {
    fn make<T: OSName>(self: Self, os: T) -> Option<OperatingSystem> {
        OperatingSystem::from_name(os.get_os_name())
    }
}

struct UserPaths;

impl UserPaths {
    fn get_system_path_from_name<S>(name: S) -> Option<String>
    where
        S: Into<String>,
    {
        OperatingSystem::from_name(name).map(OperatingSystem::get_path)
    }
}
