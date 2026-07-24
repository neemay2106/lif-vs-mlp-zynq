module tb_top;

reg clk;
reg rst;
initial clk = 0;

reg start;
reg [783:0]spikes_in_vec;
wire [255:0]spikes_out_vec;
wire done;
wire [31:0]skipped_mac_count;



lif_layer1 layer1(
    .clk(clk),
    .rst(rst),
    .start(start),
    .spike_in_vec(spikes_in_vec),
    .spike_out_vec(spikes_out_vec),
    .done(done),
    .skipped_mac_count(skipped_mac_count)
);

always  #5 clk = ~clk;

reg [0:0] spike_bits [0:783];
integer j;
integer out_fd,b;

initial begin
    $readmemh("/Users/neemayrajan/Documents/Project_2/spike/spikes_t1.txt", spike_bits);
    for (j = 0; j < 784; j = j + 1) begin
        spikes_in_vec[j] = spike_bits[j];
    end
end

initial begin 
    rst = 1;
    start = 0;

    @(posedge clk); 
    @(posedge clk);
    rst = 0;

    @(posedge clk);
    start = 1;
    @(posedge clk);
    start = 0;

    wait(done == 1);
    $display("DONE reached at time %0t", $time);
    $display("skipped_mac_count = %0d (expect 784*256 = 200704 for all-zero input)", skipped_mac_count);
    $display("spikes_out_vec = %h, count of spikes = %0d", spikes_out_vec, $countones(spikes_out_vec));
    out_fd = $fopen("layer1_output.txt", "w");
    for (b = 0; b < 256; b = b + 1) begin
        $fwrite(out_fd, "%0d\n", spikes_out_vec[b]);
    end
    $fclose(out_fd);

    

    $finish;

end

endmodule 
