//
// Created by dneumann on 12/6/25.
//

#include "gc.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void owl_list_append(Owl_GC *gc, Owl_Object *list, Owl_Object *value) {
    if (list == NULL || value == NULL) return;
    if (list->value == NULL) {
        list->value = value;
        list->next = NULL;
        return;
    }
    Owl_Object *it = list;
    while (it->next != NULL) {
        it = it->next;
    }
    Owl_Object *node = owl_gc_new(gc, OWL_LIST);
    node->value = value;
    node->next = NULL;
    it->next = node;
}

Owl_GC owl_gc_init(const Owl_Alloc alloc) {
    Owl_GC gc = (Owl_GC){
        .alloc = alloc,
        .heap = NULL,
        .roots = OWL_NEW(alloc, sizeof(Owl_GC_Header*)*OWL_ROOT_COUNT),
        .root_length = 0,
        .root_capacity = OWL_ROOT_COUNT,
        .nothing = NULL
    };

    gc.nothing = owl_new_nothing(&gc);

    if (gc.roots == NULL) {
        fprintf(stderr, "Failed to allocate roots\n");
        exit(1);
    }

    return gc;
}

void owl_gc_add_root(Owl_GC *gc, Owl_Object *root) {
    if (gc->root_length >= gc->root_capacity) {
        gc->root_capacity += OWL_ROOT_COUNT;
        Owl_GC_Header **new_list = OWL_NEW(gc->alloc, sizeof(Owl_GC_Header*)*gc->root_capacity);
        if (new_list == NULL) {
            fprintf(stderr, "Failed to allocate roots\n");
            exit(1);
        }
    }
    gc->roots[gc->root_length++] = OWL_GC_GET_HEADER(root);
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
        case OWL_DICT: {
            const Owl_Object *list = (Owl_Object *) object;
            owl_gc_mark_object(list->dict_key);
            owl_gc_mark_object(list->dict_value);
            owl_gc_mark_object(list->dict_next);
            break;
        }
        case OWL_ARRAY:
            // TODO: what should I do here?
            break;
        }
}

void owl_gc_mark(const Owl_GC *self) {
    for (size_t i = 0; i < self->root_length; i++) {
        Owl_GC_Header *root = self->roots[i];
        if (root == NULL) continue;
        const Owl_Object *object = OWL_GC_OBJECT_FROM_HEADER(root);
        owl_gc_mark_object(object);
    }
}

void owl_gc_sweep(Owl_GC *self) {
    Owl_GC_Header **current = &self->heap;
    while (*current != NULL) {
        Owl_GC_Header *header = *current;
        if (header->marked == F && header->pinned == F) {
            *current = header->next;
            self->alloc.del(self->alloc.state, header);
        } else {
            header->marked = F;
            current = &header->next;
        }
    }
}

void owl_gc_deinit(Owl_GC *gc) {
    OWL_DEL(gc->alloc, gc->roots);
    gc->root_length = 0;
    gc->root_capacity = 0;
    Owl_GC_Header *current = gc->heap;
    while (current != NULL) {
        Owl_GC_Header *header = current;
        current = current->next;
        free(header);
    }
}

void owl_gc_pin(Owl_Object *object) {
    OWL_GC_GET_HEADER(object)->pinned = T;
}

Owl_Object *owl_new_symbol(Owl_GC *self, const char *cstr) {
    Owl_Object *s = owl_gc_new(self, OWL_SYMBOL);
    s->symbol.data = (char *) (cstr);
    s->symbol.length = strlen(cstr);
    s->symbol.owned = false;
    return s;
}

Owl_Object *owl_new_number(Owl_GC *self, const double value) {
    Owl_Object *n = owl_gc_new(self, OWL_NUMBER);
    n->number = value;
    return n;
}

Owl_Object *owl_new_list(Owl_GC *self) {
    Owl_Object *list = owl_gc_new(self, OWL_LIST);
    list->next = NULL;
    list->value = NULL;
    return list;
}

Owl_Object *owl_new_nothing(Owl_GC *self) {
    if (self->nothing == NULL) {
        self->nothing = owl_gc_new(self, OWL_NOTHING);
        owl_gc_pin(self->nothing);
    }
    return self->nothing;
}

Owl_Object *owl_new_array(Owl_GC *self, size_t length) {
    Owl_Object *array = owl_gc_new(self, OWL_ARRAY);
    array->array = OWL_NEW(self->alloc, sizeof(Owl_Object *) * length);
    memset(array->array, 0, sizeof(Owl_Object *) * length);
    array->length = length;
    array->capacity = length;
    return array;
}
