#ifndef OWL_EVALUATOR_H
#define OWL_EVALUATOR_H
#include <stddef.h>

enum Owl_OpcodeType {
    OWL_OP_NONE = 0,
    OWL_OP_JUMP = 1,
};

typedef enum Owl_OpcodeType Owl_OpcodeType;

struct Owl_Opcode {
    Owl_OpcodeType type;
};

typedef struct Owl_Opcode Owl_Opcode;

struct Owl_Code {
    Owl_Opcode *code;
    size_t length;
};

struct Owl_Evaluator {

};

typedef struct Owl_Evaluator Owl_Evaluator;

#endif //OWL_EVALUATOR_H