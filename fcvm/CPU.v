module fc8_cpu (
    input wire clk,
    input wire rst_n,
    output reg [15:0] addr,     // Logical address (Section 5)
    input wire [7:0] data_in,
    output reg [7:0] data_out,
    output reg we,              // Write enable
    input wire irq_n,           // IRQ (active-low)
    input wire nmi_n            // NMI (active-low)
);

    // Registers (Section 5)
    reg [7:0] A;                // Accumulator
    reg [7:0] X, Y;             // Index registers
    reg [15:0] SP;              // Stack Pointer
    reg [15:0] PC;              // Program Counter
    reg [7:0] F;                // Flags: NVIZC (Section 5)

    // State machine
    reg [2:0] state;
    localparam FETCH = 3'd0, DECODE = 3'd1, EXECUTE = 3'd2, MEM_ACCESS = 3'd3, WRITEBACK = 3'd4;

    // Instruction register
    reg [7:0] current_instruction; 
    reg [15:0] operand_addr;
    reg [7:0] operand_val; 
    reg is_fetching_addr_hi; 
    reg [2:0] cycle_count; // Generic cycle counter for multi-cycle ops (JSR, RTS, etc.)
    reg [7:0] temp_data_reg; // Temporary storage for various operations (e.g. RTS PCL)
    reg [8:0] alu_temp_ext;  // For ADC/SBC to capture carry/borrow easily

    // Flags: F[7]=N, F[6]=V, F[5]=unused/B, F[4]=unused/D, F[3]=I (for SEI/CLI in 6502, but FC8 uses F[2]), F[2]=I, F[1]=Z, F[0]=C
    // Let's stick to NVIZC where F[2] is Int_Disable for now.
    // F[7] = N (Negative)
    // F[6] = V (Overflow)
    // F[5] = - (Unused, often B-flag in software)
    // F[4] = - (Unused, D-flag Decimal mode - not implemented)
    // F[3] = - (Unused)
    // F[2] = I (Interrupt Disable)
    // F[1] = Z (Zero)
    // F[0] = C (Carry)


    // Opcodes (expanding from previous set)
    localparam NOP_OP    = 8'hEA; 
    localparam LDA_IMM   = 8'hA9; localparam LDA_ABS   = 8'hAD;
    localparam STA_ABS   = 8'h8D;
    localparam LDX_IMM   = 8'hA2; localparam LDX_ABS   = 8'hAE;
    localparam STX_ABS   = 8'h8E;
    localparam LDY_IMM   = 8'hA0; localparam LDY_ABS   = 8'hAC;
    localparam STY_ABS   = 8'h8C;

    localparam JMP_ABS   = 8'h4C; 
    localparam JSR_ABS   = 8'h20; 
    localparam RTS_OP    = 8'h60; 

    localparam BNE_REL   = 8'hD0; // Z=0
    localparam BEQ_REL   = 8'hF0; // Z=1
    localparam BCC_REL   = 8'h90; // C=0
    localparam BCS_REL   = 8'hB0; // C=1
    localparam BPL_REL   = 8'h10; // N=0
    localparam BMI_REL   = 8'h30; // N=1

    localparam PHA_OP    = 8'h48; 
    localparam PLA_OP    = 8'h68; 
    
    localparam INC_ABS   = 8'hEE; localparam INX_IMP = 8'hE8; localparam INY_IMP = 8'hC8;
    localparam DEC_ABS   = 8'hCE; localparam DEX_IMP = 8'hCA; localparam DEY_IMP = 8'h88;

    // Arithmetic
    localparam ADC_IMM   = 8'h69; localparam ADC_ABS   = 8'h6D;
    localparam SBC_IMM   = 8'hE9; localparam SBC_ABS   = 8'hED;

    // Logical
    localparam AND_IMM   = 8'h29; localparam AND_ABS   = 8'h2D;
    localparam ORA_IMM   = 8'h09; localparam ORA_ABS   = 8'h0D;
    localparam EOR_IMM   = 8'h49; localparam EOR_ABS   = 8'h4D;

    // Compare
    localparam CMP_IMM   = 8'hC9; localparam CMP_ABS   = 8'hCD;
    localparam CPX_IMM   = 8'hE0; localparam CPX_ABS   = 8'hEC;
    localparam CPY_IMM   = 8'hC0; localparam CPY_ABS   = 8'hCC;

    // Shift/Rotate (Accumulator)
    localparam ASL_A_IMP = 8'h0A;
    localparam LSR_A_IMP = 8'h4A;
    localparam ROL_A_IMP = 8'h2A;
    localparam ROR_A_IMP = 8'h6A;

    // Flag control
    localparam CLC_IMP   = 8'h18; localparam SEC_IMP   = 8'h38;
    localparam CLI_IMP   = 8'h58; localparam SEI_IMP   = 8'h78;


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            A <= 8'h00;
            X <= 8'h00; Y <= 8'h00;
            SP <= 16'h01FF;     
            PC <= 16'h8000;     
            F <= 8'b00000100; // Init with I flag set, Z flag can be 1 if A is 0 (FC8 specific might differ)
            addr <= 16'h0000;
            we <= 1'b0;
            is_fetching_addr_hi <= 1'b0;
            cycle_count <= 0;
            state <= FETCH;
        end else begin
            // Default assignments
            we <= 1'b0;

            case (state)
                FETCH: begin
                    addr <= PC;
                    is_fetching_addr_hi <= 1'b0; 
                    cycle_count <= 0; // Reset cycle counter for new instruction
                    state <= DECODE;
                end
                DECODE: begin
                    current_instruction <= data_in;
                    PC <= PC + 1;
                    case (data_in)
                        NOP_OP, CLC_IMP, SEC_IMP, CLI_IMP, SEI_IMP, 
                        INX_IMP, INY_IMP, DEX_IMP, DEY_IMP,
                        ASL_A_IMP, LSR_A_IMP, ROL_A_IMP, ROR_A_IMP,
                        PHA_OP, PLA_OP, RTS_OP: state <= EXECUTE; // Implied/Accumulator/Stack direct to EXECUTE

                        LDA_IMM, LDX_IMM, LDY_IMM,
                        ADC_IMM, SBC_IMM, AND_IMM, ORA_IMM, EOR_IMM, CMP_IMM, CPX_IMM, CPY_IMM: 
                            state <= EXECUTE; // Immediate ops fetch operand in EXECUTE

                        BNE_REL, BEQ_REL, BCC_REL, BCS_REL, BPL_REL, BMI_REL: 
                            state <= EXECUTE; // Relative ops fetch offset in EXECUTE
                        
                        LDA_ABS, LDX_ABS, LDY_ABS, STA_ABS, STX_ABS, STY_ABS, JMP_ABS, JSR_ABS, 
                        INC_ABS, DEC_ABS, ADC_ABS, SBC_ABS, AND_ABS, ORA_ABS, EOR_ABS, CMP_ABS, CPX_ABS, CPY_ABS: begin
                            is_fetching_addr_hi <= 1'b0; 
                            state <= MEM_ACCESS; // Absolute ops fetch address first
                        end
                        
                        default: state <= FETCH; 
                    endcase
                end
                EXECUTE: begin // Handles Immediate, Implied, Accumulator, Stack ops, JSR/RTS sequencing
                    case (current_instruction)
                        LDA_IMM, LDX_IMM, LDY_IMM, ADC_IMM, SBC_IMM, AND_IMM, ORA_IMM, EOR_IMM, CMP_IMM, CPX_IMM, CPY_IMM: begin
                            addr <= PC; PC <= PC + 1; state <= WRITEBACK; // Fetch immediate operand
                        end
                        BNE_REL, BEQ_REL, BCC_REL, BCS_REL, BPL_REL, BMI_REL: begin
                            addr <= PC; PC <= PC + 1; state <= WRITEBACK; // Fetch relative offset
                        end
                        
                        INX_IMP: begin X <= X + 1; F[1] <= (X + 1 == 0); F[7] <= (X + 1)[7]; state <= FETCH; end
                        INY_IMP: begin Y <= Y + 1; F[1] <= (Y + 1 == 0); F[7] <= (Y + 1)[7]; state <= FETCH; end
                        DEX_IMP: begin X <= X - 1; F[1] <= (X - 1 == 0); F[7] <= (X - 1)[7]; state <= FETCH; end
                        DEY_IMP: begin Y <= Y - 1; F[1] <= (Y - 1 == 0); F[7] <= (Y - 1)[7]; state <= FETCH; end

                        ASL_A_IMP: begin F[0] <= A[7]; A <= A << 1; F[1] <= (A << 1 == 0); F[7] <= (A << 1)[7]; state <= FETCH; end
                        LSR_A_IMP: begin F[0] <= A[0]; A <= A >> 1; F[1] <= (A >> 1 == 0); F[7] <= 1'b0; state <= FETCH; end // LSR shifts 0 into MSB
                        ROL_A_IMP: begin {F[0], A} <= {A[7], A << 1 | F[0]}; F[1] <= ({A[7],A<<1|F[0]} == 0); F[7] <= A[7]; state <= FETCH; end
                        ROR_A_IMP: begin {A, F[0]} <= {F[0], A[0], A >> 1}; F[1] <= ({F[0],A[0],A>>1} == 0); F[7] <= F[0]; state <= FETCH; end
                        
                        CLC_IMP: begin F[0] <= 1'b0; state <= FETCH; end
                        SEC_IMP: begin F[0] <= 1'b1; state <= FETCH; end
                        CLI_IMP: begin F[2] <= 1'b0; state <= FETCH; end // F[2] is Interrupt Disable
                        SEI_IMP: begin F[2] <= 1'b1; state <= FETCH; end

                        PHA_OP: begin addr <= SP; data_out <= A; we <= 1'b1; SP <= SP - 1; state <= FETCH; end
                        PLA_OP: begin SP <= SP + 1; addr <= SP; state <= WRITEBACK; end // Read from stack in WRITEBACK

                        JSR_ABS: begin // operand_addr is fetched in MEM_ACCESS
                            if (cycle_count == 0) begin // Push PCH
                                addr <= SP; data_out <= PC[15:8]; we <= 1'b1; SP <= SP - 1;
                                cycle_count <= 1; state <= EXECUTE; // Stay in EXECUTE for next cycle
                            end else if (cycle_count == 1) begin // Push PCL
                                addr <= SP; data_out <= PC[7:0]; we <= 1'b1; SP <= SP - 1;
                                PC <= operand_addr; // Set PC to subroutine address
                                cycle_count <= 0; state <= FETCH;
                            end
                        end
                        RTS_OP: begin
                            if (cycle_count == 0) begin // Pull PCL
                                SP <= SP + 1; addr <= SP;
                                cycle_count <= 1; state <= EXECUTE;
                            end else if (cycle_count == 1) begin // Pull PCH
                                temp_data_reg <= data_in; // Store PCL
                                SP <= SP + 1; addr <= SP;
                                cycle_count <= 2; state <= EXECUTE;
                            end else if (cycle_count == 2) begin // Construct PC and increment
                                PC <= {data_in, temp_data_reg} + 1; // data_in is PCH, temp_data_reg is PCL
                                cycle_count <= 0; state <= FETCH;
                            end
                        end
                        
                        // INC_ABS/DEC_ABS modify step (after read in WRITEBACK, data in operand_val)
                        INC_ABS, DEC_ABS: begin 
                            addr <= operand_addr; 
                            if (current_instruction == INC_ABS) begin
                                operand_val <= operand_val + 1;
                                F[1] <= (operand_val + 1 == 0); F[7] <= (operand_val + 1)[7];
                                data_out <= operand_val + 1;
                            end else begin // DEC_ABS
                                operand_val <= operand_val - 1;
                                F[1] <= (operand_val - 1 == 0); F[7] <= (operand_val - 1)[7];
                                data_out <= operand_val - 1;
                            end
                            we <= 1'b1; state <= FETCH;
                        end
                        default: state <= FETCH; 
                    endcase
                end
                MEM_ACCESS: begin 
                    addr <= PC; PC <= PC + 1;
                    if (is_fetching_addr_hi) begin 
                        operand_addr[15:8] <= data_in;
                        is_fetching_addr_hi <= 1'b0; 

                        case (current_instruction)
                            LDA_ABS, LDX_ABS, LDY_ABS, ADC_ABS, SBC_ABS, AND_ABS, ORA_ABS, EOR_ABS, CMP_ABS, CPX_ABS, CPY_ABS, INC_ABS, DEC_ABS: begin
                                addr <= operand_addr; // Set address for data read/RMW read
                                state <= WRITEBACK; 
                            end
                            STA_ABS, STX_ABS, STY_ABS: begin
                                addr <= operand_addr; 
                                if (current_instruction == STA_ABS) data_out <= A;
                                else if (current_instruction == STX_ABS) data_out <= X;
                                else if (current_instruction == STY_ABS) data_out <= Y;
                                we <= 1'b1; state <= FETCH; 
                            end
                            JMP_ABS: begin PC <= operand_addr; state <= FETCH; end
                            JSR_ABS: begin state <= EXECUTE; end // Address fetched, proceed to EXECUTE for stack ops
                            default: state <= FETCH; 
                        endcase
                    end else { 
                        operand_addr[7:0] <= data_in;
                        is_fetching_addr_hi <= 1'b1; 
                        state <= MEM_ACCESS; 
                    }
                end
                WRITEBACK: begin 
                    operand_val <= data_in; // Capture data_in for all ops needing it here
                    case (current_instruction)
                        LDA_IMM, LDA_ABS: begin A <= data_in; F[1] <= (data_in == 0); F[7] <= data_in[7]; state <= FETCH; end
                        LDX_IMM, LDX_ABS: begin X <= data_in; F[1] <= (data_in == 0); F[7] <= data_in[7]; state <= FETCH; end
                        LDY_IMM, LDY_ABS: begin Y <= data_in; F[1] <= (data_in == 0); F[7] <= data_in[7]; state <= FETCH; end
                        PLA_OP: begin A <= data_in; F[1] <= (data_in == 0); F[7] <= data_in[7]; state <= FETCH; end

                        ADC_IMM, ADC_ABS: begin
                            alu_temp_ext <= {1'b0, A} + {1'b0, data_in} + F[0];
                            F[0] <= alu_temp_ext[8]; // Carry
                            F[6] <= (A[7] == data_in[7]) && (alu_temp_ext[7] != A[7]); // Overflow
                            A <= alu_temp_ext[7:0];
                            F[1] <= (A == 0); F[7] <= A[7]; // Zero, Negative
                            state <= FETCH;
                        end
                        SBC_IMM, SBC_ABS: begin // A = A - M - (1-C)
                            alu_temp_ext <= {1'b0, A} - {1'b0, data_in} - (1 - F[0]);
                            F[0] <= ~alu_temp_ext[8]; // Borrow is inverse of carry out
                            F[6] <= (A[7] != data_in[7]) && (alu_temp_ext[7] != A[7]); // Overflow
                            A <= alu_temp_ext[7:0];
                            F[1] <= (A == 0); F[7] <= A[7]; // Zero, Negative
                            state <= FETCH;
                        end
                        AND_IMM, AND_ABS: begin A <= A & data_in; F[1] <= ((A & data_in) == 0); F[7] <= (A & data_in)[7]; state <= FETCH; end
                        ORA_IMM, ORA_ABS: begin A <= A | data_in; F[1] <= ((A | data_in) == 0); F[7] <= (A | data_in)[7]; state <= FETCH; end
                        EOR_IMM, EOR_ABS: begin A <= A ^ data_in; F[1] <= ((A ^ data_in) == 0); F[7] <= (A ^ data_in)[7]; state <= FETCH; end
                        
                        CMP_IMM, CMP_ABS: begin alu_temp_ext <= {1'b0, A} - {1'b0, data_in}; F[0] <= ~alu_temp_ext[8]; F[1] <= (alu_temp_ext[7:0] == 0); F[7] <= alu_temp_ext[7]; state <= FETCH; end
                        CPX_IMM, CPX_ABS: begin alu_temp_ext <= {1'b0, X} - {1'b0, data_in}; F[0] <= ~alu_temp_ext[8]; F[1] <= (alu_temp_ext[7:0] == 0); F[7] <= alu_temp_ext[7]; state <= FETCH; end
                        CPY_IMM, CPY_ABS: begin alu_temp_ext <= {1'b0, Y} - {1'b0, data_in}; F[0] <= ~alu_temp_ext[8]; F[1] <= (alu_temp_ext[7:0] == 0); F[7] <= alu_temp_ext[7]; state <= FETCH; end

                        BNE_REL: begin if (F[1] == 1'b0) PC <= PC + (data_in[7] ? -signed'(~data_in+1) : signed'(data_in)); state <= FETCH; end // Z=0
                        BEQ_REL: begin if (F[1] == 1'b1) PC <= PC + (data_in[7] ? -signed'(~data_in+1) : signed'(data_in)); state <= FETCH; end // Z=1
                        BCC_REL: begin if (F[0] == 1'b0) PC <= PC + (data_in[7] ? -signed'(~data_in+1) : signed'(data_in)); state <= FETCH; end // C=0
                        BCS_REL: begin if (F[0] == 1'b1) PC <= PC + (data_in[7] ? -signed'(~data_in+1) : signed'(data_in)); state <= FETCH; end // C=1
                        BPL_REL: begin if (F[7] == 1'b0) PC <= PC + (data_in[7] ? -signed'(~data_in+1) : signed'(data_in)); state <= FETCH; end // N=0
                        BMI_REL: begin if (F[7] == 1'b1) PC <= PC + (data_in[7] ? -signed'(~data_in+1) : signed'(data_in)); state <= FETCH; end // N=1
                        
                        INC_ABS, DEC_ABS: begin // Data was read into operand_val in MEM_ACCESS, now pass to EXECUTE
                            operand_val <= data_in; // Capture the read value
                            state <= EXECUTE;       // Go to EXECUTE to perform modify & write
                        end
                        default: state <= FETCH; 
                    endcase
                end
            endcase

            // Interrupt handling (Section 13.4) - simplified, needs proper state integration
            // if (!nmi_n && state == FETCH) begin
            //     // Proper NMI/IRQ handling requires dedicated states for pushing PC and F onto stack,
            //     // then loading PC from interrupt vector address.
            //     // Example:
            //     // 1. Push PCH: addr <= SP; data_out <= PC[15:8]; we <= 1'b1; SP <= SP - 1;
            //     // 2. Push PCL: addr <= SP; data_out <= PC[7:0]; we <= 1'b1; SP <= SP - 1;
            //     // 3. Push F:   addr <= SP; data_out <= F; we <= 1'b1; SP <= SP - 1; F[2] <= 1'b1; // Set I flag
            //     // 4. Fetch NMI_VECTOR_LO: addr <= NMI_VECTOR_ADDR;
            //     // 5. Fetch NMI_VECTOR_HI: addr <= NMI_VECTOR_ADDR + 1; PC <= {NMI_HI, NMI_LO}; state <= FETCH;
            //     state <= EXECUTE; // Placeholder for simplified interrupt sequence
            // end
        end
    end

endmodule
