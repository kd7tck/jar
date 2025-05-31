// FCVM/fc8_ram.v
`include "fc8_defines.v"

module fc8_ram #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 15, // For 32KB RAM (2^15 = 32768)
    parameter RAM_SIZE   = 1 << ADDR_WIDTH
) (
    input wire clk,
    input wire rst_n, // Active low reset

    input wire [ADDR_WIDTH-1:0] phy_addr_in,
    input wire [DATA_WIDTH-1:0] phy_data_in,
    input wire phy_wr_en,
    input wire phy_cs_en, // Chip select

    output reg [DATA_WIDTH-1:0] phy_data_out
);

    // Declare the memory array
    reg [DATA_WIDTH-1:0] mem [0:RAM_SIZE-1];

    // Read operation
    always @(posedge clk) begin
        if (phy_cs_en && !phy_wr_en) begin
            phy_data_out <= mem[phy_addr_in];
        end
    end

    // Write operation & Reset initialization
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize memory to $00 on reset
            for (integer i = 0; i < RAM_SIZE; i = i + 1) begin
                mem[i] <= {DATA_WIDTH{1'b0}};
            end
            phy_data_out <= {DATA_WIDTH{1'b0}}; // Default output during/after reset
        end else begin
            if (phy_cs_en && phy_wr_en) begin
                mem[phy_addr_in] <= phy_data_in;
            end
        end
    end

endmodule
