// Shared AXI-Lite weight/bias load tasks for mlp_top_tb and lif_top_tb.
//
// Streams a .hex file into one on-chip memory through the PDATA/PCTRL
// registers, exactly the way the PS driver has to do it on hardware.
// Both slaves decode these two addresses identically:
//
//   0x010 PDATA  write: one byte per transfer, auto-incrementing pointer
//                read : {14'd0, wr_ptr}
//   0x014 PCTRL  write: [1:0] layer, [2] pointer reset, [3] target
//                       (target: 0 = weight, 1 = bias; the SNN slave
//                        ignores bit 3, it has no bias memory)
//
// Usage: `include this file INSIDE the testbench module, AFTER write_reg
// and read_reg are defined, since the tasks call them.
//
//   load_mem(2'd1, 1'b0, 784*256, "weights/layer1_weights.hex");
//   load_mem(2'd1, 1'b1, 256,     "weights/layer1_bias.hex");
//
// The testbench must declare `integer errors;` (the tasks bump it on
// mismatch) and the BRAM INIT_FILE parameters must be overridden to ""
// so the load path is the only way data gets in.

localparam [31:0] LOAD_REG_PDATA = 32'h0000_0010;
localparam [31:0] LOAD_REG_PCTRL = 32'h0000_0014;

localparam integer LOAD_BUF_MAX = 784*256;      // largest memory: L1 weights

reg  [7:0]  load_buf [0:LOAD_BUF_MAX-1];
reg  [31:0] load_rdata;
integer     load_i;
integer     load_t0;

// One memory: select it, reset the pointer, stream every byte, verify the count.
task load_mem;
    input [1:0]        layer;      // 1..3
    input              target;     // 0 = weights, 1 = bias
    input integer      count;      // bytes in the file
    input [8*256-1:0]  fname;      // path, as a string literal
    begin
        // clear the buffer so a short file cannot leave stale bytes behind
        for (load_i = 0; load_i < LOAD_BUF_MAX; load_i = load_i + 1)
            load_buf[load_i] = 8'h00;

        // bounded read: the buffer is sized for the biggest memory, so an
        // unbounded $readmemh warns on every smaller file
        $readmemh(fname, load_buf, 0, count-1);

        // layer + target select, pointer reset, all in one write
        write_reg(LOAD_REG_PCTRL, {28'd0, target, 1'b1, layer});

        load_t0 = $time;
        for (load_i = 0; load_i < count; load_i = load_i + 1)
            write_reg(LOAD_REG_PDATA, {24'd0, load_buf[load_i]});

        // pointer readback must equal the byte count, else writes were dropped
        read_reg(LOAD_REG_PDATA, load_rdata);
        if (load_rdata[17:0] !== count[17:0]) begin
            $display("FAIL: load layer=%0d target=%0d wrote %0d bytes, wr_ptr=%0d",
                     layer, target, count, load_rdata[17:0]);
            errors = errors + 1;
        end else begin
            $display("loaded layer=%0d target=%0d %0d bytes in %0d ns",
                     layer, target, count, $time - load_t0);
        end
    end
endtask

// All 6 MLP memories, in file order: weights then bias, layer 1..3.
task load_all_mlp;
    begin
        load_mem(2'd1, 1'b0, 784*256, "weights/layer1_weights.hex");
        load_mem(2'd1, 1'b1, 256,     "weights/layer1_bias.hex");
        load_mem(2'd2, 1'b0, 256*128, "weights/layer2_weights.hex");
        load_mem(2'd2, 1'b1, 128,     "weights/layer2_bias.hex");
        load_mem(2'd3, 1'b0, 128*10,  "weights/layer3_weights.hex");
        load_mem(2'd3, 1'b1, 10,      "weights/layer3_bias.hex");
        $display("MLP load done: 235146 byte writes");
    end
endtask

// All 3 SNN weight memories. No biases in the LIF datapath.
task load_all_snn;
    begin
        load_mem(2'd1, 1'b0, 784*256, "data_layer/weights/weights_layer1.hex");
        load_mem(2'd2, 1'b0, 256*128, "data_layer/weights/weights_layer2.hex");
        load_mem(2'd3, 1'b0, 128*10,  "data_layer/weights/weights_layer3.hex");
        $display("SNN load done: 234752 byte writes");
    end
endtask
