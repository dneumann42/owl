#ifndef OWL_STRINGS_H
#define OWL_STRINGS_H
#include <stddef.h>

#include "alloc.h"

struct Owl_String {
    char *data;
    size_t length;
    int owned;
};

typedef struct Owl_String Owl_String;

Owl_String owl_string_new(Owl_Alloc alloc);

void owl_string_del(Owl_String *string, Owl_Alloc alloc);

Owl_String owl_string_concat(Owl_String lhs, Owl_String rhs, Owl_Alloc alloc);

Owl_String owl_string_concat_cstr(Owl_String lhs, const char *rhs, Owl_Alloc alloc);

void owl_string_append(Owl_String *string, Owl_String suffix, Owl_Alloc alloc);

void owl_string_append_cstr(Owl_String *string, const char *suffix, Owl_Alloc alloc);

void owl_string_add_line(Owl_String *string, Owl_String line, Owl_Alloc alloc);

void owl_string_add_line_cstr(Owl_String *string, const char *line, Owl_Alloc alloc);

#endif //OWL_STRINGS_H
