`timescale 1ns / 1ps

module fc8_testbench;

    // Signal Declarations
    reg clk_20mhz;
    reg rst_n;
    reg [7:0] cart_rom_data_tb;
    reg raw_joy_up_tb;
    reg raw_joy_down_tb;
    reg raw_joy_left_tb;
    reg raw_joy_right_tb;
    reg raw_button_a_tb;
    reg raw_button_b_tb;

    wire [7:0] vga_rgb_tb;
    wire vga_hsync_tb;
    wire vga_vsync_tb;
    wire [7:0] audio_pwm_out_tb;

    // Instantiate fc8_top (Device Under Test)
    fc8_top dut (
        .clk_20mhz(clk_20mhz),
        .rst_n(rst_n),
        
        .raw_joy_up(raw_joy_up_tb),
        .raw_joy_down(raw_joy_down_tb),
        .raw_joy_left(raw_joy_left_tb),
        .raw_joy_right(raw_joy_right_tb),
        .raw_button_a(raw_button_a_tb),
        .raw_button_b(raw_button_b_tb),
        
        .cart_rom_data(cart_rom_data_tb),
        
        .vga_rgb(vga_rgb_tb),
        .vga_hsync(vga_hsync_tb),
        .vga_vsync(vga_vsync_tb),
        
        .audio_pwm_out(audio_pwm_out_tb)
    );

    // Clock Generation (20MHz -> 50ns period)
    initial clk_20mhz = 0;
    always #25 clk_20mhz = ~clk_20mhz;

    // ROM Content
    reg [7:0] test_program_rom [0:255];
    integer i;

    // Drive ROM data based on CPU address
    // dut.cpu_addr is the logical address from the CPU instance within fc8_top
    // This assumes fc8_top exposes cpu_addr or it can be accessed hierarchically.
    // In TOPLEVEL.v, fc8_cpu instance `cpu` has output `addr(cpu_addr)`.
    // This cpu_addr wire is top-level within fc8_top.
    assign cart_rom_data_tb = (dut.cpu_addr >= 16'h8000 && dut.cpu_addr < 16'h8100) ? 
                              test_program_rom[dut.cpu_addr - 16'h8000] : 
                              8'hEA; // Default to NOP if outside defined 256-byte test ROM

    // Reset Generation and Initialization
    initial begin
        // Initialize inputs
        rst_n = 1'b0; // Assert reset
        cart_rom_data_tb = 8'hEA; // Default ROM data during reset
        raw_joy_up_tb = 0;
        raw_joy_down_tb = 0;
        raw_joy_left_tb = 0;
        raw_joy_right_tb = 0;
        raw_button_a_tb = 0;
        raw_button_b_tb = 0;

        // Initialize ROM contents
        for (i = 0; i < 256; i = i + 1) begin
            test_program_rom[i] = 8'hEA; // Fill with NOPs
        end

        // Simple Test Program (CPU PC starts at 16'h8000)
        // Program: Set PageSelectReg, Write Color to VRAM, Loop
        // ROM Address | CPU Address | Mnemonic    | Hex
        // ------------|-------------|-------------|--------
        // 0x00        | 0x8000      | LDA #$01    | A9 01
        // 0x02        | 0x8002      | STA $00FE   | 8D FE 00
        // 0x05        | 0x8005      | LDA #$0F    | A9 0F
        // 0x07        | 0x8007      | STA $8000   | 8D 00 80  (Logical $8000, now VRAM)
        // 0x0A        | 0x800A      | JMP $800A   | 4C 0A 80
        
        test_program_rom[0] = 8'hA9; // LDA_IMM
        test_program_rom[1] = 8'h01; // Page value for VRAM (e.g., bank 01 for phys_addr[19:15])
        test_program_rom[2] = 8'h8D; // STA_ABS
        test_program_rom[3] = 8'hFE; // PAGE_SELECT_REG low byte ($00FE)
        test_program_rom[4] = 8'h00; // PAGE_SELECT_REG high byte
        
        test_program_rom[5] = 8'hA9; // LDA_IMM
        test_program_rom[6] = 8'h0F; // Color index 15 (e.g., Light Green from palette)
        test_program_rom[7] = 8'h8D; // STA_ABS
        test_program_rom[8] = 8'h00; // VRAM address low byte (for logical $8000)
        test_program_rom[9] = 8'h80; // VRAM address high byte (for logical $8000)
        
        test_program_rom[10] = 8'h4C; // JMP_ABS
        test_program_rom[11] = 8'h0A; // Jump target low byte ($800A)
        test_program_rom[12] = 8'h80; // Jump target high byte ($800A)

        // De-assert reset after some time
        #100;
        rst_n = 1'b1;
    end

    // Simulation Control
    initial begin
        #20000; // Run for 20,000 ns (20 us)
        $display("Simulation finished at %t ns", $time);
        $finish;
    end

    initial begin
        $dumpfile("fc8_testbench.vcd");
        $dumpvars(0, fc8_testbench);
        // To dump signals inside DUT: $dumpvars(0, fc8_testbench.dut);
        // To dump signals inside CPU in DUT: $dumpvars(0, fc8_testbench.dut.cpu);
    end

endmodule
