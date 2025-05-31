// FCVM/tb_fc8_system_interrupt_test.v
`include "fc8_defines.v"

module tb_fc8_system_interrupt_test;

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

    // Test Sequence
    initial begin
        master_rst_n = 1'b0; // Assert reset
        #200; // Hold reset for a bit
        master_rst_n = 1'b1; // De-assert reset

        // Monitor signals
        $display("Time PC Opcode A X Y SP NVBDIZC IRQ NMI RAM0010 RAM0011 INT_EN INT_STAT CPU_I_FLAG");
        $monitor("%6dns %04X %02X    %02X %02X %02X %04X %b%b%b%b%b%b%b%b  %b   %b   %02X      %02X      %02X     %02X       %b",
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
                 u_fc8_system.cpu_irq_req, // IRQ line to CPU
                 u_fc8_system.cpu_nmi_req, // NMI line to CPU
                 u_fc8_system.u_fixed_ram.mem[16'h0010], // NMI counter
                 u_fc8_system.u_fixed_ram.mem[16'h0011], // IRQ counter
                 u_fc8_system.u_sfr_block.int_enable_reg_internal, // INT_ENABLE_REG content
                 u_fc8_system.u_sfr_block.int_status_reg_internal, // INT_STATUS_REG content
                 u_fc8_system.u_cpu.f[`I_FLAG_BIT] // CPU's I flag
        );

        // Run for a duration sufficient to observe multiple interrupts
        // Timer with prescaler 0 on a 20MHz CPU clock will overflow very fast.
        // Timer clock = 20MHz / (2^0) = 20MHz. Overflow every 256 * 50ns = 12.8 us.
        // VBLANK NMI occurs once per frame. Frame time is approx 17ms (from graphics test).
        // Let's run for ~50ms to see a few VBLANKs and many timer IRQs.
        #50_000_000; // 50 ms

        // Verification
        $display("\n--- Interrupt Test Verification ---");
        if (u_fc8_system.u_fixed_ram.mem[16'h0010] > 2) begin // Check if NMI handler ran multiple times
            $display("SUCCESS: NMI counter (RAM[0010]) is %d, indicates multiple VBLANK NMIs handled.", u_fc8_system.u_fixed_ram.mem[16'h0010]);
        end else begin
            $display("FAILURE: NMI counter (RAM[0010]) is %d. Expected > 2.", u_fc8_system.u_fixed_ram.mem[16'h0010]);
        end

        if (u_fc8_system.u_fixed_ram.mem[16'h0011] > 10) begin // Check if IRQ handler ran multiple times
            $display("SUCCESS: Timer IRQ counter (RAM[0011]) is %d, indicates multiple Timer IRQs handled.", u_fc8_system.u_fixed_ram.mem[16'h0011]);
        end else begin
            $display("FAILURE: Timer IRQ counter (RAM[0011]) is %d. Expected > 10.", u_fc8_system.u_fixed_ram.mem[16'h0011]);
        end

        // Check if I flag was mostly 0 in main loop (after CLI) and 1 in handlers (implicitly by RTI restoring it)
        // This is harder to check with a single final value. Waveform is better.
        // We can check current I flag. If in main loop, should be 0.
        // This check is weak as it depends on where simulation stops.
        // $display("INFO: Final CPU I-flag: %b", u_fc8_system.u_cpu.f[`I_FLAG_BIT]);

        $finish;
    end

endmodule
