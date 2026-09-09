module lif_top(

    //input wire [783:0] layer1_input, 
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
    //output wire  [9:0] network_output
);

wire start_bit, reset_bit;
wire [31:0] threshold_cfg;
wire        done_layer_3;
wire [31:0] skip_count_total;
wire w_wr_en;
wire [17:0] w_wr_addr;
wire [7:0]  w_wr_data;
wire [1:0] w_wr_layer;
localparam NUM_TIMESTEPS = 25; 
reg [4:0] timestep_count; 

wire [7:0] l1_rd_data;
wire [7:0] l2_rd_data;
wire [7:0] l3_rd_data;

wire [17:0] l1_rd_addr;
wire [14:0] l2_rd_addr;
wire [10:0] l3_rd_addr;

wire in_wr_en;
wire [4:0] in_wr_addr;
wire [31:0] in_wr_data;

reg [799:0] input_frame;
wire [9:0] network_output;

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

    .done(true_done),
    .skipped_mac_count(skip_count_total),
    .class_count(class_count_flat),
    .in_wr_en(in_wr_en),
    .in_wr_addr(in_wr_addr),
    .in_wr_data(in_wr_data),
    .w_wr_en(w_wr_en),
    .w_wr_addr(w_wr_addr),
    .w_wr_data(w_wr_data),
    .w_wr_layer(w_wr_layer),
    .start(start_bit),
    .rst(reset_bit),
    .threshold(threshold_cfg)
);

wire wen1 = w_wr_en & (w_wr_layer == 2'd1);
wire wen2 = w_wr_en & (w_wr_layer == 2'd2);
wire wen3 = w_wr_en & (w_wr_layer == 2'd3);

always @(posedge S_AXI_ACLK) begin 
    if(!S_AXI_ARESETN) begin 
        input_frame <= 800'b0;
    end else if(in_wr_en) input_frame[in_wr_addr*32+:32] <= in_wr_data;
    end
        
wire [783:0] layer1_input = input_frame[783:0];

 
bram #(.RAM_DEPTH(784*256),.INIT_FILE("data_layer/weights/weights_layer1.hex")) B1 (.clk(S_AXI_ACLK), .wr_en(wen1), .wr_addr(w_wr_addr[17:0]),
                                .wr_data(w_wr_data), .rd_addr(l1_rd_addr), .rd_data(l1_rd_data));
bram #(.RAM_DEPTH(256*128),.INIT_FILE("data_layer/weights/weights_layer2.hex")) B2 (.clk(S_AXI_ACLK), .wr_en(wen2), .wr_addr(w_wr_addr[14:0]),
                                .wr_data(w_wr_data), .rd_addr(l2_rd_addr), .rd_data(l2_rd_data));
bram #(.RAM_DEPTH(128*10), .INIT_FILE("data_layer/weights/weights_layer3.hex"))  B3 (.clk(S_AXI_ACLK), .wr_en(wen3), .wr_addr(w_wr_addr[10:0]),
                                .wr_data(w_wr_data), .rd_addr(l3_rd_addr), .rd_data(l3_rd_data));


 
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
reg  running;
wire accepted_start = start_pulse && !running;

always @(posedge S_AXI_ACLK) begin
    if (layer_reset)          running <= 1'b0;
    else if (accepted_start)  running <= 1'b1;
    else if (done3_pulse)     running <= 1'b0;   //on line 181
end


always @(posedge S_AXI_ACLK) begin 
    if(layer_reset) begin 
        timestep_count <= 0;
    end else if(accepted_start) begin 
        timestep_count <= timestep_count +1;
    end
end

wire final_timestep = (timestep_count == NUM_TIMESTEPS);
reg true_done;

always @(posedge S_AXI_ACLK) begin 
if(layer_reset) begin 
        true_done <= 1'b0;
    end else begin 
        true_done <= done_layer_3 && final_timestep;
    end
end

lif_layer #(.INPUT_LENGTH(784), .NUM_NEURONS(256) ) L1  (.clk(S_AXI_ACLK), .rst(layer_reset), .start(accepted_start), .spike_in_vec(layer1_input),
                   .wr_rd_data(l1_rd_data),.w_rd_addr(l1_rd_addr),.spike_out_vec(layer1_output), .done(done1), .skipped_mac_count(skip1));

lif_layer #(.INPUT_LENGTH(256), .NUM_NEURONS(128) ) L2 (.clk(S_AXI_ACLK), .rst(layer_reset), .start(start2), .spike_in_vec(layer1_output),
                   .wr_rd_data(l2_rd_data),.w_rd_addr(l2_rd_addr),.spike_out_vec(layer2_output), .done(done2), .skipped_mac_count(skip2));

lif_layer #(.INPUT_LENGTH(128), .NUM_NEURONS(10)) L3 (.clk(S_AXI_ACLK), .rst(layer_reset), .start(start3), .spike_in_vec(layer2_output),
                   .wr_rd_data(l3_rd_data),.w_rd_addr(l3_rd_addr),.spike_out_vec(network_output), .done(done_layer_3), .skipped_mac_count(skip3));

assign skip_count_total = skip1 + skip2 + skip3 ;

reg done3_prev;
always @(posedge S_AXI_ACLK)
    done3_prev <= (layer_reset) ? 1'b0 : done_layer_3;
wire done3_pulse = done_layer_3 && !done3_prev;

reg [7:0] sum_clases [0:9];
integer c;
always @(posedge S_AXI_ACLK) begin
    if (layer_reset) begin
        for (c = 0; c < 10; c = c + 1) sum_clases[c] <= 8'd0;
    end else if (done3_pulse) begin
        for (c = 0; c < 10; c = c + 1)
            if (network_output[c]) sum_clases[c] <= sum_clases[c] + 1'b1;
    end
end

wire [79:0] class_count_flat;
genvar g;
generate
  for (g = 0; g < 10; g = g + 1) begin : pack
    assign class_count_flat[g*8 +: 8] = sum_clases[g];
  end
endgenerate
 
endmodule