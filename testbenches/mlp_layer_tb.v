module mlp_layer_tb;

    localparam N_INPUTS  = 784;
    localparam N_NEURONS = 256;

    localparam N_INPUTS_LAYER2  = 256;
    localparam N_NEURONS_LAYER2 = 128;

    localparam N_INPUTS_LAYER3  = 128;
    localparam N_NEURONS_LAYER3 = 10;
    reg clk;
    reg rst;
    reg start;
    reg signed [7:0]  act_data [0:N_INPUTS-1];
    wire signed [7:0] out_data [0:N_NEURONS-1];
    wire signed [7:0] out_data_layer2 [0:N_NEURONS_LAYER2-1];
    wire signed [7:0] out_data_layer3 [0:N_NEURONS_LAYER3-1];




    wire done;
    wire done2;
    wire done3;

    // ------------------------------------------------
    // DUT
    // ------------------------------------------------
    mlp_layer #(
        .N_INPUTS  (N_INPUTS),
        .N_NEURONS (N_NEURONS),
        .SHIFT_AMT (7),
        .RELU_EN   (1)
    ) dut (
        .clk       (clk),
        .rst       (rst),
        .start     (start),
        .act_data  (act_data),
        .out_data  (out_data),
        .done      (done)
    );

    mlp_layer2 #(
        .N_INPUTS  (N_INPUTS_LAYER2),
        .N_NEURONS (N_NEURONS_LAYER2),
        .SHIFT_AMT (7),
        .RELU_EN   (1)
    ) dut2 (
        .clk       (clk),
        .rst       (rst),
        .start     (done),
        .act_data  (out_data),
        .out_data  (out_data_layer2),
        .done      (done2)
    );

    mlp_layer3 #(
        .N_INPUTS  (N_INPUTS_LAYER3),
        .N_NEURONS (N_NEURONS_LAYER3),
        .SHIFT_AMT (9),
        .RELU_EN   (1)
    ) dut3 (
        .clk       (clk),
        .rst       (rst),
        .start     (done2),
        .act_data  (out_data_layer2),
        .out_data  (out_data_layer3),
        .done      (done3)
    );

    reg [7:0] input_data [0:783];


    // ------------------------------------------------
    // Clock
    // ------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    integer j;

    initial begin 
        $readmemh("mnist_89_q17.hex", input_data);
        for (j = 0; j < 784; j = j + 1) begin
            act_data[j] = input_data[j];
        end
    end

    initial begin
    #10_000_000;
    $display("ERROR: Simulation timed out!");
    $finish;
    end


    // ------------------------------------------------
    // Test
    // ------------------------------------------------
    integer i,k;

    initial begin
    rst = 1;
    start = 0;

    repeat (2) @(posedge clk);

    @(negedge clk);
    rst = 0;

    @(negedge clk);
    start = 1;

    @(negedge clk);
    start = 0;

    wait(done3);

    $display("MLP layer finished!");

    // for (i = 0; i < N_NEURONS; i = i + 1)
    //     $display("output[%0d] = %0d", i, out_data[i]);

    #20;

    for (k = 0; k < N_NEURONS_LAYER3; k = k + 1)
        $display("output[%0d]_layer3 = %0d", k, out_data_layer3[k]);

    $finish;
end

endmodule