nn_vitis_sw - bare-metal Vitis apps for the MLP and SNN accelerators (ZedBoard)
==============================================================================

Layout
------
python/
  gen_mlp_headers.py   reads weights/*.hex + mnist_89_q17.hex from the repo,
                       runs a bit-exact model of mlp_layer.v, writes
                       mlp/mlp_weights.h and mlp/mlp_test_image.h
  gen_snn_headers.py   reads data_layer/weights/*.hex + spike/spikes_t*.txt,
                       runs a bit-exact model of lif_layer.v, writes
                       snn/snn_weights.h and snn/snn_test_spikes.h

mlp/   (one Vitis application)
  mlp_regs.h           register map: base, offsets, bit masks, sizes
  mlp_driver.h/.c      reset, load weights, write image, run, read results
  main.c               reset -> load -> image -> run -> compare with golden
  mlp_weights.h        GENERATED, ~1.2 MB of text
  mlp_test_image.h     GENERATED

snn/   (one Vitis application)
  snn_regs.h           register map (differs from MLP, see comments)
  snn_driver.h/.c      reset, load weights, write spikes, run timestep/image,
                       read results
  main.c               reset -> load -> reset -> 25 timesteps -> compare
  snn_weights.h        GENERATED
  snn_test_spikes.h    GENERATED

Golden values (already checked)
-------------------------------
MLP: logits [-77, 80, -41, 4, 0, -61, -56, 11, -28, -32], pred 1
     matches the expected[] values hard-coded in testbenches/mlp_top_tb.v
SNN: counts [3, 0, 0, 0, 1, 2, 12, 0, 4, 0], pred 6, skipped 4920466
     matches python/LIF_neuron.py output exactly

Regenerating the headers
------------------------
  cd python
  python3 gen_mlp_headers.py --repo /path/to/Project_2 --out ../mlp
  python3 gen_snn_headers.py --repo /path/to/Project_2 --out ../snn

Run these again whenever weights, the test image, or the spike files change.

Using in Vitis
--------------
1. Create one application per folder on your platform (e.g. mlp_app, snn_app).
2. Copy all .c and .h files of that folder into the app's src/ directory.
3. Build. The generated headers define static const arrays: include them
   from main.c only.

Things to check before running on the board
-------------------------------------------
- Base address names: mlp_regs.h uses XPAR_MLP_TOP_0_BASEADDR (confirmed).
  snn_regs.h uses XPAR_LIF_TOP_0_BASEADDR (a guess). Check xparameters.h
  after adding lif_top to the block design.
- PL_CLK_HZ in each main.c: set to the ACTUAL FCLK_CLK0 frequency from the
  PS config. It is only used to convert cycles to microseconds.
- Linker script (lscript.ld): weights are ~235 KB of .rodata. Make sure
  .rodata goes to DDR (ps7_ddr_0), not on-chip memory (256 KB).
- Timer header: drivers use xtime_l.h (XTime_GetTime, COUNTS_PER_SECOND).
  If your BSP version does not have it, grep the BSP include folder for
  XTime_GetTime.
- SNN: call snn_reset() before every image. The IP only clears its timestep
  counter and class counts on reset.

Driver notes
------------
- Only *_driver.c touches registers. main.c only calls the API.
- Drivers never print. They return status codes; *_strerror() gives text.
- All register writes use Xil_Out32 so WSTRB = 0xF. PDATA and IN_DATA reject
  partial-strobe writes with SLVERR.
- Every load is verified by reading back the hardware write pointer.
- Every wait has a timeout (XTime based) and returns the last STATUS value,
  so a hang reports where the hardware is stuck.

RTL comment to fix in the repo
------------------------------
rtl/axi_lite_slave_mp.v line ~157 says "1 for weights and 0 for biases".
The real logic in mlp_top.v is 0 = weights, 1 = bias.
