use crate::{
    parser::{parse, ParseError},
    values::{Assignment, Do, List, Table, Val},
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

fn fnwrap<T: ToString>(s: T) -> String {
    format!("(function()\n{} end)()", s.to_string())
}

fn get_expr_from_stmt(v: &Val) -> Result<LuaSource> {
    match v {
        Val::Assignment((ident, _)) => return Ok(ident.to_lua()?),
        _ => panic!(),
    }
}

fn transpile_table(tbl: &Table) -> Result<LuaSource> {
    let mut ls: String = "".to_owned();

    ls.push_str("{");

    let mut it = tbl.arr.iter().peekable();

    while let Some(v) = it.next() {
        if v.is_stmt() {
            ls.push_str(&fnwrap(v.to_lua()?))
        } else {
            ls.push_str(&v.to_lua()?)
        }

        ls.push_str(",")
    }

    let mut kv_it_vec: Vec<_> = tbl.kv.iter().collect();
    kv_it_vec.sort_by(|(a, _), (b, _)| a.partial_cmp(b).unwrap());

    let mut kv_it = kv_it_vec.iter().peekable();

    while let Some((k, v)) = kv_it.next() {
        ls.push_str(&format!("{} = {},", k, v.to_lua()?))
    }

    ls.push_str("}");

    Ok(ls)
}

fn transpile_binop(op: &String, lh: &Box<Val>, rh: &Box<Val>) -> Result<LuaSource> {
    Ok(format!(
        "({} {} {})",
        lh.as_ref().to_lua()?,
        op,
        rh.as_ref().to_lua()?
    ))
}

fn transpile_do(xs: &Vec<Box<Val>>) -> Result<LuaSource> {
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

fn transpile_block(xs: &Vec<Box<Val>>) -> Result<LuaSource> {
    let mut ls: String = String::from("do\n");

    for val in xs {
        ls.push_str(&val.as_ref().to_lua()?);
        ls.push_str("\n");
    }

    ls.push_str("end\n");

    Ok(ls)
}

fn transpile_assignment(ident: &Box<Val>, expr: &Box<Val>) -> Result<LuaSource> {
    let mut ls: String = String::from("local ");
    ls.push_str(&ident.to_lua()?);
    ls.push_str(" = ");
    ls.push_str(&expr.to_lua()?);
    ls.push_str("\n");
    Ok(ls)
}

impl ToLua for Val {
    fn to_lua(&self) -> Result<LuaSource> {
        match self {
            Val::None => Ok("nil".to_string()),
            Val::Ident(a) => Ok(a.to_string()),
            Val::List(_) => todo!(),
            Val::UnOp((op, v)) => Ok(format!("{}{}", op, v.as_ref().to_lua()?)),
            Val::BinOp((op, lh, rh)) => transpile_binop(op, lh, rh),
            Val::Table(tbl) => transpile_table(tbl),
            Val::Do(xs) => transpile_do(xs),
            Val::Block(xs) => transpile_block(xs),
            Val::Assignment((ident, expr)) => transpile_assignment(ident, expr),
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
