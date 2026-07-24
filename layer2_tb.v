module tb_top;

reg clk;
reg rst;
initial clk = 0;

reg start;
reg [255:0]spikes_in_vec;
wire [127:0]spikes_out_vec;
wire done;
wire [31:0]skipped_mac_count;



lif_layer2 layer2(
    .clk(clk),
    .rst(rst),
    .start(start),
    .spike_in_vec(spikes_in_vec),
    .spike_out_vec(spikes_out_vec),
    .done(done),
    .skipped_mac_count(skipped_mac_count)
);

always  #5 clk = ~clk;

reg [0:0] spike_bits [0:255];
integer j;
integer out_fd,b;

initial begin
    $readmemh("layer1_output.txt", spike_bits);
    for (j = 0; j < 256; j = j + 1) begin
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
    $display("skipped_mac_count = %0d ", skipped_mac_count);
    $display("spikes_out_vec = %h, count of spikes = %0d", spikes_out_vec, $countones(spikes_out_vec));
    out_fd = $fopen("layer2_output.txt", "w");
    for (b = 0; b < 127 ; b = b + 1) begin
        $fwrite(out_fd, "%0d\n", spikes_out_vec[b]);
    end
    $fclose(out_fd);

    

    $finish;

end

endmodule 
