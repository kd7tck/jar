// FCVM/tb_fc8_cpu_minimal.v
`include "fc8_defines.v"

module tb_fc8_cpu_minimal;

    // Clock and Reset
    reg clk;
    reg rst_n;

    // CPU Interface Wires
    wire [15:0] mem_addr_out_cpu;
    wire [7:0]  mem_data_out_cpu;
    wire        mem_rd_en_cpu;
    wire        mem_wr_en_cpu;
    reg  [7:0]  mem_data_in_cpu; // To CPU from RAM

    // RAM instance (e.g., 1KB for testing)
    localparam RAM_ADDR_WIDTH = 10; // 2^10 = 1024 locations (1KB)
    localparam RAM_SIZE = 1 << RAM_ADDR_WIDTH;
    reg [7:0] test_ram [0:RAM_SIZE-1];

    // Instantiate CPU
    fc8_cpu u_cpu (
        .clk(clk),
        .rst_n(rst_n),
        .mem_data_in(mem_data_in_cpu),
        .mem_addr_out(mem_addr_out_cpu),
        .mem_data_out(mem_data_out_cpu),
        .mem_rd_en(mem_rd_en_cpu),
        .mem_wr_en(mem_wr_en_cpu),
        .irq_n(1'b1), // Tie off interrupts
        .nmi_n(1'b1)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10ns period (100MHz)
    end

    // RAM model (synchronous write, asynchronous read for simplicity in TB)
    always @(posedge clk) begin
        if (mem_wr_en_cpu && mem_addr_out_cpu < RAM_SIZE) begin
            test_ram[mem_addr_out_cpu] <= mem_data_out_cpu;
        end
    end
    // Asynchronous read for CPU
    always @* begin
        if (mem_rd_en_cpu && mem_addr_out_cpu < RAM_SIZE) begin
            mem_data_in_cpu = test_ram[mem_addr_out_cpu];
        end else begin
            mem_data_in_cpu = 8'hZZ; // High-impedance if not reading RAM
        end
    end


    // Test Sequence
    initial begin
        // 1. Initialize RAM and Reset CPU
        rst_n = 1'b0; // Assert reset
        for (integer i = 0; i < RAM_SIZE; i = i + 1) begin
            test_ram[i] = 8'h00;
        end

        // Load program into RAM. CPU starts fetching from $FFFC/$FFFD for reset vector.
        // We'll set PC to $0200 for this minimal test.
        // CPU's reset sequence fetches PC from $FFFC, $FFFD.
        // In this testbench, RAM is small (1KB), so map $FFFC/$FFFD to $0FFC/$0FFD.
        // RAM addresses $0000-$03FF.
        // Initial SP will be $0100.
        test_ram[16'h0FFC] = 16'h00; // Low byte of start address ($0200)
        test_ram[16'h0FFD] = 16'h02; // High byte of start address ($0200)
        // The CPU will read these and set its PC to $0200.

        // Program to load at $0200
        // Test original sequence first, then add stack tests
        // LDA #$C3       (A9 C3)     ; PC: 0200
        // STA $0020      (8D 20 00)  ; PC: 0202, Store at $0020 (away from stack area)
        // LDX #$AB       (A2 AB)     ; PC: 0205
        // ADC #$01       (69 01)     ; PC: 0207, A=$C4, N=1
        // CLC            (18)        ; PC: 0209
        // BCS +2         (B0 02)     ; PC: 020A, Branch not taken
        // LDA $0020      (AD 20 00)  ; PC: 020C, A=$C3
        // NOP            (EA)        ; PC: 020F

        // Stack Test Sequence (continues from above)
        // Current PC: $0210
        // LDA #$AA       (A9 AA)     ; PC: 0210
        // PHA            (48)        ; PC: 0212, RAM[0100]=$AA, SP=$0101
        // LDA #$BB       (A9 BB)     ; PC: 0213
        // PHA            (48)        ; PC: 0215, RAM[0101]=$BB, SP=$0102
        // LDA #$CC       (A9 CC)     ; PC: 0216, A=$CC (to verify PLA changes it)
        // PLA            (68)        ; PC: 0218, A=$BB, SP=$0101
        // PLA            (68)        ; PC: 0219, A=$AA, SP=$0100
        // SEC            (38)        ; PC: 021A, Set Carry for PHP
        // PHP            (08)        ; PC: 021B, RAM[0100]=Flags (with C=1, B=1, bit5=1), SP=$0101
        // CLC            (18)        ; PC: 021C, Clear Carry
        // PLP            (28)        ; PC: 021D, Flags restored (C=1), SP=$0100
        // NOP            (EA)        ; PC: 021E
        // JMP $021E      (4C 1E 02)  ; Loop at end PC: 021F

        // Program Memory Setup
        integer prog_ptr = 16'h0200;
        test_ram[prog_ptr] = `OP_LDA_IMM; prog_ptr++; // LDA #$C3
        test_ram[prog_ptr] = 8'hC3;       prog_ptr++;
        test_ram[prog_ptr] = `OP_STA_ABS; prog_ptr++; // STA $0020
        test_ram[prog_ptr] = 16'h20;      prog_ptr++; // ADL
        test_ram[prog_ptr] = 16'h00;      prog_ptr++; // ADH
        test_ram[prog_ptr] = `OP_LDX_IMM; prog_ptr++; // LDX #$AB
        test_ram[prog_ptr] = 8'hAB;       prog_ptr++;
        test_ram[prog_ptr] = `OP_ADC_IMM; prog_ptr++; // ADC #$01
        test_ram[prog_ptr] = 8'h01;       prog_ptr++;
        test_ram[prog_ptr] = `OP_CLC;     prog_ptr++; // CLC
        test_ram[prog_ptr] = `OP_BCS_REL; prog_ptr++; // BCS +2 (target: prog_ptr+2)
        test_ram[prog_ptr] = 8'h02;       prog_ptr++; // Relative offset
        test_ram[prog_ptr] = `OP_LDA_ABS; prog_ptr++; // LDA $0020
        test_ram[prog_ptr] = 16'h20;      prog_ptr++; // ADL
        test_ram[prog_ptr] = 16'h00;      prog_ptr++; // ADH
        test_ram[prog_ptr] = `OP_NOP;     prog_ptr++; // PC: 020F

        // Stack Test part starts at $0210
        test_ram[prog_ptr] = `OP_LDA_IMM; prog_ptr++; // LDA #$AA ; $0210
        test_ram[prog_ptr] = 8'hAA;       prog_ptr++;
        test_ram[prog_ptr] = `OP_PHA;     prog_ptr++; // PHA      ; $0212, RAM[0100]=$AA, SP becomes $0101
        test_ram[prog_ptr] = `OP_LDA_IMM; prog_ptr++; // LDA #$BB ; $0213
        test_ram[prog_ptr] = 8'hBB;       prog_ptr++;
        test_ram[prog_ptr] = `OP_PHA;     prog_ptr++; // PHA      ; $0215, RAM[0101]=$BB, SP becomes $0102
        test_ram[prog_ptr] = `OP_LDA_IMM; prog_ptr++; // LDA #$CC ; $0216, A=$CC
        test_ram[prog_ptr] = 8'hCC;       prog_ptr++;
        test_ram[prog_ptr] = `OP_PLA;     prog_ptr++; // PLA      ; $0218, A=$BB, SP becomes $0101
        test_ram[prog_ptr] = `OP_PLA;     prog_ptr++; // PLA      ; $0219, A=$AA, SP becomes $0100
        test_ram[prog_ptr] = `OP_SEC;     prog_ptr++; // SEC      ; $021A
        test_ram[prog_ptr] = `OP_PHP;     prog_ptr++; // PHP      ; $021B, RAM[0100]=Flags_C1, SP becomes $0101
        test_ram[prog_ptr] = `OP_CLC;     prog_ptr++; // CLC      ; $021C
        test_ram[prog_ptr] = `OP_PLP;     prog_ptr++; // PLP      ; $021D, Flags_C1 restored, SP becomes $0100
        test_ram[prog_ptr] = `OP_NOP;     prog_ptr++; // NOP      ; $021E
        test_ram[prog_ptr] = `OP_JMP_ABS; prog_ptr++; // JMP $021E
        test_ram[prog_ptr] = {prog_ptr}[7:0]-1; prog_ptr++; // ADL ($1E)
        test_ram[prog_ptr] = {prog_ptr}[15:8];prog_ptr++; // ADH ($02)

        // De-assert reset after a few cycles
        #20 rst_n = 1'b1;

        // Monitor signals - ensure SP is displayed correctly
        $display("Time   PC   Opcode  A  X  Y  SP    NV-BDIZC  MemAddr MemDataIn MemDataOut Rd Wr | RAM[0100] RAM[0101]");
        $monitor("%4dns %04X %02X    %02X %02X %02X %04X  %b%b%b%b%b%b%b%b  %04X    %02X      %02X       %b  %b | %02X      %02X",
                 $time, u_cpu.pc, u_cpu.opcode, u_cpu.a, u_cpu.x, u_cpu.y, u_cpu.sp,
                 u_cpu.f[`N_FLAG_BIT], u_cpu.f[`V_FLAG_BIT], u_cpu.f[5], u_cpu.f[`B_FLAG_BIT], // Display bit 5
                 u_cpu.f[`D_FLAG_BIT], u_cpu.f[`I_FLAG_BIT], u_cpu.f[`Z_FLAG_BIT], u_cpu.f[`C_FLAG_BIT],
                 mem_addr_out_cpu, mem_data_in_cpu, mem_data_out_cpu, mem_rd_en_cpu, mem_wr_en_cpu,
                 test_ram[16'h0100], test_ram[16'h0101]);

        // Run for a fixed duration - extended to cover stack tests
        #2000; // Run for 2000ns (200 cycles)

        // Check some values from the original test
        if (test_ram[16'h0020] == 8'hC3) begin // Adjusted STA address
            $display("SUCCESS: STA $0020 stored $C3 correctly.");
        end else begin
            $display("FAILURE: STA $0020 value is %02X, expected $C3.", test_ram[16'h0020]);
        end

        // Add specific checks for stack operations after sufficient time
        // These checks are illustrative; precise timing for checking CPU registers might be needed.
        // Checking RAM is more robust for now.
        #10 // Wait a bit more for last operations to settle if needed
        $display("--- Stack Test Verification ---");
        $display("Expected SP at end: $0100. Actual SP: %04X", u_cpu.sp);
        if (u_cpu.sp == 16'h0100) $display("SUCCESS: SP final value matches $0100.");
        else $display("FAILURE: SP final value is %04X, expected $0100.", u_cpu.sp);

        // Check final accumulator value after PLAs
        $display("Expected A at end of PLAs: $AA. Actual A: %02X", u_cpu.a);
         if (u_cpu.a == 8'hAA) $display("SUCCESS: Accumulator after PLAs matches $AA.");
        else $display("FAILURE: Accumulator after PLAs is %02X, expected $AA.", u_cpu.a);

        // Check final Carry flag after PLP
        $display("Expected Carry flag after PLP: 1. Actual C: %b", u_cpu.f[`C_FLAG_BIT]);
        if (u_cpu.f[`C_FLAG_BIT] == 1'b1) $display("SUCCESS: Carry flag after PLP is 1.");
        else $display("FAILURE: Carry flag after PLP is %b, expected 1.", u_cpu.f[`C_FLAG_BIT]);

        $finish;
    end

endmodule
