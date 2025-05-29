`timescale 1ns / 1ps

// FCVM Memory Controller
// Implements the memory map and Special Function Registers (SFRs)
// as per the FCVm Specification (Sections 3 and 15).

module fc8_memory_controller (
    input wire clk,
    input wire rst_n,               // Active-low reset
    input wire [15:0] cpu_addr,      // 16-bit logical address from CPU
    input wire [7:0] cpu_data_in,   // Data from CPU for writes
    output reg [7:0] cpu_data_out,  // Data to CPU for reads
    input wire we,                  // Write enable from CPU (1 for write, 0 for read)
    
    output wire [19:0] phys_addr,   // 20-bit physical address output

    // Cartridge Interface
    input wire [7:0] cart_rom_data, // Data read from cartridge ROM at current phys_addr

    // VRAM Interface
    output reg [7:0] vram_data_out_for_cpu, // VRAM data read by CPU (for consistency if CPU needs to see it)
    input wire [15:0] vram_addr_from_graphics,      // Address from Graphics to read VRAM
    output reg [7:0] vram_data_to_graphics,       // Data from VRAM to Graphics

    // Input System Interface
    input wire [7:0] gamepad1_data, 
    input wire [7:0] gamepad2_data, 
    input wire gamepad1_connected_in,
    input wire gamepad2_connected_in,

    // Interrupt output signals
    output wire timer_irq_out,
    output wire text_irq_out,
    output wire tile_irq_out,
    output wire sprite_irq_out, 
    output wire audio_irq_out,

    // --- Graphics Subsystem Interface (SFRs driven to graphics) ---
    output wire [7:0] screen_ctrl_to_graphics,    
    output wire [7:0] scroll_x_to_graphics,       
    output wire [7:0] scroll_y_to_graphics,       
    input wire [1:0] vsync_status_from_graphics, 
    input wire frame_count_inc_from_graphics,

    // --- Audio System SFR Outputs (to fc8_audio_system) ---
    output wire [7:0] audio_ch1_freq_lo_to_audio,
    output wire [7:0] audio_ch1_freq_hi_to_audio,
    output wire [7:0] audio_ch1_vol_env_to_audio,    
    output wire [7:0] audio_ch1_wave_duty_to_audio,  
    output wire [7:0] audio_ch1_ctrl_to_audio,       
    output wire [7:0] audio_ch2_freq_lo_to_audio,
    output wire [7:0] audio_ch2_freq_hi_to_audio,
    output wire [7:0] audio_ch2_vol_env_to_audio,
    output wire [7:0] audio_ch2_wave_duty_to_audio,
    output wire [7:0] audio_ch2_ctrl_to_audio,
    output wire [7:0] audio_ch3_freq_lo_to_audio,
    output wire [7:0] audio_ch3_freq_hi_to_audio,
    output wire [7:0] audio_ch3_vol_env_to_audio,
    output wire [7:0] audio_ch3_wave_duty_to_audio,
    output wire [7:0] audio_ch3_ctrl_to_audio,
    output wire [7:0] audio_ch4_freq_lo_to_audio,
    output wire [7:0] audio_ch4_freq_hi_to_audio,
    output wire [7:0] audio_ch4_vol_env_to_audio,
    output wire [7:0] audio_ch4_wave_duty_to_audio,
    output wire [7:0] audio_ch4_ctrl_to_audio,
    output wire [7:0] master_vol_to_audio,        
    output wire [7:0] audio_sys_enable_to_audio   
);

    // --- Physical Memory Map Constants (Section 3) ---
    localparam FIXED_RAM_BASE_ADDR     = 20'h000000;
    localparam FIXED_RAM_END_ADDR      = 20'h007FFF; 
    localparam PAGE_SELECT_REG_PHYS_ADDR = 20'h0000FE;
    localparam RESERVED_PAGE_BASE_ADDR = 20'h008000;
    localparam RESERVED_PAGE_END_ADDR  = 20'h00FFFF;
    localparam VRAM_BASE_ADDR          = 20'h010000;
    localparam VRAM_END_ADDR           = 20'h01FFFF;
    localparam SFR_PAGE_BASE_ADDR      = 20'h020000;
    localparam SFR_PAGE_END_ADDR       = 20'h02FFFF; 
    localparam CART_ROM_BASE_ADDR      = 20'h030000;
    localparam CART_ROM_END_ADDR       = 20'h0FFFFF;

    // --- Memory Declarations ---
    reg [7:0] page_select_reg;      
    reg [7:0] fixed_ram [0:32767];  
    reg [7:0] vram [0:65535];       

    // --- SFR Declarations (Section 15) ---
    localparam SCREEN_BOUND_X1_LO_ADDR = SFR_PAGE_BASE_ADDR + 20'h00; reg [7:0] sfr_screen_bound_x1_lo;
    localparam SCREEN_BOUND_X1_HI_ADDR = SFR_PAGE_BASE_ADDR + 20'h01; reg [7:0] sfr_screen_bound_x1_hi;
    localparam SCREEN_BOUND_Y1_LO_ADDR = SFR_PAGE_BASE_ADDR + 20'h02; reg [7:0] sfr_screen_bound_y1_lo;
    localparam SCREEN_BOUND_Y1_HI_ADDR = SFR_PAGE_BASE_ADDR + 20'h03; reg [7:0] sfr_screen_bound_y1_hi;
    localparam SCREEN_BOUND_X2_LO_ADDR = SFR_PAGE_BASE_ADDR + 20'h04; reg [7:0] sfr_screen_bound_x2_lo;
    localparam SCREEN_BOUND_X2_HI_ADDR = SFR_PAGE_BASE_ADDR + 20'h05; reg [7:0] sfr_screen_bound_x2_hi;
    localparam SCREEN_BOUND_Y2_LO_ADDR = SFR_PAGE_BASE_ADDR + 20'h06; reg [7:0] sfr_screen_bound_y2_lo;
    localparam SCREEN_BOUND_Y2_HI_ADDR = SFR_PAGE_BASE_ADDR + 20'h07; reg [7:0] sfr_screen_bound_y2_hi;
    localparam VRAM_FLAGS_REG_ADDR      = SFR_PAGE_BASE_ADDR + 20'h08; reg [7:0] sfr_vram_flags;
    localparam VRAM_SCROLL_X_LO_ADDR    = SFR_PAGE_BASE_ADDR + 20'h09; reg [7:0] sfr_vram_scroll_x_lo;
    localparam VRAM_SCROLL_X_HI_ADDR    = SFR_PAGE_BASE_ADDR + 20'h0A; reg [7:0] sfr_vram_scroll_x_hi;
    localparam VRAM_SCROLL_Y_LO_ADDR    = SFR_PAGE_BASE_ADDR + 20'h0B; reg [7:0] sfr_vram_scroll_y_lo;
    localparam VRAM_SCROLL_Y_HI_ADDR    = SFR_PAGE_BASE_ADDR + 20'h0C; reg [7:0] sfr_vram_scroll_y_hi;
    localparam AUDIO_CH1_FREQ_LO_ADDR   = SFR_PAGE_BASE_ADDR + 20'h10; reg [7:0] sfr_audio_ch1_freq_lo;
    localparam AUDIO_CH1_FREQ_HI_ADDR   = SFR_PAGE_BASE_ADDR + 20'h11; reg [7:0] sfr_audio_ch1_freq_hi;
    localparam AUDIO_CH1_VOL_ADDR       = SFR_PAGE_BASE_ADDR + 20'h12; reg [3:0] sfr_audio_ch1_vol; 
    localparam AUDIO_CH1_CTRL_ADDR      = SFR_PAGE_BASE_ADDR + 20'h13; reg [7:0] sfr_audio_ch1_ctrl;
    localparam AUDIO_CH2_FREQ_LO_ADDR   = SFR_PAGE_BASE_ADDR + 20'h14; reg [7:0] sfr_audio_ch2_freq_lo;
    localparam AUDIO_CH2_FREQ_HI_ADDR   = SFR_PAGE_BASE_ADDR + 20'h15; reg [7:0] sfr_audio_ch2_freq_hi;
    localparam AUDIO_CH2_VOL_ADDR       = SFR_PAGE_BASE_ADDR + 20'h16; reg [3:0] sfr_audio_ch2_vol;
    localparam AUDIO_CH2_CTRL_ADDR      = SFR_PAGE_BASE_ADDR + 20'h17; reg [7:0] sfr_audio_ch2_ctrl;
    localparam AUDIO_CH3_FREQ_LO_ADDR   = SFR_PAGE_BASE_ADDR + 20'h18; reg [7:0] sfr_audio_ch3_freq_lo;
    localparam AUDIO_CH3_FREQ_HI_ADDR   = SFR_PAGE_BASE_ADDR + 20'h19; reg [7:0] sfr_audio_ch3_freq_hi;
    localparam AUDIO_CH3_VOL_ADDR       = SFR_PAGE_BASE_ADDR + 20'h1A; reg [3:0] sfr_audio_ch3_vol;
    localparam AUDIO_CH3_CTRL_ADDR      = SFR_PAGE_BASE_ADDR + 20'h1B; reg [7:0] sfr_audio_ch3_ctrl;
    localparam AUDIO_CH4_FREQ_LO_ADDR   = SFR_PAGE_BASE_ADDR + 20'h1C; reg [7:0] sfr_audio_ch4_freq_lo;
    localparam AUDIO_CH4_FREQ_HI_ADDR   = SFR_PAGE_BASE_ADDR + 20'h1D; reg [7:0] sfr_audio_ch4_freq_hi;
    localparam AUDIO_CH4_VOL_ADDR       = SFR_PAGE_BASE_ADDR + 20'h1E; reg [3:0] sfr_audio_ch4_vol;
    localparam AUDIO_CH4_CTRL_ADDR      = SFR_PAGE_BASE_ADDR + 20'h1F; reg [7:0] sfr_audio_ch4_ctrl;
    localparam MASTER_AUDIO_CTRL_ADDR   = SFR_PAGE_BASE_ADDR + 20'h20; reg [7:0] sfr_master_audio_ctrl;
    localparam SCREEN_CTRL_REG_ADDR     = SFR_PAGE_BASE_ADDR + 20'h21; reg [7:0] sfr_screen_ctrl;
    localparam PALETTE_ADDR_REG_ADDR    = SFR_PAGE_BASE_ADDR + 20'h22; reg [5:0] sfr_palette_addr; 
    localparam PALETTE_DATA_REG_ADDR    = SFR_PAGE_BASE_ADDR + 20'h23; reg [7:0] sfr_palette_data;
    localparam RAND_NUM_REG_ADDR        = SFR_PAGE_BASE_ADDR + 20'h24; reg [7:0] sfr_rand_num; 
    localparam TEXT_CTRL_REG_ADDR       = SFR_PAGE_BASE_ADDR + 20'h25; reg [7:0] sfr_text_ctrl;
    localparam TIMER_CTRL_REG_ADDR      = SFR_PAGE_BASE_ADDR + 20'h28; reg [7:0] sfr_timer_ctrl;
    localparam TIMER_COUNT_LO_ADDR      = SFR_PAGE_BASE_ADDR + 20'h29; 
    localparam TIMER_COUNT_HI_ADDR      = SFR_PAGE_BASE_ADDR + 20'h2A; 
    reg [15:0] internal_timer_counter; 
    localparam INT_ENABLE_REG_ADDR      = SFR_PAGE_BASE_ADDR + 20'h2B; reg [7:0] sfr_int_enable;
    localparam INT_STATUS_REG_ADDR      = SFR_PAGE_BASE_ADDR + 20'h2C; reg [7:0] sfr_int_status; 
    localparam TEXT_CHAR_MAP_LO_ADDR    = SFR_PAGE_BASE_ADDR + 20'h2D; reg [7:0] sfr_text_char_map_lo;
    localparam TEXT_CHAR_MAP_HI_ADDR    = SFR_PAGE_BASE_ADDR + 20'h2E; reg [7:0] sfr_text_char_map_hi; 
    localparam TILEMAP_DEF_RAM_LO_ADDR  = SFR_PAGE_BASE_ADDR + 20'h2F; reg [7:0] sfr_tilemap_def_ram_lo;
    localparam TILEMAP_DEF_RAM_HI_ADDR  = SFR_PAGE_BASE_ADDR + 20'h30; reg [7:0] sfr_tilemap_def_ram_hi; 
    
    localparam GAMEPAD1_STATUS_ADDR_SPEC  = SFR_PAGE_BASE_ADDR + 20'h0600; 
    localparam GAMEPAD2_STATUS_ADDR_SPEC  = SFR_PAGE_BASE_ADDR + 20'h0601; 
    localparam INPUT_STATUS_REG_ADDR_SPEC = SFR_PAGE_BASE_ADDR + 20'h0602; 
    reg [1:0] sfr_input_connection_status; 

    localparam VSYNC_STATUS_REG_ADDR    = SFR_PAGE_BASE_ADDR + 20'h33; reg [1:0] sfr_vsync_status; 
    localparam FRAME_COUNT_LO_ADDR      = SFR_PAGE_BASE_ADDR + 20'h34; 
    localparam FRAME_COUNT_HI_ADDR      = SFR_PAGE_BASE_ADDR + 20'h35; 
    reg [15:0] sfr_frame_counter;
    reg [7:0] internal_frame_count_hi_latched; 

    localparam SPRITE_ATTR_RAM_BASE_ADDR = SFR_PAGE_BASE_ADDR + 20'h100;
    localparam SPRITE_ATTR_RAM_END_ADDR  = SFR_PAGE_BASE_ADDR + 20'h1FF;
    reg [7:0] sprite_attr_ram [0:255];

    assign phys_addr = (cpu_addr < 16'h8000) ? {4'b0000, cpu_addr} : 
                                             {page_select_reg[4:0], cpu_addr[14:0]};

    integer k_init; 
    initial begin
        for (k_init = 0; k_init < 32768; k_init = k_init + 1) fixed_ram[k_init] = 8'h00;
        for (k_init = 0; k_init < 65536; k_init = k_init + 1) vram[k_init] = 8'h00;
        sfr_rand_num = 8'hA5; 
    end
    
    assign timer_irq_out  = sfr_int_status[0] & sfr_int_enable[0]; 
    assign text_irq_out   = sfr_int_status[2] & sfr_int_enable[2]; 
    assign tile_irq_out   = sfr_int_status[3] & sfr_int_enable[3]; 
    assign sprite_irq_out = sfr_int_status[4] & sfr_int_enable[4]; 
    assign audio_irq_out  = sfr_int_status[5] & sfr_int_enable[5]; 

    assign screen_ctrl_to_graphics = sfr_screen_ctrl;
    assign scroll_x_to_graphics = sfr_vram_scroll_x_lo; 
    assign scroll_y_to_graphics = sfr_vram_scroll_y_lo; 

    assign audio_ch1_freq_lo_to_audio   = sfr_audio_ch1_freq_lo;
    assign audio_ch1_freq_hi_to_audio   = sfr_audio_ch1_freq_hi;
    assign audio_ch1_vol_env_to_audio   = {sfr_audio_ch1_vol, sfr_audio_ch1_ctrl[3:0]}; 
    assign audio_ch1_wave_duty_to_audio = sfr_audio_ch1_ctrl; 
    assign audio_ch1_ctrl_to_audio      = sfr_audio_ch1_ctrl; 
    assign audio_ch2_freq_lo_to_audio   = sfr_audio_ch2_freq_lo;
    assign audio_ch2_freq_hi_to_audio   = sfr_audio_ch2_freq_hi;
    assign audio_ch2_vol_env_to_audio   = {sfr_audio_ch2_vol, sfr_audio_ch2_ctrl[3:0]};
    assign audio_ch2_wave_duty_to_audio = sfr_audio_ch2_ctrl;
    assign audio_ch2_ctrl_to_audio      = sfr_audio_ch2_ctrl;
    assign audio_ch3_freq_lo_to_audio   = sfr_audio_ch3_freq_lo;
    assign audio_ch3_freq_hi_to_audio   = sfr_audio_ch3_freq_hi;
    assign audio_ch3_vol_env_to_audio   = {sfr_audio_ch3_vol, sfr_audio_ch3_ctrl[3:0]};
    assign audio_ch3_wave_duty_to_audio = sfr_audio_ch3_ctrl;
    assign audio_ch3_ctrl_to_audio      = sfr_audio_ch3_ctrl;
    assign audio_ch4_freq_lo_to_audio   = sfr_audio_ch4_freq_lo;
    assign audio_ch4_freq_hi_to_audio   = sfr_audio_ch4_freq_hi;
    assign audio_ch4_vol_env_to_audio   = {sfr_audio_ch4_vol, sfr_audio_ch4_ctrl[3:0]};
    assign audio_ch4_wave_duty_to_audio = sfr_audio_ch4_ctrl;
    assign audio_ch4_ctrl_to_audio      = sfr_audio_ch4_ctrl;
    assign master_vol_to_audio        = sfr_master_audio_ctrl; 
    assign audio_sys_enable_to_audio  = sfr_master_audio_ctrl; 

    always @(posedge clk) begin 
        vram_data_to_graphics <= vram[vram_addr_from_graphics];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            page_select_reg <= 8'h00;
            sfr_screen_bound_x1_lo <= 8'h00; sfr_screen_bound_x1_hi <= 8'h00; 
            sfr_screen_bound_y1_lo <= 8'h00; sfr_screen_bound_y1_hi <= 8'h00; 
            sfr_screen_bound_x2_lo <= 8'h3F; sfr_screen_bound_x2_hi <= 8'h01; 
            sfr_screen_bound_y2_lo <= 8'hDF; sfr_screen_bound_y2_hi <= 8'h00; 
            sfr_vram_flags         <= 8'h00; 
            sfr_vram_scroll_x_lo   <= 8'h00; sfr_vram_scroll_x_hi <= 8'h00;
            sfr_vram_scroll_y_lo   <= 8'h00; sfr_vram_scroll_y_hi <= 8'h00;
            sfr_audio_ch1_freq_lo  <= 8'h00; sfr_audio_ch1_freq_hi <= 8'h00;
            sfr_audio_ch1_vol      <= 4'h0;  sfr_audio_ch1_ctrl    <= 8'h00; 
            sfr_audio_ch2_freq_lo  <= 8'h00; sfr_audio_ch2_freq_hi <= 8'h00;
            sfr_audio_ch2_vol      <= 4'h0;  sfr_audio_ch2_ctrl    <= 8'h00;
            sfr_audio_ch3_freq_lo  <= 8'h00; sfr_audio_ch3_freq_hi <= 8'h00;
            sfr_audio_ch3_vol      <= 4'h0;  sfr_audio_ch3_ctrl    <= 8'h00;
            sfr_audio_ch4_freq_lo  <= 8'h00; sfr_audio_ch4_freq_hi <= 8'h00;
            sfr_audio_ch4_vol      <= 4'h0;  sfr_audio_ch4_ctrl    <= 8'h00;
            sfr_master_audio_ctrl  <= 8'h00; 
            sfr_screen_ctrl        <= 8'h00; 
            sfr_palette_addr       <= 6'h00;
            sfr_palette_data       <= 8'h00; 
            sfr_text_ctrl          <= 8'h00; 
            sfr_timer_ctrl         <= 8'h00; 
            internal_timer_counter <= 16'h0000;
            sfr_int_enable         <= 8'h00; 
            sfr_int_status         <= 8'h00; 
            sfr_text_char_map_lo   <= 8'h00; sfr_text_char_map_hi <= 8'h00; 
            sfr_tilemap_def_ram_lo <= 8'h00; sfr_tilemap_def_ram_hi <= 8'h00;
            sfr_vsync_status <= 2'b00; 
            sfr_frame_counter <= 16'h0000;
            internal_frame_count_hi_latched <= 8'h00;
            sfr_input_connection_status <= 2'b00; 
            cpu_data_out <= 8'h00;
            vram_data_out_for_cpu <= 8'h00;
        end else begin
            cpu_data_out <= 8'hFF; 
            vram_data_out_for_cpu <= vram_data_out_for_cpu; 

            sfr_vsync_status[0] <= vsync_status_from_graphics[0]; 
            if (vsync_status_from_graphics[1]) begin 
                sfr_vsync_status[1] <= 1'b1; 
            end
            if (frame_count_inc_from_graphics) begin 
                sfr_frame_counter <= sfr_frame_counter + 1;
            end
            sfr_input_connection_status[0] <= gamepad1_connected_in;
            sfr_input_connection_status[1] <= gamepad2_connected_in;

            if (we) begin
                if (phys_addr == PAGE_SELECT_REG_PHYS_ADDR) page_select_reg <= cpu_data_in;
                else if (phys_addr >= FIXED_RAM_BASE_ADDR && phys_addr <= FIXED_RAM_END_ADDR) fixed_ram[phys_addr[14:0]] <= cpu_data_in;
                else if (phys_addr >= VRAM_BASE_ADDR && phys_addr <= VRAM_END_ADDR) vram[phys_addr[15:0]] <= cpu_data_in;
                else if (phys_addr >= SPRITE_ATTR_RAM_BASE_ADDR && phys_addr <= SPRITE_ATTR_RAM_END_ADDR) sprite_attr_ram[phys_addr - SPRITE_ATTR_RAM_BASE_ADDR] <= cpu_data_in;
                else if (phys_addr == SCREEN_BOUND_X1_LO_ADDR) sfr_screen_bound_x1_lo <= cpu_data_in;
                else if (phys_addr == SCREEN_BOUND_X1_HI_ADDR) sfr_screen_bound_x1_hi <= cpu_data_in;
                else if (phys_addr == SCREEN_BOUND_Y1_LO_ADDR) sfr_screen_bound_y1_lo <= cpu_data_in;
                else if (phys_addr == SCREEN_BOUND_Y1_HI_ADDR) sfr_screen_bound_y1_hi <= cpu_data_in;
                else if (phys_addr == SCREEN_BOUND_X2_LO_ADDR) sfr_screen_bound_x2_lo <= cpu_data_in;
                else if (phys_addr == SCREEN_BOUND_X2_HI_ADDR) sfr_screen_bound_x2_hi <= cpu_data_in;
                else if (phys_addr == SCREEN_BOUND_Y2_LO_ADDR) sfr_screen_bound_y2_lo <= cpu_data_in;
                else if (phys_addr == SCREEN_BOUND_Y2_HI_ADDR) sfr_screen_bound_y2_hi <= cpu_data_in;
                else if (phys_addr == VRAM_FLAGS_REG_ADDR) sfr_vram_flags <= cpu_data_in;
                else if (phys_addr == VRAM_SCROLL_X_LO_ADDR) sfr_vram_scroll_x_lo <= cpu_data_in;
                else if (phys_addr == VRAM_SCROLL_X_HI_ADDR) sfr_vram_scroll_x_hi <= cpu_data_in;
                else if (phys_addr == VRAM_SCROLL_Y_LO_ADDR) sfr_vram_scroll_y_lo <= cpu_data_in;
                else if (phys_addr == VRAM_SCROLL_Y_HI_ADDR) sfr_vram_scroll_y_hi <= cpu_data_in;
                else if (phys_addr == AUDIO_CH1_FREQ_LO_ADDR) sfr_audio_ch1_freq_lo <= cpu_data_in;
                else if (phys_addr == AUDIO_CH1_FREQ_HI_ADDR) sfr_audio_ch1_freq_hi <= cpu_data_in;
                else if (phys_addr == AUDIO_CH1_VOL_ADDR) sfr_audio_ch1_vol <= cpu_data_in[3:0];
                else if (phys_addr == AUDIO_CH1_CTRL_ADDR) sfr_audio_ch1_ctrl <= cpu_data_in;
                else if (phys_addr == AUDIO_CH2_FREQ_LO_ADDR) sfr_audio_ch2_freq_lo <= cpu_data_in;
                else if (phys_addr == AUDIO_CH2_FREQ_HI_ADDR) sfr_audio_ch2_freq_hi <= cpu_data_in;
                else if (phys_addr == AUDIO_CH2_VOL_ADDR) sfr_audio_ch2_vol <= cpu_data_in[3:0];
                else if (phys_addr == AUDIO_CH2_CTRL_ADDR) sfr_audio_ch2_ctrl <= cpu_data_in;
                else if (phys_addr == AUDIO_CH3_FREQ_LO_ADDR) sfr_audio_ch3_freq_lo <= cpu_data_in;
                else if (phys_addr == AUDIO_CH3_FREQ_HI_ADDR) sfr_audio_ch3_freq_hi <= cpu_data_in;
                else if (phys_addr == AUDIO_CH3_VOL_ADDR) sfr_audio_ch3_vol <= cpu_data_in[3:0];
                else if (phys_addr == AUDIO_CH3_CTRL_ADDR) sfr_audio_ch3_ctrl <= cpu_data_in;
                else if (phys_addr == AUDIO_CH4_FREQ_LO_ADDR) sfr_audio_ch4_freq_lo <= cpu_data_in;
                else if (phys_addr == AUDIO_CH4_FREQ_HI_ADDR) sfr_audio_ch4_freq_hi <= cpu_data_in;
                else if (phys_addr == AUDIO_CH4_VOL_ADDR) sfr_audio_ch4_vol <= cpu_data_in[3:0];
                else if (phys_addr == AUDIO_CH4_CTRL_ADDR) sfr_audio_ch4_ctrl <= cpu_data_in;
                else if (phys_addr == MASTER_AUDIO_CTRL_ADDR) sfr_master_audio_ctrl <= cpu_data_in;
                else if (phys_addr == SCREEN_CTRL_REG_ADDR) sfr_screen_ctrl <= cpu_data_in;
                else if (phys_addr == PALETTE_ADDR_REG_ADDR) sfr_palette_addr <= cpu_data_in[5:0];
                else if (phys_addr == PALETTE_DATA_REG_ADDR) begin
                    sfr_palette_data <= cpu_data_in;
                    sfr_palette_addr <= sfr_palette_addr + 1; 
                end
                else if (phys_addr == RAND_NUM_REG_ADDR) sfr_rand_num <= cpu_data_in; 
                else if (phys_addr == TEXT_CTRL_REG_ADDR) sfr_text_ctrl <= cpu_data_in;
                else if (phys_addr == TIMER_CTRL_REG_ADDR) sfr_timer_ctrl <= cpu_data_in;
                else if (phys_addr == INT_ENABLE_REG_ADDR) sfr_int_enable <= cpu_data_in;
                else if (phys_addr == INT_STATUS_REG_ADDR) sfr_int_status <= sfr_int_status & (~cpu_data_in); 
                else if (phys_addr == TEXT_CHAR_MAP_LO_ADDR) sfr_text_char_map_lo <= cpu_data_in;
                else if (phys_addr == TEXT_CHAR_MAP_HI_ADDR) sfr_text_char_map_hi <= cpu_data_in;
                else if (phys_addr == TILEMAP_DEF_RAM_LO_ADDR) sfr_tilemap_def_ram_lo <= cpu_data_in;
                else if (phys_addr == TILEMAP_DEF_RAM_HI_ADDR) sfr_tilemap_def_ram_hi <= cpu_data_in;
            end
            else begin 
                if (phys_addr == PAGE_SELECT_REG_PHYS_ADDR) cpu_data_out <= page_select_reg;
                else if (phys_addr >= FIXED_RAM_BASE_ADDR && phys_addr <= FIXED_RAM_END_ADDR) cpu_data_out <= fixed_ram[phys_addr[14:0]];
                else if (phys_addr >= RESERVED_PAGE_BASE_ADDR && phys_addr <= RESERVED_PAGE_END_ADDR) cpu_data_out <= 8'hFF;
                else if (phys_addr >= VRAM_BASE_ADDR && phys_addr <= VRAM_END_ADDR) begin
                    cpu_data_out <= vram[phys_addr[15:0]];
                    vram_data_out_for_cpu <= vram[phys_addr[15:0]]; 
                end
                else if (phys_addr >= SPRITE_ATTR_RAM_BASE_ADDR && phys_addr <= SPRITE_ATTR_RAM_END_ADDR) cpu_data_out <= sprite_attr_ram[phys_addr - SPRITE_ATTR_RAM_BASE_ADDR];
                else if (phys_addr == SCREEN_BOUND_X1_LO_ADDR) cpu_data_out <= sfr_screen_bound_x1_lo;
                else if (phys_addr == SCREEN_BOUND_X1_HI_ADDR) cpu_data_out <= sfr_screen_bound_x1_hi;
                else if (phys_addr == SCREEN_BOUND_Y1_LO_ADDR) cpu_data_out <= sfr_screen_bound_y1_lo;
                else if (phys_addr == SCREEN_BOUND_Y1_HI_ADDR) cpu_data_out <= sfr_screen_bound_y1_hi;
                else if (phys_addr == SCREEN_BOUND_X2_LO_ADDR) cpu_data_out <= sfr_screen_bound_x2_lo;
                else if (phys_addr == SCREEN_BOUND_X2_HI_ADDR) cpu_data_out <= sfr_screen_bound_x2_hi;
                else if (phys_addr == SCREEN_BOUND_Y2_LO_ADDR) cpu_data_out <= sfr_screen_bound_y2_lo;
                else if (phys_addr == SCREEN_BOUND_Y2_HI_ADDR) cpu_data_out <= sfr_screen_bound_y2_hi;
                else if (phys_addr == VRAM_FLAGS_REG_ADDR) cpu_data_out <= sfr_vram_flags;
                else if (phys_addr == VRAM_SCROLL_X_LO_ADDR) cpu_data_out <= sfr_vram_scroll_x_lo;
                else if (phys_addr == VRAM_SCROLL_X_HI_ADDR) cpu_data_out <= sfr_vram_scroll_x_hi;
                else if (phys_addr == VRAM_SCROLL_Y_LO_ADDR) cpu_data_out <= sfr_vram_scroll_y_lo;
                else if (phys_addr == VRAM_SCROLL_Y_HI_ADDR) cpu_data_out <= sfr_vram_scroll_y_hi;
                else if (phys_addr == AUDIO_CH1_FREQ_LO_ADDR) cpu_data_out <= sfr_audio_ch1_freq_lo;
                else if (phys_addr == AUDIO_CH1_FREQ_HI_ADDR) cpu_data_out <= sfr_audio_ch1_freq_hi;
                else if (phys_addr == AUDIO_CH1_VOL_ADDR) cpu_data_out <= {4'b0000, sfr_audio_ch1_vol};
                else if (phys_addr == AUDIO_CH1_CTRL_ADDR) cpu_data_out <= sfr_audio_ch1_ctrl;
                else if (phys_addr == AUDIO_CH2_FREQ_LO_ADDR) cpu_data_out <= sfr_audio_ch2_freq_lo;
                else if (phys_addr == AUDIO_CH2_FREQ_HI_ADDR) cpu_data_out <= sfr_audio_ch2_freq_hi;
                else if (phys_addr == AUDIO_CH2_VOL_ADDR) cpu_data_out <= {4'b0000, sfr_audio_ch2_vol};
                else if (phys_addr == AUDIO_CH2_CTRL_ADDR) cpu_data_out <= sfr_audio_ch2_ctrl;
                else if (phys_addr == AUDIO_CH3_FREQ_LO_ADDR) cpu_data_out <= sfr_audio_ch3_freq_lo;
                else if (phys_addr == AUDIO_CH3_FREQ_HI_ADDR) cpu_data_out <= sfr_audio_ch3_freq_hi;
                else if (phys_addr == AUDIO_CH3_VOL_ADDR) cpu_data_out <= {4'b0000, sfr_audio_ch3_vol};
                else if (phys_addr == AUDIO_CH3_CTRL_ADDR) cpu_data_out <= sfr_audio_ch3_ctrl;
                else if (phys_addr == AUDIO_CH4_FREQ_LO_ADDR) cpu_data_out <= sfr_audio_ch4_freq_lo;
                else if (phys_addr == AUDIO_CH4_FREQ_HI_ADDR) cpu_data_out <= sfr_audio_ch4_freq_hi;
                else if (phys_addr == AUDIO_CH4_VOL_ADDR) cpu_data_out <= {4'b0000, sfr_audio_ch4_vol};
                else if (phys_addr == AUDIO_CH4_CTRL_ADDR) cpu_data_out <= sfr_audio_ch4_ctrl;
                else if (phys_addr == MASTER_AUDIO_CTRL_ADDR) cpu_data_out <= sfr_master_audio_ctrl;
                else if (phys_addr == SCREEN_CTRL_REG_ADDR) cpu_data_out <= sfr_screen_ctrl;
                else if (phys_addr == PALETTE_ADDR_REG_ADDR) cpu_data_out <= {2'b00, sfr_palette_addr};
                else if (phys_addr == PALETTE_DATA_REG_ADDR) cpu_data_out <= sfr_palette_data;
                else if (phys_addr == RAND_NUM_REG_ADDR) cpu_data_out <= sfr_rand_num;
                else if (phys_addr == TEXT_CTRL_REG_ADDR) cpu_data_out <= sfr_text_ctrl;
                else if (phys_addr == TIMER_CTRL_REG_ADDR) cpu_data_out <= sfr_timer_ctrl;
                else if (phys_addr == TIMER_COUNT_LO_ADDR) cpu_data_out <= internal_timer_counter[7:0];
                else if (phys_addr == TIMER_COUNT_HI_ADDR) cpu_data_out <= internal_timer_counter[15:8];
                else if (phys_addr == INT_ENABLE_REG_ADDR) cpu_data_out <= sfr_int_enable;
                else if (phys_addr == INT_STATUS_REG_ADDR) cpu_data_out <= sfr_int_status;
                else if (phys_addr == TEXT_CHAR_MAP_LO_ADDR) cpu_data_out <= sfr_text_char_map_lo;
                else if (phys_addr == TEXT_CHAR_MAP_HI_ADDR) cpu_data_out <= sfr_text_char_map_hi;
                else if (phys_addr == TILEMAP_DEF_RAM_LO_ADDR) cpu_data_out <= sfr_tilemap_def_ram_lo;
                else if (phys_addr == TILEMAP_DEF_RAM_HI_ADDR) cpu_data_out <= sfr_tilemap_def_ram_hi;
                else if (phys_addr == GAMEPAD1_STATUS_ADDR_SPEC) cpu_data_out <= gamepad1_data; 
                else if (phys_addr == GAMEPAD2_STATUS_ADDR_SPEC) cpu_data_out <= gamepad2_data; 
                else if (phys_addr == INPUT_STATUS_REG_ADDR_SPEC) cpu_data_out <= {6'b000000, sfr_input_connection_status}; 
                else if (phys_addr == VSYNC_STATUS_REG_ADDR) begin
                    cpu_data_out <= sfr_vsync_status;
                    sfr_vsync_status[1] <= 1'b0; 
                end
                else if (phys_addr == FRAME_COUNT_LO_ADDR) begin
                    cpu_data_out <= sfr_frame_counter[7:0];
                    internal_frame_count_hi_latched <= sfr_frame_counter[15:8]; 
                end
                else if (phys_addr == FRAME_COUNT_HI_ADDR) cpu_data_out <= internal_frame_count_hi_latched;
                else if (phys_addr >= CART_ROM_BASE_ADDR && phys_addr <= CART_ROM_END_ADDR) cpu_data_out <= cart_rom_data;
            end
            
            if (rst_n && sfr_timer_ctrl[0]) begin 
                internal_timer_counter <= internal_timer_counter + 1;
                if (internal_timer_counter == 16'hFFFF) begin 
                    if (sfr_timer_ctrl[3]) begin 
                        internal_timer_counter <= 16'h0000; 
                    end
                    sfr_int_status[0] <= 1'b1; 
                end
            end else if (!sfr_timer_ctrl[0] && rst_n) begin 
                internal_timer_counter <= 16'h0000;
            end

            if (rst_n) begin 
                sfr_rand_num <= {sfr_rand_num[0] ^ sfr_rand_num[3] ^ sfr_rand_num[4] ^ sfr_rand_num[5], sfr_rand_num[7:1]};
            end
        end
    end
endmodule
