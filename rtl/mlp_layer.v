module mlp_layer #(
    parameter N_INPUTS   = 784,
    parameter N_NEURONS  = 256,
    parameter SHIFT_AMT  = 7,     // 7 for layers 1-2, 9 for layer 3 — set per instantiation
    parameter RELU_EN    = 1      // 1 for layers 1-2, 0 for layer 3
)(
    input  clk, rst,
    input  start,
    output reg done,

    output [$clog2(N_INPUTS)-1:0]  act_addr, 
    input  signed [7:0]            act_data,

    output [$clog2(N_INPUTS*N_NEURONS)-1:0] weight_addr,
    input  signed [7:0]                     weight_data,

    output [$clog2(N_NEURONS)-1:0] bias_addr,
    input  signed [7:0]            bias_data,

    output [$clog2(N_NEURONS)-1:0] out_addr,
    output signed [7:0]            out_data,
    output out_wr_en
);

    localparam IDLE = 4'd0;
    localparam LOAD = 4'd1;
    localparam ACCUMULATE = 4'd2;
    localparam REQUANT = 4'd3;
    localparam WRITE_OUT = 4'd4;
    localparam DONE = 4'd5;

    reg [3:0] states;
    reg [7:0] neuron_idx;
    reg [9:0] input_idx;


    reg signed [15:0] weight_mem [0:(784*256)-1];
    reg signed [31:0] neuron_sum [0:255];


    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            neuron_idx <= 0;
            input_idx <= 0;
            done <= 0;
            end
        end
        

    // FSM states — mirror the LIF layer's structure since that pattern is
    // already proven to work: IDLE, LOAD, ACCUMULATE, REQUANT, WRITE_OUT, NEXT_NEURON, DONE

    // WIDTH NOTES (check every one of these before writing a line of logic):
    //   act_data, weight_data, bias_data : signed [7:0]        (int8, Q1.7)
    //   product (act_data * weight_data) : signed [15:0]       (8x8 -> 16 bits, no truncation)
    //   accumulator                      : signed [31:0]       (INT32 per your plan, headroom for 784 accumulations)
    //   post-shift value (acc >>> SHIFT) : MUST stay signed [31:0] here —
    //       do NOT assign into a narrower reg before the bias-add and clip.
    //       This is the exact bug you just found in lif_layer1's mem_decayed:
    //       widening the accumulator does nothing if a downstream intermediate
    //       register truncates it back down before the value is used.
    //   post-bias value (post-shift + bias_data) : signed [31:0], still wide
    //   final clip (-128..127) -> out_data : signed [7:0], ONLY at the very last step

    // MAC loop: one (act_data * weight_data) per cycle, time-multiplexed,
    // accumulate into the 32-bit reg, no early truncation — per your plan's
    // explicit constraint ("never truncate to INT8 before the full dot
    // product is complete")

    // after last input for a neuron:
    //   acc_shifted = acc >>> SHIFT_AMT          // stays 32-bit
    //   acc_biased  = acc_shifted + bias_data     // stays 32-bit
    //   acc_relu    = RELU_EN ? (acc_biased[31] ? 32'sd0 : acc_biased) : acc_biased
    //   out_data    = clamp(acc_relu, -128, 127)  // narrows to 8-bit ONLY here

endmodule