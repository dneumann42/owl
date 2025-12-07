#include "strings.h"

#include <string.h>

static size_t owl_string_cstr_length(const char *text) {
    return (text == NULL ? 0 : strlen(text));
}

static char *owl_string_build_buffer(const char *lhs, size_t lhs_len, const char *rhs, size_t rhs_len, Owl_Alloc alloc) {
    size_t total = lhs_len + rhs_len;
    char *buffer = OWL_NEW(alloc, total + 1);
    if (!buffer) {
        return NULL;
    }

    if (lhs && lhs_len > 0) {
        memcpy(buffer, lhs, lhs_len);
    }

    if (rhs && rhs_len > 0) {
        memcpy(buffer + lhs_len, rhs, rhs_len);
    }

    buffer[total] = '\0';
    return buffer;
}

static void owl_string_replace_data(Owl_String *string, char *buffer, size_t length, Owl_Alloc alloc) {
    if (!buffer) {
        return;
    }

    if (string->owned && string->data) {
        OWL_DEL(alloc, string->data);
    }

    string->data = buffer;
    string->length = length;
    string->owned = 1;
}

static void owl_string_append_bytes(Owl_String *string, const char *suffix, size_t suffix_len, Owl_Alloc alloc) {
    if (suffix_len == 0) {
        return;
    }

    char *buffer = owl_string_build_buffer(string->data, string->length, suffix, suffix_len, alloc);
    if (!buffer) {
        return;
    }

    owl_string_replace_data(string, buffer, string->length + suffix_len, alloc);
}

Owl_String owl_string_new([[maybe_unused]] Owl_Alloc alloc) {
    Owl_String string = {};
    return string;
}

void owl_string_del(Owl_String *string, Owl_Alloc alloc) {
    if (string->owned && string->data) {
        OWL_DEL(alloc, string->data);
    }

    string->data = NULL;
    string->length = 0;
    string->owned = 0;
}

Owl_String owl_string_concat(Owl_String lhs, Owl_String rhs, Owl_Alloc alloc) {
    Owl_String result = {};
    char *buffer = owl_string_build_buffer(lhs.data, lhs.length, rhs.data, rhs.length, alloc);
    if (!buffer) {
        return result;
    }

    result.data = buffer;
    result.length = lhs.length + rhs.length;
    result.owned = 1;
    return result;
}

Owl_String owl_string_concat_cstr(Owl_String lhs, const char *rhs, Owl_Alloc alloc) {
    Owl_String result = {};
    size_t rhs_len = owl_string_cstr_length(rhs);
    char *buffer = owl_string_build_buffer(lhs.data, lhs.length, rhs, rhs_len, alloc);
    if (!buffer) {
        return result;
    }

    result.data = buffer;
    result.length = lhs.length + rhs_len;
    result.owned = 1;
    return result;
}

void owl_string_append(Owl_String *string, Owl_String suffix, Owl_Alloc alloc) {
    owl_string_append_bytes(string, suffix.data, suffix.length, alloc);
}

void owl_string_append_cstr(Owl_String *string, const char *suffix, Owl_Alloc alloc) {
    size_t len = owl_string_cstr_length(suffix);
    owl_string_append_bytes(string, suffix, len, alloc);
}

void owl_string_add_line(Owl_String *string, Owl_String line, Owl_Alloc alloc) {
    owl_string_append(string, line, alloc);
    owl_string_append_cstr(string, "\n", alloc);
}

void owl_string_add_line_cstr(Owl_String *string, const char *line, Owl_Alloc alloc) {
    owl_string_append_cstr(string, line, alloc);
    owl_string_append_cstr(string, "\n", alloc);
}
