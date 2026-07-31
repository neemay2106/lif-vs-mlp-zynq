
module lif_layer1(
    input wire clk,
    input wire rst,
    input wire start,
    input wire [783:0] spike_in_vec,
    output reg [255:0] spike_out_vec,
    output reg done,
    output reg [31:0] skipped_mac_count
);

localparam IDLE = 3'd0;
localparam LOAD_INPUT = 3'd1;
localparam ACCUMULATE = 3'd2;
localparam THRESHOLD = 3'd3;
localparam OUT_SPIKES = 3'd4;

reg [2:0] state;
reg [7:0] neuron_idx;
reg [9:0] input_idx;

parameter signed [15:0] BETA = 16'sd243;
parameter signed [15:0] THRESHOLD_VAL = 16'sd256;

reg signed [15:0] weight_mem [0:(784*256)-1];
reg signed [31:0] membrane_mem [0:255];
reg decayed_this_timestep [0:255];
integer k;
reg signed [15:0] mem_decayed;

initial begin
    $readmemh("/Users/neemayrajan/Documents/Project_2/data_layer/weights/weights_layer1.hex", weight_mem);
end



always @(*) begin
    if (decayed_this_timestep[neuron_idx])
        mem_decayed = membrane_mem[neuron_idx];
    else
        mem_decayed = (membrane_mem[neuron_idx] * BETA) >>> 8;
end

always @(posedge clk) begin
    if (rst) begin
        state <= IDLE;
        neuron_idx <= 0;
        input_idx <= 0;
        skipped_mac_count <= 0;
        done <= 0;
        for (k = 0; k < 256; k = k + 1) begin
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
                for (k = 0; k < 256; k = k + 1) begin
                    decayed_this_timestep[k] <= 0;
                end
                state <= ACCUMULATE;
            end

            ACCUMULATE: begin

                if (spike_in_vec[input_idx]) begin
                    membrane_mem[neuron_idx] <= mem_decayed + (weight_mem[neuron_idx*784 + input_idx] >>> 7);
                end else begin
                    membrane_mem[neuron_idx] <= mem_decayed;
                    skipped_mac_count <= skipped_mac_count + 1;
                end

                decayed_this_timestep[neuron_idx] <= 1;

                if (input_idx == 783) begin
                    input_idx <= 0;
                    state <= THRESHOLD;
                end else begin
                    input_idx <= input_idx + 1;
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
                if (neuron_idx == 255) begin
                    done <= 1;
                    state <= IDLE;
                end else begin
                    neuron_idx <= neuron_idx + 1;
                    input_idx  <= 0;
                    state <= ACCUMULATE;
                end
            end

            default: begin 
                state <= IDLE;
            end 
        endcase
    end
end

endmodule
