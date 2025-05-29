`timescale 1ns / 1ps

// FCVM Input Controller
// Handles debouncing for raw gamepad inputs.

module fc8_input_controller (
    input wire clk,         // System clock (e.g., cpu_clk - 5MHz)
    input wire rst_n,       // Active-low reset

    // Raw Gamepad 1 Inputs
    input wire raw_joy_up,
    input wire raw_joy_down,
    input wire raw_joy_left,
    input wire raw_joy_right,
    input wire raw_button_a,
    input wire raw_button_b,
    // input wire raw_button_start, // Assuming these will be added later
    // input wire raw_button_select,

    // Debounced Gamepad Outputs
    output reg [7:0] gamepad1_state_out,    // Debounced state for Gamepad 1
    output reg [7:0] gamepad2_state_out,    // Debounced state for Gamepad 2 (placeholder)
    output reg gamepad1_connected_out, // Connection status for Gamepad 1
    output reg gamepad2_connected_out  // Connection status for Gamepad 2 (placeholder)
);

    // Debouncer Parameters
    // Debounce time: e.g., 10ms. If clk is 5MHz (200ns period):
    // 10ms / 200ns = 10,000,000 ns / 200 ns = 50,000 clock cycles.
    // Counter needs to hold up to 50000. 2^15 = 32768, 2^16 = 65536. So 16 bits.
    localparam DEBOUNCE_COUNT_MAX = 16'd49999; // For ~10ms at 5MHz

    // Debouncer Instance Registers for Gamepad 1
    reg [15:0] debounce_counter_up;
    reg debounce_last_raw_up;
    reg debounced_up_state;

    reg [15:0] debounce_counter_down;
    reg debounce_last_raw_down;
    reg debounced_down_state;

    reg [15:0] debounce_counter_left;
    reg debounce_last_raw_left;
    reg debounced_left_state;

    reg [15:0] debounce_counter_right;
    reg debounce_last_raw_right;
    reg debounced_right_state;

    reg [15:0] debounce_counter_a;
    reg debounce_last_raw_a;
    reg debounced_button_a_state;

    reg [15:0] debounce_counter_b;
    reg debounce_last_raw_b;
    reg debounced_button_b_state;

    // Generic Debouncer Macro (or repeated logic)
    // This would be better as a generate block or task if fully parameterizable,
    // but for fixed 6 inputs, direct repetition is acceptable for now.

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset debouncer states for UP
            debounce_counter_up <= 0;
            debounce_last_raw_up <= raw_joy_up; 
            debounced_up_state <= raw_joy_up;   

            // Reset debouncer states for DOWN
            debounce_counter_down <= 0;
            debounce_last_raw_down <= raw_joy_down;
            debounced_down_state <= raw_joy_down;

            // Reset debouncer states for LEFT
            debounce_counter_left <= 0;
            debounce_last_raw_left <= raw_joy_left;
            debounced_left_state <= raw_joy_left;

            // Reset debouncer states for RIGHT
            debounce_counter_right <= 0;
            debounce_last_raw_right <= raw_joy_right;
            debounced_right_state <= raw_joy_right;

            // Reset debouncer states for A
            debounce_counter_a <= 0;
            debounce_last_raw_a <= raw_button_a;
            debounced_button_a_state <= raw_button_a;

            // Reset debouncer states for B
            debounce_counter_b <= 0;
            debounce_last_raw_b <= raw_button_b;
            debounced_button_b_state <= raw_button_b;

            // Outputs
            // Initial gamepad state can be 0 (not pressed) or follow raw inputs.
            // FCVm spec: GAMEPAD_STATUS bits are active-LOW (0 when pressed).
            // This module outputs debounced states as active-HIGH (1 when pressed).
            // Memory controller will invert when CPU reads GAMEPAD_STATUS_ADDR.
            gamepad1_state_out <= {2'b00, debounced_button_b_state, debounced_button_a_state, debounced_right_state, debounced_left_state, debounced_down_state, debounced_up_state};
            gamepad2_state_out <= 8'h00; // All buttons released (not pressed)
            gamepad1_connected_out <= 1'b1; // Assume connected
            gamepad2_connected_out <= 1'b1; // Placeholder, assume connected for now
            
        end else begin
            // --- Debouncer for UP ---
            if (raw_joy_up != debounce_last_raw_up) begin 
                debounce_counter_up <= 0;                 
                debounce_last_raw_up <= raw_joy_up;       
            end else if (debounce_counter_up < DEBOUNCE_COUNT_MAX) begin
                debounce_counter_up <= debounce_counter_up + 1; 
            end else begin 
                debounced_up_state <= debounce_last_raw_up; 
            end

            // --- Debouncer for DOWN ---
            if (raw_joy_down != debounce_last_raw_down) begin
                debounce_counter_down <= 0;
                debounce_last_raw_down <= raw_joy_down;
            end else if (debounce_counter_down < DEBOUNCE_COUNT_MAX) begin
                debounce_counter_down <= debounce_counter_down + 1;
            end else begin
                debounced_down_state <= debounce_last_raw_down;
            end

            // --- Debouncer for LEFT ---
            if (raw_joy_left != debounce_last_raw_left) begin
                debounce_counter_left <= 0;
                debounce_last_raw_left <= raw_joy_left;
            end else if (debounce_counter_left < DEBOUNCE_COUNT_MAX) begin
                debounce_counter_left <= debounce_counter_left + 1;
            end else begin
                debounced_left_state <= debounce_last_raw_left;
            end

            // --- Debouncer for RIGHT ---
            if (raw_joy_right != debounce_last_raw_right) begin
                debounce_counter_right <= 0;
                debounce_last_raw_right <= raw_joy_right;
            end else if (debounce_counter_right < DEBOUNCE_COUNT_MAX) begin
                debounce_counter_right <= debounce_counter_right + 1;
            end else begin
                debounced_right_state <= debounce_last_raw_right;
            end

            // --- Debouncer for BUTTON A ---
            if (raw_button_a != debounce_last_raw_a) begin
                debounce_counter_a <= 0;
                debounce_last_raw_a <= raw_button_a;
            end else if (debounce_counter_a < DEBOUNCE_COUNT_MAX) begin
                debounce_counter_a <= debounce_counter_a + 1;
            end else begin
                debounced_button_a_state <= debounce_last_raw_a;
            end

            // --- Debouncer for BUTTON B ---
            if (raw_button_b != debounce_last_raw_b) begin
                debounce_counter_b <= 0;
                debounce_last_raw_b <= raw_button_b;
            end else if (debounce_counter_b < DEBOUNCE_COUNT_MAX) begin
                debounce_counter_b <= debounce_counter_b + 1;
            end else begin
                debounced_button_b_state <= debounce_last_raw_b;
            end

            // Assign debounced states to output register
            // Bits: [7 Sälj Start B A R L D U 0] (Select, Start, B, A, Right, Left, Down, Up)
            // Outputting active-HIGH (1 = pressed)
            gamepad1_state_out[0] <= debounced_up_state;
            gamepad1_state_out[1] <= debounced_down_state;
            gamepad1_state_out[2] <= debounced_left_state;
            gamepad1_state_out[3] <= debounced_right_state;
            gamepad1_state_out[4] <= debounced_button_a_state;
            gamepad1_state_out[5] <= debounced_button_b_state;
            gamepad1_state_out[6] <= 1'b0; // START - Placeholder (not pressed = 0 for active-high)
            gamepad1_state_out[7] <= 1'b0; // SELECT - Placeholder (not pressed = 0 for active-high)
            
            // Placeholder for Gamepad 2
            gamepad2_state_out <= 8'h00; // All buttons not pressed

            // Connection status (hardwired for now)
            gamepad1_connected_out <= 1'b1;
            gamepad2_connected_out <= 1'b1; // Placeholder, assume connected
        end
    end

endmodule
