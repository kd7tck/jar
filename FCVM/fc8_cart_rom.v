// FCVM/fc8_cart_rom.v
`include "fc8_defines.v"

module fc8_cart_rom #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 18, // For CPU view via MMU (up to 256KB window)
                              // Sprite engine might use full 20-bit physical address for 1MB
    parameter ROM_SIZE = 1 << ADDR_WIDTH // This is for the CPU view primarily.
                                       // The actual ROM array might be larger if accessed by sprite engine directly.
                                       // Let's define a larger internal ROM if sprite addresses can exceed ADDR_WIDTH.
                                       // For now, assume sprite patterns are within the first 256KB for simplicity via this parameter.
                                       // If sprite_addr_in is 20-bit, internal ROM should be 1MB.
) (
    input wire clk,
    input wire rst_n,

    // Port 1: CPU Interface (via MMU paged access)
    input wire [ADDR_WIDTH-1:0] phy_addr_in_cpu, // CPU physical address (offset in current page or mapped header addr)
    input wire                  phy_cs_en_cpu,   // Chip select from MMU for CPU access
    output reg [DATA_WIDTH-1:0] phy_data_out_cpu,

    // Port 2: Sprite Engine Interface (Direct Physical Access)
    input wire [19:0] phy_addr_in_sprite, // Sprite engine physical address (up to 1MB)
    input wire        phy_cs_en_sprite,   // Chip select from MMU/System for sprite access
    output reg [DATA_WIDTH-1:0] phy_data_out_sprite
);

    // Define total physical ROM size, e.g., 1MB if sprite addresses are 20-bit
    localparam PHYSICAL_ROM_SIZE = 1 << 20; // 1MByte
    reg [DATA_WIDTH-1:0] rom [0:PHYSICAL_ROM_SIZE-1];

    initial begin
        integer i;
        for (i = 0; i < PHYSICAL_ROM_SIZE; i = i + 1) begin
            rom[i] = 8'h00;
        end

        localparam HEADER_PAGE_PHYS_BASE = `CART_ROM_PHYSICAL_PAGE_6_BASE;
        localparam PROG_ENTRY_LOGICAL = 16'h8000;

        rom[HEADER_PAGE_PHYS_BASE + 32'h0000] = `CART_HEADER_MAGIC_0;
        rom[HEADER_PAGE_PHYS_BASE + 32'h0001] = `CART_HEADER_MAGIC_1;
        // ... (rest of header and tilemap test program from previous step) ...
        // For brevity, assuming the tilemap test program is still here.
        // We'll add sprite patterns at a different physical location.

        // --- Tilemap Test Program (copied from previous state for completeness) ---
        localparam PROG_START_PHYS = HEADER_PAGE_PHYS_BASE;
        integer offset = 0;
        rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; rom[PROG_START_PHYS + offset] = 8'h04; offset++;
        rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        rom[PROG_START_PHYS + offset] = `PAGE_SELECT_REG_ADDR[7:0]; offset++; rom[PROG_START_PHYS + offset] = `PAGE_SELECT_REG_ADDR[15:8]; offset++;
        localparam TILEMAP_DEF_LOGICAL_BASE = PROG_ENTRY_LOGICAL + `TILEMAP_DEF_RAM_PAGE4_START_OFFSET;
        rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; rom[PROG_START_PHYS + offset] = 8'h01; offset++;
        rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        rom[PROG_START_PHYS + offset] = (TILEMAP_DEF_LOGICAL_BASE + 0)[7:0];  offset++; rom[PROG_START_PHYS + offset] = (TILEMAP_DEF_LOGICAL_BASE + 0)[15:8]; offset++;
        rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; rom[PROG_START_PHYS + offset] = 8'h00; offset++;
        rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        rom[PROG_START_PHYS + offset] = (TILEMAP_DEF_LOGICAL_BASE + 1)[7:0];  offset++; rom[PROG_START_PHYS + offset] = (TILEMAP_DEF_LOGICAL_BASE + 1)[15:8]; offset++;
        rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; rom[PROG_START_PHYS + offset] = 8'h02; offset++;
        rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        rom[PROG_START_PHYS + offset] = (TILEMAP_DEF_LOGICAL_BASE + 2)[7:0];  offset++; rom[PROG_START_PHYS + offset] = (TILEMAP_DEF_LOGICAL_BASE + 2)[15:8]; offset++;
        rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; rom[PROG_START_PHYS + offset] = 8'h81; offset++;
        rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        rom[PROG_START_PHYS + offset] = (TILEMAP_DEF_LOGICAL_BASE + 3)[7:0];  offset++; rom[PROG_START_PHYS + offset] = (TILEMAP_DEF_LOGICAL_BASE + 3)[15:8]; offset++;
        rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; rom[PROG_START_PHYS + offset] = 8'h03; offset++;
        rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        rom[PROG_START_PHYS + offset] = `PAGE_SELECT_REG_ADDR[7:0]; offset++; rom[PROG_START_PHYS + offset] = `PAGE_SELECT_REG_ADDR[15:8]; offset++;
        localparam TILE1_PATTERN_VRAM_LOGICAL_START = PROG_ENTRY_LOGICAL + `VRAM_TILE_PATTERN_BASE_ADDR + (`BYTES_PER_TILE_PATTERN * 1);
        integer current_vram_addr; integer row, col; reg [7:0] pixel_val;
        for (row = 0; row < 8; row = row+1) for (col = 0; col < 8; col = col+1) {
            current_vram_addr = TILE1_PATTERN_VRAM_LOGICAL_START + (row * 8) + col;
            pixel_val = (((row + col) % 2) == 0) ? 8'h01 : 8'h02;
            rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; rom[PROG_START_PHYS + offset] = pixel_val; offset++;
            rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
            rom[PROG_START_PHYS + offset] = current_vram_addr[7:0];   offset++; rom[PROG_START_PHYS + offset] = current_vram_addr[15:8]; offset++;
        }
        localparam TILE2_PATTERN_VRAM_LOGICAL_START = PROG_ENTRY_LOGICAL + `VRAM_TILE_PATTERN_BASE_ADDR + (`BYTES_PER_TILE_PATTERN * 2);
        for (i = 0; i < `BYTES_PER_TILE_PATTERN; i = i+1) {
            current_vram_addr = TILE2_PATTERN_VRAM_LOGICAL_START + i;
            rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; rom[PROG_START_PHYS + offset] = 8'h03; offset++;
            rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
            rom[PROG_START_PHYS + offset] = current_vram_addr[7:0];   offset++; rom[PROG_START_PHYS + offset] = current_vram_addr[15:8]; offset++;
        }
        rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; rom[PROG_START_PHYS + offset] = 8'h04; offset++;
        rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        rom[PROG_START_PHYS + offset] = `PAGE_SELECT_REG_ADDR[7:0]; offset++; rom[PROG_START_PHYS + offset] = `PAGE_SELECT_REG_ADDR[15:8]; offset++;
        rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; rom[PROG_START_PHYS + offset] = 8'h01; offset++;
        rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        rom[PROG_START_PHYS + offset] = `PALETTE_ADDR_REG_ADDR[7:0]; offset++; rom[PROG_START_PHYS + offset] = (`PALETTE_ADDR_REG_ADDR[15:8] | 8'h80); offset++;
        rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; rom[PROG_START_PHYS + offset] = 8'hE7; offset++;
        rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        rom[PROG_START_PHYS + offset] = `PALETTE_DATA_REG_ADDR[7:0]; offset++; rom[PROG_START_PHYS + offset] = (`PALETTE_DATA_REG_ADDR[15:8] | 8'h80); offset++;
        rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; rom[PROG_START_PHYS + offset] = 8'hAA; offset++;
        rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        rom[PROG_START_PHYS + offset] = `PALETTE_DATA_REG_ADDR[7:0]; offset++; rom[PROG_START_PHYS + offset] = (`PALETTE_DATA_REG_ADDR[15:8] | 8'h80); offset++;
        rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; rom[PROG_START_PHYS + offset] = 8'h13; offset++;
        rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        rom[PROG_START_PHYS + offset] = `PALETTE_ADDR_REG_ADDR[7:0]; offset++; rom[PROG_START_PHYS + offset] = (`PALETTE_ADDR_REG_ADDR[15:8] | 8'h80); offset++;
        rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; rom[PROG_START_PHYS + offset] = 8'h03; offset++;
        rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        rom[PROG_START_PHYS + offset] = `PALETTE_DATA_REG_ADDR[7:0]; offset++; rom[PROG_START_PHYS + offset] = (`PALETTE_DATA_REG_ADDR[15:8] | 8'h80); offset++;
        rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; rom[PROG_START_PHYS + offset] = 8'h03; offset++;
        rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        rom[PROG_START_PHYS + offset] = `SCREEN_CTRL_REG_ADDR[7:0]; offset++; rom[PROG_START_PHYS + offset] = (`SCREEN_CTRL_REG_ADDR[15:8] | 8'h80); offset++;
        localparam END_LOOP_OFFS = offset;
        rom[PROG_START_PHYS + offset] = `OP_JMP_ABS; offset++;
        rom[PROG_START_PHYS + offset] = END_LOOP_OFFS[7:0]; offset++;
        rom[PROG_START_PHYS + offset] = (PROG_ENTRY_LOGICAL[15:8] | (END_LOOP_OFFS >> 8)); offset++;
        // --- End of Tilemap Test Program ---


        // --- Sprite Patterns ---
        // Store at a known physical ROM location, e.g., starting at $040000
        localparam SPRITE_PATTERN_PHYS_BASE = 32'h040000;

        // Sprite ID 0: 16x16 solid square of color index $05
        // 256 bytes (16 rows * 16 pixels/row * 1 byte/pixel)
        for (i = 0; i < 256; i = i + 1) begin
            rom[SPRITE_PATTERN_PHYS_BASE + (0 * 256) + i] = 8'h05; // Color index 5
        end

        // Sprite ID 1: 16x16 frame (border color $06, inner $00 transparent)
        for (row = 0; row < 16; row = row + 1) begin
            for (col = 0; col < 16; col = col + 1) begin
                if (row == 0 || row == 15 || col == 0 || col == 15) begin
                    rom[SPRITE_PATTERN_PHYS_BASE + (1 * 256) + (row * 16) + col] = 8'h06; // Border color index 6
                end else begin
                    rom[SPRITE_PATTERN_PHYS_BASE + (1 * 256) + (row * 16) + col] = 8'h00; // Transparent inner
                end
            end
        end

    end

    // Port 1: CPU Read operation
    always @(posedge clk) begin
        if (phy_cs_en_cpu) begin
            // CPU address is page-relative or header-mapped.
            // This port is typically used for the program code & data.
            // phy_addr_in_cpu is already the correct physical address for the CPU view of ROM.
            if (phy_addr_in_cpu < PHYSICAL_ROM_SIZE) begin // Check against full ROM size if addresses can be large
                phy_data_out_cpu <= rom[phy_addr_in_cpu];
            end else begin
                phy_data_out_cpu <= 8'h00;
            end
        end else begin
            phy_data_out_cpu <= 8'hZZ;
        end
    end

    // Port 2: Sprite Engine Read operation
    always @(posedge clk) begin
        if (phy_cs_en_sprite) begin
            // phy_addr_in_sprite is a direct physical address into the ROM space
            if (phy_addr_in_sprite < PHYSICAL_ROM_SIZE) begin
                phy_data_out_sprite <= rom[phy_addr_in_sprite];
            end else begin
                phy_data_out_sprite <= 8'h00; // Or default sprite pixel (e.g. transparent)
            end
        end else begin
            phy_data_out_sprite <= 8'hZZ;
        end
    end

endmodule
