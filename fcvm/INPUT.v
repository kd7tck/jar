module debouncer (
    input wire clk,
    input wire btn_in,
    output reg btn_out
);
    reg [19:0] counter; // 10ms at 5MHz ≈ 50,000 cycles. Assuming a 5MHz clock for this counter.
                        // If CPU clock is different, this counter max may need adjustment.
    localparam COUNT_MAX = 20'd50000; // Example: for 50MHz clock, need 500,000 for 10ms.
                                     // Let's assume clk is fast enough that 50000 is reasonable.

    always @(posedge clk) begin
        if (btn_in != btn_out) begin
            if (counter < COUNT_MAX)
                counter <= counter + 1;
            else begin
                btn_out <= btn_in;
                counter <= 0;
            end
        end else
            counter <= 0;
    end
endmodule

module fc8_input_controller (
    input wire clk,
    input wire rst_n, // rst_n is included for completeness but not used by this debouncer version
    input wire raw_joy_up,
    input wire raw_joy_down,
    input wire raw_joy_left,
    input wire raw_joy_right,
    input wire raw_button_a,
    input wire raw_button_b,
    output wire [7:0] debounced_input_status
);

    // Wires for debounced signals
    wire debounced_up;
    wire debounced_down;
    wire debounced_left;
    wire debounced_right;
    wire debounced_button_a;
    wire debounced_button_b;

    // Instantiate debouncers for each input
    debouncer debouncer_up (
        .clk(clk),
        .btn_in(raw_joy_up),
        .btn_out(debounced_up)
    );

    debouncer debouncer_down (
        .clk(clk),
        .btn_in(raw_joy_down),
        .btn_out(debounced_down)
    );

    debouncer debouncer_left (
        .clk(clk),
        .btn_in(raw_joy_left),
        .btn_out(debounced_left)
    );

    debouncer debouncer_right (
        .clk(clk),
        .btn_in(raw_joy_right),
        .btn_out(debounced_right)
    );

    debouncer debouncer_button_a (
        .clk(clk),
        .btn_in(raw_button_a),
        .btn_out(debounced_button_a)
    );

    debouncer debouncer_button_b (
        .clk(clk),
        .btn_in(raw_button_b),
        .btn_out(debounced_button_b)
    );

    // Combine debounced signals into the output status byte
    assign debounced_input_status[0] = debounced_up;
    assign debounced_input_status[1] = debounced_down;
    assign debounced_input_status[2] = debounced_left;
    assign debounced_input_status[3] = debounced_right;
    assign debounced_input_status[4] = debounced_button_a;
    assign debounced_input_status[5] = debounced_button_b;
    assign debounced_input_status[6] = 1'b0; // Reserved
    assign debounced_input_status[7] = 1'b0; // Reserved

endmodule
