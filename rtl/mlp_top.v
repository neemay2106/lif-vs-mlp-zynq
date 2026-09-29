module mlp_top #(
    // Simulation-only BRAM preload. Vivado drops these (translate_off in
    // weight_bram.v), so on hardware the PS load is the only path.
    // Override with "" to test that load path in simulation.
    parameter W1_INIT = "weights/layer1_weights.hex",
    parameter B1_INIT = "weights/layer1_bias.hex",
    parameter W2_INIT = "weights/layer2_weights.hex",
    parameter B2_INIT = "weights/layer2_bias.hex",
    parameter W3_INIT = "weights/layer3_weights.hex",
    parameter B3_INIT = "weights/layer3_bias.hex"
)(

    
    input  wire        S_AXI_ACLK,
    input  wire        S_AXI_ARESETN,
    input  wire [31:0] S_AXI_AWADDR,
    input  wire  [2:0] S_AXI_AWPROT,
    input  wire        S_AXI_AWVALID,
    output wire         S_AXI_AWREADY,
    input  wire [31:0] S_AXI_WDATA,
    input  wire [3:0]  S_AXI_WSTRB,
    input  wire        S_AXI_WVALID,
    output wire         S_AXI_WREADY,
    output wire [1:0]  S_AXI_BRESP,
    output wire         S_AXI_BVALID,
    input  wire        S_AXI_BREADY,
    input  wire [31:0] S_AXI_ARADDR,
    input wire [2:0]   S_AXI_ARPROT,
    input  wire        S_AXI_ARVALID,
    output wire         S_AXI_ARREADY,
    output wire [31:0] S_AXI_RDATA,
    output wire [1:0]  S_AXI_RRESP,
    output wire         S_AXI_RVALID,
    input  wire        S_AXI_RREADY
  
);

wire start_bit, reset_bit;
wire        done_layer_3;
wire w_wr_en;
wire [17:0] w_wr_addr;
wire [7:0]  w_wr_data;
wire [1:0] w_wr_layer;
wire w_wr_target;

wire [7:0] l1_rd_data;
wire [7:0] l2_rd_data;
wire [7:0] l3_rd_data;

wire [17:0] l1_rd_addr;
wire [14:0] l2_rd_addr;
wire [10:0] l3_rd_addr;

wire [7:0] b1_rd_data;
wire [7:0] b2_rd_data;
wire [7:0] b3_rd_data;

wire [7:0] b1_rd_addr;
wire [6:0] b2_rd_addr;
wire [3:0] b3_rd_addr;

wire in_wr_en;
wire [7:0] in_wr_addr;
wire [31:0] in_wr_data;

wire [3:0] status;
wire        done3_pulse;

reg [6271:0] input_frame;

reg [79:0] logits_q;      // L3 outputs, frozen at done   -> 0x040/44/48
reg  [3:0] pred_q;        // argmax of those logits       -> 0x020
reg [31:0] cycle_cnt;     // free-running while busy
reg [31:0] cycles_q;      // latency of last image        -> 0x008
reg        done_sticky;   // status[0]: result ready, held until next accepted start
reg        start_rejected;// status[3]: a start was dropped (busy or not ready)

reg start_prev;
wire start_pulse;
always @(posedge S_AXI_ACLK) begin 
    if(!S_AXI_ARESETN) start_prev <= 1'b0;
    else               start_prev <= start_bit;
end 
assign start_pulse =  start_bit && !start_prev && S_AXI_ARESETN;

