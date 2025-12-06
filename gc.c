//
// Created by dneumann on 12/6/25.
//

#include "gc.h"

#include <stdio.h>
#include <stdlib.h>

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

Owl_GC owl_gc_init(const Owl_Alloc alloc) {
    return (Owl_GC){
        .alloc = alloc,
        .heap = NULL,
        .root = NULL,
    };
}

Owl_Object *owl_gc_new(Owl_GC *self, const Owl_ObjectType type) {
    Owl_GC_Header *header = OWL_NEW(self->alloc, sizeof(Owl_GC_Header) + sizeof(Owl_Object));
    if (!header) {
        fprintf(stderr, "Out of memory\n");
        exit(1);
    }

    header->marked = F;
    header->next = self->heap;
    self->heap = header;

    Owl_Object *object = (Owl_Object *) (header + 1);
    object->type = type;
    return object;
}

void owl_gc_mark_object(const Owl_Object *object) {
    if (object == NULL) return;

    Owl_GC_Header *h = OWL_GC_GET_HEADER(object);
    if (h->marked == T) return;
    h->marked = T;

    switch (object->type) {
        case OWL_NOTHING:
        case OWL_NUMBER:
        case OWL_BOOLEAN:
        case OWL_SYMBOL:
        case OWL_STRING:
            OWL_GC_GET_HEADER(object)->marked = T;
            break;
        case OWL_LIST: {
            const Owl_Object *list = (Owl_Object *) object;
            owl_gc_mark_object(list->value);
            owl_gc_mark_object(list->next);
            break;
        }
        case OWL_STRUCT: {
            const Owl_Object *list = (Owl_Object *) object;
            owl_gc_mark_object(list->struct_key);
            owl_gc_mark_object(list->struct_value);
            owl_gc_mark_object(list->struct_next);
            break;
        }
    }
}

void owl_gc_mark(Owl_GC *self) {
    if (self->root == NULL) return;
    const Owl_Object *object = OWL_GC_OBJECT_FROM_HEADER(self->root);
    owl_gc_mark_object(object);
}

void owl_gc_sweep(Owl_GC *self) {
    Owl_GC_Header **current = &self->heap;
    while (*current != NULL) {
        Owl_GC_Header *header = *current;
        if (header->marked == F) {
            *current = header->next;
            self->alloc.del(self->alloc.state, header);
        } else {
            header->marked = F;
            current = &header->next;
        }
    }
}
