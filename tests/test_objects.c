#include <assert.h>
#include <string.h>

#include "alloc.h"
#include "gc.h"
#include "objects.h"

static void assert_string(Owl_String string, const char *expected, Owl_Alloc alloc) {
    assert(string.length == strlen(expected));
    assert(strncmp(string.data, expected, string.length) == 0);
    owl_string_del(&string, alloc);
}

int main(void) {
    Owl_Alloc alloc = owl_default_alloc_init();
    Owl_GC gc = owl_gc_init(alloc);

    Owl_Object *n1 = owl_new_number(&gc, 1.0);
    Owl_Object *n2 = owl_new_number(&gc, 2.0);
    Owl_Object *n3 = owl_new_number(&gc, 3.0);

    Owl_Stack stack = {0};
    owl_stack_push(&stack, n1, alloc);
    owl_stack_push(&stack, n2, alloc);
    owl_stack_push(&stack, n3, alloc);
    assert(stack.length == 3);
    assert(owl_stack_pop(&stack) == n3);
    assert(owl_stack_pop(&stack) == n2);
    assert(owl_stack_pop(&stack) == n1);
    assert(owl_stack_pop(&stack) == NULL);
    OWL_DEL(alloc, stack.data);

    assert_string(owl_object_tostring(n1, alloc), "1", alloc);

    Owl_Object *bool_true = owl_gc_new(&gc, OWL_BOOLEAN);
    bool_true->boolean = T;
    assert_string(owl_object_tostring(bool_true, alloc), "#t", alloc);
    bool_true->boolean = F;
    assert_string(owl_object_tostring(bool_true, alloc), "#f", alloc);

    Owl_Object *sym = owl_new_symbol(&gc, "sym");
    assert(owl_check_symbol(sym, "sym") == T);
    assert(owl_check_symbol(sym, "other") == F);
    assert_string(owl_object_tostring(sym, alloc), "sym", alloc);

    Owl_Object *str_obj = owl_gc_new(&gc, OWL_STRING);
    str_obj->string = (Owl_String){ .data = "abc", .length = 3, .owned = 0 };
    assert_string(owl_object_tostring(str_obj, alloc), "\"abc\"", alloc);

    Owl_Object *list = owl_new_list(&gc);
    owl_list_append(&gc, list, owl_new_number(&gc, 4.0));
    owl_list_append(&gc, list, owl_new_number(&gc, 5.0));
    assert_string(owl_object_tostring(list, alloc), "(4 5)", alloc);

    Owl_Object *array = owl_new_array(&gc, 2);
    array->array[0] = owl_new_number(&gc, 7.0);
    array->array[1] = owl_new_number(&gc, 8.5);
    assert_string(owl_object_tostring(array, alloc), "[7 8.5]", alloc);

    Owl_Object *dict = owl_gc_new(&gc, OWL_DICT);
    dict->dict_key = owl_new_symbol(&gc, "k");
    dict->dict_value = owl_new_number(&gc, 9.0);
    dict->dict_next = NULL;
    assert_string(owl_object_tostring(dict, alloc), "{k = 9}", alloc);

    owl_gc_deinit(&gc);
    return 0;
}
