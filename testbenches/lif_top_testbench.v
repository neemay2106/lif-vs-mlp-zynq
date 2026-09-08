`timescale 1ns/1ps

module lif_top_tb;

    //=========================================================
    // Register map (must match axi_lite_slave.v byte decode)
    //=========================================================
    localparam [31:0] REG_CONTROL   = 32'h0000_0000;  // [0]=start [1]=rst
    localparam [31:0] REG_STATUS    = 32'h0000_0004;  // [0]=done            (RO)
    localparam [31:0] REG_THRESHOLD = 32'h0000_0008;
    localparam [31:0] REG_SKIPCNT   = 32'h0000_000C;  //                      (RO)
    localparam [31:0] REG_WDATA     = 32'h0000_0010;  // W: push weight byte / R: wr_ptr
    localparam [31:0] REG_WCTRL     = 32'h0000_0014;  // W: {rst_ptr, layer}  / R: {wr_ptr, layer}

    localparam integer N_W1 = 784*256;
    localparam integer N_W2 = 256*128;
    localparam integer N_W3 = 128*10;

    localparam integer NUM_TIMESTEPS = 25;

    // Each MAC now costs 2 cycles (ADDR + ACCUMULATE), plus 2 tail cycles per
    // neuron. Per timestep: L1 256*(784*2+2) + L2 128*(256*2+2) + L3 10*(128*2+2)
    // ~= 470k cycles ~= 4.7 ms at 10 ns. 25 timesteps ~= 118 ms.
`ifdef SHORT_RUN
    localparam integer TIMEOUT_NS = `SHORT_RUN;
`else
    localparam integer TIMEOUT_NS = 200_000_000;
