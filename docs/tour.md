# A Tour of Owl

This is a tour of what Owl can currently do, as of version 0.0.0_dev,
owl is early in development so much of this is subject to change, and
many more features will be added as needed.

## Hello, World!

create a file named `hello.owl`, and add this code

```owl
echo("Hello, World!")
```
You can run it with this command: `owl hello.owl`
you should see `Hello, World` printed to your screen

## Comments

a comment is text you can add to your script that isn't executed,
useful for documenting and explaining your code

```
;; Comments start with a `;`

x := 10 ; they can be inline
```

## Math and logic

Owl supports these basic binary operators
`+ - * / < >`

and these logical binary operators
`eq noteq`

Owl also has a number of unary operators
`- not`

## Variables, definitions and assignment

To define a variable, use the `:=` operator
`hello := "world"`

variables are mutable by default, meaning you can change their 
values using the `=` operator
`hello = 56`

## Collections

Owl has a few basic collections

### List

List literal
`[1, 2, 3]`

Here are a few basic operations you can do with a list

 Adds an element to a list
`list-add([1, 2, 3], 4)`

 Removes an element at index `1`
`list-remove([1, 2], 1)`

returns the length of the list, this function is also used with 
strings
`len([1, 2, 3])` 

### Dictionary

Dictionary literal
`{ x: 123, y: 321 }`

Access a field of a dictionary using the dot operator
`a.b.c`

You can chain dot and call operations
`my-var := a.b().c.d().e`

This is also valid on the left side of an assignment operator
`a.b().c = 42`

### Modules

Each script file is its own module, you can use other modules from
within your script using the `use` keyword
`use terminal`

this will add the terminal module to your scripts environment, to access it 
you would use the `terminal` identifier
`terminal.clear()`

the last expression in the script is what the module exports
```
;; my math module `math.owl`
fun add(a, b) a + b end
fun sub(a, b) a - b end

{
    add: add,
    sub: sub
}
```

```
;; using the math module in `main.owl`
use math

echo(math.add(1, 2)) ;; 3
```

the `use` command will search for scripts in the same directory, as of 
this version there is no way to search for scripts in sub directories.
future versions will have a search path of common directories.

## Conditionals

Owl has two main ways of doing conditionals

### If

ifs work much like you would expect

```owl
age := read-line("What is your age?")
if age < 18 then
    echo("You cannot vote")
elif age > 17 and age < 32 then
    echo("You are young")
elif age > 31 and age < 56 then
    echo("You are a mature adult")
else
    echo("You are getting old")
end
```

### Cond

```owl
cond 
    age < 18                do echo("You cannot vote") end
    age > 17 and age < 32   do echo("You are young") end
    age > 31 and age < 56   do echo("You are a mature adult") end
    true                    do echo("You are getting old") end
end
```

## Looping

Owl has a while loop and a for loop

### While

While loops will loop as long as the condition holds true
```
i := 0
while i < 10 do
    ;; this will execute mutliple times until i >= 10
    echo(i) 
    i += 1
end
```
### For

`for` loops are a special syntax for `while` loops, they are made to be
used with iterators, for example the `range` function returns an iterator
that can be used with a `for`

```owl
for i in range(0, 10) do
    echo(i)
end
```

Will get transformed into a `while` loop

```owl
do
  next = range(0, 10)
  i = next()
  while i do
    echo(i)
    i = next()
  end
end
```

inside the body of the for loop, you will have access to the `next` function

### Iterators

iterators are functions that when called will either return a value or false,
representing the end of the iteration, for example the `range` function, which is provided in the core library, is implemented like so

```owl
fun range(min, max)
  fn() if min > max then
    false
  else
    idx := min
    min = min + 1
    idx
  end
end
```

## Functions & Lambdas

functions are defined using the `fun` keyword

```owl
fun my-func()
    ...
end
```
functions can be anonymous

```owl
my-func := fun()
    ...
end
```

lambdas are similar, the body of the lambda is a single expression

```owl
add-one := fn(a, b) a + b + 1

functional-add := fn(a) fn(b) a + b
functional-add(1)(2) ; 3
```

## Mapping, Filtering & Sorting

WIP
