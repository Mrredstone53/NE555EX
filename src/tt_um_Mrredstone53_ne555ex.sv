// NE555EX for Tiny Tapeout (digital/synth-friendly)
// - Modes: monostable, astable, pwm, burst
// - Extra features: retrigger, sync, invert, pin-configurable rate & duty
//
// ui_in[0] enable
// ui_in[2:1] mode: 00 mono, 01 astable, 10 pwm, 11 burst
// ui_in[3] fire (trigger)
// ui_in[4] sync (phase reset)
// ui_in[5] invert_out
// ui_in[6] retrigger_en (mono)
// ui_in[7] reset gate (0 = reset)
//
// uio_in[3:0] rate (prescaler shift)
// uio_in[7:4] duty (0..15) for PWM
//
// uo_out[0] OUT
// uo_out[1] DISCHARGE
// uo_out[2] DONE (mono finished pulse)
// uo_out[7:3] debug

module tt_um_Mrredstone53_ne555ex (
    input  logic [7:0] ui_in,
    output logic [7:0] uo_out,

    input  logic [7:0] uio_in,
    output logic [7:0] uio_out,
    output logic [7:0] uio_oe,

    input  logic       clk,
    input  logic       rst_n
);

  // --- Make bidirectional pins inputs only (safe default for Tiny Tapeout) ---
  assign uio_out = 8'h00;
  assign uio_oe  = 8'h00;

  // --- Inputs / controls ---
  logic enable, fire, sync, invert_out, retrigger_en;
  logic [1:0] mode;
  logic reset_ok;

  assign enable       = ui_in[0];
  assign mode         = ui_in[2:1];
  assign fire         = ui_in[3];
  assign sync         = ui_in[4];
  assign invert_out   = ui_in[5];
  assign retrigger_en = ui_in[6];

  // extra gate so you can "reset" with a pin even if rst_n is high
  assign reset_ok     = ui_in[7];

  // rate & duty from uio_in
  logic [3:0] rate;
  logic [3:0] duty;
  assign rate = uio_in[3:0];
  assign duty = uio_in[7:4];

  // --- Prescaled tick generation ---
  // tick goes high once per (2^rate) cycles (rate=0 -> fastest)
  logic [31:0] pre_cnt;
  logic        tick;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pre_cnt <= 32'd0;
      tick    <= 1'b0;
    end else begin
      pre_cnt <= pre_cnt + 32'd1;
      tick    <= (pre_cnt == (32'd1 << rate)); // simple prescaler
      if (tick) pre_cnt <= 32'd0;
    end
  end

  // --- Main state machine ---
  typedef enum logic [2:0] {IDLE, MONO_HIGH, AST_HIGH, AST_LOW, PWM_RUN, BURST_ON, BURST_OFF} state_t;
  state_t st, st_n;

  logic [15:0] cnt, cnt_n;

  // timing constants (in ticks, not raw clk)
  // You can later replace these with real programmable registers; for now it's "knobs-only".
  logic [15:0] T_HIGH, T_LOW, T_PULSE, BURST_ON_T, BURST_OFF_T;

  always_comb begin
    // base timings: scale with rate indirectly via tick; these are just "feel-good" defaults.
    T_HIGH      = 16'd80;
    T_LOW       = 16'd80;
    T_PULSE     = 16'd120;  // monostable pulse width
    BURST_ON_T  = 16'd60;
    BURST_OFF_T = 16'd200;
  end

  logic out_i, discharge_i, done_i;

  // registers
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st  <= IDLE;
      cnt <= 16'd0;
    end else begin
      st  <= st_n;
      cnt <= cnt_n;
    end
  end

  // next-state
  always_comb begin
    st_n = st;
    cnt_n = cnt;

    out_i = 1'b0;
    discharge_i = 1'b1;
    done_i = 1'b0;

    if (!reset_ok || !enable) begin
      st_n = IDLE;
      cnt_n = 16'd0;
      out_i = 1'b0;
      discharge_i = 1'b1;
    end else begin
      unique case (st)

        IDLE: begin
          out_i = 1'b0;
          discharge_i = 1'b1;
          cnt_n = 16'd0;

          unique case (mode)
            2'b00: if (fire) begin st_n = MONO_HIGH; cnt_n = 16'd0; end
            2'b01: begin st_n = AST_HIGH; cnt_n = 16'd0; end
            2'b10: begin st_n = PWM_RUN;  cnt_n = 16'd0; end
            2'b11: begin st_n = BURST_ON; cnt_n = 16'd0; end
          endcase
        end

        MONO_HIGH: begin
          out_i = 1'b1;
          discharge_i = 1'b0;

          // sync forces restart
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
          // period in ticks
          // duty[3:0]=0..15 => compare with (period * duty / 16)
          logic [15:0] period;
          logic [15:0] high_ticks;

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

  // output conditioning
  logic out_final;
  assign out_final = invert_out ? ~out_i : out_i;

  // stretch done pulse to be visible (a few cycles)
  logic [3:0] done_stretch;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) done_stretch <= 4'd0;
    else if (!reset_ok || !enable) done_stretch <= 4'd0;
    else if (done_i) done_stretch <= 4'd10;
    else if (done_stretch != 0) done_stretch <= done_stretch - 4'd1;
  end

  // uo_out mapping
  always_comb begin
    uo_out        = 8'h00;
    uo_out[0]     = out_final;
    uo_out[1]     = discharge_i;
    uo_out[2]     = (done_stretch != 0);

    // debug: state + a bit of counter
    uo_out[5:3]   = st;
    uo_out[7:6]   = cnt[1:0];
  end

endmodule
