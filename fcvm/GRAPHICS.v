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
    integer i; // Declare loop variable for initial block

    initial begin
        // Define a 16-color base palette (R3G3B2 format)
        palette[0]  <= 8'b00000000; // 0: Black (Can be treated as transparent color key)
        palette[1]  <= 8'b11111111; // 1: White
        palette[2]  <= 8'b11100000; // 2: Bright Red
        palette[3]  <= 8'b00011100; // 3: Bright Green
        palette[4]  <= 8'b00000011; // 4: Bright Blue
        palette[5]  <= 8'b11111100; // 5: Yellow (R+G)
        palette[6]  <= 8'b11100011; // 6: Magenta (R+B)
        palette[7]  <= 8'b00011111; // 7: Cyan (G+B)
        palette[8]  <= 8'b11011010; // 8: Orange (R=6, G=6, B=2)
        palette[9]  <= 8'b00101101; // 9: Light Blue (R=1, G=3, B=1)
        palette[10] <= 8'b10110101; // 10: Medium Gray (R=5, G=5, B=1)
        palette[11] <= 8'b01001001; // 11: Dark Gray (R=2, G=2, B=1)
        palette[12] <= 8'b11110000; // 12: Bright Yellow (R=7, G=4, B=0)
        palette[13] <= 8'b10001000; // 13: Brown (R=4, G=2, B=0)
        palette[14] <= 8'b10101010; // 14: Another Gray (R=5, G=2, B=2)
        palette[15] <= 8'b01101101; // 15: Light Green (R=3, G=3, B=1)

        // Repeat the 16-color pattern for the rest of the palette
        for (i = 16; i < 256; i = i + 1) begin
            palette[i] <= palette[i % 16];
        end
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
