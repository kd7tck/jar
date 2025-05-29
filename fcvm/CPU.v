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
    reg [7:0] opcode;
    reg [15:0] operand_addr;
    reg [7:0] operand;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            A <= 8'h00;
            X <= 8'h00;
            Y <= 8'h00;
            SP <= 16'h0100;     // Stack at $0100 (Section 3)
            PC <= 16'h8000;     // Cartridge entry point (Section 4)
            F <= 8'h00;         // Clear flags
            addr <= 16'h0000;
            we <= 1'b0;
            state <= FETCH;
        end else begin
            case (state)
                FETCH: begin
                    addr <= PC;
                    we <= 1'b0;
                    state <= DECODE;
                end
                DECODE: begin
                    opcode <= data_in;
                    PC <= PC + 1;
                    case (data_in) // Simplified opcode decode (Section 5)
                        8'hA9: state <= EXECUTE; // LDA immediate
                        8'h8D: state <= MEM_ACCESS; // STA absolute
                        8'h4C: state <= MEM_ACCESS; // JMP absolute
                        default: state <= FETCH; // Undefined as NOP
                    endcase
                end
                EXECUTE: begin
                    case (opcode)
                        8'hA9: begin // LDA immediate
                            addr <= PC;
                            state <= WRITEBACK;
                        end
                    endcase
                end
                MEM_ACCESS: begin
                    case (opcode)
                        8'h8D: begin // STA absolute
                            addr <= PC;
                            we <= 1'b0;
                            state <= WRITEBACK;
                        end
                        8'h4C: begin // JMP absolute
                            addr <= PC;
                            state <= WRITEBACK;
                        end
                    endcase
                end
                WRITEBACK: begin
                    case (opcode)
                        8'hA9: begin // LDA immediate
                            A <= data_in;
                            F[1] <= (data_in == 8'h00); // Zero flag
                            F[7] <= data_in[7];         // Negative flag
                            PC <= PC + 1;
                            state <= FETCH;
                        end
                        8'h8D: begin // STA absolute
                            operand_addr[7:0] <= data_in;
                            addr <= PC + 1;
                            state <= EXECUTE;
                            if (PC == PC + 1) begin
                                operand_addr[15:8] <= data_in;
                                addr <= operand_addr;
                                data_out <= A;
                                we <= 1'b1;
                                state <= FETCH;
                            end
                        end
                        8'h4C: begin // JMP absolute
                            operand_addr[7:0] <= data_in;
                            addr <= PC + 1;
                            if (PC == PC + 1) begin
                                operand_addr[15:8] <= data_in;
                                PC <= operand_addr;
                                state <= FETCH;
                            end
                        end
                    endcase
                end
            endcase

            // Interrupt handling (Section 13.4)
            if (!nmi_n && state == FETCH) begin
                addr <= SP;
                data_out <= PC[15:8];
                we <= 1'b1;
                SP <= SP + 1;
                state <= EXECUTE; // Simplified; expand for full sequence
            end
        end
    end

endmodule
