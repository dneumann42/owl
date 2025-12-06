#include <stdio.h>

#include "gc.h"

int main(const int argc, const char **argv) {
    Owl_Alloc alloc = owl_default_alloc_init();
    Owl_GC gc = owl_gc_init(alloc);

    Owl_Object *list = owl_gc_new(&gc, OWL_LIST);
    list->next = NULL;
    list->value = NULL;

    gc.root = OWL_GC_GET_HEADER(list);

    Owl_Object *tail = list;

    for (int i = 0; i < 10; i++) {
        Owl_Object *n = owl_gc_new(&gc, OWL_NUMBER);
        n->number = (double) i;

        if (list->value == NULL) {
            list->value = n;
            tail = list;
        } else {
            Owl_Object *node = owl_gc_new(&gc, OWL_LIST);
            node->value = n;
            node->next = NULL;

            tail->next = node;
            tail = node;
        }
    }

    Owl_Object *it = OWL_GC_OBJECT_FROM_HEADER(gc.root);
    while (it != NULL) {
        const Owl_Object *n = it->value;
        printf("GOT: %f\n", n->number);
        it = it->next;
    }

    gc.root = NULL;

    owl_gc_mark(&gc);
    owl_gc_sweep(&gc);
    return 0;
}
