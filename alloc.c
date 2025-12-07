#include "alloc.h"

#include <stddef.h>
#include <stdlib.h>

#include "objects.h"

void *owl_default_new([[maybe_unused]] void *state, const size_t size) {
    return malloc(size);
}

void owl_default_del([[maybe_unused]] void *state, void *ptr) {
    free(ptr);
}

Owl_Alloc owl_default_alloc_init() {
    return (Owl_Alloc){
        .state = NULL,
        .new = owl_default_new,
        .del = owl_default_del,
    };
}
