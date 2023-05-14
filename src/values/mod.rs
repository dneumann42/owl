#[derive(Debug, Clone, PartialEq)]
pub enum Val {
    None,
    Num(f64),
    Bool(bool),
    Str(String),
    Ident(String),
    List(Vec<Box<Val>>),
    Do(Vec<Box<Val>>),
    Block(Vec<Box<Val>>),
    Assignment(Box<Val>, Box<Val>),
}

pub fn is_none(v: &Val) -> bool {
    matches!(v, &Val::None)
}

pub fn not_none(v: &Val) -> bool {
    !is_none(v)
}
