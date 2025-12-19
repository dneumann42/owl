#include <assert.h>

#include "gc.h"

int main(void) {
    Owl_Alloc alloc = owl_default_alloc_init();
    Owl_GC gc = owl_gc_init(alloc);

    Owl_Object *rooted = owl_new_number(&gc, 1.0);
    Owl_Object *unrooted = owl_new_number(&gc, 2.0);

    OWL_GC_GET_HEADER(rooted)->pinned = F;
    OWL_GC_GET_HEADER(unrooted)->pinned = F;

    owl_gc_add_root(&gc, rooted);
    owl_gc_mark(&gc);
    owl_gc_sweep(&gc);

    Owl_GC_Header *head = gc.heap;
    assert(OWL_GC_OBJECT_FROM_HEADER(head) == rooted);
    assert(head->next == OWL_GC_GET_HEADER(gc.nothing));
    assert(OWL_GC_GET_HEADER(rooted)->marked == F);

    owl_gc_deinit(&gc);
    return 0;
}
