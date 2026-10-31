/*
 * snn_driver.c - hardware access for the lif_top AXI-Lite IP
 *
 * Only this file reads or writes IP registers.
 */
#include <stddef.h>
#include "snn_driver.h"
#include "snn_regs.h"
#include "xil_io.h"      /* Xil_In32, Xil_Out32 */
#include "xiltimer.h"     /* XTime, XTime_GetTime, COUNTS_PER_SECOND */

/* ---- private helpers ---- */
static inline void wr(u32 off, u32 val) { Xil_Out32(SNN_BASE + off, val); }
static inline u32  rd(u32 off)          { return Xil_In32(SNN_BASE + off); }

static void ctrl_pulse(u32 bit)
{
    wr(SNN_CTRL, bit);
    wr(SNN_CTRL, 0);
}

static XTime ms_to_ticks(u32 ms)
{
    return (XTime)ms * COUNTS_PER_SECOND / 1000u;
}

/* Poll STATUS until (status & mask) != 0, or timeout. Returns 1 if seen. */
static int wait_status_bit(u32 mask, u32 timeout_ms, u32 *last)
{
    XTime t0, now;
    const XTime limit = ms_to_ticks(timeout_ms);
    XTime_GetTime(&t0);
    for (;;) {
        u32 st = rd(SNN_STATUS);
        *last = st;
        if (st & mask) return 1;
        XTime_GetTime(&now);
        if (now - t0 > limit) return 0;
    }
}

static const u32 mem_size[3] = { SNN_L1_W_BYTES, SNN_L2_W_BYTES, SNN_L3_W_BYTES };

/* ---- reset ---- */
snn_status_t snn_reset(void)
{
    u32 st;

    ctrl_pulse(SNN_CTRL_RST);

    /* layers clear their membrane memory (256 cycles) before going IDLE */
    if (!wait_status_bit(SNN_STATUS_CHAIN_READY, SNN_RESET_TIMEOUT_MS, &st))
        return SNN_ERR_RESET;

    if (st & (SNN_STATUS_RUNNING | SNN_STATUS_PASS_DONE | SNN_STATUS_DONE))
        return SNN_ERR_RESET;

    return SNN_OK;
}

/* ---- weight load ---- */
snn_status_t snn_load_mem(u8 layer, const u8 *data, u32 count)
{
    if (layer < 1 || layer > 3 || data == NULL)
        return SNN_ERR_BAD_ARG;
    if (count == 0 || count > mem_size[layer - 1])
        return SNN_ERR_BAD_ARG;

    u32 pctrl = 0;
    pctrl |= ((u32)layer << SNN_PCTRL_LAYER_SHIFT) & SNN_PCTRL_LAYER_MASK;
    pctrl |= SNN_PCTRL_RESET_WRPTR;
    wr(SNN_PCTRL, pctrl);

    for (u32 i = 0; i < count; i++) {
        wr(SNN_PDATA, data[i]);
    }

    u32 wr_ptr = (rd(SNN_PDATA) & SNN_PDATA_WRPTR_MASK) >> SNN_PDATA_WRPTR_SHIFT;
    if (wr_ptr != count) {
        return SNN_ERR_LOAD_COUNT;
    }
    return SNN_OK;
}

snn_status_t snn_load_all(const snn_params_t *p)
{
    snn_status_t s;

    if (p == NULL)
        return SNN_ERR_BAD_ARG;

    s = snn_load_mem(1, p->l1_w, SNN_L1_W_BYTES);  if (s != SNN_OK) return s;
    s = snn_load_mem(2, p->l2_w, SNN_L2_W_BYTES);  if (s != SNN_OK) return s;
    s = snn_load_mem(3, p->l3_w, SNN_L3_W_BYTES);  if (s != SNN_OK) return s;

    return SNN_OK;
}

/* ---- one timestep of input: 784 spikes -> 25 words, spike i at word i/32 bit i%32 ---- */
snn_status_t snn_write_spikes(const u8 *spikes)
{
    if (spikes == NULL)
        return SNN_ERR_BAD_ARG;

    wr(SNN_IN_PTR_RST, SNN_IN_PTR_RST_BIT);           /* input_ptr = 0 */

    for (u32 w = 0; w < SNN_IN_WORDS; w++) {
        u32 word = 0;
        for (u32 b = 0; b < 32; b++) {
            u32 i = w * 32 + b;
            if (i < SNN_N_IN && spikes[i])
                word |= (1u << b);
        }
        wr(SNN_IN_DATA, word);
    }
    return SNN_OK;
}

