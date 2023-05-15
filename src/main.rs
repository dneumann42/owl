use std::{
    fs::File,
    io::{Error, Write},
};

use owl::transpiler::ToLua;

pub mod parser;
pub mod values;

fn main() -> Result<(), Error> {
    let mut output = File::create("demo.lua")?;

    let owl = "
    a = 123
    b = 6.4
    false
    ";

    write!(output, "{}", owl.to_lua().unwrap())?;

    Ok(())
}
