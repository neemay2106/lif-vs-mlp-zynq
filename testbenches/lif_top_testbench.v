module lif_top_tb;

    // Clock and reset
    reg         S_AXI_ACLK;
    reg         S_AXI_ARESETN;
    
    initial S_AXI_ACLK = 0;
    always #5 S_AXI_ACLK = ~S_AXI_ACLK;   // 10ns period, adjust as needed
    // Layer input
    reg  [783:0] layer1_input;

    // AXI-Lite Write Address Channel
    reg  [31:0] S_AXI_AWADDR;
    reg         S_AXI_AWVALID;
    wire        S_AXI_AWREADY;

    // AXI-Lite Write Data Channel
    reg  [31:0] S_AXI_WDATA;
    reg  [3:0]  S_AXI_WSTRB;
    reg         S_AXI_WVALID;
    wire        S_AXI_WREADY;

    // AXI-Lite Write Response Channel
    wire [1:0]  S_AXI_BRESP;
    wire        S_AXI_BVALID;
    reg         S_AXI_BREADY;

    // AXI-Lite Read Address Channel
    reg  [31:0] S_AXI_ARADDR;
    reg         S_AXI_ARVALID;
    wire        S_AXI_ARREADY;

    // AXI-Lite Read Data Channel
    wire [31:0] S_AXI_RDATA;
    wire [1:0]  S_AXI_RRESP;
    wire        S_AXI_RVALID;
    reg         S_AXI_RREADY;

    // Network output
    wire [9:0] network_output;

    //=========================================================
    // DUT
    //=========================================================
    lif_top dut (
        .layer1_input (layer1_input),

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
        .S_AXI_RREADY (S_AXI_RREADY),

        .network_output(network_output)
    );


// task that completes write transaction
task write_reg;
    input [31:0] addr;
    input [31:0] data;
    integer timeout;
    reg aw_done, w_done, b_done;
    begin
        $display("WRITE_REG: starting addr=%h data=%h", addr, data);

        @(posedge S_AXI_ACLK); #1;
        S_AXI_AWADDR  = addr;
        S_AXI_AWVALID = 1;
        S_AXI_WDATA   = data;
        S_AXI_WSTRB   = 4'hF;
        S_AXI_WVALID  = 1;
        S_AXI_BREADY  = 1;
        aw_done = 0;
        w_done  = 0;
        b_done  = 0;
        timeout = 0;
        while (!b_done) begin
            @(posedge S_AXI_ACLK);

            if (!aw_done && S_AXI_AWVALID && S_AXI_AWREADY) begin
                aw_done = 1;
                #1 S_AXI_AWVALID = 0;
            end

            if (!w_done && S_AXI_WVALID && S_AXI_WREADY) begin
                w_done = 1;
                #1 S_AXI_WVALID = 0;
            end

            if (S_AXI_BVALID && S_AXI_BREADY) begin
                b_done = 1;
            end

            timeout = timeout + 1;
            if (timeout > 100) begin
                $display("WRITE_REG: TIMEOUT waiting for AW/W/B (aw_done=%b w_done=%b)", aw_done, w_done);
                $finish;
            end
        end
        $display("WRITE_REG: BRESP=%b", S_AXI_BRESP);
        #1 S_AXI_BREADY = 0;

        $display("WRITE_REG: transaction complete");
    end
endtask

reg [0:0] spike_bits [0:783];
integer j;
reg [9:0] class_accumulator [0:9];
string filename;
                          

//input spikes beign fed 
// initial begin
//     $readmemh("/Users/neemayrajan/Documents/Project_2/spike/spikes_t17.txt", spike_bits);
//     for (j = 0; j < 784; j = j + 1) begin
//         layer1_input[j] = spike_bits[j];
//     end
// end

integer i,t,c;
initial begin 
    for (c = 0; c < 10; c = c + 1) class_accumulator[c] = 0;

    S_AXI_ARESETN = 0;
    repeat (5) @(posedge S_AXI_ACLK);
    S_AXI_ARESETN = 1;

    @(posedge S_AXI_ACLK);

    
    for (t = 0; t < 25; t = t + 1) begin

            filename = $sformatf("/Users/neemayrajan/Documents/Project_2/spike/spikes_t%0d.txt", t);
            
            $readmemh(filename, spike_bits);
            for (j = 0; j < 784; j = j + 1) begin
                layer1_input[j] = spike_bits[j];
            end
            

            @(posedge S_AXI_ACLK);
            write_reg(32'h0000_0000, 32'h0000_0001);
            $display("=== Pulsing start for timestep %0d at time %0t ===", t, $time);
            @(posedge S_AXI_ACLK);
            write_reg(32'h0000_0000, 32'h0000_0000);

            

            wait(dut.done_layer_3 == 1);
            $display("skipped mac count %d", dut.skip_count_total);
            
            for (c = 0; c < 10; c = c + 1) begin
                if (network_output[c])
                    class_accumulator[c] = class_accumulator[c] + 1;
            end

            @(posedge S_AXI_ACLK);
        end

        wait(dut.true_done == 1);
        $display("Final class counts:");
        for (c = 0; c < 10; c = c + 1)
            $display("  class %0d: %0d spikes", c, class_accumulator[c]);

        $finish;
    end

endmodule