// FCVM/fc8_system.v
`include "fc8_defines.v"

module fc8_system (
    input wire master_clk,
    input wire master_rst_n,

    // Gamepad Inputs (for testbench initially)
    input wire [7:0] tb_gamepad1_data,
    input wire [7:0] tb_gamepad2_data,
    input wire       tb_gamepad1_connected,
    input wire       tb_gamepad2_connected,

    output wire cpu_dummy_output
);

    // CPU <-> MMU Interface
    wire [15:0] cpu_mem_addr_out;
    wire [7:0]  cpu_mem_data_to_mmu;
    wire [7:0]  mmu_mem_data_to_cpu;
    wire        cpu_mem_rd_en;
    wire        cpu_mem_wr_en;
    wire        cpu_nmi_req;
    wire        cpu_irq_req;


    // MMU <-> Fixed RAM Interface
    wire [14:0] mmu_fixed_ram_addr_out;
    wire [7:0]  mmu_fixed_ram_data_out;
    wire [7:0]  fixed_ram_data_to_mmu;
    wire        mmu_fixed_ram_wr_en;
    wire        mmu_fixed_ram_cs_en;

    // MMU <-> Cartridge ROM Interface (CPU Port)
    wire [17:0] mmu_cart_rom_cpu_addr; // To ROM CPU port addr
    wire [7:0]  cart_rom_data_from_cpu_port; // From ROM CPU port data
    wire        mmu_cart_rom_cpu_cs;     // To ROM CPU port CS

    // MMU <-> Cartridge ROM Interface (Sprite Port - only CS from MMU)
    wire        mmu_cart_rom_sprite_cs;  // To ROM Sprite port CS

    // Sprite Engine <-> Cartridge ROM Interface (Direct address, data via MMU wires for connection)
    wire [19:0] sprite_engine_rom_addr;   // From Sprite Engine to ROM Sprite port
    wire [7:0]  cart_rom_data_to_sprite_engine; // From ROM Sprite port to Sprite Engine
    wire        sprite_engine_rom_rd_en;  // From Sprite Engine to ROM Sprite port


    // MMU <-> SFR Block Interface (for CPU access to SFRs)
    wire [15:0] mmu_sfr_addr_out;
    wire [7:0]  mmu_sfr_data_to_sfr_block;
    wire [7:0]  sfr_block_data_to_mmu;
    wire        mmu_sfr_wr_en_out;
    wire        mmu_sfr_cs_out;

    // Sprite Engine <-> SFR Block Interface (for SAT read)
    wire [9:0]  sprite_engine_sat_addr_to_sfr;
    wire [7:0]  sfr_sat_data_to_sprite_engine;


    // MMU <-> VRAM (CPU Port) Interface
    wire [15:0] mmu_vram_addr_out;
    wire [7:0]  mmu_vram_data_to_vram;
    wire [7:0]  vram_data_to_mmu;
    wire        mmu_vram_wr_en_out;
    wire        mmu_vram_cs_out;

    // Graphics <-> VRAM (Video Port) Interface
    wire [15:0] graphics_vram_addr_out;
    wire [7:0]  vram_data_to_graphics;

    // SFR Block <-> Graphics Interface (Controls & Status)
    wire        sfr_display_enable_to_graphics;
    wire        sfr_graphics_mode_to_graphics;
    wire [7:0]  sfr_palette_addr_to_graphics;
    wire [7:0]  sfr_palette_data_to_graphics;
    wire        sfr_palette_wr_en_to_graphics;
    wire [7:0]  sfr_scroll_x_to_graphics;
    wire [7:0]  sfr_scroll_y_to_graphics;
    wire [7:0]  sfr_vram_flags_to_graphics;
    wire [7:0]  sfr_sbo_offset_to_graphics;

    wire        graphics_in_vblank_from_graphics;
    wire        graphics_new_frame_from_graphics;
    wire [7:0]  graphics_current_col_x_to_sfr;

    // Graphics <-> SFR Block Interface (for Tilemap Definition RAM access by Graphics)
    wire [11:0] graphics_tilemap_def_addr_to_sfr; // Existing for tilemap
    wire [7:0]  sfr_tilemap_def_data_to_graphics;

    // Graphics <-> SFR Block Interface (for Text Character Map data read by Graphics) - New
    wire [10:0] graphics_text_map_addr_to_sfr;
    wire [7:0]  sfr_text_char_map_data_to_graphics;

    // SFR Block <-> Audio Module Interface (New)
    wire [7:0] sfr_ch1_freq_lo_to_audio, sfr_ch1_freq_hi_to_audio, sfr_ch1_vol_env_to_audio, sfr_ch1_wave_duty_to_audio, sfr_ch1_ctrl_to_audio;
    wire [7:0] sfr_ch2_freq_lo_to_audio, sfr_ch2_freq_hi_to_audio, sfr_ch2_vol_env_to_audio, sfr_ch2_wave_duty_to_audio, sfr_ch2_ctrl_to_audio;
    wire [7:0] sfr_ch3_freq_lo_to_audio, sfr_ch3_freq_hi_to_audio, sfr_ch3_vol_env_to_audio, sfr_ch3_wave_duty_to_audio, sfr_ch3_ctrl_to_audio;
    wire [7:0] sfr_ch4_freq_lo_to_audio, sfr_ch4_freq_hi_to_audio, sfr_ch4_vol_env_to_audio, sfr_ch4_wave_duty_to_audio, sfr_ch4_ctrl_to_audio;
    wire [7:0] sfr_audio_master_vol_to_audio;
    wire       sfr_audio_system_enable_to_audio;
    wire [7:0] audio_pwm_out_from_audio; // Output from fc8_audio

    // Graphics <-> Sprite Engine Interface
    wire [7:0]  graphics_vram_pixel_color_to_sprite; // Background pixel from Graphics
    wire [7:0]  sprite_final_pixel_color_to_graphics; // Final pixel to Graphics Palette lookup
    wire [7:0]  graphics_current_scanline_to_sprite;
    wire [7:0]  graphics_h_coord_to_sprite;


    // SFR Block <-> Interrupt Controller Interface
    wire        sfr_int_enable_vblank; wire  sfr_int_enable_timer; wire sfr_int_enable_external;
    wire [3:0]  sfr_timer_prescaler; wire  sfr_timer_enable;
    wire        sfr_clear_vblank_pending; wire  sfr_clear_timer_pending; wire sfr_clear_external_pending;
    wire        ic_vblank_pending_to_sfr; wire  ic_timer_pending_to_sfr; wire ic_external_pending_to_sfr;

    wire clk_pixel;
    reg [1:0] clk_div_count = 0;
    always @(posedge master_clk or negedge master_rst_n) begin
        if (!master_rst_n) clk_div_count <= 0;
        else clk_div_count <= clk_div_count + 1;
    end
    assign clk_pixel = (clk_div_count == 2'b11 && master_clk);


    fc8_cpu u_cpu (
        .clk(master_clk), .rst_n(master_rst_n),
        .mem_data_in(mmu_mem_data_to_cpu), .mem_addr_out(cpu_mem_addr_out),
        .mem_data_out(cpu_mem_data_to_mmu), .mem_rd_en(cpu_mem_rd_en), .mem_wr_en(cpu_mem_wr_en),
        .nmi_req_in(cpu_nmi_req), .irq_req_in(cpu_irq_req)
    );

    fc8_mmu u_mmu (
        .clk(master_clk), .rst_n(master_rst_n),
        .cpu_addr_in(cpu_mem_addr_out), .cpu_data_in(cpu_mem_data_to_mmu),
        .cpu_rd_en(cpu_mem_rd_en), .cpu_wr_en(cpu_mem_wr_en), .cpu_data_out(mmu_mem_data_to_cpu),
        .fixed_ram_addr_out(mmu_fixed_ram_addr_out), .fixed_ram_data_in(fixed_ram_data_to_mmu),
        .fixed_ram_data_out(mmu_fixed_ram_data_out), .fixed_ram_wr_en(mmu_fixed_ram_wr_en), .fixed_ram_cs_en(mmu_fixed_ram_cs_en),
        .cart_rom_cpu_addr_out(mmu_cart_rom_cpu_addr), .cart_rom_cpu_data_in(cart_rom_data_from_cpu_port), // To ROM CPU Port
        .cart_rom_cpu_cs_en(mmu_cart_rom_cpu_cs),                                                        // To ROM CPU Port CS
        .sprite_rom_addr_in(sprite_engine_rom_addr), .sprite_rom_rd_en_in(sprite_engine_rom_rd_en),         // From Sprite Engine
        .sprite_rom_data_out(cart_rom_data_to_sprite_engine), .cart_rom_sprite_cs_en(mmu_cart_rom_sprite_cs),// To ROM Sprite Port CS & Data
        .vram_addr_out(mmu_vram_addr_out), .vram_data_from_cpu_port(vram_data_to_mmu),
        .vram_data_to_cpu_port(mmu_vram_data_to_vram), .vram_wr_en_out(mmu_vram_wr_en_out), .vram_cs_out(mmu_vram_cs_out),
        .sfr_addr_out(mmu_sfr_addr_out), .sfr_data_from_sfr_block(sfr_block_data_to_mmu),
        .sfr_data_to_sfr_block(mmu_sfr_data_to_sfr_block), .sfr_wr_en_out(mmu_sfr_wr_en_out), .sfr_cs_out(mmu_sfr_cs_out)
    );

    fc8_ram #( .RAM_SIZE(`FIXED_RAM_SIZE_BYTES) ) u_fixed_ram (
        .clk(master_clk), .rst_n(master_rst_n),
        .phy_addr_in(mmu_fixed_ram_addr_out), .phy_data_in(mmu_fixed_ram_data_out),
        .phy_wr_en(mmu_fixed_ram_wr_en), .phy_cs_en(mmu_fixed_ram_cs_en),
        .phy_data_out(fixed_ram_data_to_mmu)
    );

    fc8_cart_rom u_cart_rom (
        .clk(master_clk), .rst_n(master_rst_n),
        .phy_addr_in_cpu(mmu_cart_rom_cpu_addr), .phy_cs_en_cpu(mmu_cart_rom_cpu_cs), // CPU Port
        .phy_data_out_cpu(cart_rom_data_from_cpu_port),
        .phy_addr_in_sprite(sprite_engine_rom_addr), .phy_cs_en_sprite(mmu_cart_rom_sprite_cs), // Sprite Port
        .phy_data_out_sprite(cart_rom_data_to_sprite_engine)
    );

    fc8_sfr_block u_sfr_block (
        .clk(master_clk), .rst_n(master_rst_n),
        .sfr_cs_in(mmu_sfr_cs_out), .sfr_wr_en_in(mmu_sfr_wr_en_out),
        .sfr_addr_in(mmu_sfr_addr_out), .sfr_data_in(mmu_sfr_data_to_sfr_block), .sfr_data_out(sfr_block_data_to_mmu),
        .sfr_display_enable_out(sfr_display_enable_to_graphics), .sfr_graphics_mode_out(sfr_graphics_mode_to_graphics),
        .sfr_palette_addr_out(sfr_palette_addr_to_graphics), .sfr_palette_data_out(sfr_palette_data_to_graphics),
        .sfr_palette_wr_en_out(sfr_palette_wr_en_to_graphics),
        .sfr_scroll_x_out(sfr_scroll_x_to_graphics), .sfr_scroll_y_out(sfr_scroll_y_to_graphics),
        .sfr_vram_flags_out(sfr_vram_flags_to_graphics), .sfr_sbo_offset_data_out(sfr_sbo_offset_to_graphics),
        .graphics_in_vblank_in(graphics_in_vblank_from_graphics), .graphics_new_frame_in(graphics_new_frame_from_graphics),
        .graphics_current_col_x_in(graphics_current_col_x_to_sfr),
        .graphics_tilemap_def_addr_in(graphics_tilemap_def_addr_to_sfr),
        .sfr_tilemap_def_data_out(sfr_tilemap_def_data_to_graphics),
        .sprite_engine_sat_addr_in(sprite_engine_sat_addr_to_sfr), // From Sprite Engine
        .sfr_sat_data_out(sfr_sat_data_to_sprite_engine),         // To Sprite Engine
        .sfr_int_enable_vblank_out(sfr_int_enable_vblank),.sfr_int_enable_timer_out(sfr_int_enable_timer),.sfr_int_enable_external_out(sfr_int_enable_external),
        .sfr_timer_prescaler_out(sfr_timer_prescaler),.sfr_timer_enable_out(sfr_timer_enable),
        .sfr_clear_vblank_pending_out(sfr_clear_vblank_pending),.sfr_clear_timer_pending_out(sfr_clear_timer_pending),.sfr_clear_external_pending_out(sfr_clear_external_pending),
        .ic_vblank_pending_in(ic_vblank_pending_to_sfr),.ic_timer_pending_in(ic_timer_pending_to_sfr),.ic_external_pending_in(ic_external_pending_to_sfr),
        // Gamepad connections
        .gamepad1_data_in(tb_gamepad1_data),
        .gamepad2_data_in(tb_gamepad2_data),
        .gamepad1_connected_in(tb_gamepad1_connected),
        .gamepad2_connected_in(tb_gamepad2_connected),
        // Audio SFR outputs
        .sfr_ch1_freq_lo_out(sfr_ch1_freq_lo_to_audio), .sfr_ch1_freq_hi_out(sfr_ch1_freq_hi_to_audio),
        .sfr_ch1_vol_env_out(sfr_ch1_vol_env_to_audio), .sfr_ch1_wave_duty_out(sfr_ch1_wave_duty_to_audio), .sfr_ch1_ctrl_out(sfr_ch1_ctrl_to_audio),
        .sfr_ch2_freq_lo_out(sfr_ch2_freq_lo_to_audio), .sfr_ch2_freq_hi_out(sfr_ch2_freq_hi_to_audio),
        .sfr_ch2_vol_env_out(sfr_ch2_vol_env_to_audio), .sfr_ch2_wave_duty_out(sfr_ch2_wave_duty_to_audio), .sfr_ch2_ctrl_out(sfr_ch2_ctrl_to_audio),
        .sfr_ch3_freq_lo_out(sfr_ch3_freq_lo_to_audio), .sfr_ch3_freq_hi_out(sfr_ch3_freq_hi_to_audio),
        .sfr_ch3_vol_env_out(sfr_ch3_vol_env_to_audio), .sfr_ch3_wave_duty_out(sfr_ch3_wave_duty_to_audio), .sfr_ch3_ctrl_out(sfr_ch3_ctrl_to_audio),
        .sfr_ch4_freq_lo_out(sfr_ch4_freq_lo_to_audio), .sfr_ch4_freq_hi_out(sfr_ch4_freq_hi_to_audio),
        .sfr_ch4_vol_env_out(sfr_ch4_vol_env_to_audio), .sfr_ch4_wave_duty_out(sfr_ch4_wave_duty_to_audio), .sfr_ch4_ctrl_out(sfr_ch4_ctrl_to_audio),
        .sfr_audio_master_vol_out(sfr_audio_master_vol_to_audio),
        .sfr_audio_system_enable_out(sfr_audio_system_enable_to_audio),
        // Text map RAM interface with Graphics
        .graphics_text_map_addr_in(graphics_text_map_addr_to_sfr),
        .sfr_text_char_map_data_out(sfr_text_char_map_data_to_graphics)
    );

    fc8_vram u_vram (
        .clk(master_clk), .rst_n(master_rst_n),
        .cpu_addr_in(mmu_vram_addr_out), .cpu_data_in(mmu_vram_data_to_vram),
        .cpu_wr_en_in(mmu_vram_wr_en_out), .cpu_cs_in(mmu_vram_cs_out), .cpu_data_out(vram_data_to_mmu),
        .video_addr_in(graphics_vram_addr_out), .video_rd_en_in(1'b1),
        .video_data_out(vram_data_to_graphics)
    );

    fc8_graphics u_graphics (
        .clk_pixel(clk_pixel), .rst_n(master_rst_n),
        .display_enable(sfr_display_enable_to_graphics), .graphics_mode_in(sfr_graphics_mode_to_graphics),
        .palette_addr(sfr_palette_addr_to_graphics), .palette_data(sfr_palette_data_to_graphics), .palette_wr_en(sfr_palette_wr_en_to_graphics),
        .scroll_x_in(sfr_scroll_x_to_graphics), .scroll_y_in(sfr_scroll_y_to_graphics), .vram_flags_in(sfr_vram_flags_to_graphics),
        .current_col_sbo_offset_in(sfr_sbo_offset_to_graphics),
        .sprite_final_pixel_color_in(sprite_final_pixel_color_to_graphics), // Input from Sprite Engine
        .vram_data_in(vram_data_to_graphics), .vram_addr_out(graphics_vram_addr_out),
        .tilemap_def_addr_out(graphics_tilemap_def_addr_to_sfr), .tilemap_def_data_in(sfr_tilemap_def_data_to_graphics),
        .text_map_addr_out(graphics_text_map_addr_to_sfr), .text_map_data_in(sfr_text_char_map_data_to_graphics), // New ports for text map
        .in_vblank_status(graphics_in_vblank_from_graphics), .new_frame_status(graphics_new_frame_from_graphics),
        .current_screen_column_x_out(graphics_current_col_x_to_sfr),
        .current_scanline_out(graphics_current_scanline_to_sprite),
        .h_coord_out(graphics_h_coord_to_sprite)
        // VGA outputs are internal for now
    );

    fc8_audio u_audio_system (
        .clk(master_clk), // Or a specific audio_clk if derived and available
        .rst_n(master_rst_n),

        // Channel 1 Inputs
        .sfr_ch1_freq_lo_in(sfr_ch1_freq_lo_to_audio),
        .sfr_ch1_freq_hi_in(sfr_ch1_freq_hi_to_audio),
        .sfr_ch1_vol_env_in(sfr_ch1_vol_env_to_audio),
        .sfr_ch1_wave_duty_in(sfr_ch1_wave_duty_to_audio),
        .sfr_ch1_ctrl_in(sfr_ch1_ctrl_to_audio),

        // Channel 2 Inputs
        .sfr_ch2_freq_lo_in(sfr_ch2_freq_lo_to_audio),
        .sfr_ch2_freq_hi_in(sfr_ch2_freq_hi_to_audio),
        .sfr_ch2_vol_env_in(sfr_ch2_vol_env_to_audio),
        .sfr_ch2_wave_duty_in(sfr_ch2_wave_duty_to_audio),
        .sfr_ch2_ctrl_in(sfr_ch2_ctrl_to_audio),

        // Channel 3 Inputs
        .sfr_ch3_freq_lo_in(sfr_ch3_freq_lo_to_audio),
        .sfr_ch3_freq_hi_in(sfr_ch3_freq_hi_to_audio),
        .sfr_ch3_vol_env_in(sfr_ch3_vol_env_to_audio),
        .sfr_ch3_wave_duty_in(sfr_ch3_wave_duty_to_audio),
        .sfr_ch3_ctrl_in(sfr_ch3_ctrl_to_audio),

        // Channel 4 Inputs
        .sfr_ch4_freq_lo_in(sfr_ch4_freq_lo_to_audio),
        .sfr_ch4_freq_hi_in(sfr_ch4_freq_hi_to_audio),
        .sfr_ch4_vol_env_in(sfr_ch4_vol_env_to_audio),
        .sfr_ch4_wave_duty_in(sfr_ch4_wave_duty_to_audio),
        .sfr_ch4_ctrl_in(sfr_ch4_ctrl_to_audio),

        // Global Audio Control Inputs
        .sfr_audio_master_vol_in(sfr_audio_master_vol_to_audio),
        .sfr_audio_system_enable_in(sfr_audio_system_enable_to_audio),

        // Audio Output
        .audio_out_pwm(audio_pwm_out_from_audio) // Connect to a top-level output or test signal
    );

    // fc8_audio u_audio ( /* Placeholder for audio module connections */ ); // Original placeholder removed

    fc8_sprite_engine u_sprite_engine (
        .clk_pixel(clk_pixel), .rst_n(master_rst_n),
        .current_scanline_in(graphics_current_scanline_to_sprite),
        .h_coord_in(graphics_h_coord_to_sprite),
        .vram_pixel_color_in(vram_data_to_graphics), // This should be the BG pixel from Graphics *before* sprite mixing
                                                     // Graphics needs to output its BG pixel before it receives final_pixel_color
                                                     // This requires a slight re-arch of graphics pixel output for sprite input.
                                                     // For now, connecting vram_data_to_graphics, assuming it's pre-sprite.
        .text_pixel_color_in(8'h00),    // Stubbed
        .text_priority_in(1'b0),        // Stubbed
        .sat_data_in(sfr_sat_data_to_sprite_engine),
        .rom_data_in(cart_rom_data_to_sprite_engine),
        .final_pixel_color_out(sprite_final_pixel_color_to_graphics),
        .sat_addr_out(sprite_engine_sat_addr_to_sfr),
        .rom_addr_out(sprite_engine_rom_addr),
        .rom_rd_en_out(sprite_engine_rom_rd_en)
    );

    fc8_interrupt_controller u_interrupt_controller (
        .clk_cpu(master_clk), .rst_n(master_rst_n),
        .vblank_nmi_pending_raw(graphics_new_frame_from_graphics),
        .external_irq_pending_raw(1'b0),
        .int_enable_vblank(sfr_int_enable_vblank), .int_enable_timer(sfr_int_enable_timer), .int_enable_external(sfr_int_enable_external),
        .int_status_vblank_clear(sfr_clear_vblank_pending), .int_status_timer_clear(sfr_clear_timer_pending), .int_status_external_clear(sfr_clear_external_pending),
        .timer_prescaler_select(sfr_timer_prescaler), .timer_enable(sfr_timer_enable),
        .cpu_nmi_req(cpu_nmi_req), .cpu_irq_req(cpu_irq_req),
        .vblank_pending_to_sfr(ic_vblank_pending_to_sfr), .timer_pending_to_sfr(ic_timer_pending_to_sfr), .external_pending_to_sfr(ic_external_pending_to_sfr)
    );

    assign cpu_dummy_output = cpu_mem_rd_en | cpu_mem_wr_en;

endmodule
