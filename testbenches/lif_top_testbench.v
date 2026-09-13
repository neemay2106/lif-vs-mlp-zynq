`timescale 1ns/1ps

// Simple lif_top TB: one forward pass per timestep, 25 timesteps.
// Weights come from the BRAM INIT_FILE preload, no AXI weight load.
module lif_top_tb;

    //=========================================================
    // Register map (matches axi_lite_slave.v byte decode)
    //=========================================================
    localparam [31:0] REG_CONTROL   = 32'h0000_0000;  // [0]=start [1]=rst
    localparam [31:0] REG_STATUS    = 32'h0000_0004;  // [0]=true_done       (RO)
    localparam [31:0] REG_SKIPCNT   = 32'h0000_000C;  //                     (RO)
    localparam [31:0] REG_INDATA    = 32'h0000_0018;  // push one input word
    localparam [31:0] REG_INCTRL    = 32'h0000_001C;  // [0]=reset input_ptr
    localparam [31:0] REG_CLASS0    = 32'h0000_0040;  // classes 0..3        (RO)
    localparam [31:0] REG_CLASS1    = 32'h0000_0044;  // classes 4..7        (RO)
    localparam [31:0] REG_CLASS2    = 32'h0000_0048;  // classes 8..9        (RO)

    localparam integer N_IN_WORDS    = 25;            // 800-bit input_frame / 32
    localparam integer NUM_TIMESTEPS = 25;            // must match lif_top

    // 1 timestep: L1 256*(784*2+2) + L2 128*(256*2+2) + L3 10*(128*2+2)
    // ~= 470k cycles ~= 4.7 ms at 10 ns. 25 timesteps ~= 118 ms.
    localparam integer TIMEOUT_NS = 200_000_000;

    //=========================================================
    // Clock and reset
    //=========================================================
    reg S_AXI_ACLK;
    reg S_AXI_ARESETN;

    initial S_AXI_ACLK = 0;
    always #5 S_AXI_ACLK = ~S_AXI_ACLK;   // 100 MHz

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

    //=========================================================
    // DUT — AXI-Lite only. lif_top has no layer1_input or
    // network_output port now; input arrives over REG_INDATA and
    // results are read from the class-count registers.
    //=========================================================
    lif_top dut (
        .S_AXI_ACLK   (S_AXI_ACLK),
        .S_AXI_ARESETN(S_AXI_ARESETN),
        .S_AXI_AWADDR (S_AXI_AWADDR),
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
        .S_AXI_RREADY (S_AXI_RREADY)
    );

    integer errors = 0;

    //=========================================================
    // AXI-Lite master tasks
    //=========================================================
    // Holds each VALID until its READY, then waits for the write
    // response. Waiting for BVALID clear up front avoids latching
    // the previous transaction's response.
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
    // done_layer_3 pulse counter
    //=========================================================
    // done_layer_3 is a 1-cycle pulse, so a bare wait() can miss it.
    // Count pulses instead and have the loop wait on the count.
    reg     done3_prev;
    integer done3_count;

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            done3_prev  <= 1'b0;
            done3_count <= 0;
        end else begin
            if (dut.done_layer_3 && !done3_prev) done3_count <= done3_count + 1;
            done3_prev <= dut.done_layer_3;
        end
    end

    //=========================================================
    // Global timeout
    //=========================================================
    initial begin
        #TIMEOUT_NS;
        $display("FAIL: timed out after %0d/%0d timesteps", done3_count, NUM_TIMESTEPS);
        errors = errors + 1;
        $finish;
    end

    //=========================================================
    // Progress monitor
    //=========================================================
    initial forever begin
        #10_000_000;   // every 10 ms
        $display("PROGRESS t=%0t ts=%0d done3=%0d | L1 st=%0d n=%0d i=%0d | L2 st=%0d | L3 st=%0d",
                 $time, dut.timestep_count, done3_count,
                 dut.L1.state, dut.L1.neuron_idx, dut.L1.input_idx,
                 dut.L2.state, dut.L3.state);
    end

    //=========================================================
    // Stimulus — one forward pass per timestep
    //=========================================================
    reg [0:0]  spike_bits [0:783];   // one timestep of spikes, 1 bit per line
    reg [799:0] frame;               // 800 bits = 25 words; top 16 unused
    reg [31:0] rdata;
    integer j, t, c, best;
    reg [7:0] class_count [0:9];

    initial begin
        S_AXI_AWADDR  = 0; S_AXI_AWVALID = 0;
        S_AXI_WDATA   = 0; S_AXI_WSTRB   = 4'hF; S_AXI_WVALID = 0;
        S_AXI_BREADY  = 0;
        S_AXI_ARADDR  = 0; S_AXI_ARVALID = 0; S_AXI_RREADY = 0;

        S_AXI_ARESETN = 0;
        repeat (5) @(posedge S_AXI_ACLK);
        S_AXI_ARESETN = 1;
        @(posedge S_AXI_ACLK);

        //-----------------------------------------------------
        // One forward pass per timestep, 25 total
        //-----------------------------------------------------
        for (t = 0; t < NUM_TIMESTEPS; t = t + 1) begin
            // load this timestep's spikes over AXI
            $readmemh($sformatf("spike/spikes_t%0d.txt", t), spike_bits);
            frame = 800'd0;
            for (j = 0; j < 784; j = j + 1) frame[j] = spike_bits[j];

            write_reg(REG_INCTRL, 32'd1);            // reset input_ptr
            for (j = 0; j < N_IN_WORDS; j = j + 1)   // 25 words fill input_frame
                write_reg(REG_INDATA, frame[j*32 +: 32]);

            write_reg(REG_CONTROL, 32'h0000_0001);   // start = 1
            write_reg(REG_CONTROL, 32'h0000_0000);   // start = 0, edge-detected pulse

            wait (done3_count == t + 1);             // pass t finished
            $display("t=%0d done at %0t  out=%b", t, $time, dut.network_output);

            @(posedge S_AXI_ACLK);                   // let done3_pulse update sum_clases
            @(posedge S_AXI_ACLK);                   // and let running clear before next start
        end

        //-----------------------------------------------------
        // Results
        //-----------------------------------------------------
        // true_done asserts only on the last timestep (done3 && timestep_count==25)
        read_reg(REG_STATUS, rdata);
        if (rdata[0] !== 1'b1) begin
            $display("FAIL: status.done = %b after %0d timesteps, expected 1", rdata[0], NUM_TIMESTEPS);
            errors = errors + 1;
        end else begin
            $display("PASS: status.done = 1");
        end

        read_reg(REG_SKIPCNT, rdata);
        $display("skipped_mac_count = %0d", rdata);

        // class counts are 10 bytes packed across three registers
        read_reg(REG_CLASS0, rdata);
        for (c = 0; c < 4; c = c + 1) class_count[c] = rdata[c*8 +: 8];
        read_reg(REG_CLASS1, rdata);
        for (c = 0; c < 4; c = c + 1) class_count[4+c] = rdata[c*8 +: 8];
        read_reg(REG_CLASS2, rdata);
        for (c = 0; c < 2; c = c + 1) class_count[8+c] = rdata[c*8 +: 8];

        best = 0;
        $display("Class counts after %0d timesteps:", NUM_TIMESTEPS);
        for (c = 0; c < 10; c = c + 1) begin
            $display("  class %0d: %0d", c, class_count[c]);
            if (class_count[c] > class_count[best]) best = c;
        end
        $display("Prediction: %0d", best);

        if (errors == 0) $display("=== ALL CHECKS PASSED ===");
        else             $display("=== %0d CHECK(S) FAILED ===", errors);

        $finish;
    end

endmodule
