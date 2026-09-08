module bram #(
    parameter RAM_DEPTH = 784*256,
    parameter RAM_WIDTH = 8,
    parameter INIT_FILE = ""
)
(
    input                              clk,
    input                              wr_en,
    input      [$clog2(RAM_DEPTH)-1:0] wr_addr,
    input      [RAM_WIDTH-1:0]         wr_data,
    input      [$clog2(RAM_DEPTH)-1:0] rd_addr,
    output reg [RAM_WIDTH-1:0]         rd_data
    
);

(* ram_style = "block" *) reg [RAM_WIDTH-1:0] mem [0:RAM_DEPTH-1];
`ifndef SYNTHESIS
initial if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
`endif

always @(posedge clk) begin 
    if(wr_en) mem[wr_addr] <= wr_data;
    rd_data <= mem[rd_addr];
end

endmodule