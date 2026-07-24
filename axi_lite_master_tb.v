module master_top_tb;

reg         clk;
reg         rst_n;

// Write address channel
reg  [31:0] M_AXI_AWADDR;
reg         M_AXI_AWVALID;
wire        M_AXI_AWREADY;

// Write data channel
reg  [31:0] M_AXI_WDATA;
reg  [3:0]  M_AXI_WSTRB;
reg         M_AXI_WVALID;
wire        M_AXI_WREADY;

// Write response channel
wire [1:0]  M_AXI_BRESP;
wire        M_AXI_BVALID;
reg         M_AXI_BREADY;

// Read address channel
reg  [31:0] M_AXI_ARADDR;
reg         M_AXI_ARVALID;
wire        M_AXI_ARREADY;

// Read data channel
wire [31:0] M_AXI_RDATA;
wire [1:0]  M_AXI_RRESP;
wire        M_AXI_RVALID;
reg         M_AXI_RREADY;

initial clk = 0;
always #5 clk = ~clk;

axi_lite_slave dut (
    .S_AXI_ACLK    (clk),
    .S_AXI_ARESETN (rst_n),

    .S_AXI_AWADDR  (M_AXI_AWADDR),
    .S_AXI_AWVALID (M_AXI_AWVALID),
    .S_AXI_AWREADY (M_AXI_AWREADY),

    .S_AXI_WDATA   (M_AXI_WDATA),
    .S_AXI_WSTRB   (M_AXI_WSTRB),
    .S_AXI_WVALID  (M_AXI_WVALID),
    .S_AXI_WREADY  (M_AXI_WREADY),

    .S_AXI_BRESP   (M_AXI_BRESP),
    .S_AXI_BVALID  (M_AXI_BVALID),
    .S_AXI_BREADY  (M_AXI_BREADY),

    .S_AXI_ARADDR  (M_AXI_ARADDR),
    .S_AXI_ARVALID (M_AXI_ARVALID),
    .S_AXI_ARREADY (M_AXI_ARREADY),

    .S_AXI_RDATA   (M_AXI_RDATA),
    .S_AXI_RRESP   (M_AXI_RRESP),
    .S_AXI_RVALID  (M_AXI_RVALID),
    .S_AXI_RREADY  (M_AXI_RREADY)
);

 reg [31:0] read_data;   

// task that completes write transaction
task write_reg;
    input [31:0] addr;
    input [31:0] data;
    integer timeout;
    reg aw_done, w_done, b_done;
    begin
        $display("WRITE_REG: starting addr=%h data=%h", addr, data);

        @(posedge clk); #1;
        M_AXI_AWADDR  = addr;
        M_AXI_AWVALID = 1;
        M_AXI_WDATA   = data;
        M_AXI_WSTRB   = 4'hF;
        M_AXI_WVALID  = 1;
        M_AXI_BREADY  = 1;
        aw_done = 0;
        w_done  = 0;
        b_done  = 0;
        timeout = 0;
        while (!b_done) begin
            @(posedge clk);

            if (!aw_done && M_AXI_AWVALID && M_AXI_AWREADY) begin
                aw_done = 1;
                #1 M_AXI_AWVALID = 0;
            end

            if (!w_done && M_AXI_WVALID && M_AXI_WREADY) begin
                w_done = 1;
                #1 M_AXI_WVALID = 0;
            end

            if (M_AXI_BVALID && M_AXI_BREADY) begin
                b_done = 1;
            end

            timeout = timeout + 1;
            if (timeout > 100) begin
                $display("WRITE_REG: TIMEOUT waiting for AW/W/B (aw_done=%b w_done=%b)", aw_done, w_done);
                $finish;
            end
        end
        $display("WRITE_REG: BRESP=%b", M_AXI_BRESP);
        #1 M_AXI_BREADY = 0;

        $display("WRITE_REG: transaction complete");
    end
endtask

// task that completes read transaction
task read_reg;
    input  [31:0] addr;
    output [31:0] data;
    integer timeout;
    begin
        $display("READ_REG: starting addr=%h", addr);

        @(posedge clk); #1;
        M_AXI_ARADDR  = addr;
        M_AXI_ARVALID = 1;
        M_AXI_RREADY  = 1;

        // wait for AR handshake
        timeout = 0;
        while (!M_AXI_ARREADY) begin
            @(posedge clk);
            timeout = timeout + 1;
            if (timeout > 100) begin
                $display("READ_REG: TIMEOUT waiting for ARREADY");
                $finish;
            end
        end
        @(posedge clk); #1;
        M_AXI_ARVALID = 0;

        // wait for read data
        timeout = 0;
        while (!M_AXI_RVALID) begin
            @(posedge clk);
            timeout = timeout + 1;
            if (timeout > 100) begin
                $display("READ_REG: TIMEOUT waiting for RVALID");
                $finish;
            end
        end
        data = M_AXI_RDATA;
        $display("READ_REG: got data=%h RRESP=%b", data, M_AXI_RRESP);
        @(posedge clk); #1;
        M_AXI_RREADY = 0;

        $display("READ_REG: transaction complete");
    end
endtask

task busy_reject_check;
    input [31:0] addr1, data1;
    input [31:0] addr2, data2;
    begin
        
        @(posedge clk); #1;
        M_AXI_AWADDR  = addr1;
        M_AXI_AWVALID = 1;
        M_AXI_WDATA   = data1;
        M_AXI_WVALID  = 1;
        M_AXI_BREADY  = 0; 

        if (M_AXI_AWREADY !== 0) begin
            $display("FAIL: AWREADY should be 0 while DUT is in WRITE_RESP, got %b", M_AXI_AWREADY);
        end

        read_reg(addr1,read_data);
        $display("first write %s ",read_data);

        M_AXI_AWADDR  = addr2;
        M_AXI_AWVALID = 1;
        M_AXI_WDATA   = data2;
        M_AXI_WVALID  = 1;
        @(posedge clk); #1;

        if (dut.aw_latched === 1 && dut.awaddr_captured === addr2) begin
            $display("FAIL: second address was latched while DUT was still busy — bug present");
        end

        M_AXI_BREADY = 1;
        @(posedge clk); #1;
        M_AXI_BREADY = 0;

    

        read_reg(addr2,read_data);
        $display(" second write %s",read_data);
    end
endtask




initial begin
    rst_n         = 0;
    M_AXI_AWADDR  = 0;
    M_AXI_AWVALID = 0;
    M_AXI_WDATA   = 0;
    M_AXI_WSTRB   = 4'hF;
    M_AXI_WVALID  = 0;
    M_AXI_BREADY  = 0;
    M_AXI_ARADDR  = 0;
    M_AXI_ARVALID = 0;
    M_AXI_RREADY  = 0;

    repeat (4) @(posedge clk);
    rst_n = 1;

    dut.reg1_status = 32'hAAAA_AAAA;
    write_reg(32'h0000_0004, 32'h1111_1111);
    read_reg(32'h0000_0004, read_data);
    if (read_data !== 32'hAAAA_AAAA) begin
    $display("FAIL: REG1 write-block broken — expected AAAA_AAAA, got %h", read_data);
    end else begin
    $display("PASS: REG1 correctly rejected AXI write");
    end

    write_reg(32'h0000_0000,32'hABCDEF);
    read_reg(32'h0000_0000,read_data);
    if(read_data == 32'hABCDEF) begin
        $display("worked");
    end
    $finish;
end

endmodule