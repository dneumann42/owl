#include "objects.h"

#include <stdio.h>
#include <string.h>

static void owl_object_tostring_impl(Owl_String *out, const Owl_Object *object, Owl_Alloc alloc);

Owl_Boolean owl_check_symbol(const Owl_Object *object, const char *sym) {
    return (object->type == OWL_SYMBOL ? strcmp(object->symbol.data, sym) == 0 : F);
}

static void owl_object_tostring_list(Owl_String *out, const Owl_Object *list, Owl_Alloc alloc) {
    owl_string_append_cstr(out, "(", alloc);
    const Owl_Object *node = list;
    Owl_Boolean first = T;
    while (node != NULL) {
        if (node->value != NULL) {
            if (!first) {
                owl_string_append_cstr(out, " ", alloc);
            }
            owl_object_tostring_impl(out, node->value, alloc);
            first = F;
        }
        node = node->next;
    }
    owl_string_append_cstr(out, ")", alloc);
}

static void owl_object_tostring_array(Owl_String *out, const Owl_Object *array, Owl_Alloc alloc) {
    owl_string_append_cstr(out, "[", alloc);
    for (size_t i = 0; i < array->length; i++) {
        if (i > 0) {
            owl_string_append_cstr(out, " ", alloc);
        }
        if (array->array[i] != NULL) {
            owl_object_tostring_impl(out, array->array[i], alloc);
        } else {
            owl_string_append_cstr(out, "()", alloc);
        }
    }
    owl_string_append_cstr(out, "]", alloc);
}

static void owl_object_tostring_dict(Owl_String *out, const Owl_Object *dict, Owl_Alloc alloc) {
    owl_string_append_cstr(out, "{", alloc);
    const Owl_Object *node = dict;
    Owl_Boolean first = T;
    while (node != NULL) {
        if (!first) {
            owl_string_append_cstr(out, ", ", alloc);
        }
        if (node->dict_key) {
            owl_object_tostring_impl(out, node->dict_key, alloc);
        } else {
            owl_string_append_cstr(out, "()", alloc);
        }
        owl_string_append_cstr(out, " = ", alloc);
        if (node->dict_value) {
            owl_object_tostring_impl(out, node->dict_value, alloc);
        } else {
            owl_string_append_cstr(out, "()", alloc);
        }
        first = F;
        node = node->dict_next;
    }
    owl_string_append_cstr(out, "}", alloc);
}

static void owl_object_tostring_impl(Owl_String *out, const Owl_Object *object, Owl_Alloc alloc) {
    if (object == NULL) {
        owl_string_append_cstr(out, "()", alloc);
        return;
    }

    char buffer[64];
    switch (object->type) {
        case OWL_NOTHING:
            owl_string_append_cstr(out, "()", alloc);
            break;
        case OWL_NUMBER:
            snprintf(buffer, sizeof(buffer), "%g", object->number);
            owl_string_append_cstr(out, buffer, alloc);
            break;
        case OWL_BOOLEAN:
            owl_string_append_cstr(out, object->boolean == T ? "#t" : "#f", alloc);
            break;
        case OWL_SYMBOL:
            owl_string_append(out, object->symbol, alloc);
            break;
        case OWL_STRING:
            owl_string_append_cstr(out, "\"", alloc);
            owl_string_append(out, object->string, alloc);
            owl_string_append_cstr(out, "\"", alloc);
            break;
        case OWL_LIST:
            owl_object_tostring_list(out, object, alloc);
            break;
        case OWL_ARRAY:
            owl_object_tostring_array(out, object, alloc);
            break;
        case OWL_DICT:
            owl_object_tostring_dict(out, object, alloc);
            break;
    }
}

Owl_String owl_object_tostring(const Owl_Object *object, Owl_Alloc alloc) {
    Owl_String out = owl_string_new(alloc);
    owl_object_tostring_impl(&out, object, alloc);
    return out;
}

void owl_stack_push(Owl_Stack *stack, Owl_Object *object, Owl_Alloc alloc) {
    if (stack->capacity == 0) {
        stack->capacity = 16;
        stack->length = 0;
        stack->data =
            OWL_NEW(alloc, sizeof(Owl_Object) * stack->capacity);
    }
    if (stack->length >= stack->capacity) {
        stack->capacity *= 2;
        size_t new_size = sizeof(Owl_Object) * stack->capacity;
        Owl_Object **new_data =
            OWL_NEW(alloc, new_size);
        memcpy(new_data, stack->data, stack->length * sizeof(Owl_Object));
        OWL_DEL(alloc, stack->data);
        stack->data = new_data;
    }
    stack->data[stack->length++] = object;
}

Owl_Object *owl_stack_pop(Owl_Stack *stack) {
    if (stack->length <= 0)
        return NULL;
    return stack->data[--stack->length];
}
