/*
 * main.c - SNN (LIF) bring-up test on ZedBoard (bare metal)
 *
 * 1. soft reset, check idle status
 * 2. load the three weight memories over AXI-Lite, time it
 * 3. run one image = 25 timesteps of spikes
 * 4. compare class counts, pred, skipped MACs with the Python golden model
 */
#include <stdio.h>
#include "xil_types.h"
#include "xiltimer.h"

#include "snn_regs.h"
#include "snn_driver.h"
#include "snn_weights.h"       /* generated: l1_w_data, l2_w_data, l3_w_data */
#include "snn_test_spikes.h"   /* generated: test_spikes, test_expected_counts, ... */

/* PL clock (FCLK_CLK0) set in the Zynq PS config. Check "Actual Frequency" in Vivado. */
#define PL_CLK_HZ   66666667u

static u32 ticks_to_us(XTime t)
{
    return (u32)((t * 1000000ull) / COUNTS_PER_SECOND);
}

static int fail(const char *step, snn_status_t s, u32 status)
{
    printf("FAIL at %s: %s (status=0x%08lx: done=%lu running=%lu pass_done=%lu chain_ready=%lu)\r\n",
           step, snn_strerror(s), (unsigned long)status,
           (unsigned long)((status >> 0) & 1u), (unsigned long)((status >> 1) & 1u),
           (unsigned long)((status >> 2) & 1u), (unsigned long)((status >> 3) & 1u));
    return -1;
}

int main(void)
{
    snn_status_t s;
    u32 cycles = 0, status = 0, failed_t = 0;
    XTime t0, t1;

    printf("\r\n==== SNN (LIF) accelerator test ====\r\n");
    printf("IP base = 0x%08lx\r\n", (unsigned long)SNN_BASE);

    /* 1. reset */
    s = snn_reset();
    if (s != SNN_OK) return fail("reset", s, 0);
    printf("reset ok\r\n");

    /* 2. weights */
    const snn_params_t params = {
        .l1_w = l1_w_data,
        .l2_w = l2_w_data,
        .l3_w = l3_w_data,
    };
    XTime_GetTime(&t0);
    s = snn_load_all(&params);
    XTime_GetTime(&t1);
    if (s != SNN_OK) return fail("load_all", s, 0);
    printf("weights loaded in %lu us\r\n", (unsigned long)ticks_to_us(t1 - t0));

    /* 3. one image = SNN_NUM_TIMESTEPS forward passes.
          Reset again so membranes, timestep count and class counts start at 0. */
    s = snn_reset();
    if (s != SNN_OK) return fail("reset before image", s, 0);

    XTime_GetTime(&t0);
    s = snn_run_image(test_spikes, &cycles, &status, &failed_t);
    XTime_GetTime(&t1);
    if (s != SNN_OK) {
        printf("error at timestep %lu\r\n", (unsigned long)failed_t);
        return fail("run_image", s, status);
    }

    /* 4. results */
    u8  counts[SNN_NUM_CLASSES];
    u8  pred = 0;
    u32 skipped = 0;
    snn_read_results(counts, &pred, &skipped);

    int errors = 0;
    printf("\r\n class  hw   golden\r\n");
    for (u32 k = 0; k < SNN_NUM_CLASSES; k++) {
        int ok = (counts[k] == test_expected_counts[k]);
        if (!ok) errors++;
        printf("  %lu   %4u   %4u  %s\r\n", (unsigned long)k,
               (unsigned)counts[k], (unsigned)test_expected_counts[k],
               ok ? "" : "<-- MISMATCH");
    }
    printf("pred = %u (golden %u)\r\n", (unsigned)pred, (unsigned)TEST_EXPECTED_PRED);
    if (pred != TEST_EXPECTED_PRED) errors++;

    printf("skipped MACs = %lu (golden %lu)\r\n",
           (unsigned long)skipped, (unsigned long)TEST_EXPECTED_SKIPPED);
    if (skipped != TEST_EXPECTED_SKIPPED) errors++;

    printf("\r\nhardware compute cycles (%lu timesteps) = %lu  (%lu us at %lu Hz)\r\n",
           (unsigned long)SNN_NUM_TIMESTEPS, (unsigned long)cycles,
           (unsigned long)((cycles * 1000000ull) / PL_CLK_HZ),
           (unsigned long)PL_CLK_HZ);
    printf("PS-side image time = %lu us (includes spike writes + polling)\r\n",
           (unsigned long)ticks_to_us(t1 - t0));

    if (errors == 0) printf("\r\n=== SNN PASS ===\r\n");
    else             printf("\r\n=== SNN FAIL: %d mismatch(es) ===\r\n", errors);

    return errors ? -1 : 0;
}
