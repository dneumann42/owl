# Owl

Note: this project is very very early in development and doesn't do a whole lot

<pre>
 ~___~  Owl (0.0.0-dev)
 {O,o}  run with 'help' for list of commands
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

def x do
  def y 10
  1 + y
end
x ; 11
```
