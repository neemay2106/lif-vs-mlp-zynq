module mlp_layer3 #(
    parameter N_INPUTS   = 128,
    parameter N_NEURONS  = 10,
    parameter SHIFT_AMT  = 9,     // 7 for layers 1-2, 9 for layer 3 — set per instantiation
    parameter RELU_EN    = 1      // 1 for layers 1-2, 0 for layer 3
)(
    input  clk, rst,
    input  start,
    output reg done,
    input  wire signed [7:0] act_data [0:127],
    output reg signed  [7:0] out_data [0:9]
    
);

    localparam IDLE = 4'd0;
    localparam LOAD = 4'd1;
    localparam ACCUMULATE = 4'd2;
    localparam REQUANT = 4'd3;
    localparam BIAS = 4'd4;
    localparam RELU = 4'd5;
    localparam WRITE_OUT = 4'd6;
    localparam DONE = 4'd7;
    

    initial begin
        $readmemh("weights/layer3_bias.hex", bias_data);
        $readmemh("weights/layer3_weights.hex", weight_data);
    end


    reg signed [7:0] weight_data [0:(128*10)-1];
    reg signed [7:0] bias_data[0:10];
    reg [3:0] states;
    reg [7:0] neuron_idx;
    reg [9:0] input_idx;


    reg signed [31:0] acc;          // raw MAC accumulator — only ever added-to during ACCUMULATE
    reg signed [31:0] acc_shifted;  // acc >>> SHIFT_AMT — computed once, in REQUANT
    reg signed [31:0] acc_biased;   // acc_shifted + bias_data — computed once, in REQUANT
    reg signed [31:0] acc_relu;  
    
    //always @(posedge clk) begin
    // $display("time=%0t state=%0d neuron=%0d input=%0d acc=%0d done=%b",
    //          $time, states, neuron_idx, input_idx, acc, done);
    // end   // ReLU applied (or passthrough) — computed once, in REQUANT

    always @(posedge clk) begin
        if (rst) begin
            states <= IDLE;
            neuron_idx <= 0;
            input_idx <= 0;
            done <= 0;
            acc <= 0;
            end else begin
        case(states) 
        IDLE: begin 
            done <= 0;
            if (start) states <= LOAD;
        end

        LOAD:begin 
            neuron_idx <= 0;
            input_idx <= 0;
            states <= ACCUMULATE;
        end 

        ACCUMULATE:begin 
            acc <= acc + (act_data[input_idx] * weight_data[neuron_idx*N_INPUTS + input_idx]); 

            if (input_idx == N_INPUTS-1) begin
                input_idx <= 0;
                states <= REQUANT;
            end else begin
            input_idx <= input_idx + 1;
        end
        end

        REQUANT:begin 
            
            acc_shifted <= acc >>> SHIFT_AMT;
            states <= BIAS;

        end

        BIAS:begin 
            acc_biased <= acc_shifted + bias_data[neuron_idx];
            states <= WRITE_OUT;
        end 

        

        WRITE_OUT:begin

            // $display("NEURON %0d: acc=%0d shifted=%0d biased=%0d relu=%0d",
            //  neuron_idx,
            //  acc,
            //  acc_shifted,
            //  acc_biased,
            //  acc_relu);
            if (acc_relu > 32'sd127)
                out_data[neuron_idx] <= 8'sd127;
            else if (acc_relu < -32'sd128)
                out_data[neuron_idx] <= -8'sd128;
            else
                out_data[neuron_idx] <= acc_biased[7:0];

            states <= DONE;
        end

        DONE:begin 
            if (neuron_idx != 10) begin 
                neuron_idx <= neuron_idx +1;
                input_idx <= 0;
                acc <= 0;
                states <= ACCUMULATE;
            end 
            else begin
                done <= 1;
                states <= IDLE;
            end 
        end
        endcase
            end
    end                                                                                          

endmodule