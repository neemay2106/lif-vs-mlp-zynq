/*
 * main.c - MLP bring-up test on ZedBoard (bare metal)
 *
 * 1. soft reset, check idle status
 * 2. load all weights + biases over AXI-Lite, time it
 * 3. write one test image
 * 4. run one inference, time it (PS side) and read hardware cycles
 * 5. compare logits + pred with the Python golden model
 */
#include <stdio.h>
#include "xil_types.h"
#include "xiltimer.h"

#include "mlp_regs.h"
#include "mlp_driver.h"
#include "mlp_weights.h"      /* generated: l1_w_data ... l3_b_data */
#include "mlp_test_image.h"   /* generated: test_pixels, test_expected_logits, TEST_EXPECTED_PRED */

/* PL clock (FCLK_CLK0) set in the Zynq PS config. Check "Actual Frequency" in Vivado. */
#define PL_CLK_HZ   66666667u

static u32 ticks_to_us(XTime t)
{
    return (u32)((t * 1000000ull) / (COUNTS_PER_SECOND));
}

static int fail(const char *step, mlp_status_t s, u32 status)
{
    printf("FAIL at %s: %s (status=0x%08lx: done=%lu running=%lu ready=%lu rejected=%lu)\r\n",
           step, mlp_strerror(s), (unsigned long)status,
           (unsigned long)((status >> 0) & 1u), (unsigned long)((status >> 1) & 1u),
           (unsigned long)((status >> 2) & 1u), (unsigned long)((status >> 3) & 1u));
    return -1;
}

int main(void)
{
    mlp_status_t s;
    u32 cycles = 0, status = 0;
    XTime t0, t1;

    printf("\r\n==== MLP accelerator test ====\r\n");
    printf("IP base = 0x%08lx\r\n", (unsigned long)MLP_BASE);

    /* 1. reset */
    s = mlp_reset();
    if (s != MLP_OK) return fail("reset", s, 0);
    printf("reset ok\r\n");

    /* 2. weights */
    const mlp_params_t params = {
        .l1_w = l1_w_data, .l1_b = l1_b_data,
        .l2_w = l2_w_data, .l2_b = l2_b_data,
        .l3_w = l3_w_data, .l3_b = l3_b_data,
    };
    XTime_GetTime(&t0);
    s = mlp_load_all(&params);
    XTime_GetTime(&t1);
    if (s != MLP_OK) return fail("load_all", s, 0);
    printf("weights loaded in %lu us\r\n", (unsigned long)ticks_to_us(t1 - t0));

    /* 3. image */
    s = mlp_write_image(test_pixels);
    if (s != MLP_OK) return fail("write_image", s, 0);

    /* 4. inference */
    XTime_GetTime(&t0);
    s = mlp_run(&cycles, &status);
    XTime_GetTime(&t1);
    if (s != MLP_OK) return fail("run", s, status);

    /* 5. results */
    s8 logits[MLP_NUM_CLASSES];
    u8 pred = 0;
    mlp_read_results(logits, &pred);

    int errors = 0;
    printf("\r\n class  hw   golden\r\n");
    for (u32 k = 0; k < MLP_NUM_CLASSES; k++) {
        int ok = (logits[k] == test_expected_logits[k]);
        if (!ok) errors++;
        printf("  %lu   %4d   %4d  %s\r\n", (unsigned long)k,
               (int)logits[k], (int)test_expected_logits[k], ok ? "" : "<-- MISMATCH");
    }
    printf("pred = %u (golden %u)\r\n", (unsigned)pred, (unsigned)TEST_EXPECTED_PRED);
    if (pred != TEST_EXPECTED_PRED) errors++;

    printf("\r\nhardware cycles = %lu  (%lu us at %lu Hz)\r\n",
           (unsigned long)cycles,
           (unsigned long)((cycles * 1000000ull) / PL_CLK_HZ),
           (unsigned long)PL_CLK_HZ);
    printf("PS-side run time = %lu us (includes polling)\r\n",
           (unsigned long)ticks_to_us(t1 - t0));

    if (errors == 0) printf("\r\n=== MLP PASS ===\r\n");
    else             printf("\r\n=== MLP FAIL: %d mismatch(es) ===\r\n", errors);

    return errors ? -1 : 0;
}