`endif

    //=========================================================
    // Clock and reset
    //=========================================================
    reg S_AXI_ACLK;
    reg S_AXI_ARESETN;

    initial S_AXI_ACLK = 0;
    always #5 S_AXI_ACLK = ~S_AXI_ACLK;   // 100 MHz

    reg [783:0] layer1_input;

    // AXI-Lite
    reg  [31:0] S_AXI_AWADDR;
    reg         S_AXI_AWVALID;
    wire        S_AXI_AWREADY;
    reg  [31:0] S_AXI_WDATA;
    reg  [3:0]  S_AXI_WSTRB;
    reg         S_AXI_WVALID;
    wire        S_AXI_WREADY;
    wire [1:0]  S_AXI_BRESP;
    wire        S_AXI_BVALID;
    reg         S_AXI_BREADY;
    reg  [31:0] S_AXI_ARADDR;
    reg         S_AXI_ARVALID;
    wire        S_AXI_ARREADY;
    wire [31:0] S_AXI_RDATA;
    wire [1:0]  S_AXI_RRESP;
    wire        S_AXI_RVALID;
    reg         S_AXI_RREADY;

    wire [9:0]  network_output;

    //=========================================================
    // DUTr1_input (layer1_input),
        
    //=========================================================
    lif_top dut (
        .S_AXI_ACLK   (S_AXI_ACLK),
        .S_AXI_ARESETN(S_AXI_ARESETN),
        .S_AXI_AWADDR (S_AXI_AWADDR),
        .S_AXI_
        .S_AXI_AWVALID(S_AXI_AWVALID),
        .S_AXI_AWREADY(S_AXI_AWREADY),
        .S_AXI_WDATA  (S_AXI_WDATA),
        .S_AXI_WSTRB  (S_AXI_WSTRB),
        .S_AXI_WVALID (S_AXI_WVALID),
        .S_AXI_WREADY (S_AXI_WREADY),
        .S_AXI_BRESP  (S_AXI_BRESP),
        .S_AXI_BVALID (S_AXI_BVALID),
        .S_AXI_BREADY (S_AXI_BREADY),
        .S_AXI_ARADDR (S_AXI_ARADDR),
        .S_AXI_ARVALID(S_AXI_ARVALID),
        .S_AXI_ARREADY(S_AXI_ARREADY),
        .S_AXI_RDATA  (S_AXI_RDATA),
        .S_AXI_RRESP  (S_AXI_RRESP),
        .S_AXI_RVALID (S_AXI_RVALID),
        .S_AXI_RREADY (S_AXI_RREADY),
        .network_output(network_output)
    );

    integer errors = 0;

    //=========================================================
    // AXI-Lite master tasks
    //=========================================================
    // AXI-Lite write. Drives master signals with nonblocking assignments so they
    // stay stable through the whole cycle the slave samples them, holds each
    // VALID until its READY, and only then waits for the write response. Waiting
    // for BVALID to be clear up front prevents latching onto the previous
    // transaction's response.
    task write_reg;
        input [31:0] addr;
        input [31:0] data;
        integer to;
        reg aw_done, w_done;
        begin
            while (S_AXI_BVALID === 1'b1) @(posedge S_AXI_ACLK);

            @(posedge S_AXI_ACLK);
            S_AXI_AWADDR  <= addr;
            S_AXI_AWVALID <= 1'b1;
            S_AXI_WDATA   <= data;
            S_AXI_WSTRB   <= 4'hF;
            S_AXI_WVALID  <= 1'b1;
            S_AXI_BREADY  <= 1'b1;

            aw_done = 0; w_done = 0; to = 0;
            while (!(aw_done && w_done)) begin
                @(posedge S_AXI_ACLK);
                if (!aw_done && S_AXI_AWVALID && S_AXI_AWREADY) begin
                    aw_done = 1; S_AXI_AWVALID <= 1'b0;
                end
                if (!w_done && S_AXI_WVALID && S_AXI_WREADY) begin
                    w_done = 1; S_AXI_WVALID <= 1'b0;
                end
                to = to + 1;
                if (to > 100) begin
                    $display("FAIL: write addr=%h stalled (aw=%b w=%b)", addr, aw_done, w_done);
                    errors = errors + 1; $finish;
                end
            end

            to = 0;
            while (!S_AXI_BVALID) begin
                @(posedge S_AXI_ACLK);
                to = to + 1;
                if (to > 100) begin
                    $display("FAIL: write addr=%h no BVALID", addr);
                    errors = errors + 1; $finish;
                end
            end
            @(posedge S_AXI_ACLK);      // BVALID && BREADY handshake
            S_AXI_BREADY <= 1'b0;
        end
    endtask

    task read_reg;
        input  [31:0] addr;
        output [31:0] data;
        integer to;
        begin
            while (S_AXI_RVALID === 1'b1) @(posedge S_AXI_ACLK);

            @(posedge S_AXI_ACLK);
            S_AXI_ARADDR  <= addr;
            S_AXI_ARVALID <= 1'b1;
            S_AXI_RREADY  <= 1'b1;

            to = 0;
            while (!(S_AXI_ARVALID && S_AXI_ARREADY)) begin
                @(posedge S_AXI_ACLK);
                to = to + 1;
                if (to > 100) begin
                    $display("FAIL: read addr=%h no ARREADY", addr);
                    errors = errors + 1; $finish;
                end
            end
            S_AXI_ARVALID <= 1'b0;

            to = 0;
            while (!S_AXI_RVALID) begin
                @(posedge S_AXI_ACLK);
                to = to + 1;
                if (to > 100) begin
                    $display("FAIL: read addr=%h no RVALID", addr);
                    errors = errors + 1; $finish;
                end
            end
            data = S_AXI_RDATA;
            @(posedge S_AXI_ACLK);      // RVALID && RREADY handshake
            S_AXI_RREADY <= 1'b0;
        end
    endtask

    //=========================================================
    // Golden weights (tb-side copies of the same .hex the BRAMs preload)
    //=========================================================
    reg [7:0] w1_mem [0:N_W1-1];
    reg [7:0] w2_mem [0:N_W2-1];
    reg [7:0] w3_mem [0:N_W3-1];

    initial begin
        $readmemh("data_layer/weights/weights_layer1.hex", w1_mem);
        $readmemh("data_layer/weights/weights_layer2.hex", w2_mem);
        $readmemh("data_layer/weights/weights_layer3.hex", w3_mem);
    end

    //=========================================================
    // Weight-load-over-AXI tasks (enabled with +define+AXI_LOAD)
    //=========================================================
    integer li;

    // Wipe the INIT_FILE preload so the AXI path is genuinely exercised —
    // otherwise a broken loader would be masked by the simulation preload.
    task clear_brams;
        begin
            for (li = 0; li < N_W1; li = li + 1) dut.B1.mem[li] = 8'h00;
            for (li = 0; li < N_W2; li = li + 1) dut.B2.mem[li] = 8'h00;
            for (li = 0; li < N_W3; li = li + 1) dut.B3.mem[li] = 8'h00;
            $display("INFO: BRAMs cleared (preload discarded)");
        end
    endtask

    task load_layer;
        input [1:0]   layer;
        input integer count;
        integer i;
        reg [31:0] rb;
        begin
            $display("INFO: loading layer %0d (%0d bytes) at t=%0t", layer, count, $time);
            write_reg(REG_WCTRL, {29'd0, 1'b1, layer});   // select layer, reset wr_ptr
            for (i = 0; i < count; i = i + 1) begin
                case (layer)
                    2'd1: write_reg(REG_WDATA, {24'd0, w1_mem[i]});
                    2'd2: write_reg(REG_WDATA, {24'd0, w2_mem[i]});
                    2'd3: write_reg(REG_WDATA, {24'd0, w3_mem[i]});
                endcase
            end
            read_reg(REG_WDATA, rb);
            if (rb[17:0] !== count[17:0]) begin
                $display("FAIL: layer %0d wr_ptr=%0d, expected %0d", layer, rb[17:0], count);
                errors = errors + 1;
            end else begin
                $display("PASS: layer %0d wr_ptr=%0d", layer, rb[17:0]);
            end
        end
    endtask

    // Byte-for-byte check that what landed in the BRAMs equals the .hex.
    // Catches wr_ptr offset, layer-select and ordering bugs directly.
    task check_brams;
        integer i, bad1, bad2, bad3;
        begin
            bad1 = 0; bad2 = 0; bad3 = 0;
            for (i = 0; i < N_W1; i = i + 1)
                if (dut.B1.mem[i] !== w1_mem[i]) bad1 = bad1 + 1;
            for (i = 0; i < N_W2; i = i + 1)
                if (dut.B2.mem[i] !== w2_mem[i]) bad2 = bad2 + 1;
            for (i = 0; i < N_W3; i = i + 1)
                if (dut.B3.mem[i] !== w3_mem[i]) bad3 = bad3 + 1;

            if (bad1 || bad2 || bad3) begin
                $display("FAIL: BRAM mismatches  L1=%0d  L2=%0d  L3=%0d", bad1, bad2, bad3);
                errors = errors + 1;
            end else begin
                $display("PASS: all %0d weight bytes match the .hex files", N_W1+N_W2+N_W3);
            end

            // Dump for the Python-side diff (python/check_weight_load.py)
            $writememh("rtl_weights_l1.txt", dut.B1.mem);
            $writememh("rtl_weights_l2.txt", dut.B2.mem);
            $writememh("rtl_weights_l3.txt", dut.B3.mem);
        end
    endtask

    //=========================================================
    // true_done pulse monitor
    //=========================================================
    reg     true_done_prev;
    integer true_done_pulse_count;

    always @(posedge S_AXI_ACLK) begin
        #1;   // sample after NBA updates settle
        if (!S_AXI_ARESETN) begin
            true_done_prev        <= 1'b0;
            true_done_pulse_count <= 0;
        end else begin
            if (dut.true_done && !true_done_prev)
                true_done_pulse_count <= true_done_pulse_count + 1;
            true_done_prev <= dut.true_done;
        end
    end

    //=========================================================
    // Progress monitor
    //=========================================================
    initial begin
        forever begin
            #10_000_000;   // every 10 ms
            $display("PROGRESS t=%0t ts=%0d | L1 st=%0d n=%0d i=%0d | L2 st=%0d n=%0d | L3 st=%0d n=%0d | d1=%b d2=%b d3=%b td=%b",
                     $time, dut.timestep_count,
                     dut.L1.state, dut.L1.neuron_idx, dut.L1.input_idx,
                     dut.L2.state, dut.L2.neuron_idx,
                     dut.L3.state, dut.L3.neuron_idx,
                     dut.done1, dut.done2, dut.done_layer_3, dut.true_done);
        end
    end

    //=========================================================
    // Global timeout
    //=========================================================
    initial begin
        #TIMEOUT_NS;
        $display("FAIL: simulation timed out — true_done never asserted. Stuck at timestep %0d",
                 dut.timestep_count);
        errors = errors + 1;
        $finish;
    end

    //=========================================================
    // Stimulus
    //=========================================================
    reg [0:0] spike_bits [0:783];
    reg [9:0] class_accumulator [0:9];
    reg [31:0] rdata;
    integer j, t, c, best;

    initial begin
        for (c = 0; c < 10; c = c + 1) class_accumulator[c] = 0;

        S_AXI_AWADDR  = 0; S_AXI_AWVALID = 0;
        S_AXI_WDATA   = 0; S_AXI_WSTRB   = 4'hF; S_AXI_WVALID = 0;
        S_AXI_BREADY  = 0;
        S_AXI_ARADDR  = 0; S_AXI_ARVALID = 0; S_AXI_RREADY = 0;
        layer1_input  = 784'd0;

        S_AXI_ARESETN = 0;
        repeat (5) @(posedge S_AXI_ACLK);
        S_AXI_ARESETN = 1;
        @(posedge S_AXI_ACLK);

        //-----------------------------------------------------
        // Phase 1 — weight load
        //-----------------------------------------------------
`ifdef AXI_LOAD
        clear_brams();
        load_layer(2'd1, N_W1);
        load_layer(2'd2, N_W2);
        load_layer(2'd3, N_W3);
        check_brams();
`else
        $display("INFO: using BRAM INIT_FILE preload (rerun with +define+AXI_LOAD to test the AXI load path)");
`endif

        // Runtime threshold. No-op until lif_layer{1,2,3} take a threshold port
        // and lif_top connects threshold_cfg (Gap 1).
        write_reg(REG_THRESHOLD, 32'd256);
        read_reg (REG_THRESHOLD, rdata);
        if (rdata !== 32'd256) begin
            $display("FAIL: threshold readback = %0d, expected 256", rdata);
            errors = errors + 1;
        end else begin
            $display("PASS: threshold register readback = %0d", rdata);
        end

        //-----------------------------------------------------
        // Phase 2 — inference over 25 timesteps
        //-----------------------------------------------------
        for (t = 0; t < NUM_TIMESTEPS; t = t + 1) begin
            $readmemh($sformatf("spike/spikes_t%0d.txt", t), spike_bits);
            for (j = 0; j < 784; j = j + 1)
                layer1_input[j] = spike_bits[j];

            @(posedge S_AXI_ACLK);
            write_reg(REG_CONTROL, 32'h0000_0001);   // start = 1
            write_reg(REG_CONTROL, 32'h0000_0000);   // start = 0  (edge-detected pulse)

            wait (dut.done_layer_3 == 1);

            for (c = 0; c < 10; c = c + 1)
                if (network_output[c])
                    class_accumulator[c] = class_accumulator[c] + 1;

            $display("t=%0d done at %0t  out=%b", t, $time, network_output);
            @(posedge S_AXI_ACLK); #5;
        end

        //-----------------------------------------------------
        // Phase 3 — checks and results
        //-----------------------------------------------------
        wait (dut.true_done == 1);

        if (true_done_pulse_count !== 1) begin
            $display("FAIL: true_done pulsed %0d times, expected exactly 1", true_done_pulse_count);
            errors = errors + 1;
        end else begin
            $display("PASS: true_done pulsed exactly once");
        end

        read_reg(REG_STATUS, rdata);
        if (rdata[0] !== 1'b1) begin
            $display("FAIL: status.done = %b, expected 1", rdata[0]);
            errors = errors + 1;
        end else begin
            $display("PASS: status.done = 1");
        end

        read_reg(REG_SKIPCNT, rdata);
        $display("skipped_mac_count = %0d   (compare against python/LIF_neuron.py)", rdata);

        best = 0;
        $display("Final class counts:");
        for (c = 0; c < 10; c = c + 1) begin
            $display("  class %0d: %0d spikes", c, class_accumulator[c]);
            if (class_accumulator[c] > class_accumulator[best]) best = c;
        end
        $display("Prediction: %0d", best);

        if (errors == 0) $display("=== ALL CHECKS PASSED ===");
        else             $display("=== %0d CHECK(S) FAILED ===", errors);

        $finish;
    end

endmodule
