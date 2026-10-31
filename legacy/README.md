# legacy

Earlier per-layer design, kept for reference. The final accelerators
(`rtl/lif_top.v`, `rtl/mlp_top.v`) do not use anything in this folder.

- `rtl/` - fixed-size LIF layers (`lif_layer1/2/3.v`), the single-neuron
  `lif_neuron_gated.v`, and the MLP layers `mlp_layer2/3.v`
- `testbenches/` - their testbenches (`forward_pass.v` chains the three LIF layers)
- `expected/` - golden outputs for `lif_neuron_gated_tb.v`, written by
  `python/LIF_neuron.py`. The testbench opens them by bare file name, so run
  that simulation from inside `legacy/expected/` (or copy them next to it).

Some of these testbenches still contain absolute paths from the original
development machine and need editing before they run.
