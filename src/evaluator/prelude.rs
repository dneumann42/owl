use crate::{
    evaluator::{eval, Env},
    parser::parse,
    values::Val,
};

pub struct Prelude {
    initialized: bool,
    env: Env,
}

impl Prelude {
    fn eval_str(self: &mut Self, s: &'static str) {
        let parse = parse(s);
        self.env = Env::make();
        self.init();
    }

    fn eval(self: &mut Self, v: Val) -> Val {
        eval(v, &mut self.env)
    }

    fn init(self: &mut Self) {
        if self.initialized {
            return;
        }

        // self.env.set(
        //     String::from("do"),
        //     Val::Fun(|xs| {
        //         let mut result = Val::None;
        //         match xs {
        //             Val::List(vs) => {
        //                 for x in vs {
        //                     // TODO: Eval
        //                     result = self.eval(x);
        //                 }
        //             }
        //             _ => {
        //                 panic!("never");
        //             }
        //         }
        //         return result;
        //     }),
        // );

        // self.env.set(
        //     String::from("+"),
        //     Val::Fun(|xs| {
        //         let mut x = 0.0;
        //         match xs {
        //             Val::List(vs) => {
        //                 for a in vs {
        //                     match a {
        //                         Val::Number(n) => {
        //                             x += n;
        //                         }
        //                         _ => panic!("Invalid value: {:?}", a),
        //                     }
        //                 }
        //                 Val::Number(x)
        //             }
        //             _ => {
        //                 panic!("Invalid value {:?}", xs)
        //             }
        //         }
        //     }),
        // );
        self.initialized = true;
    }
}

pub fn init(env: &mut Env) {}
