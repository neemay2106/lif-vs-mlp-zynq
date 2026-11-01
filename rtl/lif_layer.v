
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
    output reg [31:0] skipped_mac_count,
    output wire ready
);

localparam IDLE       = 4'd0;
localparam LOAD_INPUT = 4'd1;
localparam ADDR       = 4'd2;
localparam ACCUMULATE = 4'd3;
localparam THRESHOLD  = 4'd4;
localparam OUT_SPIKES = 4'd5;
localparam MEM_RD     = 4'd6;   // new
localparam DECAY      = 4'd7;   // nee
localparam CLEAR      = 4'd8;
localparam BUILD_LIST = 4'd9;   // event-driven: collect active input indices once per pass

localparam AW = $clog2(NUM_NEURONS);
localparam IW = $clog2(INPUT_LENGTH);

reg [3:0] state;
reg [7:0] neuron_idx;
reg [9:0] input_idx;

parameter signed [15:0] BETA = 16'sd243;
parameter signed [15:0] THRESHOLD_VAL = 16'sd256;

// spike list: indices of the 1-bits in spike_in_vec, built in BUILD_LIST.
// Every neuron then loops over these n_active entries only, so a zero
// spike costs no cycles. Async-read LUTRAM keeps the address path at
// one cycle, same as before.
(* ram_style = "distributed" *) reg [IW-1:0] spike_list [0:INPUT_LENGTH-1];
reg  [IW:0]   n_active;                     // 0..INPUT_LENGTH, one extra bit
reg  [IW:0]   k;                            // position in spike_list
reg  [17:0]   w_base;                       // neuron_idx*INPUT_LENGTH, kept by adding
wire [IW-1:0] cur_idx = spike_list[k[IW-1:0]];
wire          list_we = (state == BUILD_LIST) && spike_in_vec[input_idx];

always @(posedge clk) begin
    if (list_we) spike_list[n_active[IW-1:0]] <= input_idx[IW-1:0];
end

wire signed [31:0] w_q8_8 = {{24{wr_rd_data[7]}}, wr_rd_data} <<< 1;
assign w_rd_addr = w_base + cur_idx;

//reg signed [31:0] membrane_mem [0:NUM_NEURONS-1];
(* ram_style = "block" *) reg signed [31:0] membrane_mem [0:NUM_NEURONS-1];

reg signed [31:0] mem_rd;
reg signed [31:0] mem_wdata;
reg signed [31:0] acc;
reg [AW-1:0] clear_idx;
reg  mem_we;

wire [AW-1:0] mem_addr = (state == CLEAR) ? clear_idx : neuron_idx[AW-1:0];

assign ready = (state == IDLE);

always @(posedge clk) begin
    if (mem_we) membrane_mem[mem_addr] <= mem_wdata;
    mem_rd <= membrane_mem[mem_addr];
end


// reg decayed_this_timestep [0:NUM_NEURONS-1];
// integer k;
// reg signed [31:0] mem_decayed;
// always @(*) begin
//     if (decayed_this_timestep[neuron_idx])
//         mem_decayed = membrane_mem[neuron_idx];
//     else
//         mem_decayed = (membrane_mem[neuron_idx] * BETA) >>> 8; // turncates to 32 bits before conversion -> look at it 
// end

always @(posedge clk) begin
    if (rst) begin
            state <= CLEAR;
            clear_idx <= 0;
            neuron_idx <= 0;
            input_idx <= 0;
            n_active <= 0;
            k <= 0;
            w_base <= 0;
            skipped_mac_count <= 0;
            done <= 0;
            mem_we <= 1'b1;
            mem_wdata <= 32'sd0;
    end else begin
        case (state)

            CLEAR: begin 
                mem_we <= 1'b1;
                mem_wdata <= 32'b0;
                if (clear_idx == NUM_NEURONS-1) begin 
                    mem_we <= 1'b0;
                    state <= IDLE;
                end else clear_idx <= clear_idx + 1'b1;
            end


            IDLE: begin
                done <= 0;
                if (start) state <= LOAD_INPUT;
            end


            LOAD_INPUT: begin

                neuron_idx <= 0;
                input_idx  <= 0;
                n_active   <= 0;
                w_base     <= 0;
                k          <= 0;
                state <= BUILD_LIST;
            end

            BUILD_LIST: begin       // 1 input per cycle; list_we writes spike_list[n_active]
                if (spike_in_vec[input_idx]) n_active <= n_active + 1'b1;

                if (input_idx == INPUT_LENGTH-1) begin
                    input_idx <= 0;
                    state     <= MEM_RD;
                end else begin
                    input_idx <= input_idx + 1;
                end
            end

            MEM_RD: begin           // mem_addr = neuron_idx, BRAM latches at this edge
                mem_we <= 1'b0;     // w_rd_addr = w_base + spike_list[0] is fetched now too
                state  <= DECAY;
            end

            DECAY: begin            // mem_rd now valid; multiply alone in this cycle
                acc   <= (mem_rd * BETA) >>> 8;
                if (n_active == 0) state <= THRESHOLD;   // no spikes: leak only
                else               state <= ACCUMULATE;
            end

            ADDR:begin
                state <=  ACCUMULATE;
            end

            ACCUMULATE: begin       // wr_rd_data belongs to spike_list[k], always a 1-bit

                acc <= acc + w_q8_8;

                if (k == n_active-1) begin
                    k     <= 0;
                    state <= THRESHOLD;
                end else begin
                    k     <= k + 1'b1;
                    state <= ADDR;
                end
            end

            THRESHOLD: begin
                spike_out_vec[neuron_idx] <= (acc >= THRESHOLD_VAL);
                mem_we    <= 1'b1;
                mem_wdata <= (acc >= THRESHOLD_VAL) ? 32'sd0 : acc;
                skipped_mac_count <= skipped_mac_count + (INPUT_LENGTH - n_active);   // zero spikes of this neuron
                state     <= OUT_SPIKES;
            end

            OUT_SPIKES: begin
                mem_we <= 1'b0;
                if (neuron_idx == NUM_NEURONS-1) begin
                    done  <= 1;
                    state <= IDLE;
                end else begin
                    neuron_idx <= neuron_idx + 1;
                    w_base     <= w_base + INPUT_LENGTH;
                    k          <= 0;
                    state      <= MEM_RD;
                end
            end

            default: begin 
                state <= IDLE;
            end 
        endcase
    end
end

endmodule
