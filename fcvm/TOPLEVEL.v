`timescale 1ns / 1ps
module fc8_top (
    input wire clk_20mhz,       // 20MHz master clock (Section 19.1)
    input wire rst_n,           // Active-low reset (Section 19.6)
    output wire [7:0] vga_rgb,  // R3G3B2 VGA output (Section 11)
    output wire vga_hsync,
    output wire vga_vsync,

    // New Input Ports for Input Controller
    input wire raw_joy_up,
    input wire raw_joy_down,
    input wire raw_joy_left,
    input wire raw_joy_right,
    input wire raw_button_a,
    input wire raw_button_b,

    // New Input Port for Cartridge ROM
    input wire [7:0] cart_rom_data,

    // New Output Port for Audio
    output wire [7:0] audio_pwm_out
);

    // Clock generation (Section 19.1 & subtask requirement)
    reg [1:0] cpu_pixel_clk_div; // For 20MHz / 4 = 5MHz
    reg [4:0] audio_clk_div;     // For 20MHz / 20 = 1MHz
    
    wire cpu_clk;               // 5MHz CPU clock
    wire pixel_clk;             // 5MHz Pixel clock (approximated from 5.03MHz)
    wire audio_clk;             // 1MHz Audio clock

    assign cpu_clk = cpu_pixel_clk_div[1];
    assign pixel_clk = cpu_pixel_clk_div[1]; // Using same 5MHz clock for CPU and Pixel for now
    assign audio_clk = audio_clk_div[4];     // Divide by 20 (counter 0-19, tap at bit 4 for 1MHz)

    always @(posedge clk_20mhz or negedge rst_n) begin
        if (!rst_n) begin
            cpu_pixel_clk_div <= 2'b0;
            audio_clk_div <= 5'b0;
        end else begin
            cpu_pixel_clk_div <= cpu_pixel_clk_div + 1;
            audio_clk_div <= audio_clk_div + 1;
        end
    end

    // CPU signals
    wire [15:0] cpu_addr;       // 16-bit logical address (Section 5)
    wire [7:0] cpu_data_in;
    wire [7:0] cpu_data_out;
    wire cpu_we;                // Write enable
    wire cpu_irq_n;             // IRQ (active-low)
    wire cpu_nmi_n;             // NMI (active-low)

    // Memory signals
    wire [19:0] phys_addr;      // Physical address from Memory Controller
    // wire [7:0] mem_data_out; // From Memory to CPU (now cpu_data_in for CPU)
    // wire [7:0] vram_data;    // From Memory to old VGA (now handled by fc8_graphics)
    // wire [7:0] sfr_data;     // Old generic SFR output from mem_ctrl

    // Wire for Debounced Input Status (from Input Controller to Memory Controller)
    wire [7:0] debounced_inputs;

    // --- Wires for Audio System SFRs (from Memory Controller to Audio System) ---
    wire [7:0] ch1_freq_lo_to_audio;
    wire [7:0] ch1_freq_hi_to_audio;
    wire [7:0] ch1_vol_env_to_audio;
    wire [7:0] ch1_wave_duty_to_audio;
    wire [7:0] ch1_ctrl_to_audio;
    // CH2
    wire [7:0] ch2_freq_lo_to_audio;
    wire [7:0] ch2_freq_hi_to_audio;
    wire [7:0] ch2_vol_env_to_audio;
    wire [7:0] ch2_wave_duty_to_audio;
    wire [7:0] ch2_ctrl_to_audio;
    // CH3
    wire [7:0] ch3_freq_lo_to_audio;
    wire [7:0] ch3_freq_hi_to_audio;
    wire [7:0] ch3_vol_env_to_audio;
    wire [7:0] ch3_wave_duty_to_audio;
    wire [7:0] ch3_ctrl_to_audio;
    // CH4
    wire [7:0] ch4_freq_lo_to_audio;
    wire [7:0] ch4_freq_hi_to_audio;
    wire [7:0] ch4_vol_env_to_audio;
    wire [7:0] ch4_wave_duty_to_audio;
    wire [7:0] ch4_ctrl_to_audio;
    // Global Audio Controls
    wire [7:0] master_vol_to_audio;
    wire [7:0] audio_sys_enable_to_audio;

    // --- Graphics System Wires ---
    wire [15:0] vram_addr_from_graphics;    // From Graphics to Memory
    wire [7:0] vram_data_to_graphics;      // From Memory to Graphics
    wire [7:0] screen_ctrl_to_graphics;    // From Memory (SFR) to Graphics
    wire [7:0] scroll_x_to_graphics;       // From Memory (SFR) to Graphics
    wire [7:0] scroll_y_to_graphics;       // From Memory (SFR) to Graphics
    wire [1:0] vsync_status_from_graphics; // From Graphics to Memory (SFR)
    wire drive_frame_count_inc_from_graphics; // From Graphics to Memory (SFR)
    wire vblank_status;                    // VBLANK signal from Graphics for NMI

    // Instantiate CPU
    fc8_cpu cpu (
        .clk(cpu_clk),
        .rst_n(rst_n),
        .addr(cpu_addr),
        .data_in(cpu_data_in),
        .data_out(cpu_data_out),
        .we(cpu_we),
        .irq_n(cpu_irq_n),
        .nmi_n(cpu_nmi_n)
    );

    // Instantiate Memory Controller
    fc8_memory_controller mem_ctrl (
        .clk(cpu_clk), // Memory system clocked by CPU clock
        .rst_n(rst_n),
        .cpu_addr(cpu_addr),
        .cpu_data_in(cpu_data_out), // From CPU WE
        .cpu_data_out(cpu_data_in),   // To CPU RD
        .we(cpu_we),
        .phys_addr(phys_addr),        // To Cartridge slot / external
        .cart_rom_data(cart_rom_data),// From Cartridge slot

        // VRAM connections for Graphics
        .vram_addr_from_graphics(vram_addr_from_graphics), // Input from Graphics
        .vram_data_to_graphics(vram_data_to_graphics),   // Output to Graphics

        // SFR connections for Graphics
        .screen_ctrl_to_graphics(screen_ctrl_to_graphics), // Output to Graphics
        .scroll_x_to_graphics(scroll_x_to_graphics),       // Output to Graphics
        .scroll_y_to_graphics(scroll_y_to_graphics),       // Output to Graphics
        .vsync_status_from_graphics(vsync_status_from_graphics), // Input from Graphics
        .frame_count_inc_from_graphics(drive_frame_count_inc_from_graphics), // Input from Graphics
        
        // Gamepad connections
        .gamepad1_data(debounced_inputs[7:4]), // Example: Upper nibble for GP1 UDLR, lower for ABSS
        .gamepad2_data(debounced_inputs[3:0]), // Example: Lower nibble for GP2 UDLR
                                              // Actual mapping depends on input_controller and MEMORY.v gamepad SFRs.
                                              // For now, use debounced_inputs as placeholder for gamepad data.
                                              // This needs to match how MEMORY.v exposes gamepad data.
                                              // The previous MEMORY.v had gamepad1_data and gamepad2_data inputs.
                                              // So, connect debounced_inputs to those.
        // The previous MEMORY.v expects .gamepad1_data(gamepad1_data_wire) etc.
        // Let's assume debounced_inputs holds combined gamepad data that MEMORY.v will decode.
        .input_status_in(debounced_inputs) // General input to memory for SFRs like GAMEPAD1_STATUS_ADDR
                                           // This was the old connection. The new MEMORY.v has distinct gamepad inputs.
                                           // Reverting to more direct connection based on new MEMORY.v ports.
        // .gamepad1_data(gamepad1_data_wire), // Requires gamepad1_data_wire from input_ctrl
        // .gamepad2_data(gamepad2_data_wire), // Requires gamepad2_data_wire from input_ctrl
        // For now, let's keep input_status_in and MEMORY.v can internally map it.
        // The new MEMORY.v from previous step has gamepad1_data, gamepad2_data inputs.
        // So, we need wires for these from input_ctrl. Let's assume input_ctrl provides them.
        // For now, will connect debounced_inputs to input_status_in.
        // The memory controller from previous step has specific gamepad inputs.
        // This TOPLEVEL should provide them.
        // Let's assume input_ctrl provides separate gamepad1 and gamepad2 wires.
        // wire [7:0] gamepad1_status_wire;
        // wire [7:0] gamepad2_status_wire;
        // .gamepad1_data(gamepad1_status_wire),
        // .gamepad2_data(gamepad2_status_wire)
        // This part needs consistent port names from Input controller through Memory.
        // For this step, I will assume Memory.v takes the full debounced_inputs for its own decoding.

        // --- Audio SFR Connections from Memory to Audio System ---
        .audio_ch1_freq_lo_to_audio(ch1_freq_lo_to_audio),
        .audio_ch1_freq_hi_to_audio(ch1_freq_hi_to_audio),
        .audio_ch1_vol_env_to_audio(ch1_vol_env_to_audio),
        .audio_ch1_wave_duty_to_audio(ch1_wave_duty_to_audio),
        .audio_ch1_ctrl_to_audio(ch1_ctrl_to_audio),
        .audio_ch2_freq_lo_to_audio(ch2_freq_lo_to_audio),
        .audio_ch2_freq_hi_to_audio(ch2_freq_hi_to_audio),
        .audio_ch2_vol_env_to_audio(ch2_vol_env_to_audio),
        .audio_ch2_wave_duty_to_audio(ch2_wave_duty_to_audio),
        .audio_ch2_ctrl_to_audio(ch2_ctrl_to_audio),
        .audio_ch3_freq_lo_to_audio(ch3_freq_lo_to_audio),
        .audio_ch3_freq_hi_to_audio(ch3_freq_hi_to_audio),
        .audio_ch3_vol_env_to_audio(ch3_vol_env_to_audio),
        .audio_ch3_wave_duty_to_audio(ch3_wave_duty_to_audio),
        .audio_ch3_ctrl_to_audio(ch3_ctrl_to_audio),
        .audio_ch4_freq_lo_to_audio(ch4_freq_lo_to_audio),
        .audio_ch4_freq_hi_to_audio(ch4_freq_hi_to_audio),
        .audio_ch4_vol_env_to_audio(ch4_vol_env_to_audio),
        .audio_ch4_wave_duty_to_audio(ch4_wave_duty_to_audio),
        .audio_ch4_ctrl_to_audio(ch4_ctrl_to_audio),
        .master_vol_to_audio(master_vol_to_audio),
        .audio_sys_enable_to_audio(audio_sys_enable_to_audio)
    );

    // Instantiate Input Controller
    fc8_input_controller input_ctrl (
        .clk(cpu_clk),
        .rst_n(rst_n),
        .raw_joy_up(raw_joy_up),
        .raw_joy_down(raw_joy_down),
        .raw_joy_left(raw_joy_left),
        .raw_joy_right(raw_joy_right),
        .raw_button_a(raw_button_a),
        .raw_button_b(raw_button_b),
        .debounced_input_status(debounced_inputs)
    );

    // Instantiate Audio Channel
    // Instantiate Audio System (New)
    fc8_audio_system audio_system_unit (
        .audio_clk(audio_clk),
        .rst_n(rst_n),
        .vsync_pulse_in(vsync_status_from_graphics[1]), // NEW_FRAME pulse from Graphics

        .ch1_freq_lo_in(ch1_freq_lo_to_audio),
        .ch1_freq_hi_in(ch1_freq_hi_to_audio),
        .ch1_vol_env_in(ch1_vol_env_to_audio),
        .ch1_wave_duty_in(ch1_wave_duty_to_audio),
        .ch1_ctrl_in(ch1_ctrl_to_audio),

        .ch2_freq_lo_in(ch2_freq_lo_to_audio),
        .ch2_freq_hi_in(ch2_freq_hi_to_audio),
        .ch2_vol_env_in(ch2_vol_env_to_audio),
        .ch2_wave_duty_in(ch2_wave_duty_to_audio),
        .ch2_ctrl_in(ch2_ctrl_to_audio),

        .ch3_freq_lo_in(ch3_freq_lo_to_audio),
        .ch3_freq_hi_in(ch3_freq_hi_to_audio),
        .ch3_vol_env_in(ch3_vol_env_to_audio),
        .ch3_wave_duty_in(ch3_wave_duty_to_audio),
        .ch3_ctrl_in(ch3_ctrl_to_audio),

        .ch4_freq_lo_in(ch4_freq_lo_to_audio),
        .ch4_freq_hi_in(ch4_freq_hi_to_audio),
        .ch4_vol_env_in(ch4_vol_env_to_audio),
        .ch4_wave_duty_in(ch4_wave_duty_to_audio),
        .ch4_ctrl_in(ch4_ctrl_to_audio),

        .master_vol_in(master_vol_to_audio),
        .audio_sys_enable_in(audio_sys_enable_to_audio),

        .audio_pwm_out(audio_pwm_out) // To Top PWM Port
    );

    // Instantiate Graphics Controller (New)
    fc8_graphics graphics_ctrl (
        .pixel_clk(pixel_clk),
        .rst_n(rst_n),
        .vram_addr_out(vram_addr_from_graphics), // To Memory
        .vram_data_in(vram_data_to_graphics),   // From Memory
        .screen_ctrl_reg_in(screen_ctrl_to_graphics), // From Memory (SFR)
        .vram_scroll_x_in(scroll_x_to_graphics),     // From Memory (SFR)
        .vram_scroll_y_in(scroll_y_to_graphics),     // From Memory (SFR)
        .vga_hsync(vga_hsync),                       // To Top VGA Port
        .vga_vsync(vga_vsync),                       // To Top VGA Port
        .vga_rgb(vga_rgb),                           // To Top VGA Port
        .drive_vsync_status(vsync_status_from_graphics), // To Memory (SFR)
        .drive_frame_count_increment(drive_frame_count_inc_from_graphics) // To Memory (SFR)
    );
    // Assign vblank_status for NMI from the correct graphics output if drive_vsync_status provides it
    // drive_vsync_status[0] is IN_VBLANK
    assign vblank_status = vsync_status_from_graphics[0];


    // Interrupt signals
    // NMI on VBLANK (Section 13.1) - vblank_status comes from graphics controller
    assign cpu_nmi_n = ~vblank_status; 
    
    // Other IRQ sources (Timer, Text, Tile, Sprite, Audio) come from MEMORY.v SFRs via Interrupt Controller (not shown)
    // For now, connect MEMORY.v's IRQ outputs to placeholder wires or directly if IRQ controller is simple.
    wire timer_irq_source, text_irq_source, tile_irq_source, sprite_irq_source, audio_irq_source;
    // Connect these to Memory.v outputs (need to add these output ports to Memory.v if not already there)
    // The Memory.v generated in previous step has these.
    // assign timer_irq_source = mem_ctrl.timer_irq_out; // Requires named port in mem_ctrl
    // assign text_irq_source  = mem_ctrl.text_irq_out;
    // assign tile_irq_source  = mem_ctrl.tile_irq_out;
    // assign sprite_irq_source= mem_ctrl.sprite_irq_out;
    // assign audio_irq_source = mem_ctrl.audio_irq_out;
    // For now, keep main IRQ line disabled. An IRQ controller would combine these sources.
    assign cpu_irq_n = 1'b1;    // IRQ disabled for now

endmodule
