
# NE555EX — Tiny Tapeout Digital Timer (Sky130)

## 1. Overview
**NE555EX** is a Tiny Tapeout (TT) compatible **digital, synthesizable** timer core inspired by the classic NE555 behavior, but extended with modern convenience features.  
It is intended as a “drop-in timer-like block” for small ASIC demos: oscillator (astable), one-shot (monostable), PWM generator, and burst mode, all configurable via pins (no firmware required).

This project targets **SkyWater SKY130** (open PDK) through the Tiny Tapeout toolchain.

---

## 2. Key Features
### Core modes (selected via pins)
- **Monostable (one-shot)**: generates a pulse of fixed length when triggered
- **Astable**: free-running oscillator (square-ish waveform)
- **PWM**: adjustable duty cycle using 4-bit input
- **Burst**: periodic on/off gating of the output (useful for “beeper”/LED patterns)

### Extended (“EX”) features
- **SYNC input**: resets phase/counter to sync multiple timers or external beats
- **Retrigger** (monostable): re-trigger restarts pulse duration (optional)
- **Invert output**: flips polarity without external inverter
- **Rate control**: 4-bit prescaler selects tick speed (coarse frequency control)
- **Debug outputs**: state and counter bits exposed for easy observation on TT boards

---

## 3. High-Level Architecture
NE555EX is fully digital and implemented as:

1. **Prescaler / Tick Generator**
   - Converts the global clock (`clk`) into a slower “tick” based on `rate[3:0]`
   - Tick occurs once every `2^rate` cycles (coarse speed knob)

2. **Finite State Machine (FSM)**
   - States: IDLE, MONO_HIGH, AST_HIGH, AST_LOW, PWM_RUN, BURST_ON, BURST_OFF
   - Transitions depend on mode, tick, sync, trigger, and internal counters

3. **Counter**
   - `cnt` increments on each tick
   - Used to implement pulse lengths / high/low durations / PWM phase / burst windows

4. **Output Conditioning**
   - Optional inversion
   - “DONE” pulse is stretched briefly to be visible externally

---

## 4. I/O and Pin Mapping (Tiny Tapeout)
The top module follows the Tiny Tapeout standard interface:
- `clk` (system clock)
- `rst_n` (active-low reset)
- `ena` (global enable from TT harness)
- `ui_in[7:0]` dedicated inputs
- `uo_out[7:0]` dedicated outputs
- `uio_in/out/oe[7:0]` bidirectional pins (configured as inputs only in this design)

### Inputs (`ui_in`)
| Pin | Name         | Description |
|-----|--------------|-------------|
| ui[0] | EN          | Local enable (gates behavior) |
| ui[1] | MODE0       | Mode select bit 0 |
| ui[2] | MODE1       | Mode select bit 1 |
| ui[3] | TRIG_FIRE   | Trigger / fire event |
| ui[4] | SYNC        | Phase reset / sync input |
| ui[5] | INV_OUT     | Invert output polarity |
| ui[6] | RETRIG_EN   | Retrigger enable (monostable) |
| ui[7] | PIN_RESET_N | Extra active-low reset gate (0 = reset) |

### Inputs (`uio_in`) — used as inputs only
| Pin | Name   | Description |
|-----|--------|-------------|
| uio[3:0] | RATE[3:0] | Prescaler control; larger = slower |
| uio[7:4] | DUTY[3:0] | PWM duty; 0..15 maps to 0..100% |

### Outputs (`uo_out`)
| Pin | Name       | Description |
|-----|------------|-------------|
| uo[0] | OUT       | Main timer output |
| uo[1] | DISCHARGE | “Low-phase” indicator (active when output low/idle) |
| uo[2] | DONE      | One-shot finished pulse (stretched) |
| uo[5:3] | DBG_STATE[2:0] | FSM state debug |
| uo[7:6] | DBG_CNT[1:0]   | Counter LSB debug |

### Mode encoding (`ui_in[2:1]`)
| MODE1:MODE0 | Mode |
|-------------|------|
| 00 | Monostable |
| 01 | Astable |
| 10 | PWM |
| 11 | Burst |

---

## 5. Timing Model
NE555EX uses a digital tick-based timing model:
- A global system clock `clk` drives a prescaler
- A slower `tick` updates the FSM counter
- Fixed tick-domain constants define default pulse/high/low/burst durations

Notes:
- This design is **not analog-accurate** to a real NE555 (no RC comparator model).
- The focus is **predictable synthesis and easy demonstration**.

---

## 6. Technology / PDK / Toolchain
### Target PDK
- **SkyWater SKY130** (open PDK), typically via `sky130A`  
  Used by the Tiny Tapeout flow to produce GDS.

### Flow / Tools
- Tiny Tapeout reference flow (containerized), OpenLane/LibreLane/OpenROAD based
- Lint: Verilator lint during harden
- Outputs: GDS, LEF/DEF, reports

---

## 7. Reset and Enable Behavior
The effective run condition is:

- `rst_n` must be high (global reset released)
- `ena` must be high (Tiny Tapeout global enable)
- `ui_in[0]` must be high (local enable)
- `ui_in[7]` must be high (pin reset gate released)

If any is false, the core returns to IDLE with output low and discharge high.















![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# Tiny Tapeout Verilog Project Template

- [Read the documentation for project](docs/info.md)

## What is Tiny Tapeout?

Tiny Tapeout is an educational project that aims to make it easier and cheaper than ever to get your digital and analog designs manufactured on a real chip.

To learn more and get started, visit https://tinytapeout.com.

## Set up your Verilog project

1. Add your Verilog files to the `src` folder.
2. Edit the [info.yaml](info.yaml) and update information about your project, paying special attention to the `source_files` and `top_module` properties. If you are upgrading an existing Tiny Tapeout project, check out our [online info.yaml migration tool](https://tinytapeout.github.io/tt-yaml-upgrade-tool/).
3. Edit [docs/info.md](docs/info.md) and add a description of your project.
4. Adapt the testbench to your design. See [test/README.md](test/README.md) for more information.

The GitHub action will automatically build the ASIC files using [LibreLane](https://www.zerotoasiccourse.com/terminology/librelane/).

## Enable GitHub actions to build the results page

- [Enabling GitHub Pages](https://tinytapeout.com/faq/#my-github-action-is-failing-on-the-pages-part)

## Resources

- [FAQ](https://tinytapeout.com/faq/)
- [Digital design lessons](https://tinytapeout.com/digital_design/)
- [Learn how semiconductors work](https://tinytapeout.com/siliwiz/)
- [Join the community](https://tinytapeout.com/discord)
- [Build your design locally](https://www.tinytapeout.com/guides/local-hardening/)

## What next?

- [Submit your design to the next shuttle](https://app.tinytapeout.com/).
- Edit [this README](README.md) and explain your design, how it works, and how to test it.
- Share your project on your social network of choice:
  - LinkedIn [#tinytapeout](https://www.linkedin.com/search/results/content/?keywords=%23tinytapeout) [@TinyTapeout](https://www.linkedin.com/company/100708654/)
  - Mastodon [#tinytapeout](https://chaos.social/tags/tinytapeout) [@matthewvenn](https://chaos.social/@matthewvenn)
  - X (formerly Twitter) [#tinytapeout](https://twitter.com/hashtag/tinytapeout) [@tinytapeout](https://twitter.com/tinytapeout)
  - Bluesky [@tinytapeout.com](https://bsky.app/profile/tinytapeout.com)
