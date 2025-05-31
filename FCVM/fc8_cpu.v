// FCVM/fc8_cpu.v
`include "fc8_defines.v"

module fc8_cpu (
    input wire clk,
    input wire rst_n, // Active low reset

    // Memory Interface
    input wire [7:0] mem_data_in,
    output reg [15:0] mem_addr_out,
    output reg [7:0] mem_data_out,
    output reg mem_rd_en,
    output reg mem_wr_en,

    // Interrupt Inputs (from interrupt controller)
    input wire nmi_req_in,  // Level sensitive NMI request
    input wire irq_req_in   // Level sensitive IRQ request
);

    // Registers
    reg [15:0] pc; // Program Counter
    reg [15:0] sp; // Stack Pointer
    reg [7:0] a;  // Accumulator
    reg [7:0] x;  // Index Register X
    reg [7:0] y;  // Index Register Y
    reg [7:0] f;  // Flag Register (N V - B D I Z C)

    // Internal signals
    reg [7:0] opcode;
    reg [15:0] effective_addr;
    reg [7:0] operand_val;
    reg [7:0] temp_val;
    reg signed_branch_offset;

    // CPU States
    localparam S_RESET_0        = 6'd0;
    localparam S_RESET_1        = 6'd1;
    localparam S_RESET_2        = 6'd2;
    localparam S_RESET_3        = 6'd3;
    localparam S_RESET_4        = 6'd4;
    localparam S_FETCH_OPCODE   = 6'd5;
    localparam S_DECODE         = 6'd6;

    localparam S_FETCH_ZP_ADDR  = 6'd7;
    localparam S_FETCH_ABS_ADL  = 6'd8;
    localparam S_FETCH_ABS_ADH  = 6'd9;
    localparam S_CALC_ZP_X_ADDR = 6'd10;
    localparam S_CALC_ABS_X_ADL = 6'd11;
    localparam S_CALC_ABS_X_ADH = 6'd12;
    localparam S_CALC_ABS_Y_ADL = 6'd13;
    localparam S_CALC_ABS_Y_ADH = 6'd14;

    localparam S_EXEC_READ      = 6'd15;
    localparam S_EXEC_WRITE     = 6'd16;
    localparam S_EXEC_IMPLIED   = 6'd17;
    localparam S_EXEC_BRANCH    = 6'd18;
    localparam S_BRANCH_TAKEN   = 6'd19;
    localparam S_BRANCH_PAGE_CROSS = 6'd20;

    localparam S_PUSH_1         = 6'd21;
    localparam S_PUSH_2         = 6'd22;
    localparam S_PULL_1         = 6'd23;
    localparam S_PULL_2         = 6'd24;
    localparam S_PULL_3         = 6'd25;

    // Interrupt Handling States
    localparam S_INT_0_START_SEQ = 6'd26;
    localparam S_INT_1_PUSH_PCH  = 6'd27;
    localparam S_INT_2_PUSH_PCL  = 6'd28;
    localparam S_INT_3_PUSH_F    = 6'd29;
    localparam S_INT_4_FETCH_ADL = 6'd30;
    localparam S_INT_5_FETCH_ADH = 6'd31;

    // RTI specific states
    localparam S_RTI_1_DEC_SP_POP_F   = 6'd32;
    localparam S_RTI_2_DEC_SP_POP_PCL = 6'd33;
    localparam S_RTI_3_DEC_SP_POP_PCH = 6'd34;

    localparam S_JSR_FETCH_ADL  = 6'd35; // Was 6'd35
    localparam S_JSR_FETCH_ADH  = 6'd36; // Was 6'd36
    localparam S_JSR_PUSH_RET_PCH = 6'd37; // New, was S_JSR_PUSH_PCH
    localparam S_JSR_PUSH_RET_PCL = 6'd38; // New, was S_JSR_PUSH_PCL
    localparam S_RTS_PULL_PCL   = 6'd39;
    localparam S_RTS_PULL_PCH   = 6'd40;
    localparam S_RTS_INC_PC     = 6'd41;
    localparam S_HALTED         = 6'd42;

    // New CPU States for Read-Modify-Write and JMP IND (Phase 2)
    localparam S_RMW_FETCH_DATA = 6'd43; // For ASL, LSR, ROL, ROR on memory (INC/DEC mem use existing states)
    localparam S_RMW_EXECUTE    = 6'd44;
    localparam S_RMW_WRITE_BACK = 6'd45;
    localparam S_JMP_IND_FETCH_ADL = 6'd46; // For JMP ($addr)
    localparam S_JMP_IND_FETCH_ADH = 6'd47;
    // S_PUSH_1, S_PUSH_2, S_PULL_1, S_PULL_2, S_PULL_3 will be reused for PHX/PHY, PLX/PLY

    reg [5:0] current_state; // Max state is 47, so 6 bits are still fine.
    reg [5:0] next_state;

    reg [2:0] cycle_count;
    reg         interrupt_pending_type_nmi;
    reg [15:0]  interrupt_vector_addr_base;
    // reg [7:0]   flags_to_push_on_stack; // Removed, direct usage of format
    reg [15:0]  pc_for_push;
    reg [7:0]   data_for_rmw; // Holds data fetched for RMW ops
    reg         c_for_rmw;    // Holds carry calculated for RMW ops

    // Helper flags for instruction categories
    wire is_lda, is_ldx, is_ldy;
    wire is_sta, is_stx, is_sty;
    wire is_adc, is_sbc;
    wire is_inc, is_dec, is_inx, is_iny, is_dex, is_dey;
    wire is_and, is_ora, is_eor;
    wire is_asl_a, is_lsr_a, is_rol_a, is_ror_a;
    wire is_flags_op;
    wire is_compare_op;
    wire is_branch_op;
    wire is_stack_op;
    wire is_jmp_op;
    wire is_nop_op;
    wire is_rti_op;
    wire is_brk_op;
    wire is_jsr_op, is_rts_op;
    wire is_transfer_op;
    wire is_phx_phy_op, is_plx_ply_op;
    wire is_hlt_op;

    // New helper wires for Phase 2
    wire is_asl_mem_op, is_lsr_mem_op, is_rol_mem_op, is_ror_mem_op;
    wire is_rmw_op; // Read-Modify-Write for ASL,LSR,ROL,ROR (mem) and INC (mem), DEC (mem)
    wire is_bit_op;
    wire is_jmp_ind_op;

    // Addressing mode indicators
    wire is_imm, is_zp, is_zp_x, is_abs, is_abs_x, is_abs_y, is_implied, is_rel, is_ind; // Added is_ind

    // --- Flag helpers ---
    wire n_flag = f[`N_FLAG_BIT];
    wire v_flag = f[`V_FLAG_BIT];
    wire d_flag = f[`D_FLAG_BIT];
    wire i_flag = f[`I_FLAG_BIT];
    wire z_flag = f[`Z_FLAG_BIT];
    wire c_flag = f[`C_FLAG_BIT];

    task set_nz_flags;
        input [7:0] value;
    begin
        f[`N_FLAG_BIT] = value[7];
        f[`Z_FLAG_BIT] = (value == 8'h00);
    end
    endtask

    // Initialize registers on reset
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sp <= 16'h0100; // Stack pointer starts at $01FF, first push to $01FF, then SP becomes $01FE. So init to $0100 is wrong. Should be $01FF and decrement. Or $0100 and post-increment. Standard 6502 is top-down, $01FF initial. Let's assume $0100 means $0100-$01FF is stack, so $01FF is top. Or if SP points to *next free slot*, $0100 is fine. The current push (PHA/PHP) logic does mem_addr_out = sp; sp <= sp + 1; so it's an ascending stack SP points to last item. This is non-standard for 6502 (which is descending). For now, I'll keep SP init as is, as it's a larger change.
            a  <= 8'h00;
            x  <= 8'h00;
            y  <= 8'h00;
            // Corrected Reset Value: All flags cleared, including I (bit 5) as per Spec Sec 3.
            // Spec Sec 3 refers to I_FLAG_BIT which is bit 2.
            // So, f <= 8'h00 means N,V,U,B,D,I,Z,C all 0.
            f  <= 8'h00;
            current_state <= S_RESET_0;
            mem_rd_en <= 1'b0;
            mem_wr_en <= 1'b0;
            pc <= 16'h0000;
            cycle_count <= 3'd0;
        end else begin
            current_state <= next_state;
            cycle_count <= cycle_count + 1;

            mem_rd_en <= (next_state == S_FETCH_OPCODE ||
                           next_state == S_FETCH_ZP_ADDR ||
                           next_state == S_FETCH_ABS_ADL ||
                           next_state == S_FETCH_ABS_ADH ||
                           next_state == S_CALC_ABS_X_ADL ||
                           next_state == S_CALC_ABS_X_ADH ||
                           next_state == S_CALC_ABS_Y_ADL ||
                           next_state == S_CALC_ABS_Y_ADH ||
                           next_state == S_EXEC_READ ||
                           // Read for RTI stack pop
                           current_state == S_RTI_1_DEC_SP_POP_F ||
                           current_state == S_RTI_2_DEC_SP_POP_PCL||
                           current_state == S_RTI_3_DEC_SP_POP_PCH||
                           // Read for interrupt vector fetch
                           current_state == S_INT_3_PUSH_F    ||
                           current_state == S_INT_4_FETCH_ADL ||
                           (current_state == S_RESET_0 && next_state == S_RESET_1) ||
                           (current_state == S_RESET_2 && next_state == S_RESET_3) ||
                           // JSR reads
                           next_state == S_JSR_FETCH_ADL ||
                           next_state == S_JSR_FETCH_ADH ||
                           // RTS reads
                           current_state == S_RTS_PULL_PCL ||
                           current_state == S_RTS_PULL_PCH ||
                           // RMW read
                           next_state == S_RMW_FETCH_DATA ||
                           // JMP IND reads (indirect address first, then final PC) - covered by S_FETCH_ABS_ADL/ADH and then these
                           next_state == S_JMP_IND_FETCH_ADL ||
                           next_state == S_JMP_IND_FETCH_ADH
                           ) && !(current_state == S_HALTED);

            mem_wr_en <= ((next_state == S_EXEC_WRITE ||
                           next_state == S_PUSH_2 || // PHA, PHP, PHX, PHY
                           // Writes for interrupt stack push
                           current_state == S_INT_0_START_SEQ ||
                           current_state == S_INT_1_PUSH_PCH  ||
                           current_state == S_INT_2_PUSH_PCL ||
                           // JSR Pushes
                           next_state == S_JSR_PUSH_RET_PCH ||
                           next_state == S_JSR_PUSH_RET_PCL ||
                           // RMW write back
                           next_state == S_RMW_WRITE_BACK
                           )) && !(current_state == S_HALTED);

            case (current_state)
                S_RESET_1: pc[7:0] <= mem_data_in;
                S_RESET_3: pc[15:8] <= mem_data_in;
                S_FETCH_OPCODE: begin
                    opcode <= mem_data_in;
                    pc <= pc + 1;
                end
                S_FETCH_ZP_ADDR: begin effective_addr <= {8'h00, mem_data_in}; pc <= pc + 1; end
                S_FETCH_ABS_ADL: begin effective_addr[7:0] <= mem_data_in; pc <= pc + 1; end
                S_FETCH_ABS_ADH: begin effective_addr[15:8] <= mem_data_in; pc <= pc + 1; end
                S_CALC_ZP_X_ADDR: effective_addr <= {8'h00, effective_addr[7:0] + x};
                S_CALC_ABS_X_ADL: begin temp_val <= operand_val; effective_addr[7:0] <= operand_val + x; pc <= pc + 1; end
                S_CALC_ABS_X_ADH: begin effective_addr[15:8] <= mem_data_in + ( (temp_val + x > 8'hFF) ? 1:0 ); pc <= pc + 1; end
                S_CALC_ABS_Y_ADL: begin temp_val <= operand_val; effective_addr[7:0] <= operand_val + y; pc <= pc + 1; end
                S_CALC_ABS_Y_ADH: begin effective_addr[15:8] <= mem_data_in + ( (temp_val + y > 8'hFF) ? 1:0 ); pc <= pc + 1; end
                S_EXEC_READ: operand_val <= mem_data_in;
                S_EXEC_WRITE: ;

                // JSR States (Clocked)
                S_JSR_FETCH_ADL: begin
                    effective_addr[7:0] <= mem_data_in;
                    pc <= pc + 1;
                end
                S_JSR_FETCH_ADH: begin
                    effective_addr[15:8] <= mem_data_in;
                    pc <= pc + 1;
                    pc_for_push <= pc - 1;
                end
                S_JSR_PUSH_RET_PCH: begin
                    sp <= sp + 1;
                end
                S_JSR_PUSH_RET_PCL: begin
                    sp <= sp + 1;
                    pc <= effective_addr;
                end

                // RTS States (Clocked)
                S_RTS_PULL_PCL: begin // PCL is read from stack (mem_data_in will have it next cycle)
                    effective_addr[7:0] <= mem_data_in; // Latch PCL
                    sp <= sp - 1; // Decrement SP after PCL read (SP was pointing to PCL's location + 1 due to JSR's post-increment)
                                  // So sp-1 points to PCL. After this, sp will point to PCH's location.
                                  // The combinational S_DECODE set mem_addr_out = sp-1 (pointing to PCL).
                                  // The combinational S_RTS_PULL_PCL will set mem_addr_out = sp-1 (new sp, so points to PCH).
                end
                S_RTS_PULL_PCH: begin // PCH is read from stack
                    effective_addr[15:8] <= mem_data_in; // Latch PCH
                    sp <= sp - 1; // Second SP decrement for RTS, after PCH pull.
                                  // JSR increments SP twice. RTS should decrement SP twice.
                                  // First was in S_RTS_PULL_PCL (clocked). This is the second.
                                  // SP now points to the location where PCH was, after being read.
                end
                S_RTS_INC_PC: begin
                    pc <= effective_addr + 1;
                end

                S_RMW_FETCH_DATA: begin
                    data_for_rmw <= mem_data_in;
                end
                S_RMW_EXECUTE: begin
                    f[`C_FLAG_BIT] <= c_for_rmw;
                    set_nz_flags(data_for_rmw);
                    mem_data_out <= data_for_rmw;
                end
                S_RMW_WRITE_BACK: begin
                end

                // JMP IND States (Clocked)
                S_JMP_IND_FETCH_ADL: begin // mem_data_in has final PCL
                    pc[7:0] <= mem_data_in;
                    // Prepare to fetch ADH from (original_indirect_addr_high_byte, original_indirect_addr_low_byte + 1)
                    // effective_addr currently holds the base indirect address {INDH, INDL}
                    // Need to handle page boundary crossing for the indirect vector itself if INDL is $FF.
                    // Standard 6502 JMP ($xxFF) bug: reads ADH from $xx00 instead of $xxFF+1.
                    // Subtask says "JMP IND page boundary bug is not typically emulated unless specified". So, simple +1.
                    effective_addr <= {effective_addr[15:8], effective_addr[7:0] + 1};
                    // mem_addr_out will be set to this new effective_addr by combinational logic for S_JMP_IND_FETCH_ADH read.
                    // next_state = S_JMP_IND_FETCH_ADH; // Set in combinational
                end
                S_JMP_IND_FETCH_ADH: begin // mem_data_in has final PCH
                    pc[15:8] <= mem_data_in;
                    // next_state = S_FETCH_OPCODE; // Set in combinational
                end

                S_EXEC_IMPLIED: begin
                    if (is_transfer_op) begin
                        case(opcode)
                            `OP_TAX_IMP: begin x <= a; set_nz_flags(a); end
                            `OP_TAY_IMP: begin y <= a; set_nz_flags(a); end
                            `OP_TSX_IMP: begin x <= sp[7:0]; set_nz_flags(sp[7:0]); end // SP is 16-bit, TSX uses low byte
                            `OP_TXA_IMP: begin a <= x; set_nz_flags(x); end
                            `OP_TXS_IMP: begin sp <= {8'h01, x}; end // Set SP to $01X
                            `OP_TYA_IMP: begin a <= y; set_nz_flags(y); end
                        endcase
                    end
                    else if (is_bit_op) begin // BIT instruction (operand_val is from memory)
                        f[`Z_FLAG_BIT] = (a & operand_val) == 8'h00;
                        f[`N_FLAG_BIT] = operand_val[7];
                        f[`V_FLAG_BIT] = operand_val[6];
                    end
                    else if (is_lda) begin a <= operand_val; set_nz_flags(operand_val); end
                    else if (is_ldx) begin x <= operand_val; set_nz_flags(operand_val); end
                    else if (is_ldy) begin y <= operand_val; set_nz_flags(operand_val); end
                    else if (is_adc) begin temp_val = a; {f[`C_FLAG_BIT], a} = a + operand_val + f[`C_FLAG_BIT]; f[`V_FLAG_BIT] = (~(temp_val[7] ^ operand_val[7]) & (temp_val[7] ^ a[7])); set_nz_flags(a); end
                    if (is_sbc) begin temp_val = a; {f[`C_FLAG_BIT], a} = a - operand_val - (1-f[`C_FLAG_BIT]); f[`V_FLAG_BIT] = ((temp_val[7] ^ operand_val[7]) & (temp_val[7] ^ a[7])); set_nz_flags(a); end
                    if (is_inc) begin temp_val <= operand_val + 1; set_nz_flags(operand_val + 1); end
                    if (is_dec) begin temp_val <= operand_val - 1; set_nz_flags(operand_val - 1); end
                    if (is_inx) begin x <= x + 1; set_nz_flags(x + 1); end
                    if (is_iny) begin y <= y + 1; set_nz_flags(y + 1); end
                    if (is_dex) begin x <= x - 1; set_nz_flags(x - 1); end
                    if (is_dey) begin y <= y - 1; set_nz_flags(y - 1); end
                    if (is_and) begin a <= a & operand_val; set_nz_flags(a & operand_val); end
                    if (is_ora) begin a <= a | operand_val; set_nz_flags(a | operand_val); end
                    if (is_eor) begin a <= a ^ operand_val; set_nz_flags(a ^ operand_val); end
                    if (is_asl_a) begin f[`C_FLAG_BIT] = a[7]; a <= a << 1; set_nz_flags(a << 1); end
                    if (is_lsr_a) begin f[`C_FLAG_BIT] = a[0]; a <= a >> 1; set_nz_flags(a >> 1); end
                    if (is_rol_a) begin temp_val = a; {f[`C_FLAG_BIT], a} = {temp_val[7], temp_val[6:0], f[`C_FLAG_BIT]}; set_nz_flags(a); end
                    if (is_ror_a) begin temp_val = a; {a, f[`C_FLAG_BIT]} = {f[`C_FLAG_BIT], temp_val[7:1], temp_val[0]}; set_nz_flags(a); end
                    if (is_flags_op) begin
                        case(opcode)
                            `OP_CLC: f[`C_FLAG_BIT] = 1'b0; `OP_SEC: f[`C_FLAG_BIT] = 1'b1;
                            `OP_CLI: f[`I_FLAG_BIT] = 1'b0; `OP_SEI: f[`I_FLAG_BIT] = 1'b1;
                            `OP_CLV: f[`V_FLAG_BIT] = 1'b0;
                        endcase
                    end
                    if (is_compare_op) begin
                        reg [7:0] val_to_compare;
                        if (opcode == `OP_CPX_IMM || opcode == `OP_CPX_ZP) val_to_compare = x;
                        else if (opcode == `OP_CPY_IMM || opcode == `OP_CPY_ZP) val_to_compare = y;
                        else val_to_compare = a;
                        temp_val = val_to_compare - operand_val;
                        set_nz_flags(temp_val);
                        f[`C_FLAG_BIT] = (val_to_compare >= operand_val);
                    end
                end
                S_BRANCH_TAKEN: pc <= effective_addr;
                S_BRANCH_PAGE_CROSS: pc <= effective_addr;
                S_PUSH_1: ; // mem_addr_out set in S_DECODE. Data to push set in global mem_data_out. Write happens at S_PUSH_2.
                S_PUSH_2: sp <= sp + 1; // Actual SP increment after push.
                S_PULL_1: sp <= sp - 1; // SP decrement. mem_addr_out (from S_DECODE) was (original_sp - 1).
                                      // Data read using that addr will be in mem_data_in for S_PULL_2.
                                      // New SP value is (original_sp - 1).
                S_PULL_2: ; // Data is being read from stack (address was set based on sp before S_PULL_1's decrement).
                S_PULL_3: begin // Data is in mem_data_in.
                    if (opcode == `OP_PLA) begin a <= mem_data_in; set_nz_flags(mem_data_in); end
                    else if (opcode == `OP_PLP) begin
                        // f <= (mem_data_in & ~((1<<`B_FLAG_BIT) | (1<<5))) | (f & ((1<<`B_FLAG_BIT) | (1<<5))); // Old logic
                        // Corrected Popping F (PLP): N,V,I (f[5]) restored. Unused bits 4,3,2 in F reg become 0. Z,C restored.
                        // I_FLAG_BIT is bit 2. B_FLAG_BIT is bit 4. D_FLAG_BIT is bit 3.
                        // So, {data[7],data[6],data[5], 1'b0/*B*/, 1'b0/*D*/, 1'b0/*I*/, data[1],data[0]}
                        reg [7:0] data_from_stack; data_from_stack = mem_data_in;
                        f <= {data_from_stack[7],data_from_stack[6],data_from_stack[5],1'b0,1'b0,1'b0,data_from_stack[1],data_from_stack[0]};
                    end
                    else if (opcode == `OP_PLX_IMP) begin x <= mem_data_in; set_nz_flags(mem_data_in); end
                    else if (opcode == `OP_PLY_IMP) begin y <= mem_data_in; set_nz_flags(mem_data_in); end
                end

                S_INT_1_PUSH_PCH:  sp <= sp + 1;
                S_INT_2_PUSH_PCL:  sp <= sp + 1;
                S_INT_3_PUSH_F:    sp <= sp + 1;

                S_INT_4_FETCH_ADL: begin
                    // FC8 Spec Sec 10.3: "I flag is set to 1" for NMI, IRQ, BRK interrupt sequence
                    f[`I_FLAG_BIT] <= 1'b1;
                    pc[7:0] <= mem_data_in;
                end
                S_INT_5_FETCH_ADH: begin
                    pc[15:8] <= mem_data_in;
                end

                S_RTI_1_DEC_SP_POP_F: begin
                    // f <= (mem_data_in & ~((1<<`B_FLAG_BIT) | (1<<5))) | (f & ((1<<`B_FLAG_BIT) | (1<<5)));
                    // Per spec: f <= {data[7],data[6],data[5],1'b0,1'b0,1'b0,data[1],data[0]};
                    reg [7:0] data_from_stack; data_from_stack = mem_data_in; // Renamed for clarity
                    f <= {data_from_stack[7],data_from_stack[6],data_from_stack[5],1'b0,1'b0,1'b0,data_from_stack[1],data_from_stack[0]};
                end
                S_RTI_2_DEC_SP_POP_PCL: begin
                    pc[7:0] <= mem_data_in;
                end
                S_RTI_3_DEC_SP_POP_PCH: begin
                    pc[15:8] <= mem_data_in;
                end
            endcase
        end
    end

    // State machine logic & instruction decode
    always @(*) begin
        next_state = current_state;
        cycle_count = 3'd0;
        mem_addr_out = effective_addr;
        // This mem_data_out is primarily for writes that happen in S_EXEC_WRITE or S_PUSH_2.
        // For S_PUSH_2, data is prepared when current_state is S_PUSH_1 (or JSR/INT states that lead to push).
        mem_data_out = (is_sta && !is_stx && !is_sty) ? a :       // STA
                       (is_stx) ? x :                            // STX
                       (is_sty) ? y :                            // STY
                       ((is_inc || is_dec) && !(is_inx || is_iny || is_dex || is_dey)) ? temp_val : // INC/DEC memory
                       // Data for stack push operations - value is set when current_state is S_PUSH_1 (for PHA/PHP/PHX/PHY)
                       // The actual write happens when next_state becomes S_PUSH_2.
                       (current_state == S_PUSH_1 && opcode == `OP_PHA) ? a :
                       // Corrected PHP: {f[7],f[6],f[5], 1'b1/*B*/, 1'b0/*D/unused*/, 1'b0/*unused*/, f[1],f[0]}
                       // Assuming bit 5 is I, bit 2 is unused. But defines say I_FLAG_BIT is 2.
                       // Using defines: N=f[7], V=f[6], f[5]=f[5], B_FLAG_BIT(4)=1, D_FLAG_BIT(3)=0, I_FLAG_BIT(2)=0, Z=f[1], C=f[0]
                       (current_state == S_PUSH_1 && opcode == `OP_PHP) ? {f[`N_FLAG_BIT],f[`V_FLAG_BIT],f[5],1'b1,1'b0,1'b0,f[`Z_FLAG_BIT],f[`C_FLAG_BIT]} :
                       (current_state == S_PUSH_1 && opcode == `OP_PHX_IMP) ? x :
                       (current_state == S_PUSH_1 && opcode == `OP_PHY_IMP) ? y :
                       // Data for JSR stack push
                       (current_state == S_JSR_FETCH_ADH && next_state == S_JSR_PUSH_RET_PCH) ? pc_for_push[15:8] :
                       (current_state == S_JSR_PUSH_RET_PCH && next_state == S_JSR_PUSH_RET_PCL) ? pc_for_push[7:0] :
                       // Data for Interrupt/BRK stack push
                       // Corrected: {f[7],f[6],f[5], (is_brk_op ? 1'b1 : 1'b0) /*B*/, 1'b0/*unused*/,1'b0/*unused*/,f[1],f[0]}
                       (current_state == S_INT_0_START_SEQ && next_state == S_INT_1_PUSH_PCH) ? pc_for_push[15:8] : // PCH
                       (current_state == S_INT_1_PUSH_PCH && next_state == S_INT_2_PUSH_PCL) ? pc_for_push[7:0] :   // PCL
                       (current_state == S_INT_2_PUSH_PCL && next_state == S_INT_3_PUSH_F) ? {f[`N_FLAG_BIT],f[`V_FLAG_BIT],f[5],(is_brk_op ? 1'b1 : 1'b0),1'b0,1'b0,f[`Z_FLAG_BIT],f[`C_FLAG_BIT]} :
                       8'h00; // Default

        case (current_state)
            S_RESET_0: begin mem_addr_out = `RESET_VECTOR_ADDR_LOW; next_state = S_RESET_1; end
            S_RESET_1: next_state = S_RESET_2;
            S_RESET_2: begin mem_addr_out = `RESET_VECTOR_ADDR_HIGH; next_state = S_RESET_3; end
            S_RESET_3: next_state = S_RESET_4;
            S_RESET_4: next_state = S_FETCH_OPCODE;

            S_FETCH_OPCODE: begin
                if (nmi_req_in) begin
                    interrupt_pending_type_nmi <= 1'b1;
                    pc_for_push <= pc;
                    next_state = S_INT_0_START_SEQ;
                end else if (irq_req_in && !f[`I_FLAG_BIT]) begin
                    interrupt_pending_type_nmi <= 1'b0;
                    pc_for_push <= pc;
                    next_state = S_INT_0_START_SEQ;
                end else begin
                    mem_addr_out = pc;
                    next_state = S_DECODE;
                end
            end

            S_DECODE: begin
                cycle_count = 3'd0;
                temp_val = a;
                next_state = S_EXEC_IMPLIED;

                if (is_imm) begin mem_addr_out = pc; next_state = S_EXEC_READ; end
                else if (is_zp) begin mem_addr_out = pc; next_state = S_FETCH_ZP_ADDR; end
                else if (is_zp_x) begin mem_addr_out = pc; next_state = S_FETCH_ZP_ADDR; end
                else if (is_abs) begin mem_addr_out = pc; next_state = S_FETCH_ABS_ADL; end // Also for JMP IND initial fetch
                else if (is_abs_x) begin mem_addr_out = pc; next_state = S_CALC_ABS_X_ADL; operand_val = mem_data_in; end
                else if (is_abs_y) begin mem_addr_out = pc; next_state = S_CALC_ABS_Y_ADL; operand_val = mem_data_in; end
                else if (is_rel) begin mem_addr_out = pc; next_state = S_EXEC_BRANCH; end
                else if (is_implied || is_flags_op || // This covers accumulator RMW, transfers, stack (non-JSR/RTS), etc.
                         is_asl_a || is_lsr_a || is_rol_a || is_ror_a || // Accumulator shifts
                         is_inx || is_iny || is_dex || is_dey) begin
                    if (is_brk_op) begin
                        interrupt_pending_type_nmi <= 1'b0;
                        pc_for_push <= pc + 1;
                        next_state = S_INT_0_START_SEQ;
                    end else if (is_rti_op) begin
                        next_state = S_RTI_1_DEC_SP_POP_F;
                    end else if (is_nop_op) begin
                        next_state = S_FETCH_OPCODE;
                    end else if (is_hlt_op) begin
                        next_state = S_HALTED;
                    end else if (is_jsr_op) begin
                        mem_addr_out = pc;
                        next_state = S_JSR_FETCH_ADL;
                    end else if (is_rts_op) begin
                        mem_addr_out = sp - 1;
                        next_state = S_RTS_PULL_PCL;
                    end
                    // Transfer ops are handled in S_EXEC_IMPLIED (clocked)
                    // So S_DECODE for is_transfer_op should go to S_EXEC_IMPLIED if it's not already covered by general implied.
                    // is_implied already covers is_transfer_op.
                    // The S_DECODE part: if (is_transfer_op) next_state = S_EXEC_IMPLIED is implicitly handled.
                    else begin
                        next_state = S_EXEC_IMPLIED;
                    end
                end
                else if (is_jmp_op && opcode == `OP_JMP_ABS) begin mem_addr_out = pc; next_state = S_FETCH_ABS_ADL; end
                // Stack operations routing in S_DECODE:
                // JSR and RTS are handled above by is_jsr_op and is_rts_op checks.
                else if (is_phx_phy_op || opcode == `OP_PHA || opcode == `OP_PHP) begin // All PUSH types
                    mem_addr_out = sp; // SP points to where data will be written.
                    next_state = S_PUSH_1;
                end
                else if (is_plx_ply_op || opcode == `OP_PLA || opcode == `OP_PLP) begin // All PULL types
                    mem_addr_out = sp - 1; // SP points to *next free slot*, so item is at sp-1.
                    next_state = S_PULL_1;
                end
                else begin next_state = S_FETCH_OPCODE; end // Default fall-through if no other instruction matched
            end

            S_HALTED: begin
                if (nmi_req_in || (irq_req_in && !f[`I_FLAG_BIT])) begin
                    interrupt_pending_type_nmi <= nmi_req_in;
                    pc_for_push <= pc; // PC of HLT instruction itself, or next? Spec says PC of instruction *after* HLT.
                                       // Current PC already points to instruction *after* HLT due to S_FETCH_OPCODE increment.
                    next_state = S_INT_0_START_SEQ;
                end else begin
                    next_state = S_HALTED;
                end
            end

            S_FETCH_ZP_ADDR: begin
                if (is_zp_x) begin next_state = S_CALC_ZP_X_ADDR; end
                else if (is_rmw_op || is_bit_op) begin // RMW (ASL,LSR,ROL,ROR ZP, INC ZP, DEC ZP) & BIT ZP
                    mem_addr_out = effective_addr; // effective_addr is ZP address from previous cycle
                    if (is_rmw_op) next_state = S_RMW_FETCH_DATA; else next_state = S_EXEC_READ; // BIT ops go to S_EXEC_READ
                end else if (is_sta || is_stx || is_sty) begin // STA, STX, STY ZP
                    operand_val = (is_sta ? a : (is_stx ? x : y)); next_state = S_EXEC_WRITE;
                end else begin // LDA, LDX, LDY ZP, ADC ZP, SBC ZP, CMP ZP etc.
                    next_state = S_EXEC_READ;
                end
            end
            S_CALC_ZP_X_ADDR: begin // effective_addr is now {8'h00, base_zp_addr + x}
                if (is_rmw_op || is_bit_op) begin // RMW ZP,X (Not in spec for ASL/LSR/ROL/ROR, but INC/DEC ZP,X could exist)
                                               // BIT ZP,X not in spec.
                    mem_addr_out = effective_addr;
                    if (is_rmw_op) next_state = S_RMW_FETCH_DATA; else next_state = S_EXEC_READ;
                end else if (is_sta || is_stx || is_sty ) begin // STA ZP,X etc
                    operand_val = (is_sta ? a : (is_stx ? x : y)); next_state = S_EXEC_WRITE;
                end else { // LDA ZP,X etc
                    next_state = S_EXEC_READ;
                }
            end

            S_FETCH_ABS_ADL: begin mem_addr_out = pc; next_state = S_FETCH_ABS_ADH; end // Also for JMP IND first step
            S_FETCH_ABS_ADH: begin // effective_addr[15:8] now has ADH. PC points after ADH.
                if (is_jmp_op && !is_jmp_ind_op) begin pc <= effective_addr; next_state = S_FETCH_OPCODE; end // JMP ABS
                else if (is_jmp_ind_op) begin // JMP IND - indirect address is now in effective_addr
                    mem_addr_out = effective_addr; // Use indirect address to fetch final PCL
                    next_state = S_JMP_IND_FETCH_ADL;
                end else if (is_rmw_op || is_bit_op) begin // RMW ABS (ASL,LSR,ROL,ROR,INC,DEC) & BIT ABS
                    mem_addr_out = effective_addr;
                    if (is_rmw_op) next_state = S_RMW_FETCH_DATA; else next_state = S_EXEC_READ;
                end else if (is_sta || is_stx || is_sty) begin // STA ABS etc.
                     operand_val = (is_sta ? a : (is_stx ? x : y)); next_state = S_EXEC_WRITE;
                end else { // LDA ABS, ADC ABS etc.
                    next_state = S_EXEC_READ;
                }
            end

            S_CALC_ABS_X_ADL: begin mem_addr_out = pc; next_state = S_CALC_ABS_X_ADH; end // TODO: RMW ABS,X
            S_CALC_ABS_X_ADH: begin
                if (is_sta && !is_stx && !is_sty) { operand_val = a; next_state = S_EXEC_WRITE; }
                else if (is_stx) { operand_val = x; next_state = S_EXEC_WRITE; }
                else if (is_sty) { operand_val = y; next_state = S_EXEC_WRITE; }
                else { next_state = S_EXEC_READ; }
            end
            S_CALC_ABS_Y_ADL: begin mem_addr_out = pc; next_state = S_CALC_ABS_Y_ADH; end
            S_CALC_ABS_Y_ADH: begin
                if (is_sta && !is_stx && !is_sty) { operand_val = a; next_state = S_EXEC_WRITE; }
                else if (is_stx) { operand_val = x; next_state = S_EXEC_WRITE; }
                else if (is_sty) { operand_val = y; next_state = S_EXEC_WRITE; }
                else { next_state = S_EXEC_READ; }
            end

            S_EXEC_READ: begin
                if (is_inc || is_dec) begin
                    next_state = S_EXEC_IMPLIED;
                end else begin
                    next_state = S_EXEC_IMPLIED;
                end
            end
            S_EXEC_WRITE: next_state = S_FETCH_OPCODE;
            S_EXEC_IMPLIED: begin
                if ((is_inc || is_dec) && !(is_inx || is_iny || is_dex || is_dey) ) begin
                    mem_data_out = temp_val;
                    next_state = S_EXEC_WRITE;
                end else begin
                    next_state = S_FETCH_OPCODE;
                end
            end

            S_EXEC_BRANCH: begin
                signed_branch_offset = mem_data_in[7] ? -({1'b0, mem_data_in[6:0]}) : {1'b0, mem_data_in[6:0]};

                wire branch_condition_met;
                case (opcode)
                    `OP_BCC_REL: branch_condition_met = !f[`C_FLAG_BIT]; `OP_BCS_REL: branch_condition_met = f[`C_FLAG_BIT];
                    `OP_BEQ_REL: branch_condition_met = f[`Z_FLAG_BIT]; `OP_BNE_REL: branch_condition_met = !f[`Z_FLAG_BIT];
                    `OP_BMI_REL: branch_condition_met = f[`N_FLAG_BIT]; `OP_BPL_REL: branch_condition_met = !f[`N_FLAG_BIT];
                    `OP_BVC_REL: branch_condition_met = !f[`V_FLAG_BIT]; `OP_BVS_REL: branch_condition_met = f[`V_FLAG_BIT];
                    default: branch_condition_met = 1'b0;
                endcase

                if (branch_condition_met) begin
                    effective_addr = pc + 1 + signed_branch_offset;
                    if ((pc+1)[15:8] != effective_addr[15:8]) begin
                        next_state = S_BRANCH_PAGE_CROSS;
                    end else begin
                        next_state = S_BRANCH_TAKEN;
                    end
                end else begin
                    pc <= pc + 1;
                    next_state = S_FETCH_OPCODE;
                end
            end
            S_BRANCH_TAKEN: begin pc <= effective_addr; next_state = S_FETCH_OPCODE; end
            S_BRANCH_PAGE_CROSS: begin pc <= effective_addr; next_state = S_FETCH_OPCODE; end

            S_PUSH_1: begin // mem_addr_out was set in S_DECODE. Data for push is set in global mem_data_out.
                next_state = S_PUSH_2; // Next cycle will perform the write and sp update.
            end
            S_PUSH_2: begin // Data write occurred. SP was incremented in clocked S_PUSH_2.
                next_state = S_FETCH_OPCODE;
            end
            S_PULL_1: begin // mem_addr_out was set in S_DECODE. SP was decremented in clocked S_PULL_1.
                next_state = S_PULL_2; // Data will be in mem_data_in in S_PULL_2 cycle.
            end
            S_PULL_2: begin // Data is being read from stack.
                next_state = S_PULL_3;
            end
            S_PULL_3: begin
                next_state = S_FETCH_OPCODE;
            end

            // RMW states (combinational part)
            S_RMW_FETCH_DATA: begin // Data being fetched into 'data_for_rmw' (clocked)
                next_state = S_RMW_EXECUTE;
            end
            S_RMW_EXECUTE: begin
                reg [7:0] result_val_rmw;
                reg       f_temp_c_rmw;
                // Calculate result and new carry based on 'data_for_rmw' (which has mem_data_in from previous cycle)
                case (opcode)
                    `OP_ASL_ZP:  begin f_temp_c_rmw = data_for_rmw[7]; result_val_rmw = data_for_rmw << 1; end
                    `OP_ASL_ABS: begin f_temp_c_rmw = data_for_rmw[7]; result_val_rmw = data_for_rmw << 1; end
                    `OP_LSR_ZP:  begin f_temp_c_rmw = data_for_rmw[0]; result_val_rmw = data_for_rmw >> 1; end
                    `OP_LSR_ABS: begin f_temp_c_rmw = data_for_rmw[0]; result_val_rmw = data_for_rmw >> 1; end
                    `OP_ROL_ZP:  begin f_temp_c_rmw = data_for_rmw[7]; result_val_rmw = {data_for_rmw[6:0], f[`C_FLAG_BIT]}; end
                    // ROL ABS not in spec
                    `OP_ROR_ZP:  begin f_temp_c_rmw = data_for_rmw[0]; result_val_rmw = {f[`C_FLAG_BIT], data_for_rmw[7:1]}; end
                    // ROR ABS not in spec
                    `OP_INC_ZP:  begin result_val_rmw = data_for_rmw + 1; f_temp_c_rmw = f[`C_FLAG_BIT]; end // INC doesn't change C
                    `OP_INC_ABS: begin result_val_rmw = data_for_rmw + 1; f_temp_c_rmw = f[`C_FLAG_BIT]; end
                    `OP_DEC_ZP:  begin result_val_rmw = data_for_rmw - 1; f_temp_c_rmw = f[`C_FLAG_BIT]; end // DEC doesn't change C
                    `OP_DEC_ABS: begin result_val_rmw = data_for_rmw - 1; f_temp_c_rmw = f[`C_FLAG_BIT]; end
                    default:     begin result_val_rmw = data_for_rmw; f_temp_c_rmw = f[`C_FLAG_BIT]; end // Should not happen
                endcase
                // These assignments will be used by the clocked S_RMW_EXECUTE to update flags and mem_data_out
                data_for_rmw = result_val_rmw; // Pass result to clocked block via data_for_rmw
                c_for_rmw = f_temp_c_rmw;       // Pass new carry to clocked block via c_for_rmw

                mem_addr_out = effective_addr; // Ensure address is still effective_addr for write back
                next_state = S_RMW_WRITE_BACK;
            end
            S_RMW_WRITE_BACK: begin
                next_state = S_FETCH_OPCODE;
            end

            // JMP IND states (combinational part)
            S_JMP_IND_FETCH_ADL: begin // PCL of final address is being fetched
                mem_addr_out = effective_addr; // Use incremented address for ADH fetch
                next_state = S_JMP_IND_FETCH_ADH;
            end
            S_JMP_IND_FETCH_ADH: begin // PCH of final address is being fetched
                // PC is updated in clocked block.
                next_state = S_FETCH_OPCODE;
            end

            // JSR states (combinational part)
            S_JSR_FETCH_ADL: begin
                mem_addr_out = pc; // For fetching ADH
                next_state = S_JSR_FETCH_ADH;
            end
            S_JSR_FETCH_ADH: begin
                mem_data_out = pc_for_push[15:8]; // pc_for_push was set in clocked S_JSR_FETCH_ADH
                mem_addr_out = sp;
                next_state = S_JSR_PUSH_RET_PCH;
            end
            S_JSR_PUSH_RET_PCH: begin
                mem_data_out = pc_for_push[7:0]; // pc_for_push from clocked S_JSR_FETCH_ADH
                mem_addr_out = sp; // sp was incremented in clocked S_JSR_PUSH_RET_PCH for PCH write
                next_state = S_JSR_PUSH_RET_PCL;
            end
            S_JSR_PUSH_RET_PCL: begin
                next_state = S_FETCH_OPCODE; // pc will be set to effective_addr in clocked S_JSR_PUSH_RET_PCL
            end

            // RTS States (combinational part)
            S_RTS_PULL_PCL: begin
                // effective_addr[7:0] gets mem_data_in in clocked S_RTS_PULL_PCL
                // sp is decremented in clocked S_RTS_PULL_PCL
                // mem_addr_out for PCH read uses the *new* sp value.
                mem_addr_out = sp - 1; // SP in this expression is the new SP after PCL pull's decrement.
                next_state = S_RTS_PULL_PCH;
            end
            S_RTS_PULL_PCH: begin
                // effective_addr[15:8] gets mem_data_in in clocked S_RTS_PULL_PCH
                // No SP change in clocked S_RTS_PULL_PCH as per spec point 5.
                next_state = S_RTS_INC_PC;
            end
            S_RTS_INC_PC: begin
                // pc gets effective_addr + 1 in clocked S_RTS_INC_PC
                next_state = S_FETCH_OPCODE;
            end

            // Interrupt Handling States
            S_INT_0_START_SEQ: begin // Cycle 1 of 7
                mem_addr_out = sp;
                // flags_to_push_on_stack = f | (1<<`B_FLAG_BIT) | (1<<5); // Old logic
                // mem_data_out for PCH is set by global assignment based on current_state & next_state
                next_state = S_INT_1_PUSH_PCH;
            end
            S_INT_1_PUSH_PCH: begin // Cycle 2
                mem_addr_out = sp;
                // mem_data_out for PCL is set by global assignment
                next_state = S_INT_2_PUSH_PCL;
            end
            S_INT_2_PUSH_PCL: begin // Cycle 3
                mem_addr_out = sp;
                // mem_data_out for SR is set by global assignment
                next_state = S_INT_3_PUSH_F;
            end
            S_INT_3_PUSH_F: begin   // Cycle 4
                interrupt_vector_addr_base = (interrupt_pending_type_nmi && !is_brk_op) ? `NMI_VECTOR_ADDR_LOW : `IRQ_BRK_VECTOR_ADDR_LOW;
                mem_addr_out = interrupt_vector_addr_base;
                next_state = S_INT_4_FETCH_ADL;
            end
            S_INT_4_FETCH_ADL: begin // Cycle 5
                mem_addr_out = interrupt_vector_addr_base + 1;
                next_state = S_INT_5_FETCH_ADH;
            end
            S_INT_5_FETCH_ADH: begin // Cycle 6
                                     // Cycle 7 will be S_FETCH_OPCODE of ISR
                next_state = S_FETCH_OPCODE;
            end

            // RTI handling
            S_RTI_1_DEC_SP_POP_F: begin // Cycle 1&2 (SP dec, mem read)
                sp <= sp - 1;
                mem_addr_out = sp - 1;
                next_state = S_RTI_2_DEC_SP_POP_PCL;
            end
            S_RTI_2_DEC_SP_POP_PCL: begin // Cycle 3&4
                sp <= sp - 1;
                mem_addr_out = sp - 1;
                next_state = S_RTI_3_DEC_SP_POP_PCH;
            end
            S_RTI_3_DEC_SP_POP_PCH: begin // Cycle 5&6
                sp <= sp - 1;
                mem_addr_out = sp -1;
                next_state = S_FETCH_OPCODE;
            end

            default: next_state = S_RESET_0;
        endcase
        // Ensure memory enables are low if halted, overriding other conditions
        if (current_state == S_HALTED) begin
            mem_rd_en = 1'b0;
            mem_wr_en = 1'b0;
        end
    end

    // --- Instruction type and addressing mode decoding ---
    assign is_lda = (opcode == `OP_LDA_IMM) || (opcode == `OP_LDA_ZP)  || (opcode == `OP_LDA_ZP_X) ||
                    (opcode == `OP_LDA_ABS) || (opcode == `OP_LDA_ABS_X) || (opcode == `OP_LDA_ABS_Y);
    assign is_ldx = (opcode == `OP_LDX_IMM) || (opcode == `OP_LDX_ZP);
    assign is_ldy = (opcode == `OP_LDY_IMM) || (opcode == `OP_LDY_ZP);
    assign is_sta = (opcode == `OP_STA_ZP)  || (opcode == `OP_STA_ZP_X) || (opcode == `OP_STA_ABS) ||
                    (opcode == `OP_STA_ABS_X) || (opcode == `OP_STA_ABS_Y);
    assign is_stx = (opcode == `OP_STX_ZP);
    assign is_sty = (opcode == `OP_STY_ZP);
    assign is_adc = (opcode == `OP_ADC_IMM) || (opcode == `OP_ADC_ZP) || (opcode == `OP_ADC_ABS);
    assign is_sbc = (opcode == `OP_SBC_IMM) || (opcode == `OP_SBC_ZP) || (opcode == `OP_SBC_ABS);
    assign is_inc = (opcode == `OP_INC_ZP) || (opcode == `OP_INC_ABS);
    assign is_dec = (opcode == `OP_DEC_ZP) || (opcode == `OP_DEC_ABS);
    assign is_inx = (opcode == `OP_INX); assign is_iny = (opcode == `OP_INY);
    assign is_dex = (opcode == `OP_DEX); assign is_dey = (opcode == `OP_DEY);
    assign is_and = (opcode == `OP_AND_IMM) || (opcode == `OP_AND_ZP) || (opcode == `OP_AND_ABS);
    assign is_ora = (opcode == `OP_ORA_IMM) || (opcode == `OP_ORA_ZP) || (opcode == `OP_ORA_ABS);
    assign is_eor = (opcode == `OP_EOR_IMM) || (opcode == `OP_EOR_ZP) || (opcode == `OP_EOR_ABS);
    assign is_asl_a = (opcode == `OP_ASL_A); assign is_lsr_a = (opcode == `OP_LSR_A);
    assign is_rol_a = (opcode == `OP_ROL_A); assign is_ror_a = (opcode == `OP_ROR_A);
    assign is_flags_op = (opcode == `OP_CLC) || (opcode == `OP_SEC) || (opcode == `OP_CLI) ||
                         (opcode == `OP_SEI) || (opcode == `OP_CLV) ||
                         (opcode == `OP_CLD) || (opcode == `OP_SED);
    assign is_compare_op = (opcode == `OP_CMP_IMM) || (opcode == `OP_CMP_ZP) || (opcode == `OP_CMP_ABS) ||
                           (opcode == `OP_CPX_IMM) || (opcode == `OP_CPX_ZP) ||
                           (opcode == `OP_CPY_IMM) || (opcode == `OP_CPY_ZP);
    assign is_branch_op = (opcode == `OP_BCC_REL) || (opcode == `OP_BCS_REL) || (opcode == `OP_BEQ_REL) ||
                          (opcode == `OP_BNE_REL) || (opcode == `OP_BMI_REL) || (opcode == `OP_BPL_REL) ||
                          (opcode == `OP_BVC_REL) || (opcode == `OP_BVS_REL);
    assign is_stack_op = (opcode == `OP_PHA) || (opcode == `OP_PLA) || (opcode == `OP_PHP) || (opcode == `OP_PLP) ||
                         (opcode == `OP_PHX_IMP) || (opcode == `OP_PHY_IMP) || (opcode == `OP_PLX_IMP) || (opcode == `OP_PLY_IMP) ||
                         (opcode == `OP_JSR_ABS) || (opcode == `OP_RTS_IMP); // JSR/RTS are stack related
    assign is_jmp_op = (opcode == `OP_JMP_ABS);
    assign is_jsr_op = (opcode == `OP_JSR_ABS);
    assign is_rts_op = (opcode == `OP_RTS_IMP);
    assign is_transfer_op = (opcode == `OP_TAX_IMP) || (opcode == `OP_TAY_IMP) || (opcode == `OP_TSX_IMP) ||
                            (opcode == `OP_TXA_IMP) || (opcode == `OP_TXS_IMP) || (opcode == `OP_TYA_IMP);
    assign is_phx_phy_op = (opcode == `OP_PHX_IMP) || (opcode == `OP_PHY_IMP);
    assign is_plx_ply_op = (opcode == `OP_PLX_IMP) || (opcode == `OP_PLY_IMP);
    assign is_hlt_op = (opcode == `OP_HLT_IMP);
    assign is_nop_op = (opcode == `OP_NOP) || (opcode == `OP_CLD) || (opcode == `OP_SED); // HLT is not a NOP anymore
    assign is_rti_op = (opcode == `OP_RTI);
    assign is_brk_op = (opcode == `OP_BRK);

    // Phase 2 instruction helper assignments
    assign is_asl_mem_op = (opcode == `OP_ASL_ZP) || (opcode == `OP_ASL_ABS);
    assign is_lsr_mem_op = (opcode == `OP_LSR_ZP) || (opcode == `OP_LSR_ABS);
    assign is_rol_mem_op = (opcode == `OP_ROL_ZP); // ROL ABS not in spec
    assign is_ror_mem_op = (opcode == `OP_ROR_ZP); // ROR ABS not in spec
    assign is_rmw_op = is_asl_mem_op || is_lsr_mem_op || is_rol_mem_op || is_ror_mem_op ||
                       (is_inc && (is_zp || is_abs)) || // INC ZP, INC ABS
                       (is_dec && (is_zp || is_abs));   // DEC ZP, DEC ABS
    assign is_bit_op = (opcode == `OP_BIT_ZP) || (opcode == `OP_BIT_ABS);
    assign is_jmp_ind_op = (opcode == `OP_JMP_IND);


    assign is_imm = (opcode == `OP_LDA_IMM) || (opcode == `OP_LDX_IMM) || (opcode == `OP_LDY_IMM) ||
                    (opcode == `OP_ADC_IMM) || (opcode == `OP_SBC_IMM) ||
                    (opcode == `OP_AND_IMM) || (opcode == `OP_ORA_IMM) || (opcode == `OP_EOR_IMM) ||
                    (opcode == `OP_CMP_IMM) || (opcode == `OP_CPX_IMM) || (opcode == `OP_CPY_IMM);
    assign is_zp = (opcode == `OP_LDA_ZP)  || (opcode == `OP_LDX_ZP)  || (opcode == `OP_LDY_ZP) ||
                   (opcode == `OP_STA_ZP)  || (opcode == `OP_STX_ZP)  || (opcode == `OP_STY_ZP) ||
                   (opcode == `OP_ADC_ZP)  || (opcode == `OP_SBC_ZP)  || (opcode == `OP_INC_ZP) || (opcode == `OP_DEC_ZP) ||
                   (opcode == `OP_AND_ZP)  || (opcode == `OP_ORA_ZP)  || (opcode == `OP_EOR_ZP) ||
                   (opcode == `OP_CMP_ZP)  || (opcode == `OP_CPX_ZP)  || (opcode == `OP_CPY_ZP);
    assign is_zp_x = (opcode == `OP_LDA_ZP_X) || (opcode == `OP_STA_ZP_X);
    assign is_abs = (opcode == `OP_LDA_ABS) || (opcode == `OP_STA_ABS) || (opcode == `OP_JMP_ABS) ||
                    (opcode == `OP_ADC_ABS) || (opcode == `OP_SBC_ABS) || (opcode == `OP_INC_ABS) || (opcode == `OP_DEC_ABS) ||
                    (opcode == `OP_AND_ABS) || (opcode == `OP_ORA_ABS) || (opcode == `OP_EOR_ABS) ||
                    (opcode == `OP_CMP_ABS) || (opcode == `OP_ASL_ABS) || (opcode == `OP_LSR_ABS) || (opcode == `OP_BIT_ABS); // Added Phase 2 ops
    assign is_abs_x = (opcode == `OP_LDA_ABS_X) || (opcode == `OP_STA_ABS_X);
    assign is_abs_y = (opcode == `OP_LDA_ABS_Y) || (opcode == `OP_STA_ABS_Y);
    assign is_ind = (opcode == `OP_JMP_IND);
    assign is_implied = (opcode == `OP_INX) || (opcode == `OP_INY) || (opcode == `OP_DEX) || (opcode == `OP_DEY) ||
                        (opcode == `OP_ASL_A) || (opcode == `OP_LSR_A) || (opcode == `OP_ROL_A) || (opcode == `OP_ROR_A) ||
                        is_flags_op || is_stack_op || is_nop_op || is_rti_op || is_brk_op || is_rts_op || is_transfer_op || is_hlt_op ||
                        is_phx_phy_op || is_plx_ply_op; // PHX/PHY/PLX/PLY are implied. RMW ops on memory are not implied.
    assign is_rel = is_branch_op;

    // Helper for JSR PCH push state to precalculate value based on current PC (which is pointing at ADH byte)
    // wire [15:0] pc_for_push_calc_in_decode = pc; // REMOVED - This was not used correctly. pc_for_push register is sufficient.

    localparam B_FLAG_BIT_VALUE_AFTER_RESET = 1'b0;
    localparam I_FLAG_BIT_VALUE_AFTER_RESET = 1'b1;
    localparam UNUSED_FLAG_BIT_5_VALUE = 1'b1;

endmodule
