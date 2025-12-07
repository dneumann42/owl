#ifndef OWL_GC_H
#define OWL_GC_H

#include "objects.h"
#include "alloc.h"

struct Owl_GC_Header {
    struct Owl_GC_Header *next;
    Owl_Boolean marked;
    Owl_Boolean pinned;
};

typedef struct Owl_GC_Header Owl_GC_Header;

#define OWL_GC_GET_HEADER(p) \
    (((Owl_GC_Header *)(p)) - 1)

#define OWL_GC_OBJECT_FROM_HEADER(h) \
    ((Owl_Object *)(h + 1))

// This is the default number of root nodes allocated,
// resizing will extend the list by OWL_ROOT_COUNT
#define OWL_ROOT_COUNT \
    16

#define OWL_IS_PINNED(o) \
    (OWL_GC_GET_HEADER((o))->pinned == T)

struct Owl_GC {
    Owl_Alloc alloc;

    Owl_GC_Header **roots;
    size_t root_length;
    size_t root_capacity;

    Owl_GC_Header *heap;

    Owl_Object *nothing;
};

typedef struct Owl_GC Owl_GC;

void owl_list_append(Owl_GC *gc, Owl_Object *list, Owl_Object* value);

Owl_GC owl_gc_init(Owl_Alloc alloc);
void owl_gc_deinit(Owl_GC *gc);

void owl_gc_add_root(Owl_GC *gc, Owl_Object *root);
void owl_gc_pin(Owl_Object *object);

Owl_Object *owl_gc_new(Owl_GC *self, Owl_ObjectType type);

void owl_gc_mark(const Owl_GC *self);

void owl_gc_sweep(Owl_GC *self);

// Constructors
Owl_Object *owl_new_nothing(Owl_GC *self);
Owl_Object *owl_new_symbol(Owl_GC *self, const char *cstr);
Owl_Object *owl_new_number(Owl_GC *self, double value);
Owl_Object *owl_new_list(Owl_GC *self);

Owl_Object *owl_new_array(Owl_GC *self, size_t length);

#endif //OWL_GC_H