/* ---- one timestep ---- */
snn_status_t snn_run_timestep(u32 *status)
{
    u32 st;

    if (status == NULL)
        return SNN_ERR_BAD_ARG;

    /* chain must be idle, or the start pulse is silently dropped */
    if (!wait_status_bit(SNN_STATUS_CHAIN_READY, SNN_TIMESTEP_TIMEOUT_MS, &st)) {
        *status = st;
        return SNN_ERR_NOT_READY;
    }
    if (st & SNN_STATUS_RUNNING) {
        *status = st;
        return SNN_ERR_NOT_READY;
    }

    ctrl_pulse(SNN_CTRL_START);

    /* PASS_DONE from the previous timestep stays 1 until a start is accepted.
       A timestep takes milliseconds, so right after the start writes the IP
       must be RUNNING with PASS_DONE cleared. If not, the start was dropped
       and polling PASS_DONE would return a stale "done". */
    st = rd(SNN_STATUS);
    *status = st;
    if (!(st & SNN_STATUS_RUNNING) || (st & SNN_STATUS_PASS_DONE))
        return SNN_ERR_START_REJECTED;

    if (!wait_status_bit(SNN_STATUS_PASS_DONE, SNN_TIMESTEP_TIMEOUT_MS, &st)) {
        *status = st;
        return SNN_ERR_TIMEOUT;
    }
    *status = st;
    return SNN_OK;
}

/* ---- one full image ---- */
snn_status_t snn_run_image(const u8 spikes[][SNN_N_IN], u32 *cycles,
                           u32 *status, u32 *failed_t)
{
    snn_status_t s;

    if (spikes == NULL || cycles == NULL || status == NULL || failed_t == NULL)
        return SNN_ERR_BAD_ARG;

    for (u32 t = 0; t < SNN_NUM_TIMESTEPS; t++) {
        *failed_t = t;

        s = snn_write_spikes(spikes[t]);
        if (s != SNN_OK) return s;

        s = snn_run_timestep(status);
        if (s != SNN_OK) return s;
    }

    /* true_done is set only when the last timestep finishes */
    u32 st = rd(SNN_STATUS);
    *status = st;
    if (!(st & SNN_STATUS_DONE))
        return SNN_ERR_NOT_DONE;

    *cycles = rd(SNN_CYCLES);
    return SNN_OK;
}

/* ---- results ---- */
void snn_read_results(u8 counts[10], u8 *pred, u32 *skipped)
{
    u32 w[3];
    w[0] = rd(SNN_COUNT0);      /* classes 0..3 */
    w[1] = rd(SNN_COUNT1);      /* classes 4..7 */
    w[2] = rd(SNN_COUNT2);      /* classes 8..9 in [15:0] */

    for (u32 k = 0; k < SNN_NUM_CLASSES; k++)
        counts[k] = (u8)((w[k / 4] >> ((k % 4) * 8)) & 0xFFu);   /* unsigned counts */

    if (pred != NULL)
        *pred = (u8)(rd(SNN_PRED) & SNN_PRED_MASK);
    if (skipped != NULL)
        *skipped = rd(SNN_SKIPPED);
}

const char *snn_strerror(snn_status_t s)
{
    switch (s) {
    case SNN_OK:                 return "OK";
    case SNN_ERR_LOAD_COUNT:     return "load count mismatch (PDATA ptr readback)";
    case SNN_ERR_BAD_ARG:        return "bad argument";
    case SNN_ERR_NOT_READY:      return "chain not ready / still running before start";
    case SNN_ERR_START_REJECTED: return "start dropped (not running after start)";
    case SNN_ERR_RESET:          return "status not idle after reset";
    case SNN_ERR_TIMEOUT:        return "timeout waiting for pass_done";
    case SNN_ERR_NOT_DONE:       return "done not set after last timestep";
    default:                     return "unknown error";
    }
}
