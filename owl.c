#include <stdio.h>

#include "gc.h"

int main(const int argc, const char **argv) {
    Owl_Alloc alloc = owl_default_alloc_init();
    Owl_GC gc = owl_gc_init(alloc);

    Owl_Object *script = owl_new_list(&gc);
    owl_list_append(&gc, script, owl_new_symbol(&gc, "do"));

    Owl_Object *arithmetic = owl_new_list(&gc);
    owl_list_append(&gc, arithmetic, owl_new_symbol(&gc, "+"));
    owl_list_append(&gc, arithmetic, owl_new_number(&gc, 1.0));
    owl_list_append(&gc, arithmetic, owl_new_number(&gc, 2.0));
    owl_list_append(&gc, arithmetic, owl_new_number(&gc, 3.0));

    owl_list_append(&gc, script, arithmetic);

    owl_gc_add_root(&gc, script);

    owl_gc_mark(&gc);
    owl_gc_sweep(&gc);

    owl_gc_deinit(&gc);

    return 0;
}
