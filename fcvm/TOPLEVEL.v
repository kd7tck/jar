`timescale 1ns / 1ps
module fc8_top (
    input wire clk_20mhz,       // 20MHz master clock (Section 19.1)
    input wire rst_n,           // Active-low reset (Section 19.6)
    output wire [7:0] vga_rgb,  // R3G3B2 VGA output (Section 11)
    output wire vga_hsync,
    output wire vga_vsync
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
    wire [7:0] sfr_data;
    wire [7:0] rom_data;

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
        .sfr_data(sfr_data),
        .rom_data(rom_data)
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
