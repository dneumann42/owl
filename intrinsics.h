#ifndef OWL_INTRINSICS_H
#define OWL_INTRINSICS_H

#include "code.h"
#include "gc.h"

void owl_intrinsic_add(Owl_GC *gc, Owl_Stack *stack);
void owl_intrinsic_sub(Owl_GC *gc, Owl_Stack *stack);
void owl_intrinsic_mul(Owl_GC *gc, Owl_Stack *stack);
void owl_intrinsic_div(Owl_GC *gc, Owl_Stack *stack);
void owl_intrinsic_echo(Owl_GC *gc, Owl_Stack *stack);

static struct { owl_intrinsic fn; const char *sym; } owl_base_intrinsics[] = {
    { .fn = owl_intrinsic_add, .sym = "+" },
    { .fn = owl_intrinsic_sub, .sym = "-" },
    { .fn = owl_intrinsic_mul, .sym = "*" },
    { .fn = owl_intrinsic_div, .sym = "/" },
    { .fn = owl_intrinsic_echo, .sym = "echo" },
};

#endif //OWL_INTRINSICS_H
