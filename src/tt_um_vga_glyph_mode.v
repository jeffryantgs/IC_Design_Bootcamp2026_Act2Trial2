/*
 * Copyright (c) 2024-2025 James Ross
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_vga_glyph_mode(
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // VGA signals
    wire hsync, vsync, display_on;
    wire [10:0] hpos;
    wire [9:0] vpos;

    // TinyVGA PMOD: {hsync, R1, G1, B1, vsync, R0, G0, B0}
    assign uo_out = {hsync, RGB[0], RGB[2], RGB[4], vsync, RGB[1], RGB[3], RGB[5]};

    assign uio_out = 0;
    assign uio_oe  = 0;

    // Position and Grid logic
    wire [7:0] xb = hpos[10:3];
    wire [6:0] x_mix = {xb[7] ^ xb[3], xb[1], xb[4], xb[1], xb[6], xb[0], xb[2]};
    wire [2:0] g_x = hpos[2:0];
    wire [5:0] yb;
    wire [3:0] _unused;
    assign {_unused, yb} = vpos / 10'd12;
    wire [3:0] g_y;
    wire [5:0] g_unused;
    assign {g_unused, g_y} = vpos - {yb, 3'b000} - {1'b0, yb, 2'b00};
    wire hl;

    wire _unused_ok = &{ena, ui_in[5:2], uio_in};

    reg [9:0] frame;
    reg rst_drop;

    hvsync_generator hvsync_gen(
        .clk(clk),
        .reset(~rst_n),
        .mode(ui_in[7:6]),
        .hsync(hsync),
        .vsync(vsync),
        .display_on(display_on),
        .hpos(hpos),
        .vpos(vpos)
    );

    // --- JEFFRYANTAGSIP FALLING LOGIC ---
    // name_ptr cycles 0-13 based on position and vertical scroll
    wire [3:0] name_ptr = (yb + xb) % 4'd14;
    
    reg [5:0] falling_name_glyph;
    always @(*) begin
        case (name_ptr)
            4'd0:  falling_name_glyph = 6'd9;  // J
            4'd1:  falling_name_glyph = 6'd4;  // E
            4'd2:  falling_name_glyph = 6'd5;  // F
            4'd3:  falling_name_glyph = 6'd5;  // F
            4'd4:  falling_name_glyph = 6'd17; // R
            4'd5:  falling_name_glyph = 6'd24; // Y
            4'd6:  falling_name_glyph = 6'd0;  // A
            4'd7:  falling_name_glyph = 6'd13; // N
            4'd8:  falling_name_glyph = 6'd19; // T
            4'd9:  falling_name_glyph = 6'd0;  // A
            4'd10: falling_name_glyph = 6'd6;  // G
            4'd11: falling_name_glyph = 6'd18; // S
            4'd12: falling_name_glyph = 6'd8;  // I
            4'd13: falling_name_glyph = 6'd15; // P
            default: falling_name_glyph = 6'd38; 
        endcase
    end

    wire [5:0] glyph_index = falling_name_glyph;

    glyphs_rom glyphs(
        .c(glyph_index),
        .y(g_y),
        .x(g_x),
        .pixel(hl)
    );

    // --- CINEMATIC MATRIX EFFECTS ---
    
    // Using frame[9:1] slows the fall speed by half. 
    // Use frame[9:2] for even slower rain.
    wire [8:0] slow_frame = frame[9:1]; 

    wire [5:0] color;
    palette_rom palettes(
        .cid(y),
        .pid(ui_in[1:0]),
        .color(color)
    );

    wire [1:0] a = xb[1:0];
    wire [3:0] b = xb[5:2];
    wire [2:0] d = xb[3:2] + 2'd3;

    wire s = ^xb[6:0];
    wire n = xb[1] ^ xb[3] ^ xb[5];
    
    // Descent speed calculation using the slowed frame counter
    wire [6:0] v = (s ? slow_frame[7:1] : slow_frame[8:2]) - yb - x_mix;
    
    wire [3:0] c = {1'b0, a} + d;
    wire [6:0] e = {3'b000, b} << c;
    wire [6:0] f = v & e;
    wire [6:0] x = v >> a;
    wire [2:0] y = ~x[2:0];
    
    wire [9:0] drop = {1'b0, yb, 3'd0} >> s;
    wire drop_bit = ({3'd0, x_mix} + drop > frame) & ~rst_drop;
    wire [5:0] glyph_color = {6{drop_bit}} ^ color;

    // The "Head" of the drop (Brightest White pixel)
    wire [5:0] z = (&(~v[2:0]) & &(y)) ? 6'd63 : glyph_color;

    // Final RGB Output
    wire [5:0] RGB = (display_on & hl & (|f | n | drop_bit)) ? z : 6'd0;

    // Frame/Time counter
    always @(posedge vsync, negedge rst_n) begin
        if (~rst_n) begin
            rst_drop <= 1'b0;
            frame <= 10'd0;
        end else begin
            if (&frame) rst_drop <= 1'b1;
            frame <= frame + 1'b1;
        end
    end

endmodule