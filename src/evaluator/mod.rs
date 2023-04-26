pub mod intrinsic;
pub mod prelude;
pub mod eval;

use std::{
    collections::HashSet,
    env::args,
    fmt::format,
    io::{self, stdout, BufRead, Write},
};

use crate::{env::Env, values::Val};