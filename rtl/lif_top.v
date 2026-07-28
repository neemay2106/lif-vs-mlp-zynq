module lif_top(

    input wire [783:0] layer1_input, 
    input  wire        S_AXI_ACLK,
    input  wire        S_AXI_ARESETN,
    input  wire [31:0] S_AXI_AWADDR,
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
    input  wire        S_AXI_ARVALID,
    output wire         S_AXI_ARREADY,
    output wire [31:0] S_AXI_RDATA,
    output wire [1:0]  S_AXI_RRESP,
    output wire         S_AXI_RVALID,
    input  wire        S_AXI_RREADY,
    output wire  [9:0] network_output
);

wire start_bit, reset_bit;
wire [31:0] threshold_cfg;
wire        done_signal;
wire [31:0] skip_count_total;

reg start_prev;
wire start_pulse;
always @(posedge S_AXI_ACLK) begin 
    if(!S_AXI_ARESETN) start_prev <= 1'b0;
    else               start_prev <= start_bit;
end 
assign start_pulse =  start_bit && !start_prev && S_AXI_ARESETN;

axi_lite_slave axi_slave(

    .S_AXI_ACLK    (S_AXI_ACLK),
    .S_AXI_ARESETN (S_AXI_ARESETN),

    .S_AXI_AWADDR  (S_AXI_AWADDR),
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
    .S_AXI_ARVALID (S_AXI_ARVALID),
    .S_AXI_ARREADY (S_AXI_ARREADY),

    .S_AXI_RDATA   (S_AXI_RDATA),
    .S_AXI_RRESP   (S_AXI_RRESP),
    .S_AXI_RVALID  (S_AXI_RVALID),
    .S_AXI_RREADY  (S_AXI_RREADY),

    .done(done_signal),
    .skipped_mac_count(skip_count_total),
    .start(start_bit),
    .rst(reset_bit),
    .threshold(threshold_cfg)
);
 
wire [255:0] layer1_output;
wire [127:0] layer2_output;
wire [31:0] skip1, skip2, skip3;
wire done1, done2;
reg done1_prev, done2_prev;
wire start2,start3;


always @(posedge S_AXI_ACLK) begin 
    if (!S_AXI_ARESETN) begin 
        done1_prev <= 1'b0;
        done2_prev <= 1'b0;
    end else begin 
        done1_prev <= done1;
        done2_prev <= done2;
    end 
end 

assign start2 = done1 && !done1_prev;
assign start3 = done2 && !done2_prev;

wire layer_reset = reset_bit || !S_AXI_ARESETN;
lif_layer1 L1 (.clk(S_AXI_ACLK), .rst(layer_reset), .start(start_pulse), .spike_in_vec(layer1_input),
                   .spike_out_vec(layer1_output), .done(done1), .skipped_mac_count(skip1));

lif_layer2 L2 (.clk(S_AXI_ACLK), .rst(layer_reset), .start(start2), .spike_in_vec(layer1_output),
                   .spike_out_vec(layer2_output), .done(done2), .skipped_mac_count(skip2));

lif_layer3 L3 (.clk(S_AXI_ACLK), .rst(layer_reset), .start(start3), .spike_in_vec(layer2_output),
                   .spike_out_vec(network_output), .done(done_signal), .skipped_mac_count(skip3));

assign skip_count_total = skip1 + skip2 + skip3 ;






endmodule