`timescale 1ns/1ps

// Single-image smoke test for mlp_top over AXI-Lite only.
// Weights come from the bram INIT_FILE preload, no AXI weight load yet.
// No hierarchical peeks: completion is polled from the STATUS register,
// exactly as a PS driver would do it.
module mlp_top_tb;

    //=========================================================
    // Register map (matches axi_lite_slave_mp.v)
    //=========================================================
    localparam [31:0] REG_CONTROL = 32'h0000_0000;  // [0]=start [1]=soft reset
    localparam [31:0] REG_STATUS  = 32'h0000_0004;  // [0]=done [1]=running [2]=ready [3]=start_rejected
    localparam [31:0] REG_CYCLES  = 32'h0000_0008;  // cycles for the last image
    localparam [31:0] REG_PRED    = 32'h0000_0020;  // argmax
    localparam [31:0] REG_INDATA  = 32'h0000_0018;  // 4 pixels per word
    localparam [31:0] REG_INCTRL  = 32'h0000_001C;  // [0]=reset input_ptr
    localparam [31:0] REG_LOGIT0  = 32'h0000_0040;  // classes 0..3
    localparam [31:0] REG_LOGIT1  = 32'h0000_0044;  // classes 4..7
    localparam [31:0] REG_LOGIT2  = 32'h0000_0048;  // classes 8..9

    localparam integer N_IN_WORDS = 196;            // 784 pixels / 4 per word

    // 2 cycles per input: L1 256*1572 + L2 128*516 + L3 10*260 ~= 471k cycles
    localparam integer TIMEOUT_NS = 20_000_000;

    //=========================================================
    // Clock and reset
    //=========================================================
    reg S_AXI_ACLK;
    reg S_AXI_ARESETN;

    initial S_AXI_ACLK = 0;
    always #5 S_AXI_ACLK = ~S_AXI_ACLK;             // 100 MHz, same as the SNN

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

    // LOAD_OVER_AXI=1 empties the BRAM preload and streams all 6 memories
    // through PDATA/PCTRL instead — the only path that exists on hardware.
    // Run both ways: `iverilog -DLOAD_OVER_AXI ...`
`ifdef LOAD_OVER_AXI
    localparam LOAD_OVER_AXI = 1;
    mlp_top #(.W1_INIT(""), .B1_INIT(""), .W2_INIT(""),
              .B2_INIT(""), .W3_INIT(""), .B3_INIT("")) dut (
`else
    localparam LOAD_OVER_AXI = 0;
    mlp_top dut (
`endif
        .S_AXI_ACLK   (S_AXI_ACLK),
        .S_AXI_ARESETN(S_AXI_ARESETN),
        .S_AXI_AWADDR (S_AXI_AWADDR),
        .S_AXI_AWPROT (3'b000),
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
        .S_AXI_ARPROT (3'b000),
        .S_AXI_ARVALID(S_AXI_ARVALID),
        .S_AXI_ARREADY(S_AXI_ARREADY),
        .S_AXI_RDATA  (S_AXI_RDATA),
        .S_AXI_RRESP  (S_AXI_RRESP),
        .S_AXI_RVALID (S_AXI_RVALID),
        .S_AXI_RREADY (S_AXI_RREADY)
    );

    integer errors = 0;
    integer load_cycles;

    //=========================================================
    // AXI-Lite master tasks
    //=========================================================
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
            if (S_AXI_BRESP !== 2'b00) begin
                $display("FAIL: write addr=%h BRESP=%b, expected OKAY", addr, S_AXI_BRESP);
                errors = errors + 1;
            end
            @(posedge S_AXI_ACLK);              // BVALID && BREADY handshake
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
            @(posedge S_AXI_ACLK);              // RVALID && RREADY handshake
            S_AXI_RREADY <= 1'b0;
        end
    endtask

`include "testbenches/axi_load_tasks.vh"

    //=========================================================
    // Global timeout
    //=========================================================
    initial begin
        #TIMEOUT_NS;
        $display("FAIL: timed out");
        errors = errors + 1;
        $finish;
    end

    //=========================================================
    // Stimulus
    //=========================================================
    reg  [7:0]  img [0:783];            // one image, Q1.7 pixels 0..127
    reg  [31:0] rdata;
    reg  [79:0] logits;
    integer j, c, best, polls;
    reg signed [7:0] logit;
    reg signed [7:0] best_val;

    // golden logits for mnist_89_q17.hex, from python/mlp_forward_pass.py
    reg signed [7:0] expected [0:9];
    initial begin
        expected[0] = -77; expected[1] =  80; expected[2] = -41; expected[3] =   4;
        expected[4] =   0; expected[5] = -61; expected[6] = -56; expected[7] =  11;
        expected[8] = -28; expected[9] = -32;
    end

    initial begin
        S_AXI_AWADDR  = 0; S_AXI_AWVALID = 0;
        S_AXI_WDATA   = 0; S_AXI_WSTRB   = 4'hF; S_AXI_WVALID = 0;
        S_AXI_BREADY  = 0;
        S_AXI_ARADDR  = 0; S_AXI_ARVALID = 0; S_AXI_RREADY = 0;

        $readmemh("mnist_89_q17.hex", img);

        S_AXI_ARESETN = 0;
        repeat (5) @(posedge S_AXI_ACLK);
        S_AXI_ARESETN = 1;
        @(posedge S_AXI_ACLK);

        //-----------------------------------------------------
        // reset state: ready high, nothing else set
        //-----------------------------------------------------
        read_reg(REG_STATUS, rdata);
        if (rdata[2] !== 1'b1) begin
            $display("FAIL: status=%b after reset, expected ready", rdata[3:0]);
            errors = errors + 1;
        end
        if (rdata[1] !== 1'b0 || rdata[0] !== 1'b0) begin
            $display("FAIL: status=%b after reset, expected idle and not done", rdata[3:0]);
            errors = errors + 1;
        end

        //-----------------------------------------------------
        // weights and biases over AXI, when the preload is off
        //-----------------------------------------------------
        if (LOAD_OVER_AXI) begin
            load_cycles = $time;
            load_all_mlp;
            $display("weight+bias load took %0d cycles", ($time - load_cycles) / 10);
        end

        //-----------------------------------------------------
        // load the image: 196 words, 4 pixels each
        //-----------------------------------------------------
        write_reg(REG_INCTRL, 32'd1);               // input_ptr = 0
        for (j = 0; j < N_IN_WORDS; j = j + 1)
            write_reg(REG_INDATA, {img[j*4+3], img[j*4+2], img[j*4+1], img[j*4+0]});

        //-----------------------------------------------------
        // start
        //-----------------------------------------------------
        read_reg(REG_STATUS, rdata);
        if (!rdata[2]) begin
            $display("FAIL: not ready before start, status=%b", rdata[3:0]);
            errors = errors + 1;
        end

        write_reg(REG_CONTROL, 32'h0000_0001);      // start = 1
        write_reg(REG_CONTROL, 32'h0000_0000);      // start = 0, edge detected

        //-----------------------------------------------------
        // poll done, same as a PS driver
        //-----------------------------------------------------
        polls = 0;
        rdata = 0;
        while (!rdata[0]) begin
            read_reg(REG_STATUS, rdata);
            if (rdata[3]) begin
                $display("FAIL: start_rejected set, status=%b", rdata[3:0]);
                errors = errors + 1; $finish;
            end
            polls = polls + 1;
            if (polls > 200000) begin
                $display("FAIL: done never set, status=%b", rdata[3:0]);
                errors = errors + 1; $finish;
            end
        end
        $display("done at %0t after %0d status polls", $time, polls);

        if (rdata[1] !== 1'b0) begin
            $display("FAIL: still running when done is set, status=%b", rdata[3:0]);
            errors = errors + 1;
        end

        //-----------------------------------------------------
        // results
        //-----------------------------------------------------
        read_reg(REG_LOGIT0, rdata); logits[31:0]  = rdata;
        read_reg(REG_LOGIT1, rdata); logits[63:32] = rdata;
        read_reg(REG_LOGIT2, rdata); logits[79:64] = rdata[15:0];

        best = 0;
        best_val = $signed(logits[7:0]);
        for (c = 0; c < 10; c = c + 1) begin
            logit = $signed(logits[c*8 +: 8]);
            $display("  logit[%0d] = %0d (expected %0d)", c, logit, expected[c]);
            if (logit !== expected[c]) begin
                $display("FAIL: logit[%0d] = %0d, expected %0d", c, logit, expected[c]);
                errors = errors + 1;
            end
            if (logit > best_val) begin
                best_val = logit;
                best = c;
            end
        end
        $display("Prediction: %0d", best);

        read_reg(REG_PRED, rdata);
        if (rdata[3:0] !== best[3:0]) begin
            $display("FAIL: PRED = %0d, expected %0d", rdata[3:0], best);
            errors = errors + 1;
        end

        read_reg(REG_CYCLES, rdata);
        $display("cycles per image = %0d (%0.2f ms at 100 MHz)", rdata, rdata / 100000.0);
        if (rdata < 32'd400_000 || rdata > 32'd500_000) begin
            $display("FAIL: cycles = %0d, expected ~471900", rdata);
            errors = errors + 1;
        end

        if (errors == 0) $display("=== ALL CHECKS PASSED ===");
        else             $display("=== %0d CHECK(S) FAILED ===", errors);

        $finish;
    end

endmodule
