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

    reg [5:0] current_state;
    reg [5:0] next_state;

    reg [2:0] cycle_count;
    reg         interrupt_pending_type_nmi;
    reg [15:0]  interrupt_vector_addr_base;
    reg [7:0]   flags_to_push_on_stack;
    reg [15:0]  pc_for_push;

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

    // Addressing mode indicators
    wire is_imm, is_zp, is_zp_x, is_abs, is_abs_x, is_abs_y, is_implied, is_rel;

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
            sp <= 16'h0100;
            a  <= 8'h00;
            x  <= 8'h00;
            y  <= 8'h00;
            f  <= {1'b0, 1'b0, `UNUSED_FLAG_BIT_5_VALUE, 1'b0 /*B on reset*/, 1'b0, `I_FLAG_BIT_VALUE_AFTER_RESET, 1'b0, 1'b0};
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
                           (current_state == S_RESET_2 && next_state == S_RESET_3)
                           );

            mem_wr_en <= (next_state == S_EXEC_WRITE ||
                           next_state == S_PUSH_2 || // PHA, PHP
                           // Writes for interrupt stack push
                           current_state == S_INT_0_START_SEQ ||
                           current_state == S_INT_1_PUSH_PCH  ||
                           current_state == S_INT_2_PUSH_PCL
                           );

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

                S_EXEC_IMPLIED: begin
                    if (is_lda) begin a <= operand_val; set_nz_flags(operand_val); end
                    if (is_ldx) begin x <= operand_val; set_nz_flags(operand_val); end
                    if (is_ldy) begin y <= operand_val; set_nz_flags(operand_val); end
                    if (is_adc) begin temp_val = a; {f[`C_FLAG_BIT], a} = a + operand_val + f[`C_FLAG_BIT]; f[`V_FLAG_BIT] = (~(temp_val[7] ^ operand_val[7]) & (temp_val[7] ^ a[7])); set_nz_flags(a); end
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
                S_PUSH_1: ;
                S_PUSH_2: sp <= sp + 1;
                S_PULL_1: ;
                S_PULL_2: ;
                S_PULL_3: begin
                    if (opcode == `OP_PLA) begin a <= mem_data_in; set_nz_flags(mem_data_in); end
                    if (opcode == `OP_PLP) begin
                        f <= (mem_data_in & ~((1<<`B_FLAG_BIT) | (1<<5))) | (f & ((1<<`B_FLAG_BIT) | (1<<5)));
                    end
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
                    f <= (mem_data_in & ~((1<<`B_FLAG_BIT) | (1<<5))) | (f & ((1<<`B_FLAG_BIT) | (1<<5)));
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
        mem_data_out = (is_sta && !is_stx && !is_sty) ? a :
                       (is_stx) ? x :
                       (is_sty) ? y :
                       ((is_inc || is_dec) && !is_inx && !is_iny && !is_dex && !is_dey) ? temp_val :
                       (opcode == `OP_PHA) ? a :
                       (opcode == `OP_PHP) ? (f | (1<<`B_FLAG_BIT) | (1<<5)) :
                       8'h00;

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
                else if (is_abs) begin mem_addr_out = pc; next_state = S_FETCH_ABS_ADL; end
                else if (is_abs_x) begin mem_addr_out = pc; next_state = S_CALC_ABS_X_ADL; operand_val = mem_data_in; end
                else if (is_abs_y) begin mem_addr_out = pc; next_state = S_CALC_ABS_Y_ADL; operand_val = mem_data_in; end
                else if (is_rel) begin mem_addr_out = pc; next_state = S_EXEC_BRANCH; end
                else if (is_implied || is_flags_op ||
                         is_asl_a || is_lsr_a || is_rol_a || is_ror_a ||
                         is_inx || is_iny || is_dex || is_dey) begin // General implied ops
                    if (is_brk_op) begin
                        interrupt_pending_type_nmi <= 1'b0;
                        pc_for_push <= pc + 1;
                        next_state = S_INT_0_START_SEQ;
                    end else if (is_rti_op) begin
                        next_state = S_RTI_1_DEC_SP_POP_F;
                    end else if (is_nop_op) begin
                        next_state = S_FETCH_OPCODE;
                    end
                    else begin
                        next_state = S_EXEC_IMPLIED;
                    end
                end
                else if (is_jmp_op && opcode == `OP_JMP_ABS) begin mem_addr_out = pc; next_state = S_FETCH_ABS_ADL; end
                else if (is_stack_op) begin
                    case(opcode)
                        `OP_PHA: next_state = S_PUSH_1; `OP_PHP: next_state = S_PUSH_1;
                        `OP_PLA: next_state = S_PULL_1; `OP_PLP: next_state = S_PULL_1;
                    endcase
                end
                else begin next_state = S_FETCH_OPCODE; end
            end

            S_FETCH_ZP_ADDR: begin
                if (is_zp_x) begin next_state = S_CALC_ZP_X_ADDR;
                end else begin
                    if (is_sta || is_stx || is_sty || is_inc || is_dec) begin
                        if(is_sta || is_stx || is_sty) begin operand_val = (is_sta ? a : (is_stx ? x : y)); next_state = S_EXEC_WRITE; end
                        else { next_state = S_EXEC_READ; }
                    end else begin next_state = S_EXEC_READ; end
                end
            end
            S_CALC_ZP_X_ADDR: begin
                if (is_sta || is_stx || is_sty || is_inc || is_dec) begin
                    if(is_sta || is_stx || is_sty) { operand_val = (is_sta ? a : (is_stx ? x : y)); next_state = S_EXEC_WRITE; }
                    else { next_state = S_EXEC_READ; }
                end else { next_state = S_EXEC_READ; }
            end

            S_FETCH_ABS_ADL: begin mem_addr_out = pc; next_state = S_FETCH_ABS_ADH; end
            S_FETCH_ABS_ADH: begin
                if (is_jmp_op) begin pc <= effective_addr; next_state = S_FETCH_OPCODE; end
                else if (is_sta || is_stx || is_sty || is_inc || is_dec) begin
                     if(is_sta || is_stx || is_sty) { operand_val = (is_sta ? a : (is_stx ? x : y)); next_state = S_EXEC_WRITE; }
                     else { next_state = S_EXEC_READ; }
                end else { next_state = S_EXEC_READ; }
            end

            S_CALC_ABS_X_ADL: begin mem_addr_out = pc; next_state = S_CALC_ABS_X_ADH; end
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

            S_PUSH_1: begin mem_addr_out = sp; next_state = S_PUSH_2; end
            S_PUSH_2: next_state = S_FETCH_OPCODE;
            S_PULL_1: begin sp <= sp - 1; mem_addr_out = sp - 1; next_state = S_PULL_2; end
            S_PULL_2: next_state = S_PULL_3;
            S_PULL_3: next_state = S_FETCH_OPCODE;

            // Interrupt Handling States
            S_INT_0_START_SEQ: begin // Cycle 1 of 7
                mem_addr_out = sp;
                flags_to_push_on_stack = f | (1<<`B_FLAG_BIT) | (1<<5);
                mem_data_out = pc_for_push[15:8]; // PCH
                next_state = S_INT_1_PUSH_PCH;
            end
            S_INT_1_PUSH_PCH: begin // Cycle 2
                mem_addr_out = sp; // SP was already incremented in clocked part of S_INT_1
                mem_data_out = pc_for_push[7:0];   // PCL
                next_state = S_INT_2_PUSH_PCL;
            end
            S_INT_2_PUSH_PCL: begin // Cycle 3
                mem_addr_out = sp; // SP was already incremented
                mem_data_out = flags_to_push_on_stack;
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
    assign is_stack_op = (opcode == `OP_PHA) || (opcode == `OP_PLA) || (opcode == `OP_PHP) || (opcode == `OP_PLP);
    assign is_jmp_op = (opcode == `OP_JMP_ABS);
    assign is_nop_op = (opcode == `OP_NOP) || (opcode == `OP_CLD) || (opcode == `OP_SED) || (opcode == `OP_HLT`);
    assign is_rti_op = (opcode == `OP_RTI);
    assign is_brk_op = (opcode == `OP_BRK);

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
                    (opcode == `OP_CMP_ABS);
    assign is_abs_x = (opcode == `OP_LDA_ABS_X) || (opcode == `OP_STA_ABS_X);
    assign is_abs_y = (opcode == `OP_LDA_ABS_Y) || (opcode == `OP_STA_ABS_Y);
    assign is_implied = (opcode == `OP_INX) || (opcode == `OP_INY) || (opcode == `OP_DEX) || (opcode == `OP_DEY) ||
                        (opcode == `OP_ASL_A) || (opcode == `OP_LSR_A) || (opcode == `OP_ROL_A) || (opcode == `OP_ROR_A) ||
                        is_flags_op || is_stack_op || is_nop_op || is_rti_op || is_brk_op;
    assign is_rel = is_branch_op;

    localparam B_FLAG_BIT_VALUE_AFTER_RESET = 1'b0;
    localparam I_FLAG_BIT_VALUE_AFTER_RESET = 1'b1;
    localparam UNUSED_FLAG_BIT_5_VALUE = 1'b1;

endmodule
