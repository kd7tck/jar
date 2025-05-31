// FCVM/fc8_interrupt_controller.v
`include "fc8_defines.v"

module fc8_interrupt_controller (
    input wire clk_cpu, // CPU clock
    input wire rst_n,

    // Raw Interrupt Sources
    input wire vblank_nmi_pending_raw,   // From Graphics (NEW_FRAME pulse)
    // timer_irq_pending_raw is internal to this module
    input wire external_irq_pending_raw, // Stubbed input

    // Enables from INT_ENABLE_REG (via SFR block)
    input wire int_enable_vblank,       // For INT_STATUS_REG bit 0
    input wire int_enable_timer,        // For INT_STATUS_REG bit 1
    input wire int_enable_external,     // For INT_STATUS_REG bit 2

    // Clear signals for status bits (from INT_STATUS_REG write-1-to-clear, via SFR block)
    input wire int_status_vblank_clear,
    input wire int_status_timer_clear,
    input wire int_status_external_clear,

    // Timer Control from TIMER_CTRL_REG (via SFR block)
    input wire [3:0] timer_prescaler_select, // TIMER_CTRL_REG.B0-B3
    input wire       timer_enable,           // TIMER_CTRL_REG.B4

    // Outputs to CPU
    output reg cpu_nmi_req,
    output reg cpu_irq_req,

    // Pending status to INT_STATUS_REG (via SFR block)
    output reg vblank_pending_to_sfr,   // To INT_STATUS_REG.B0
    output reg timer_pending_to_sfr,    // To INT_STATUS_REG.B1
    output reg external_pending_to_sfr  // To INT_STATUS_REG.B2
);

    // --- Internal Timer Logic ---
    reg [15:0] prescaler_counter; // Up to 2^15, selected by timer_prescaler_select (max 2^8 for 4 bits)
                                 // Max prescaler is 2^8, so 8 bits for counter is enough if we count down.
                                 // Let's use a wider counter for flexibility if prescaler logic changes.
    reg [7:0] timer_value_counter; // 8-bit up-counter for timer itself
    wire timer_clock_enable;
    reg  internal_timer_irq_pending_raw; // Latched timer overflow

    // Prescaler Logic
    // TimerClock = clk_cpu / (2^PrescalerSelect)
    // If PrescalerSelect is 0, TimerClock = clk_cpu / 1
    // If PrescalerSelect is 1, TimerClock = clk_cpu / 2
    // ...
    // If PrescalerSelect is 8, TimerClock = clk_cpu / 256
    // Max value of timer_prescaler_select is 4'b1000 (8) for 2^8.
    // If timer_prescaler_select > 8, it's treated as 8.

    wire [7:0] current_prescaler_max;
    assign current_prescaler_max = (timer_prescaler_select == 4'b0000) ? 8'd0 : // Divide by 1 (0+1)
                                   (1 << (timer_prescaler_select - 1)); // For 1->2, 2->4, ... 8->128. No, this is 2^(N-1)
                                                                       // Correct: 2^N. If N=1 (0001), 2^1=2. If N=8 (1000), 2^8=256
                                                                       // So, if N=0, count 0 cycles (means every cycle)
                                                                       // If N=1, count 1 cycle (means every 2nd cycle)
                                                                       // If N=8, count 255 cycles (means every 256th cycle)

    assign timer_clock_enable = (prescaler_counter == 8'h00); // Enable when prescaler reaches 0

    always @(posedge clk_cpu or negedge rst_n) begin
        if (!rst_n) begin
            prescaler_counter <= 8'h00;
            timer_value_counter <= 8'h00;
            internal_timer_irq_pending_raw <= 1'b0;
        end else begin
            if (timer_enable) begin
                if (prescaler_counter == 8'h00) begin
                    // Use timer_prescaler_select directly as count down value for 2^N division
                    // If timer_prescaler_select = 0, then prescaler_counter = 0, so timer_clock_enable is true always.
                    // If timer_prescaler_select = 1, then prescaler_counter = 1. Counts 1,0. Tick on 0. (Div by 2)
                    // If timer_prescaler_select = N, then prescaler_counter = N. Counts N, N-1 ... 0. Tick on 0. (Div by N+1)
                    // This is not 2^N. Let's use 2^N.
                    // Need a counter that counts up to (1 << timer_prescaler_select) -1
                    // Example: Select=0 -> Div by 1. Counter counts 0. Tick.
                    // Select=1 -> Div by 2. Counter counts 0,1. Tick on 1.
                    // Select=2 -> Div by 4. Counter counts 0,1,2,3. Tick on 3.
                    // Select=8 -> Div by 256. Counter counts 0..255. Tick on 255.
                    reg [7:0] prescaler_target_count;
                    if (timer_prescaler_select == 4'b0000) prescaler_target_count = 8'd0; // Divide by 1
                    else prescaler_target_count = (1 << timer_prescaler_select) - 1;

                    if (prescaler_counter >= prescaler_target_count) begin
                        prescaler_counter <= 8'h00;
                        // Timer clock tick
                        if (timer_value_counter == 8'hFF) begin
                            timer_value_counter <= 8'h00;
                            internal_timer_irq_pending_raw <= 1'b1; // Set pending flag
                        end else begin
                            timer_value_counter <= timer_value_counter + 1;
                            internal_timer_irq_pending_raw <= 1'b0; // Clear if not overflowing
                        end
                    end else begin
                        prescaler_counter <= prescaler_counter + 1;
                        internal_timer_irq_pending_raw <= 1'b0;
                    end
                end else { // Timer enabled but prescaler not at target yet
                     // This logic is flawed. Prescaler should run independently.
                     // Corrected prescaler logic:
                     // prescaler_counter counts from 0 up to (2^Select)-1
                     // timer_clock_enable is true when prescaler_counter reaches max
                }
            } else { // Timer not enabled
                timer_value_counter <= 8'h00; // Reset counter when disabled
                prescaler_counter <= 8'h00;   // Reset prescaler when timer disabled
                internal_timer_irq_pending_raw <= 1'b0;
            }
        end
    end

    // Corrected Prescaler and Timer Counter Logic
    reg [15:0] actual_prescaler_count; // Max 2^15 if needed, but for 2^8, 8 bits is fine.
                                      // Let's use 8 bits for prescaler counter for 2^0 to 2^8 division.
    reg [7:0] timer_prescaler_countdown;

    always @(posedge clk_cpu or negedge rst_n) begin
        if (!rst_n) begin
            timer_prescaler_countdown <= 8'h00;
            if (timer_enable) begin // On reset, if timer is to be enabled, load initial prescale
                 timer_prescaler_countdown <= (timer_prescaler_select == 0) ? 8'd0 : (1 << timer_prescaler_select) -1;
            end
            timer_value_counter <= 8'h00;
            internal_timer_irq_pending_raw <= 1'b0;
        end else begin
            if (timer_enable) begin
                if (timer_prescaler_countdown == 8'h00) begin
                    // Reset prescaler countdown
                    timer_prescaler_countdown <= (timer_prescaler_select == 0) ? 8'd0 : (1 << timer_prescaler_select) -1;

                    // Increment main timer counter
                    if (timer_value_counter == 8'hFF) begin
                        timer_value_counter <= 8'h00;
                        internal_timer_irq_pending_raw <= 1'b1; // Generate IRQ pulse
                    end else begin
                        timer_value_counter <= timer_value_counter + 1;
                        internal_timer_irq_pending_raw <= 1'b0; // Ensure it's a pulse
                    end
                end else begin
                    timer_prescaler_countdown <= timer_prescaler_countdown - 1;
                    internal_timer_irq_pending_raw <= 1'b0; // IRQ only on overflow
                end
            } else { // Timer not enabled
                timer_value_counter <= 8'h00; // Reset counter
                timer_prescaler_countdown <= (timer_prescaler_select == 0) ? 8'd0 : (1 << timer_prescaler_select) -1; // Reset prescaler
                internal_timer_irq_pending_raw <= 1'b0;
            }
        end
    end


    // --- Interrupt Status Logic (To SFR block) ---
    // These are latched versions of raw events, gated by enables, and clearable
    always @(posedge clk_cpu or negedge rst_n) begin
        if (!rst_n) begin
            vblank_pending_to_sfr <= 1'b0;
            timer_pending_to_sfr <= 1'b0;
            external_pending_to_sfr <= 1'b0;
        end else begin
            // VBLANK Status
            if (vblank_nmi_pending_raw && int_enable_vblank) begin // VBLANK NMI source also sets status if enabled
                vblank_pending_to_sfr <= 1'b1;
            end
            if (int_status_vblank_clear) begin
                vblank_pending_to_sfr <= 1'b0;
            end

            // Timer Status
            if (internal_timer_irq_pending_raw && int_enable_timer) begin
                timer_pending_to_sfr <= 1'b1;
            end
            if (int_status_timer_clear) begin
                timer_pending_to_sfr <= 1'b0;
            end

            // External Status
            if (external_irq_pending_raw && int_enable_external) begin
                external_pending_to_sfr <= 1'b1;
            end
            if (int_status_external_clear) begin
                external_pending_to_sfr <= 1'b0;
            end
        end
    end

    // --- CPU Interrupt Request Logic ---
    always @(posedge clk_cpu or negedge rst_n) begin
        if (!rst_n) begin
            cpu_nmi_req <= 1'b0;
            cpu_irq_req <= 1'b0;
        end else begin
            // NMI is edge-sensitive typically, or level as long as condition persists.
            // Spec: "NMI signal is asserted ... when NEW_FRAME ... is set"
            // Assuming vblank_nmi_pending_raw is the NEW_FRAME pulse.
            // NMI should be requested as long as the source is active (or latched if source is a pulse).
            // For now, let's assume NMI is generated directly from raw source, not gated by INT_ENABLE.
            cpu_nmi_req <= vblank_nmi_pending_raw;

            // IRQ is level sensitive, requested if any enabled source has its status bit set.
            if (timer_pending_to_sfr || external_pending_to_sfr) begin
                cpu_irq_req <= 1'b1;
            end else begin
                cpu_irq_req <= 1'b0;
            end
        end
    end

endmodule
