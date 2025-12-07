#ifndef OWL_EVALUATOR_H
#define OWL_EVALUATOR_H
#include <stddef.h>

#include "code.h"
#include "gc.h"
#include "objects.h"

typedef void (*owl_intrinsic)(Owl_GC *gc, Owl_Code *code, Owl_Object *args);

#define OWL_INTRINSIC_LENGTH \
    16

struct Owl_NamedIntrinsic {
    const char *sym;
    owl_intrinsic fn;
};

typedef struct Owl_NamedIntrinsic Owl_NamedIntrinsic;

struct Owl_Evaluator {
    Owl_GC *gc;
    struct {
        Owl_NamedIntrinsic *fns;
        size_t length;
        size_t capacity;
    } intrinsics;
};

typedef struct Owl_Evaluator Owl_Evaluator;

Owl_Evaluator owl_eval_init(Owl_GC *gc);
void owl_eval_deinit(Owl_Evaluator *eval);
void owl_add_intrinsic(Owl_Evaluator *eval, owl_intrinsic intrinsic, const char *sym);
void owl_compile_object(Owl_Evaluator *val, Owl_Code *code, Owl_Object *object);

owl_intrinsic owl_get_intrinsic(Owl_Evaluator *eval, const char *sym);

Owl_Code owl_compile(Owl_Evaluator *eval, const Owl_Object *script);

Owl_Object *owl_eval(Owl_GC *gc, const Owl_Object *script);

#endif //OWL_EVALUATOR_H