axi_lite_slave_mp axi_slave(

    .S_AXI_ACLK    (S_AXI_ACLK),
    .S_AXI_ARESETN (S_AXI_ARESETN),

    .S_AXI_AWADDR  (S_AXI_AWADDR),
    .S_AXI_AWPROT  (S_AXI_AWPROT),
    .S_AXI_AWVALID (S_AXI_AWVALID),
    .S_AXI_AWREADY (S_AXI_AWREADY),

    .S_AXI_WDATA   (S_AXI_WDATA),
    .S_AXI_WSTRB   (S_AXI_WSTRB),
    .S_AXI_WVALID  (S_AXI_WVALID),
    .S_AXI_WREADY  (S_AXI_WREADY),

    .S_AXI_BRESP   (S_AXI_BRESP),
    .S_AXI_BVALID  (S_AXI_BVALID),
    .S_AXI_BREADY  (S_AXI_BREADY),

    .S_AXI_ARADDR  (S_AXI_ARADDR),
    .S_AXI_ARPROT   (S_AXI_ARPROT),
    .S_AXI_ARVALID (S_AXI_ARVALID),
    .S_AXI_ARREADY (S_AXI_ARREADY),

    .S_AXI_RDATA   (S_AXI_RDATA),
    .S_AXI_RRESP   (S_AXI_RRESP),
    .S_AXI_RVALID  (S_AXI_RVALID),
    .S_AXI_RREADY  (S_AXI_RREADY),

    .status(status),
    .logits(logits_q),
    .cycles(cycles_q),
    .pred(pred_q),
    .in_wr_en(in_wr_en),
    .in_wr_addr(in_wr_addr),
    .in_wr_data(in_wr_data),
    .w_wr_en(w_wr_en),
    .w_wr_addr(w_wr_addr),
    .w_wr_data(w_wr_data),
    .w_wr_layer(w_wr_layer),
    .w_wr_target(w_wr_target),
    .start(start_bit),
    .rst(reset_bit)
);

wire wen_w1 = w_wr_en & !w_wr_target & (w_wr_layer == 2'd1);
wire wen_b1 = w_wr_en &  w_wr_target & (w_wr_layer == 2'd1);

wire wen_w2 = w_wr_en & !w_wr_target & (w_wr_layer == 2'd2);
wire wen_b2 = w_wr_en &  w_wr_target & (w_wr_layer == 2'd2);

wire wen_w3 = w_wr_en & !w_wr_target & (w_wr_layer == 2'd3);
wire wen_b3 = w_wr_en &  w_wr_target & (w_wr_layer == 2'd3);

always @(posedge S_AXI_ACLK) begin 
    if(!S_AXI_ARESETN) begin 
        input_frame <= 6272'b0;
    end else if(in_wr_en) input_frame[in_wr_addr*32+:32] <= in_wr_data;
    end
        
 
bram #(.RAM_DEPTH(784*256),.INIT_FILE(W1_INIT)) BW1 (.clk(S_AXI_ACLK), .wr_en(wen_w1), .wr_addr(w_wr_addr[17:0]),
                                .wr_data(w_wr_data), .rd_addr(l1_rd_addr), .rd_data(l1_rd_data)); //weights layer1

bram #(.RAM_DEPTH(256),.INIT_FILE(B1_INIT)) BB1 (.clk(S_AXI_ACLK), .wr_en(wen_b1), .wr_addr(w_wr_addr[7:0]),
                                .wr_data(w_wr_data), .rd_addr(b1_rd_addr), .rd_data(b1_rd_data)); //bias layer1

bram #(.RAM_DEPTH(256*128),.INIT_FILE(W2_INIT)) BW2 (.clk(S_AXI_ACLK), .wr_en(wen_w2), .wr_addr(w_wr_addr[14:0]),
                                .wr_data(w_wr_data), .rd_addr(l2_rd_addr), .rd_data(l2_rd_data));//weights layer2

bram #(.RAM_DEPTH(128),.INIT_FILE(B2_INIT)) BB2 (.clk(S_AXI_ACLK), .wr_en(wen_b2), .wr_addr(w_wr_addr[6:0]),
                                .wr_data(w_wr_data), .rd_addr(b2_rd_addr), .rd_data(b2_rd_data));//bias layer2

bram #(.RAM_DEPTH(128*10), .INIT_FILE(W3_INIT))  BW3 (.clk(S_AXI_ACLK), .wr_en(wen_w3), .wr_addr(w_wr_addr[10:0]),
                                .wr_data(w_wr_data), .rd_addr(l3_rd_addr), .rd_data(l3_rd_data));//weights layer3

bram #(.RAM_DEPTH(10),.INIT_FILE(B3_INIT)) BB3 (.clk(S_AXI_ACLK), .wr_en(wen_b3), .wr_addr(w_wr_addr[3:0]),
                                .wr_data(w_wr_data), .rd_addr(b3_rd_addr), .rd_data(b3_rd_data));//bias layer3

 
wire [2047:0] layer1_output;   // 256 x int8
wire [1023:0] layer2_output;   // 128 x int8
wire   [79:0] layer3_output;   //  10 x int8
wire done1, done2;

