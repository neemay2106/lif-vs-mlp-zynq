/*
 * mlp_driver.h - API for the mlp_top AXI-Lite IP
 *
 * The driver touches hardware and returns status codes. It never prints;
 * the caller decides what to report.
 */
#ifndef MLP_DRIVER_H
#define MLP_DRIVER_H

#include "xil_types.h"

/* Error codes: 0 = success, negative = failure */
typedef enum {
    MLP_OK                 =  0,
    MLP_ERR_LOAD_COUNT     = -1,   /* PDATA ptr readback != bytes written      */
    MLP_ERR_BAD_ARG        = -2,   /* argument out of range or NULL pointer    */
    MLP_ERR_NOT_READY      = -3,   /* STATUS.READY = 0 before start            */
    MLP_ERR_START_REJECTED = -4,   /* STATUS.START_REJECTED = 1 while polling  */
    MLP_ERR_RESET          = -5,   /* STATUS not idle after soft reset         */
    MLP_ERR_TIMEOUT        = -6    /* DONE not set within MLP_TIMEOUT_MS       */
} mlp_status_t;

/* All six parameter memories, as pointers to the caller's arrays */
typedef struct {
    const u8 *l1_w;  const u8 *l1_b;
    const u8 *l2_w;  const u8 *l2_b;
    const u8 *l3_w;  const u8 *l3_b;
} mlp_params_t;

/* Pulse CTRL.RST, verify STATUS is idle + ready. Weights are kept. */
mlp_status_t mlp_reset(void);

/* Stream 'count' bytes into one memory, verify via PDATA ptr readback. */
mlp_status_t mlp_load_mem(u8 layer, u8 is_bias, const u8 *data, u32 count);

/* Load all six memories, stops at the first error. */
mlp_status_t mlp_load_all(const mlp_params_t *p);

/* Reset input ptr, write 784 pixels packed 4 per word (pixel 4w+b in byte b). */
mlp_status_t mlp_write_image(const u8 *pixels);

/* Check READY, pulse START, poll DONE with timeout.
   *cycles: hardware latency. *status: last STATUS read (for diagnosis). */
mlp_status_t mlp_run(u32 *cycles, u32 *status);

/* Read 10 signed logits and the predicted class. */
void mlp_read_results(s8 logits[10], u8 *pred);

/* Short text for an error code, for printing. */
const char *mlp_strerror(mlp_status_t s);

#endif /* MLP_DRIVER_H */
