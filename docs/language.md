# Owl - a programming language

```owl

fun tostring ({ x, y }) ; destructure
    string.format("<%s %s>", x, y)
end

echo(tostring({ 
  x 100, 
  y 200 
}))
```
