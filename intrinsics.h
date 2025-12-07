#ifndef OWL_INTRINSICS_H
#define OWL_INTRINSICS_H
#include "code.h"
#include "evaluator.h"
#include "gc.h"

void owl_intrinsic_add(Owl_GC *gc, Owl_Code *code, Owl_Object *args);
void owl_intrinsic_sub(Owl_GC *gc, Owl_Code *code, Owl_Object *args);
void owl_intrinsic_mul(Owl_GC *gc, Owl_Code *code, Owl_Object *args);
void owl_intrinsic_div(Owl_GC *gc, Owl_Code *code, Owl_Object *args);
void owl_intrinsic_echo(Owl_GC *gc, Owl_Code *code, Owl_Object *args);

typedef void (*owl_intrinsic_)(Owl_GC *gc, Owl_Code *code, Owl_Object *args);
static struct { owl_intrinsic_ fn; const char *sym; } owl_base_intrinsics[] = {
    { .fn = owl_intrinsic_add, .sym = "+" },
    { .fn = owl_intrinsic_sub, .sym = "-" },
    { .fn = owl_intrinsic_mul, .sym = "*" },
    { .fn = owl_intrinsic_div, .sym = "/" },
    { .fn = owl_intrinsic_echo, .sym = "echo" },
};

#endif //OWL_INTRINSICS_H