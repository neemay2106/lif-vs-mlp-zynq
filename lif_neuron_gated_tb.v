module lif_top_tb;
  reg clk;
  reg rst;
  initial clk = 0;

  //lif signals
   reg spike_in;
   reg signed [15:0] weight_in;
   wire spike_out;
   wire [31:0] skipped_mac_count;

   reg signed [15:0] expected_spike_out;
   reg signed [31:0] expected_membrane;
   reg signed [31:0] expected_skipped_count;

   integer fd;
   integer scan;
   integer cycle_count;
   integer error_count;


   lif_neuron_gated #(
    .WIDTH(16)
    ) dut (
        .clk(clk),
        .rst(rst),
        .spike_in(spike_in),
        .weight_in(weight_in),
        .spike_out(spike_out),
        .skipped_mac_count(skipped_mac_count)
    );

    always #5 clk = ~clk;

    task compare_with;
    input string filename_given;
    begin 
        fd = $fopen(filename_given, "r");
         if (fd == 0) begin
            $display("ERROR: could not open test vector file");
            $finish;
        end

        while (!$feof(fd)) begin 
            scan =  $fscanf(fd, "%d %d %d %d %d", spike_in,expected_spike_out,expected_membrane,
            expected_skipped_count,weight_in);
            // $display("scan=%0d", scan);
            // $display("spike=%0d exp_spike=%0d exp_mem=%0d exp_skip=%0d weight=%0d",
            //     spike_in, expected_spike_out, expected_membrane,
            //     expected_skipped_count, weight_in);

            if(scan == 5) begin 
              @(posedge clk); #1;

            cycle_count = cycle_count + 1;

            if (spike_out !== expected_spike_out) begin
                $display("MISMATCH at cycle %0d: spike_out = %0d, expected %0d",
                    cycle_count, spike_out, expected_spike_out);
                error_count = error_count + 1;
            end

            if (dut.membrane !== expected_membrane) begin
                $display("MISMATCH at cycle %0d: membrane = %0d, expected %0d",
                    cycle_count, dut.membrane, expected_membrane);
                error_count = error_count + 1;
            end

            if (skipped_mac_count !== expected_skipped_count) begin
                $display("MISMATCH at cycle %0d: skipped_mac_count = %0d, expected %0d",
                    cycle_count, skipped_mac_count, expected_skipped_count);
                error_count = error_count + 1;
            end
            end
            else begin
                $display("WARNING: fscanf returned %0d at cycle %0d, expected 5 — stopping", scan, cycle_count);
                disable compare_with;  // or use a flag + break pattern if `disable` on task name isn't supported by your sim
            end
        end

        $fclose(fd);

        if (error_count == 0) begin
            $display("PASS: all %0d cycles matched exactly.", cycle_count);
        end else begin
            $display("FAIL: %0d mismatches across %0d cycles.", error_count, cycle_count);
        end
        end
    endtask




    initial begin 
        clk = 0; 
        rst = 1;
        spike_in = 0;
        weight_in = 0;
        scan = 0;
        cycle_count = 0;
        error_count = 0;

        @(posedge clk);
        @(posedge clk);
        rst = 0;

        compare_with("expected_all_zero.txt");
        rst = 1;
        @(posedge clk);
        @(posedge clk);
        rst = 0;
        compare_with("expected_all_one.txt");
        rst = 1;
        @(posedge clk);
        @(posedge clk);
        rst = 0;
        compare_with("expected_negative.txt");
        rst = 1;
        @(posedge clk);
        @(posedge clk);
        rst = 0;
        compare_with("expected_realistic.txt");
        $finish;
    end


endmodule 
