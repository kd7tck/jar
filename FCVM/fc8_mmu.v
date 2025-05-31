// FCVM/fc8_mmu.v
`include "fc8_defines.v"

module fc8_mmu (
    input wire clk,
    input wire rst_n,

    // CPU Interface
    input wire [15:0] cpu_addr_in,
    input wire [7:0]  cpu_data_in,
    input wire        cpu_rd_en,
    input wire        cpu_wr_en,
    output reg [7:0]  cpu_data_out,

    // Physical Memory Interface (Fixed RAM)
    output reg [14:0] fixed_ram_addr_out,
    input wire [7:0]  fixed_ram_data_in,
    output reg [7:0]  fixed_ram_data_out,
    output reg        fixed_ram_wr_en,
    output reg        fixed_ram_cs_en,

    // Physical Memory Interface (Cartridge ROM) - CPU Port
    output reg [17:0] cart_rom_cpu_addr_out, // Renamed for clarity
    input wire [7:0]  cart_rom_cpu_data_in,  // Renamed for clarity
    output reg        cart_rom_cpu_cs_en,    // Renamed for clarity

    // Physical Memory Interface (Cartridge ROM) - Sprite Engine Port
    input wire [19:0] sprite_rom_addr_in,    // From Sprite Engine (physical address)
    input wire        sprite_rom_rd_en_in,   // From Sprite Engine
    output reg [7:0]  sprite_rom_data_out,   // To Sprite Engine
    output reg        cart_rom_sprite_cs_en, // Chip select for sprite access to ROM

    // Physical Memory Interface (VRAM) - CPU Port
    output reg [15:0] vram_addr_out,
    input wire [7:0]  vram_data_from_cpu_port,
    output reg [7:0]  vram_data_to_cpu_port,
    output reg        vram_wr_en_out,
    output reg        vram_cs_out,

    // Physical Memory Interface (SFR Block)
    output reg [15:0] sfr_addr_out,
    input wire [7:0]  sfr_data_from_sfr_block,
    output reg [7:0]  sfr_data_to_sfr_block,
    output reg        sfr_wr_en_out,
    output reg        sfr_cs_out
);

    reg [7:0] page_select_reg_internal;
    wire is_fixed_ram_logical_access;
    wire is_paged_space_logical_access;
    wire is_page_select_reg_logical_access;
    wire is_cart_rom_paged_access;
    wire is_sfr_paged_access;
    wire is_vram_paged_access;

    localparam VRAM_PAGE0_ID = 8'h02;
    localparam VRAM_PAGE1_ID = 8'h03;
    localparam SFR_PAGE_ID = 8'h04;

    assign is_fixed_ram_logical_access = (cpu_addr_in[15] == 1'b0);
    assign is_paged_space_logical_access  = (cpu_addr_in[15] == 1'b1);
    assign is_page_select_reg_logical_access = (is_fixed_ram_logical_access && cpu_addr_in == `PAGE_SELECT_REG_ADDR);
    assign is_vram_paged_access = is_paged_space_logical_access &&
                                  (page_select_reg_internal == VRAM_PAGE0_ID || page_select_reg_internal == VRAM_PAGE1_ID);
    assign is_sfr_paged_access = is_paged_space_logical_access && (page_select_reg_internal == SFR_PAGE_ID);
    assign is_cart_rom_paged_access = is_paged_space_logical_access &&
                                      !(page_select_reg_internal == VRAM_PAGE0_ID ||
                                        page_select_reg_internal == VRAM_PAGE1_ID ||
                                        page_select_reg_internal == SFR_PAGE_ID);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            page_select_reg_internal <= `CART_HEADER_INIT_PAGE_SELECT;
            cpu_data_out <= 8'h00;
            fixed_ram_wr_en <= 1'b0; fixed_ram_cs_en <= 1'b0;
            cart_rom_cpu_cs_en <= 1'b0; cart_rom_sprite_cs_en <= 1'b0; sprite_rom_data_out <= 8'h00;
            vram_cs_out <= 1'b0; vram_wr_en_out <= 1'b0;
            vram_addr_out <= 16'h0000; vram_data_to_cpu_port <= 8'h00;
            sfr_cs_out <= 1'b0; sfr_wr_en_out <= 1'b0;
            sfr_addr_out <= 16'h0000; sfr_data_to_sfr_block <= 8'h00;
        end else begin
            fixed_ram_cs_en <= 1'b0; fixed_ram_wr_en <= 1'b0;
            cart_rom_cpu_cs_en  <= 1'b0; cart_rom_sprite_cs_en <= 1'b0; // Default sprite CS off
            vram_cs_out     <= 1'b0; vram_wr_en_out  <= 1'b0;
            sfr_cs_out      <= 1'b0; sfr_wr_en_out   <= 1'b0;
            cpu_data_out    <= 8'h00;

            // CPU Access Logic
            if (cpu_rd_en || cpu_wr_en) begin
                if (is_fixed_ram_logical_access) begin
                    fixed_ram_cs_en <= 1'b1;
                    fixed_ram_addr_out <= cpu_addr_in[14:0];
                    if (cpu_wr_en) begin
                        fixed_ram_wr_en <= 1'b1; fixed_ram_data_out <= cpu_data_in;
                        if (is_page_select_reg_logical_access) page_select_reg_internal <= cpu_data_in;
                    end else cpu_data_out <= fixed_ram_data_in;
                end else if (is_vram_paged_access) begin
                    vram_cs_out <= 1'b1;
                    vram_addr_out <= (page_select_reg_internal == VRAM_PAGE1_ID) ?
                                     ({1'b1, cpu_addr_in[14:0]}) : ({1'b0, cpu_addr_in[14:0]});
                    if (cpu_wr_en) begin
                        vram_wr_en_out <= 1'b1; vram_data_to_cpu_port <= cpu_data_in;
                    end else cpu_data_out <= vram_data_from_cpu_port;
                end else if (is_sfr_paged_access) begin
                    sfr_cs_out <= 1'b1; sfr_addr_out <= cpu_addr_in[14:0];
                    if (cpu_wr_en) begin
                        sfr_wr_en_out <= 1'b1; sfr_data_to_sfr_block <= cpu_data_in;
                    end else cpu_data_out <= sfr_data_from_sfr_block;
                end else if (is_cart_rom_paged_access) begin
                    cart_rom_cpu_cs_en <= 1'b1;
                    cart_rom_cpu_addr_out <= {page_select_reg_internal[4:0], cpu_addr_in[14:0]}; // Use renamed output
                    if (cpu_rd_en) cpu_data_out <= cart_rom_cpu_data_in; // Use renamed input
                end
            end

            // Sprite Engine ROM Access Logic (independent of CPU paged access)
            // Assumes sprite_rom_addr_in is a full physical address for the ROM
            if (sprite_rom_rd_en_in) begin
                cart_rom_sprite_cs_en <= 1'b1;
                // The sprite engine provides a full physical address.
                // The fc8_cart_rom module expects an address relative to its own start.
                // If fc8_cart_rom models the entire 1MB potential ROM space, then sprite_rom_addr_in can be used directly if it's within ROM's range.
                // For now, assume sprite_rom_addr_in is directly usable by fc8_cart_rom if it's within its ADDR_WIDTH.
                // No specific mapping here, direct pass-through of address.
                // Data will be available on cart_rom_cpu_data_in if ROM is single port, or a new port.
                // This will require fc8_cart_rom to have a second port.
                // For now, let's assume sprite_rom_data_out is directly connected to a second read port on fc8_cart_rom.
                // The MMU's role here is minimal if sprite engine generates full physical addresses for ROM.
                // If MMU needs to *map* a sprite engine logical address, this would be different.
                // The current plan is sprite engine gives physical ROM address.
                // So, MMU just needs to pass this through to the ROM's sprite port.
                // This means cart_rom_sprite_cs_en is the main signal from MMU to enable that port on ROM.
                // The actual ROM addressing for sprite port is handled in system.v by connecting sprite_rom_addr_in to ROM.
            end else begin
                cart_rom_sprite_cs_en <= 1'b0;
            end


            // CPU Reset Vector Fetching
            if (cpu_rd_en && (cpu_addr_in == `RESET_VECTOR_ADDR_LOW || cpu_addr_in == `RESET_VECTOR_ADDR_HIGH)) begin
                fixed_ram_cs_en <= 1'b0; vram_cs_out <= 1'b0; sfr_cs_out <= 1'b0;
                cart_rom_cpu_cs_en  <= 1'b1; // Use CPU port for reset vector
                reg [17:0] header_base_addr;
                // This should use page_select_reg_internal as it's set to CART_HEADER_INIT_PAGE_SELECT on reset.
                header_base_addr = {page_select_reg_internal[4:0], 15'h0000};
                if (cpu_addr_in == `RESET_VECTOR_ADDR_LOW)
                    cart_rom_cpu_addr_out <= header_base_addr + 18'h0026;
                else
                    cart_rom_cpu_addr_out <= header_base_addr + 18'h0027;
                cpu_data_out <= cart_rom_cpu_data_in;
            end
        end
    end

endmodule
