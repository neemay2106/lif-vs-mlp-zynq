module axi_lite_slave (
    input  wire        S_AXI_ACLK,
    input  wire        S_AXI_ARESETN,

    // Write address channel
    input  wire [31:0] S_AXI_AWADDR,
    input wire [2:0] S_AXI_AWPROT,
    input  wire        S_AXI_AWVALID,
    output wire        S_AXI_AWREADY,

    // Write data channel
    input  wire [31:0] S_AXI_WDATA,
    input  wire [3:0]  S_AXI_WSTRB,
    input  wire        S_AXI_WVALID,
    output wire         S_AXI_WREADY,

    // Write response channel
    output reg  [1:0]  S_AXI_BRESP,
    output reg         S_AXI_BVALID,
    input  wire        S_AXI_BREADY,

    // Read address channel
    input  wire [31:0] S_AXI_ARADDR,
    input wire [2:0] S_AXI_ARPROT,
    input  wire        S_AXI_ARVALID,
    output reg         S_AXI_ARREADY,

    // Read data channel
    output reg  [31:0] S_AXI_RDATA,
    output reg  [1:0]  S_AXI_RRESP,
    output reg         S_AXI_RVALID,
    input  wire        S_AXI_RREADY,

    //wire into registers
    input wire [2:0] status, 
    input wire [79:0] class_count,
    input wire [31:0] skipped_mac_count,
    output reg        in_wr_en,
    output reg [4:0]  in_wr_addr,
    output reg [31:0] in_wr_data,
    output reg        w_wr_en,
    output reg [17:0] w_wr_addr,
    output reg [7:0]  w_wr_data,
    output reg [1:0]  w_wr_layer,
    output wire  start,
    output wire rst
);

    reg [31:0] reg0_control;
    reg [31:0] reg1_status;
    reg [31:0] reg3_skip_count;
    reg [79:0] reg_class_counts;

    reg [17:0] wr_ptr;
    reg [4:0] input_ptr;

    assign start     = reg0_control[0];
    assign rst       = reg0_control[1];


    always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN) begin
        reg1_status     <= 32'd0;
        reg3_skip_count <= 32'd0;
    end else begin
        reg1_status     <= {29'd0, status};
        reg3_skip_count <= skipped_mac_count;
        reg_class_counts <= class_count;
    end
    end

    reg aw_latched, w_latched;
    reg [31:0] awaddr_captured, wdata_captured;

    localparam WRITE_IDLE = 1'b0;
    localparam WRITE_RESP = 1'b1;
    localparam READ_IDLE  = 1'b0;
    localparam READ_RESP  = 1'b1;
    reg write_state, read_state;
    
    wire [31:0] wd = w_latched ? wdata_captured : S_AXI_WDATA;
    reg [3:0] wstrb_captured;
    wire [3:0] ws = w_latched ? wstrb_captured : S_AXI_WSTRB;

    assign S_AXI_AWREADY = (write_state == WRITE_IDLE) && !aw_latched;
    assign S_AXI_WREADY =  (write_state == WRITE_IDLE) && !w_latched;

    // Write channel FSM
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            write_state     <= WRITE_IDLE;
            aw_latched      <= 0;
            w_latched       <= 0;
            reg0_control    <= 32'd0;
            S_AXI_BVALID    <= 0;
            S_AXI_BRESP     <= 2'b00;
            w_wr_en    <= 1'b0;
            w_wr_addr  <= 18'd0;
            w_wr_data  <= 8'd0;
            in_wr_en <= 1'b0;
            w_wr_layer <= 2'd0;
            wr_ptr     <= 18'd0;
            input_ptr <= 0;
            in_wr_en <= 0;
        end else begin
            w_wr_en <= 1'b0;
            case (write_state)

                WRITE_IDLE: begin
                
                    if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                        awaddr_captured <= S_AXI_AWADDR;
                        aw_latched      <= 1;
                    end

                    
                    if (S_AXI_WVALID && S_AXI_WREADY) begin
                        wdata_captured <= S_AXI_WDATA;
                        wstrb_captured <= S_AXI_WSTRB;
                        w_latched      <= 1;
                    end

                    if ((aw_latched || (S_AXI_AWVALID && S_AXI_AWREADY)) &&
                        (w_latched  || (S_AXI_WVALID  && S_AXI_WREADY))) begin

                        case (aw_latched ? awaddr_captured[11:0] : S_AXI_AWADDR[11:0])
                            12'h000: begin
                                  if (ws[0]) reg0_control[7:0]   <= wd[7:0];
                                  S_AXI_BRESP   <= 2'b00;
                            end

                            12'h010:begin
                                if(ws == 4'hF) begin  
                                    w_wr_en   <= 1'b1;             // ← overrides the default
                                    w_wr_addr <= wr_ptr;
                                    w_wr_data  <= wd[7:0];
                                    wr_ptr    <= wr_ptr + 1'b1;
                                    S_AXI_BRESP   <= 2'b00;
                                end else begin 
                                    S_AXI_BRESP <= 2'b10;
                                end
                            end

                            12'h014:begin                    // weight ctrl
                                if (ws[0]) w_wr_layer  <= wd[1:0];
                                if (ws[0] && wd[2]) wr_ptr <= 18'd0;
                                S_AXI_BRESP   <= 2'b00;
                            end

                            12'h018:begin
                                if(ws == 4'hF) begin
                                    in_wr_en <= 1'b1;
                                    in_wr_addr <= input_ptr;
                                    in_wr_data <= wd;   // stray "if" removed, was a syntax error
                                    input_ptr <= (input_ptr == 5'd24)? 5'b0: input_ptr+1'b1;
                                    S_AXI_BRESP   <= 2'b00;
                                end else begin 
                                    S_AXI_BRESP <= 2'b10;
                                end
                            end

                            12'h01c:begin 
                                if(ws[0] && wd[0]) input_ptr <= 0;
                                S_AXI_BRESP   <= 2'b00;
                            end

                            default: begin
                                S_AXI_BRESP <= 2'b11;
                            end
                        endcase

                        aw_latched    <= 0;
                        w_latched     <= 0;
                        S_AXI_BVALID  <= 1;
                        write_state   <= WRITE_RESP;
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
                    if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                        case (S_AXI_ARADDR[11:0]) 
                                12'h000: S_AXI_RDATA <= reg0_control;
                                12'h004: S_AXI_RDATA <= reg1_status;
                                12'h00C: S_AXI_RDATA <= reg3_skip_count;
                                12'h010: S_AXI_RDATA <= {14'd0, wr_ptr};
                                12'h014: S_AXI_RDATA <= {12'd0, wr_ptr, w_wr_layer};
                                12'h040: S_AXI_RDATA <= reg_class_counts[31:0];
                                12'h044: S_AXI_RDATA <= reg_class_counts[63:32];
                                12'h048: S_AXI_RDATA <= reg_class_counts[79:64];
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