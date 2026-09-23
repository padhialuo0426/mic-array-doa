# Digilent rgb2dvi

Source from https://github.com/Digilent/vivado-library at commit
`f4613fff005b098065fd5d619a2b88e55720a423`.

All seven files in `src/` are unmodified files from `ip/rgb2dvi/src/`.
`SyncAsyncReset.vhd` already declares the `ResetBridge` entity; do not also
import the newer shared module of that name. Six files retain their explicit
BSD-3-Clause notices. `ClockGen.vhd` has no file-specific license header and
is covered by the upstream repository's MIT license. Both notices are
preserved in the root `licenses/` directory and accompany binary builds.

We supply coherent 74.25/371.25 MHz clocks externally, disable the internal
clock generator, and explicitly map ordinary RGB into this core's RBG input.
No audio, HDCP, CEC or EDID functions are enabled. Board integration is in
`hw/rtl/hdmi_display.v`; physical behavior still needs a compatible 720p sink.
