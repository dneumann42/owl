use std::collections::{HashMap, LinkedList};

use crate::values::Val;

#[derive(Debug)]
pub struct Env {
    stack: Vec<HashMap<String, Val>>,
}

impl Env {
    pub fn make() -> Self {
        Env {
            stack: vec![HashMap::new()],
        }
    }

    pub fn test(&mut self) -> i32 {
        32
    }

    pub fn find(&self, key: String) -> Option<Val> {
        for scope in &self.stack {
            match scope.get(&key) {
                Some(v) => return Some(v.to_owned()),
                None => {}
            }
        }
        None
    }

    pub fn set(&mut self, key: String, val: Val) -> Val {
        match self.stack.last_mut() {
            Some(v) => {
                v.insert(key, val.clone());
            }
            None => {}
        }
        val
    }

    pub fn push(&mut self) {
        self.stack.push(HashMap::new())
    }

    pub fn pop(&mut self) -> Option<HashMap<String, Val>> {
        self.stack.pop()
    }
}
