use crate::{evaluator::Env, values::Val};

pub fn init(env: &mut Env) {
    env.set(
        String::from("+"),
        Val::Fun(|xs| {
            let mut x = 0.0;
            for a in xs {
                match a {
                    Val::Number(n) => {
                        x += n;
                    }
                    _ => panic!("Invalid value: {:?}", a),
                }
            }
            Val::Number(x)
        }),
    );
}
