# Owl

This project is very very early in development.

<pre>
 ~___~  Owl (0.0.0-dev)
 {O,o}  run with ',h' for list of commands
/)___)  enter '?' to show help for repl
  ' '
</pre>

### Example

```owl
fun compute-factorial(n)
  if n < 2 then
    1
  else
    n * compute-factorial(n - 1)
  end
end

compute-factorial(5) ; 120

x := do
  y := 10
  1 + y
end
x ; 11

my-add := fn(a) fn(b) a + b
c := my-add(1)(2) ;; 3

my-dict := {
    hello: {
        world: fn() "HI"
    }
}
echo(my-dict.hello.world()) ; "HI"
```
