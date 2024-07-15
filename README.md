# Owl

A programming language and environment

### Example

```owl
fun compute-factorial(n)
  if n < 2 then
    1
  else
    n * compute-factorial(n - 1)
  end
end

compute-factorial(5) ;; 120

def x do
  def y 10
  1 + y
end
x ;; 11
```
