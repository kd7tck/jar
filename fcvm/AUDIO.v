module audio_channel (
    input wire clk_1mhz,
    input wire rst_n,
    input wire [15:0] freq_val,
    input wire [3:0] volume,
    output reg [7:0] pwm_out
);
    reg [15:0] phase_acc;
    always @(posedge clk_1mhz) begin
        if (!rst_n) phase_acc <= 0;
        else phase_acc <= phase_acc + freq_val + 1;
        pwm_out <= phase_acc[15] ? (volume * 17) : 8'h00; // Square wave
    end
endmodule
