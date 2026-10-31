/*
 * mlp_driver.c - hardware access for the mlp_top AXI-Lite IP
 *
 * Only this file reads or writes IP registers.
 */
#include <stddef.h>
#include "mlp_driver.h"
#include "mlp_regs.h"
#include "xil_io.h"      /* Xil_In32, Xil_Out32 */
#include "xiltimer.h"     /* XTime, XTime_GetTime, COUNTS_PER_SECOND */

/* ---- private helpers ---- */
static inline void wr(u32 off, u32 val) { Xil_Out32(MLP_BASE + off, val); }
static inline u32  rd(u32 off)          { return Xil_In32(MLP_BASE + off); }

/* write a CTRL bit, then clear it (start and rst are edge/level bits in CTRL) */
static void ctrl_pulse(u32 bit)
{
    wr(MLP_CTRL, bit);
    wr(MLP_CTRL, 0);
}

/* Max bytes per memory, indexed [layer-1][is_bias] */
static const u32 mem_size[3][2] = {
    { MLP_L1_W_BYTES, MLP_L1_B_BYTES },
    { MLP_L2_W_BYTES, MLP_L2_B_BYTES },
    { MLP_L3_W_BYTES, MLP_L3_B_BYTES },
};

/* ---- reset ---- */
mlp_status_t mlp_reset(void)
{
    ctrl_pulse(MLP_CTRL_RST);

    u32 st = rd(MLP_STATUS);
    if (!(st & MLP_STATUS_READY) ||
         (st & (MLP_STATUS_RUNNING | MLP_STATUS_DONE | MLP_STATUS_START_REJECTED)))
        return MLP_ERR_RESET;

    return MLP_OK;
}

/* ---- weight / bias load ---- */
mlp_status_t mlp_load_mem(u8 layer, u8 is_bias, const u8 *data, u32 count)
{
    /* 1. validate before touching hardware */
    if (layer < 1 || layer > 3 || data == NULL)
        return MLP_ERR_BAD_ARG;
    if (count == 0 || count > mem_size[layer - 1][is_bias ? 1 : 0])
        return MLP_ERR_BAD_ARG;

    /* 2. select memory + rewind pointer */
    u32 pctrl = 0;
    pctrl |= ((u32)layer << MLP_PCTRL_LAYER_SHIFT) & MLP_PCTRL_LAYER_MASK;
    pctrl |= MLP_PCTRL_RESET_WRPTR;
    if (is_bias) {
        pctrl |= MLP_PCTRL_TARGET_BIAS;
    }
    wr(MLP_PCTRL, pctrl);

    /* 3. stream bytes, one PDATA write each (Xil_Out32 -> WSTRB = 0xF) */
    for (u32 i = 0; i < count; i++) {
        wr(MLP_PDATA, data[i]);
    }

    /* 4. verify every byte arrived */
    u32 wr_ptr = (rd(MLP_PDATA) & MLP_PDATA_WRPTR_MASK) >> MLP_PDATA_WRPTR_SHIFT;
    if (wr_ptr != count) {
        return MLP_ERR_LOAD_COUNT;
    }
    return MLP_OK;
}

mlp_status_t mlp_load_all(const mlp_params_t *p)
{
    mlp_status_t s;

    if (p == NULL)
        return MLP_ERR_BAD_ARG;

    s = mlp_load_mem(1, 0, p->l1_w, MLP_L1_W_BYTES);  if (s != MLP_OK) return s;
    s = mlp_load_mem(1, 1, p->l1_b, MLP_L1_B_BYTES);  if (s != MLP_OK) return s;
    s = mlp_load_mem(2, 0, p->l2_w, MLP_L2_W_BYTES);  if (s != MLP_OK) return s;
    s = mlp_load_mem(2, 1, p->l2_b, MLP_L2_B_BYTES);  if (s != MLP_OK) return s;
    s = mlp_load_mem(3, 0, p->l3_w, MLP_L3_W_BYTES);  if (s != MLP_OK) return s;
    s = mlp_load_mem(3, 1, p->l3_b, MLP_L3_B_BYTES);  if (s != MLP_OK) return s;

    return MLP_OK;
}

/* ---- input image: 784 pixels -> 196 words, pixel 4w+b in byte b ---- */
mlp_status_t mlp_write_image(const u8 *pixels)
{
    if (pixels == NULL)
        return MLP_ERR_BAD_ARG;

    wr(MLP_IN_PTR_RST, MLP_IN_PTR_RST_BIT);           /* input_ptr = 0 */

    for (u32 w = 0; w < MLP_IN_WORDS; w++) {
        const u8 *px = &pixels[w * 4];
        u32 word = ((u32)px[0] <<  0) |
                   ((u32)px[1] <<  8) |
                   ((u32)px[2] << 16) |
                   ((u32)px[3] << 24);
        wr(MLP_IN_DATA, word);
    }
    return MLP_OK;
}

/* ---- one inference ---- */
mlp_status_t mlp_run(u32 *cycles, u32 *status)
{
    if (cycles == NULL || status == NULL)
        return MLP_ERR_BAD_ARG;

    u32 st = rd(MLP_STATUS);
    *status = st;
    if (!(st & MLP_STATUS_READY))
        return MLP_ERR_NOT_READY;

    ctrl_pulse(MLP_CTRL_START);

    XTime t0, now;
    const XTime limit = (XTime)MLP_TIMEOUT_MS * COUNTS_PER_SECOND / 1000u;
    XTime_GetTime(&t0);

    for (;;) {
        st = rd(MLP_STATUS);
        *status = st;

        if (st & MLP_STATUS_START_REJECTED)
            return MLP_ERR_START_REJECTED;

        if (st & MLP_STATUS_DONE) {
            *cycles = rd(MLP_CYCLES);
            return MLP_OK;
        }

        XTime_GetTime(&now);
        if (now - t0 > limit)
            return MLP_ERR_TIMEOUT;
    }
}

/* ---- results ---- */
void mlp_read_results(s8 logits[10], u8 *pred)
{
    u32 w[3];
    w[0] = rd(MLP_LOGIT0);      /* logits 0..3 */
    w[1] = rd(MLP_LOGIT1);      /* logits 4..7 */
    w[2] = rd(MLP_LOGIT2);      /* logits 8..9 in [15:0] */

    for (u32 k = 0; k < MLP_NUM_CLASSES; k++)
        logits[k] = (s8)((w[k / 4] >> ((k % 4) * 8)) & 0xFFu);

    if (pred != NULL)
        *pred = (u8)(rd(MLP_PRED) & MLP_PRED_MASK);
}

const char *mlp_strerror(mlp_status_t s)
{
    switch (s) {
    case MLP_OK:                 return "OK";
    case MLP_ERR_LOAD_COUNT:     return "load count mismatch (PDATA ptr readback)";
    case MLP_ERR_BAD_ARG:        return "bad argument";
    case MLP_ERR_NOT_READY:      return "not ready before start";
    case MLP_ERR_START_REJECTED: return "start rejected";
    case MLP_ERR_RESET:          return "status not idle after reset";
    case MLP_ERR_TIMEOUT:        return "timeout waiting for done";
    default:                     return "unknown error";
    }
}
