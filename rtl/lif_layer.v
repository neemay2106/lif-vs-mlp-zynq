
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
    output reg [31:0] skipped_mac_count
);

localparam IDLE = 3'd0;
localparam LOAD_INPUT = 3'd1;
localparam ADDR = 3'd2;
localparam ACCUMULATE = 3'd3;
localparam THRESHOLD = 3'd4;
localparam OUT_SPIKES = 3'd5;

reg [2:0] state;
reg [7:0] neuron_idx;
reg [9:0] input_idx;

parameter signed [15:0] BETA = 16'sd243;
parameter signed [15:0] THRESHOLD_VAL = 16'sd256;


wire signed [31:0] w_q8_8 = {{24{wr_rd_data[7]}}, wr_rd_data} <<< 1;
assign w_rd_addr = neuron_idx*(INPUT_LENGTH) + input_idx;

reg signed [31:0] membrane_mem [0:NUM_NEURONS-1];
reg decayed_this_timestep [0:NUM_NEURONS-1];
integer k;
reg signed [31:0] mem_decayed;


always @(*) begin
    if (decayed_this_timestep[neuron_idx])
        mem_decayed = membrane_mem[neuron_idx];
    else
        mem_decayed = (membrane_mem[neuron_idx] * BETA) >>> 8; // turncates to 32 bits before conversion -> look at it 
end

always @(posedge clk) begin
    if (rst) begin
        state <= IDLE;
        neuron_idx <= 0;
        input_idx <= 0;
        skipped_mac_count <= 0;
        done <= 0;
        for (k = 0; k < NUM_NEURONS; k = k + 1) begin
            membrane_mem[k] <= 0;
            decayed_this_timestep[k] <= 0;
        end
    end else begin
        case (state)
            IDLE: begin
                done <= 0;
                if (start) state <= LOAD_INPUT;
            end


            LOAD_INPUT: begin

                neuron_idx <= 0;
                input_idx  <= 0;
                for (k = 0; k < NUM_NEURONS; k = k + 1) begin
                    decayed_this_timestep[k] <= 0;
                end
                state <= ADDR;
            end

            ADDR:begin 
                state <=  ACCUMULATE;
            end

            ACCUMULATE: begin

                if (spike_in_vec[input_idx]) begin
                    membrane_mem[neuron_idx] <= mem_decayed + w_q8_8;
                end else begin
                    membrane_mem[neuron_idx] <= mem_decayed;
                    skipped_mac_count <= skipped_mac_count + 1;
                end

                decayed_this_timestep[neuron_idx] <= 1;

                if (input_idx == INPUT_LENGTH-1) begin
                    input_idx <= 0;
                    state <= THRESHOLD;
                end else begin
                    input_idx <= input_idx + 1;
                    state <= ADDR;
                end
            end

            THRESHOLD: begin
                if (membrane_mem[neuron_idx] >= THRESHOLD_VAL) begin
                    spike_out_vec[neuron_idx] <= 1;
                    membrane_mem[neuron_idx] <= 0;
                end else begin
                    spike_out_vec[neuron_idx] <= 0;
                end
                state <= OUT_SPIKES;
            end

            OUT_SPIKES: begin
                if (neuron_idx == NUM_NEURONS-1) begin
                    done <= 1;
                    state <= IDLE;
                end else begin
                    neuron_idx <= neuron_idx + 1;
                    input_idx  <= 0;
                    state <= ADDR;
                end
            end

            default: begin 
                state <= IDLE;
            end 
        endcase
    end
end

endmodule
