local read = require("src.reader")

local _ = [[

cond
  : 1 == 2 do
    print("Hello")
  end
  : 2 == 3 print("World")
else
  123
end

{ : hello ~World,
  : test  1 + 2 }

if #t 
| print("Hello, World") 
| print("Not true") 
end

def add fn(a) 1 + a
def sub fun(a, b)
  a + b
end

]]
