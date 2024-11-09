```owl
;; concatenation
"hello" & "world"
```

default arguments are evaluated at the
callsite, each argument is evaluated in order of definition

```owl
fun test(
    a fn() 123,
    b a() + 321
)
    b
end
```
