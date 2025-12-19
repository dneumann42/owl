#include <assert.h>
#include <string.h>

#include "alloc.h"
#include "evaluator.h"
#include "gc.h"

static Owl_Object *build_script(Owl_GC *gc) {
    Owl_Object *script = owl_new_list(gc);
    owl_list_append(gc, script, owl_new_symbol(gc, "do"));

    Owl_Object *arithmetic = owl_new_list(gc);
    owl_list_append(gc, arithmetic, owl_new_symbol(gc, "+"));
    owl_list_append(gc, arithmetic, owl_new_number(gc, 1.0));
    owl_list_append(gc, arithmetic, owl_new_number(gc, 2.0));
    owl_list_append(gc, arithmetic, owl_new_number(gc, 3.0));

    owl_list_append(gc, script, arithmetic);
    return script;
}

int main(void) {
    Owl_Alloc alloc = owl_default_alloc_init();
    Owl_GC gc = owl_gc_init(alloc);

    Owl_Object *script = build_script(&gc);
    owl_gc_add_root(&gc, script);

    Owl_Evaluator eval = owl_eval_init(&gc);
    Owl_Code code = owl_compile(&eval, script);
    assert(code.length == 4);

    Owl_String bytecode = owl_code_tostr(&code);
    assert(strstr(bytecode.data, "SYSCALL + argc=3") != NULL);
    owl_string_del(&bytecode, alloc);

    Owl_Object *result = owl_eval_code(&eval, code);
    assert(result != NULL);
    assert(result->type == OWL_NUMBER);
    assert(result->number == 6.0);

    owl_code_deinit(&code);
    owl_eval_deinit(&eval);
    owl_gc_mark(&gc);
    owl_gc_sweep(&gc);
    owl_gc_deinit(&gc);
    return 0;
}
