#include <assert.h>
#include <string.h>

#include "alloc.h"
#include "strings.h"

static Owl_String make_const(const char *text) {
    return (Owl_String){
        .data = (char *)text,
        .length = (text ? strlen(text) : 0),
        .owned = 0,
    };
}

static void assert_string(Owl_String string, const char *expected, Owl_Alloc alloc) {
    assert(string.length == strlen(expected));
    assert(strcmp(string.data, expected) == 0);
    owl_string_del(&string, alloc);
}

int main(void) {
    Owl_Alloc alloc = owl_default_alloc_init();

    Owl_String lhs = make_const("foo");
    Owl_String rhs = make_const("bar");
    Owl_String concat = owl_string_concat(lhs, rhs, alloc);
    assert_string(concat, "foobar", alloc);

    Owl_String base = make_const("hello");
    Owl_String suffix = make_const(" world");
    owl_string_append(&base, suffix, alloc);
    assert_string(base, "hello world", alloc);

    Owl_String with_cstr = make_const("hi");
    owl_string_append_cstr(&with_cstr, " there", alloc);
    owl_string_append_cstr(&with_cstr, "!", alloc);
    assert_string(with_cstr, "hi there!", alloc);

    Owl_String lines = owl_string_new(alloc);
    owl_string_add_line_cstr(&lines, "one", alloc);
    owl_string_add_line_cstr(&lines, "two", alloc);
    assert_string(lines, "one\ntwo\n", alloc);

    return 0;
}
