/*
 * main.c - ARM-only MLP baseline on ZedBoard (bare metal)
 *
 * 1. run one forward pass in C, check logits + pred against the Python golden model
 * 2. time N_RUNS passes with XTime, print the average per image
 * Compare with the PL: 471,085 cycles = 7.07 ms (compute only).
 */
#include <stdio.h>
#include <stdint.h>
#include "xil_types.h"
#include "xiltimer.h"

#include "mlp_ref.h"
#include "mlp_test_image.h"   /* generated: test_pixels, test_expected_logits, TEST_EXPECTED_PRED */

#define N_RUNS  100u

static u32 ticks_to_us(XTime t)
{
    return (u32)((t * 1000000ull) / (COUNTS_PER_SECOND));
}

int main(void)
{
    int8_t logits[10];
    XTime t0, t1;
    int errors = 0;

    printf("\r\n==== ARM baseline: MLP in C ====\r\n");

    /* 1. correctness first: one pass, compare with golden */
    mlp_forward((const int8_t *)test_pixels, logits);
    int pred = argmax10(logits);

    printf("logits:");
    for (int k = 0; k < 10; k++) {
        printf(" %d", logits[k]);
        if (logits[k] != test_expected_logits[k]) errors++;
    }
    printf("\r\npred = %d (expected %u)\r\n", pred, TEST_EXPECTED_PRED);
    if (pred != (int)TEST_EXPECTED_PRED) errors++;

    if (errors) {
        printf("=== ARM FAIL: %d mismatches ===\r\n", errors);
        return -1;
    }

    /* 2. timing: many passes, one pass is too short to measure well */
    XTime_GetTime(&t0);
    for (u32 r = 0; r < N_RUNS; r++) {
        mlp_forward((const int8_t *)test_pixels, logits);
    }
    XTime_GetTime(&t1);

    /* use the result so -O2/-O3 cannot delete the loop */
    if (argmax10(logits) != (int)TEST_EXPECTED_PRED) {
        printf("=== ARM FAIL: result changed during timing ===\r\n");
        return -1;
    }

    XTime total = t1 - t0;
    printf("%u runs: %lu ticks, %lu us total\r\n",
           N_RUNS, (unsigned long)total, (unsigned long)ticks_to_us(total));
    printf("per image: %lu us   (PL compute: 7066 us)\r\n",
           (unsigned long)(ticks_to_us(total) / N_RUNS));
    printf("COUNTS_PER_SECOND = %lu\r\n", (unsigned long)COUNTS_PER_SECOND);

    printf("=== ARM PASS ===\r\n");
    return 0;
}