use crate::{
    parser::{parse, ParseError},
    values::{Assignment, Do, List, Val},
};

pub type Result<T> = core::result::Result<T, TranspilerError>;
pub type LuaSource = String;

#[derive(Debug)]
pub enum TranspilerError {
    Generic(String),
    SyntaxError(ParseError),
}

pub trait ToLua {
    fn to_lua(&self) -> Result<LuaSource>;
}

// impl ToLua for Val {
//     fn to_lua(&self) -> Result<LuaString> {
//         todo!()
//     }
// }

fn fnwrap<T: ToString>(s: T) -> String {
    format!("(function()\n{} end)()", s.to_string())
}

fn get_expr_from_stmt(v: &Val) -> Result<LuaSource> {
    match v {
        Val::Assignment((ident, _)) => return Ok(ident.to_lua()?),
        _ => panic!(),
    }
}

impl ToLua for Val {
    fn to_lua(&self) -> Result<LuaSource> {
        match self {
            Val::None => Ok("nil".to_string()),
            Val::Ident(a) => Ok(a.to_string()),
            Val::List(_) => todo!(),
            Val::Do(xs) => {
                let mut ls: String = "".to_owned();

                // turn it into a list of tuple(val, luastring)

                let vs: Vec<Val> = xs.iter().map(|v| v.as_ref().to_owned()).collect();
                let mut it = vs.iter().peekable();

                while let Some(exp) = it.next() {
                    let mut val = "".to_owned();

                    if exp.is_stmt() {
                        ls.push_str(&exp.to_lua()?);
                        val = get_expr_from_stmt(exp)?;
                    } else {
                        val = exp.to_lua()?;
                    }

                    if it.peek().is_none() {
                        ls.push_str(&format!("return {}\n", val));
                    } else {
                        ls.push_str(&format!("local _ = {}\n", val));
                    }
                }

                Ok(fnwrap(ls))
            }
            Val::Block(xs) => {
                let mut ls: String = String::from("do\n");

                for val in xs {
                    ls.push_str(&val.as_ref().to_lua()?);
                    ls.push_str("\n");
                }

                ls.push_str("end\n");

                Ok(ls)
            }
            Val::Assignment((ident, expr)) => {
                let mut ls: String = String::from("local ");
                ls.push_str(&ident.to_lua()?);
                ls.push_str(" = ");
                ls.push_str(&expr.to_lua()?);
                ls.push_str("\n");
                Ok(ls)
            }
            Val::Str(s) => Ok(format!("{:?}", s)),
            v => Ok(v.to_string()),
        }
    }
}

impl ToLua for String {
    fn to_lua(&self) -> Result<LuaSource> {
        let ast = parse(self).map_err(|e| TranspilerError::SyntaxError(e))?;
        println!("{:?}", ast);
        ast.to_lua()
    }
}

impl ToLua for &str {
    fn to_lua(&self) -> Result<LuaSource> {
        self.to_string().to_lua()
    }
}
