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
    (3 * (2 - a)) + (2 / 2)
    ";

    write!(output, "{}", owl.to_lua().unwrap())?;

    Ok(())
}
