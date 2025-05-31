// FCVM/tb_fc8_tilemap_test.v
`include "fc8_defines.v"

module tb_fc8_tilemap_test;

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
                                            // Pixel clock will be 20MHz / 4 = 5MHz (200ns period)
    end

    // Test Sequence
    initial begin
        master_rst_n = 1'b0; // Assert reset
        #200; // Hold reset for a bit
        master_rst_n = 1'b1; // De-assert reset

        // Monitor signals relevant to tilemap mode
        $display("Time PC Opcode A X Y SP NVBDIZC PSR_MMU GfxMode VRAMAddr TileDefAddr TileDefData HSync VSync R G B");
        $monitor("%6dns %04X %02X    %02X %02X %02X %04X %b%b%b%b%b%b%b%b  %02X      %01b       %04X     %04X        %02X          %b %b %1d%1d%1d",
                 $time,
                 u_fc8_system.u_cpu.pc,
                 u_fc8_system.u_cpu.opcode,
                 u_fc8_system.u_cpu.a,
                 u_fc8_system.u_cpu.x,
                 u_fc8_system.u_cpu.y,
                 u_fc8_system.u_cpu.sp,
                 u_fc8_system.u_cpu.f[`N_FLAG_BIT], u_fc8_system.u_cpu.f[`V_FLAG_BIT],
                 u_fc8_system.u_cpu.f[5], // Unused bit
                 u_fc8_system.u_cpu.f[`B_FLAG_BIT],
                 u_fc8_system.u_cpu.f[`D_FLAG_BIT], u_fc8_system.u_cpu.f[`I_FLAG_BIT],
                 u_fc8_system.u_cpu.f[`Z_FLAG_BIT], u_fc8_system.u_cpu.f[`C_FLAG_BIT],
                 u_fc8_system.u_mmu.page_select_reg_internal,      // MMU's internal page select
                 u_fc8_system.sfr_graphics_mode_to_graphics,       // Graphics mode to graphics unit
                 u_fc8_system.graphics_vram_addr_out,              // VRAM address from graphics
                 u_fc8_system.graphics_tilemap_def_addr_to_sfr,    // Tile Def RAM address from graphics
                 u_fc8_system.sfr_tilemap_def_data_to_graphics,    // Tile Def RAM data to graphics
                 u_fc8_system.u_graphics.vga_hsync,
                 u_fc8_system.u_graphics.vga_vsync,
                 u_fc8_system.u_graphics.vga_r,
                 u_fc8_system.u_graphics.vga_g,
                 u_fc8_system.u_graphics.vga_b
        );

        // Run for enough time to see a few frames.
        // One frame is H_TOTAL_PIXELS * V_TOTAL_LINES * pixel_clk_period
        // = 341 * 262 * 200ns = 17.8564 ms
        // Let's run for ~3 frames => ~54ms
        #54_000_000; // 54 ms in ns

        // Verification
        $display("\n--- Tilemap Test Verification ---");

        // Check if display was enabled and in tilemap mode
        if (u_fc8_system.u_sfr_block.screen_ctrl_reg_internal == 8'h03) begin // B0=1 (Enable), B1=1 (Tilemap)
            $display("SUCCESS: Display enabled in Tilemap Mode (SCREEN_CTRL_REG = %02X).", u_fc8_system.u_sfr_block.screen_ctrl_reg_internal);
        end else begin
            $display("FAILURE: Display not enabled or not in Tilemap Mode. SCREEN_CTRL_REG: %02X (Expected $03).", u_fc8_system.u_sfr_block.screen_ctrl_reg_internal);
        end

        // Check Tilemap Definition RAM content (via hierarchical path for simplicity)
        // Tile (0,0) -> TileID 1, Palette 0
        if (u_fc8_system.u_sfr_block.tilemap_def_ram[0] == 8'h01 && u_fc8_system.u_sfr_block.tilemap_def_ram[1] == 8'h00) begin
            $display("SUCCESS: Tilemap Def RAM for tile (0,0) is TileID=1, Attr=0.");
        end else begin
            $display("FAILURE: Tilemap Def RAM for tile (0,0) is TileID=%02X (exp 01), Attr=%02X (exp 00).",
                     u_fc8_system.u_sfr_block.tilemap_def_ram[0], u_fc8_system.u_sfr_block.tilemap_def_ram[1]);
        end
        // Tile (1,0) -> TileID 2, Palette 1, FlipX
        if (u_fc8_system.u_sfr_block.tilemap_def_ram[2] == 8'h02 && u_fc8_system.u_sfr_block.tilemap_def_ram[3] == 8'h81) begin
            $display("SUCCESS: Tilemap Def RAM for tile (1,0) is TileID=2, Attr=$81 (Pal1, FlipX).");
        end else begin
            $display("FAILURE: Tilemap Def RAM for tile (1,0) is TileID=%02X (exp 02), Attr=%02X (exp $81).",
                     u_fc8_system.u_sfr_block.tilemap_def_ram[2], u_fc8_system.u_sfr_block.tilemap_def_ram[3]);
        end

        // Check some VRAM Tile Pattern data (via hierarchical path)
        // Tile 2, first byte (solid color index 3, stored as $03)
        localparam TILE2_PATTERN_VRAM_START_ADDR = `VRAM_TILE_PATTERN_BASE_ADDR + (`BYTES_PER_TILE_PATTERN * 2); // VRAM address for Tile 2 pattern
        if (u_fc8_system.u_vram.mem[TILE2_PATTERN_VRAM_START_ADDR] == 8'h03) begin
            $display("SUCCESS: VRAM pattern data for Tile 2, first byte is $03.");
        end else begin
            $display("FAILURE: VRAM pattern data for Tile 2, first byte is %02X (Expected $03).", u_fc8_system.u_vram.mem[TILE2_PATTERN_VRAM_START_ADDR]);
        end

        // Check Palette RAM
        if (u_fc8_system.u_graphics.palette_ram[16'h01] == 8'hE7 &&
            u_fc8_system.u_graphics.palette_ram[16'h11] == 8'hC0 &&
            u_fc8_system.u_graphics.palette_ram[16'h13] == 8'h03) begin
            $display("SUCCESS: Key palette entries set correctly: $01=%02X, $11=%02X, $13=%02X",
                u_fc8_system.u_graphics.palette_ram[16'h01],
                u_fc8_system.u_graphics.palette_ram[16'h11],
                u_fc8_system.u_graphics.palette_ram[16'h13]);
        end else begin
            $display("FAILURE: Palette entries incorrect.");
        end

        $finish;
    end

endmodule
