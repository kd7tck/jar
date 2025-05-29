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
    input wire [7:0] rom_data,

    // New SFR outputs
    output wire [7:0] audio_freq_lo_out,
    output wire [7:0] audio_freq_hi_out,
    output wire [3:0] audio_volume_out,

    // New SFR input
    input wire [7:0] input_status_in
);

    // SFR Addresses
    localparam SFR_AUDIO_FREQ_LO_ADDR = 20'h020000;
    localparam SFR_AUDIO_FREQ_HI_ADDR = 20'h020001;
    localparam SFR_AUDIO_VOLUME_ADDR  = 20'h020002;
    localparam SFR_INPUT_STATUS_ADDR  = 20'h020003;

    // PAGE_SELECT_REG at $00FE (Section 3)
    reg [7:0] page_select_reg;

    // Memory blocks (simplified as registers; use BRAM in FPGA)
    reg [7:0] fixed_ram [0:32767];   // 32KB Fixed RAM ($000000-$007FFF)
    reg [7:0] vram [0:65535];        // 64KB VRAM ($010000-$01FFFF)
    // reg [7:0] sfr [0:32767];      // SFRs ($020000-$027FFF) - This will be replaced by individual SFR registers

    // New SFR registers
    reg [7:0] sfr_audio_freq_lo;
    reg [7:0] sfr_audio_freq_hi;
    reg [3:0] sfr_audio_volume;
    reg [7:0] sfr_input_status; // Read-only for CPU, written by input controller

    // Bank switching (Section 3)
    assign phys_addr = (cpu_addr < 16'h8000) ? {4'b0000, cpu_addr} :
                       {page_select_reg[4:0], cpu_addr[14:0] - 15'h8000};

    // Assign outputs for audio SFRs
    assign audio_freq_lo_out = sfr_audio_freq_lo;
    assign audio_freq_hi_out = sfr_audio_freq_hi;
    assign audio_volume_out = sfr_audio_volume;

    // Connect input status
    // sfr_input_status is updated combinationally from input_status_in
    // For reads, it will be handled in the always block.
    // For writes (by external controller), this input directly reflects its state.

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            page_select_reg <= 8'h00;
            cpu_data_out <= 8'h00;
            vram_data <= 8'h00;
            // sfr_data <= 8'h00; // Original SFR output, may remove if not used elsewhere
            
            // Initialize new SFRs
            sfr_audio_freq_lo <= 8'h00;
            sfr_audio_freq_hi <= 8'h00;
            sfr_audio_volume  <= 4'h0;
            // sfr_input_status is an input, so no reset here by memory controller
        end else begin
            // Handle reads
            if (!we) begin
                case (phys_addr[19:15])
                    5'b00000: cpu_data_out <= fixed_ram[phys_addr[14:0]]; // Fixed RAM
                    5'b00001: cpu_data_out <= 8'hFF; // Reserved (Section 14)
                    5'b00010, 5'b00011: cpu_data_out <= vram[phys_addr[15:0]]; // VRAM
                    // 5'b00100: cpu_data_out <= sfr[phys_addr[14:0]]; // SFRs - Old generic SFR read
                    5'b00100: begin // SFR region
                        if (phys_addr == SFR_AUDIO_FREQ_LO_ADDR)
                            cpu_data_out <= sfr_audio_freq_lo;
                        else if (phys_addr == SFR_AUDIO_FREQ_HI_ADDR)
                            cpu_data_out <= sfr_audio_freq_hi;
                        else if (phys_addr == SFR_AUDIO_VOLUME_ADDR)
                            cpu_data_out <= {4'b0000, sfr_audio_volume}; // Ensure 8-bit output for CPU
                        else if (phys_addr == SFR_INPUT_STATUS_ADDR)
                            cpu_data_out <= input_status_in; // Read directly from input
                        else
                            cpu_data_out <= 8'h00; // Default for unassigned SFRs
                    end
                    default: cpu_data_out <= rom_data; // Cartridge ROM
                endcase
            end

            // Handle writes
            if (we) begin
                case (phys_addr[19:15])
                    5'b00000: fixed_ram[phys_addr[14:0]] <= cpu_data_in;
                    5'b00010, 5'b00011: vram[phys_addr[15:0]] <= cpu_data_in;
                    // 5'b00100: sfr[phys_addr[14:0]] <= cpu_data_in; // SFRs - Old generic SFR write
                    5'b00100: begin // SFR region
                        if (phys_addr == SFR_AUDIO_FREQ_LO_ADDR)
                            sfr_audio_freq_lo <= cpu_data_in;
                        else if (phys_addr == SFR_AUDIO_FREQ_HI_ADDR)
                            sfr_audio_freq_hi <= cpu_data_in;
                        else if (phys_addr == SFR_AUDIO_VOLUME_ADDR)
                            sfr_audio_volume <= cpu_data_in[3:0]; // Store only lower 4 bits
                        // Writes to SFR_INPUT_STATUS_ADDR are ignored as it's read-only for CPU
                    end
                endcase
                if (cpu_addr == 16'h00FE) page_select_reg <= cpu_data_in; // Update PAGE_SELECT_REG
            end
        end
    end

endmodule
