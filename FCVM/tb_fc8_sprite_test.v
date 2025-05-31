// FCVM/tb_fc8_sprite_test.v
`include "fc8_defines.v"

module tb_fc8_sprite_test;

    // Clock and Reset
    reg master_clk;
    reg master_rst_n;

    // Instantiate fc8_system
     fc8_system u_fc8_system (
        .master_clk(master_clk),
        .master_rst_n(master_rst_n)
    );

    // Clock generation (e.g., 20MHz master clock)
    initial begin
        master_clk = 0;
        forever #25 master_clk = ~master_clk; // 50ns period (20MHz)
    end

    // ROM program specific to this testbench
    initial begin
        // Program the fc8_cart_rom with sprite test program
        // This requires direct access to the ROM's memory array for test setup.
        // This is usually done via $readmemh or by pre-loading the 'rom' array
        // if the ROM module allows it for test purposes.
        // For this flow, we assume the fc8_cart_rom.v has been updated with the
        // sprite test program (setting SAT entries, VRAM background, enabling display).

        // Example of how one might load if 'rom' was accessible:
        // --- Cartridge Header ---
        // u_fc8_system.u_cart_rom.rom[`CART_ROM_PHYSICAL_PAGE_6_BASE + 32'h0000] = `CART_HEADER_MAGIC_0;
        // ... (rest of header) ...
        // u_fc8_system.u_cart_rom.rom[`CART_ROM_PHYSICAL_PAGE_6_BASE + 32'h0038] = 8'h06; // Start on page 6

        // --- Sprite Test Program (at logical $8000 on page 6) ---
        integer offset = 0;
        localparam PROG_START_PHYS = `CART_ROM_PHYSICAL_PAGE_6_BASE;

        // 1. Set PAGE_SELECT_REG to 4 (SFR Page)
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = 8'h04;       offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `PAGE_SELECT_REG_ADDR[7:0]; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `PAGE_SELECT_REG_ADDR[15:8]; offset++;

        // 2. Write SAT Entries (SFR space $0200-$05FF on Page 4 -> logical $8200-$85FF)
        localparam SAT_LOGICAL_BASE = 16'h8000 + `SAT_PAGE4_START_OFFSET;
        // Sprite 0: ID 0, X=50, Y=50, Attr (Priority=1, Palette=0)
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = 8'd50; offset++; // Y
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = (SAT_LOGICAL_BASE + 0)[7:0]; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = (SAT_LOGICAL_BASE + 0)[15:8]; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = 8'h00; offset++; // ID
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = (SAT_LOGICAL_BASE + 1)[7:0]; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = (SAT_LOGICAL_BASE + 1)[15:8]; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = 8'b00100000; offset++; // Attr: P=1
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = (SAT_LOGICAL_BASE + 2)[7:0]; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = (SAT_LOGICAL_BASE + 2)[15:8]; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = 8'd50; offset++; // X
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = (SAT_LOGICAL_BASE + 3)[7:0]; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = (SAT_LOGICAL_BASE + 3)[15:8]; offset++;

        // Sprite 1: ID 1, X=70, Y=50, Attr (Priority=0, Palette=0, FlipX=1)
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = 8'd50; offset++; // Y
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = (SAT_LOGICAL_BASE + 4)[7:0]; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = (SAT_LOGICAL_BASE + 4)[15:8]; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = 8'h01; offset++; // ID
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = (SAT_LOGICAL_BASE + 5)[7:0]; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = (SAT_LOGICAL_BASE + 5)[15:8]; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = 8'b01000000; offset++; // Attr: P=0, FlipX=1
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = (SAT_LOGICAL_BASE + 6)[7:0]; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = (SAT_LOGICAL_BASE + 6)[15:8]; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = 8'd70; offset++; // X
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = (SAT_LOGICAL_BASE + 7)[7:0]; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = (SAT_LOGICAL_BASE + 7)[15:8]; offset++;

        // Disable further sprites
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = 8'hFF; offset++; // Sprite ID FF
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = (SAT_LOGICAL_BASE + 9)[7:0]; offset++; // SAT entry 2, Tile ID byte
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = (SAT_LOGICAL_BASE + 9)[15:8]; offset++;

        // 3. Initialize Palette (e.g., color $01=blue, $05=green for sprite 0, $06=red for sprite 1)
        // Palette Addr $01
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = 8'h01; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `PALETTE_ADDR_REG_ADDR[7:0]; offset++; u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = (`PALETTE_ADDR_REG_ADDR[15:8]|8'h80); offset++;
        // Palette Data $03 (Blue) for VRAM background
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = 8'h03; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `PALETTE_DATA_REG_ADDR[7:0]; offset++; u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = (`PALETTE_DATA_REG_ADDR[15:8]|8'h80); offset++;
        // Palette Addr $05 (auto-inc from $01 fails if addr was written before)
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = 8'h05; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `PALETTE_ADDR_REG_ADDR[7:0]; offset++; u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = (`PALETTE_ADDR_REG_ADDR[15:8]|8'h80); offset++;
        // Palette Data $2C (Green) for Sprite 0
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = 8'h2C; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `PALETTE_DATA_REG_ADDR[7:0]; offset++; u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = (`PALETTE_DATA_REG_ADDR[15:8]|8'h80); offset++;
        // Palette Addr $06
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = 8'h06; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `PALETTE_ADDR_REG_ADDR[7:0]; offset++; u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = (`PALETTE_ADDR_REG_ADDR[15:8]|8'h80); offset++;
        // Palette Data $C0 (Red) for Sprite 1
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = 8'hC0; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `PALETTE_DATA_REG_ADDR[7:0]; offset++; u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = (`PALETTE_DATA_REG_ADDR[15:8]|8'h80); offset++;

        // 4. Set PAGE_SELECT_REG to 2 (VRAM Page 0)
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = 8'h02; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `PAGE_SELECT_REG_ADDR[7:0]; offset++; u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `PAGE_SELECT_REG_ADDR[15:8]; offset++;

        // 5. Write VRAM background (e.g., all color index $01)
        // Simple fill of first 256 bytes of VRAM
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_LDX_IMM; offset++; u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = 8'h00; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = 8'h01; offset++; // BG color index
        localparam VRAM_FILL_LOOP_OFFS = offset;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_STA_ABS_X; offset++; // STA $8000,X (logical VRAM $0000,X on page 2)
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = 8'h00; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = 8'h80; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_INX; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_BNE_REL; offset++; // Loop if X != 0 (after INX)
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = (256 - (offset - VRAM_FILL_LOOP_OFFS) - 1); offset++;


        // 6. Set PAGE_SELECT_REG to 4 (SFR Page)
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = 8'h04; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `PAGE_SELECT_REG_ADDR[7:0]; offset++; u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `PAGE_SELECT_REG_ADDR[15:8]; offset++;

        // 7. Enable display (SCREEN_CTRL_REG $8800 on SFR page)
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_LDA_IMM; offset++; u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = 8'h01; offset++; // Display enable, bitmap mode
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_STA_ABS; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `SCREEN_CTRL_REG_ADDR[7:0]; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = (`SCREEN_CTRL_REG_ADDR[15:8] | 8'h80); offset++;

        // 8. Loop indefinitely
        localparam END_LOOP_SPRITE_OFFS = offset;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = `OP_JMP_ABS; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = END_LOOP_SPRITE_OFFS[7:0]; offset++;
        u_fc8_system.u_cart_rom.rom[PROG_START_PHYS + offset] = (`PROG_ENTRY_LOGICAL[15:8] | (END_LOOP_SPRITE_OFFS >> 8)); offset++;

    end


    // Test Sequence
    initial begin
        master_rst_n = 1'b0;
        #200;
        master_rst_n = 1'b1;

        $display("Time PC Opcode A X Y SP NVBDIZC PSR_MMU GfxMode SATAddr SATData ROMAddr ROMData HSync VSync R G B");
        $monitor("%6dns %04X %02X    %02X %02X %02X %04X %b%b%b%b%b%b%b%b  %02X      %01b       %03X     %02X      %05X   %02X      %b %b %1d%1d%1d",
                 $time,
                 u_fc8_system.u_cpu.pc, u_fc8_system.u_cpu.opcode,
                 u_fc8_system.u_cpu.a, u_fc8_system.u_cpu.x, u_fc8_system.u_cpu.y, u_fc8_system.u_cpu.sp,
                 u_fc8_system.u_cpu.f[`N_FLAG_BIT], u_fc8_system.u_cpu.f[`V_FLAG_BIT], u_fc8_system.u_cpu.f[5],
                 u_fc8_system.u_cpu.f[`B_FLAG_BIT], u_fc8_system.u_cpu.f[`D_FLAG_BIT], u_fc8_system.u_cpu.f[`I_FLAG_BIT],
                 u_fc8_system.u_cpu.f[`Z_FLAG_BIT], u_fc8_system.u_cpu.f[`C_FLAG_BIT],
                 u_fc8_system.u_mmu.page_select_reg_internal,
                 u_fc8_system.sfr_graphics_mode_to_graphics,
                 u_fc8_system.u_sprite_engine.sat_addr_out,
                 u_fc8_system.u_sprite_engine.sat_data_in,
                 u_fc8_system.u_sprite_engine.rom_addr_out,
                 u_fc8_system.u_sprite_engine.rom_data_in,
                 u_fc8_system.u_graphics.vga_hsync, u_fc8_system.u_graphics.vga_vsync,
                 u_fc8_system.u_graphics.vga_r, u_fc8_system.u_graphics.vga_g, u_fc8_system.u_graphics.vga_b
        );

        #100_000_000; // 100 ms

        $display("\n--- Sprite Test Verification ---");
        // Check SAT entries (via hierarchical path)
        if (u_fc8_system.u_sfr_block.sprite_attribute_table_ram[`SAT_PAGE4_START_OFFSET - `SAT_PAGE4_START_OFFSET + 0] == 8'd50 && // Sprite 0 Y
            u_fc8_system.u_sfr_block.sprite_attribute_table_ram[`SAT_PAGE4_START_OFFSET - `SAT_PAGE4_START_OFFSET + 1] == 8'h00 && // Sprite 0 ID
            u_fc8_system.u_sfr_block.sprite_attribute_table_ram[`SAT_PAGE4_START_OFFSET - `SAT_PAGE4_START_OFFSET + 2] == 8'b00100000 && // Sprite 0 Attr
            u_fc8_system.u_sfr_block.sprite_attribute_table_ram[`SAT_PAGE4_START_OFFSET - `SAT_PAGE4_START_OFFSET + 3] == 8'd50) begin // Sprite 0 X
            $display("SUCCESS: SAT Entry 0 for Sprite 0 programmed correctly.");
        end else begin
            $display("FAILURE: SAT Entry 0 for Sprite 0 incorrect.");
        end

        if (u_fc8_system.u_sfr_block.sprite_attribute_table_ram[`SAT_PAGE4_START_OFFSET - `SAT_PAGE4_START_OFFSET + 4] == 8'd50 && // Sprite 1 Y
            u_fc8_system.u_sfr_block.sprite_attribute_table_ram[`SAT_PAGE4_START_OFFSET - `SAT_PAGE4_START_OFFSET + 5] == 8'h01 && // Sprite 1 ID
            u_fc8_system.u_sfr_block.sprite_attribute_table_ram[`SAT_PAGE4_START_OFFSET - `SAT_PAGE4_START_OFFSET + 6] == 8'b01000000 && // Sprite 1 Attr
            u_fc8_system.u_sfr_block.sprite_attribute_table_ram[`SAT_PAGE4_START_OFFSET - `SAT_PAGE4_START_OFFSET + 7] == 8'd70) begin // Sprite 1 X
            $display("SUCCESS: SAT Entry 1 for Sprite 1 programmed correctly.");
        end else begin
            $display("FAILURE: SAT Entry 1 for Sprite 1 incorrect.");
        end


        // Check VRAM background
        if (u_fc8_system.u_vram.mem[16'h0000] == 8'h01) begin // VRAM address $0000 (logical $8000 on page 2)
             $display("SUCCESS: VRAM background pixel at $0000 set to $01.");
        end else begin
             $display("FAILURE: VRAM background pixel at $0000 is %02X (Expected $01).", u_fc8_system.u_vram.mem[16'h0000]);
        end

        $finish;
    end

endmodule
