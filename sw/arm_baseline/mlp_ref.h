#include <stdio.h>
#include <stdint.h>
#include "xil_printf.h"

/*MLP layer*/
void layer(const int8_t *in, uint16_t n_in, const int8_t *w, const int8_t *b, uint16_t n_out, int shift, int relu, int8_t *out);


/*full forward pass*/
void mlp_forward(const int8_t *pixels, int8_t *logits);

/*Return the index of the largest logit -> ARGMAX*/
int argmax10(const int8_t *logits);
