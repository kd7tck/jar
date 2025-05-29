`timescale 1ns / 1ps

// FCVM Audio System
// Implements basic sound generation for FCVm.

module fc8_audio_system (
    input wire audio_clk,       // 1MHz audio system clock
    input wire rst_n,           // Active-low reset
    input wire vsync_pulse_in,   // VSYNC pulse for envelope timing (future use)

    // Channel 1 Inputs (from Memory/SFRs)
    input wire [7:0] ch1_freq_lo_in,
    input wire [7:0] ch1_freq_hi_in,
    input wire [7:0] ch1_vol_env_in,     // [7:4] = Volume, [3:0] = Envelope type/params
    input wire [7:0] ch1_wave_duty_in,   // [7:6] = Waveform, [5:0] = Duty / Noise params
    input wire [7:0] ch1_ctrl_in,        // [0] = Channel Enable, [1]=Loop, [2]=Sweep Enable...

    // Channel 2 Inputs (placeholder)
    input wire [7:0] ch2_freq_lo_in,
    input wire [7:0] ch2_freq_hi_in,
    input wire [7:0] ch2_vol_env_in,
    input wire [7:0] ch2_wave_duty_in,
    input wire [7:0] ch2_ctrl_in,

    // Channel 3 Inputs (placeholder)
    input wire [7:0] ch3_freq_lo_in,
    input wire [7:0] ch3_freq_hi_in,
    input wire [7:0] ch3_vol_env_in,
    input wire [7:0] ch3_wave_duty_in,
    input wire [7:0] ch3_ctrl_in,

    // Channel 4 Inputs (placeholder)
    input wire [7:0] ch4_freq_lo_in,
    input wire [7:0] ch4_freq_hi_in,
    input wire [7:0] ch4_vol_env_in,
    input wire [7:0] ch4_wave_duty_in,
    input wire [7:0] ch4_ctrl_in,

    // Global Audio Controls (from Memory/SFRs)
    input wire [7:0] master_vol_in,      // [2:0] = Master Volume
    input wire [7:0] audio_sys_enable_in,// [0] = Audio System Enable

    // Final Audio Output
    output reg audio_pwm_out     // 8-bit PWM output (effectively 1-bit after comparator)
);

    // --- Channel 1: Square Wave Implementation (Simplified) ---
    reg [15:0] ch1_fval;             // Combined frequency value
    reg [15:0] ch1_phase_accumulator;  // Phase accumulator for frequency generation
    reg ch1_square_wave_raw;    // Raw square wave output (0 or 1)
    reg [7:0] ch1_square_wave_8bit; // 8-bit representation ($00 or $FF)
    reg [3:0] ch1_volume;           // Extracted volume
    reg [7:0] ch1_output_scaled;    // Channel output after volume scaling

    // --- Other Channels (placeholder) ---
    // reg [7:0] ch2_output_scaled;
    // reg [7:0] ch3_output_scaled;
    // reg [7:0] ch4_output_scaled;

    // --- Mixing & Master Control ---
    reg [7:0] mixed_output_pre_master; // Sum of all channel outputs (before master vol)
    reg [2:0] master_volume;           // Extracted master volume
    reg [7:0] final_sample_level;      // Final sample level before PWM

    // --- PWM Generation ---
    reg [7:0] pwm_counter;             // Counter for PWM generation

    // Combine frequency bytes for Channel 1
    always @(*) begin
        ch1_fval = {ch1_freq_hi_in, ch1_freq_lo_in};
    end

    // Channel 1 Logic
    always @(posedge audio_clk or negedge rst_n) begin
        if (!rst_n) begin
            ch1_phase_accumulator <= 16'h0000;
            ch1_square_wave_raw <= 1'b0;
            ch1_square_wave_8bit <= 8'h00;
            ch1_volume <= 4'h0;
            ch1_output_scaled <= 8'h00;
        end else begin
            if (ch1_ctrl_in[0]) begin // Channel 1 Enable
                // Phase Accumulator for Frequency
                // F_out = (F_audio_clk * FVAL) / 2^16
                // For FVAL=1, period is 2^16/F_audio_clk.
                // If FVAL represents period directly (e.g. audio_clk / (FVAL+1) ), logic is different.
                // Assuming FVAL is for phase increment style (like NES APU)
                // Period P = CLK_FREQ / (SAMPLE_RATE * F_VAL) -> F_VAL = CLK_FREQ / (SAMPLE_RATE * P)
                // Or, if FVAL is the value to count down from:
                // if (ch1_phase_accumulator == 0) begin
                //    ch1_square_wave_raw <= ~ch1_square_wave_raw;
                //    ch1_phase_accumulator <= ch1_fval; // Reload period
                // else
                //    ch1_phase_accumulator <= ch1_phase_accumulator - 1;
                // end
                // For now, using phase accumulator style:
                ch1_phase_accumulator <= ch1_phase_accumulator + ch1_fval; // Add FVAL to phase accumulator

                // Square Wave Generation (50% duty from MSB of phase accumulator)
                // Waveform select (ch1_wave_duty_in[7:6]) ignored for now, default to 50% square
                ch1_square_wave_raw <= ch1_phase_accumulator[15]; // Use MSB for 50% duty
                ch1_square_wave_8bit <= ch1_square_wave_raw ? 8'hFF : 8'h00;

                // Volume
                ch1_volume <= ch1_vol_env_in[7:4]; // Bits [7:4] for volume

                // Scale square wave by volume
                // Simple scaling: (value * volume) / 15. For 8'hFF, it's (255 * vol) / 15
                // Or, if square is 0/1: output = volume_mapped_to_8bit if high, 0 if low.
                // Let's use (8bit_wave * volume) >> 4 for (val * vol / 16)
                ch1_output_scaled <= (ch1_square_wave_8bit & {ch1_volume, ch1_volume}); // Rough scaling by replicating volume bits
                                                                                       // Better: (ch1_square_wave_raw ? {ch1_volume, 4'h0} : 8'h00) if volume maps to amplitude.
                                                                                       // Or (ch1_square_wave_8bit * ch1_volume) / 15 (requires multiplier)
                                                                                       // Simplest for now: output volume level if square high, else 0
                if (ch1_square_wave_raw) begin
                     // Scale volume (0-15) to an 8-bit range (0 - ~240)
                    ch1_output_scaled <= ch1_volume * 16; // Volume 15 -> 240. Volume 0 -> 0.
                end else begin
                    ch1_output_scaled <= 8'h00;
                end

            end else begin // Channel 1 disabled
                ch1_phase_accumulator <= 16'h0000;
                ch1_square_wave_raw <= 1'b0;
                ch1_square_wave_8bit <= 8'h00;
                ch1_output_scaled <= 8'h00;
            end
        end
    end

    // Mixing and Master Volume & Enable
    always @(posedge audio_clk or negedge rst_n) begin
        if (!rst_n) begin
            mixed_output_pre_master <= 8'h00;
            master_volume <= 3'h0;
            final_sample_level <= 8'h80; // Midpoint for silence if PWM is signed-like
        end else begin
            // Mix channels (only CH1 for now)
            // TODO: Add CH2, CH3, CH4 outputs here with proper signed addition if necessary
            mixed_output_pre_master <= ch1_output_scaled; // Simple sum for now

            if (audio_sys_enable_in[0]) begin // Audio System Enable
                master_volume <= master_vol_in[2:0]; // Bits [2:0] for master volume (0-7)
                
                // Apply master volume: (sample * (master_vol+1)) / 8
                // (master_vol+1) to make range 1-8 for scaling.
                // Using a shift for division: (sample * (master_vol+1)) >> 3
                // This will attenuate.
                // Example: master_vol = 7 (max) -> scale by 8/8 = 1
                //          master_vol = 3 (mid) -> scale by 4/8 = 0.5
                //          master_vol = 0 (min) -> scale by 1/8
                // Need to be careful with integer truncation.
                // For simplicity: final_sample_level <= mixed_output_pre_master >> (7 - master_volume); (approx)
                // Or:
                automatic signed [15:0] temp_scaled_sample;
                temp_scaled_sample = mixed_output_pre_master * (master_volume + 1);
                final_sample_level <= temp_scaled_sample[10:3]; // equivalent to /8 and taking top 8 bits of scaled result

            end else begin // Audio system disabled
                final_sample_level <= 8'h80; // Midpoint for silence (assuming PWM bipolar-like output)
                                             // Or 8'h00 if PWM is unipolar from 0.
                                             // Spec for PWM output usually clarifies silence level.
                                             // Let's assume 0 for silence if PWM is 0 to SampleMax.
                final_sample_level <= 8'h00; 
            end
        end
    end

    // PWM Generation
    // Carrier frequency = audio_clk / 256
    always @(posedge audio_clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_counter <= 8'h00;
            audio_pwm_out <= 1'b0;
        end else begin
            pwm_counter <= pwm_counter + 1; // Free-running 8-bit counter
            if (pwm_counter < final_sample_level) begin
                audio_pwm_out <= 1'b1; // Output high if counter < sample level
            end else begin
                audio_pwm_out <= 1'b0; // Output low otherwise
            end
        end
    end

endmodule
