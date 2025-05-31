// FCVM/fc8_defines.v

// Memory Map Addresses
`define FIXED_RAM_BASE  32'h00000000 // Fixed RAM block
`define SFR_PAGE_BASE   32'h000000FE // Special Function Registers (PAGE_SELECT_REG is here)
`define CART_ROM_LOGICAL_BASE 16'h8000

// Initial Cartridge Physical Base for Page 6 (as per spec)
`define CART_ROM_PHYSICAL_PAGE_6_BASE 32'h00030000

// CPU Reset Vector (Logical Address)
`define RESET_VECTOR_ADDR_LOW  16'hFFFC
`define RESET_VECTOR_ADDR_HIGH 16'hFFFD
`define CPU_DEFAULT_ENTRY_POINT 16'h8000 // Default logical entry point after reset

// Cartridge Header Defines
`define CART_HEADER_MAGIC_0         8'h46 // 'F'
`define CART_HEADER_MAGIC_1         8'h43 // 'C'
`define CART_HEADER_MAGIC_2         8'h38 // '8'
`define CART_HEADER_MAGIC_3         8'h43 // 'C'
`define CART_HEADER_ENTRY_POINT_L   (`CPU_DEFAULT_ENTRY_POINT & 8'hFF)
`define CART_HEADER_ENTRY_POINT_H   ((`CPU_DEFAULT_ENTRY_POINT >> 8) & 8'hFF)
`define CART_HEADER_INIT_PAGE_SELECT 8'h06 // Initial page select (Page 6)

// MMU Related
`define PAGE_SELECT_REG_ADDR 16'h00FE
`define FIXED_RAM_SIZE_BYTES 32768 // 32KB
`define FIXED_RAM_ADDR_MASK  15'h7FFF // Mask for 32KB address space

// Cart ROM size for initial testing (will be 832KB later)
`define CART_ROM_PAGE_SIZE_BYTES 32768 // 32KB for now
`define CART_ROM_PAGE_ADDR_MASK 15'h7FFF

// --- Flag Register Bits (Processor Status Register P) ---
// FC8 uses standard 6502-like flags
// Bit:  7 6 5 4 3 2 1 0
// Flag: N V - B D I Z C
// Note: Bit 5 is often shown as '1' or unused, Bit 4 is Break flag.
`define N_FLAG_BIT 7 // Negative
`define V_FLAG_BIT 6 // Overflow
`define B_FLAG_BIT 4 // Break Command
`define D_FLAG_BIT 3 // Decimal Mode (Not used in FC8, NOP for SED/CLD)
`define I_FLAG_BIT 2 // Interrupt Disable
`define Z_FLAG_BIT 1 // Zero
`define C_FLAG_BIT 0 // Carry

// --- Instruction Opcodes ---
// Existing
`define OP_NOP      8'hEA // NOP

// Load Accumulator
`define OP_LDA_IMM  8'hA9 // LDA #$val
`define OP_LDA_ZP   8'hA5 // LDA $zp
`define OP_LDA_ZP_X 8'hB5 // LDA $zp,X
`define OP_LDA_ABS  8'hAD // LDA $abs
`define OP_LDA_ABS_X 8'hBD // LDA $abs,X
`define OP_LDA_ABS_Y 8'hB9 // LDA $abs,Y
// `define OP_LDA_IND_X 8'hA1 // LDA ($ind,X) - Not requested yet
// `define OP_LDA_IND_Y 8'hB1 // LDA ($ind),Y - Not requested yet

// Store Accumulator
`define OP_STA_ZP   8'h85 // STA $zp
`define OP_STA_ZP_X 8'h95 // STA $zp,X
`define OP_STA_ABS  8'h8D // STA $abs
`define OP_STA_ABS_X 8'h9D // STA $abs,X
`define OP_STA_ABS_Y 8'h99 // STA $abs,Y
// `define OP_STA_IND_X 8'h81 // STA ($ind,X) - Not requested yet
// `define OP_STA_IND_Y 8'h91 // STA ($ind),Y - Not requested yet

// Load Index X
`define OP_LDX_IMM  8'hA2 // LDX #$val
`define OP_LDX_ZP   8'hA6 // LDX $zp
// `define OP_LDX_ZP_Y 8'hB6 // LDX $zp,Y - Not requested yet
// `define OP_LDX_ABS  8'hAE // LDX $abs - Not requested yet
// `define OP_LDX_ABS_Y 8'hBE // LDX $abs,Y - Not requested yet

// Store Index X
`define OP_STX_ZP   8'h86 // STX $zp
// `define OP_STX_ZP_Y 8'h96 // STX $zp,Y - Not requested yet
// `define OP_STX_ABS  8'h8E // STX $abs - Not requested yet

// Load Index Y
`define OP_LDY_IMM  8'hA0 // LDY #$val
`define OP_LDY_ZP   8'hA4 // LDY $zp
// `define OP_LDY_ZP_X 8'hB4 // LDY $zp,X - Not requested yet
// `define OP_LDY_ABS  8'hAC // LDY $abs - Not requested yet
// `define OP_LDY_ABS_X 8'hBC // LDY $abs,X - Not requested yet

// Store Index Y
`define OP_STY_ZP   8'h84 // STY $zp
// `define OP_STY_ZP_X 8'h94 // STY $zp,X - Not requested yet
// `define OP_STY_ABS  8'h8C // STY $abs - Not requested yet

// Arithmetic
`define OP_ADC_IMM  8'h69 // ADC #$val
`define OP_ADC_ZP   8'h65 // ADC $zp
`define OP_ADC_ABS  8'h6D // ADC $abs
// ... other ADC addressing modes if needed

`define OP_SBC_IMM  8'hE9 // SBC #$val
`define OP_SBC_ZP   8'hE5 // SBC $zp
`define OP_SBC_ABS  8'hED // SBC $abs
// ... other SBC addressing modes if needed

`define OP_INC_ZP   8'hE6 // INC $zp
`define OP_INC_ABS  8'hEE // INC $abs
`define OP_DEC_ZP   8'hC6 // DEC $zp
`define OP_DEC_ABS  8'hCE // DEC $abs
`define OP_INX      8'hE8 // INX
`define OP_INY      8'hC8 // INY
`define OP_DEX      8'hCA // DEX
`define OP_DEY      8'h88 // DEY

// Logical
`define OP_AND_IMM  8'h29 // AND #$val
`define OP_AND_ZP   8'h25 // AND $zp
`define OP_AND_ABS  8'h2D // AND $abs

`define OP_ORA_IMM  8'h09 // ORA #$val
`define OP_ORA_ZP   8'h05 // ORA $zp
`define OP_ORA_ABS  8'h0D // ORA $abs

`define OP_EOR_IMM  8'h49 // EOR #$val
`define OP_EOR_ZP   8'h45 // EOR $zp
`define OP_EOR_ABS  8'h4D // EOR $abs

// Shifts/Rotates (Accumulator)
`define OP_ASL_A    8'h0A // ASL A
`define OP_LSR_A    8'h4A // LSR A
`define OP_ROL_A    8'h2A // ROL A
`define OP_ROR_A    8'h6A // ROR A

// Flag Manipulation
`define OP_CLC      8'h18 // CLC
`define OP_SEC      8'h38 // SEC
`define OP_CLI      8'h58 // CLI
`define OP_SEI      8'h78 // SEI
`define OP_CLV      8'hB8 // CLV
`define OP_CLD      8'hD8 // CLD (NOP in FC8)
`define OP_SED      8'hF8 // SED (NOP in FC8)

// Comparisons
`define OP_CMP_IMM  8'hC9 // CMP #$val
`define OP_CMP_ZP   8'hC5 // CMP $zp
`define OP_CMP_ABS  8'hCD // CMP $abs

`define OP_CPX_IMM  8'hE0 // CPX #$val
`define OP_CPX_ZP   8'hE4 // CPX $zp
// `define OP_CPX_ABS  8'hEC // CPX $abs - Not requested yet

`define OP_CPY_IMM  8'hC0 // CPY #$val
`define OP_CPY_ZP   8'hC4 // CPY $zp
// `define OP_CPY_ABS  8'hCC // CPY $abs - Not requested yet

// Branching (Conditional)
`define OP_BCC_REL  8'h90 // BCC relative
`define OP_BCS_REL  8'hB0 // BCS relative
`define OP_BEQ_REL  8'hF0 // BEQ relative
`define OP_BNE_REL  8'hD0 // BNE relative
`define OP_BMI_REL  8'h30 // BMI relative
`define OP_BPL_REL  8'h10 // BPL relative
`define OP_BVC_REL  8'h50 // BVC relative
`define OP_BVS_REL  8'h70 // BVS relative

// Jump / Subroutine
`define OP_JMP_ABS  8'h4C // JMP $abs
// `define OP_JMP_IND  8'h6C // JMP ($ind) - Not requested yet
`define OP_JSR_ABS  8'h20 // JSR $abs
`define OP_RTS_IMP  8'h60 // RTS

// Stack Operations
`define OP_PHA      8'h48 // PHA (Push Accumulator)
`define OP_PLA      8'h68 // PLA (Pull Accumulator)
`define OP_PHP      8'h08 // PHP (Push Processor Status)
`define OP_PLP      8'h28 // PLP (Pull Processor Status)

// System
`define OP_BRK      8'h00 // BRK (Force Interrupt)
`define OP_RTI      8'h40 // RTI (Return from Interrupt)
// `define OP_HLT      8'h02 // HLT (Halt CPU - not fully implemented yet, treat as NOP for now) // Will be replaced

// New Opcodes for Phase 1
// `define OP_JSR_ABS  8'h20 // Already defined above
// `define OP_RTS_IMP  8'h60 // Already defined above
`define OP_TAX_IMP  8'hAA
`define OP_TAY_IMP  8'hA8
`define OP_TSX_IMP  8'hBA
`define OP_TXA_IMP  8'h8A
`define OP_TXS_IMP  8'h9A
`define OP_TYA_IMP  8'h98
`define OP_PHX_IMP  8'hDA
`define OP_PHY_IMP  8'h5A
`define OP_PLX_IMP  8'hFA
`define OP_PLY_IMP  8'h7A
`define OP_HLT_IMP  8'h02

// New Opcodes for Phase 2
`define OP_ASL_ZP   8'h06
`define OP_ASL_ABS  8'h0E
`define OP_LSR_ZP   8'h46
`define OP_LSR_ABS  8'h4E
`define OP_ROL_ZP   8'h26
// ROL ABS is not in spec table
`define OP_ROR_ZP   8'h66
// ROR ABS is not in spec table
`define OP_BIT_ZP   8'h24
`define OP_BIT_ABS  8'h2C
`define OP_JMP_IND  8'h6C


// --- Interrupt Vectors ---
`define NMI_VECTOR_ADDR_LOW    16'hFFFA
`define NMI_VECTOR_ADDR_HIGH   16'hFFFB
`define IRQ_BRK_VECTOR_ADDR_LOW 16'hFFF8
`define IRQ_BRK_VECTOR_ADDR_HIGH 16'hFFF9
// Reset vector is already defined: `RESET_VECTOR_ADDR_LOW` 16'hFFFC, `RESET_VECTOR_ADDR_HIGH` 16'hFFFD


// --- SFR Addresses ---
// These are offsets within the SFR physical page ($020000 - $027FFF for page 4)
// Or, if accessed via a different mechanism, their full physical addresses.
// For now, assume they are offsets from the start of the SFR page selected by MMU.

// Page 4 SFRs (Physical Base $020000)
// Screen Bounding Offsets (256 bytes)
`define SCREEN_BOUND_OFFSET_BASE_ADDR 16'h0000 // Relative to SFR page start ($020000)
                                            // Accesses are e.g. $020000 to $0200FF
`define VRAM_FLAGS_REG_ADDR         16'h0100 // $020100
`define VRAM_SCROLL_X_REG_ADDR      16'h0101 // $020101
`define VRAM_SCROLL_Y_REG_ADDR      16'h0102 // $020102

`define GAMEPAD1_STATE_REG_ADDR     16'h0600 // $020600
`define GAMEPAD2_STATE_REG_ADDR     16'h0601 // $020601
`define INPUT_STATUS_REG_ADDR       16'h0602 // $020602

`define SCREEN_CTRL_REG_ADDR        16'h0800 // $020800
`define PALETTE_ADDR_REG_ADDR       16'h0810 // $020810
`define PALETTE_DATA_REG_ADDR       16'h0811 // $020811
`define FRAME_COUNT_LO_REG_ADDR     16'h0820 // $020820
`define FRAME_COUNT_HI_REG_ADDR     16'h0821 // $020821
`define RAND_NUM_REG_ADDR           16'h0830 // $020830
// ... other math regs ...
`define VSYNC_STATUS_REG_ADDR       16'h0850 // $020850
`define TIMER_CTRL_REG_ADDR         16'h0860 // $020860
// ... other timer regs ...
`define TEXT_CTRL_REG_ADDR        16'h0840 // As per Spec Sec 12
`define INT_ENABLE_REG_ADDR         16'h0870 // $020870
`define INT_STATUS_REG_ADDR         16'h0871 // $020871
// ... other interrupt regs ...

// Audio SFR Addresses (Offsets within SFR Page 4, assuming base $020000)
`define CH1_FREQ_LO_REG_ADDR      16'h0700
`define CH1_FREQ_HI_REG_ADDR      16'h0701
`define CH1_VOL_ENV_REG_ADDR      16'h0702
`define CH1_WAVE_DUTY_REG_ADDR    16'h0703
`define CH1_CTRL_REG_ADDR         16'h0704

`define CH2_FREQ_LO_REG_ADDR      16'h0705
`define CH2_FREQ_HI_REG_ADDR      16'h0706
`define CH2_VOL_ENV_REG_ADDR      16'h0707
`define CH2_WAVE_DUTY_REG_ADDR    16'h0708
`define CH2_CTRL_REG_ADDR         16'h0709

`define CH3_FREQ_LO_REG_ADDR      16'h070A
`define CH3_FREQ_HI_REG_ADDR      16'h070B
`define CH3_VOL_ENV_REG_ADDR      16'h070C
`define CH3_WAVE_DUTY_REG_ADDR    16'h070D
`define CH3_CTRL_REG_ADDR         16'h070E

`define CH4_FREQ_LO_REG_ADDR      16'h070F
`define CH4_FREQ_HI_REG_ADDR      16'h0710
`define CH4_VOL_ENV_REG_ADDR      16'h0711
`define CH4_WAVE_DUTY_REG_ADDR    16'h0712
`define CH4_CTRL_REG_ADDR         16'h0713

`define AUDIO_MASTER_VOL_REG_ADDR 16'h07F0
`define AUDIO_SYSTEM_CTRL_REG_ADDR 16'h07F1

// Text Character Map RAM (Offsets within SFR Page 4, assuming base $020000)
// Spec Sec 12: $021000-$02177F. Offset $1000 - $177F from page start.
`define TEXT_CHAR_MAP_PAGE4_START_OFFSET 16'h1000
`define TEXT_CHAR_MAP_PAGE4_END_OFFSET   16'h177F
`define TEXT_CHAR_MAP_SIZE_BYTES         1920 // 32x30 cells * 2 bytes/cell

// Gamepad input enable (placeholder for actual input connection)
// These are not SFR addresses but control signals for testing
// `define GAMEPAD1_DATA_IN_ADDR        16'hXXXX // Not an SFR to write to
// `define GAMEPAD2_DATA_IN_ADDR        16'hYYYY // Not an SFR to write to
