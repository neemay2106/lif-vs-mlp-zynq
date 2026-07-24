module axi_lite_slave (
    input  wire        S_AXI_ACLK,
    input  wire        S_AXI_ARESETN,

    // Write address channel
    input  wire [31:0] S_AXI_AWADDR,
    input  wire        S_AXI_AWVALID,
    output reg         S_AXI_AWREADY,

    // Write data channel
    input  wire [31:0] S_AXI_WDATA,
    input  wire [3:0]  S_AXI_WSTRB,
    input  wire        S_AXI_WVALID,
    output reg         S_AXI_WREADY,

    // Write response channel
    output reg  [1:0]  S_AXI_BRESP,
    output reg         S_AXI_BVALID,
    input  wire        S_AXI_BREADY,

    // Read address channel
    input  wire [31:0] S_AXI_ARADDR,
    input  wire        S_AXI_ARVALID,
    output reg         S_AXI_ARREADY,

    // Read data channel
    output reg  [31:0] S_AXI_RDATA,
    output reg  [1:0]  S_AXI_RRESP,
    output reg         S_AXI_RVALID,
    input  wire        S_AXI_RREADY
);

    reg [31:0] reg0_control;
    reg [31:0] reg1_status;
    reg [31:0] reg2_threshold;
    reg [31:0] reg3_skip_count;

    reg aw_latched, w_latched;
    reg [31:0] awaddr_captured, wdata_captured;

    localparam WRITE_IDLE = 1'b0;
    localparam WRITE_RESP = 1'b1;
    localparam READ_IDLE  = 1'b0;
    localparam READ_RESP  = 1'b1;
    reg write_state, read_state;

    // Combinational: only WREADY here now (AWREADY driven sequentially below)
    always @(*) begin
        S_AXI_WREADY = (write_state == WRITE_IDLE);
    end

    // Write channel FSM
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            write_state     <= WRITE_IDLE;
            aw_latched      <= 0;
            w_latched       <= 0;
            // reg0_control    <= 32'd0;
            // reg2_threshold  <= 32'd0;
            // reg1_status     <= 32'd0;
            // reg3_skip_count <= 32'd0;
            S_AXI_BVALID    <= 0;
            S_AXI_AWREADY   <= 0;
            S_AXI_BRESP     <= 2'b00;
        end else begin
            case (write_state)

                WRITE_IDLE: begin
                    S_AXI_AWREADY <= 1;
                    S_AXI_WREADY <= 1;
                
                    if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                        awaddr_captured <= S_AXI_AWADDR;
                        aw_latched      <= 1;
                    end

                    
                    if (S_AXI_WVALID && S_AXI_WREADY) begin
                        wdata_captured <= S_AXI_WDATA;
                        w_latched      <= 1;
                    end

                    if ((aw_latched || S_AXI_AWVALID) &&
                        (w_latched  || (S_AXI_WVALID  && S_AXI_WREADY))) begin
                            $display("if statement worked");
                        case (aw_latched ? awaddr_captured[3:2] : S_AXI_AWADDR[3:2])
                            2'd0: reg0_control   <= w_latched ? wdata_captured : S_AXI_WDATA;
                            2'd2: reg2_threshold <= w_latched ? wdata_captured : S_AXI_WDATA;
                        endcase
                    

                        aw_latched    <= 0;
                        w_latched     <= 0;
                        S_AXI_AWREADY <= 0;
                        S_AXI_BVALID  <= 1;
                        S_AXI_BRESP   <= 2'b00;
                        write_state   <= WRITE_RESP;
                        end else begin 
                            $display("if statement didnt work"); 
                        end 
                end

                WRITE_RESP: begin
                    if (S_AXI_BVALID && S_AXI_BREADY) begin
                        S_AXI_BVALID <= 0;
                        write_state  <= WRITE_IDLE;
                    end
                end

            endcase
        end
    end

    // Read channel FSM
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_RVALID  <= 0;
            S_AXI_ARREADY <= 0;
            read_state    <= READ_IDLE;
        end else begin
            case (read_state)

                READ_IDLE: begin
                    S_AXI_ARREADY <= 1;
                    if (S_AXI_ARVALID) begin
                        case (S_AXI_ARADDR[3:2])
                            2'd0: S_AXI_RDATA <= reg0_control;
                            2'd1: S_AXI_RDATA <= reg1_status;
                            2'd2: S_AXI_RDATA <= reg2_threshold;
                            2'd3: S_AXI_RDATA <= reg3_skip_count;
                            default: S_AXI_RDATA <= 32'd0;
                        endcase

                        S_AXI_RRESP   <= 2'b00;
                        S_AXI_RVALID  <= 1;
                        S_AXI_ARREADY <= 0;
                        read_state    <= READ_RESP;
                    end
                end

                READ_RESP: begin
                    if (S_AXI_RVALID && S_AXI_RREADY) begin
                        S_AXI_RVALID <= 0;
                        read_state   <= READ_IDLE;
                    end
                end

            endcase
        end
    end

endmodule