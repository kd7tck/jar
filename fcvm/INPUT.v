module debouncer (
    input wire clk,
    input wire btn_in,
    output reg btn_out
);
    reg [19:0] counter; // 10ms at 5MHz ≈ 50,000 cycles
    always @(posedge clk) begin
        if (btn_in != btn_out && counter < 20'd50000)
            counter <= counter + 1;
        else if (counter == 20'd50000) begin
            btn_out <= btn_in;
            counter <= 0;
        end else
            counter <= 0;
    end
endmodule
