echo(1 + 2, 3)

```
PUSH 1
PUSH 2
SYSCALL :+ ; automatically pushes return address

PUSH 3
SYSCALL :echo

FUNCTION :factorial
    PUSH $0 ; arguments automatically bind to $0 .. $n, they are popped from the stack so to use it we need to push
    PUSH 1
    SYSCALL :<= 
    JUMP_IF_TRUE factorial_return 
    PUSH $0
    PUSH 1
    SYSCALL :-
    CALL :factorial
    PUSH $0
    SYSCALL :*
    JUMP factorial_done 
    factorial_return:
        PUSH 1    
        RETURN 
    factorial_done:
        RETURN 
        
PUSH 5
CALL :factorial
SYSCALL :echo
```