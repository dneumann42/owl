#include "intrinsics.h"
#include <assert.h>

void owl_intrinsic_add(Owl_GC *gc, Owl_Stack *stack) {
  Owl_Object *result = owl_new_number(gc, 0.0);
  size_t index = 0;
  while (index < stack->length) {
      assert(stack->data[index]->type == OWL_NUMBER);
      result->number += stack->data[index]->number;
      index++;
  }
  owl_stack_push(stack, result, gc->alloc);
}

void owl_intrinsic_sub(Owl_GC *gc, Owl_Stack *stack) {
}

void owl_intrinsic_mul(Owl_GC *gc, Owl_Stack *stack) {
}

void owl_intrinsic_div(Owl_GC *gc, Owl_Stack *stack) {
}

void owl_intrinsic_echo(Owl_GC *gc, Owl_Stack *stack) {
}
