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


    // VRAM Interface (Video Port - for fetching tile patterns or bitmap data)
    input wire [7:0] vram_data_in,
    output reg [15:0] vram_addr_out,

    // Tilemap Definition RAM Interface (to SFR block)
    output reg [11:0] tilemap_def_addr_out,
    input wire [7:0] tilemap_def_data_in,

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
    output reg [7:0] h_coord_out                  // To Sprite Engine (h_coord_visible)
);

    // --- VGA Timing Parameters ---
    localparam H_VISIBLE_PIXELS = 256;
    localparam H_FRONT_PORCH    = 16;
    localparam H_SYNC_PULSE     = 40;
    localparam H_BACK_PORCH     = 29;
    localparam H_TOTAL_PIXELS   = H_VISIBLE_PIXELS + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH; // 341

    localparam V_VISIBLE_LINES  = 240;
    localparam V_FRONT_PORCH    = 10;
    localparam V_SYNC_PULSE     = 2;
    localparam V_BACK_PORCH     = 10;
    localparam V_TOTAL_LINES    = V_VISIBLE_LINES + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH; // 262

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

    reg [7:0] vram_bg_color_index_pipe; // To hold the VRAM pixel color for sprite engine input


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
            fetch_tile_entry_byte0_next <= 0;
            fetch_tile_entry_byte1_next <= 0;
        end else begin
            // Horizontal & Vertical Counters
            if (h_count_total == H_TOTAL_PIXELS - 1) begin
                h_count_total <= 0; h_coord_visible <= 0; current_screen_column_x_out <= 0; h_coord_out <= 0;
                if (v_count_total == V_TOTAL_LINES - 1) begin
                    v_count_total <= 0; v_coord_visible <= 0; new_frame_status <= 1'b1; current_scanline_out <= 0;
                end else begin
                    v_count_total <= v_count_total + 1;
                    if (v_draw_active && v_coord_visible < V_VISIBLE_LINES -1) begin
                        v_coord_visible <= v_coord_visible + 1;
                        current_scanline_out <= v_coord_visible + 1;
                    end else if (v_count_total == (V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH) -1 ) {
                         v_coord_visible <= 0; current_scanline_out <= 0;
                    }
                    new_frame_status <= 1'b0;
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
                new_frame_status <= 1'b0;
            end

            vga_hsync <= !((h_count_total >= H_FRONT_PORCH) && (h_count_total < (H_FRONT_PORCH + H_SYNC_PULSE)));
            vga_vsync <= !((v_count_total >= V_FRONT_PORCH) && (v_count_total < (V_FRONT_PORCH + V_SYNC_PULSE)));
            in_vblank_status <= !((v_count_total >= (V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH)) &&
                                (v_count_total < (V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH + V_VISIBLE_LINES)));

            if (fetch_tile_entry_byte0_next) begin
                tilemap_def_addr_out <= tile_entry_addr_pipe;
                fetch_tile_entry_byte0_next <= 1'b0;
                fetch_tile_entry_byte1_next <= 1'b1;
            end else if (fetch_tile_entry_byte1_next) begin
                tile_id_pipe <= tilemap_def_data_in;
                tilemap_def_addr_out <= tile_entry_addr_pipe + 1;
                fetch_tile_entry_byte1_next <= 1'b0;
            end
        end
    end

    assign h_draw_active = (h_count_total >= (H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH)) &&
                           (h_count_total < (H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH + H_VISIBLE_PIXELS));
    assign v_draw_active = (v_count_total >= (V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH)) &&
                           (v_count_total < (V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH + V_VISIBLE_LINES));

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
                    // It needs to set vram_addr_out for pattern fetch.
                    // The result (vram_data_in) will be used in the *next* cycle by sprite engine.
                    if (!fetch_tile_entry_byte0_next && !fetch_tile_entry_byte1_next) { // Tile def is ready
                        reg tile_flip_x_eff = tile_attr_pipe[7];
                        reg tile_flip_y_eff = tile_attr_pipe[6];
                        // pixel_x_in_tile_pipe and pixel_y_in_tile_pipe are for the current screen pixel
                        pixel_x_in_tile_pipe <= effective_source_x_pre_flip % TILE_WIDTH_PX;
                        pixel_y_in_tile_pipe <= effective_source_y_pre_flip % TILE_HEIGHT_PX;

                        reg [2:0] final_pixel_x = tile_flip_x_eff ? (7 - pixel_x_in_tile_pipe) : pixel_x_in_tile_pipe;
                        reg [2:0] final_pixel_y = tile_flip_y_eff ? (7 - pixel_y_in_tile_pipe) : pixel_y_in_tile_pipe;

                        vram_addr_out <= VRAM_TILE_PATTERN_BASE_ADDR +
                                         (tile_id_pipe * BYTES_PER_TILE_PATTERN) +
                                         (final_pixel_y * BYTES_PER_TILE_PATTERN_ROW) +
                                         final_pixel_x * BYTES_PER_TILE_PATTERN_PIXEL;

                        // The vram_data_in from this address will be used next cycle to form the bg color
                        // Store it for the sprite engine.
                        vram_bg_color_index_pipe <= {tile_attr_pipe[3:0], vram_data_in[3:0]}; // Combine with tile's palette
                    } else { // Still fetching tile def
                        vram_bg_color_index_pipe <= 8'h00; // Default to transparent/black
                    }

                    // Trigger tile definition fetch if new tile is entered
                    reg [7:0] current_tile_map_col = (effective_source_x_pre_flip / TILE_WIDTH_PX) % (mirror_x_map ? (TILEMAP_WIDTH_IN_TILES*2) : TILEMAP_WIDTH_IN_TILES);
                    reg [7:0] current_tile_map_row = (effective_source_y_pre_flip / TILE_HEIGHT_PX) % (mirror_y_map ? (TILEMAP_HEIGHT_IN_TILES*2) : TILEMAP_HEIGHT_IN_TILES);
                    if ( (pixel_x_in_tile_pipe == 0 && pixel_y_in_tile_pipe == 0 && h_coord_visible > 0 && v_coord_visible > 0) || (h_coord_visible == 0 && v_coord_visible == 0) ) { // Start of new tile or frame
                         tile_entry_addr_pipe <= (current_tile_map_row * TILEMAP_WIDTH_IN_TILES * BYTES_PER_TILE_DEF) +
                                                 (current_tile_map_col * BYTES_PER_TILE_DEF);
                         fetch_tile_entry_byte0_next <= 1'b1;
                    }
                }
                // The final color index is now from the sprite engine
                reg [7:0] final_color_for_palette;
                final_color_for_palette = sprite_final_pixel_color_in; // Use sprite engine's output

                vga_r <= palette_ram[final_color_for_palette][7:5];
                vga_g <= palette_ram[final_color_for_palette][4:2];
                vga_b <= palette_ram[final_color_for_palette][1:0];

            end else { // Not active display area
                vram_addr_out <= 16'h0000;
                vga_r <= 3'b000; vga_g <= 3'b000; vga_b <= 2'b00;
                vram_bg_color_index_pipe <= 8'h00;
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
