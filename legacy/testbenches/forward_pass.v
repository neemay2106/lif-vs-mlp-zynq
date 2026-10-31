module tb_full_inference;

    reg clk, rst, start;
    reg [783:0] layer1_input;
    wire [255:0] layer1_output;
    wire [127:0] layer2_output;
    wire [9:0]   layer3_output;
    wire done1, done2, done3;
    wire [31:0] skip1, skip2, skip3;
    integer f;

    // --- NEW: edge detection for done1/done2 so L2/L3 get single-cycle start pulses ---
    reg done1_prev, done2_prev;
    wire start2 = done1 && !done1_prev;
    wire start3 = done2 && !done2_prev;

    reg [9:0] class_accumulator [0:9];
    integer t, c, j;
    reg [0:0] spike_bits [0:783];
    string filename;

    lif_layer1 L1 (.clk(clk), .rst(rst), .start(start), .spike_in_vec(layer1_input),
                   .spike_out_vec(layer1_output), .done(done1), .skipped_mac_count(skip1));

    lif_layer2 L2 (.clk(clk), .rst(rst), .start(start2), .spike_in_vec(layer1_output),
                   .spike_out_vec(layer2_output), .done(done2), .skipped_mac_count(skip2));

    lif_layer3 L3 (.clk(clk), .rst(rst), .start(start3), .spike_in_vec(layer2_output),
                   .spike_out_vec(layer3_output), .done(done3), .skipped_mac_count(skip3));

    always #5 clk = ~clk;

    // --- NEW: track previous-cycle done1/done2 for edge detection ---
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            done1_prev <= 0;
            done2_prev <= 0;
        end else begin
            done1_prev <= done1;
            done2_prev <= done2;
        end
    end

    initial begin
        clk = 0; rst = 1; start = 0;
        for (c = 0; c < 10; c = c + 1) class_accumulator[c] = 0;

        @(posedge clk); @(posedge clk);
        rst = 0;

        for (t = 0; t < 25; t = t + 1) begin

            filename = $sformatf("/Users/neemayrajan/Documents/Project_2/spike/spikes_t%0d.txt", t);
            
            $readmemh(filename, spike_bits);
            for (j = 0; j < 784; j = j + 1) begin
                layer1_input[j] = spike_bits[j];
            end
            

            @(posedge clk);
            start <= 1;
            $display("=== Pulsing start for timestep %0d at time %0t ===", t, $time);
            @(posedge clk);
            start <= 0;

            $display("spikes_out_vec = %h, count of spikes = %0d", layer2_output, $countones(layer2_output));

            wait (done3 == 1);

            for (c = 0; c < 10; c = c + 1) begin
                if (layer3_output[c])
                    class_accumulator[c] = class_accumulator[c] + 1;
            end

            @(posedge clk);
        end

        $display("Final class counts:");
        for (c = 0; c < 10; c = c + 1)
            $display("  class %0d: %0d spikes", c, class_accumulator[c]);

        $finish;
    end

endmodule