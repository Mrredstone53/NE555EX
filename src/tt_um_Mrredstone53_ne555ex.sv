// NE555EX for Tiny Tapeout (TT standard top interface)
// Fixes: adds required 'ena' port expected by TT tooling.
//
// ui_in[0] EN (extra enable inside design; global ena also gates)
// ui_in[2:1] MODE: 00 mono, 01 astable, 10 pwm, 11 burst
// ui_in[3] TRIG_FIRE
// ui_in[4] SYNC
// ui_in[5] INV_OUT
// ui_in[6] RETRIG_EN
// ui_in[7] PIN_RESET_N (0 = reset)
//
// uio_in[3:0] RATE (prescaler shift)
// uio_in[7:4] DUTY (0..15) for PWM
//
// uo_out[0] OUT
// uo_out[1] DISCHARGE
// uo_out[2] DONE
// uo_out[5:3] DBG_STATE
// uo_out[7:6] DBG_CNT(1:0)

module tt_um_Mrredstone53_ne555ex (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,

    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,

    input  wire       ena,   // REQUIRED by Tiny Tapeout tooling
    input  wire       clk,
    input  wire       rst_n
);

  // Make bidirectional pins inputs only (safe)
  assign uio_out = 8'h00;
  assign uio_oe  = 8'h00;

  // Controls
  wire enable_local   = ui_in[0];
  wire [1:0] mode     = ui_in[2:1];
  wire fire           = ui_in[3];
  wire sync           = ui_in[4];
  wire invert_out     = ui_in[5];
  wire retrigger_en   = ui_in[6];
  wire pin_reset_n    = ui_in[7];   // 0 = reset

  wire [3:0] rate     = uio_in[3:0];
  wire [3:0] duty     = uio_in[7:4];

  // Global enable = TT 'ena' AND your local enable AND pin_reset_n
  wire run_ok = ena & enable_local & pin_reset_n;

  // Prescaled tick: tick high once per 2^rate cycles
  reg  [31:0] pre_cnt;
  reg         tick;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pre_cnt <= 32'd0;
      tick    <= 1'b0;
    end else if (!run_ok) begin
      pre_cnt <= 32'd0;
      tick    <= 1'b0;
    end else begin
      pre_cnt <= pre_cnt + 32'd1;
      tick    <= (pre_cnt == (32'd1 << rate));
      if (tick) pre_cnt <= 32'd0;
    end
  end

  // State machine
  localparam [2:0] IDLE      = 3'd0;
  localparam [2:0] MONO_HIGH = 3'd1;
  localparam [2:0] AST_HIGH  = 3'd2;
  localparam [2:0] AST_LOW   = 3'd3;
  localparam [2:0] PWM_RUN   = 3'd4;
  localparam [2:0] BURST_ON  = 3'd5;
  localparam [2:0] BURST_OFF = 3'd6;

  reg [2:0]  st, st_n;
  reg [15:0] cnt, cnt_n;

  // Timings (in ticks) — tweak later
  wire [15:0] T_HIGH      = 16'd80;
  wire [15:0] T_LOW       = 16'd80;
  wire [15:0] T_PULSE     = 16'd120;
  wire [15:0] BURST_ON_T  = 16'd60;
  wire [15:0] BURST_OFF_T = 16'd200;

  reg out_i, discharge_i, done_i;

  // registers
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st  <= IDLE;
      cnt <= 16'd0;
    end else begin
      st  <= st_n;
      cnt <= cnt_n;
    end
  end

  // next-state
  always @(*) begin
    st_n = st;
    cnt_n = cnt;

    out_i = 1'b0;
    discharge_i = 1'b1;
    done_i = 1'b0;

    if (!run_ok) begin
      st_n = IDLE;
      cnt_n = 16'd0;
      out_i = 1'b0;
      discharge_i = 1'b1;
    end else begin
      case (st)
        IDLE: begin
          out_i = 1'b0;
          discharge_i = 1'b1;
          cnt_n = 16'd0;

          case (mode)
            2'b00: if (fire) begin st_n = MONO_HIGH; cnt_n = 16'd0; end
            2'b01: begin st_n = AST_HIGH; cnt_n = 16'd0; end
            2'b10: begin st_n = PWM_RUN;  cnt_n = 16'd0; end
            2'b11: begin st_n = BURST_ON; cnt_n = 16'd0; end
          endcase
        end

        MONO_HIGH: begin
          out_i = 1'b1;
          discharge_i = 1'b0;

          if (sync) begin
            cnt_n = 16'd0;
          end else if (retrigger_en && fire) begin
            cnt_n = 16'd0;
          end else if (tick) begin
            if (cnt >= (T_PULSE - 1)) begin
              st_n = IDLE;
              cnt_n = 16'd0;
              done_i = 1'b1;
            end else begin
              cnt_n = cnt + 16'd1;
            end
          end
        end

        AST_HIGH: begin
          out_i = 1'b1;
          discharge_i = 1'b0;

          if (sync) begin
            cnt_n = 16'd0;
          end else if (tick) begin
            if (cnt >= (T_HIGH - 1)) begin
              st_n = AST_LOW;
              cnt_n = 16'd0;
            end else begin
              cnt_n = cnt + 16'd1;
            end
          end
        end

        AST_LOW: begin
          out_i = 1'b0;
          discharge_i = 1'b1;

          if (sync) begin
            cnt_n = 16'd0;
          end else if (tick) begin
            if (cnt >= (T_LOW - 1)) begin
              st_n = AST_HIGH;
              cnt_n = 16'd0;
            end else begin
              cnt_n = cnt + 16'd1;
            end
          end
        end

        PWM_RUN: begin
          // PWM period (in ticks)
          // duty[3:0] maps 0..15 => 0..(period-1)
          reg [15:0] period;
          reg [15:0] high_ticks;
          period     = 16'd256;
          high_ticks = (period * duty) >> 4;

          if (sync) begin
            cnt_n = 16'd0;
          end else if (tick) begin
            if (cnt >= (period - 1)) cnt_n = 16'd0;
            else cnt_n = cnt + 16'd1;
          end

          out_i       = (cnt < high_ticks);
          discharge_i = ~out_i;
        end

        BURST_ON: begin
          out_i = 1'b1;
          discharge_i = 1'b0;

          if (sync) begin
            cnt_n = 16'd0;
          end else if (tick) begin
            if (cnt >= (BURST_ON_T - 1)) begin
              st_n = BURST_OFF;
              cnt_n = 16'd0;
            end else cnt_n = cnt + 16'd1;
          end
        end

        BURST_OFF: begin
          out_i = 1'b0;
          discharge_i = 1'b1;

          if (sync) begin
            cnt_n = 16'd0;
          end else if (tick) begin
            if (cnt >= (BURST_OFF_T - 1)) begin
              st_n = BURST_ON;
              cnt_n = 16'd0;
            end else cnt_n = cnt + 16'd1;
          end
        end

        default: begin
          st_n  = IDLE;
          cnt_n = 16'd0;
        end
      endcase
    end
  end

  // Output conditioning
  wire out_final = invert_out ? ~out_i : out_i;

  // Stretch done pulse so it’s visible
  reg [3:0] done_stretch;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) done_stretch <= 4'd0;
    else if (!run_ok) done_stretch <= 4'd0;
    else if (done_i) done_stretch <= 4'd10;
    else if (done_stretch != 0) done_stretch <= done_stretch - 4'd1;
  end

  // Pack outputs
  assign uo_out[0] = out_final;
  assign uo_out[1] = discharge_i;
  assign uo_out[2] = (done_stretch != 0);
  assign uo_out[5:3] = st[2:0];
  assign uo_out[7:6] = cnt[1:0];

  // unused outputs
  assign uo_out[3] = st[0];
  assign uo_out[4] = st[1];
  // (uo_out[5] already used as part of [5:3])
  // (uo_out[6],[7] used)

endmodule
