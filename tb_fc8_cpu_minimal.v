// Testbench for fc8_cpu (minimal with Phase 1 & 2 opcodes)
`include "FCVM/fc8_defines.v"
`timescale 1ns/1ps

module tb_fc8_cpu_minimal;

    // Inputs
    reg clk;
    reg rst_n;
    reg [7:0] mem_data_in;
    reg nmi_req_in;
    reg irq_req_in;

    // Outputs
    wire [15:0] mem_addr_out;
    wire [7:0]  mem_data_out;
    wire        mem_rd_en;
    wire        mem_wr_en;

    // Instantiate the Unit Under Test (UUT)
    fc8_cpu uut (
        .clk(clk),
        .rst_n(rst_n),
        .mem_data_in(mem_data_in),
        .mem_addr_out(mem_addr_out),
        .mem_data_out(mem_data_out),
        .mem_rd_en(mem_rd_en),
        .mem_wr_en(mem_wr_en),
        .nmi_req_in(nmi_req_in),
        .irq_req_in(irq_req_in)
    );

    // Simple Memory Model (Behavioral)
    reg [7:0] memory [0:65535];
    integer i;

    initial begin
        // Initialize memory to 0 or a known pattern
        for (i = 0; i < 65536; i = i + 1) begin
            memory[i] = 8'h00;
        end
    end

    // Memory read logic
    always @(posedge clk) begin
        if (mem_rd_en) begin
            mem_data_in <= memory[mem_addr_out];
        end
    end

    // Memory write logic
    always @(posedge clk) begin
        if (mem_wr_en) begin
            memory[mem_addr_out] <= mem_data_out;
        end
    end

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz
    end

    // Reset and initial stimulus
    initial begin
        rst_n = 0;
        nmi_req_in = 0;
        irq_req_in = 0;
        mem_data_in = 8'h00; // Default
        #20 rst_n = 1;

        // --- Test Scenarios ---
        // These are placeholders. Full tests require loading programs into memory,
        // controlling inputs cycle by cycle, and checking outputs/CPU state.

        // Example: Load a NOP and check PC increment
        memory[`CPU_DEFAULT_ENTRY_POINT] = `OP_NOP;
        #20; // Let CPU fetch and execute NOP
        // Add checks for PC, registers, flags here

        // --- II. CPU Test Scenarios ---
        // For each scenario:
        // 1. Load program/data into 'memory' array.
        // 2. Set initial CPU state if possible (e.g. by forcing regs in testbench, or through instructions).
        // 3. Run for enough cycles.
        // 4. Check PC, SP, A, X, Y, F registers, and relevant memory locations.

        // 1. JSR/RTS Test
        //    - Program: JSR SUB_ADDR; NOP; ... SUB_ADDR: RTS
        //    - Verify: PC behavior, return address on stack, SP changes.
        /*
        $display("---- CPU TEST: JSR/RTS ----");
        memory[`CPU_DEFAULT_ENTRY_POINT + 0] = `OP_JSR_ABS;
        memory[`CPU_DEFAULT_ENTRY_POINT + 1] = 8'h0A; // ADL of subroutine (e.g., $800A)
        memory[`CPU_DEFAULT_ENTRY_POINT + 2] = 8'h80; // ADH
        memory[`CPU_DEFAULT_ENTRY_POINT + 3] = `OP_NOP; // Should return here (PC = $8003 after JSR setup)
        // ...
        memory[16'h800A] = `OP_RTS_IMP;
        // Run, then check PC, SP, stack contents.
        */

        // 2. Transfer Instructions (TAX, TAY, TSX, TXA, TXS, TYA)
        //    - Load A,X,Y,SP. Execute transfer. Verify dest reg, N,Z flags (except TXS).
        /*
        $display("---- CPU TEST: Transfer Instructions ----");
        // Example for TAX:
        // memory[PC] = `OP_LDA_IMM; memory[PC+1] = #VAL_A; // Load A
        // memory[PC+2] = `OP_LDX_IMM; memory[PC+3] = #VAL_X_Initial; // Load X
        // memory[PC+4] = `OP_TAX_IMP;
        // memory[PC+5] = `OP_NOP;
        // Run, then check X == VAL_A, N/Z flags based on VAL_A.
        */

        // 3. Stack Instructions (PHX, PHY, PLX, PLY)
        //    - PHX/PHY: Load X/Y, push, check stack & SP.
        //    - PLX/PLY: Push known, pull, check X/Y, SP, N,Z flags.
        /*
        $display("---- CPU TEST: PHX/PHY/PLX/PLY ----");
        */

        // 4. HLT Instruction
        //    - Execute HLT. Verify PC stops, no mem activity.
        //    - Assert IRQ (I=0): Verify wake, ISR, continue.
        //    - Assert NMI: Verify wake, ISR, continue.
        /*
        $display("---- CPU TEST: HLT ----");
        // memory[PC] = `OP_HLT_IMP;
        // memory[PC+1] = `OP_NOP; // Should not reach this until interrupt
        // Run, check PC. Then:
        // irq_req_in <= 1; // (ensure I flag in CPU is 0 via previous instruction like CLI)
        // Wait for ISR execution, then check PC moves to NOP.
        */

        // 5. Flag Register (F) Behavior (Reset, Push/Pop)
        //    - Check F after reset (should be $00 based on new spec).
        //    - PHP: Check stack value: {N,V,f[5], B=1, U=0, U=0, Z,C}.
        //    - PLP: Load stack, PLP, check F: N,V,f[5],Z,C restored; B,D,I become 0.
        //    - IRQ/NMI/BRK: Check pushed F on stack: {N,V,f[5], B_val, U=0, U=0, Z,C}.
        //    - RTI: Load stack, RTI, check F. (same as PLP for flags).
        /*
        $display("---- CPU TEST: Flag Register ----");
        // Reset value is implicitly tested at start if F can be read.
        // For PHP:
        // Setup F register with known pattern (e.g., via LDA #val, PHA, PLA, then some ops, then PHP)
        // Check value pushed to stack.
        */

        // 6. Memory Shift/Rotate (ASL, LSR, ROL, ROR zp/abs)
        //    - Write to mem. Execute op. Read mem. Check value, N,Z,C flags.
        /*
        $display("---- CPU TEST: Memory Shift/Rotate ----");
        // memory[ZP_ADDR] = #INITIAL_VAL;
        // memory[PC] = `OP_ASL_ZP; memory[PC+1] = ZP_ADDR;
        // Run. Check memory[ZP_ADDR], N,Z,C flags.
        */

        // 7. BIT (zp/abs)
        //    - Set A, mem. Execute BIT. Verify Z,N,V flags. A unchanged.
        /*
        $display("---- CPU TEST: BIT ----");
        // LDA #A_VAL
        // memory[ZP_ADDR] = #MEM_VAL
        // memory[PC] = `OP_BIT_ZP; memory[PC+1] = ZP_ADDR;
        // Run. Check Z,N,V flags. Check A.
        */

        // 8. JMP IND
        //    - Setup indirect ptr: ($0100) -> $CCDDFFEE -> target $1234.
        //    - JMP ($0100). Verify PC becomes $1234.
        /*
        $display("---- CPU TEST: JMP IND ----");
        memory[16'h0100] = 16'hEE; // LSB of pointer $FFEE
        memory[16'h0101] = 16'hFF; // MSB of pointer $FFEE
        memory[16'hFFEE] = 16'h34; // LSB of target $1234
        memory[16'hFFEF] = 16'h12; // MSB of target $1234
        // memory[PC] = `OP_JMP_IND; memory[PC+1] = 16'h00; memory[PC+2] = 16'h01; // JMP ($0100)
        // Run. Check PC.
        */

        #2000; // Run for a duration
        $display("Minimal CPU Testbench: Simulation Finished.");
        $finish;
    end

endmodule
