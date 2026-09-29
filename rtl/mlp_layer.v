
module mlp_layer #(
    parameter N_INPUTS   = 784,
    parameter N_NEURONS  = 256,
    parameter SHIFT_AMT  = 7,    
    parameter RELU_EN    = 1,     
    parameter AW = $clog2(N_INPUTS*N_NEURONS),        // weight address width
    parameter BW = $clog2(N_NEURONS),                 // bias address / neuron index
    parameter IW = $clog2(N_INPUTS)                   // input index
)(
    input  wire clk,
    input  wire rst,                                  
    input  wire start,                                
    output wire ready,                                
    output reg  done,                                 

    input  wire [N_INPUTS*8-1:0]  act_in,             
    output reg  [N_NEURONS*8-1:0] out_flat,           

    output wire [AW-1:0] w_rd_addr,
    input  wire [7:0]    w_rd_data,
    output wire [BW-1:0] b_rd_addr,
    input  wire [7:0]    b_rd_data
);

    localparam IDLE       = 4'd0;
    localparam LOAD       = 4'd1;
    localparam PRIME      = 4'd2;                     // first weight read in flight
    localparam ACCUMULATE = 4'd3;
    localparam ADDR       = 4'd4;                     // BRAM latency wait
    localparam REQUANT    = 4'd5;
    localparam BIAS       = 4'd6;
    localparam WRITE_OUT  = 4'd7;
    localparam NEXT       = 4'd8;

    reg [3:0]      state;
    reg [BW-1:0]   neuron_idx;
    reg [IW-1:0]   input_idx;
    reg [AW-1:0]   w_base;                            // neuron_idx*N_INPUTS, kept by adding

    reg signed [31:0] acc;
    reg signed [31:0] acc_shifted;
    reg signed [31:0] acc_biased;
    reg signed [31:0] val;                            // relu applied, pre-saturation
    reg [7:0]  act_q;

    assign ready     = (state == IDLE);
    assign w_rd_addr = w_base + input_idx;
    assign b_rd_addr = neuron_idx;

    always @(posedge clk) begin
        if (rst) begin
            state      <= IDLE;
            done       <= 1'b0;
            neuron_idx <= 0;
            input_idx  <= 0;
            w_base     <= 0;
            acc        <= 32'sd0;
        end else begin
            case (state)

            IDLE: begin
                done <= 1'b0;
                if (start) state <= LOAD;
            end

            LOAD: begin                                // start of an image
                neuron_idx <= 0;
                input_idx  <= 0;
                w_base     <= 0;
                acc        <= 32'sd0;
                state      <= PRIME;
            end

            PRIME: begin                               // addr held one cycle, data valid next
                act_q <= act_in[input_idx*8 +: 8];
                state <= ACCUMULATE;
            end

            ACCUMULATE: begin                          // w_rd_data belongs to input_idx
                acc <= acc + ($signed(act_q) * $signed(w_rd_data));

                if (input_idx == N_INPUTS-1) begin
                    input_idx <= 0;
                    state     <= REQUANT;
                end else begin
                    input_idx <= input_idx + 1'b1;
                    state     <= ADDR;
                end
            end

            ADDR: begin                                // new address presented, wait for BRAM
                act_q <= act_in[input_idx*8 +: 8];
                state <= ACCUMULATE;
            end

            REQUANT: begin
                acc_shifted <= acc >>> SHIFT_AMT;
                state       <= BIAS;
            end

            BIAS: begin                                // b_rd_data stable since PRIME
                acc_biased <= acc_shifted + $signed(b_rd_data);
                state      <= WRITE_OUT;
            end

            WRITE_OUT: begin
                val = (RELU_EN && acc_biased[31]) ? 32'sd0 : acc_biased;

                if (val > 32'sd127)       out_flat[neuron_idx*8 +: 8] <= 8'sd127;
                else if (val < -32'sd128) out_flat[neuron_idx*8 +: 8] <= -8'sd128;
                else                      out_flat[neuron_idx*8 +: 8] <= val[7:0];

                state <= NEXT;
            end

            NEXT: begin
                if (neuron_idx == N_NEURONS-1) begin
                    done  <= 1'b1;
                    state <= IDLE;
                end else begin
                    neuron_idx <= neuron_idx + 1'b1;
                    w_base     <= w_base + N_INPUTS;
                    input_idx  <= 0;
                    acc        <= 32'sd0;              // no carry-over between neurons
                    state      <= PRIME;
                end
            end

            default: state <= IDLE;

            endcase
        end
    end

endmodule
