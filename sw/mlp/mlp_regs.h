/*
 * mlp_regs.h - register map of the mlp_top AXI-Lite IP (axi_lite_slave_mp.v)
 *
 * Facts only: base address, offsets, bit fields, sizes. No code.
 * If the RTL register map changes, this is the only file to update.
 */
#ifndef MLP_REGS_H
#define MLP_REGS_H

#include "xparameters.h"

/* ---------------- base address ---------------- */
#define MLP_BASE                    XPAR_MLP_TOP_0_BASEADDR

/* ---------------- register offsets ---------------- */
#define MLP_CTRL                    0x000u  /* RW [0] start, [1] soft reset (level)        */
#define MLP_STATUS                  0x004u  /* RO see MLP_STATUS_* bits                    */
#define MLP_CYCLES                  0x008u  /* RO cycles from accepted start to L3 done    */
#define MLP_PDATA                   0x010u  /* W  one weight/bias byte, wr_ptr++ (WSTRB=F)  */
                                            /* R  {14'd0, wr_ptr[17:0]}                    */
#define MLP_PCTRL                   0x014u  /* W  [1:0] layer, [2] ptr reset, [3] target   */
                                            /* R  [1:0] layer, [3] target, [21:4] wr_ptr   */
#define MLP_IN_DATA                 0x018u  /* W  one input word, input_ptr++ (WSTRB=F)     */
#define MLP_IN_PTR_RST              0x01Cu  /* W  [0]=1 resets input_ptr                   */
#define MLP_PRED                    0x020u  /* RO [3:0] argmax class                       */
#define MLP_LOGIT0                  0x040u  /* RO logits 0..3, logit k at [8k+7:8k]        */
#define MLP_LOGIT1                  0x044u  /* RO logits 4..7                              */
#define MLP_LOGIT2                  0x048u  /* RO logits 8..9 in [15:0]                    */

/* ---------------- CTRL bits ---------------- */
#define MLP_CTRL_START              (1u << 0)
#define MLP_CTRL_RST                (1u << 1)

/* ---------------- STATUS bits ({start_rejected, ready, running, done}) ---------------- */
#define MLP_STATUS_DONE             (1u << 0)   /* sticky until next accepted start */
#define MLP_STATUS_RUNNING          (1u << 1)
#define MLP_STATUS_READY            (1u << 2)
#define MLP_STATUS_START_REJECTED   (1u << 3)

/* ---------------- PDATA readback ---------------- */
#define MLP_PDATA_WRPTR_SHIFT       0
#define MLP_PDATA_WRPTR_MASK        (0x3FFFFu << MLP_PDATA_WRPTR_SHIFT)   /* [17:0] */

/* ---------------- PCTRL fields ---------------- */
#define MLP_PCTRL_LAYER_SHIFT       0
#define MLP_PCTRL_LAYER_MASK        (0x3u << MLP_PCTRL_LAYER_SHIFT)       /* [1:0] 1..3 */
#define MLP_PCTRL_RESET_WRPTR       (1u << 2)                             /* write only */
#define MLP_PCTRL_TARGET_BIAS       (1u << 3)                             /* 0 = weights, 1 = bias */
#define MLP_PCTRL_WRPTR_SHIFT       4
#define MLP_PCTRL_WRPTR_MASK        (0x3FFFFu << MLP_PCTRL_WRPTR_SHIFT)   /* [21:4] read only */

/* ---------------- IN_PTR_RST ---------------- */
#define MLP_IN_PTR_RST_BIT          (1u << 0)

/* ---------------- PRED ---------------- */
#define MLP_PRED_MASK               0xFu

/* ---------------- sizes ---------------- */
#define MLP_N_IN                    784u
#define MLP_N_H1                    256u
#define MLP_N_H2                    128u
#define MLP_NUM_CLASSES             10u

#define MLP_L1_W_BYTES              (MLP_N_IN * MLP_N_H1)       /* 200704 */
#define MLP_L1_B_BYTES              (MLP_N_H1)                  /*    256 */
#define MLP_L2_W_BYTES              (MLP_N_H1 * MLP_N_H2)       /*  32768 */
#define MLP_L2_B_BYTES              (MLP_N_H2)                  /*    128 */
#define MLP_L3_W_BYTES              (MLP_N_H2 * MLP_NUM_CLASSES)/*   1280 */
#define MLP_L3_B_BYTES              (MLP_NUM_CLASSES)           /*     10 */

#define MLP_IN_WORDS                (MLP_N_IN / 4u)             /* 196 words, 4 pixels each */

/* ~470k cycles per image at 66.67 MHz is ~7 ms; 100 ms is ~14x margin */
#define MLP_TIMEOUT_MS              100u

#endif /* MLP_REGS_H */
