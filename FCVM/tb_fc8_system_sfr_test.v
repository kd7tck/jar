// FCVM/tb_fc8_system_sfr_test.v
`include "fc8_defines.v"

module tb_fc8_system_sfr_test;

    // Clock and Reset
    reg master_clk;
    reg master_rst_n;

    // Instantiate fc8_system
    fc8_system u_fc8_system (
        .master_clk(master_clk),
        .master_rst_n(master_rst_n)
        // No outputs from system needed for this test yet
    );

    // Clock generation
    initial begin
        master_clk = 0;
        forever #5 master_clk = ~master_clk; // 10ns period (100MHz)
    end

    // Test Sequence
    initial begin
        master_rst_n = 1'b0; // Assert reset
        #20; // Hold reset for a bit
        master_rst_n = 1'b1; // De-assert reset

        // Monitor signals
        // Access internal signals for monitoring. This requires simulator support for hierarchical names.
        $display("Time PC Opcode A X Y SP NVBDIZC PSR_RAM PSR_MMU SFR_Addr SFR_Din SFR_Dout SFR_WR SFR_CS RAM0 RAM1 RAM2 RAM3");
        $monitor("%4dns %04X %02X %02X %02X %02X %04X %b%b%b%b%b%b%b%b %02X %02X %04X %02X %02X %b %b %02X %02X %02X %02X",
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
                 u_fc8_system.mmu_sfr_addr_out,                  // Address to SFR block from MMU
                 u_fc8_system.mmu_sfr_data_to_sfr_block,         // Data to SFR block from MMU
                 u_fc8_system.sfr_block_data_to_mmu,             // Data from SFR block to MMU
                 u_fc8_system.mmu_sfr_wr_en_out,                 // Write enable to SFR
                 u_fc8_system.mmu_sfr_cs_out,                    // Chip select to SFR
                 u_fc8_system.u_fixed_ram.mem[16'h0000], // RAM[0] for VRAM_SCROLL_X_REG check
                 u_fc8_system.u_fixed_ram.mem[16'h0001], // RAM[1] for INPUT_STATUS_REG check
                 u_fc8_system.u_fixed_ram.mem[16'h0002], // RAM[2] for INT_STATUS_REG first read
                 u_fc8_system.u_fixed_ram.mem[16'h0003]  // RAM[3] for INT_STATUS_REG second read
        );

        // Run for a fixed duration - enough to execute the ROM program sequence
        #3000; // Increased duration for more SFR operations

        // Verification
        $display("\n--- SFR Test Verification ---");

        // 1. PAGE_SELECT_REG was set to 4
        if (u_fc8_system.u_fixed_ram.mem[`PAGE_SELECT_REG_ADDR] == 8'h04 &&
            u_fc8_system.u_mmu.page_select_reg_internal == 8'h04) begin
            $display("SUCCESS: PAGE_SELECT_REG written to $04 and MMU internal copy updated.");
        end else begin
            $display("FAILURE: PAGE_SELECT_REG RAM value: %02X, MMU internal: %02X. Expected $04 for both.",
                     u_fc8_system.u_fixed_ram.mem[`PAGE_SELECT_REG_ADDR], u_fc8_system.u_mmu.page_select_reg_internal);
        end

        // 2. VRAM_SCROLL_X_REG write and readback
        // Check RAM[0] which should hold the value read back from VRAM_SCROLL_X_REG
        // And also check the internal SFR register if directly accessible (e.g. u_fc8_system.u_sfr_block.vram_scroll_x_reg)
        // For now, we check RAM content written by the test program.
        if (u_fc8_system.u_fixed_ram.mem[16'h0000] == 8'hA5) begin
            $display("SUCCESS: VRAM_SCROLL_X_REG write ($A5) and readback to RAM[0] correct.");
        // Optional: Direct check if SFR internal is accessible
        // $display("INFO: SFR VRAM_SCROLL_X_REG internal value: %02X", u_fc8_system.u_sfr_block.vram_scroll_x_reg);
        end else begin
            $display("FAILURE: RAM[0] value is %02X, expected $A5 (from VRAM_SCROLL_X_REG readback).",
                     u_fc8_system.u_fixed_ram.mem[16'h0000]);
        end

        // 3. INPUT_STATUS_REG read
        // Default value in sfr_block is 8'b00000001 (GP1 connected)
        if (u_fc8_system.u_fixed_ram.mem[16'h0001] == 8'h01) begin
            $display("SUCCESS: INPUT_STATUS_REG readback to RAM[1] correct ($01).");
        end else begin
            $display("FAILURE: RAM[1] value is %02X, expected $01 (from INPUT_STATUS_REG readback).",
                     u_fc8_system.u_fixed_ram.mem[16'h0001]);
        end

        // 4. INT_STATUS_REG W1C test
        if (u_fc8_system.u_fixed_ram.mem[16'h0002] == 8'h03) begin
            $display("SUCCESS: INT_STATUS_REG first readback to RAM[2] correct ($03).");
        end else begin
            $display("FAILURE: RAM[2] value is %02X, expected $03 (from INT_STATUS_REG first readback).",
                     u_fc8_system.u_fixed_ram.mem[16'h0002]);
        end
        // After writing $01 to clear bit 0, bit 1 should remain, so value should be $02
        if (u_fc8_system.u_fixed_ram.mem[16'h0003] == 8'h02) begin
            $display("SUCCESS: INT_STATUS_REG second readback to RAM[3] correct ($02 after W1C).");
        end else begin
            $display("FAILURE: RAM[3] value is %02X, expected $02 (from INT_STATUS_REG second readback after W1C).",
                     u_fc8_system.u_fixed_ram.mem[16'h0003]);
        end

        // 5. PALETTE_ADDR_REG and PALETTE_DATA_REG
        // We can't directly read PALETTE_ADDR_REG from CPU.
        // We can check the internal palette_addr_reg in the SFR block via hierarchical path.
        // Expected: Initial write $10. Then two data writes, so $10 -> $11 -> $12.
        if (u_fc8_system.u_sfr_block.palette_addr_reg == 8'h12) begin
             $display("SUCCESS: PALETTE_ADDR_REG internal value is $12 after two data writes.");
        end else begin
             $display("FAILURE: PALETTE_ADDR_REG internal value is %02X, expected $12.", u_fc8_system.u_sfr_block.palette_addr_reg);
        end
        // Check palette RAM content (e.g., at addr $10 and $11)
        if (u_fc8_system.u_sfr_block.palette_ram[8'h10] == 8'hE0 && u_fc8_system.u_sfr_block.palette_ram[8'h11] == 8'hC3) begin
            $display("SUCCESS: Palette RAM values at $10 (%02X) and $11 (%02X) correct.",
                     u_fc8_system.u_sfr_block.palette_ram[8'h10], u_fc8_system.u_sfr_block.palette_ram[8'h11]);
        end else begin
            $display("FAILURE: Palette RAM values incorrect. RAM[$10]=%02X (exp $E0), RAM[$11]=%02X (exp $C3).",
                     u_fc8_system.u_sfr_block.palette_ram[8'h10], u_fc8_system.u_sfr_block.palette_ram[8'h11]);
        end

        $finish;
    end

endmodule
