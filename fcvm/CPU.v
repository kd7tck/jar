`timescale 1ns / 1ps

// FCVM CPU Core
// Implements the FCVm CPU instruction set and behavior
// as per the FCVm Specification (Section 5).

module fc8_cpu (
    input wire clk,
    input wire rst_n,           // Active-low reset
    output reg [15:0] addr,     // 16-bit address bus
    input wire [7:0] data_in,   // 8-bit data bus input
    output reg [7:0] data_out,  // 8-bit data bus output
    output reg we,              // Write enable (1 for write, 0 for read)
    
    input wire irq_n,           // Maskable Interrupt Request (active-low)
    input wire nmi_n            // Non-Maskable Interrupt (active-low)
);

    // --- CPU Registers (Section 5.1) ---
    reg [7:0] A;                // Accumulator
    reg [7:0] X, Y;             // Index Registers
    reg [15:0] SP;              // Stack Pointer (Hardware ops use $01xx)
    reg [15:0] PC;              // Program Counter
    
    // Flag Register (F) - N V I B D U Z C (U=Unused, B=BRK/IRQ, D=Decimal)
    // FCVm Spec: N V I - - - Z C (Bit 5 is I, Bit 4 for BRK/PHP is implicit)
    // For implementation:
    // Bit 7: N (Negative)
    // Bit 6: V (Overflow)
    // Bit 5: I (Interrupt Disable)
    // Bit 4: B (Break command - software flag, set when F is pushed by BRK/IRQ)
    // Bit 3: D (Decimal mode - NOP on FCVm, but flag exists for PHP/PLP)
    // Bit 2: U (Unused - can be placeholder, e.g. always 1 when pushed)
    // Bit 1: Z (Zero)
    // Bit 0: C (Carry)
    reg [7:0] F;

    // --- Internal CPU State & Temporary Registers ---
    reg [4:0] state;            // CPU state machine (expanded for more states)
    reg [7:0] opcode;           // Current instruction opcode
    reg [15:0] effective_addr;   // Calculated effective address
    reg [7:0] operand_lo;       // Low byte of operand/address fetched
    reg [7:0] operand_hi;       // High byte of operand/address fetched
    reg [7:0] fetched_data;     // Data fetched from memory (operand or for RMW)
    reg [8:0] alu_temp9;        // 9-bit temporary for ADC/SBC carry calculation, and BIT instruction
    reg [15:0] temp_addr;       // Temporary address for JMP (ind), branches or other calculations
    reg [2:0] cycle;            // Current cycle number for multi-cycle instructions (T0-T7 approx)
    
    reg nmi_edge_detected;      // Latched NMI signal (on falling edge)
    reg prev_nmi_n_state;       // Previous state of nmi_n for edge detection
    
    reg irq_sequence_active;    // True if IRQ sequence is active
    reg nmi_sequence_active;    // True if NMI sequence is active 
    reg brk_sequence_active;    // True if BRK sequence is active

    reg halted;                 // HLT instruction status

    // --- CPU States (expanded for clarity and cycle accuracy) ---
    localparam S_RESET_0       = 5'd0;  // Initial state, wait for rst_n to go high
    localparam S_RESET_1_SP    = 5'd1;  // Init SP
    localparam S_RESET_2_REGS  = 5'd2;  // Init A,X,Y,F
    localparam S_RESET_3_PCL   = 5'd3;  // Fetch PC Low from $FFFC (or $0000 for now)
    localparam S_RESET_4_PCH   = 5'd4;  // Fetch PC High from $FFFD, go to Opcode Fetch
    
    localparam S_FETCH_OP      = 5'd5;  // T0: Fetch opcode, PC++
    
    // Addressing mode states (examples, may be combined or expanded)
    localparam S_ADDR_IMM      = 5'd6;  // T1: Fetch immediate operand (LDA #$10) -> addr=PC, PC++
    localparam S_ADDR_ZP       = 5'd7;  // T1: Fetch ZP addr -> addr=PC, PC++
    localparam S_ADDR_ZPX      = 5'd8;  // T1: Fetch ZP addr -> addr=PC, PC++. T2: EffAddr = (ZP+X) % 256 (dummy read)
    localparam S_ADDR_ZPY      = 5'd9;  // T1: Fetch ZP addr -> addr=PC, PC++. T2: EffAddr = (ZP+Y) % 256 (dummy read) - for LDX, STX
    localparam S_ADDR_ABS      = 5'd10; // T1: Fetch ADL -> addr=PC, PC++. T2: Fetch ADH -> addr=PC, PC++
    localparam S_ADDR_ABSX     = 5'd11; // T1: Fetch ADL. T2: Fetch ADH. T3: EffAddr = ADDR+X (check page cross)
    localparam S_ADDR_ABSY     = 5'd12; // T1: Fetch ADL. T2: Fetch ADH. T3: EffAddr = ADDR+Y (check page cross)
    localparam S_ADDR_INDX     = 5'd13; // T1: Fetch ZP ptr. T2: ptr+X. T3: Read EffAddr_L. T4: Read EffAddr_H.
    localparam S_ADDR_INDY     = 5'd14; // T1: Fetch ZP ptr. T2: Read EffAddr_L. T3: Read EffAddr_H. T4: EffAddr+Y (check page cross)
    localparam S_ADDR_INDJMP   = 5'd15; // T1: Fetch Ptr_L. T2: Fetch Ptr_H. T3: Read JMP_L from (Ptr). T4: Read JMP_H from (Ptr+1, no page wrap for ptr+1)
    
    // Memory operation states
    localparam S_MEM_READ_OP   = 5'd16; // Read data from effective_addr (for LDA, ADC etc.)
    localparam S_MEM_WRITE_OP  = 5'd17; // Write data to effective_addr (for STA, STX etc.)
    localparam S_RMW_READ      = 5'd18; // Read data for RMW instructions (INC, DEC, ASL, LSR, ROL, ROR mem)
    localparam S_RMW_WRITE     = 5'd19; // Write modified data for RMW (after dummy write/ALU op)
    localparam S_RMW_MODIFY    = 5'd20; // Internal ALU operation for RMW (dummy write cycle)

    // Interrupt/BRK/RTI states
    localparam S_INT_0_CYCLE   = 5'd21; // Cycle 0/1 (internal, check if instruction completed)
    localparam S_INT_1_PUSH_PCH= 5'd22; // Cycle 2: Push PCH, SP--
    localparam S_INT_2_PUSH_PCL= 5'd23; // Cycle 3: Push PCL, SP--
    localparam S_INT_3_PUSH_F  = 5'd24; // Cycle 4: Push F (B set if BRK/IRQ), SP--, F[I]=1
    localparam S_INT_4_VEC_L   = 5'd25; // Cycle 5: Read Vector Low. Addr = $FFFA/B (NMI) or $FFFE/F (IRQ/BRK)
    localparam S_INT_5_VEC_H   = 5'd26; // Cycle 6: Read Vector High, PC_L <= fetched_data. Addr = vector + 1
                                        // Cycle 7: PC_H <= fetched_data. PC formed. Go to S_FETCH_OP.
    localparam S_RTI_PULL_F    = 5'd27; // RTI: Pull F
    localparam S_RTI_PULL_PCL  = 5'd28; // RTI: Pull PCL
    localparam S_RTI_PULL_PCH  = 5'd29; // RTI: Pull PCH, then S_FETCH_OP


    // --- Opcode Definitions (Section 5.10, abbreviated for brevity, full list in comments above) ---
    `include "fc8_opcodes.vh" // Assuming opcodes are in a separate file for clarity

    // --- Helper Tasks ---
    task set_nz; input [7:0] val; begin F[7]=val[7]; F[1]=(val==0); end endtask
    task set_nzc; input [7:0] val; input c_val; begin set_nz(val); F[0]=c_val; end endtask
    
    task do_adc; input [7:0] M; begin alu_temp9=A+M+F[0]; F[0]=alu_temp9[8]; F[6]=(~(A[7]^M[7]))&(A[7]^alu_temp9[7]); A=alu_temp9[7:0]; set_nz(A); end endtask
    task do_sbc; input [7:0] M; begin alu_temp9=A-M-(1-F[0]); F[0]=~alu_temp9[8];F[6]=(A[7]^M[7])&(A[7]^alu_temp9[7]); A=alu_temp9[7:0]; set_nz(A); end endtask
    
    task push_byte; input [7:0] val; begin addr={8'h01,SP}; data_out=val; we=1'b1; SP=SP-1; end endtask
    task pull_byte; begin SP=SP+1; addr={8'h01,SP}; we=1'b0; end endtask // Result in data_in next cycle


    // --- Main CPU Logic ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_RESET_0;
            halted <= 1'b0; 
            nmi_edge_detected <= 1'b0; 
            prev_nmi_n_state <= 1'b1;
            irq_sequence_active <= 1'b0; 
            nmi_sequence_active <= 1'b0;
            brk_sequence_active <= 1'b0;
        end else begin
            // NMI edge detection (latches on falling edge)
            if (!nmi_n && prev_nmi_n_state) nmi_edge_detected <= 1'b1;
            prev_nmi_n_state <= nmi_n;

            // Default outputs
            we <= 1'b0;
            // addr, data_out are state-dependent

            // --- Interrupt Pre-emption Check (before state dispatch) ---
            if (state != S_RESET_0 && state != S_RESET_1_SP && state != S_RESET_2_REGS && 
                state != S_RESET_3_PCL && state != S_RESET_4_PCH &&
                !irq_sequence_active && !nmi_sequence_active && !brk_sequence_active && !halted) begin // Not during reset or existing interrupt
                if (nmi_edge_detected) begin
                    nmi_edge_detected <= 1'b0; 
                    nmi_sequence_active <= 1'b1; 
                    state <= S_INT_0_CYCLE; cycle <= 0; // Start NMI sequence
                end else if (!irq_n && !F[5]) begin // IRQ line active and I-flag clear
                    irq_sequence_active <= 1'b1; 
                    state <= S_INT_0_CYCLE; cycle <= 0; // Start IRQ sequence
                end
            end
            
            // --- Halt Logic ---
            if (halted && !(nmi_sequence_active || irq_sequence_active)) begin // Remain halted unless NMI/IRQ active
                // Bus activity during HLT: FCVm spec "CPU stops executing instructions"
                // Usually means it might tristate buses or repeatedly fetch current PC.
                // For simplicity, let it go to fetch, but it will re-detect HLT if not woken.
                addr <= PC; // Keep PC on address bus
                state <= S_FETCH_OP; // Will re-evaluate HLT state
            end

            // --- Main State Machine ---
            case (state)
                S_RESET_0: if (rst_n) state <= S_RESET_1_SP; // Wait for reset release
                S_RESET_1_SP: begin SP <= 16'h0100; state <= S_RESET_2_REGS; end // Init SP
                S_RESET_2_REGS: begin // Init A,X,Y,F
                    A <= 8'h00; X <= 8'h00; Y <= 8'h00; 
                    F <= 8'b00100000; // I=1 (bit 5), others 0. (B implicitly 0, D implicitly 0)
                                      // Spec shows B and D as part of F register for PHP/PLP.
                                      // Initialize F with I=1. For PHP/PLP, B and D should be represented.
                                      // True 6502 F on reset: $34 (I=1, U=1, B=1). FCVm may differ.
                                      // For now, I=1, rest 0 as per subtask CPU reset.
                    state <= S_RESET_3_PCL;
                end
                S_RESET_3_PCL: begin // Load PC from $0000 (subtask specific)
                    PC <= 16'h0000;
                    state <= S_FETCH_OP; cycle <= 0; // Go to fetch first opcode
                end
                // S_RESET_4_PCH: would be if fetching from $FFFC/D

                S_FETCH_OP: begin // T0
                    addr <= PC; we <= 1'b0;
                    PC <= PC + 1;
                    cycle <= 1; // Start of instruction cycle count
                    state <= S_DECODE_EXEC;
                end

                S_DECODE_EXEC: begin
                    opcode <= data_in; // Opcode fetched in S_FETCH_OP
                    // This state is the main dispatcher for all opcodes.
                    // It will determine addressing mode, fetch further bytes if needed,
                    // perform operations, and manage 'cycle' counter.
                    // Due to extreme length, only a few examples are sketched here.
                    // Each instruction will have its own logic block within this state,
                    // potentially spanning multiple cycles using the 'cycle' register.

                    // --- Start of Opcode Dispatch (Massive Case Statement) ---
                    case (opcode)
                        // Examples (replace with full instruction set)
                        NOP: begin // 2 cycles total (T0=fetch, T1=decode/dummy)
                            if (cycle == 1) begin state <= S_FETCH_OP; cycle <= 0; end
                            // else: error or unexpected cycle
                        end
                        HLT: begin // 2 cycles (T0=fetch, T1=decode/halt)
                            if (cycle == 1) begin halted <= 1'b1; state <= S_FETCH_OP; cycle <= 0; end
                        end
                        
                        // LDA Immediate
                        LDA_IMM: begin
                            if (cycle == 1) begin // T1: Opcode done. This is T2: Fetch operand.
                                addr <= PC; PC <= PC + 1; we <= 1'b0;
                                cycle <= 2; // Next cycle is T3
                            end else if (cycle == 2) begin // T2 done (operand fetched). This is T3: Update A and flags.
                                A <= data_in; set_nz(A);
                                state <= S_FETCH_OP; cycle <= 0;
                            end
                        end

                        // STA Absolute (Example)
                        STA_ABS: begin
                            if (cycle == 1)      begin addr <= PC; PC <= PC + 1; we <= 1'b0; cycle <= 2; end // Fetch ADL
                            else if (cycle == 2) begin operand_lo <= data_in; addr <= PC; PC <= PC + 1; we <= 1'b0; cycle <= 3; end // Fetch ADH
                            else if (cycle == 3) begin // Store ADH, form address, write A
                                operand_hi <= data_in; effective_addr <= {operand_hi, operand_lo};
                                addr <= effective_addr; data_out <= A; we <= 1'b1;
                                cycle <= 4; // This is T4 (write cycle)
                            end else if (cycle == 4) begin // Write complete
                                state <= S_FETCH_OP; cycle <= 0;
                            end
                        end
                        
                        // JMP Absolute
                        JMP_ABS: begin
                            if (cycle == 1)      begin addr <= PC; PC <= PC + 1; we <= 1'b0; cycle <= 2; end // Fetch ADL
                            else if (cycle == 2) begin operand_lo <= data_in; addr <= PC; /*PC not inc'd here*/ we <= 1'b0; cycle <= 3; end // Fetch ADH
                            else if (cycle == 3) begin // Store ADH, form address, set PC
                                operand_hi <= data_in; PC <= {operand_hi, operand_lo};
                                state <= S_FETCH_OP; cycle <= 0; // JMP takes 3 cycles
                            end
                        end

                        // Stack Operations (Ascending stack, SP decrements on PUSH, increments on PULL)
                        PHA: begin // Push A
                            if (cycle == 1) begin // T1 (Opcode fetch) done. This is T2: Push.
                                push_byte(A); // Sets addr, data_out, we, SP--
                                cycle <= 2; // T3 (stack write happens here)
                            end else if (cycle == 2) begin // T2 (Push setup) done.
                                state <= S_FETCH_OP; cycle <= 0; // PHA is 3 cycles
                            end
                        end
                        PLA: begin // Pull A
                            if (cycle == 1) begin // T1 done. T2: Setup pull.
                                pull_byte();      // SP++, sets addr for read
                                cycle <= 2;       // T3: Read from stack
                            end else if (cycle == 2) begin // T2 done. T3: data is on stack, read it.
                                // data_in has stack value. This is effectively T4.
                                A <= data_in; set_nz(A);
                                state <= S_FETCH_OP; cycle <= 0; // PLA is 4 cycles
                            end
                        end
                        
                        // BRK - Software Interrupt
                        BRK: begin // 7 cycles
                            if (cycle == 1) begin // T1: Opcode fetch done. BRK is 1 byte, but PC incremented.
                                                // PC needs to be incremented once more for return address (PC+2 from BRK start)
                                PC <= PC + 1; // Dummy byte read after BRK opcode
                                brk_sequence_active <= 1'b1;
                                state <= S_INT_0_CYCLE; cycle <= 0; // Use common interrupt sequence
                            end
                        end

                        // RTI - Return from Interrupt
                        RTI: begin // 6 cycles
                            if (cycle == 1) begin // T1 done. T2: Pull F.
                                pull_byte(); cycle <= 2; state <= S_RTI_PULL_F;
                            end
                        end

                        // ... Other opcodes would follow similar pattern ...
                        // Each addressing mode would add cycles for operand/address fetching.
                        // RMW instructions would need read, (dummy write/modify), write cycles.

                        default: begin // Unimplemented or invalid opcode
                            // Treat as NOP or go to error state if desired.
                            // For now, acts like a 1-cycle NOP after fetch.
                            state <= S_FETCH_OP; cycle <= 0;
                        end
                    endcase
                    // --- End of Opcode Dispatch ---
                end

                // --- Interrupt State Machine (Continued) ---
                S_INT_0_CYCLE: begin // Cycle 1 of sequence (common entry for NMI, IRQ, BRK)
                    // This state is for any internal prep if needed. The actual stack ops start next.
                    // If BRK, PC is already pointing after the dummy byte.
                    // If HW interrupt, PC is pointing to the next instruction.
                    state <= S_INT_1_PUSH_PCH; cycle <= 2;
                end
                S_INT_1_PUSH_PCH: begin // Cycle 2
                    push_byte(PC[15:8]); state <= S_INT_2_PUSH_PCL; cycle <= 3;
                end
                S_INT_2_PUSH_PCL: begin // Cycle 3
                    push_byte(PC[7:0]);  state <= S_INT_3_PUSH_F;   cycle <= 4;
                end
                S_INT_3_PUSH_F: begin   // Cycle 4
                    // B flag (bit 4) is set if from BRK or IRQ, cleared for NMI.
                    // U flag (bit 2) is pushed as 1.
                    temp_val = F | 8'b00000100; // Ensure U is 1
                    if (nmi_sequence_active) temp_val = temp_val & 8'b11101111; // Clear B if NMI
                    else temp_val = temp_val | 8'b00010000; // Set B if BRK or IRQ
                    push_byte(temp_val);
                    F[5] <= 1'b1; // Set Interrupt Disable flag
                    state <= S_INT_4_VEC_L; cycle <= 5;
                end
                S_INT_4_VEC_L: begin    // Cycle 5: Read Vector Low byte
                    if (nmi_sequence_active) addr <= 16'hFFFA;      // NMI Vector Low
                    else addr <= 16'hFFFE;                          // IRQ/BRK Vector Low
                    we <= 1'b0;
                    state <= S_INT_5_VEC_H; cycle <= 6;
                end
                S_INT_5_VEC_H: begin    // Cycle 6: Read Vector High byte, store Low byte
                    operand_lo <= data_in; // Store Vector Low from previous cycle's read
                    if (nmi_sequence_active) addr <= 16'hFFFB;      // NMI Vector High
                    else addr <= 16'hFFFF;                          // IRQ/BRK Vector High
                    we <= 1'b0;
                    // Cycle 7: Store Vector High, form PC, go to Fetch Op. This happens implicitly on transition to S_FETCH_OP.
                    PC <= {data_in, operand_lo}; // Form new PC (data_in is ADH, operand_lo is ADL)
                    nmi_sequence_active <= 1'b0; 
                    irq_sequence_active <= 1'b0; 
                    brk_sequence_active <= 1'b0;
                    state <= S_FETCH_OP; cycle <= 0; // This is effectively start of cycle 7
                end
                
                // RTI States
                S_RTI_PULL_F: begin // Cycle 2 done (PULL F setup). This is T3: F read from stack.
                    if (cycle == 2) begin // Data from stack is now in data_in
                        F <= data_in & 8'b11001111; // Restore F. Mask out B (bit 4) and U (bit 2) as they are not directly restored.
                                                    // I (bit 5) is restored.
                        pull_byte(); // Setup PCL pull
                        cycle <= 3; state <= S_RTI_PULL_PCL;
                    end
                end
                S_RTI_PULL_PCL: begin // Cycle 3 done (PCL read setup). This is T4: PCL read from stack.
                     if (cycle == 3) begin
                        operand_lo <= data_in; // Store PCL
                        pull_byte(); // Setup PCH pull
                        cycle <= 4; state <= S_RTI_PULL_PCH;
                     end
                end
                S_RTI_PULL_PCH: begin // Cycle 4 done (PCH read setup). This is T5: PCH read from stack.
                    if (cycle == 4) begin
                        operand_hi <= data_in; // Store PCH
                        PC <= {operand_hi, operand_lo}; // Form PC
                        // Cycle 6 (T6) is the fetch of the new instruction
                        state <= S_FETCH_OP; cycle <= 0; // RTI is 6 cycles
                    end
                end

                default: begin // Should not happen with complete logic
                    state <= S_FETCH_OP; cycle <= 0;
                end
            endcase
        end
    end

endmodule
