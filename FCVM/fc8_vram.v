// FCVM/fc8_vram.v
`include "fc8_defines.v"

module fc8_vram #(
    parameter AWIDTH = 16, // Address width for 64KB
    parameter DWIDTH = 8,  // Data width
    parameter SIZE   = 1 << AWIDTH // 65536 bytes
) (
    input wire clk, // Common clock for both ports for now
    input wire rst_n,

    // Port 1: CPU Interface (Read/Write)
    input wire [AWIDTH-1:0] cpu_addr_in,
    input wire [DWIDTH-1:0] cpu_data_in,
    input wire              cpu_wr_en_in,
    input wire              cpu_cs_in, // Chip select for CPU port
    output reg [DWIDTH-1:0] cpu_data_out,

    // Port 2: Video Controller Interface (Read-Only)
    input wire [AWIDTH-1:0] video_addr_in,
    input wire              video_rd_en_in, // Typically always enabled during active display
    output reg [DWIDTH-1:0] video_data_out
);

    // Declare the dual-port memory array
    // True dual-port RAM might require specific FPGA block RAM primitives.
    // This models a generic synchronous dual-port RAM.
    reg [DWIDTH-1:0] mem [0:SIZE-1];

    // CPU Port Logic (Port 1)
    always @(posedge clk) begin
        if (rst_n == 1'b0) begin
            // Initialize memory to $00 on reset
            // This can take a long time in simulation for large RAMs.
            // Consider if full reset initialization is always needed or can be skipped for faster sim.
            for (integer i = 0; i < SIZE; i = i + 1) begin
                mem[i] <= {DWIDTH{1'b0}};
            end
            cpu_data_out <= {DWIDTH{1'b0}};
        end else begin
            if (cpu_cs_in) begin
                if (cpu_wr_en_in) begin
                    if (cpu_addr_in < SIZE) begin // Bounds check
                        mem[cpu_addr_in] <= cpu_data_in;
                    end
                end
                // Read operation (combinational read-through for simplicity, or clocked)
                // For a synchronous read, data would be available on the next cycle.
                // This model provides data on the same cycle if not writing.
                // To model synchronous read for CPU:
                // if (!cpu_wr_en_in) begin cpu_data_out <= mem[cpu_addr_in]; end
                // For now, let's make it a clocked read.
                if (!cpu_wr_en_in) begin
                     if (cpu_addr_in < SIZE) begin // Bounds check
                        cpu_data_out <= mem[cpu_addr_in];
                    end else begin
                        cpu_data_out <= {DWIDTH{1'bz}}; // Or $00
                    end
                end else {
                     cpu_data_out <= {DWIDTH{1'bz}}; // Or old data if not writing and not reading
                }
            end else begin
                cpu_data_out <= {DWIDTH{1'bz}}; // High-impedance if chip not selected
            end
        end
    end

    // Video Port Logic (Port 2 - Read-Only)
    // This port is typically read continuously by the video display logic.
    always @(posedge clk) begin
        if (rst_n == 1'b0) begin
            video_data_out <= {DWIDTH{1'b0}};
        end else begin
            if (video_rd_en_in) begin // video_rd_en_in could be tied to h_active & v_active
                if (video_addr_in < SIZE) begin // Bounds check
                    video_data_out <= mem[video_addr_in];
                end else begin
                    video_data_out <= {DWIDTH{1'b0}}; // Black for out-of-bounds
                end
            end else {
                video_data_out <= {DWIDTH{1'b0}}; // Or a default color (e.g. border color if implemented)
            end
        end
    end

endmodule
