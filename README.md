# Arturia KeyLab Essential mk3 — Renoise Tool

A Renoise scripting tool that turns an **Arturia KeyLab Essential 49/61/88 mk3** into a
hands-on control surface for Renoise: transport, pattern-editing knobs and faders,
pads, tap tempo, and hardware LED feedback.

This is a fork of the original [Arturia KeyLab mk3 tool](https://www.renoise.com/tools/arturia-keylab-mkii)
by **foma** (itself based on the mkII tool by **ulneiz**), reworked specifically for the
**Essential** line, which uses a genuinely different MIDI protocol from the Pro-line
hardware the original tool targeted. It will **not** work correctly with a Pro-line
KeyLab mk3 (49/61/88, no "Essential" in the name) — that hardware needs the original tool.

- **Compatibility:** Renoise 3.5.x (Lua API 6)
- **Hardware:** Arturia KeyLab Essential 49 / 61 / 88 mk3
- **License:** GNU General Public License
- **O/S used or testing:** Kubuntu 24.04
- **Tested on hardware:** Arturia KeyLab Essential 61 mk3.

---

## Installation

1. Copy `main.lua` and the `lua/` folder into a tool directory named
   `dev.foma.ArturiaKeyLabmk3.xrnx` inside your Renoise Tools folder
   (`~/.config/Renoise/V3.5.x/Scripts/Tools/` on Linux).
2. Restart Renoise.
3. Open the tool from the **Tools** menu.

## One-time setup

Do this once, ever — it's not something you'll need to repeat.

### 1. Put the keyboard in DAW mode

Press **Prog** on the keyboard until the screen shows **"DAWs Program"**. This is a
physical setting on the hardware itself, not something Renoise or this tool controls.

### 2. Pick the right MIDI ports in the tool

In the tool's own dialog, set both **In Device** and **Out Device** to your keyboard's
plain MIDI port — something like `KL Essential 61 mk3 MIDI`.

> ⚠️ **Do not use the "MCU/HUI" port.** Unlike the Pro-line hardware, the Essential
> mk3's MCU/HUI port stays completely silent — all DAW control data (transport, knobs,
> faders, dial) actually rides the plain MIDI port alongside your regular note input.

Then pick your exact model (49/61/88 Essential) in the **Name** dropdown — this is
remembered across restarts.

### 3. Tell Renoise to ignore the control-surface CCs

Without this step, Renoise will record every button press and knob turn straight into
your patterns as raw effect commands whenever Edit Mode is on.

Go to **Edit → Preferences → MIDI**, find **"Ignore specific controllers"**, and paste:

```
20,21,22,24,25,26,27,40,42,43,96,97,98,99,100,101,102,103,104,105,106,107,108,109,110,111,112,113,116,117,118
```

*(The tool also shows this exact box the first time you ever open it, so you don't have
to come back here to find it.)*

---

## What everything does

### Transport

| Control | Action |
|---|---|
| Play | Toggles play/pause (properly stops on second press, doesn't just restart) |
| Stop | Stops playback; pressing again while already stopped also silences any hanging notes |
| Record | Toggles Renoise's Edit Mode (and switches to the Pattern Editor view) |
| Loop | Toggles pattern loop |
| Metronome | Toggles the metronome |
| Undo / Redo | Real Renoise undo/redo (`song:undo()` / `song:redo()`) |
| Save | Quick-saves if the song already has a filename; otherwise prompts for one |
| `<<` / `>>` | Select previous / next track |
| Quant | Toggles Renoise's global **Record Quantization** on/off |
| Part | Toggles the **Mixer** view on/off (jumps back to the Pattern Editor) |
| Tap | Tap a steady rhythm (2+ taps) to set the song's BPM — averages your last 4 taps, resets if you pause more than 2 seconds |

### Knobs 1–9 and Faders 1–9

Both rows control the same nine things, in the same order — a knob and its matching
fader are two ways to adjust the same value:

| # | Controls |
|---|---|
| 1 | Note (of the note column at the pattern cursor) |
| 2 | Instrument |
| 3 | Volume |
| 4 | Panning |
| 5 | Delay (pattern micro-timing offset — **not** an audio echo effect) |
| 6 | Sample-FX / effect-command type (e.g. `0S` sample offset, `0G` glide, `0A` arpeggio) |
| 7 | Sample-FX / effect-command amount |
| 8 | Note/effect column navigation |
| 9 | Step length (pattern cursor step size) |

Knobs 1–7 use **direct position mapping** — wherever the knob physically sits maps
straight onto the target's value, immediately, every time. Knobs 8 and 9 are
different: they're relative *movements* (not a "position"), so they use step-counting
instead, which means they can occasionally get stuck at the knob's own physical
0/127 limit until you turn it back the other way slightly. That's an accepted
quirk of those two specifically, not a bug.

All of this only does anything while **Edit Mode is on**.

### Dial

Turn to navigate between Renoise's main panels (Pattern Editor, Mixer, etc.). Press
and hold to jump straight to the Instrument editor.

### Pitch wheel & mod wheel

Deliberately **not** touched by this tool — both pass straight through to Renoise's
native MIDI input, so you can map them yourself via each instrument's own **Macros**
(`pitchbend_macro` / `modulation_wheel_macro`), the same way you would with any MIDI
controller. Pitch-bend needs a Pitch modulation entry on the instrument itself
(Sampler → Modulation tab) to actually do anything — that's normal Renoise behaviour,
unrelated to this tool.

### Hardware LEDs

Play, Record, Loop, Quantize, and Part light up to reflect their current state,
staying in sync no matter how you changed that state (hardware button, mouse,
keyboard shortcut). Tap Tempo's button brightens while you're actively tapping and
dims out after a 2-second pause.

### On-screen GUI

The tool's own dialog mirrors most of this: the same Play/Record/Loop/Metronome/Follow
indicators light up on screen, and Save/Undo/Redo/Stop flash briefly to confirm they
fired. These are status indicators, not clickable controls (aside from the
Previous/Next Track buttons, which do work with the mouse) — the hardware is the
intended way to drive everything.

---

## Known limitations

- Knobs 8 and 9 (relative-movement controls) can get stuck at their own physical
  0/127 limit until you turn back slightly — see above.
- Play/Record/Loop/Part's on-screen sync (and pad-function firing) only tracks what
  you'd expect if you're not also using the pads to play real notes at the same time.
- The two Renoise settings in the setup steps above (ignore-controllers list,
  per-instrument channel) can't be set automatically by a Renoise Tool — that's a platform limitation, not something this tool chose not to do.
- The buttons LED's backlighting state can be incoherent after the sleep/"Vegas" mode is triggered. One workaround fors Windows users would be to disable sleep mode for your MIDI keyboard with Arturia's software.

## Credits

- Original KeyLab mkII tool: **ulneiz**
- KeyLab mk3 (Pro-line) port: **foma**
- KeyLab Essential mk3 port: this fork
