`timescale 1ns / 1ps

// FCVM Graphics Controller - Basic VGA Timing and Bitmap Mode
// Reference: FCVm Specification Sections 9.2 (Bitmap), 19.3 (VGA)

module fc8_graphics (
    input wire pixel_clk,       // 5MHz pixel clock (approx)
    input wire rst_n,           // Active-low reset

    // VRAM Interface
    output reg [15:0] vram_addr_out, // Address to VRAM (16-bit for 64KB VRAM)
    input wire [7:0] vram_data_in,   // Data from VRAM (color index)

    // SFR Inputs (from Memory Controller)
    input wire [7:0] screen_ctrl_reg_in, // SCREEN_CTRL_REG ($020800)
    input wire [7:0] vram_scroll_x_in,   // VRAM_SCROLL_X_LO_REG ($020009) - using LO for 8-bit scroll
    input wire [7:0] vram_scroll_y_in,   // VRAM_SCROLL_Y_LO_REG ($02000B) - using LO for 8-bit scroll

    // VGA Outputs
    output reg vga_hsync,
    output reg vga_vsync,
    output reg [7:0] vga_rgb,       // R3G3B2 format (directly outputting VRAM index for now)

    // Status Outputs (to Memory Controller / SFRs)
    output reg [1:0] drive_vsync_status,       // [1]=NEW_FRAME (pulse), [0]=IN_VBLANK (level)
    output reg drive_frame_count_increment // Pulse at NEW_FRAME
);

    // VGA Timing Parameters (Example for ~256x240 visible)
    // Horizontal: Total 318 clocks. Visible 256. HSync Pulse ~19-38. HBlank ~62.
    // Using example values that are common, adjust to spec if more precise values given.
    // Spec Section 19.3: 256 visible width, 240 visible height.
    // Horizontal Timing (pixels, based on pixel_clk)
    localparam H_DISPLAY_PERIOD = 256; // Visible width
    localparam H_FRONT_PORCH    = 8;   // Approx
    localparam H_SYNC_PULSE     = 24;  // Approx (Spec example HSync=19) - let's use a common value
    localparam H_BACK_PORCH     = 30;  // Approx
    localparam H_TOTAL_PERIOD   = H_DISPLAY_PERIOD + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH; // 256+8+24+30 = 318

    // Vertical Timing (lines)
    localparam V_DISPLAY_PERIOD = 240; // Visible height
    localparam V_FRONT_PORCH    = 2;   // Approx
    localparam V_SYNC_PULSE     = 2;   // Scanlines for VSYNC pulse
    localparam V_BACK_PORCH     = 18;  // Approx (Spec says 262 total lines)
    localparam V_TOTAL_PERIOD   = V_DISPLAY_PERIOD + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH; // 240+2+2+18 = 262

    // Counters
    reg [9:0] h_counter; // Max H_TOTAL_PERIOD (e.g., 318)
    reg [9:0] v_counter; // Max V_TOTAL_PERIOD (e.g., 262)

    // Active display area signals
    reg h_active;
    reg v_active;
    reg display_active; // h_active & v_active

    // Latched VRAM data
    reg [7:0] latched_vram_data;

    // Calculate VRAM address based on counters and scroll registers
    reg [7:0] current_screen_x; // 0-255 during h_active
    reg [7:0] current_screen_y; // 0-239 during v_active

    reg [7:0] source_x; // scrolled X coordinate in the 256-wide bitmap page
    reg [7:0] source_y; // scrolled Y coordinate in the 256-high bitmap page


    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            h_counter <= 0;
            v_counter <= 0;
            vga_hsync <= 1'b1; // Typically high when inactive
            vga_vsync <= 1'b1; // Typically high when inactive
            h_active <= 1'b0;
            v_active <= 1'b0;
            display_active <= 1'b0;
            drive_vsync_status <= 2'b00; // IN_VBLANK=0, NEW_FRAME=0
            drive_frame_count_increment <= 1'b0;
            vram_addr_out <= 16'h0000;
            vga_rgb <= 8'h00;
            latched_vram_data <= 8'h00;
            current_screen_x <= 8'h00;
            current_screen_y <= 8'h00;
            source_x <= 8'h00;
            source_y <= 8'h00;
        end else begin
            // Horizontal Counter
            if (h_counter == H_TOTAL_PERIOD - 1) begin
                h_counter <= 0;
                // Vertical Counter
                if (v_counter == V_TOTAL_PERIOD - 1) begin
                    v_counter <= 0;
                end else begin
                    v_counter <= v_counter + 1;
                end
            end else begin
                h_counter <= h_counter + 1;
            end

            // HSync Generation (active low)
            if (h_counter >= H_DISPLAY_PERIOD + H_FRONT_PORCH && 
                h_counter < H_DISPLAY_PERIOD + H_FRONT_PORCH + H_SYNC_PULSE) begin
                vga_hsync <= 1'b0;
            end else begin
                vga_hsync <= 1'b1;
            end

            // VSync Generation (active low)
            if (v_counter >= V_DISPLAY_PERIOD + V_FRONT_PORCH &&
                v_counter < V_DISPLAY_PERIOD + V_FRONT_PORCH + V_SYNC_PULSE) begin
                vga_vsync <= 1'b0;
            end else begin
                vga_vsync <= 1'b1;
            end

            // Active Display Area
            h_active <= (h_counter < H_DISPLAY_PERIOD);
            v_active <= (v_counter < V_DISPLAY_PERIOD);
            display_active <= h_active && v_active;

            // VSYNC Status and Frame Count Increment
            if (v_counter >= V_DISPLAY_PERIOD) begin // In VBLANK period
                drive_vsync_status[0] <= 1'b1; // IN_VBLANK = true
                if (v_counter == V_DISPLAY_PERIOD && h_counter == 0) begin // Start of VBLANK (first line, first pixel)
                     drive_vsync_status[1] <= 1'b1; // NEW_FRAME pulse
                     drive_frame_count_increment <= 1'b1;
                end else begin
                     drive_vsync_status[1] <= 1'b0;
                     drive_frame_count_increment <= 1'b0;
                end
            end else begin // Not in VBLANK
                drive_vsync_status[0] <= 1'b0; // IN_VBLANK = false
                drive_vsync_status[1] <= 1'b0; // Ensure NEW_FRAME is a pulse
                drive_frame_count_increment <= 1'b0; // Ensure increment is a pulse
            end
            
            // Latch VRAM data (data read from VRAM based on last cycle's vram_addr_out)
            latched_vram_data <= vram_data_in;

            // Rendering Logic
            if (screen_ctrl_reg_in[0]) begin // DisplayEnable is bit 0
                if (display_active) begin
                    current_screen_x <= h_counter; 
                    current_screen_y <= v_counter; 

                    if (screen_ctrl_reg_in[1] == 1'b0) begin // Mode 0: Bitmap Mode
                        // Apply scroll (simple modulo 256 for X, modulo 240 for Y for this example)
                        source_x <= current_screen_x + vram_scroll_x_in; 
                        source_y <= current_screen_y + vram_scroll_y_in; 
                        
                        // VRAM Address Calculation: (Y * Width) + X
                        // Assuming VRAM is organized as 256 pixels wide for bitmap mode.
                        // source_y determines the "row" (0-239 for visible area after scroll)
                        // source_x determines the "column" (0-255 for visible area after scroll)
                        vram_addr_out <= {source_y, source_x}; // Forms a 16-bit address: YYYYYYYYXXXXXXXX

                        vga_rgb <= latched_vram_data; // Output VRAM data (color index)
                    end else begin // Other modes (Text, Tile, Sprite) - output black for now
                        vga_rgb <= 8'h00;
                        vram_addr_out <= 16'h0000; // Default VRAM address
                    end
                end else begin // Not in active display area (blanking interval)
                    vga_rgb <= 8'h00; // Black
                    vram_addr_out <= 16'h0000; // Default VRAM address
                end
            end else begin // Display disabled
                vga_rgb <= 8'h00; // Black
                vram_addr_out <= 16'h0000; // Default VRAM address
            end
        end
    end

endmodule
