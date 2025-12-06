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

struct Owl_GC {
    Owl_Alloc alloc;
    Owl_GC_Header *root;
    Owl_GC_Header *heap;
};

typedef struct Owl_GC Owl_GC;

Owl_GC owl_gc_init(Owl_Alloc alloc);

Owl_Object *owl_gc_new(Owl_GC *self, Owl_ObjectType type);

void owl_gc_mark(Owl_GC *self);

void owl_gc_sweep(Owl_GC *self);

#endif //OWL_GC_H
