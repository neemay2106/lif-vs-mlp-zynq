module lif_neuron_gated #(
    parameter WIDTH = 16,
    parameter signed [WIDTH-1:0] BETA = 16'sd243,
    parameter signed [WIDTH-1:0] THRESHOLD = 16'sd256
)(
    input  wire clk,
    input  wire rst,
    input  wire spike_in,
    input  wire signed [WIDTH-1:0] weight_in,
    output reg  spike_out,
    output reg  [31:0] skipped_mac_count
);

    reg  signed [WIDTH-1:0] membrane;
    wire signed [2*WIDTH-1:0] mac_beta_product;
    wire signed [WIDTH-1:0] weight_q8_8;
    wire signed [WIDTH-1:0] mem_decayed;
    wire signed [WIDTH-1:0] mem_next_prespike;   // decayed (+ weight if spiking), BEFORE reset check
    wire                    will_spike;

    assign weight_q8_8      = weight_in >>> 7;
    assign mac_beta_product = membrane * BETA;
    assign mem_decayed      = mac_beta_product >>> 8;
    assign mem_next_prespike = spike_in ? (mem_decayed + weight_q8_8) : mem_decayed;
    assign will_spike        = (mem_next_prespike >= THRESHOLD);

    always @(posedge clk) begin
        if (rst) begin
            membrane          <= 0;
            spike_out         <= 0;
            skipped_mac_count <= 0;
        end else begin
            membrane  <= will_spike ? {WIDTH{1'b0}} : mem_next_prespike;
            spike_out <= will_spike;
            if (!spike_in) begin
                skipped_mac_count <= skipped_mac_count + 1;
            end
        end
    end

endmodule