// mlp_layer done is already a 1-cycle pulse, so it starts the next layer directly
wire start2 = done1;
wire start3 = done2;

wire layer_reset = reset_bit || !S_AXI_ARESETN;
reg  running;
wire l1_ready, l2_ready, l3_ready;
wire chain_ready = l1_ready && l2_ready && l3_ready;
wire ready_bit   = chain_ready && !running;              // status[2]: safe to start
wire accepted_start = start_pulse && !running && chain_ready;

always @(posedge S_AXI_ACLK) begin
    if (layer_reset)          running <= 1'b0;
    else if (accepted_start)  running <= 1'b1;
    else if (done3_pulse)     running <= 1'b0;
end

mlp_layer #(.N_INPUTS(784), .N_NEURONS(256), .SHIFT_AMT(7), .RELU_EN(1)) L1 (.clk(S_AXI_ACLK), .rst(layer_reset), .start(accepted_start), .ready(l1_ready),
                   .act_in(input_frame), .w_rd_addr(l1_rd_addr), .w_rd_data(l1_rd_data), .b_rd_addr(b1_rd_addr), .b_rd_data(b1_rd_data),
                   .out_flat(layer1_output), .done(done1));

mlp_layer #(.N_INPUTS(256), .N_NEURONS(128), .SHIFT_AMT(7), .RELU_EN(1)) L2 (.clk(S_AXI_ACLK), .rst(layer_reset), .start(start2), .ready(l2_ready),
                   .act_in(layer1_output), .w_rd_addr(l2_rd_addr), .w_rd_data(l2_rd_data), .b_rd_addr(b2_rd_addr), .b_rd_data(b2_rd_data),
                   .out_flat(layer2_output), .done(done2));

mlp_layer #(.N_INPUTS(128), .N_NEURONS(10), .SHIFT_AMT(9), .RELU_EN(0)) L3 (.clk(S_AXI_ACLK), .rst(layer_reset), .start(start3), .ready(l3_ready),
                   .act_in(layer2_output), .w_rd_addr(l3_rd_addr), .w_rd_data(l3_rd_data), .b_rd_addr(b3_rd_addr), .b_rd_data(b3_rd_data),
                   .out_flat(layer3_output), .done(done_layer_3));

reg done3_prev;
always @(posedge S_AXI_ACLK)
    done3_prev <= (layer_reset) ? 1'b0 : done_layer_3;
assign done3_pulse = done_layer_3 && !done3_prev;

// argmax of the 10 int8 logits, first index wins a tie (matches np.argmax)
reg  [3:0] pred_c;
reg signed [7:0] best_c;
integer k;
always @* begin
    pred_c = 4'd0;
    best_c = $signed(layer3_output[7:0]);
    for (k = 1; k < 10; k = k + 1)
        if ($signed(layer3_output[k*8 +: 8]) > best_c) begin
            best_c = $signed(layer3_output[k*8 +: 8]);
            pred_c = k[3:0];
        end
end

// cycles from accepted start to L3 done -> hardware latency per image
always @(posedge S_AXI_ACLK) begin
    if (layer_reset)         cycle_cnt <= 32'd0;
    else if (accepted_start) cycle_cnt <= 32'd0;
    else if (running)        cycle_cnt <= cycle_cnt + 1'b1;
end

// every result register updates on the same edge, so a poller never sees a mixed set
always @(posedge S_AXI_ACLK) begin
    if (layer_reset) begin
        logits_q    <= 80'd0;
        pred_q      <= 4'd0;
        cycles_q    <= 32'd0;
        done_sticky <= 1'b0;
    end else if (accepted_start) begin
        done_sticky <= 1'b0;                 // clear before the new image, not after
    end else if (done3_pulse) begin
        logits_q    <= layer3_output;
        pred_q      <= pred_c;
        cycles_q    <= cycle_cnt;
        done_sticky <= 1'b1;
    end
end

// a start dropped because the core was busy or not ready; PS clears it by starting again
always @(posedge S_AXI_ACLK) begin
    if (layer_reset)                          start_rejected <= 1'b0;
    else if (accepted_start)                  start_rejected <= 1'b0;
    else if (start_pulse && !accepted_start)  start_rejected <= 1'b1;
end

assign status = {start_rejected, ready_bit, running, done_sticky};




 
endmodule