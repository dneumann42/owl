#[derive(Debug, Clone, PartialEq)]
pub enum Val {
    None,
    Number(f64),
    Atom(String),
    Bool(bool),
    List(Vec<Box<Val>>),
}
