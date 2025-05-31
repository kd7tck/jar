// Testbench for fc8_system
`include "FCVM/fc8_defines.v"
`timescale 1ns/1ps

module tb_fc8_system;

    // Inputs
    reg master_clk;
    reg master_rst_n;
    reg [7:0] tb_gamepad1_data;
    reg [7:0] tb_gamepad2_data;
    reg       tb_gamepad1_connected;
    reg       tb_gamepad2_connected;

    // Outputs (if any from fc8_system need to be monitored directly)
    // wire cpu_dummy_output; // Example

    // Instantiate the Unit Under Test (UUT)
    fc8_system uut (
        .master_clk(master_clk),
        .master_rst_n(master_rst_n),
        .tb_gamepad1_data(tb_gamepad1_data),
        .tb_gamepad2_data(tb_gamepad2_data),
        .tb_gamepad1_connected(tb_gamepad1_connected),
        .tb_gamepad2_connected(tb_gamepad2_connected)
        // .cpu_dummy_output(cpu_dummy_output)
    );

    // Clock generation
    initial begin
        master_clk = 0;
        forever #5 master_clk = ~master_clk; // 100MHz clock (10ns period)
    end

    // Reset generation
    initial begin
        master_rst_n = 0;
        tb_gamepad1_data = 8'hFF; // Default no buttons pressed
        tb_gamepad2_data = 8'hFF;
        tb_gamepad1_connected = 1'b0;
        tb_gamepad2_connected = 1'b0;
        #20 master_rst_n = 1;
    end

    // --- Testbench Tasks (Placeholders) ---
    // Task to write to CPU memory space (handles MMU page select if necessary)
    // This would typically involve a CPU model or a way to inject bus cycles.
    // For now, it's a conceptual placeholder.
    /*
    task cpu_write;
        input [15:0] address;
        input [7:0]  data;
        begin
            // TODO: Implement CPU write sequence or use a CPU model
            $display("TB TASK: CPU_WRITE Address: %h, Data: %h", address, data);
        end
    endtask

    task cpu_read;
        input [15:0] address;
        output [7:0] data;
        begin
            // TODO: Implement CPU read sequence or use a CPU model
            data = 8'h00; // Placeholder
            $display("TB TASK: CPU_READ Address: %h, Read Data: %h", address, data);
        end
    endtask
    */

    // Task to load cartridge ROM (fc8_cart_rom.v needs a load mechanism)
    /*
    task load_cartridge_ram;
        input string file_path; // Or array
        begin
            // Example: uut.u_cart_rom.load_program(file_path);
            $display("TB TASK: LOAD_CARTRIDGE_RAM File: %s", file_path);
        end
    endtask
    */

    // Task to set SFR Page Select Register
    task set_sfr_page;
        input [7:0] page_num;
        begin
            $display("TB TASK: SET_SFR_PAGE Page: %h", page_num);
            // This requires a CPU write to `PAGE_SELECT_REG_ADDR` which is at a fixed logical address
            // cpu_write(`PAGE_SELECT_REG_ADDR`, page_num); // Conceptual
            // Direct SFR write for testbench (if CPU model not available for this)
            // This implies we need tasks to simulate CPU writes to SFRs directly for some tests
            // For now, assume cpu_write handles this.
            // Let's simulate a direct write to the SFR block via MMU signals for testing purposes.
            // This is a simplified way to test SFRs without full CPU bus cycles.
            @(posedge master_clk);
            uut.u_mmu.sfr_cs_out_reg <= 1'b1; // Assuming direct access for test
            uut.u_mmu.sfr_wr_en_out_reg <= 1'b1;
            uut.u_mmu.sfr_addr_out_reg <= `PAGE_SELECT_REG_ADDR; // This is logical addr, MMU should map page select itself
                                                              // PAGE_SELECT_REG is special, always accessible.
            uut.u_mmu.sfr_data_to_sfr_block_reg <= page_num;
            @(posedge master_clk);
            uut.u_mmu.sfr_cs_out_reg <= 1'b0;
            uut.u_mmu.sfr_wr_en_out_reg <= 1'b0;
            $display("TB: Set PAGE_SELECT_REG to %h via simulated direct SFR write", page_num);
        end
    endtask

    // Task to write to an SFR register within the currently selected page
    task sfr_write;
        input [15:0] sfr_offset_addr; // e.g., `CH1_FREQ_LO_REG_ADDR`
        input [7:0]  data;
        begin
            $display("TB TASK: SFR_WRITE (current page) Offset: %h, Data: %h", sfr_offset_addr, data);
            @(posedge master_clk);
            // These signals would normally be driven by the MMU based on CPU actions
            uut.u_mmu.sfr_cs_out_reg <= 1'b1;
            uut.u_mmu.sfr_wr_en_out_reg <= 1'b1;
            uut.u_mmu.sfr_addr_out_reg <= sfr_offset_addr;
            uut.u_mmu.sfr_data_to_sfr_block_reg <= data;
            @(posedge master_clk);
            uut.u_mmu.sfr_cs_out_reg <= 1'b0;
            uut.u_mmu.sfr_wr_en_out_reg <= 1'b0;
        end
    endtask

    // Task to read from an SFR register
    task sfr_read;
        input [15:0] sfr_offset_addr;
        output [7:0] data;
        begin
            $display("TB TASK: SFR_READ (current page) Offset: %h", sfr_offset_addr);
            @(posedge master_clk);
            uut.u_mmu.sfr_cs_out_reg <= 1'b1;
            uut.u_mmu.sfr_wr_en_out_reg <= 1'b0; // Read operation
            uut.u_mmu.sfr_addr_out_reg <= sfr_offset_addr;
            @(posedge master_clk); // Allow data to propagate
            data = uut.sfr_block_data_to_mmu; // Assuming this is how data comes back through MMU
            @(posedge master_clk);
            uut.u_mmu.sfr_cs_out_reg <= 1'b0;
            $display("TB TASK: SFR_READ (current page) Offset: %h, Data Read: %h", sfr_offset_addr, data);
        end
    endtask


    // Task to check pixel color (conceptual)
    /*
    task check_pixel_color;
        input integer x, y;
        input [2:0] expected_r, expected_g;
        input [1:0] expected_b;
        begin
            // TODO: Implement pixel checking if VGA output is observable
            // This would involve waiting for specific h_count_total and v_count_total
            // then sampling uut.vga_r, uut.vga_g, uut.vga_b
            $display("TB TASK: CHECK_PIXEL_COLOR X: %d, Y: %d, Expected RGB: %h_%h_%h", x, y, expected_r, expected_g, expected_b);
        end
    endtask
    */

    // Task to check audio register (by reading SFR block output wires)
    task check_audio_reg_output;
        input [1:0] channel; // 0 for CH1, 1 for CH2 etc. 4 for master/system
        input [2:0] reg_type; // 0:FREQ_LO, 1:FREQ_HI, 2:VOL_ENV, 3:WAVE_DUTY, 4:CTRL
                              // For master/system: 0:MASTER_VOL, 1:SYS_CTRL
        input [7:0] expected_value;
        reg [7:0] actual_value;
        begin
            @(posedge master_clk); // Ensure SFR outputs have settled
            case (channel)
                0: case(reg_type) // CH1
                    0: actual_value = uut.sfr_ch1_freq_lo_to_audio;
                    1: actual_value = uut.sfr_ch1_freq_hi_to_audio;
                    2: actual_value = uut.sfr_ch1_vol_env_to_audio;
                    3: actual_value = uut.sfr_ch1_wave_duty_to_audio;
                    4: actual_value = uut.sfr_ch1_ctrl_to_audio;
                    default: $display("TB ERROR: Invalid reg_type for CH1");
                endcase
                // Add cases for CH2, CH3, CH4 similarly
                // ...
                4: case(reg_type) // Global Audio
                    0: actual_value = uut.sfr_audio_master_vol_to_audio;
                    1: actual_value = {7'b0, uut.sfr_audio_system_enable_to_audio}; // Extend enable bit
                    default: $display("TB ERROR: Invalid reg_type for Global Audio");
                endcase
                default: $display("TB ERROR: Invalid audio channel");
            endcase

            if (actual_value === expected_value) begin
                $display("TB CHECK_AUDIO_REG_OUTPUT: Channel %d, RegType %d - Value %h OK", channel, reg_type, actual_value);
            end else begin
                $error("TB CHECK_AUDIO_REG_OUTPUT: Channel %d, RegType %d - Value %h MISMATCH (expected %h)", channel, reg_type, actual_value, expected_value);
            end
        end
    endtask


    // --- Test Scenarios ---
    initial begin
        // Wait for reset to complete
        wait (master_rst_n === 1'b1);
        #100;

        // --- III. SFR Interaction Tests ---
        $display("---- STARTING SFR INTERACTION TESTS ----");
        // 1. Audio SFR Writes
        // Set page to 4 (assuming PAGE_SELECT_REG is $FE, and CPU can write to it)
        // The PAGE_SELECT_REG is special and not on page 4 itself.
        // For simplicity, we'll assume direct SFR writes for now using tasks.
        // The MMU has PAGE_SELECT_REG at a fixed logical address $00FE.
        // cpu_write(`PAGE_SELECT_REG_ADDR`, 8'h04); // Target SFR page 4

        // Using the simplified sfr_write task for now:
        // This assumes the MMU is already configured to map these sfr_offset_addrs to the SFR block
        // if the CPU were to write to them. For testbench control, this is a shortcut.

        // Test Audio SFR Writes
        sfr_write(`CH1_FREQ_LO_REG_ADDR`, 8'h12);
        sfr_write(`CH1_FREQ_HI_REG_ADDR`, 8'h34);
        sfr_write(`CH1_VOL_ENV_REG_ADDR`, 8'hAB);
        sfr_write(`CH1_WAVE_DUTY_REG_ADDR`, 8'hCD);
        sfr_write(`CH1_CTRL_REG_ADDR`, 8'h81); // Enable + Trigger

        sfr_write(`AUDIO_MASTER_VOL_REG_ADDR`, 8'h05);
        sfr_write(`AUDIO_SYSTEM_CTRL_REG_ADDR`, 8'h01); // System enable

        // Check outputs (these are wires from SFR block to audio module)
        check_audio_reg_output(0, 0, 8'h12); // CH1 Freq Lo
        check_audio_reg_output(0, 1, 8'h34); // CH1 Freq Hi
        check_audio_reg_output(0, 2, 8'hAB); // CH1 Vol Env
        check_audio_reg_output(0, 3, 8'hCD); // CH1 Wave Duty
        check_audio_reg_output(0, 4, 8'h81); // CH1 Ctrl
        check_audio_reg_output(4, 0, 8'h05); // Master Vol
        check_audio_reg_output(4, 1, 8'h01); // System Enable

        // 2. Text Character Map RAM R/W
        // Assuming SFR page 4 is still selected for these offsets
        sfr_write(`TEXT_CHAR_MAP_PAGE4_START_OFFSET + 0`, 8'hAA);
        sfr_write(`TEXT_CHAR_MAP_PAGE4_START_OFFSET + 1`, 8'hBB);
        sfr_write(`TEXT_CHAR_MAP_PAGE4_START_OFFSET + 1919`, 8'hCC); // Last byte

        begin
            reg [7:0] read_data;
            sfr_read(`TEXT_CHAR_MAP_PAGE4_START_OFFSET + 0`, read_data);
            if (read_data === 8'hAA) $display("TB: Text Map Read OK [0] = AA"); else $error("TB: Text Map Read FAIL [0] != AA (was %h)", read_data);
            sfr_read(`TEXT_CHAR_MAP_PAGE4_START_OFFSET + 1`, read_data);
            if (read_data === 8'hBB) $display("TB: Text Map Read OK [1] = BB"); else $error("TB: Text Map Read FAIL [1] != BB (was %h)", read_data);
            sfr_read(`TEXT_CHAR_MAP_PAGE4_START_OFFSET + 1919`, read_data);
            if (read_data === 8'hCC) $display("TB: Text Map Read OK [1919] = CC"); else $error("TB: Text Map Read FAIL [1919] != CC (was %h)", read_data);
        end

        // 3. FRAME_COUNT_LO/HI Atomicity (Conceptual - needs more control)
        // Allow frame counter to run for a bit
        $display("TB: Testing Frame Counter Atomicity (Conceptual)");
        #1000; // Let some frames pass
        begin
            reg [7:0] lo_val, hi_val_after_lo, hi_val_direct;
            sfr_read(`FRAME_COUNT_LO_REG_ADDR`, lo_val);
            // In a real test, one might try to force internal_frame_counter to change here if possible
            // For now, just read hi immediately after.
            sfr_read(`FRAME_COUNT_HI_REG_ADDR`, hi_val_after_lo);
            // Read again for a potentially newer value if not atomic
            sfr_read(`FRAME_COUNT_HI_REG_ADDR`, hi_val_direct);
            $display("TB: Frame Count LO=%h, HI_latched=%h, HI_direct=%h", lo_val, hi_val_after_lo, hi_val_direct);
            // Verification would depend on knowing if internal_frame_counter could have changed.
            // The design ensures hi_val_after_lo is the latched value.
        end

        // 4. Gamepad Inputs
        $display("TB: Testing Gamepad Inputs");
        tb_gamepad1_data = 8'b11110000; // Example: Up, Down, Left, Right pressed
        tb_gamepad1_connected = 1'b1;
        tb_gamepad2_data = 8'b11001100; // Example: B, A, Select, Start pressed
        tb_gamepad2_connected = 1'b1;
        #20; // Allow SFR block to update its internal regs from inputs
        begin
            reg [7:0] g1_state, g2_state, input_stat;
            sfr_read(`GAMEPAD1_STATE_REG_ADDR`, g1_state);
            if (g1_state === 8'b11110000) $display("TB: Gamepad1 State OK: %b", g1_state); else $error("TB: Gamepad1 State FAIL: %b (exp %b)", g1_state, 8'b11110000);
            sfr_read(`GAMEPAD2_STATE_REG_ADDR`, g2_state);
            if (g2_state === 8'b11001100) $display("TB: Gamepad2 State OK: %b", g2_state); else $error("TB: Gamepad2 State FAIL: %b (exp %b)", g2_state, 8'b11001100);
            sfr_read(`INPUT_STATUS_REG_ADDR`, input_stat);
            if (input_stat[1:0] === 2'b11) $display("TB: Input Status (Connected) OK: %b", input_stat); else $error("TB: Input Status (Connected) FAIL: %b (exp 2'b11)", input_stat);
        end
        tb_gamepad1_connected = 1'b0; // Test disconnect
        #20;
        begin
            reg [7:0] input_stat;
            sfr_read(`INPUT_STATUS_REG_ADDR`, input_stat);
             if (input_stat[0] === 1'b0) $display("TB: Input Status (G1 Disconnected) OK: %b", input_stat); else $error("TB: Input Status (G1 Disconnected) FAIL: %b", input_stat);
        end


        // --- IV. Graphics Tests ---
        $display("---- STARTING GRAPHICS TESTS (Conceptual) ----");
        // These tests are highly conceptual without pixel-level checking capabilities or full VRAM/Tile loading.

        // 1. Tilemap FlipX/FlipY
        $display("TB: Graphics - Tilemap Flip (Conceptual - requires VRAM setup & pixel check)");
        // cpu_write(TILEMAP_DEF_RAM_PAGE4_START_OFFSET, tile_id);
        // cpu_write(TILEMAP_DEF_RAM_PAGE4_START_OFFSET+1, attributes_with_flips);
        // check_pixel_color(...)

        // 2. Display Mode Switching (240p vs 256p)
        $display("TB: Graphics - Display Mode Switch");
        sfr_write(`SCREEN_CTRL_REG_ADDR`, 8'b00000001); // Mode 240p, Display Enable
        $display("TB: Set 240p mode. Expect ~240 visible lines.");
        // Monitor uut.u_graphics.v_count_total, uut.u_graphics.in_vblank_status over time
        #50000; // Run for a few frames
        sfr_write(`SCREEN_CTRL_REG_ADDR`, 8'b00000011); // Mode 256p, Display Enable
        $display("TB: Set 256p mode. Expect ~256 visible lines, shorter VBLANK.");
        #50000; // Run for a few frames

        // 3. VRAM Background Pixel Output
        $display("TB: Graphics - VRAM BG Pixel Output (Conceptual - requires VRAM setup & pixel check)");
        // Write to VRAM, then ensure uut.graphics_bg_pixel_to_sprite_engine shows correct value

        // 4. Basic Text Layer Display
        $display("TB: Graphics - Basic Text Layer (Conceptual)");
        sfr_write(`TEXT_CTRL_REG_ADDR`, 8'b00000001); // Enable text layer
        // Write 'A' to text char map RAM [0,0]
        sfr_write(`TEXT_CHAR_MAP_PAGE4_START_OFFSET + 0`, 8'h41); // Char code for 'A'
        sfr_write(`TEXT_CHAR_MAP_PAGE4_START_OFFSET + 1`, 8'h1F); // FG=1 (white), BG=F (black/ignored if font bit is 1)
        // Monitor uut.graphics_text_pixel_to_sprite_engine for non-zero output at top-left of screen
        #10000;
        $display("TB: Text layer test - check for pixel output if possible.");


        // --- V. System Integration Test ---
        $display("---- STARTING SYSTEM INTEGRATION TESTS (Conceptual) ----");
        // 1. Boot test - Load program to write to SFR
        $display("TB: System Boot Test (Conceptual - requires ROM loading and CPU model)");
        // load_cartridge_ram("test_sfr_write.hex");
        // Run for N cycles
        // sfr_read(VRAM_SCROLL_X_REG_ADDR, read_val) and check.

        $display("---- ALL CONCEPTUAL TESTS FINISHED ----");
        #100;
        $finish;
    end

endmodule
