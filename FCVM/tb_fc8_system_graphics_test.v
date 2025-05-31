// FCVM/tb_fc8_system_graphics_test.v
`include "fc8_defines.v"

module tb_fc8_system_graphics_test;

    // Clock and Reset
    reg master_clk;
    reg master_rst_n;

    // VGA Signals from fc8_system (if exposed)
    // For now, we'll use hierarchical paths to observe them if not directly output by fc8_system
    wire vga_hsync_tb;
    wire vga_vsync_tb;
    wire [2:0] vga_r_tb;
    wire [2:0] vga_g_tb;
    wire [1:0] vga_b_tb;

    // Instantiate fc8_system
    // Expose VGA signals if fc8_system is modified to output them
    /*
    fc8_system u_fc8_system (
        .master_clk(master_clk),
        .master_rst_n(master_rst_n),
        .vga_hsync_out(vga_hsync_tb),
        .vga_vsync_out(vga_vsync_tb),
        .vga_r_out(vga_r_tb),
        .vga_g_out(vga_g_tb),
        .vga_b_out(vga_b_tb)
    );
    */
    // For now, assuming fc8_system does not output VGA directly, use hierarchical paths.
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
        #100; // Hold reset for a bit (a few master clock cycles)
        master_rst_n = 1'b1; // De-assert reset

        // Monitor signals
        $display("Time PC Opcode A X Y SP NVBDIZC PSR_RAM PSR_MMU VRAM_Addr VRAM_Din VRAM_Dout VRAM_WR VRAM_CS RAM[0] RAM[1] HSync VSync R G B");
        $monitor("%4dns %04X %02X %02X %02X %02X %04X %b%b%b%b%b%b%b%b %02X %02X %04X %02X %02X %b %b %02X %02X %b %b %1d%1d%1d",
                 $time,
                 u_fc8_system.u_cpu.pc,
                 u_fc8_system.u_cpu.opcode,
                 u_fc8_system.u_cpu.a,
                 u_fc8_system.u_cpu.x,
                 u_fc8_system.u_cpu.y,
                 u_fc8_system.u_cpu.sp,
                 u_fc8_system.u_cpu.f[`N_FLAG_BIT], u_fc8_system.u_cpu.f[`V_FLAG_BIT], u_fc8_system.u_cpu.f[5], u_fc8_system.u_cpu.f[`B_FLAG_BIT],
                 u_fc8_system.u_cpu.f[`D_FLAG_BIT], u_fc8_system.u_cpu.f[`I_FLAG_BIT], u_fc8_system.u_cpu.f[`Z_FLAG_BIT], u_fc8_system.u_cpu.f[`C_FLAG_BIT],
                 u_fc8_system.u_fixed_ram.mem[`PAGE_SELECT_REG_ADDR], // PAGE_SELECT_REG in RAM
                 u_fc8_system.u_mmu.page_select_reg_internal,      // MMU's internal copy
                 u_fc8_system.mmu_vram_addr_out,                 // Address to VRAM from MMU (CPU port)
                 u_fc8_system.mmu_vram_data_to_vram,             // Data to VRAM from MMU (CPU port)
                 u_fc8_system.vram_data_to_mmu,                  // Data from VRAM to MMU (CPU port)
                 u_fc8_system.mmu_vram_wr_en_out,                // Write enable to VRAM (CPU port)
                 u_fc8_system.mmu_vram_cs_out,                   // Chip select to VRAM (CPU port)
                 u_fc8_system.u_fixed_ram.mem[16'h0000],
                 u_fc8_system.u_fixed_ram.mem[16'h0001],
                 u_fc8_system.u_graphics.vga_hsync, // Hierarchical path
                 u_fc8_system.u_graphics.vga_vsync, // Hierarchical path
                 u_fc8_system.u_graphics.vga_r,     // Hierarchical path
                 u_fc8_system.u_graphics.vga_g,     // Hierarchical path
                 u_fc8_system.u_graphics.vga_b      // Hierarchical path
        );

        // Run for enough time to see multiple frames and CPU operations
        // One frame is H_TOTAL_PIXELS * V_TOTAL_LINES * pixel_clk_period
        // = 341 * 262 * 200ns = 17856400 ns = 17.8564 ms
        // Let's run for ~3 frames => ~54ms
        #54000000; // 54 ms in ns

        // Verification (basic checks, visual inspection in waveform viewer is key for graphics)
        $display("\n--- Graphics Test Verification ---");

        // Check if display was enabled (SCREEN_CTRL_REG bit 0)
        if (u_fc8_system.u_sfr_block.screen_ctrl_reg[0] == 1'b1) begin
            $display("SUCCESS: Display was enabled via SCREEN_CTRL_REG.");
        end else begin
            $display("FAILURE: Display was NOT enabled via SCREEN_CTRL_REG. Value: %b", u_fc8_system.u_sfr_block.screen_ctrl_reg[0]);
        end

        // Check palette RAM values (via hierarchical path)
        if (u_fc8_system.u_graphics.palette_ram[1] == 8'hE0 && u_fc8_system.u_graphics.palette_ram[2] == 8'h24) {
            $display("SUCCESS: Palette RAM entries 1 ($%02X) and 2 ($%02X) set correctly.",
                     u_fc8_system.u_graphics.palette_ram[1], u_fc8_system.u_graphics.palette_ram[2]);
        } else {
            $display("FAILURE: Palette RAM entries incorrect. RAM[1]=$%02X (exp $E0), RAM[2]=$%02X (exp $24).",
                     u_fc8_system.u_graphics.palette_ram[1], u_fc8_system.u_graphics.palette_ram[2]);
        }

        // Check VRAM values (via hierarchical path, from CPU perspective after writes)
        // The ROM program writes index 1 to VRAM $0000 and index 2 to VRAM $0001
        if (u_fc8_system.u_vram.mem[16'h0000] == 8'h01 && u_fc8_system.u_vram.mem[16'h0001] == 8'h02) {
            $display("SUCCESS: VRAM locations $0000 ($%02X) and $0001 ($%02X) written correctly by CPU.",
                u_fc8_system.u_vram.mem[16'h0000], u_fc8_system.u_vram.mem[16'h0001]);
        } else {
            $display("FAILURE: VRAM locations incorrect. VRAM[$0000]=$%02X (exp $01), VRAM[$0001]=$%02X (exp $02).",
                u_fc8_system.u_vram.mem[16'h0000], u_fc8_system.u_vram.mem[16'h0001]);
        }

        // Further checks could involve sampling VGA signals at specific times,
        // but this quickly becomes complex and is best done with a waveform viewer
        // or a more sophisticated image dumping testbench.

        $finish;
    end

endmodule
