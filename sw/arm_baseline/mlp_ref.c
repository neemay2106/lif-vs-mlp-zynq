#include <stdio.h>
#include <stdint.h>
#include "xil_printf.h"
#include "mlp_ref.h"
#include "mlp_weights.h"
#include "mlp_test_image.h"


static int8_t saturate(int32_t x)
{
    if (x > 127)  return 127;
    if (x < -128) return -128;
    return (int8_t)x;
}

void layer(const int8_t *in, uint16_t n_in, const int8_t *w, const int8_t *b, uint16_t n_out, int shift, int relu, int8_t *out){

    for(int j = 0; j < n_out; j++){
        int32_t acc = 0;                         
        const int8_t *w_row = &w[j * n_in];       

        for(int i = 0; i < n_in; i++){
            acc += (int32_t)in[i] * w_row[i];     
        }

        acc = acc >> shift;                       
        acc += b[j];                              

        if(relu && acc < 0){ acc = 0; }

        out[j] = saturate(acc);                   
    }
}


void mlp_forward(const int8_t *pixels, int8_t *logits){
    int8_t acc1[256];
    int8_t acc2[128];

    layer((const int8_t *)pixels, 784, (const int8_t *)l1_w_data, (const int8_t *)l1_b_data, 256, 7, 1, acc1);
    layer((const int8_t *)acc1, 256, (const int8_t *)l2_w_data, (const int8_t *)l2_b_data, 128, 7, 1, acc2);
    layer((const int8_t *)acc2, 128, (const int8_t *)l3_w_data, (const int8_t *)l3_b_data, 10, 9, 0, logits);
}

int argmax10(const int8_t *logits){

    int best = 0;                          // start with class 0

    for(int k = 1; k < 10; k++){
        if(logits[k] > logits[best]){      // strict >: a tie keeps the earlier index
            best = k;
        }
    }
    return best;
}