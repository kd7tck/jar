// FCVM/fc8_sfr_block.v
`include "fc8_defines.v"

module fc8_sfr_block (
    input wire clk,
    input wire rst_n,

    input wire        sfr_cs_in,      // Chip select (indicates Page 4: $020000-$027FFF is targeted by MMU)
    input wire        sfr_wr_en_in,
    input wire [15:0] sfr_addr_in,    // Address within the Page 4 window (e.g., $0000-$7FFF from MMU)
    input wire [7:0]  sfr_data_in,

    output reg [7:0] sfr_data_out,

    // Outputs to fc8_graphics (from SFR values)
    output reg sfr_display_enable_out,
    output reg sfr_graphics_mode_out,
    output reg [7:0] sfr_palette_addr_out,
    output reg [7:0] sfr_palette_data_out,
    output reg sfr_palette_wr_en_out,
    output reg [7:0] sfr_scroll_x_out,
    output reg [7:0] sfr_scroll_y_out,
    output reg [7:0] sfr_vram_flags_out,
    output reg [7:0] sfr_sbo_offset_data_out,

    // Inputs from fc8_graphics
    input wire graphics_in_vblank_in,
    input wire graphics_new_frame_in,
    input wire [7:0] graphics_current_col_x_in,
    input wire [11:0] graphics_tilemap_def_addr_in,
    output reg [7:0] sfr_tilemap_def_data_out,

    // New Interface for Sprite Engine to read SAT
    input wire [9:0]  sprite_engine_sat_addr_in, // 10 bits for 1024 bytes (256 entries * 4 bytes)
    output reg [7:0]  sfr_sat_data_out,          // Data from SAT to Sprite Engine

    // Interface with fc8_interrupt_controller (declarations assumed from previous steps)
    output reg sfr_int_enable_vblank_out,
    output reg sfr_int_enable_timer_out,
    output reg sfr_int_enable_external_out,
    output reg [3:0] sfr_timer_prescaler_out,
    output reg sfr_timer_enable_out,
    output reg sfr_clear_vblank_pending_out,
    output reg sfr_clear_timer_pending_out,
    output reg sfr_clear_external_pending_out,
    input wire ic_vblank_pending_in,
    input wire ic_timer_pending_in,
    input wire ic_external_pending_in
);

    // --- Sprite Attribute Table (SAT) ---
    // Physical $020200-$0205FF. Offset within SFR Page 4: $0200-$05FF. Size 1024 bytes.
    localparam SAT_PAGE4_START_OFFSET = 16'h0200;
    localparam SAT_PAGE4_END_OFFSET   = 16'h05FF;
    localparam SAT_SIZE_BYTES         = 1024;
    reg [7:0] sprite_attribute_table_ram [0:SAT_SIZE_BYTES-1]; // Renamed from screen_bounds

    // --- Tilemap Definition RAM ---
    localparam TILEMAP_DEF_RAM_PAGE4_START_OFFSET = 16'h1800;
    localparam TILEMAP_DEF_RAM_PAGE4_END_OFFSET   = 16'h1B7F;
    localparam TILEMAP_DEF_RAM_SIZE_BYTES         = 1920;
    reg [7:0] tilemap_def_ram [0:TILEMAP_DEF_RAM_SIZE_BYTES-1];

    // Other SFRs
    // Screen Bounding Offsets are at $020000 - $0200FF -> sfr_addr_in $0000-$00FF
    // This conflicts with SAT if SAT is $0200.
    // Spec Sec 15 Table:
    // $020000 - $0200FF : Screen Bounding Offsets (256 bytes) -> Page 4, offset $0000 - $00FF
    // $020200 - $0205FF : Sprite Attribute Table (1024 bytes) -> Page 4, offset $0200 - $05FF
    // So, screen_bounds should be distinct from sprite_attribute_table_ram
    reg [7:0] screen_bounding_offsets_ram [0:255]; // For $0000-$00FF on Page 4

    reg [7:0] vram_flags_reg_internal;
    reg [7:0] vram_scroll_x_reg_internal;
    reg [7:0] vram_scroll_y_reg_internal;
    reg [7:0] gamepad1_state_reg;
    reg [7:0] gamepad2_state_reg;
    reg [7:0] input_status_reg;
    reg [7:0] screen_ctrl_reg_internal;
    reg [7:0] palette_addr_reg_internal;
    reg [15:0] internal_frame_counter;
    reg [7:0] rand_num_reg;
    reg [7:0] lfsr;
    reg [7:0] vsync_status_reg_internal;
    reg [7:0] timer_ctrl_reg_internal;
    reg [7:0] int_enable_reg_internal;
    reg [7:0] int_status_reg_internal;


    // --- Reset Values & Logic ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // SAT
            for (integer j = 0; j < SAT_SIZE_BYTES; j = j + 1) begin
                sprite_attribute_table_ram[j] <= 8'h00; // Often $FF for disabled sprites
            end
            // Tilemap Definition RAM
            for (integer k = 0; k < TILEMAP_DEF_RAM_SIZE_BYTES; k = k + 1) begin
                tilemap_def_ram[k] <= 8'h00;
            end
            // Screen Bounding Offsets
            for (integer l = 0; l < 256; l = l + 1) screen_bounding_offsets_ram[l] <= 8'h00;
            // ... (specific screen_bounds initializations if any) ...

            vram_flags_reg_internal <= 8'h00;   sfr_vram_flags_out <= 8'h00;
            vram_scroll_x_reg_internal <= 8'h00; sfr_scroll_x_out <= 8'h00;
            vram_scroll_y_reg_internal <= 8'h00; sfr_scroll_y_out <= 8'h00;
            // ... (reset for other SFRs) ...
            gamepad1_state_reg <= 8'hFF;
            gamepad2_state_reg <= 8'hFF;
            input_status_reg <= 8'b00000001;
            screen_ctrl_reg_internal <= 8'h00;
            sfr_display_enable_out <= 1'b0;
            sfr_graphics_mode_out <= 1'b0;
            palette_addr_reg_internal <= 8'h00;
            sfr_palette_addr_out <= 8'h00;
            internal_frame_counter <= 16'h0000;
            rand_num_reg <= 8'h00;
            lfsr <= 8'hACE;
            vsync_status_reg_internal <= 8'h00;
            timer_ctrl_reg_internal <= 8'h00;
            sfr_timer_prescaler_out <= 4'h0; // From previous step
            sfr_timer_enable_out <= 1'b0;    // From previous step
            int_enable_reg_internal <= 8'h00;
            sfr_int_enable_vblank_out <= 1'b0; // From previous step
            sfr_int_enable_timer_out <= 1'b0;  // From previous step
            sfr_int_enable_external_out <= 1'b0; // From previous step
            int_status_reg_internal <= 8'h00;
            sfr_clear_vblank_pending_out <= 1'b0; // From previous step
            sfr_clear_timer_pending_out <= 1'b0;  // From previous step
            sfr_clear_external_pending_out <= 1'b0; // From previous step
            sfr_sbo_offset_data_out <= 8'h00;
            sfr_tilemap_def_data_out <= 8'h00;
            sfr_sat_data_out <= 8'h00;

        end else begin
            sfr_palette_wr_en_out <= 1'b0;
            sfr_clear_vblank_pending_out <= 1'b0; // Default clear pulses
            sfr_clear_timer_pending_out <= 1'b0;
            sfr_clear_external_pending_out <= 1'b0;

            // CPU Write Access to SFRs
            if (sfr_cs_in && sfr_wr_en_in) begin
                // SAT Write ($0200-$05FF within Page 4)
                if (sfr_addr_in >= SAT_PAGE4_START_OFFSET && sfr_addr_in <= SAT_PAGE4_END_OFFSET) begin
                    sprite_attribute_table_ram[sfr_addr_in - SAT_PAGE4_START_OFFSET] <= sfr_data_in;
                end
                // Tilemap Definition RAM Write ($1800-$1B7F within Page 4)
                else if (sfr_addr_in >= TILEMAP_DEF_RAM_PAGE4_START_OFFSET && sfr_addr_in <= TILEMAP_DEF_RAM_PAGE4_END_OFFSET) begin
                    tilemap_def_ram[sfr_addr_in - TILEMAP_DEF_RAM_PAGE4_START_OFFSET] <= sfr_data_in;
                end
                // Screen Bounding Offsets Write ($0000-$00FF within Page 4)
                else if (sfr_addr_in >= `SCREEN_BOUND_OFFSET_BASE_ADDR && sfr_addr_in <= (`SCREEN_BOUND_OFFSET_BASE_ADDR + 255)) begin
                    screen_bounding_offsets_ram[sfr_addr_in - `SCREEN_BOUND_OFFSET_BASE_ADDR] <= sfr_data_in;
                end
                // ... (other SFR write logic from previous steps) ...
                else if (sfr_addr_in == `VRAM_FLAGS_REG_ADDR) begin
                    vram_flags_reg_internal <= sfr_data_in; sfr_vram_flags_out <= sfr_data_in;
                end
                else if (sfr_addr_in == `VRAM_SCROLL_X_REG_ADDR) begin
                    vram_scroll_x_reg_internal <= sfr_data_in; sfr_scroll_x_out <= sfr_data_in;
                end
                else if (sfr_addr_in == `VRAM_SCROLL_Y_REG_ADDR) begin
                    vram_scroll_y_reg_internal <= sfr_data_in; sfr_scroll_y_out <= sfr_data_in;
                end
                else if (sfr_addr_in == `SCREEN_CTRL_REG_ADDR) begin
                    screen_ctrl_reg_internal <= sfr_data_in;
                    sfr_display_enable_out <= sfr_data_in[0]; sfr_graphics_mode_out  <= sfr_data_in[1];
                end
                else if (sfr_addr_in == `PALETTE_ADDR_REG_ADDR) begin
                    palette_addr_reg_internal <= sfr_data_in; sfr_palette_addr_out <= sfr_data_in;
                end
                else if (sfr_addr_in == `PALETTE_DATA_REG_ADDR) begin
                    sfr_palette_data_out <= sfr_data_in; sfr_palette_addr_out <= palette_addr_reg_internal;
                    sfr_palette_wr_en_out <= 1'b1;
                    palette_addr_reg_internal <= palette_addr_reg_internal + 1;
                    sfr_palette_addr_out <= palette_addr_reg_internal + 1;
                end
                else if (sfr_addr_in == `TIMER_CTRL_REG_ADDR) begin
                    timer_ctrl_reg_internal <= sfr_data_in;
                    sfr_timer_prescaler_out <= sfr_data_in[3:0]; sfr_timer_enable_out <= sfr_data_in[4];
                end
                else if (sfr_addr_in == `INT_ENABLE_REG_ADDR) begin
                    int_enable_reg_internal <= sfr_data_in;
                    sfr_int_enable_vblank_out <= sfr_data_in[0]; sfr_int_enable_timer_out <= sfr_data_in[1];
                    sfr_int_enable_external_out <= sfr_data_in[2];
                end
                else if (sfr_addr_in == `INT_STATUS_REG_ADDR) begin
                    if (sfr_data_in[0]) sfr_clear_vblank_pending_out <= 1'b1;
                    if (sfr_data_in[1]) sfr_clear_timer_pending_out  <= 1'b1;
                    if (sfr_data_in[2]) sfr_clear_external_pending_out <= 1'b1;
                    // Actual update to int_status_reg_internal happens based on IC inputs & these clears
                end
                 else if (sfr_addr_in == `RAND_NUM_REG_ADDR) begin // Ensure this is after specific addresses
                    rand_num_reg <= sfr_data_in;
                    lfsr <= (sfr_data_in == 8'h00) ? 8'hACE : sfr_data_in;
                end
            end

            // Update internal INT_STATUS_REG based on inputs from IC and CPU clears
            if(ic_vblank_pending_in) int_status_reg_internal[0] <= 1'b1;
            if(sfr_clear_vblank_pending_out) int_status_reg_internal[0] <= 1'b0;
            if(ic_timer_pending_in) int_status_reg_internal[1] <= 1'b1;
            if(sfr_clear_timer_pending_out) int_status_reg_internal[1] <= 1'b0;
            if(ic_external_pending_in) int_status_reg_internal[2] <= 1'b1;
            if(sfr_clear_external_pending_out) int_status_reg_internal[2] <= 1'b0;

            lfsr <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
            if (!sfr_wr_en_in || sfr_addr_in != `RAND_NUM_REG_ADDR) begin
                 rand_num_reg <= lfsr;
            end
            vsync_status_reg_internal[0] <= graphics_in_vblank_in;
            if (graphics_new_frame_in) vsync_status_reg_internal[1] <= 1'b1;
            internal_frame_counter <= internal_frame_counter + 1;

            if (graphics_current_col_x_in < 256)
                sfr_sbo_offset_data_out <= screen_bounding_offsets_ram[graphics_current_col_x_in];
            else
                sfr_sbo_offset_data_out <= 8'h00;

            if (graphics_tilemap_def_addr_in < TILEMAP_DEF_RAM_SIZE_BYTES)
                 sfr_tilemap_def_data_out <= tilemap_def_ram[graphics_tilemap_def_addr_in];
            else
                 sfr_tilemap_def_data_out <= 8'h00;

            // Sprite Engine Read Access to SAT
            if (sprite_engine_sat_addr_in < SAT_SIZE_BYTES) begin
                sfr_sat_data_out <= sprite_attribute_table_ram[sprite_engine_sat_addr_in];
            end else begin
                sfr_sat_data_out <= 8'hFF; // Typically $FF for disabled/out of bounds sprite
            end
        end
    end

    // --- CPU Read Logic for SFRs ---
    always @(*) begin
        sfr_data_out = 8'h00;
        if (sfr_cs_in) begin
            // SAT Read ($0200-$05FF within Page 4)
            if (sfr_addr_in >= SAT_PAGE4_START_OFFSET && sfr_addr_in <= SAT_PAGE4_END_OFFSET) begin
                sfr_data_out = sprite_attribute_table_ram[sfr_addr_in - SAT_PAGE4_START_OFFSET];
            end
            // Tilemap Definition RAM Read ($1800-$1B7F within Page 4)
            else if (sfr_addr_in >= TILEMAP_DEF_RAM_PAGE4_START_OFFSET && sfr_addr_in <= TILEMAP_DEF_RAM_PAGE4_END_OFFSET) begin
                sfr_data_out = tilemap_def_ram[sfr_addr_in - TILEMAP_DEF_RAM_PAGE4_START_OFFSET];
            end
            // Screen Bounding Offsets Read ($0000-$00FF within Page 4)
            else if (sfr_addr_in >= `SCREEN_BOUND_OFFSET_BASE_ADDR && sfr_addr_in <= (`SCREEN_BOUND_OFFSET_BASE_ADDR + 255)) begin
                sfr_data_out = screen_bounding_offsets_ram[sfr_addr_in - `SCREEN_BOUND_OFFSET_BASE_ADDR];
            end
            // ... (other SFR read logic from previous steps) ...
            else if (sfr_addr_in == `VRAM_FLAGS_REG_ADDR) sfr_data_out = vram_flags_reg_internal;
            else if (sfr_addr_in == `VRAM_SCROLL_X_REG_ADDR) sfr_data_out = vram_scroll_x_reg_internal;
            else if (sfr_addr_in == `VRAM_SCROLL_Y_REG_ADDR) sfr_data_out = vram_scroll_y_reg_internal;
            else if (sfr_addr_in == `GAMEPAD1_STATE_REG_ADDR) sfr_data_out = gamepad1_state_reg;
            else if (sfr_addr_in == `GAMEPAD2_STATE_REG_ADDR) sfr_data_out = gamepad2_state_reg;
            else if (sfr_addr_in == `INPUT_STATUS_REG_ADDR) sfr_data_out = input_status_reg;
            else if (sfr_addr_in == `SCREEN_CTRL_REG_ADDR) sfr_data_out = screen_ctrl_reg_internal;
            else if (sfr_addr_in == `FRAME_COUNT_LO_REG_ADDR) sfr_data_out = internal_frame_counter[7:0];
            else if (sfr_addr_in == `FRAME_COUNT_HI_REG_ADDR) sfr_data_out = internal_frame_counter[15:8];
            else if (sfr_addr_in == `RAND_NUM_REG_ADDR) sfr_data_out = rand_num_reg;
            else if (sfr_addr_in == `VSYNC_STATUS_REG_ADDR) sfr_data_out = vsync_status_reg_internal;
            else if (sfr_addr_in == `TIMER_CTRL_REG_ADDR) sfr_data_out = timer_ctrl_reg_internal;
            else if (sfr_addr_in == `INT_ENABLE_REG_ADDR) sfr_data_out = int_enable_reg_internal;
            else if (sfr_addr_in == `INT_STATUS_REG_ADDR) sfr_data_out = int_status_reg_internal;
        end
    end

    // Clocked block for read side-effects (VSYNC_STATUS_REG.NEW_FRAME clear)
    always @(posedge clk) begin
        if (!rst_n) begin
            // vsync_status_reg_internal[1] already reset
        end else begin
            if (sfr_cs_in && !sfr_wr_en_in && sfr_addr_in == `VSYNC_STATUS_REG_ADDR) begin
                if (vsync_status_reg_internal[1]) begin
                    vsync_status_reg_internal[1] <= 1'b0;
                end
            end
        end
    end

endmodule
