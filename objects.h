#ifndef OWL_OBJECTS_H
#define OWL_OBJECTS_H
#include <stddef.h>
#include <stdint.h>

#include "alloc.h"
#include "strings.h"

enum Owl_Boolean {
    F = 0,
    T = 1
};

typedef enum Owl_Boolean Owl_Boolean;

enum Owl_ObjectType {
    OWL_NOTHING,
    OWL_NUMBER,
    OWL_BOOLEAN,
    OWL_SYMBOL,
    OWL_STRING,
    OWL_LIST,
    OWL_ARRAY,
    OWL_DICT
};

typedef enum Owl_ObjectType Owl_ObjectType;

// TODO: optimize size
struct Owl_Object {
    Owl_ObjectType type;
    union {
        double number;
        Owl_String string;
        Owl_String symbol;
        Owl_Boolean boolean;
        struct {
            struct Owl_Object *value;
            struct Owl_Object *next;
        };
        struct {
            struct Owl_Object **array;
            size_t length;
            size_t capacity;
        };
        struct {
            struct Owl_Object *dict_key;
            struct Owl_Object *dict_value;
            struct Owl_Object *dict_next;
        };
    };
};

typedef struct Owl_Object Owl_Object;

Owl_Boolean owl_check_symbol(const Owl_Object *object, const char *sym);

#define OWL_EACH(ident, list) \
    for (Owl_Object *(ident) = (list); (ident) != NULL; (ident) = (ident)->next)

Owl_String owl_string_new(Owl_Alloc alloc);

Owl_String owl_object_tostring(const Owl_Object *object, Owl_Alloc alloc);

#endif //OWL_OBJECTS_H
