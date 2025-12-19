#ifndef OWL_ALLOC_H
#define OWL_ALLOC_H
#include <stddef.h>

struct Owl_Alloc {
    void *state;

    void *(*new)(void *state, size_t size);

    void (*del)(void *state, void *ptr);
};

typedef struct Owl_Alloc Owl_Alloc;

Owl_Alloc owl_default_alloc_init(void);

#define OWL_NEW(alloc, size) \
alloc.new(alloc.state, (size))

#define OWL_DEL(alloc, ptr) \
alloc.del(alloc.state, (ptr))

#endif // OWL_ALLOC_H
