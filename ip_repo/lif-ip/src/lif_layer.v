
module lif_layer
#(
    parameter INPUT_LENGTH = 0,
    parameter NUM_NEURONS = 0
)(
    input wire clk,
    input wire rst,
    input wire start,
    input wire [INPUT_LENGTH-1:0] spike_in_vec,
    input wire [7:0] wr_rd_data,
    output wire [17:0] w_rd_addr,  
    output reg [NUM_NEURONS-1:0] spike_out_vec,
    output reg done,
    output reg [31:0] skipped_mac_count,
    output wire ready
);

localparam IDLE       = 4'd0;
localparam LOAD_INPUT = 4'd1;
localparam ADDR       = 4'd2;
localparam ACCUMULATE = 4'd3;
localparam THRESHOLD  = 4'd4;
localparam OUT_SPIKES = 4'd5;
localparam MEM_RD     = 4'd6;   // new
localparam DECAY      = 4'd7;   // nee
localparam CLEAR      = 4'd8;

localparam AW = $clog2(NUM_NEURONS);

reg [3:0] state;
reg [7:0] neuron_idx;
reg [9:0] input_idx;

parameter signed [15:0] BETA = 16'sd243;
parameter signed [15:0] THRESHOLD_VAL = 16'sd256;


wire signed [31:0] w_q8_8 = {{24{wr_rd_data[7]}}, wr_rd_data} <<< 1;
assign w_rd_addr = neuron_idx*(INPUT_LENGTH) + input_idx;

//reg signed [31:0] membrane_mem [0:NUM_NEURONS-1];
(* ram_style = "block" *) reg signed [31:0] membrane_mem [0:NUM_NEURONS-1];

reg signed [31:0] mem_rd;
reg signed [31:0] mem_wdata;
reg signed [31:0] acc;
reg [AW-1:0] clear_idx;
reg  mem_we;

wire [AW-1:0] mem_addr = (state == CLEAR) ? clear_idx : neuron_idx[AW-1:0];

assign ready = (state == IDLE);

always @(posedge clk) begin
    if (mem_we) membrane_mem[mem_addr] <= mem_wdata;
    mem_rd <= membrane_mem[mem_addr];
end


// reg decayed_this_timestep [0:NUM_NEURONS-1];
// integer k;
// reg signed [31:0] mem_decayed;
// always @(*) begin
//     if (decayed_this_timestep[neuron_idx])
//         mem_decayed = membrane_mem[neuron_idx];
//     else
//         mem_decayed = (membrane_mem[neuron_idx] * BETA) >>> 8; // turncates to 32 bits before conversion -> look at it 
// end

always @(posedge clk) begin
    if (rst) begin
            state <= CLEAR;
            clear_idx <= 0;
            neuron_idx <= 0;
            input_idx <= 0;
            skipped_mac_count <= 0;
            done <= 0;
            mem_we <= 1'b1;
            mem_wdata <= 32'sd0;
    end else begin
        case (state)

            CLEAR: begin 
                mem_we <= 1'b1;
                mem_wdata <= 32'b0;
                if (clear_idx == NUM_NEURONS-1) begin 
                    mem_we <= 1'b0;
                    state <= IDLE;
                end else clear_idx <= clear_idx + 1'b1;
            end


            IDLE: begin
                done <= 0;
                if (start) state <= LOAD_INPUT;
            end


            LOAD_INPUT: begin

                neuron_idx <= 0;
                input_idx  <= 0;
                state <= MEM_RD;
            end

            MEM_RD: begin           // mem_addr = neuron_idx, BRAM latches at this edge
                mem_we <= 1'b0;
                state  <= DECAY;
            end

            DECAY: begin            // mem_rd now valid; multiply alone in this cycle
                acc   <= (mem_rd * BETA) >>> 8;
                state <= ACCUMULATE;
            end

            ADDR:begin 
                state <=  ACCUMULATE;
            end

            ACCUMULATE: begin

                if (spike_in_vec[input_idx]) acc <= acc + w_q8_8;
                else                         skipped_mac_count <= skipped_mac_count + 1;

                if (input_idx == INPUT_LENGTH-1) begin
                    input_idx <= 0;
                    state <= THRESHOLD;
                end else begin
                    input_idx <= input_idx + 1;
                    state <= ADDR;
                end
            end

            THRESHOLD: begin
                spike_out_vec[neuron_idx] <= (acc >= THRESHOLD_VAL);
                mem_we    <= 1'b1;
                mem_wdata <= (acc >= THRESHOLD_VAL) ? 32'sd0 : acc;
                state     <= OUT_SPIKES;
            end

            OUT_SPIKES: begin
                mem_we <= 1'b0;
                if (neuron_idx == NUM_NEURONS-1) begin
                    done  <= 1;
                    state <= IDLE;
                end else begin
                    neuron_idx <= neuron_idx + 1;
                    input_idx  <= 0;
                    state      <= MEM_RD;
                end
            end

            default: begin 
                state <= IDLE;
            end 
        endcase
    end
end

endmodule
