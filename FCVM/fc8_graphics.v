// FCVM/fc8_graphics.v
`include "fc8_defines.v"

module fc8_graphics (
    input wire clk_pixel,
    input wire rst_n,

    // Control signals from SFRs / System
    input wire display_enable,
    input wire graphics_mode_in,
    input wire [7:0] palette_addr,
    input wire [7:0] palette_data,
    input wire palette_wr_en,
    input wire [7:0] scroll_x_in,
    input wire [7:0] scroll_y_in,
    input wire [7:0] vram_flags_in,
    input wire [7:0] current_col_sbo_offset_in,
    input wire [7:0] sprite_final_pixel_color_in, // From Sprite Engine
    input wire [7:0] sfr_text_ctrl_reg_in, // B0:Enable, B1:Priority, B2:Blink, B3:FontSelect


    // VRAM Interface (Video Port - for fetching tile patterns or bitmap data)
    input wire [7:0] vram_data_in,
    output reg [15:0] vram_addr_out,

    // Tilemap Definition RAM Interface (to SFR block)
    output reg [11:0] tilemap_def_addr_out,
    input wire [7:0] tilemap_def_data_in,

    // Text Character Map RAM Interface (to SFR block)
    output reg [10:0] text_map_addr_out, // For graphics to specify address in text map RAM
    input wire [7:0]  text_map_data_in,  // Data from text map RAM to graphics

    // VGA Outputs
    output reg vga_hsync,
    output reg vga_vsync,
    output reg [2:0] vga_r,
    output reg [2:0] vga_g,
    output reg [1:0] vga_b,

    // Status Signals to SFR Block & Sprite Engine
    output reg in_vblank_status,
    output reg new_frame_status,
    output reg [7:0] current_screen_column_x_out, // To SFR for SBO lookup
    output reg [7:0] current_scanline_out,        // To Sprite Engine (v_coord_visible)
    output reg [7:0] h_coord_out,                 // To Sprite Engine (h_coord_visible)
    output reg [7:0] vram_background_pixel_out,   // VRAM/Tilemap pixel data to Sprite Engine
    output reg [7:0] text_layer_pixel_out         // Text layer pixel data to Sprite Engine
);

    // --- VGA Timing Parameters ---
    localparam H_VISIBLE_PIXELS = 256;
    localparam H_FRONT_PORCH    = 16;
    localparam H_SYNC_PULSE     = 40;
    localparam H_BACK_PORCH     = 29;
    localparam H_TOTAL_PIXELS   = H_VISIBLE_PIXELS + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH; // 341

    localparam V_VISIBLE_LINES  = 240; // Default 240p
    localparam V_FRONT_PORCH    = 10;
    localparam V_SYNC_PULSE     = 2;
    localparam V_BACK_PORCH     = 10;
    localparam V_TOTAL_LINES    = V_VISIBLE_LINES + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH; // 262

    // Parameters for 256-line mode (256p)
    localparam V_VISIBLE_LINES_256 = 256;
    localparam V_FRONT_PORCH_256   = 2;
    localparam V_SYNC_PULSE_256    = 2; // Keep same as 240p
    localparam V_BACK_PORCH_256    = 2;
    // V_TOTAL_LINES remains 262 for 256p mode as well, VBLANK becomes 6 lines.

    localparam SBO_REGION_HEIGHT = 64;

    // Tilemap parameters
    localparam TILEMAP_WIDTH_IN_TILES  = 32;
    localparam TILEMAP_HEIGHT_IN_TILES = 30;
    localparam TILE_WIDTH_PX = 8;
    localparam TILE_HEIGHT_PX = 8;
    localparam BYTES_PER_TILE_DEF = 2;
    localparam BYTES_PER_TILE_PATTERN_PIXEL = 1;
    localparam BYTES_PER_TILE_PATTERN_ROW = TILE_WIDTH_PX * BYTES_PER_TILE_PATTERN_PIXEL;
    localparam BYTES_PER_TILE_PATTERN = TILE_HEIGHT_PX * BYTES_PER_TILE_PATTERN_ROW;
    localparam VRAM_TILE_PATTERN_BASE_ADDR = 16'h8000;


    reg [9:0] h_count_total;
    reg [8:0] v_count_total;
    reg [7:0] h_coord_visible;
    reg [7:0] v_coord_visible;

    wire h_draw_active;
    wire v_draw_active;
    wire active_display_area;

    reg [7:0] palette_ram [0:255];
    // reg [7:0] current_palette_color; // This will be derived from sprite_final_pixel_color_in

    wire mirror_x_map, mirror_y_map;
    wire flip_screen_x, flip_screen_y;
    wire [3:0] coarse_y_offset_flags;

    assign mirror_x_map = vram_flags_in[7];
    assign mirror_y_map = vram_flags_in[6];
    assign flip_screen_x = vram_flags_in[5];
    assign flip_screen_y = vram_flags_in[4];
    assign coarse_y_offset_flags = vram_flags_in[3:0];

    // Pipeline stages for tile rendering
    reg [15:0] tile_entry_addr_pipe;
    reg [7:0] tile_id_pipe;
    reg [7:0] tile_attr_pipe;
    reg fetch_tile_entry_byte0_next;
    reg fetch_tile_entry_byte1_next;

    reg [2:0] pixel_x_in_tile_pipe;
    reg [2:0] pixel_y_in_tile_pipe;

    reg [7:0] vram_bg_color_index_pipe;

    // Text Layer Registers
    reg text_layer_enable;
    reg text_layer_priority;
    // reg text_layer_blink_enable; // For later
    reg text_font_select; // 0=builtin, 1=custom from VRAM

    reg [7:0] text_char_code_pipe;
    reg [7:0] text_char_attr_pipe;
    reg fetch_text_char_byte0_next;
    reg fetch_text_char_byte1_next;
    reg [10:0] current_text_map_entry_addr;
    reg [7:0] current_text_pixel_color_index; // Renamed from text_pixel_color_index

    // Dynamic timing registers based on graphics_mode_in
    reg current_v_visible_lines_reg;
    reg current_v_front_porch_reg;
    reg current_v_sync_pulse_reg;
    reg current_v_back_porch_reg;

    always @(*) begin // Combinational block to set current timings
        if (graphics_mode_in == 1'b1) begin // 256p mode
            current_v_visible_lines_reg = V_VISIBLE_LINES_256;
            current_v_front_porch_reg   = V_FRONT_PORCH_256;
            current_v_sync_pulse_reg    = V_SYNC_PULSE_256;
            current_v_back_porch_reg    = V_BACK_PORCH_256;
        end else begin // 240p mode
            current_v_visible_lines_reg = V_VISIBLE_LINES;
            current_v_front_porch_reg   = V_FRONT_PORCH;
            current_v_sync_pulse_reg    = V_SYNC_PULSE;
            current_v_back_porch_reg    = V_BACK_PORCH;
        end
    end

    always @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            h_count_total <= 0; v_count_total <= 0;
            vga_hsync <= 1'b1; vga_vsync <= 1'b1;
            new_frame_status <= 1'b0; in_vblank_status <= 1'b1;
            h_coord_visible <= 0; v_coord_visible <= 0;
            current_screen_column_x_out <= 0;
            current_scanline_out <= 0;
            h_coord_out <= 0;
            tilemap_def_addr_out <= 0;
            text_map_addr_out <= 0;
            fetch_tile_entry_byte0_next <= 0;
            fetch_tile_entry_byte1_next <= 0;
            vram_background_pixel_out <= 8'h00;
            text_layer_pixel_out <= 8'h00;
            text_layer_enable <= 1'b0; text_layer_priority <= 1'b0; text_font_select <= 1'b0;
            text_char_code_pipe <= 8'h00; text_char_attr_pipe <= 8'h00;
            fetch_text_char_byte0_next <= 1'b0; fetch_text_char_byte1_next <= 1'b0;
            current_text_pixel_color_index <= 8'h00;
        end else begin
            // Latch SFR inputs for text layer (these are not per-pixel)
            text_layer_enable <= sfr_text_ctrl_reg_in[0];
            text_layer_priority <= sfr_text_ctrl_reg_in[1];
            text_font_select <= sfr_text_ctrl_reg_in[3];

            // Horizontal & Vertical Counters
            if (h_count_total == H_TOTAL_PIXELS - 1) begin
                h_count_total <= 0; h_coord_visible <= 0; current_screen_column_x_out <= 0; h_coord_out <= 0;
                if (v_count_total == V_TOTAL_LINES - 1) begin // V_TOTAL_LINES is constant (262)
                    v_count_total <= 0; v_coord_visible <= 0;
                    // new_frame_status set at end of visible lines now
                    current_scanline_out <= 0;
                end else begin
                    v_count_total <= v_count_total + 1;
                    if (v_draw_active && v_coord_visible < current_v_visible_lines_reg -1) begin
                        v_coord_visible <= v_coord_visible + 1;
                        current_scanline_out <= v_coord_visible + 1;
                    end else if (v_count_total == (current_v_front_porch_reg + current_v_sync_pulse_reg + current_v_back_porch_reg) -1 ) {
                         v_coord_visible <= 0; current_scanline_out <= 0;
                    }
                end
            end else begin
                h_count_total <= h_count_total + 1;
                if (h_draw_active && h_coord_visible < H_VISIBLE_PIXELS -1) begin
                    h_coord_visible <= h_coord_visible + 1;
                    current_screen_column_x_out <= h_coord_visible + 1;
                    h_coord_out <= h_coord_visible + 1;
                end else if (h_count_total == (H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH) -1) {
                    h_coord_visible <= 0; current_screen_column_x_out <= 0; h_coord_out <= 0;
                }
            end

            // New Frame Status generation
            if (v_count_total == (current_v_front_porch_reg + current_v_sync_pulse_reg + current_v_back_porch_reg + current_v_visible_lines_reg) -1 &&
                h_count_total == H_TOTAL_PIXELS -1) begin
                new_frame_status <= 1'b1;
            end else begin
                new_frame_status <= 1'b0;
            end

            vga_hsync <= !((h_count_total >= H_FRONT_PORCH) && (h_count_total < (H_FRONT_PORCH + H_SYNC_PULSE)));
            vga_vsync <= !((v_count_total >= current_v_front_porch_reg) && (v_count_total < (current_v_front_porch_reg + current_v_sync_pulse_reg)));
            in_vblank_status <= !((v_count_total >= (current_v_front_porch_reg + current_v_sync_pulse_reg + current_v_back_porch_reg)) &&
                                (v_count_total < (current_v_front_porch_reg + current_v_sync_pulse_reg + current_v_back_porch_reg + current_v_visible_lines_reg)));

            // Tilemap data fetching pipeline
            if (fetch_tile_entry_byte0_next) begin
                tilemap_def_addr_out <= tile_entry_addr_pipe; // Address for Tile ID
                fetch_tile_entry_byte0_next <= 1'b0;
                fetch_tile_entry_byte1_next <= 1'b1;
            end else if (fetch_tile_entry_byte1_next) begin
                tile_id_pipe <= tilemap_def_data_in;
                tilemap_def_addr_out <= tile_entry_addr_pipe + 1; // Address for Tile Attribute
                fetch_tile_entry_byte1_next <= 1'b0;
            end else if (tilemap_def_addr_out == tile_entry_addr_pipe + 1 && active_display_area && graphics_mode_in == 1'b1 && !fetch_tile_entry_byte0_next && !fetch_tile_entry_byte1_next) {
                // This condition implies we were waiting for attribute data after setting address for it.
                // This is part of the tile attribute fetching, ensuring it's latched.
                 tile_attr_pipe <= tilemap_def_data_in; // Fetched attribute for tilemap
            }

            // Text Char Map data fetching pipeline (part of main clocked block)
            if (fetch_text_char_byte0_next) begin
                // text_map_addr_out is set in the drawing logic block when new char cell is entered
                // (or by the line below if current_text_map_entry_addr is ready)
                // text_map_addr_out <= current_text_map_entry_addr; // Set address for Char Code
                fetch_text_char_byte0_next <= 1'b0;
                fetch_text_char_byte1_next <= 1'b1;
            end else if (fetch_text_char_byte1_next) {
                text_char_code_pipe <= text_map_data_in; // Fetched char code
                text_map_addr_out <= current_text_map_entry_addr + 1; // Set address for attribute
                fetch_text_char_byte1_next <= 1'b0;
            } else if (text_map_addr_out == current_text_map_entry_addr + 1 && active_display_area && text_layer_enable && !fetch_text_char_byte0_next && !fetch_text_char_byte1_next) {
                text_char_attr_pipe <= text_map_data_in; // Fetched attribute
            }
        end
    end

    assign h_draw_active = (h_count_total >= (H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH)) && // H timing is fixed
                           (h_count_total < (H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH + H_VISIBLE_PIXELS));
    assign v_draw_active = (v_count_total >= (current_v_front_porch_reg + current_v_sync_pulse_reg + current_v_back_porch_reg)) &&
                           (v_count_total < (current_v_front_porch_reg + current_v_sync_pulse_reg + current_v_back_porch_reg + current_v_visible_lines_reg));

    assign active_display_area = h_draw_active && v_draw_active && display_enable;

    always @(posedge clk_pixel) begin
        if (palette_wr_en) begin
            if (palette_addr < 256) palette_ram[palette_addr] <= palette_data;
        end
    end

    always @(posedge clk_pixel) begin
        if (!rst_n) begin
            vram_addr_out <= 16'h0000;
            vga_r <= 3'b000; vga_g <= 3'b000; vga_b <= 2'b00;
            pixel_x_in_tile_pipe <= 0; pixel_y_in_tile_pipe <= 0;
            tile_id_pipe <= 0; tile_attr_pipe <= 0;
            vram_bg_color_index_pipe <= 8'h00;
        end else begin
            if (active_display_area) begin
                reg [7:0] display_h_coord;
                reg [7:0] display_v_coord;

                display_h_coord = flip_screen_x ? (H_VISIBLE_PIXELS - 1 - h_coord_visible) : h_coord_visible;
                display_v_coord = flip_screen_y ? (V_VISIBLE_LINES - 1 - v_coord_visible) : v_coord_visible;

                reg signed [12:0] coarse_scroll_y_eff;
                coarse_scroll_y_eff = coarse_y_offset_flags[3] ?
                                      ({{9{coarse_y_offset_flags[3]}}, coarse_y_offset_flags} * 16) :
                                      ({coarse_y_offset_flags} * 16);

                reg [15:0] effective_source_x_pre_flip;
                reg [15:0] effective_source_y_pre_flip;

                effective_source_x_pre_flip = scroll_x_in + display_h_coord;
                effective_source_y_pre_flip = scroll_y_in + display_v_coord + coarse_scroll_y_eff;

                if (graphics_mode_in == 1'b0) { // Bitmap mode
                    reg [8:0] map_width_bmp;  map_width_bmp  = mirror_x_map ? 9'd512 : 9'd256;
                    reg [8:0] map_height_bmp; map_height_bmp = mirror_y_map ? 9'd512 : 9'd256;
                    reg [15:0] final_source_x_bitmap;
                    reg [15:0] final_source_y_bitmap;

                    final_source_x_bitmap = effective_source_x_pre_flip % map_width_bmp;
                    final_source_y_bitmap = effective_source_y_pre_flip;
                    if (v_coord_visible >= (V_VISIBLE_LINES - SBO_REGION_HEIGHT)) begin
                        final_source_y_bitmap = (effective_source_y_pre_flip - current_col_sbo_offset_in);
                    end
                    final_source_y_bitmap = final_source_y_bitmap % map_height_bmp;
                    vram_addr_out <= (final_source_y_bitmap * 256) + final_source_x_bitmap;
                    vram_bg_color_index_pipe <= vram_data_in;
                } else { // Tilemap mode
                    if (fetch_tile_entry_byte1_next && !fetch_tile_entry_byte0_next) begin // Just fetched TileID, now have Attr
                         tile_attr_pipe <= tilemap_def_data_in;
                    }

                    // This logic now uses potentially pipelined tile_id_pipe and tile_attr_pipe
                    if (!fetch_tile_entry_byte0_next && !fetch_tile_entry_byte1_next) { // Tile def is ready
                        reg tile_flip_x_from_attr;
                        reg tile_flip_y_from_attr;
                        tile_flip_x_from_attr = tile_attr_pipe[4]; // Corrected based on Spec 9.3
                        tile_flip_y_from_attr = tile_attr_pipe[5]; // Corrected based on Spec 9.3

                        reg [2:0] final_pixel_x_in_tile;
                        reg [2:0] final_pixel_y_in_tile;

                        // pixel_x_in_tile_pipe and pixel_y_in_tile_pipe are for the current screen pixel
                        pixel_x_in_tile_pipe <= effective_source_x_pre_flip % TILE_WIDTH_PX;
                        pixel_y_in_tile_pipe <= effective_source_y_pre_flip % TILE_HEIGHT_PX;

                        final_pixel_x_in_tile = tile_flip_x_from_attr ? (TILE_WIDTH_PX - 1 - pixel_x_in_tile_pipe) : pixel_x_in_tile_pipe;
                        final_pixel_y_in_tile = tile_flip_y_from_attr ? (TILE_HEIGHT_PX - 1 - pixel_y_in_tile_pipe) : pixel_y_in_tile_pipe;

                        vram_addr_out <= VRAM_TILE_PATTERN_BASE_ADDR +
                                         (tile_id_pipe * BYTES_PER_TILE_PATTERN) +
                                         (final_pixel_y_in_tile * BYTES_PER_TILE_PATTERN_ROW) +
                                         final_pixel_x_in_tile * BYTES_PER_TILE_PATTERN_PIXEL;

                        vram_bg_color_index_pipe <= {tile_attr_pipe[3:0], vram_data_in[3:0]};
                    } else {
                        vram_bg_color_index_pipe <= 8'h00;
                    }

                    // Trigger tile definition fetch if new tile is entered
                    reg [7:0] current_tile_map_col = (effective_source_x_pre_flip / TILE_WIDTH_PX) % (mirror_x_map ? (TILEMAP_WIDTH_IN_TILES*2) : TILEMAP_WIDTH_IN_TILES);
                    reg [7:0] current_tile_map_row = (effective_source_y_pre_flip / TILE_HEIGHT_PX) % (mirror_y_map ? (TILEMAP_HEIGHT_IN_TILES*2) : TILEMAP_HEIGHT_IN_TILES);
                    if ( (pixel_x_in_tile_pipe == 0 && pixel_y_in_tile_pipe == 0 && h_coord_visible > 0 && v_coord_visible > 0) || (h_coord_visible == 0 && v_coord_visible == 0) ) {
                         tile_entry_addr_pipe <= (current_tile_map_row * TILEMAP_WIDTH_IN_TILES * BYTES_PER_TILE_DEF) +
                                                 (current_tile_map_col * BYTES_PER_TILE_DEF);
                         fetch_tile_entry_byte0_next <= 1'b1;
                    }
                }
                // The final color index is now from the sprite engine
                vga_r <= palette_ram[sprite_final_pixel_color_in][7:5];
                vga_g <= palette_ram[sprite_final_pixel_color_in][4:2];
                vga_b <= palette_ram[sprite_final_pixel_color_in][1:0];

                vram_background_pixel_out <= vram_bg_color_index_pipe; // Output VRAM BG pixel to sprite engine

                // Text Layer Rendering Logic (Simplified)
                if (text_layer_enable) begin
                    reg [4:0] text_map_col_local; reg [4:0] text_map_row_local;
                    text_map_col_local = display_h_coord[7:3]; // display_h_coord / 8
                    text_map_row_local = display_v_coord[7:3]; // display_v_coord / 8

                    current_text_map_entry_addr = (text_map_row_local * TILEMAP_WIDTH_IN_TILES * BYTES_PER_TILE_DEF) + (text_map_col_local * BYTES_PER_TILE_DEF);

                    if (fetch_text_char_byte0_next) begin
                        text_map_addr_out <= current_text_map_entry_addr;
                        // Handled in main clocked block
                    end else if (fetch_text_char_byte1_next) {
                        // Handled in main clocked block
                    }

                    if (!fetch_text_char_byte0_next && !fetch_text_char_byte1_next) { // Char code & attr are ready
                        reg [2:0] pixel_x_in_char_local; reg [2:0] pixel_y_in_char_local;
                        pixel_x_in_char_local = display_h_coord[2:0]; // display_h_coord % 8
                        pixel_y_in_char_local = display_v_coord[2:0]; // display_v_coord % 8

                        // Placeholder for font lookup (e.g. from a Font ROM or VRAM)
                        // For now, just draw if char_code is 'A' (65)
                        reg font_pixel_on; font_pixel_on = 1'b0;
                        if (text_char_code_pipe == 8'h41 && pixel_y_in_char_local < 7 && pixel_x_in_char_local < 5) { // Basic 'A' shape
                             font_pixel_on = 1'b1; // Simplified
                        }

                        reg [3:0] text_fg_pal_idx_local; reg [3:0] text_bg_pal_idx_local;
                        text_fg_pal_idx_local = text_char_attr_pipe[3:0];
                        text_bg_pal_idx_local = text_char_attr_pipe[7:4];

                        if (font_pixel_on) begin
                            current_text_pixel_color_index <= {text_fg_pal_idx_local, text_fg_pal_idx_local}; // Use palette index directly
                        end else if (text_bg_pal_idx_local != 4'h0) begin // Assuming palette 0 of text is transparent
                            current_text_pixel_color_index <= {text_bg_pal_idx_local, text_bg_pal_idx_local};
                        end else begin
                            current_text_pixel_color_index <= 8'h00; // Transparent
                        end
                    } else {
                        current_text_pixel_color_index <= 8'h00; // Still fetching
                    }
                    text_layer_pixel_out <= current_text_pixel_color_index;

                    // Trigger text char definition fetch (simplified: fetch every pixel for now, needs optimization)
                    // A better trigger would be at the start of each character cell.
                    // current_text_map_entry_addr is calculated above.
                    // Simplified trigger: if starting a new char cell
                    if ( (pixel_x_in_char_local == 0 && pixel_y_in_char_local == 0 && h_coord_visible > 0 && v_coord_visible > 0) || (h_coord_visible == 0 && v_coord_visible == 0) ) {
                         text_map_addr_out <= current_text_map_entry_addr; // Set address for Char Code
                         fetch_text_char_byte0_next <= 1'b1;
                    }

                end else { // Text layer disabled
                    text_layer_pixel_out <= 8'h00; // Transparent
                    current_text_pixel_color_index <= 8'h00;
                }

            end else { // Not active display area
                vram_addr_out <= 16'h0000;
                vga_r <= 3'b000; vga_g <= 3'b000; vga_b <= 2'b00;
                vram_bg_color_index_pipe <= 8'h00;
                vram_background_pixel_out <= 8'h00;
                text_layer_pixel_out <= 8'h00;
                current_text_pixel_color_index <= 8'h00;
            }
        end
    end

    // Reset Palette RAM
    always @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            for (integer i = 0; i < 256; i = i + 1) palette_ram[i] = 8'h00;
            palette_ram[0] = 8'h00; palette_ram[1] = 8'hE7; palette_ram[2] = 8'hC0;
            palette_ram[3] = 8'h24;
        end
    end

endmodule
