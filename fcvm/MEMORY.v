module fc8_memory_controller (
    input wire clk,
    input wire rst_n,
    input wire [15:0] cpu_addr,      // Logical address
    input wire [7:0] cpu_data_in,
    output reg [7:0] cpu_data_out,
    input wire we,
    output wire [19:0] phys_addr,    // Physical address
    input wire [7:0] mem_data_out,
    output reg [7:0] vram_data,
    output reg [7:0] sfr_data,
    input wire [7:0] rom_data
);

    // PAGE_SELECT_REG at $00FE (Section 3)
    reg [7:0] page_select_reg;

    // Memory blocks (simplified as registers; use BRAM in FPGA)
    reg [7:0] fixed_ram [0:32767];   // 32KB Fixed RAM ($000000-$007FFF)
    reg [7:0] vram [0:65535];        // 64KB VRAM ($010000-$01FFFF)
    reg [7:0] sfr [0:32767];         // SFRs ($020000-$027FFF)

    // Bank switching (Section 3)
    assign phys_addr = (cpu_addr < 16'h8000) ? {4'b0000, cpu_addr} :
                       {page_select_reg[4:0], cpu_addr[14:0] - 15'h8000};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            page_select_reg <= 8'h00;
            cpu_data_out <= 8'h00;
            vram_data <= 8'h00;
            sfr_data <= 8'h00;
        end else begin
            // Handle reads
            if (!we) begin
                case (phys_addr[19:15])
                    5'b00000: cpu_data_out <= fixed_ram[phys_addr[14:0]]; // Fixed RAM
                    5'b00001: cpu_data_out <= 8'hFF; // Reserved (Section 14)
                    5'b00010, 5'b00011: cpu_data_out <= vram[phys_addr[15:0]]; // VRAM
                    5'b00100: cpu_data_out <= sfr[phys_addr[14:0]]; // SFRs
                    default: cpu_data_out <= rom_data; // Cartridge ROM
                endcase
            end

            // Handle writes
            if (we) begin
                case (phys_addr[19:15])
                    5'b00000: fixed_ram[phys_addr[14:0]] <= cpu_data_in;
                    5'b00010, 5'b00011: vram[phys_addr[15:0]] <= cpu_data_in;
                    5'b00100: sfr[phys_addr[14:0]] <= cpu_data_in;
                endcase
                if (cpu_addr == 16'h00FE) page_select_reg <= cpu_data_in; // Update PAGE_SELECT_REG
            end
        end
    end

endmodule
