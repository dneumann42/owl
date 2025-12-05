# Owl

A programming language

![Archimedes](archimedes.png)

## Example

```owl
struct Vec2
    x : Number
    y : Number
end

let x : Vec2 = { x = 0.0, y = 0.0 }

fun vec2(x : Int, y : Int)
    { x = x, y = y }
end

let xs : [Vec2] = [vec2(0.0, 0.0), vec2(1.0, 1.0)]
let test : (Int, Bool) = (1, #t)

let f : (Int) -> Int = fn(x: Int) x + 1
```
