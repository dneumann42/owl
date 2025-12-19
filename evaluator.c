//
// Created by dneumann on 12/6/25.
//

#include "evaluator.h"
#include "intrinsics.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>


void owl_add_intrinsic(Owl_Evaluator *eval, owl_intrinsic intrinsic, const char *sym) {
    if (eval->intrinsics.fns == NULL) {
        eval->intrinsics.fns = OWL_NEW(eval->gc->alloc, sizeof(Owl_NamedIntrinsic) * OWL_INTRINSIC_LENGTH);
        eval->intrinsics.capacity = OWL_INTRINSIC_LENGTH;
        eval->intrinsics.length = 1;
        eval->intrinsics.fns[0] = (Owl_NamedIntrinsic){.fn = intrinsic, .sym = sym,};
        return;
    }
    if (eval->intrinsics.length >= eval->intrinsics.capacity) {
        eval->intrinsics.capacity += OWL_INTRINSIC_LENGTH;
        Owl_NamedIntrinsic *old_fns = eval->intrinsics.fns;
        eval->intrinsics.fns = malloc(eval->intrinsics.capacity * sizeof(Owl_NamedIntrinsic));
        for (size_t i = 0; i < eval->intrinsics.length; i++) {
            eval->intrinsics.fns[i] = old_fns[i];
        }
        OWL_DEL(eval->gc->alloc, old_fns);
    }
    eval->intrinsics.fns[eval->intrinsics.length++] = (Owl_NamedIntrinsic){
        .sym = sym,
        .fn = intrinsic,
    };
}

void owl_load_intrinsics(Owl_Evaluator *eval) {
    for (size_t i = 0; i < sizeof(owl_base_intrinsics) / sizeof(owl_base_intrinsics[0]); i++) {
        owl_add_intrinsic(eval, owl_base_intrinsics[i].fn, owl_base_intrinsics[i].sym);
    }
}

Owl_Evaluator owl_eval_init(Owl_GC *gc) {
    Owl_Evaluator eval = (Owl_Evaluator){
        .gc = gc,
        .pc = 0,
        .stack = {0},
        .intrinsics = {.fns = NULL, .length = 0, .capacity = 0}
    };

    owl_load_intrinsics(&eval);

    return eval;
}

void owl_eval_deinit(Owl_Evaluator *eval) {
    if (eval->intrinsics.fns != NULL) {
        OWL_DEL(eval->gc->alloc, eval->intrinsics.fns);
        eval->intrinsics.fns = NULL;
    }
    eval->intrinsics.length = 0;
    eval->intrinsics.capacity = 0;
}

owl_intrinsic owl_get_intrinsic(Owl_Evaluator *eval, const char *sym) {
    for (size_t i = 0; i < eval->intrinsics.length; i++) {
        if (strcmp(eval->intrinsics.fns[i].sym, sym) == 0) {
            return eval->intrinsics.fns[i].fn;
        }
    }
    return NULL;
}

void owl_compile_list(Owl_Evaluator *eval, Owl_Code *code, Owl_Object *object) {
    if (object->value == NULL) {
        return;
    }

    owl_intrinsic intr = owl_get_intrinsic(eval, object->value->symbol.data);
    if (intr != NULL) {
        int arg_count = 0;
        OWL_EACH(it, object->next) {
            owl_code_push(code, it->value);
            arg_count++;
        }
        owl_code_syscall(code, intr, object->value->symbol.data, arg_count);
    }
}

void owl_compile_object(Owl_Evaluator *eval, Owl_Code *code, Owl_Object *object) {
    switch (object->type) {
        case OWL_NOTHING:
        case OWL_NUMBER:
        case OWL_BOOLEAN:
        case OWL_SYMBOL:
        case OWL_STRING:
        case OWL_LIST:
            owl_compile_list(eval, code, object);
        case OWL_ARRAY:
        case OWL_DICT:
            break;
    }
}

Owl_Code owl_compile(Owl_Evaluator *eval, const Owl_Object *script) {
    Owl_Code code = owl_code_init(eval->gc->alloc);

    if (script->type != OWL_LIST || !owl_check_symbol(script->value, "do")) {
        fprintf(stderr, "Expected 'do'\n");
        exit(1);
    }

    Owl_Object *it = script->next;
    while (it != NULL) {
        owl_compile_object(eval, &code, it->value);
        it = it->next;
    }

    return code;
}

Owl_Boolean end_of_program(Owl_Evaluator *eval, Owl_Code code) {
    return (eval->pc >= code.length);
}

Owl_Opcode owl_eval_get_current_opcode(Owl_Evaluator *eval, const Owl_Code code) {
    return code.code[eval->pc];
}

Owl_Object *owl_eval_code(Owl_Evaluator *eval, const Owl_Code code) {
    while (!end_of_program(eval, code)) {
        Owl_Opcode op = owl_eval_get_current_opcode(eval, code);
        switch (op.type) {
        case OWL_OP_NONE:
            break;
        case OWL_OP_JUMP:
            break;
        case OWL_OP_PUSH:
            owl_stack_push(&eval->stack, op.value, eval->gc->alloc);
            break;
        case OWL_OP_SYSCALL: {
            owl_intrinsic intr = op.intrinsic;

            if ((size_t)op.intrinsic_arg_count > eval->stack.length) {
                fprintf(stderr, "stack underflow\n");
                exit(1);
            }

            size_t start = eval->stack.length - op.intrinsic_arg_count;
            Owl_Stack stack = (Owl_Stack){
                .length = op.intrinsic_arg_count,
                .capacity = eval->stack.capacity - start,
                .data = eval->stack.data + start
            };
            intr(eval->gc, &stack);

            eval->stack.length = start + stack.length;
            if (start == 0) {
                eval->stack.data = stack.data;
                eval->stack.capacity = stack.capacity;
            }
        }
        }

        eval->pc++;
    }

    return (eval->stack.length > 0 ? eval->stack.data[eval->stack.length - 1] : eval->gc->nothing);
}

Owl_Object *owl_eval(Owl_GC *gc, const Owl_Object *script) {
    Owl_Evaluator eval = owl_eval_init(gc);

    Owl_Code code = owl_compile(&eval, script);

    Owl_String str = owl_code_tostr(&code);

    printf("[ Bytecode ]\n");
    printf("%.*s\n", (int)str.length, str.data);
    owl_string_del(&str, code.alloc);
    
    Owl_Object *final_result = owl_eval_code(&eval, code);

    Owl_String result_string = owl_object_tostring(final_result, gc->alloc);
    
    printf("[ Result ]\n");
    printf("%.*s\n", (int)result_string.length, result_string.data);

    owl_string_del(&result_string, code.alloc);
    owl_code_deinit(&code);
    owl_eval_deinit(&eval);

    return NULL;
}
