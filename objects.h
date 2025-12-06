#ifndef OWL_OBJECTS_H
#define OWL_OBJECTS_H
#include <stddef.h>
#include <stdint.h>

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
    OWL_STRUCT
};

typedef enum Owl_ObjectType Owl_ObjectType;

struct Owl_String {
    uint8_t *data;
    size_t length;
    Owl_Boolean owned;
};

typedef struct Owl_String Owl_String;

struct Owl_Object {
    Owl_ObjectType type;
    union {
        double number;
        Owl_String *string;
        Owl_String *symbol;
        Owl_Boolean boolean;
        struct {
            struct Owl_Object *value;
            struct Owl_Object *next;
        };
        struct {
            struct Owl_Object *struct_key;
            struct Owl_Object *struct_value;
            struct Owl_Object *struct_next;
        };
    };
};

typedef struct Owl_Object Owl_Object;

#endif //OWL_OBJECTS_H