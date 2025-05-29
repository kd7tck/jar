module fc8_vga (
    input wire clk,                 // 5MHz pixel clock (approximated)
    input wire rst_n,
    input wire [7:0] vram_data,     // VRAM data (8-bit color index)
    output reg [7:0] vga_rgb,       // R3G3B2 (Section 11)
    output reg hsync,
    output reg vsync,
    output reg vblank
);

    // VGA timing parameters (Section 19.3, approximated for 5MHz)
    localparam H_ACTIVE = 256;
    localparam H_TOTAL = 318;       // ~5MHz / (60Hz * 262) ≈ 318 pixels
    localparam V_ACTIVE = 240;
    localparam V_TOTAL = 262;

    reg [9:0] h_count;
    reg [9:0] v_count;
    reg [15:0] vram_addr;

    // Default palette (Section 11, Appendix)
    reg [7:0] palette [0:255];
    initial begin
        palette[0] = 8'h00; // Transparent
        palette[1] = 8'hE0; // White
        palette[2] = 8'h1C; // Black
        // Initialize remaining palette entries
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_count <= 0;
            v_count <= 0;
            hsync <= 1;
            vsync <= 1;
            vblank <= 0;
            vga_rgb <= 8'h00;
        end else begin
            // Horizontal and vertical counters
            if (h_count < H_TOTAL - 1) h_count <= h_count + 1;
            else begin
                h_count <= 0;
                if (v_count < V_TOTAL - 1) v_count <= v_count + 1;
                else v_count <= 0;
            end

            // HSYNC and VSYNC
            hsync <= (h_count >= 256 && h_count < 275); // Approx. sync pulse
            vsync <= (v_count >= 240 && v_count < 242); // Approx. sync pulse
            vblank <= (v_count >= 240); // VBLANK (Section 6.3)

            // Pixel output
            if (h_count < H_ACTIVE && v_count < V_ACTIVE) begin
                vram_addr <= (v_count * 256) + h_count; // Bitmap mode (Section 9.2)
                vga_rgb <= palette[vram_data]; // Map VRAM color index to R3G3B2
            end else begin
                vga_rgb <= 8'h00; // Blank outside active area
            end
        end
    end

endmodule
