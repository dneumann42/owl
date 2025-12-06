#ifndef OWL_GC_H
#define OWL_GC_H

#include "objects.h"

struct Owl_Alloc {
    void *state;

    void *(*new)(void *state, size_t size);

    void (*del)(void *state, void *ptr);
};

typedef struct Owl_Alloc Owl_Alloc;

Owl_Alloc owl_default_alloc_init();

#define OWL_NEW(alloc, size) \
    alloc.new(alloc.state, (size))

#define OWL_DEL(alloc, ptr) \
    alloc.del(alloc.state, (ptr))

struct Owl_GC_Header {
    struct Owl_GC_Header *next;
    Owl_Boolean marked;
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

struct Owl_GC {
    Owl_Alloc alloc;

    Owl_GC_Header **roots;
    size_t root_length;
    size_t root_capacity;

    Owl_GC_Header *heap;
};

typedef struct Owl_GC Owl_GC;

void owl_list_append(Owl_GC *gc, Owl_Object *list, Owl_Object* value);

Owl_GC owl_gc_init(Owl_Alloc alloc);
void owl_gc_deinit(Owl_GC *gc);

void owl_gc_add_root(Owl_GC *gc, Owl_Object *root);

Owl_Object *owl_gc_new(Owl_GC *self, Owl_ObjectType type);

void owl_gc_mark(const Owl_GC *self);

void owl_gc_sweep(Owl_GC *self);

// Constructors
Owl_Object *owl_new_symbol(Owl_GC *self, const char *cstr);
Owl_Object *owl_new_number(Owl_GC *self, double value);
Owl_Object *owl_new_list(Owl_GC *self);

#endif //OWL_GC_H
