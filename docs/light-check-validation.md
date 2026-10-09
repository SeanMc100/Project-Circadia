# Light Check validation

Light Check turns the camera's exposure settings into an approximate light level. It
weights that by the light's colour, measured from the pixels with white balance locked
to daylight, to get melanopic EDI. It then shows a band: Very dim / Indoor / Bright indoor / Outdoor / Sunlight. Before it
ships to users, check it against a reference meter on real phones. This is the gate
in `docs/no-wearable-mode-plan.md` §4.4.

## What you need

- **A reference lux meter.** A cheap digital one is fine for photopic lux. One that
  also reports colour temperature is better.
- **Three iPhones:** the oldest one supported, a mid-range one, and a current Pro.
- **A debug build of Circadia.** The Light Check screen has a "What the camera sees"
  section. It shows the mode, the colour name with a swatch, linear RGB, xy, Δuv, CCT,
  the melanopic ratio, lux, melanopic EDI, EV100, ISO, shutter, exposure offset and
  clipped pixels.
- **Optional: a spectrometer** that reports melanopic EDI directly, for the coloured-light
  scenes. Without one, check the colour name and that red or amber light lands low.
- **Plain white printer paper** for the white-paper mode.

## How to take a reading

1. Hold the reference meter's sensor at eye level, facing the same way you look.
2. Hold the phone beside it, pointing the same way. Wait for the reading to settle,
   about 2 seconds.
3. Record the reference lux, the app's lux, the app's band and the CCT.

## Scenes (about 40)

Cover each band at least 6 times. Include the hard cases:

| Group | Examples |
|---|---|
| Evening | One warm lamp, TV-lit room, phone-only light, dimmer at lowest |
| Indoor | Living room with overhead lights on, kitchen, bedroom with daytime curtains |
| Bright indoor | Office, desk by a window, supermarket |
| Outdoor | Overcast midday, shade under a tree, cloudy morning, dusk |
| Sunlight | Open sun, sun on pavement, snow or beach if available |
| Surfaces | Same lamp pointed at a white wall vs a dark wall vs a window |
| Coloured light | Red bulb or LED, amber night-light, purple/blue smart bulb, phone screen at full brightness |
| Coloured surfaces | White lamp on a red wall, a green wall, a wooden floor |

Take each scene twice: once in scene mode and once with the white-paper check on.

## Pass criteria

- **≥ 90%** of readings land in the same band as the reference. Convert the reference to
  melanopic EDI with the same ratio table (`CircadianConfig.melanopicRatioByKelvin`),
  using the meter's CCT if it has one.
- **No reading is two or more bands off.**
- **Evening safety:** no "✓ Dim enough" verdict when the reference is above 30 lux.
  This applies to white light only. Red light above 30 lux can rightly be dim enough.
- **Colour:** red and amber light read as red or amber, never white. A white lamp on a
  coloured wall reads as white in white-paper mode.
- **White paper vs reference:** white-paper lux should be within 2× of the reference meter
  held flat in the same position as the paper.

## Tuning

- `CircadianConfig.lightMeterCalibration` (default 2.5) scales every reading. Set it to
  the median of `reference lux ÷ 2^EV100` across the scenes.
- If one device class is consistently off, add a per-model constant.
- White-paper mode uses the same constant × 0.18 ÷ 0.85
  (`lightMeterSceneReflectance` ÷ `lightMeterPaperReflectance`). If paper readings run
  consistently high or low, adjust `lightMeterPaperReflectance`.
- The colour weights (`melanopicRGBWeights`) were fitted to model spectra. These were
  blackbody 1800–12000 K, phosphor white LEDs, single-colour LEDs and red/blue mixes,
  scored against the CIE S 026 melanopic curve and anchored to illuminant A = 0.455.
  The fit is within about 1.4× for white and mixed light. It overrates deep amber
  (about 0.15 vs 0.02), which errs toward "too bright" in the evening. If a spectrometer
  is available, refit them against the measured melanopic EDI.
- If the evening safety rule fails, lower `lightBandIndoor` for the evening verdict
  rather than for the display.
- **If the gate still fails:** keep only the "Compare two places" ratio, which doesn't
  depend on the constant, and drop the bands that fail.

## Results

| Date | Device | Mode | Scene | Ref lux | Ref CCT / mEDI | App lux | App colour | App mEDI | App band | Ref band | OK |
|---|---|---|---|---|---|---|---|---|---|---|---|
| | | | | | | | | | | | |
