// FCVM/fc8_sprite_engine.v
`include "fc8_defines.v"

module fc8_sprite_engine (
    input wire clk_pixel, // Pixel clock
    input wire rst_n,

    // Inputs from fc8_graphics
    input wire [7:0] current_scanline_in, // Current visible scanline (0-239)
    input wire [7:0] h_coord_in,          // Current horizontal pixel coordinate on screen (0-255)
    input wire [7:0] vram_pixel_color_in, // Background pixel color index from graphics (tile/bitmap)

    // Inputs from (or via) fc8_sfr_block
    input wire [7:0] sat_data_in,       // Data from SAT read port on SFR block

    // Inputs from fc8_cart_rom (or MMU if patterns are elsewhere)
    input wire [7:0] rom_data_in,       // Sprite pattern data from ROM read port

    // Stubbed inputs (for future text layer integration)
    input wire [7:0] text_pixel_color_in, // Tied to transparent for now
    input wire       text_priority_in,    // Tied to low priority for now

    // Outputs
    output reg [7:0] final_pixel_color_out, // Final color index to graphics palette lookup
    output reg [9:0] sat_addr_out,        // Address to SAT read port on SFR block
    output reg [19:0] rom_addr_out,       // Physical address to Cartridge ROM (20-bit for 1MB space)
    output reg        rom_rd_en_out       // Read enable for ROM
);

    localparam MAX_SPRITES_PER_SCANLINE = 8;
    localparam SAT_ENTRY_SIZE = 4; // Bytes per sprite entry in SAT
    localparam MAX_SAT_ENTRIES = 64; // Total number of sprites in SAT

    // Sprite attributes for active sprites on the current scanline
    typedef struct packed {
        logic [7:0] y_coord;    // Byte 0
        logic [7:0] tile_id;    // Byte 1
        logic [7:0] attributes; // Byte 2 (VHPNSCCC - VFlip, HFlip, Priority, NameTable, SpritePalette)
        logic [7:0] x_coord;    // Byte 3
        logic valid;            // Is this slot active?
        logic [3:0] pattern_row_idx_in_sprite; // 0-15, which row of the 16x16 sprite pattern
    } sprite_scanline_info_t;

    sprite_scanline_info_t active_sprites [0:MAX_SPRITES_PER_SCANLINE-1];

    // Line buffers for (up to) 8 active sprites' pattern data for the current row
    // Each sprite is 16 pixels wide. Each pixel is 1 byte from ROM (lower nibble is color index)
    reg [7:0] sprite_line_buffers [0:MAX_SPRITES_PER_SCANLINE-1][0:15]; // 8 sprites, 16 pixels/row each

    // State machine for SAT processing and pattern fetching (during HBLANK ideally)
    typedef enum {
        S_IDLE,
        S_READ_SAT_Y,
        S_READ_SAT_ID,
        S_READ_SAT_ATTR,
        S_READ_SAT_X,
        S_EVAL_SPRITE,
        S_FETCH_PATTERN_START,
        S_FETCH_PATTERN_ROW_BYTE_0, // Byte 0 of 16 for a sprite row
        S_FETCH_PATTERN_ROW_BYTE_1,
        // ... up to S_FETCH_PATTERN_ROW_BYTE_15
        S_FETCH_PATTERN_ROW_DONE
    } sprite_fsm_state_e;
    sprite_fsm_state_e sprite_fsm_state;

    reg [6:0] current_sat_index; // 0-63, for iterating through SAT
    reg [2:0] active_sprite_count; // Number of active sprites found for this scanline (0-8)
    reg [2:0] current_fetch_sprite_idx; // Index into active_sprites for pattern fetching
    reg [3:0] current_fetch_byte_idx;   // 0-15, for fetching 16 bytes of a sprite row pattern

    // --- Scanline Sprite Evaluation (triggered by HBLANK, simplified here) ---
    // This process should ideally happen during HBLANK before the scanline starts drawing.
    // For now, we'll make it a state machine that runs, assuming it has enough time.

    always @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            sprite_fsm_state <= S_IDLE;
            current_sat_index <= 0;
            active_sprite_count <= 0;
            sat_addr_out <= 0;
            rom_rd_en_out <= 0;
            for (int i = 0; i < MAX_SPRITES_PER_SCANLINE; i++) active_sprites[i].valid <= 0;
        end else begin
            // Default outputs
            rom_rd_en_out <= 1'b0;

            case (sprite_fsm_state)
                S_IDLE: begin // Wait for start of active display or HBLANK to evaluate sprites
                    // This should ideally be triggered by HBLANK start.
                    // For simulation, let's trigger it when current_scanline_in changes or at frame start.
                    // A real system would use HBLANK.
                    if (h_coord_in == 0) begin // Approximation: Start of scanline processing
                        current_sat_index <= 0;
                        active_sprite_count <= 0;
                        for (int i = 0; i < MAX_SPRITES_PER_SCANLINE; i++) active_sprites[i].valid <= 0;
                        sat_addr_out <= 0; // Start reading SAT from the beginning
                        sprite_fsm_state <= S_READ_SAT_Y;
                    end
                end

                S_READ_SAT_Y: begin
                    active_sprites[active_sprite_count].y_coord <= sat_data_in;
                    sat_addr_out <= (current_sat_index * SAT_ENTRY_SIZE) + 1;
                    sprite_fsm_state <= S_READ_SAT_ID;
                end
                S_READ_SAT_ID: begin
                    active_sprites[active_sprite_count].tile_id <= sat_data_in;
                    sat_addr_out <= (current_sat_index * SAT_ENTRY_SIZE) + 2;
                    sprite_fsm_state <= S_READ_SAT_ATTR;
                end
                S_READ_SAT_ATTR: begin
                    active_sprites[active_sprite_count].attributes <= sat_data_in;
                    sat_addr_out <= (current_sat_index * SAT_ENTRY_SIZE) + 3;
                    sprite_fsm_state <= S_READ_SAT_X;
                end
                S_READ_SAT_X: begin
                    active_sprites[active_sprite_count].x_coord <= sat_data_in;
                    sprite_fsm_state <= S_EVAL_SPRITE;
                end

                S_EVAL_SPRITE: begin
                    if (active_sprites[active_sprite_count].tile_id != 8'hFF && active_sprite_count < MAX_SPRITES_PER_SCANLINE) begin
                        reg [7:0] sprite_y = active_sprites[active_sprite_count].y_coord;
                        // Sprites are 16 pixels high
                        if ((current_scanline_in >= sprite_y) && (current_scanline_in < (sprite_y + 16))) begin
                            active_sprites[active_sprite_count].valid <= 1'b1;
                            active_sprites[active_sprite_count].pattern_row_idx_in_sprite <= current_scanline_in - sprite_y;
                            active_sprite_count <= active_sprite_count + 1;
                        end
                    end
                    if (current_sat_index < MAX_SAT_ENTRIES - 1 && active_sprite_count < MAX_SPRITES_PER_SCANLINE) begin
                        current_sat_index <= current_sat_index + 1;
                        sat_addr_out <= ((current_sat_index + 1) * SAT_ENTRY_SIZE);
                        sprite_fsm_state <= S_READ_SAT_Y;
                    end else begin // Done with SAT scan or filled active sprite list
                        current_fetch_sprite_idx <= 0;
                        current_fetch_byte_idx <= 0;
                        if (active_sprite_count > 0) begin
                            sprite_fsm_state <= S_FETCH_PATTERN_START;
                        end else begin
                            sprite_fsm_state <= S_IDLE; // No active sprites
                        end
                    end
                end

                S_FETCH_PATTERN_START: begin
                    if (current_fetch_sprite_idx < active_sprite_count) begin
                        if (active_sprites[current_fetch_sprite_idx].valid) begin
                            reg sprite_y_flip;
                            sprite_y_flip = active_sprites[current_fetch_sprite_idx].attributes[7]; // VFLIP is bit 7
                            reg [3:0] row_to_fetch;
                            row_to_fetch = sprite_y_flip ?
                                (15 - active_sprites[current_fetch_sprite_idx].pattern_row_idx_in_sprite) :
                                active_sprites[current_fetch_sprite_idx].pattern_row_idx_in_sprite;

                            // Sprite patterns are 256 bytes each in ROM (16x16 pixels, 1 byte/pixel)
                            // CART_ROM_SPRITE_PATTERN_BASE assumed to be defined or is 0 if ROM is just patterns.
                            // For now, assume SpriteID * 256 is the base of the sprite pattern in ROM.
                            rom_addr_out <= (active_sprites[current_fetch_sprite_idx].tile_id * 256) +
                                            (row_to_fetch * 16) + // 16 bytes per row
                                            current_fetch_byte_idx;
                            rom_rd_en_out <= 1'b1;
                            sprite_fsm_state <= S_FETCH_PATTERN_ROW_BYTE_0; // Generic state for fetching any byte
                        end else begin // Should not happen if logic is correct
                            current_fetch_sprite_idx <= current_fetch_sprite_idx + 1; // Skip invalid (already filtered)
                            sprite_fsm_state <= S_FETCH_PATTERN_START;
                        end
                    end else { // All active sprites' current scanline data fetched
                        sprite_fsm_state <= S_IDLE;
                    }
                end

                S_FETCH_PATTERN_ROW_BYTE_0: begin // Represents fetching any byte of the row
                    // Store fetched byte
                    sprite_line_buffers[current_fetch_sprite_idx][current_fetch_byte_idx] <= rom_data_in;

                    if (current_fetch_byte_idx == 15) begin // Last byte of this sprite row
                        current_fetch_byte_idx <= 0;
                        current_fetch_sprite_idx <= current_fetch_sprite_idx + 1;
                        sprite_fsm_state <= S_FETCH_PATTERN_START; // Try to fetch for next active sprite
                    end else begin
                        current_fetch_byte_idx <= current_fetch_byte_idx + 1;
                        // Address for next byte of the same sprite row
                         rom_addr_out <= rom_addr_out + 1; // Assumes sequential bytes in ROM for the row
                         rom_rd_en_out <= 1'b1;
                        // Stay in S_FETCH_PATTERN_ROW_BYTE_0 effectively
                    end
                end
                // Note: S_FETCH_PATTERN_ROW_BYTE_1 ... _15 are not needed with this loop structure for bytes.

                default: sprite_fsm_state <= S_IDLE;
            endcase
        end
    end


    // --- Pixel Generation and Mixing (per pixel clock) ---
    always @(posedge clk_pixel) begin
        if (!rst_n) begin
            final_pixel_color_out <= 8'h00;
        end else begin
            reg [7:0] output_color_idx;
            output_color_idx = vram_pixel_color_in; // Start with background color

            // Iterate through active sprites for the current pixel
            // Sprites with lower SAT index have priority. Our active_sprites array is filled in SAT order.
            for (int i = 0; i < MAX_SPRITES_PER_SCANLINE; i = i+1) begin
                if (active_sprites[i].valid) begin
                    reg [7:0] sprite_x_coord = active_sprites[i].x_coord;
                    // Check if current h_coord_in is within this sprite's horizontal span (16 pixels)
                    if ((h_coord_in >= sprite_x_coord) && (h_coord_in < (sprite_x_coord + 16))) begin
                        reg [3:0] pixel_col_in_sprite;
                        pixel_col_in_sprite = h_coord_in - sprite_x_coord;

                        if (active_sprites[i].attributes[6]) begin // HFLIP is bit 6
                            pixel_col_in_sprite = 15 - pixel_col_in_sprite;
                        end

                        reg [7:0] fetched_sprite_pixel_byte;
                        fetched_sprite_pixel_byte = sprite_line_buffers[i][pixel_col_in_sprite];

                        reg [3:0] sprite_color_sub_index;
                        sprite_color_sub_index = fetched_sprite_pixel_byte[3:0]; // Lower nibble

                        if (sprite_color_sub_index != 4'h0) begin // Not transparent
                            reg sprite_priority; // 0: behind VRAM, 1: in front of VRAM
                            sprite_priority = active_sprites[i].attributes[5]; // PRIORITY is bit 5

                            reg [3:0] sprite_palette_select;
                            sprite_palette_select = active_sprites[i].attributes[3:0]; // Palette C0-C3

                            reg [7:0] full_sprite_color_idx;
                            full_sprite_color_idx = {sprite_palette_select, sprite_color_sub_index};

                            if (sprite_priority == 1'b1) { // Sprite in front
                                output_color_idx = full_sprite_color_idx;
                            } else { // Sprite behind
                                // If VRAM pixel is transparent (index 0 of its palette), sprite shows
                                // This assumes palette entry 0 of any VRAM sub-palette is the transparent color.
                                // For now, let's assume vram_pixel_color_in $00 is transparent.
                                if (vram_pixel_color_in[3:0] == 4'h0) begin // Check only lower nibble if VRAM is also 4bpp
                                    output_color_idx = full_sprite_color_idx;
                                end
                                // If vram_pixel_color_in is 8bpp, then check if == 8'h00
                                // if (vram_pixel_color_in == 8'h00) begin
                                //    output_color_idx = full_sprite_color_idx;
                                // end
                            }
                        end
                    end
                end
            end
            final_pixel_color_out <= output_color_idx;
        end
    end

endmodule
