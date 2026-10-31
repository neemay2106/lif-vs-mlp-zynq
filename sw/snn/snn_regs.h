/*
 * snn_regs.h - register map of the lif_top AXI-Lite IP (axi_lite_slave.v)
 *
 * Facts only: base address, offsets, bit fields, sizes. No code.
 *
 * Differences from the MLP slave:
 *   - no bias memories, PCTRL has no target bit
 *   - input is 25 words of spike bits per timestep (not 196 words of pixels)
 *   - one start = one timestep; an image is NUM_TIMESTEPS starts
 *   - STATUS bits mean different things (see below)
 *   - extra SKIPPED register at 0x00C
 */
#ifndef SNN_REGS_H
#define SNN_REGS_H

#include "xparameters.h"

/* ---------------- base address ---------------- */
/* Check the exact name in xparameters.h after adding lif_top to the block design. */
#define SNN_BASE                    0x43c10000

/* ---------------- register offsets ---------------- */
#define SNN_CTRL                    0x000u  /* RW [0] start (one timestep), [1] soft reset   */
#define SNN_STATUS                  0x004u  /* RO see SNN_STATUS_* bits                      */
#define SNN_CYCLES                  0x008u  /* RO compute cycles, summed over timesteps      */
#define SNN_SKIPPED                 0x00Cu  /* RO skipped MACs (input spike = 0), all layers */
#define SNN_PDATA                   0x010u  /* W  one weight byte, wr_ptr++ (WSTRB=F)         */
                                            /* R  {14'd0, wr_ptr[17:0]}                      */
#define SNN_PCTRL                   0x014u  /* W  [1:0] layer, [2] ptr reset                 */
                                            /* R  [1:0] layer, [19:2] wr_ptr                 */
#define SNN_IN_DATA                 0x018u  /* W  32 spike bits, input_ptr++ (WSTRB=F)        */
#define SNN_IN_PTR_RST              0x01Cu  /* W  [0]=1 resets input_ptr                     */
#define SNN_PRED                    0x020u  /* RO [3:0] argmax of class counts               */
#define SNN_COUNT0                  0x040u  /* RO class counts 0..3, count k at [8k+7:8k]    */
#define SNN_COUNT1                  0x044u  /* RO class counts 4..7                          */
#define SNN_COUNT2                  0x048u  /* RO class counts 8..9 in [15:0]                */

/* ---------------- CTRL bits ---------------- */
#define SNN_CTRL_START              (1u << 0)
#define SNN_CTRL_RST                (1u << 1)

/* ---------------- STATUS bits ({chain_ready, pass_done, running, true_done}) ---------------- */
#define SNN_STATUS_DONE             (1u << 0)   /* all NUM_TIMESTEPS finished (sticky)          */
#define SNN_STATUS_RUNNING          (1u << 1)   /* a timestep is in progress                    */
#define SNN_STATUS_PASS_DONE        (1u << 2)   /* current timestep finished, cleared on start  */
#define SNN_STATUS_CHAIN_READY      (1u << 3)   /* all layers IDLE (0 during 256-cycle CLEAR)   */

/* ---------------- PDATA readback ---------------- */
#define SNN_PDATA_WRPTR_SHIFT       0
#define SNN_PDATA_WRPTR_MASK        (0x3FFFFu << SNN_PDATA_WRPTR_SHIFT)   /* [17:0] */

/* ---------------- PCTRL fields ---------------- */
#define SNN_PCTRL_LAYER_SHIFT       0
#define SNN_PCTRL_LAYER_MASK        (0x3u << SNN_PCTRL_LAYER_SHIFT)       /* [1:0] 1..3 */
#define SNN_PCTRL_RESET_WRPTR       (1u << 2)                             /* write only */
#define SNN_PCTRL_WRPTR_SHIFT       2
#define SNN_PCTRL_WRPTR_MASK        (0x3FFFFu << SNN_PCTRL_WRPTR_SHIFT)   /* [19:2] read only */

/* ---------------- IN_PTR_RST ---------------- */
#define SNN_IN_PTR_RST_BIT          (1u << 0)

/* ---------------- PRED ---------------- */
#define SNN_PRED_MASK               0xFu

/* ---------------- sizes ---------------- */
#define SNN_N_IN                    784u
#define SNN_N_H1                    256u
#define SNN_N_H2                    128u
#define SNN_NUM_CLASSES             10u
#define SNN_NUM_TIMESTEPS           25u     /* must match NUM_TIMESTEPS in lif_top.v */

#define SNN_L1_W_BYTES              (SNN_N_IN * SNN_N_H1)        /* 200704 */
#define SNN_L2_W_BYTES              (SNN_N_H1 * SNN_N_H2)        /*  32768 */
#define SNN_L3_W_BYTES              (SNN_N_H2 * SNN_NUM_CLASSES) /*   1280 */

#define SNN_IN_WORDS                25u     /* 800-bit input_frame / 32; top 16 bits unused */

/* one timestep ~470k cycles at 66.67 MHz is ~7 ms; 100 ms is ~14x margin */
#define SNN_TIMESTEP_TIMEOUT_MS     100u
/* reset: 256-cycle CLEAR is a few us; 10 ms is generous */
#define SNN_RESET_TIMEOUT_MS        10u

#endif /* SNN_REGS_H */
