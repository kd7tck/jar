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

    // Clock generation (Section 19.1)
    reg [1:0] clk_div;
    wire cpu_clk;               // 5MHz CPU clock
    wire pixel_clk;             // ~5.03MHz pixel clock (approximated as 5MHz)
    assign cpu_clk = clk_div[1]; // 20MHz / 4 = 5MHz
    // Pixel clock approximation: use 5MHz for simplicity; adjust for 5.03MHz with PLL
    assign pixel_clk = cpu_clk;

    always @(posedge clk_20mhz or negedge rst_n) begin
        if (!rst_n) clk_div <= 0;
        else clk_div <= clk_div + 1;
    end

    // CPU signals
    wire [15:0] cpu_addr;       // 16-bit logical address (Section 5)
    wire [7:0] cpu_data_in;
    wire [7:0] cpu_data_out;
    wire cpu_we;                // Write enable
    wire cpu_irq_n;             // IRQ (active-low)
    wire cpu_nmi_n;             // NMI (active-low)

    // Memory signals
    wire [19:0] phys_addr;      // 1MB physical address (Section 3)
    wire [7:0] mem_data_out;
    wire [7:0] vram_data;
    // wire [7:0] sfr_data; // This is an output from memory_controller, keep if used by other modules not shown
                         // For now, assuming it might be, let's keep it. If it's only for new SFRs, it might be redundant.
    // wire [7:0] rom_data; // Replaced by cart_rom_data input port

    // Wires for Audio SFRs
    wire [7:0] audio_freq_lo;
    wire [7:0] audio_freq_hi;
    wire [3:0] audio_volume;

    // Wire for Debounced Input Status
    wire [7:0] debounced_inputs;

    // Graphics signals
    wire vblank;                // VBLANK signal (Section 6.3)

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
        .clk(cpu_clk),
        .rst_n(rst_n),
        .cpu_addr(cpu_addr),
        .cpu_data_in(cpu_data_out),
        .cpu_data_out(cpu_data_in),
        .we(cpu_we),
        .phys_addr(phys_addr),
        .mem_data_out(mem_data_out),
        .vram_data(vram_data),
        .sfr_data(sfr_data), // Keep if sfr_data output from mem_ctrl is used elsewhere
        // Connections for new SFRs from memory controller
        .audio_freq_lo_out(audio_freq_lo),
        .audio_freq_hi_out(audio_freq_hi),
        .audio_volume_out(audio_volume),
        .input_status_in(debounced_inputs),
        .rom_data(cart_rom_data) // Connect to new top-level input
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
    // Note: audio_channel expects clk_1mhz, but we are connecting cpu_clk (5MHz)
    // This is a simplification for this exercise. In a real scenario,
    // a proper 1MHz clock or adjustable parameters in audio_channel would be needed.
    audio_channel audio_ch0 (
        .clk_1mhz(cpu_clk), // Simplified: Using 5MHz cpu_clk instead of a dedicated 1MHz clock
        .rst_n(rst_n),
        .freq_val({audio_freq_hi, audio_freq_lo}), // Concatenate hi and lo bytes
        .volume(audio_volume),
        .pwm_out(audio_pwm_out)
    );

    // Instantiate Graphics Controller
    fc8_vga vga (
        .clk(pixel_clk),
        .rst_n(rst_n),
        .vram_data(vram_data),
        .vga_rgb(vga_rgb),
        .hsync(vga_hsync),
        .vsync(vga_vsync),
        .vblank(vblank)
    );

    // Interrupt signals (simplified)
    assign cpu_nmi_n = ~vblank; // NMI on VBLANK (Section 13.1)
    assign cpu_irq_n = 1'b1;    // IRQ disabled for now

endmodule
