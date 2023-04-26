use crate::{env::Env, values::Val};

pub trait Intrinsic {
    fn name() -> String;
    fn eval(args: &Vec<Val>, env: &mut Env) -> Val;
}
