#include "code.h"

#include <assert.h>
#include <string.h>

Owl_Code owl_code_init(const Owl_Alloc alloc) {
    Owl_Code code;
    code.length = 0;
    code.capacity = OWL_CODE_CAPACITY;
    code.code = OWL_NEW(alloc, code.capacity * sizeof(Owl_Opcode));
    code.alloc = alloc;
    memset(code.code, 0, code.capacity * sizeof(Owl_Opcode));
    return code;
}

void owl_code_deinit(Owl_Code *code) {
    OWL_DEL(code->alloc, code->code);
    code->length = 0;
    code->capacity = 0;
}

void owl_code_resize_if_needed(Owl_Code *code) {
    if (code->length < code->capacity) {
        return;
    }
    Owl_Opcode *old_code = code->code;
    code->capacity *= 2;
    code->code = OWL_NEW(code->alloc, code->capacity * sizeof(Owl_Opcode));
    memcpy(code->code, old_code, code->length * sizeof(Owl_Opcode));
    OWL_DEL(code->alloc, old_code);
}

void owl_code_push(Owl_Code *code, Owl_Object *op) {
    owl_code_resize_if_needed(code);
    code->code[code->length++] = OWL_PUSH_OP(op);
}

void owl_code_syscall(Owl_Code *code, Owl_Object *call) {
    assert(call->type == OWL_SYMBOL);

    owl_code_resize_if_needed(code);
    code->code[code->length++] = OWL_SYSCALL_OP(call);
}

Owl_String owl_code_tostr(Owl_Code *code) {
    Owl_String result = owl_string_new(code->alloc);
    for (size_t i = 0; i < code->length; i++) {
        switch (code->code[i].type) {
            case OWL_OP_NONE:
                owl_string_add_line_cstr(&result, "NOP", code->alloc);
                break;
            case OWL_OP_JUMP:
                owl_string_add_line_cstr(&result, "JUMP", code->alloc);
                break;
            case OWL_OP_PUSH:
                Owl_String push_value = owl_object_tostring(code->code[i].value, code->alloc);
                Owl_String push_line = owl_string_new(code->alloc);
                owl_string_append_cstr(&push_line, "PUSH ", code->alloc);
                owl_string_append(&push_line, push_value, code->alloc);
                owl_string_add_line(&result, push_line, code->alloc);
                owl_string_del(&push_line, code->alloc);
                owl_string_del(&push_value, code->alloc);
                break;
            case OWL_OP_SYSCALL:
                Owl_String call_value = owl_object_tostring(code->code[i].value, code->alloc);
                Owl_String sys = owl_string_new(code->alloc);
                owl_string_append_cstr(&sys, "SYSCALL ", code->alloc);
                owl_string_append(&sys, call_value, code->alloc);
                owl_string_add_line(&result, sys, code->alloc);
                owl_string_del(&sys, code->alloc);
                owl_string_del(&call_value, code->alloc);
                break;
        }
    }
    return result;
}
