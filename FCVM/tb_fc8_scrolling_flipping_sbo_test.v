// FCVM/tb_fc8_scrolling_flipping_sbo_test.v
`include "fc8_defines.v"

module tb_fc8_scrolling_flipping_sbo_test;

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

        // Monitor signals
        $display("Time PC Opcode A X Y SP NVBDIZC PSR_MMU ScrollX ScrollY VRAMFlags SBO_Col SBO_Val HSync VSync R G B");
        $monitor("%6dns %04X %02X    %02X %02X %02X %04X %b%b%b%b%b%b%b%b  %02X      %02X      %02X      %02X        %02X      %02X     %b %b %1d%1d%1d",
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
                 u_fc8_system.u_sfr_block.sfr_scroll_x_out,
                 u_fc8_system.u_sfr_block.sfr_scroll_y_out,
                 u_fc8_system.u_sfr_block.sfr_vram_flags_out,
                 u_fc8_system.u_graphics.current_screen_column_x_out, // Column X from graphics
                 u_fc8_system.u_sfr_block.sfr_sbo_offset_data_out,   // SBO value for that column
                 u_fc8_system.u_graphics.vga_hsync,
                 u_fc8_system.u_graphics.vga_vsync,
                 u_fc8_system.u_graphics.vga_r,
                 u_fc8_system.u_graphics.vga_g,
                 u_fc8_system.u_graphics.vga_b
        );

        // Run for enough time to see scrolling and other effects
        // One frame is approx 17.8ms. To see scroll_x increment a few times.
        // Scroll X increments roughly every (255 DEY loops * ~2 cycles/DEY) * CPU_clk_period
        // If CPU is 20MHz (50ns), one scroll increment is ~255*2*50ns = ~25.5us.
        // To see it scroll 10 pixels: ~255us.
        // Let's run for a few frames, e.g., 100ms.
        #100_000_000; // 100 ms

        // Verification
        $display("\n--- Scrolling/Flipping/SBO Test Verification ---");

        // Check if display was enabled
        if (u_fc8_system.u_sfr_block.sfr_display_enable_out == 1'b1) begin
            $display("SUCCESS: Display was enabled.");
        end else begin
            $display("FAILURE: Display was NOT enabled. SCREEN_CTRL_REG: %02X", u_fc8_system.u_sfr_block.screen_ctrl_reg_internal);
        end

        // Check initial VRAM values written by CPU
        if (u_fc8_system.u_vram.mem[16'h0000] == 8'h01 &&
            u_fc8_system.u_vram.mem[16'h0001] == 8'h02 &&
            u_fc8_system.u_vram.mem[16'h0100] == 8'h03) begin
            $display("SUCCESS: Initial VRAM values written correctly: $0000=%02X, $0001=%02X, $0100=%02X",
                u_fc8_system.u_vram.mem[16'h0000], u_fc8_system.u_vram.mem[16'h0001], u_fc8_system.u_vram.mem[16'h0100]);
        end else begin
            $display("FAILURE: Initial VRAM values incorrect. $0000=%02X (exp $01), $0001=%02X (exp $02), $0100=%02X (exp $03)",
                u_fc8_system.u_vram.mem[16'h0000], u_fc8_system.u_vram.mem[16'h0001], u_fc8_system.u_vram.mem[16'h0100]);
        end

        // Check SBO values written by CPU
        if (u_fc8_system.u_sfr_block.screen_bounds[5] == 8'h0A &&
            u_fc8_system.u_sfr_block.screen_bounds[10] == 8'h14) begin
            $display("SUCCESS: SBO registers for column 5 ($%02X) and 10 ($%02X) set correctly.",
                u_fc8_system.u_sfr_block.screen_bounds[5], u_fc8_system.u_sfr_block.screen_bounds[10]);
        end else begin
            $display("FAILURE: SBO registers incorrect. Col 5 = %02X (exp $0A), Col 10 = %02X (exp $14).",
                 u_fc8_system.u_sfr_block.screen_bounds[5], u_fc8_system.u_sfr_block.screen_bounds[10]);
        end

        // Check if ScrollX has changed from its initial value of 0
        if (u_fc8_system.u_sfr_block.sfr_scroll_x_out != 8'h00) begin
            $display("SUCCESS: VRAM_SCROLL_X_REG has been updated from $00 to $%02X, indicating scrolling loop ran.", u_fc8_system.u_sfr_block.sfr_scroll_x_out);
        end else begin
            $display("FAILURE: VRAM_SCROLL_X_REG is still $00. Scrolling loop may not have run as expected.");
        end

        // Further verification would involve checking VRAM contents against expected patterns
        // after scrolling/flipping, or dumping VGA output to an image file.
        // For now, visual inspection of waveforms for HSYNC, VSYNC, and pixel data is key.

        $finish;
    end

endmodule
