#ifndef OWL_CODE_H
#define OWL_CODE_H
#include <stddef.h>

#include "gc.h"

enum Owl_OpcodeType {
    OWL_OP_NONE = 0,
    OWL_OP_JUMP = 1,
    OWL_OP_PUSH = 2,
    OWL_OP_SYSCALL = 3
};

typedef enum Owl_OpcodeType Owl_OpcodeType;

struct Owl_Opcode {
    Owl_OpcodeType type;
    Owl_Object *value;
};

typedef struct Owl_Opcode Owl_Opcode;

struct Owl_Code {
    Owl_Opcode *code;
    Owl_Alloc alloc;
    size_t length;
    size_t capacity;
};

typedef struct Owl_Code Owl_Code;

#define OWL_CODE_CAPACITY \
    16

#define OWL_PUSH_OP(v) \
    ((Owl_Opcode) { .type = OWL_OP_PUSH, .value = (v) })

#define OWL_SYSCALL_OP(call) \
    ((Owl_Opcode) { .type = OWL_OP_SYSCALL, .value = (call) })

Owl_Code owl_code_init(Owl_Alloc alloc);
void owl_code_deinit(Owl_Code *code);

void owl_code_resize_if_needed(Owl_Code *code);

void owl_code_push(Owl_Code *code, Owl_Object *op);

void owl_code_syscall(Owl_Code *code, Owl_Object *call);

Owl_String owl_code_tostr(Owl_Code *code);

#endif //OWL_CODE_H