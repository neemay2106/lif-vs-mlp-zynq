/*
 * snn_driver.h - API for the lif_top AXI-Lite IP
 *
 * The driver touches hardware and returns status codes. It never prints.
 *
 * An image is NUM_TIMESTEPS forward passes. The hardware counts timesteps
 * and class spikes internally and only clears them on reset, so:
 *     snn_reset() before EVERY image.
 */
#ifndef SNN_DRIVER_H
#define SNN_DRIVER_H

#include "xil_types.h"
#include "snn_regs.h"

/* Error codes: 0 = success, negative = failure */
typedef enum {
    SNN_OK                 =  0,
    SNN_ERR_LOAD_COUNT     = -1,   /* PDATA ptr readback != bytes written            */
    SNN_ERR_BAD_ARG        = -2,   /* argument out of range or NULL pointer          */
    SNN_ERR_NOT_READY      = -3,   /* CHAIN_READY never set / RUNNING set at start   */
    SNN_ERR_START_REJECTED = -4,   /* not RUNNING right after start: start was dropped */
    SNN_ERR_RESET          = -5,   /* STATUS not idle after soft reset               */
    SNN_ERR_TIMEOUT        = -6,   /* PASS_DONE not set within the timeout           */
    SNN_ERR_NOT_DONE       = -7    /* STATUS.DONE not set after the last timestep    */
} snn_status_t;

/* The three weight memories (no biases in the LIF datapath) */
typedef struct {
    const u8 *l1_w;
    const u8 *l2_w;
    const u8 *l3_w;
} snn_params_t;

/* Pulse CTRL.RST, wait for CHAIN_READY (layers walk a 256-cycle CLEAR),
   verify idle. Clears membranes, timestep count, class counts. Weights kept. */
snn_status_t snn_reset(void);

/* Stream 'count' bytes into one weight memory, verify via PDATA ptr readback. */
snn_status_t snn_load_mem(u8 layer, const u8 *data, u32 count);

/* Load all three weight memories, stops at the first error. */
snn_status_t snn_load_all(const snn_params_t *p);

/* Reset input ptr, write one timestep: 784 spikes (0/1) packed into 25 words,
   spike i -> word i/32, bit i%32. */
snn_status_t snn_write_spikes(const u8 *spikes);

/* Wait CHAIN_READY, pulse START, confirm RUNNING, poll PASS_DONE with timeout.
   *status: last STATUS read (for diagnosis). */
snn_status_t snn_run_timestep(u32 *status);

/* One full image: for each timestep write spikes + run. Checks STATUS.DONE
   after the last one. Call snn_reset() first.
   *cycles: hardware compute cycles summed over all timesteps.
   *failed_t: timestep index where an error happened (valid on error). */
snn_status_t snn_run_image(const u8 spikes[][SNN_N_IN], u32 *cycles,
                           u32 *status, u32 *failed_t);

/* Read 10 class spike counts, predicted class, skipped-MAC count. */
void snn_read_results(u8 counts[10], u8 *pred, u32 *skipped);

/* Short text for an error code, for printing. */
const char *snn_strerror(snn_status_t s);

#endif /* SNN_DRIVER_H */
