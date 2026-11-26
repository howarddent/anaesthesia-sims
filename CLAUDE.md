# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Anaesthesia, respiratory and clinical-physiology simulations and demos,
written in Free Pascal / Lazarus on top of the **newVM** matrix library.
They were split out of the newVM repository on 2026-11-19, with their git
history, so that newVM holds the library and its general demos, and this
repository holds the clinical work.

newVM is a **git submodule** at `newVM/` (https://github.com/howarddent/newVM),
pinned to a commit. Its own `CLAUDE.md` describes the library: the `TVMobj`
types, `newVMConfig.inc` and the `HAVE_*`/`PUREPASCAL` defines, the plot
components in `newVM/Graphs/` (`TVMPlot2D`, `TVMPlot3D`, `TVMPlotStack`),
`newVMsparse.pas` and the FEM4 framework in `newVM/Delphi OOFEM/`. Read the
relevant section there before changing how a project here uses them. Where
the notes below say "see ... above" about a library feature, the section is
in newVM's `CLAUDE.md`.

## Layout

| Path | What |
|---|---|
| `Anaesthetics/PK-PD/` | The original Delphi/MtxVec PK/PD simulator, kept for reference |
| `Anaesthetics/PK-PD_FPC/` | Its newVM/Lazarus port (`PK-PD.lpi`) and FPCUnit tests (`PKPDtest.lpi`); `uBodyStats.pas` is also used by Defibrillation and HFJV |
| `demos/JetVent/` | Jet-ventilation cannula calculator; `uJetCalcVM.pas` is also used by JetFlow and HFJV |
| `demos/JetFlow/` | Jet-flow calculator built on JetVent's cannula model |
| `demos/O2Entrainment/` | Delivered O2 % against entrainment ratio |
| `demos/BioSpectra/` | ECG, EEG, arterial pressure, anaesthesia EEG and bispectrum spectra |
| `demos/GlassSpine/` | Spinal anaesthesia: bupivacaine spread in a glass dural sac, OpenCL |
| `FEM4/Examples/ThermEx1/` | Core temperature of an anaesthetised adult in a cold theatre (FEM4 `TThermalEngine`) |
| `FEM4/Examples/ThermSlab/` | Verification of FEM4's 3-D conduction against a slab (ThermEx1's check) |
| `FEM4/Examples/Defibrillation/` | Current spread from a 200 J shock through a torso; reuses ThermEx1's trunk |
| `FEM4/Examples/HFJV/` | High-frequency jet ventilation in a supine adult; reuses Defibrillation's torso. `images/` holds result plots |
| `FEM4/Examples/LeftVentricle/` | Finite-element left ventricle (Hill fibres, lumped valves and circulation) with the LVView viewer; needs newVM's `TPardisoFactor.Refactor` (d02cff7 or later) |
| `FEM4/Examples/Aorta/` | 1-D finite-element pulse waves from the aortic valve to the femorals and the left wrist, with the AortaView viewer; reads LeftVentricle's `out/beat.csv` |
| `FEM4/Examples/circ_sim/` | LeftVentricle and Aorta in one window, on two tabs, with one Compute; uses both projects' units and `../LeftVentricle/lvrun` |
| `FEM4/Examples/Asthma/` | Lung mechanics in normal people and asthma: finite-element bronchiole wall (tube law) and alveolus, then a Weibel-tree lung with chest wall giving spirometry, pleural pressure, EELV and work of breathing, uniform or patchy |
| `FEM4/Examples/Data/` | ThermEx1's gmsh inputs (`thermex1.geo/.msh/.scr`); ThermEx1 and ThermSlab find it as `../Data/` |

Cross-project dependencies inside this repo: JetFlow and HFJV use
`demos/JetVent`; Defibrillation uses `FEM4/Examples/ThermEx1` and
`Anaesthetics/PK-PD_FPC`; HFJV uses Defibrillation, ThermEx1, JetVent and
PK-PD_FPC; Aorta reads `../LeftVentricle/out/beat.csv` (not in git: run
`lvrun --csv=out/beat.csv` there first). Move none of these without fixing the others' search paths.

## Build

Clone with the submodule: `git clone --recursive
https://github.com/howarddent/anaesthesia-sims.git` (or `git submodule
update --init` after a plain clone). Every requirement of newVM itself
applies (Lazarus + FPC, and MKL/IPP/OpenBLAS/FFTW where present; see newVM's
`CLAUDE.md` and README).

- **`newVMConfig.inc` lives in the submodule** (`newVM/newVMConfig.inc`),
  and every project here includes it as `../../newVM/newVMConfig.inc`. On
  a new machine, build and run `newvmconfigure` inside `newVM/` as newVM's
  `CLAUDE.md` says. That leaves the submodule dirty, which is expected and
  shouldn't be committed from here.
- **Search paths**: projects under `demos/` and `Anaesthetics/PK-PD_FPC/`
  reach newVM as `../../newVM` (and `../../newVM/Graphs`,
  `../../newVM/LMath/...`). The FEM4 examples reach it as
  `..\..\..\newVM` and the FEM4 sources as
  `..\..\..\newVM\Delphi OOFEM\FEM4\Development\Source\<dir>`.
- Lazarus projects: `lazbuild --lazarusdir=$HOME/Lazarus --ws=gtk2
  <path>.lpi` (`lazbuild` is `~/Lazarus/lazbuild` on the P620; it isn't on
  PATH). `--ws=gtk2` matters: under GTK3 `TOpenGLControl` draws nothing.
- Console programs built with plain `fpc` (GlassSpine's `spinecheck`,
  HFJV's `hfjvrun`/`hfjvcheck`/`hfjvmesh`) give their command lines in
  their own headers and below.
- Checked after the split (2026-11-19) on the P620, katana and the mac
  (M4 Max), with newVM at fac8749: all eleven `.lpi`s and the four `fpc`
  programs build, and `PKPDtest` passes 17/17 everywhere. The mac has no
  MKL: the FEM4 examples build there on newVM's Accelerate back end for
  `newVMsparse` (`HAVE_ACCELERATE_SPARSE`, merged from newVM's
  `accelerate-sparse` branch the same day), and `hfjvcheck` passes in
  full on it (53 s). GlassSpine runs on macOS's OpenCL (device "Apple M4
  Max"), and `spinecheck --time=10` matches the P620's output figure for
  figure.
- **Updating newVM**: `cd newVM && git pull origin main`, rebuild, then
  commit the new submodule pointer here.

### Release builds (`release/`)

`release/build-release.sh [--working-tree] <path/to/Project.lpi>` builds a
binary to hand out, in `release/out/<os>-<cpu>/` (ignored by git). It
stages a clean copy (`git archive` of HEAD and of the newVM submodule, or
the tracked working-tree files with `--working-tree`), refuses to go on if a
`<name>_cl.inc` is stale against its `<name>.cl` (`tools/cl2inc.py --check`),
puts `release/newVMConfig.release.inc` over the staged
`newVM/newVMConfig.inc`, builds with lazbuild (GTK2 on Linux, Cocoa on
macOS, Win32 on Windows; `$LAZDIR`, default `~/Lazarus`), and fails if the
binary links MKL, IPP, OpenBLAS, FFTW, ArmPL, OpenCL or clFFT.

Why the release config: a normal `newVMConfig.inc` describes the build
machine, and with `HAVE_MKL`/`HAVE_IPP` the newVM units `{$Linklib}` MKL and
IPP, so the program won't start without Intel oneAPI. The release config
defines only `PUREPASCAL`/`PUREPASCAL_BLAS` and the platform, so every newVM
routine runs its plain-Pascal body; OpenCL is loaded at run time by
`OpenCLAPI` either way. GlassSpine needs nothing faster from newVM (its work
is on the GPU). Checked 2026-11-19 on the P620: the GlassSpine release
binary links only GTK2, libGL, libm and libc, and a `--snapshot` run from an
empty folder, without `LD_LIBRARY_PATH`, works on the built-in kernels.

Kernels are built in (`tools/cl2inc.py`, see GlassSpine) because FPC 3.2
can't embed a file portably: `{$R x.rc}` needs MinGW's windres on Linux and
macOS, and `-FF` (fpcres for .rc) is FPC 3.3 only.

**Windows installer** (2026-11-19; first built 2026-11-21, run 44881354420: a 2.9 MB setup, GlassSpine.exe 3.0 MB stripped, linking only Windows' own DLLs and opengl32; not yet run on a real PC): `.github/workflows/windows-installers.yml`
runs on a `glassspine-v<version>` tag, or by hand from the Actions tab. On
`windows-latest` it installs Lazarus (`gcarreno/setup-lazarus`, stable), runs
`build-release.sh` under Git Bash (which finds `lazbuild` on the PATH, uses
`python` when there's no `python3`, hands lazbuild `cygpath -m` paths and
skips the DLL check if there's no `objdump`), then Inno Setup on
`release/windows/GlassSpine.iss`: a per-user install (no admin rights),
Start-menu shortcut, optional desktop icon, uninstaller, the GPL as
`LICENSE.txt`. A tag run attaches `GlassSpine-<version>-windows-x64-setup.exe`
to the GitHub Release; a manual run keeps it as a workflow artifact. It is
not code-signed, so SmartScreen warns ("More info", "Run anyway").
`GlassSpine.lpi` gained `GraphicApplication` (Win32), without which Windows
opens a console window beside the program; `cl2inc.py --check` ignores CRLF
in the include, since a Windows checkout may convert it.

## FEM4 examples

### `FEM4/Examples/Defibrillation`

Added 2026-10-30. Shows how the current of a 200 J monophasic shock
spreads through a torso. The torso holds **ThermEx1's trunk** masses,
taken from `uThermEx1`'s own interface tables (the project `uses` it,
with `..\ThermEx1` on its search path), with core, muscle, fat and skin
as similar ellipses. Its shape is its own:
- **Abdomen.** An elliptical cylinder 0.43 m long (`AbdomenLength`),
  323 x 233 mm (`TrunkAspect` 0.72).
- **Thorax.** A truncated cone 0.25 m long (`ThoraxLength`). Its base is
  the diaphragm, where it meets the abdomen without a step. Its apex is
  the root of the neck, at half the section (`NeckRatio`).

The total length is 0.68 m and the volume is ThermEx1's 34.0 L.
(Reshaped 2026-10-31 at the user's request. It was ThermEx1's single
cylinder, 334 x 167 mm and 0.78 m long.)

gmsh still meshes a cylinder, as ThermEx1 does, but finer round the
section (32 divisions a quadrant) and graded along it (6.5 mm through
the chest). `ToBody` then moves each node onto the body:
- outside the core, everything moves in by `SectionShift(z)`, so skin,
  fat and muscle keep their thickness up the cone;
- the core ellipse scales by `CoreScale(z)`, and the chest wall keeps
  its depth below each parametric angle;
- the inner core is stretched along rays to fill the wall's new inner
  edge (an angle table, `InnerTAt`).

The three rules agree on their boundaries, so nothing tears. Tissue
tests on depth in the wall use the meshed coordinates (`FRefX/FRefY`),
and those on organs, spine, sternum and pads use the body's. Skin-face
normals come from the faces themselves and have a z component on the
cone. About 210k nodes and 264k elements. `uDefibModel.pas`'s header
has the model, and `uDefibView.pas`'s header the picture. Things worth
knowing:

- **Solver.** `TThermalEngine`: `div(sigma grad phi) = 0` is
  steady conduction, so "temperature" is volts and a node "heat source"
  is amperes. One static PARDISO solve for 1 A takes about 1-2 min, most
  of the start-up.
- **Per-element conductivity tensors in FEM4** (added for the
  anisotropic option). `TThermalEngine.SetElementConductivityTensor(Id,
  Kxx, Kyy, Kzz, Kxy, Kxz, Kyz)` stores a symmetric tensor on that
  element's `TElementData`; `SetMaterial` then calls
  `TElement.SetConductivityTensor` or `ClearConductivityTensor` for every
  element, which matters because assembly reuses one element object per
  type across the mesh. `Brick_H8V1`/`W6V1`/`T4V1` form
  `BT * CondB(B)` and skip the scalar `FConductivity` scaling when a
  tensor is set. With no tensor set, results are unchanged
  (Defibrillation's isotropic run reproduced every figure exactly). The
  2-D and edge elements don't use it.
- **Organs.** A tilted ellipsoid heart (myocardium round a blood cavity)
  and two lungs. A core element takes an organ's tissue if its centroid
  lies inside the organ, so organ surfaces staircase at element size.
- **Chest wall and skeleton** (added later the same day, at the user's
  request). ThermEx1's muscle is only 12 mm thick at the sides and less
  at the front, so an 18 mm wall of muscle conductivity is meshed
  inside the core's ellipse as one more transfinite annulus (physical
  volume 5). Its inner edge is a gmsh `Spline` through points offset
  along the ellipse's normal (`WallPoint`, which takes a height and
  gives the body's point, z = 0 being the meshed cylinder), so the wall
  has constant thickness. That only works below the core ellipse's
  smallest radius of curvature, b^2/a, which is smallest at the neck
  (33 mm); `SetupGeometry` raises if it is not. The skeleton is assigned per element in the
  wall's inner 11 mm (`DepthInCore`, a Newton solve for the nearest
  point on the ellipse):
  - twelve horizontal rib hoops of bone (0.02 S/m). `ChestStep` (6.5 mm)
    and `ChestBottom` (56 layers) were chosen so each rib is exactly two
    axial layers at a four-layer pitch;
  - costal cartilage (0.18 S/m) at the front;
  - ribs 8-10 stop either side of the midline and 11-12 at the sides;
  - a sternum plate;
  - a spine cylinder through core and wall.

  The ribs start just below the root of the neck (`ChestTop` 0.02,
  `RibFirstLayer` 3). Ribs 8-12 lie round the upper abdomen, below the
  diaphragm, as real ribs do. The spine keeps 30 mm in front of the back
  of the core, so it leans forward up the cone. The heart rests just
  above the diaphragm (centre 0.18 m below the top). The lungs run from
  the apex of the cone to the diaphragm (2.3 L together), and what
  pokes outside the wall's inner edge stays wall.
  - **Left lung wrapped round the heart** (2026-10-31, `InLungWrap`,
    default on, `--no-wrap` to compare). A 25 mm shell round the heart
    becomes lung on its left, leaving the cardiac notch in front, the
    mediastinum behind and the diaphragm below as core. The report now
    tallies what lies within 10 mm of the heart, with the core split by
    side. **It changes almost nothing.** The plain ellipsoid already
    gave 69 % lung contact, and the wrap gives 71 % (19 mL added). Wrapping
    every side but the diaphragm (a test run, not kept) gives 88 %. The
    heart share goes 12.9 / 12.9 / 12.7 %, resistance 66.2 / 66.2 /
    66.8 ohm. At 0.08 S/m against the core's 0.15, a thin lung layer is
    too weak an insulator to steer current round the heart, so the lungs'
    placement is not why the share is high. The anisotropic and
    biphasic runs were not repeated with the wrap.
  - **A thicker chest wall** (2026-11-01, a test, not kept: only
    `WallThickness` changed, with the wrap on). It thickens the wall
    inwards, at the core's expense; the body's outline and masses are
    unchanged. 18 / 27 / 31 mm (31 is just under the 33 mm curvature
    limit) give heart share 12.9 / 11.8 / 11.6 %, resistance 66.2 / 60.8 /
    59.7 ohm, mean myocardial field 42.5 / 40.7 / 40.4 V/cm, and the
    wall's share of the power 21 / 30 / 32 %. At 31 mm the wall reaches
    within 10 mm of the heart at the front. So the extra shunt helps only
    a little, and this geometry can't take a wall thick enough to explain
    a ~4 % share. A fatter or more muscular outer body, which would mean
    changing ThermEx1's masses, wasn't tried.
  - **Lung conductivity 0.04 S/m** (2026-11-01; it was 0.08, and the
    wrap and wall tests above were run at 0.08). With the wrap on,
    0.08 / 0.04 / 0.02 S/m give heart share 12.9 / 11.2 / 9.3 %,
    resistance 66.2 / 70.8 / 74.2 ohm, peak 36.9 / 35.5 / 34.5 A, mean
    myocardial field 42.5 / 36.1 / 30.3 V/cm, but maximum 103 / 133 /
    159 V/cm (the heart's surface next to the lung). The strongest lever
    tried so far, and it brings the resistance into the clinical 70-80
    ohm, but even 0.02 S/m leaves the share over twice ~4 %. 0.04 was
    kept as the default at the user's choice: an effective inflated-lung
    value (air makes inflated lung *less* conductive than deflated),
    within the published spread rather than a measurement.
  - **Height and weight** (2026-11-01, `--height=<m>`, `--weight=<kg>`,
    `TDefibModel.Height`/`Weight`, set before `Run`; defaults 1.75 m and
    70 kg reproduce the old figures exactly). The fat-free mass is
    Al-Sallami's `freeFatMass` from `Anaesthetics/PK-PD_FPC/uBodyStats.pas`
    (on the `.lpi`'s unit path; age fixed at `BodyAge` 35, male), which
    gives ThermEx1's man 56 kg fat-free, 20 % fat, though only his 3.5 kg
    of subcutaneous fat is a compartment. A body is ThermEx1's trunk plus
    the differences from that man: 50.8 % (the trunk's `MassFrac`) of the
    change in fat-free mass, skin by DuBois area and the rest split between
    core and muscle in their ratio, plus `TrunkFatShare` (0.5) of the change
    in fat, all into the fat layer. Trunk lengths scale with height; organs,
    ribs and pads keep their sizes and depths below the neck. **120 kg,
    1.80 m** (BMI 37, 37 % fat): trunk 60 L, 425 x 306 mm at the waist,
    fat 33 mm at the side (3 mm before). Resistance 131 ohm (71), fat 62 %
    of the power (16 %), heart share 8.6 % (11.2 %), peak 23.6 A (35.5),
    225 J, mean myocardial field 18 V/cm (36), range 10-56. The fat layer
    is as thick over the chest as the abdomen, so the resistance is likely
    too high; not checked against measured impedances in obese patients.
  `TDefibView.DrawSkeleton` draws the skeleton from the same rules, not
  from the elements, with a "Skeleton" check box.
- **Pads.** Each pad is a 1 mm sheet of 1e4 S/m bricks extruded on the
  skin faces it covers, the same construction as ThermEx1's gown. That
  makes it an equipotential without constraining the skin. 1 A goes into
  the sternal pad, and the apex pad is penalty-held at 0 V. The sternal
  pad's potential is then the resistance in ohms.
- **Time.** Quasi-static. Tissue relaxes charge in microseconds, so the
  field is the 1 A solution times I(t), an RLC damped sine (32 uF, 50 mH,
  11 ohm; charged for 200 J into 50 ohm). The animation's "spread" is the
  region above a chosen |J|. Don't add a diffusing or travelling front:
  that would be wrong physics.
- **Results** (lung 0.04 S/m). 71 ohm transthoracic resistance, against
  the clinical 70-80. Peak 35.5 A at 1.25 ms, 211 J delivered. Power
  balance within 1.3 %. (Lung 0.08: 66 ohm, 36.9 A, 209 J.) The skin current at the sternal pad comes to 0.995 A, counted
  over the pad and 1 cm round it, because the current crowds in at the
  pad edge. The pads are at 0.10 and 0.21 m below the root of the neck.
  On the old cylinder it was 73 ohm (80 before the wall, which replaced
  0.15 S/m core with 0.25 S/m muscle), peak 35 A, 212 J.
- **Heart share is still high.** About 11.2 % of the current crosses the
  heart, against ~4 % in the literature, with myocardial fields of
  18-133 V/cm at peak (mean 36); 12.9 % and 22-103 V/cm with the lung at
  0.08. On the cylinder it was 12 %, 25-86
  V/cm; without the wall and ribs, 16 %. Enlarging the lungs from 3 to
  4.2 L changed nothing then. The report lists what's still missing,
  chiefly the lean, armless, smooth trunk.
- **Anisotropic muscle** (`--anisotropic`, set before `Run`; it needs
  its own solve). Muscle and chest wall get 0.52 S/m along fibres and
  0.076 across (Epstein & Foster 1983), fibres horizontal and tangent to
  the section's ellipses (`FibreDir`). `PostProcess` uses `CurrentFrom`
  for J = -sigma grad phi and J.E for the power. It made things *worse*
  against the literature, not better: 85 ohm (71 isotropic), heart share
  12.6 % (11.2 %), myocardial field 21-139 V/cm at the monophasic peak;
  with the lung at 0.08, 80 ohm (66), 13.6 % (12.9 %), 25-102 V/cm.
  On the old cylinder: 91 ohm (73), 15 % (12 %), 28-78 V/cm. Across
  the fibres includes up and down the trunk, so the wall spreads current
  along the body less. That explanation is a reading of the numbers and
  hasn't been checked separately.
- **Biphasic shock** (`--biphasic`, or the Shock radio buttons in the
  window): a generic biphasic truncated exponential, 100 uF straight
  into the torso, phase 1 to 50 % tilt (t1 = tau ln 2), then reversed
  for 2/3 t1. That always delivers 90.1 % of the stored energy, so V0 is
  set for exactly 200 J at any resistance. In closed form, no RK4.
  Isotropic, lung 0.04: 2107 V, 29.7 A falling to 14.9 A over 4.91 ms,
  then -14.9 to -9.4 A over 3.27 ms (lung 0.08: 31.9 A to 15.9 A over
  4.59 ms, then -15.9 to -10.0 A over 3.06 ms). `Biphasic` can change after `Run`: `Run` saves
  the report's line count before `ComputeWaveform` (`FShockStart`, with
  `TraceLines` moved before it) and `SetBiphasic` truncates there and
  redoes the waveform and heart sections without solving again.
  `TPeak` is 0 for the biphasic shock.
- **Current direction colours** (added 2026-10-30): field lines and the
  cloud are yellow where the current heads towards the heart's apex
  (`Heart.C + R[0]*U[0]`, since `U[0]` runs base to apex) and blue where
  it heads away. The test is the sign of `I(t) J . (apex - P)`, with each
  field-line segment's direction standing in for J, because the lines
  were traced along J for +1 A. So the biphasic second phase shows the
  colours swapped.
- **Output files.** The mesh goes to `mesh/` in the project folder (23 MB,
  ignored by the `FEM4/Examples/*/[A-Za-z0-9]*` rule), not to `FEM4/Examples/Data`,
  where the msh would be untracked-but-visible.
- **Command line.** `--no-plot` gives a headless report.
  `--anisotropic` and `--biphasic` as above. `--snapshot=<prefix>`
  saves the 3D view at 0.2, 0.5 ms, the peak, 4 and 8 ms via
  `TDefibView.SaveToPNG`, plus the waveform and window. `--time=<ms>` saves
  one frame instead.

### `FEM4/Examples/HFJV`

Added 2026-11-03: high-frequency jet ventilation in a supine adult male,
work in progress. Console programs so far, built with plain `fpc -O2
-FUlib -Fu../../../newVM -Fi../../../newVM -Fu../../../demos/JetVent`
(the JetVent path is for `uJetCalcVM`), plus, for anything using the torso,
`-Fu../Defibrillation -Fu../ThermEx1 -Fu../../../Anaesthetics/PK-PD_FPC
-Fu../../../newVM/Graphs` and `-Fu"../../../newVM/Delphi OOFEM/FEM4/Development/Source/<dir>"`
for each FEM4 source directory (for `TGmsh`; the full list is in `hfjvrun.lpr`'s header). The
user's design choices are:
supine, the abdomen an incompressible fluid rather than a viscoelastic
solid, frequency and time domain both, and a FEM4 example. Units:

- `uDescriptor.pas`: one sparse system `E x' = A x + b`, built from
  triplets by every part. The frequency response `(iwE - A)X = B` is
  solved as the real 2N block system. Time stepping is trapezoidal, with
  algebraic rows imposed at the new time and the step matrix factorised
  once (`TPardisoFactor`, added to `newVMsparse.pas` for this, with
  tests).
- `uAbdomenFluid.pas`: potential flow on P1 tetrahedra, with drag
  alpha. Boundary surfaces are rigid (they reflect waves) or moving
  membranes with mass, tension, damping and gravity `rho g_up`, which is
  what makes the gravity waves. Volume is conserved through the constant
  part of phi, so the diaphragm going down is the wall coming up.
  `FindBoundary` orients faces from the tets. A moving node on a rigid
  edge is clamped only if its surface says so: the tank checks' free
  surface must not be.
- `uThorax.pas`: lumped upper and lower airways, alveolar gas
  compression, lung recoil and tissue resistance, pleural pressure, and
  the rib cage. The diaphragm is lumped, or the FEM diaphragm with
  `p_pl` coupled. The jet comes from JetVent's **bench data** (at the
  user's request): measured flow interpolated in driving pressure, and
  momentum pressure from the measured stall pressure scaled as 1/D^2 to
  the trachea (for the Cook, interpolated between 15 and 22 mm). Crane
  and the momentum formula are the fallback. The default is the user's
  "typical" setting: 2 bar, 200 /min, I:E 1:1, Biro.
  - **Turbulent upper airway** (added 2026-11-03): Rohrer's
    `R_ua Q + K_ua |Q| Q`, defaults R_ua 1.0 cmH2O/(L/s) and K_ua 1.0
    cmH2O/(L/s)^2. These are assumed, chosen to match the old linear
    2.0 at 1 L/s. The K term is the only nonlinearity, so it isn't put
    in A: it is a forcing `-K|Q_ua|Q_ua` on the upper airway's row
    (`UASource`, `UAPattern`). Impedances and the matrices see R_ua only
    (small-signal at zero flow). `K_ua = 0` is the linear model;
    `--kua=0 --rua=2` reproduces the earlier figures exactly.
- `uHFJVSolve.pas`: the steady cycle by harmonic superposition (the
  mean taken at 1e-5 Hz, since at exactly zero frequency the volume
  constraint drops out) or by stepping, plus VT, VT/VD, f VT^2,
  pressures and entrainment. `TResponseCache` keeps each frequency's
  outputs so a sweep of rate solves each frequency once (harmonic 3 of
  200 /min is harmonic 1 of 600): about half the solves. It also holds
  the response to a unit forcing on the upper airway's row, a second
  right-hand side on the same factorisation
  (`TDescriptorSystem.SolveFrequencyN`).
  - **Harmonic balance for the turbulent upper airway**: only Q_ua is
    solved self-consistently, on M = 8 NHarm samples:
    `q = q_jet + L s(q)`, `s = -K|q|q`. L is circulant, built from the
    upper airway's own transfer H_n. Newton with the dense M x M
    Jacobian `I + 2K L diag|q|` converges in about 5 iterations. Every
    other output then adds its response to s's harmonics.
    `UpperAirwaySource` gives s's harmonics to callers that need whole
    states (`AnimFile`, `WallWaves`).
  - **Stepping is exact for the nonlinear system**: the old loss goes
    into the right-hand side, and the new one is the linear step plus
    `g s_new / 2`, with `g` the step matrix's response to the upper
    airway's row (`TTrapezoidStepper.Solve`). Q_ua then satisfies
    `q + c|q|q = q0`, solved in closed form.
- `uAbdomenBox.pas`: a 0.30 x 0.26 x 0.14 m box abdomen (10.9 L,
  ThermEx1's core size), the first test geometry; `hfjvrun --box`.
- `uTorsoAbdomen.pas` (the default abdomen): the abdominal cavity of
  **Defibrillation's torso**, with a diaphragm dome and a pelvis. Its
  header has the geometry. Things worth knowing:
  - **Pull Defibrillation from GitHub first** (the user's instruction):
    the GitHub version (thorax cone on an elliptical abdomen) was more
    realistic than this machine's. `TDefibModel.SetupGeometry` was made
    public for this, so the torso can be sized (ThermEx1's masses,
    `--height`/`--weight`) without meshing Defibrillation itself.
  - Defibrillation's coordinates are kept: y up from the back, so
    supine gravity is `(0, -9.81, 0)`, not the box's -z.
  - The cavity is the chest wall's inner edge (`WallPoint` at
    `WallThickness`), with a lumbar ridge, the pelvis narrowing below
    the iliac crest to the inlet and outlet, and a dome inserting 15 mm
    above the costal margin (xiphoid, ribs 10 and 12 from Defibrillation's
    skeleton) and rising 65 mm above Defibrillation's flat diaphragm.
  - Surfaces by centroid: anterior wall (below the costal margin, above
    pubis and iliac crest, round to the posterior axillary line),
    diaphragm (above its rim), the rest rigid - including the rib band
    between margin and insertion. The 1.75 m, 70 kg man: 10.08 L, wall
    1005 cm2, diaphragm 613 cm2.
  - **The pelvis is from published data** (2026-11-04, at the user's
    request; it was my estimates, 9.96 L and wall 912 cm2): inlet
    119.8 x 110.6 mm and outlet 99.6 x 86.5 mm, the male CT means of Zhou
    et al., World J Gastrointest Oncol 2024;16:773 (139 men); iliac crest
    12.28 % of stature above the perineum (215 mm), from ANSUR II's
    public male data (iliocristale less crotch height, 4082 men); brim
    at the pubis plus half the inlet's AP times sin 60 deg. The pubis
    and floor heights, the floor's depth and how far back the inlet and
    outlet sit are still estimates, and the narrower mid-pelvis
    (interspinous 90.8 mm) is left out. The msh tag is now
    `abdomen_p2_...`. Torso at 200 /min: VT 177.0 mL (stepping 177.0)
    against 178.9, VE 35.4 against 35.8 L/min, entrainment 13.5 against
    13.9, the abdominal Rrs peak 3.5 Hz against 3.75; the dead-space
    crossing and the resonance (6.9 Hz) are unchanged. The midline wave
    peaks lower, near 220 mm, with a small antiphase lobe above 370 mm.
    `mesh/*_pelvis.png`, `wall200_pelvis.gif`.
  - Meshing is gmsh's STL-remesh workflow (tutorial 13): `WriteSTL`
    writes rings of points from the formulae, gmsh remeshes and fills
    it (~36 s at 12 mm), and the msh is cached in `mesh/` under a tag
    of height, weight and size. Two FPC traps: `TVec3` is declared in
    both `uDefibModel` and `uAbdomenFluid` (put `uAbdomenFluid` last in
    `uses`), and `Sto_ShellExecute`'s exit code is a `Cardinal`.
  - The wall's mass is 36 kg/m2 (35 mm of muscle and fat) against the
    box's 25.
- `hfjvmesh.lpr`: builds the torso mesh and reports its landmarks,
  volume and surface areas; writes `mesh/abdomen_surfaces.vtk`.
- `hfjvcheck.lpr`: checks against exact solutions, all passing:
  - tank sloshing with and without a membrane, within 2 %;
  - the lumped thorax against hand-combined impedances, to rounding;
  - harmonics against stepping, lumped and with FEM; lumped also with
    the turbulent upper airway (harmonic balance against exact
    stepping: VT 0.08 %, mean alveolar pressure 0.004 %, mean tracheal
    pressure 0.02 %, entrainment 0.04 %);
  - the FEM diaphragm against `E = rho g / A_top` quasi-statically,
    within 0.15 %.
- `hfjvrun.lpr`: the impedance, a sweep of rate, and the anterior
  wall's wave along the midline, xiphoid to pubis on the torso (`--dp
  --rate --ie --cannula --calculated --lumped --rua --kua --alpha
  --steps --harm --box --height --weight --size`). 30 harmonics by default: on the
  lumped model VT is within about 1 % of 60 harmonics (10: 2-3 %).
  The torso at 12 mm (36251 unknowns) takes about 5.5 min with
  `--steps`. Stepping at 200 /min gives VT 186.6 mL against the
  harmonic balance's 186.3, with mean alveolar pressure 6.27 cmH2O both
  ways (linear upper airway: 188.6 against 188.4, and 5.98).
  `--anim=<file>` instead writes one cycle of every
  moving node's displacement (all harmonics, mean removed) and the lung
  volume, and `anim_wall.py <file> <out.gif>` animates it: the cavity
  with its surfaces pushed out along their normals (exaggerated) and
  coloured by displacement, the front midline's profile with its
  envelope, and the lung volume. At 200 /min the midline's wall moves
  up to 2 mm in two lobes, below and above ~330 mm, in antiphase.
  `--zfile=<file>` writes the impedance at 0.25-20 Hz as CSV, and
  `plot_impedance.py <out.png> <label>=<csv> ...` plots Rrs and Xrs
  against frequency and rate for several abdomens. Resonance below the
  jet: torso 5.5 Hz, box 4.5, lumped 4.9. The torso's resistance peaks
  at 2.6 near 3 Hz (180 /min), its abdominal gravity-tension mode,
  against the lumped model's smooth 2.2-2.5.
  `--vfile=<file>` writes the cycle every 20 /min from 40 to 900 (20
  harmonics, ~400 solves with the cache, ~9 min on the torso), and
  `plot_ventilation.py` plots VE = f VT and VT against rate. VE is flat
  at 37-40 L/min from 100 to 400 /min and falls only to 35 by 900: the
  jet's own 22.5 L/min plus entrainment. VT falls below the 120 mL dead
  space at about 320 /min. The torso's dip near 180 /min is its
  abdominal mode (the resistance peak above). These figures, and the
  impedance, wall-wave and animation results above, are from before
  the turbulent upper airway, so they match `--kua=0 --rua=2`. With
  the linear upper airway, mean alveolar pressure is the same at every
  rate (Ti (Q_on R_ua + dp_on)), 5.98 cmH2O.
  - **With the turbulent upper airway** (the default since 2026-11-03),
    on the torso, mean alveolar pressure is higher and varies with
    rate: 6.20-6.31 cmH2O, highest at 100 /min. Mean tracheal pressure
    is about 1.04 cmH2O against 0.75. VT is about 1 % lower (186.3 mL
    at 200 /min) and entrainment 2-4 % lower. The difference is
    modest because K_ua was chosen to give the old resistance at
    1 L/s.
  - **With the glottis** (0.8 cm2, the default since 2026-11-03,
    `--glottis=0` to leave it out). It is an orifice in the upper airway
    with loss `k rho |Q|Q / (2A^2)`, where k = 1.37 (Ishizaka-Flanagan)
    and rho = 1.2 kg/m3. That is 1.31 cmH2O/(L/s)^2, added to K_ua, plus
    an inertance rho L/A (1 cm deep: 0.0015 cmH2O s2/L) added to I_ua
    (`TThorax.KuaSI`/`IuaSI`). Torso at 200 /min: VT 161.8 mL (stepping
    162.0), entrainment 53 mL against 78, mean alveolar pressure 6.85
    cmH2O, mean tracheal pressure 1.62. VE falls from 37-38 to 32-33
    L/min across rates, and VT reaches the 120 mL dead space at about
    270 /min rather than 315-320. Linear, turbulent and glottis sweeps
    are `mesh/v_torso.csv`, `v_torso_turb.csv` and `v_torso_glottis.csv`,
    plotted together in `ventilation_glottis.png`, with
    `wall200_glottis.gif` for the animation. The animation's midline
    envelope is about +-1.7 mm, against +-2 mm before. The impedance
    below the jet is unchanged: the glottis is above the jet.
  - **Mean subglottic (tracheal) pressure** against frequency:
    `--vfile` now also writes `Ptmean` and `Ptmax`, and
    `plot_pressure.py` plots them (`mesh/subglottic_pressure.png`).
    With a linear upper airway it is exactly R_ua times the mean jet
    flow, 0.75 cmH2O at every rate for any abdomen, because all the
    jet's gas leaves through the mouth. Torso values:

    | | range | at 200 /min | peak |
    |---|---|---|---|
    | turbulent | 0.88-1.08 | 1.04 | 100 /min |
    | with the glottis | 1.38-1.69 | 1.62 | 100 /min |

    Both rise to the peak and then fall slowly (1.48 at 900 /min with
    the glottis). They also have the torso's ripple near its abdominal
    mode (~180 /min); the lumped model is smooth.
  - **Entrainment rate** against frequency: `plot_entrainment.py`
    (`mesh/entrainment.png`) plots f x the volume entrained per cycle
    (`entrained_mL`, the inward part of the upper-airway flow) and its
    ratio to the jet's gas, with `--bench=35` drawing the Biro's bench
    open-air entrainment at 2 bar (80 - 45 L/min while open) times Ti,
    17.5 L/min. Torso at 200 /min: linear 15.9 L/min (ratio 0.71),
    turbulent 15.6 (0.69), glottis 10.7 (0.47). Each peaks near
    100 /min (18.5 / 17.6 / 12.1) and falls slowly to 12.8 / 12.7 / 8.9
    at 900 /min. The glottis cuts it by about a third at every rate.
  - **Constant-phase tissue and wall damping** (added 2026-11-03, now
    the defaults). Lung tissue, rib cage and the lumped diaphragm are
    Hantos's constant-phase tissue `Z = A (i w)^-alpha`, with
    `alpha = (2/pi) atan(1/eta)`. Hysteresivity `eta` is 0.15 for both
    `EtaL` and `EtaCW` (`--etal`, `--etacw`; 0 gives the old constant R).
    E is the elastance at `FRef` 0.25 Hz. For the lung that gives
    R 0.67 at 0.25 Hz but 0.064 at 200 /min, and E rising from 7.0 to
    8.9. The fractional power is realised as a sum of positive
    relaxations (`MakeTissue`). That sum comes from the integral
    `(i w)^-alpha = (sin(alpha pi)/pi) int s^-alpha/(s + i w) ds`,
    sampled 3 a decade from 1 mHz to 1 kHz: 18 unknowns
    `tau_k p_k' + p_k = R_k Q` per tissue. The spectrum below the range
    becomes a spring E_0 (0.59 E) and the part above a resistance R_inf.
    It is passive, works in both domains, and is within 0.06 % of the
    exact Z from 0.1 to 100 Hz (`hfjvcheck`'s `TissueCase`).
    - **Stepping needs a mean correction**: the slowest relaxation is
      160 s, so from rest stepping hadn't settled in 200 cycles. After
      each cycle `CycleByStepping` shifts the state so its cycle mean is
      the near-DC (1e-5 Hz) response to the cycle's mean forcing, jet
      plus the trapezoidal mean of the turbulent loss. A periodic
      trapezoidal cycle satisfies that exactly, so the steady state is
      unchanged. It settles in 13-23 cycles.
    - **Membrane damping**: `--cwall` 300 and `--cdia` 200 Pa s/m (were
      0). They come from the lumped diaphragm/abdomen's constant-phase R
      at 200 /min (0.073 cmH2O/(L/s)), split equally between the two
      walls as c = R A / 2, since c/A adds in series through the
      incompressible contents. They are viscous, so they are constant
      in frequency.
    - **Results, torso, glottis on, 200 /min**: VT 174.5 mL against
      161.4 (stepping 174.2), VE 34.9 against 32.3 L/min, entrainment
      13.4 against 10.7 L/min, mean P_t 1.75 against 1.62 cmH2O. VT
      reaches the dead space at 300 /min (was 280). Below the jet, Rrs
      now falls with frequency, from 2.4 at 0.25 Hz to 1.55 by 10 Hz,
      instead of a flat 2.1-2.5. Resonance moves from 5.5 to 7.0 Hz.
      Nearly all of the change is the tissue: the default wall damping
      changes VT by under 1 %, and even 10 x (3000/2000) only smooths
      the abdominal dip near 160 /min and the new VE peak near 740 /min.
      The lighter tissue damping uncovers both. Sweeps are
      `mesh/v_torso_tissue.csv`, `_cponly`, `_c1000`, `_c3000`, and
      `z_torso_tissue.csv`; the plots are `mesh/*_tissue.png`. The
      lumped model, its rib cage-diaphragm mode now lightly damped,
      shows a Rrs bump at 5 Hz and dia % over 100 at 250-300 /min.
  - **Viscoelastic contents, bowel gas, abdominal fat** (2026-11-03,
    the defaults; the user chose storage and loss, and one fat % for
    wall and contents). `uViscoelastic.pas` now holds `TTissue`/
    `MakeTissue`/`TissueImpedance`, moved out of uThorax so
    uAbdomenFluid can use them (uThorax uses uAbdomenFluid).
    - **Contents**: a constant-phase viscoelastic (Winkler) foundation
      under each moving surface (`TSurfaceProps.VEStiff`, Pa/m at
      `VEFRef` 0.25 Hz; `VEEta` 0.15). The bank has unit stiffness, 2 a
      decade from 10 mHz to 1 kHz, so 10 states per unclamped moving
      node, shared by every surface: 3873 nodes, and the torso system
      grows from 36k to 75k unknowns (a full `--steps` run took 44 min
      with nine others running). It stands in for the contents' shear
      stiffness, which potential flow lacks, but not its dependence on
      wavelength. `hfjvrun` calibrates
      `k_f = E_ab / (1/A_dia + 1/A_wall)`, the two in series through
      the incompressible contents, with `--eab` (8 cmH2O/L, the lumped
      `Edi`; 0 turns it off) and `--veeta`: 28.8 kPa/m on the torso,
      about 2.9 rho g. It replaces the viscous wall damping, so
      `--cwall`/`--cdia` now default to 0.
    - **Bowel gas** (`GasVolume`, `--gas` 150 mL, adiabatic gamma 1.4 at
      `GasPAbs`): spread uniformly. Two unknowns, dV_g and Q_g; the phi
      rows gain `-(m_i/V) Q_g` and stay algebraic, and the gas row is
      `C_g rho/V m.phi' = dV_g - C_g rho alpha/V m.phi`. C_g is
      1.0e-4 L/cmH2O, against the respiratory system's ~0.05, so it is
      negligible: 1000 mL changes VT at 200 /min by 0.6 %.
    - **Fat** (`--abfat` 20 %, by volume): contents
      `rho = f 900 + (1-f) 1060` (1028 at 20 %), and an anterior wall of
      20 mm of muscle plus `20 f/(1-f)` mm of fat (5 mm, 25.7 kg/m2 at
      20 %; it was a fixed 36). k_f is scaled by
      `(1-f) + 0.3 f` relative to 20 %, fat taken as 0.3 x as stiff
      (assumed). The torso's geometry still follows `--weight` alone.
    - **Checks** (`hfjvcheck`, all passing): `VEGasCase`, the tank with
      a massless diaphragm end, a foundation on the free surface and
      1 L of gas at 0.05 Hz, against
      `V_di/p_pl = A/(rho g + k_f i w Z) + C_g` (0.08 %) and
      `dV_g/p_pl = -C_g` (0.06 %). The adult box cycle now has both and
      still agrees, harmonics against stepping (VT 0.013 %). Torso at
      200 /min: stepping 178.9 mL, the same as harmonic balance.
    - **Results, torso at 200 /min**: VT 178.9 mL (173.5 without the
      contents, 174.5 for the previous model), VE 35.8 L/min,
      entrainment 13.9 L/min, mean P_t 1.79 cmH2O, and VT reaches the
      dead space at 320 /min (was 300). The diaphragm now carries 69 %
      of VT at 200 /min (48 % without), because the stiffer abdomen
      moves its mode from 2.75 Hz (165 /min) to 3.75 Hz (225 /min),
      close to the jet. Rrs peaks there at 1.95 against 2.50: the
      foundation's loss damps the mode. Resonance is unchanged at 6.9 Hz.
      A foundation of 2.9 rho g only raises the mode by 1.36 x: the
      contents' added mass and the lung in series also set it. So it
      does not reach the 4-8 Hz visceral resonance of whole-body
      vibration. Fat 10 / 20 / 40 %: VT 179.7 / 178.9 / 177.0 mL. The
      sweeps are `mesh/v_torso_ve.csv`, `_nove`, `_fat10`, `_fat40`,
      `_gas0` and `_gas1000`, plus `z_torso_ve.csv` and `_nove`. The
      plots are `mesh/*_ve.png` and the animation `wall200_ve.gif`,
      whose largest wall motion is 2.4 mm.
- **Modes, exactly** (2026-11-04): `hfjvrun --eigdump=<prefix>
  --eig=<Hz> [--krylov=<m>]` writes E and A as triplets
  (`TDescriptorSystem.WriteTriplets`), the dofs and wall/diaphragm
  volume weights, and an 80-vector shift-invert Arnoldi basis on
  `OP = (i w0 E - A)^-1 E`. It is factorised once by PARDISO
  (`TDescriptorSystem.FactorFrequency`, now shared with
  `SolveFrequencyN`) and takes 26 s on the torso. scipy's `splu` on the
  same 86k system hadn't finished after 10 min. `eig_modes.py <prefix>
  <Hz>` turns it into eigenvalues `lambda = i w0 - 1/nu`, checks each by
  its residual `|Ax - lambda Ex|/|Ax|`, and labels it by the volume it
  sweeps per mm of peak wall motion. Torso at 3.5 Hz, residuals about
  1e-15: **the abdominal mode is f_n 3.528 Hz, zeta 0.1805 (Q 2.8)**,
  24 mL/mm at wall and diaphragm alike (incompressible). A fit to the
  Rrs bump gave 0.14-0.20. The next volume-coupled mode is 5.28 Hz,
  zeta 0.096, 11 mL/mm and 71 % on the wall: the Rrs ripple near
  5.25 Hz. Modes at 4.21, 5.00 and 5.82 Hz sweep little or no net
  volume, and 6.41 Hz sweeps 3 mL/mm. Ritz values far from the shift
  don't converge, so read only those flagged converged. FPC trap hit
  again: a parameter `Fn` hides the field `FN`. `eig_modes.py` now keeps
  real roots (overdamped modes: zeta 1, f_d 0, f_n = decay rate / 2 pi).
- **Jet pump characteristic** (2026-11-05, the default; `--nopump`
  for the old constant stall pressure). The jet's pressure rise falls
  linearly with entrained flow, from the stall pressure (scaled to the
  trachea) at none to 0 at the bench's open-air entrainment (total less
  jet flow): `dp_j = dp_on - R_j Q_s`, `R_j = dp_on / Q_free`
  (`TThorax.RJet`, `QFree`). Biro at 2 bar: 10.5 cmH2O, 0 at 35 L/min,
  R_j 17.9 cmH2O/(L/s). The open-air end point is an assumption: there is
  no bench entrainment into a tube against no back pressure.
  - **How it's solved**: R_j acts only while the jet is on, so it is
    time-varying. Moved through the tracheal node (whose other branches
    are the upper airway and the jet's ideal flow source), it becomes an
    extra resistance R_j on Q_ua while the jet is on: part of the upper
    airway's forcing (`UASource(Q, On)`), in the same harmonic balance as
    the turbulent loss (the Jacobian gains `L diag(on R_j)`, on = 1/2 on
    an edge sample). The tracheal node's unknown then reads
    `p_t + on R_j Q_ua`, so the true p_t is taken back off: in harmonics
    as the correction's own Fourier series from the balance's samples (so
    its edge ringing cancels the node's; sampling it at the output points
    instead put the mean 1.2 % off), in stepping by `TrachealP`.
  - **Stepping is first order with the pump**: a resistance switched
    with the jet is a discontinuous coefficient, not just a forcing.
    Mean tracheal pressure 0.769 / 0.759 / 0.7545 / 0.7523 cmH2O at
    200 / 400 / 800 / 1600 steps a cycle against the exact 0.75 (harmonic
    balance gets it exactly). `hfjvcheck`'s pump cases step at 1600; a
    new lumped case has the pump on a linear upper airway. All pass.
  - **Results, torso at 200 /min** (against the same model without it,
    `v_torso_p2.csv`): VT 138.6 mL (177.0), entrained 27.7 mL per cycle
    (67.6), entrainment ratio 0.25 (0.60), 5.5 L/min (13.5), mean
    alveolar pressure 4.99 cmH2O (7.00), mean tracheal 1.36 (1.77). VE
    28 L/min (35.5). VT reaches the 120 mL dead space at about 235 /min
    (320). Impedance unchanged (the pump acts only while the jet is on).
    `mesh/v_torso_pump.csv`, `mesh/*_pump.png`.
- **Drag follows abdominal fat** (2026-11-05, the default; `--alpha=<1/s>`
  overrides, and `--alpha=5` reproduces every figure above). The user's
  measurements: the abdominal gravity wave is overdamped in slim patients
  and oscillatory only with excess intra-abdominal fat, obese 180-220 /min
  with zeta 0.2-0.5. A sweep of the exact modes showed that body size,
  wall mass, contents density and foundation stiffness as modelled barely
  move zeta; only the drag does (both 120 kg at 40 % fat and 67 kg at 10 %:
  alpha 5/20/40 /s gives zeta about 0.17/0.46/0.8, overdamped from about
  55-60 /s, f_n rising from 3.6 to ~5 Hz near critical). So `DragForFat`
  in `hfjvrun.lpr` sets alpha = 70 /s at `--abfat` 20 % or less, falling
  log-linearly to 15 /s at 40 % and held beyond. The anchors (which fat
  fraction counts as slim or obese) are my choice, not measured. Checks:
  the default 70 kg man's abdominal mode becomes a real root (decay
  13.8 /s); 30 % fat (32 /s) gives f_n 3.88 Hz, zeta 0.71; the 1.80 m
  120 kg torso at 40 % gives f_n 3.69, f_d 3.44 Hz (206 /min), zeta 0.36.
  Default man at 200 /min, alpha 5 -> 70: VT 177.0 -> 179.5 mL, the
  diaphragm's share of VT 69 -> 14 %, entrainment 67.6 -> 72.2 mL; the Rrs
  bump near 3 Hz goes, Rrs now falling smoothly 2.11 -> 1.55 from 1 to
  10 Hz; the midline wall at the fundamental falls from 1.75 mm peak low
  in the abdomen to 0.38 mm just below the costal margin (these cycle
  figures were run before the jet pump, i.e. as with `--nopump`). With
  the pump as well (both defaults), alpha 5 -> 70: VT 138.7 -> 139.2 mL,
  diaphragm 69 -> 14 %, entrained 27.9 -> 29.7 mL per cycle, mean
  alveolar pressure 4.97 -> 4.89 cmH2O, mean tracheal 1.37 -> 1.39, wall
  peak 1.36 -> 0.29 mm; across 60-800 /min VT changes by at most 2 %
  (the drag's largest effect, at 60 /min: 444 -> 435 mL). Why fat would
  lower the drag (lubricated, less tightly packed bowel) is a reading, not
  modelled. The sweeps, plots, animations and earlier figures were not
  rerun.
- **The chest follows BMI** (2026-11-10, the default on the torso;
  `--nochest` keeps the 70 kg chest at any `--weight`). Lung elastance,
  FRC, lower-airway resistance, rib-cage elastance and the abdominal load
  move from their 70 kg values to obese/normal ratios measured in
  anaesthetised, paralysed supine adults. The full ratio applies at BMI 49
  (150 kg, 1.75 m), with exponential interpolation in BMI below that (Pelosi 1998
  found FRC and compliance exponential in BMI). Nothing changes at 70 kg,
  1.75 m. `--el --frc --raw --erc --irc --eab` override each value.
  - **Ratios**: lung E x1.93 and FRC x0.39 (Pelosi 1996), Raw to
    4.7 cmH2O/(L/s) (Pelosi's obese Rmin,L), rib cage E x1.14 (Behazin
    2010's chest-wall compliance). Rib-cage inertance scales with the
    abdominal wall's mass per area, since fat adds mass but not area.
  - **The abdominal load ratio (`AbdomenRatio` 2.015) is calibrated, not
    measured.** It is the value that makes the whole chest wall (rib cage
    in parallel with the FEM diaphragm and abdomen) Behazin's x1.14 stiffer
    at 0.25 Hz, found from `--zfile` runs. 150 kg: 12.7 cmH2O/L against 8.0, so
    k_f 60.9 kPa/m, under a wall of 1248 cm2 and a diaphragm of 803 cm2,
    on a 14.6 L cavity.
  - **Modes of the 150 kg man** (`--weight=150 --abfat=46`, exact by
    `--eigdump`, 12 mm mesh, residuals below 1e-13). The volume-coupled
    modes are:
    - 4.44 Hz, zeta 0.142, 29 mL/mm, 69 % on the wall;
    - 5.93 Hz, zeta 0.10, 16 mL/mm, 73 % on the wall;
    - weaker modes at 7.13, 7.65, 7.97 and 8.43 Hz (3-7 mL/mm).

    The two main modes for the other cases:

    | Case | First mode | Second mode |
    |---|---|---|
    | 70 kg | 3.53 Hz, zeta 0.18, 24 mL/mm, 35 % wall | 5.28 Hz |
    | 150 kg, `--nochest` | 3.69 Hz, zeta 0.17, 29 mL/mm, 65 % wall | 4.89 Hz |

    A 9 mm mesh (119k unknowns) moves the main two modes by under 0.3 %
    and the others by under 1 %. Raising only the abdominal load
    (`--nochest --eab=16.12`) gives 4.43 Hz and 5.93 Hz, so the shift is
    the abdominal load's. The lung, airway and rib-cage changes only lower
    zeta from 0.150 to 0.142. The first mode therefore rests on the
    calibrated 2.015, and `--abfat=46` was my choice. The jet's 200 /min (3.33 Hz) now
    sits below the first mode, which falls at about 266 /min.
    **These modes were all run at alpha 5 /s**, before `DragForFat` was
    added, so they match `--alpha=5`. With the default drag, 46 % fat
    gets 15 /s and the 70 kg man 70 /s, so the zetas above would be much
    higher (70 kg overdamped). They were not rerun.
- `HFJVView` (`HFJVView.lpi`, `uWallAnim`/`uWallView`/`uHFJVViewForm`;
  `lazbuild --ws=gtk2`): `anim_wall.py`'s animation as a Lazarus program.
  It reads an `--anim` file (default `mesh/wall_anim_200.txt`) and draws
  the cavity in OpenGL, the wall and diaphragm pushed along their normals
  and coloured red-white-blue by displacement, rigid surfaces grey, with
  a colour bar, the front midline's profile and envelope, and the lung
  volume on `TVMPlot2D`s. Play/pause, a frame slider, exaggeration, fps
  and a mesh overlay. Compute runs `hfjvrun --anim` beside it through
  `TProcess` for the rate, pressure, I:E, cannula and abdomen in the
  second row, writing `mesh/anim_r<rate>_dp<bar>_ie<E>_c<n>[_box].txt`
  and loading it; a file that already exists is just loaded. The torso
  takes about a minute, the box a few seconds. The default view is from
  the patient's left with the head on the right, the same way round as
  the midline plot. `--compute [--box]`, `--snapshot=<prefix>` and
  `--frame=<n>` drive it from the command line. The display frame is
  (across, along, up), a mirror of the body's coordinates, so the view
  maps it back to a proper rotation, `(-along, up, across)`; shading is
  a headlamp with `|n.L|`, since the triangles' winding isn't relied on.


### `FEM4/Examples/LeftVentricle`

Added 2026-11-24 (in newVM, moved here the same day): a finite-element left ventricle with lumped valves,
stage 1 of a model whose aortic-root pressure and flow will later drive
an aorta model. Console programs, built with plain
`fpc -O3 -FUlib -Fu../../../newVM -Fi../../../newVM`. The user's design
choices: Hill-type fibres (not cross-bridge or prescribed tension), lumped
valves and blood (no fluid-structure interaction), and an ellipsoid first,
with separate mitral and aortic orifices and a 3-D elastic root as stage 2.
FEM4's own structural engine is small-strain isotropic, so only
`newVMsparse` is shared. Units: mm, kPa, s in the wall; mL, mmHg, s in the
circulation. Each unit's header has the equations.

- `uLVMech.pas` (`TLVModel`): the wall.
  - **Geometry**: truncated prolate ellipsoid, `AdultGeometry(68, 118,
    75)`: unloaded cavity 68 mL (Klotz's V0 for 125 mL at 9 mmHg), wall
    118 mL (124 g), cavity 75 mm long; wall 11.6 mm at the equator, 6.9 mm
    at the apex. Structured hexahedra (3 x 10 x 16 by default), the apical
    ring collapsed onto the axis. Each layer is scaled so its faceted
    surface encloses the ellipsoid's exact volume.
  - **Fibres**: helix +60 deg (endocardium) to -60 deg, linear.
  - **Passive**: Guccione 1991, in a frame-free form (no sheet direction),
    C fitted to Klotz (`lvrun --fitpassive`: 0.616 kPa).
  - **Incompressibility**: mean dilatation per element, Kappa 5000 kPa
    (Q1/P0 with the pressure eliminated).
  - **Active**: Kerckhoffs 2003's contractile-plus-series-elastic model,
    backward Euler (so the tangent is consistent; its one scalar
    derivative is by finite difference). Changed from that paper: ls0 2.0
    um, the twitch's timing for a human (tauR 0.10, tauD 0.07, b 0.22),
    T0 145 kPa, and **`CrossFibre` 0.4**: 40 % of the active stress also
    acts across the fibres in the wall's plane (Walker 2005, from Lin &
    Yin 1998). The Kerckhoffs values are from memory; a search didn't
    reach the paper's table.
  - **Cavity**: one pressure unknown; the volume is the exact one enclosed
    by the endocardial faces and the basal plane, and the load is
    p dV/du, so it follows the wall and is conservative.
  - **Boundary conditions**: the base slides in its plane; the endocardial
    basal ring can't move circumferentially.
  - **Solver**: Newton; elements in parallel on worker threads (taken
    four at a time from a shared counter, since this CPU has fast and
    slow cores); a map built once from each contribution to its matrix
    entry; PARDISO analysed once and refactorised
    (`TPardisoFactor.Refactor`, added to `newVMsparse.pas` for this, with
    a test: suite 330/330). A linear predictor starts each step. About
    3.2 iterations a step. A beat is 7.7 s on the mac (M4 Max) since
    newVM `bd14b27`, which stopped the Accelerate `Refactor` repeating
    the symbolic factorisation every iteration: 29.5 s before it, of
    which the solver was 25.9 s against 2.4 s now (`lvrun --beats=1
    --profile`, 2026-11-25). The 19-35 s range recorded here is from
    before that fix and was never attributed to a machine; the P620's
    MKL build reused the analysis all along, so it is unaffected.
- `uLVCirc.pas` (`TLVCirc`): pulmonary venous pressure and resistance, a
  left atrium (elastance with a sin^2 atrial systole), Mynard 2012
  valves (Bernoulli loss, inertance, an opening state; Mynard & Smolich
  2015's rates and lengths, mitral 5.1 cm2, aortic 4.0 cm2), an aortic
  root compliance, the proximal aorta's inertance and characteristic
  impedance, and a Windkessel. Backward Euler; `Trial` leaves the state
  alone so the wall's Newton iteration can call it. `(PRoot, QAo)` is the
  interface for the aorta model, which replaces the Windkessel.
  - **Aortic valve closing changed 2026-11-24** (for the Aorta model's
    dicrotic notch): `Aortic.SnapShut`, `dzeta/dt = sqrt(zeta) Kvc dp`,
    Kvc 16, instead of Mynard's `zeta Kvc dp` with 26.7. It shuts in a
    finite time, so the backflow is cut off: 2.4 mL, peak 70 mL/s,
    stopped in 10 ms (Mynard: 2.0 mL, 54 mL/s, 22 ms). The law and the
    16 are mine, chosen for a normal closing volume, not from a paper.
    `lvrun --kvc=<k>`, `--nosnap` (Mynard, 26.7). Kvc 32 with the new
    law failed ("circulation step did not converge"); 16 and 24 run.
    The beat barely changes: SV 71.8 (72.1), root 117.7/78.0 (118/78),
    dP/dt min -1232. `out/beat.csv`, `anim_default.txt` and
    `run_default.txt` are the new valve; `beat_mynard.csv` the old. The
    other `out/` runs (dt1, fine, nocross, sync, hr80) are the old valve.
- `uLVHeart.pas` (`TLVHeart`): the coupling. Each step solves the wall
  with `V(u) = V_old + dt (q_mitral - q_aortic)`, the flows being the
  circulation's response to the new pressure, so isovolumic phases need
  nothing special. A failed step is halved.
- `lvcheck.lpr`, all passing: residual against energy (the energy from
  Guccione's fibre-frame form), tangent against residual, pressure load
  against dV/du, mesh volumes, uniaxial stretch against the closed form,
  the twitch at fixed length, a thick-walled sphere against the exact
  radial integral (1.8 % at 3 x 8 x 16, 0.5 % at 6 x 16 x 32), and the
  circulation (steady jet, Windkessel decay, volume conservation).
- `lvrun.lpr`: runs beats to a steady cycle and writes the last
  (`--csv`); `plot_lv.py` draws a Wiggers diagram and the PV loop.
  `out/` has the runs below.
- `LVView` (added 2026-11-24; `LVView.lpi`, `uLVAnim`/`uLVView`/
  `uLVViewForm`; `lazbuild --ws=gtk2`), modelled on HFJVView: the wall in
  motion in OpenGL beside the P-V loop, the pressures and the valve flows
  on `TVMPlot2D`s, each with the current point.
  - **Data**: `lvrun --anim=<file>` writes the last beat: the unloaded
    mesh, the displacements and each element's mean fibre stretch and
    active stress every `--animevery` steps (2: 215 frames, 4.5 MB of
    text), and every step's samples. `TLVHeart.FrameEvery`/`Capture`/
    `WriteAnim` (the format is in `WriteAnim`'s comment);
    `TLVModel.ElemStretch`/`ElemActive` read the last assembly's sums.
    The file has no connectivity: the viewer repeats `NodeId`.
  - **View**: true size, the long axis upright, apex down. A quarter or
    half of the wall is cut away by leaving out that sector's elements (a
    half by default), so the cut turns with the twist. Coloured by
    sarcomere length, active stress (element means averaged to nodes, the
    scale fixed over the beat) or plainly. Headlamp shading per vertex,
    smooth on endocardium and epicardium, flat on the base and cuts.
  - **Playback** follows the clock: real time down to 1/20 (1/4 by
    default). All three plots are reset every frame; it still draws 166
    frames/s (`--bench`).
  - **Compute** runs `lvrun` beside it through `TProcess` for the heart
    rate, beats, T0 and any other lvrun options typed in, into
    `out/anim_hr<n>_t0<n>_b<n>[...].txt`; an existing file is just
    loaded. Progress counts the beat lines, so `lvrun` flushes after
    each. 8 beats take 3 min 47 s.
  - The plots' series are named by colour in the titles: legends covered
    the curves. The phase (a valve counts as open above 2 % opening) and
    the instant's figures are above the view.
  - `--snapshot=<prefix>`, `--time=<ms>`/`--frame`, `--colour=<0..2>`,
    `--cut=<0..2>`, `--compute`. `out/lvview_ed.png`, `lvview_es.png`.
  - FPC trap again: a local `Tag` in a form method is a duplicate
    identifier.
- **Results at 70 /min** (default mesh, 2 ms): EDV 125.5 mL, ESV 51.4,
  SV 72.1, EF 59 %, CO 5.04 L/min; LV 9.1 / 121.9 mmHg, dP/dt +1952 /
  -1223 mmHg/s; aortic root 118 / 78, mean 96; ejection 94-382 ms, peak
  487 mL/s; mean LA 7.4. Wall 9.7 -> 15.2 mm (57 %), long axis -17 %,
  sarcomere 2.22 -> 1.81 um, apical twist 15 deg. Periodic by beat 6.
  - 1 ms steps: the same to 0.1 mL. 4 x 16 x 24 elements (about 110 s a
    beat): EDV 127.6, ESV 54.4, SV 71.2, 116/77, twist 12.8.
  - **Without the cross-fibre stress** (`--cross=0`): EF 48.5 %, long axis
    -2.9 %, wall +32 %, 97/66. With it radial as well as in-plane (a first
    attempt) EF stayed near 50 % whatever T0: it resisted thickening.
  - `--sync` (no activation delay): SV 73.5, little else.
- **Things worth knowing**:
  - A line search on the residual stalled (the first step from rest has
    no forces to compare with), so Newton's step is taken whole and a
    failed load or time step is subdivided. Pressure-controlled filling
    from rest needs tiny first steps; volume control doesn't, so runs
    start with `InflateToVolume`.
  - The apex's fibre field is singular: the first ring rotates 20 deg
    under passive filling. Twist is measured a quarter of the way up.
  - EDV less ESV is 2 mL more than the forward stroke volume: the valves'
    closing backflow.
- **Left out**: right ventricle, pericardium, papillary muscles, sheet
  structure, residual stress, any real geometry. Relaxation is a little
  slow (mitral opens at 525 ms) and early filling peaks at 620 mL/s.
  Atrial and Windkessel values are typical estimates.

### `FEM4/Examples/Aorta`

Added 2026-11-24: pulse waves from the aortic valve to the common femoral
arteries and down the left arm to the wrist, driven by LeftVentricle's
aortic valve flow. Console programs, plain `fpc -O2 -FUlib` (no newVM
units). The unit headers have the equations and the vessel table.

- `uArtery1D.pas` (`TVessel`, `TArterialTree`): the **1-D** equations of
  blood flow (area A, flow Q; wall `p = P0 + beta (sqrt A - sqrt A0)`,
  P0 80 mmHg) on linear finite elements, second-order Taylor-Galerkin
  with the consistent mass matrix (one tridiagonal solve per vessel).
  1-D, not 3-D FSI, is my choice: it is the standard model for pulse
  propagation. cm-g-s inside.
  - Written about the rest state, so a tapering vessel at rest stays at
    rest to rounding.
  - `beta` is the elastance, set from the wave speed
    `c = 13.3 / d_mm^0.3` m/s (Reymond 2009, from memory). Poiseuille
    friction, `K_R = 8 pi nu`.
  - **Ends and junctions**: up to three vessel ends per junction, with
    an optional conductance to venous pressure (a branch that isn't
    modelled) and an optional inflow. Newton on total-pressure
    continuity and mass, using each vessel's outgoing characteristic in
    the form `u +- 4 (c - c0)`. The junction's state enters each vessel
    as a **boundary flux**, so volume is conserved exactly. Setting the
    end nodes directly from the characteristics, tried first, lost 3-5 %
    of the stroke volume (less on a finer mesh).
  - `TJunction.C`/`R2` make a lumped branch a three-element Windkessel
    (`Build`'s `CPeriph`: a tenth of each bed's resistance in series,
    its share of the compliance beside the rest).
- `uAortaTree.pas` (`TAortaSim`, `TLVInput`): 16 vessels, 311 elements at
  0.5 cm. Nine aortic segments, both common and external iliacs, left
  subclavian, axillary-brachial and radial. Dimensions follow
  Stergiopulos 1992 / Alastruey's tables **from memory**. Fifteen
  resistances (coronaries, brachiocephalic, left carotid, vertebral,
  intercostals, coeliac, SMA, renals, IMA, internal iliacs, ulnar, and
  the femoral and radial ends), each the total resistance (1.147
  mmHg s/mL, the LV model's Windkessel) over its share of the output
  (my estimates). `AorticStiff` multiplies beta in the aortic vessels.
  The LV's `Qaortic_mL_s` is imposed periodically: **one-way**, the
  ventricle doesn't feel the aorta.
- `aortacheck.lpr`, all passing: rest state in a taper; pulse speed
  (92.36 against 92.35 ms) and `p = Zc q`; reflection `(R-Zc)/(R+Zc)`
  (0.4999 against 0.5); bifurcation transmission and reflection (within
  0.05 %); steady friction drop; volume balance (1e-13).
- `aortarun.lpr`: `--stiff --stiffother --rtot --cperiph --beats --h
  --cfl --csv --field --sweep --tree --lv`. 12 beats take 3.3 s.
  `plot_aorta.py pulse|sweep` draws the figures in `out/`. The foot of
  the wave is by intersecting tangents on the first upstroke.
- **Results, pure resistances** (the user's specification; 70 /min,
  SV 72.1 mL), sys/dia mmHg: root 152/52, brachial 178/46, radial
  202/42, femoral 196/39; mean 97 at the root, 93 at the wrist. Foot
  reaches the wrist 105 ms after the root (7.5 m/s over 79 cm) and the
  groin after 101 ms (6.3 m/s over 63.6 cm). The pulse pressure is about
  twice normal because the modelled vessels hold only 0.52 mL/mmHg and
  resistances hold none; the fronts steepen into jumps and the
  resistances reflect strongly, so the waveforms are jagged. Halving the
  element size changes the table by under 1 mmHg, except the femoral
  diastolic minimum (39 -> 31), a sharp dip.
- **Aortic elastance x 0.5 / 1 / 2 / 4** (pure resistances): root PP
  60 / 101 / 160 / 241 mmHg, radial PP 118 / 161 / 266 / 400, speed to
  the femoral 5.0 / 6.3 / 7.9 / 9.8 m/s (transit 127 / 101 / 81 / 65 ms),
  transit to the wrist 112 / 105 / 100 / 96 ms (only 10 cm of that path
  is aorta). At x 4 diastolic pressure nears zero.
- **With `--cperiph=0.8`** (25 beats to settle): root 130/73, brachial
  146/68, radial 140/66, femoral 146/67, smooth waveforms, the same
  transit times. Sweep: root PP 36 / 57 / 75 / 88. The 0.8 and the 10 %
  series resistance are assumed.
- **Matched beds are now the default** (same day, after the user found
  the reflections excessive; `--cperiph=0` restores pure resistances).
  With pure resistances the radial end reflects about 76 % (88 against
  the vessel's 12 mmHg s/mL) and each side branch looks almost closed to
  a wave. Now every bed is a three-element Windkessel whose series
  resistance is the characteristic impedance `rho c / A` of the artery
  leading to it: for a side branch from a radius given to `AddLeak`
  (typical values from memory; the intercostals' 0.30 cm is a guess),
  for the femoral and radial ends the vessel's own. The bed's share of
  0.8 mL/mmHg (assumed) sits beside the rest of its resistance. The
  branch's inertance appears only through that impedance; there is no
  separate inertance element. Defaults: `CPeriph` 0.8, 25 beats (6.7 s).
  - **Results**: root 127/71, brachial 144/67, radial 140/65, femoral
    147/65, smooth waveforms; transits unchanged (wrist 105 ms, groin
    101 ms). Elastance x 0.5 / 1 / 2 / 4: root PP 36 / 56 / 73 / 87,
    radial PP 51 / 76 / 104 / 125. `out/pulse_matched.png`,
    `sweep_matched.png`, `run_matched.txt`.
  - These are close to the earlier 10 %-series run: for most beds 10 %
    of the resistance was already near the characteristic impedance.
  - No separate check of the Windkessel was added; the matched-end and
    reflection checks cover the resistive limit.
- **Viscoelastic wall, the default** (same day, at the user's request;
  `--walltau=0` or the viewer's "wall viscosity" 0 gives the elastic
  wall and the figures above). Kelvin-Voigt, after Alastruey 2011:
  `p = p_elastic + Gamma/(A0 sqrt A) A_t`. The one parameter is the
  retardation time `WallTau` = wall viscosity / Young's modulus
  (`Gamma = tau beta A0 / 2`), 5 ms in every vessel, **assumed**: it gives
  a wall phase lag near the measured ~0.1 rad at about 4 Hz, but a Voigt
  wall's lag grows with frequency and a real wall's hardly does. The
  viscosity is not scaled by the elastance multipliers.
  - **Scheme**: with `A_t = -Q_x` it is a diffusion of Q, diffusivity
    tau c^2, split off after each Taylor-Galerkin step as backward Euler
    with a lumped mass (`TVessel.Relax`, first order in time). A is
    untouched, so volume is still exact. No viscous flux at vessel ends;
    junctions match the elastic pressure only. `Pressure(i)` now
    includes the viscous part (one-sided at the ends), so reported
    pressure has small steps at junctions.
  - **Check 7** (`aortacheck`): an 8 Hz sine in a uniform tube against
    `k = (w/c)/sqrt(1 + i w tau)`: decay over 40 cm 0.6388 against
    0.6382, phase speed 1.0232 c0 both.
  - **Results** (tau 0 -> 5 ms): root 127/71 -> 125/71, brachial
    144/67 -> 142/68, radial 140/65 -> 138/67, femoral 147/65 -> 144/67;
    amplification at the wrist 1.36 -> 1.31. **The foot arrives
    earlier**: wrist 105 -> 88 ms, groin 101 -> 86 ms (7.4 m/s), because
    the Voigt wall carries high frequencies faster and smears the foot
    ahead of the wave; 2 ms gives 95 / 92, 10 ms 79 / 79. The root's
    pressure gains a ~7 mmHg step at valve opening (the wall resisting
    the abrupt flow upstroke). Elastance x 0.5 / 1 / 2 / 4: root PP 35 /
    55 / 73 / 87, radial PP 47 / 71 / 97 / 117, speed to the femoral
    6.2 / 7.4 / 9.0 / 10.9 m/s. `out/pulse_visc.png`, `run_visc.txt`,
    `sweep_visc.txt`, `aortaview_visc_*`.
- **Dicrotic notch** (same day; the user found none on the root's
  pressure). The ventricle's valve did have closing backflow (2.0 mL,
  54 mL/s), but Mynard's law choked it off over 22 ms and the notch was
  1 mmHg. The fix is in LeftVentricle's aortic valve (`SnapShut`, see
  there), and `beat.csv` was regenerated: backflow 2.4 mL, 70 mL/s, cut
  off in 10 ms. Root notch at 442 ms: 100.3 -> 106.6 mmHg in 8 ms, then
  settling to 102 within 6 ms. The 4 mmHg overshoot is the Voigt wall
  answering the sudden stop; with `--walltau=0` the notch is a plain
  101.0 -> 103.5. Everything else moves by 0.3 mmHg or less (root
  125/70, radial 138/66, femoral 144/67; transits 88 and 86 ms).
  `out/pulse_notch.png`, `run_notch.txt`, `sweep_notch.txt`,
  `aortaview_notch_*`. The earlier `*_visc*`, `*_matched*` and older
  outputs used the old beat, now `../LeftVentricle/out/beat_mynard.csv`.
- Static pressure steps up 3-5 mmHg along the abdominal aorta where the
  visceral branches leave: Bernoulli recovery under the total-pressure
  condition, not an error.
- `AortaView` (`AortaView.lpi`, `uAortaView`/`uAortaViewForm`;
  `lazbuild --ws=gtk2`), on LVView's pattern. Left: the tree as a front
  view in OpenGL (2-D, orthographic; wheel zooms, drag pans), each vessel
  a shaded tube on a schematic course, coloured by pressure (plasma, the
  beat's range) with its pulsation exaggerated (x 5), resistive branches
  as grey labelled stubs, rings at the four plotted sites. Right, three
  `TVMPlot2D`s: pressure against time at root, elbow, wrist and groin;
  pressure against distance along both paths at the instant shown (an
  unseen two-point series holds its scale); flows.
  - It computes in-process (`TAortaSim.Run`, 3-7 s, on the main thread)
    from the second row: aortic elastance, iliacs and arm, bed
    compliance (0.8; 0 = pure resistances), wall viscosity (5 ms),
    beats. `TAortaSim` keeps every node's pressure and
    radius ratio per 4 ms frame for it (`FrameP`, `FrameR`, `VOff`).
  - Playback on the clock, 1/10 speed by default. About 30 frames/s:
    the three plots are rebuilt each frame. The groin path is plotted
    every fourth node, since each `PlotXY` refits the bounds.
  - Labels are LCL text rendered to alpha textures. Vessels thinner than
    2.5 px are drawn at that width.
  - `--stiff --stiffother --cperiph --walltau --beats
    --snapshot=<prefix> --time=<ms> --bench`. `out/aortaview_*.png`.
  - FPC traps: a `with Vessel do` hides a local `a` behind the field
    `A`; a parameter `N` and a local `n` collide.
- Left out: the right arm and head vessels as
  vessels, gravity, two-way coupling with the ventricle.

- **Carotid, body size, carotid-femoral velocity** (2026-11-24, for
  circ_sim's age presets). The left common carotid is now a vessel
  (20.8 cm, radius 0.37, counted with the aorta for the elastance
  factor) ending in the head's bed. It was a lumped bed at the arch.
  `TAortaSim.CFPWV`/`CRPWV` are the carotid-femoral and carotid-radial
  velocities as a clinic measures them: path-length difference from the
  arch over the delay between the feet, carotid site at 0.8 of the
  vessel. `Size` scales every length and radius, `LV.Scale` the valve
  flow, and `MeanP` > 0 sets the resistance (`aortarun --size --flow
  --meanp`). At the defaults: root 124/71, carotid-femoral 6.96 m/s,
  carotid-radial 9.28 (root was 125/70 with the carotid lumped).
  aortacheck passes.

- **Forward and backward parts on the wave plot** (2026-11-25): the
  pressure-against-distance plot also draws, for the groin's path, the
  pressure's forward (blue) and backward, reflected (red) running parts.
  `TAortaSim.Run` sums dPf, dPb = (dp +- rho c du)/2 at every output
  sample of the last beat from the beat's start (`TPath.Pf`, `Pb`, each
  plus the node's pressure at the start, so P = Pf + Pb - that;
  `WMin`/`WMax` hold the plot's range). Linear and elastic-wall, so
  approximate in the upstroke, and the parts step at junctions, where
  the flow and wave speed step. What it shows (T0 65, resistance x0.6):
  the backward part is broad (17.5 mmHg at the root against 28.5
  forward), starts at each place ~25 ms after the forward front passes
  (reflection all along the taper and branches; the beds are matched),
  so it has no front returning from the periphery; the second wave seen
  starting at the root after valve closure is the dicrotic wave, a
  forward wave. circ_sim shows the cardiac output (valve flow's mean x
  "stroke volume x") in bold at the right of its settings.

### `FEM4/Examples/circ_sim`

Added 2026-11-24 at the user's request: LeftVentricle and Aorta in one
window, `circ_sim.lpi` (`lazbuild --ws=gtk2`; `uCircSimForm.pas`,
`circ_sim.lpr`). Two tabs, "Left ventricle" and "Aortic pulse", and one
Compute for both.

- **The tabs are the viewers' own forms**, `TLVViewForm` and
  `TAortaViewForm`, parented into the tab sheets (`Embed`: no border,
  their compute rows hidden, LVView's Open button hidden). The project's
  unit path reaches `..\LeftVentricle` and `..\Aorta`; nothing is
  copied. LVView and AortaView still build and work alone.
- **Settings** are two rows above the tabs: the ventricle's (heart rate,
  beats, T0, other lvrun options) and the arteries' (aortic elastance,
  iliacs and arm, bed compliance, wall viscosity, beats).
- **Compute is one coupled calculation** (2026-11-25; the one-way
  version before it ran lvrun into its Windkessel and then the tree on
  its flow). It runs `../LeftVentricle/lvrun --arteries` with every
  arterial setting through `TProcess` into `out/cs_<all settings>.txt`
  and `.csv` (two output lines a beat; 72 s for 8 beats on the mac
  since newVM `bd14b27`, about 4 min before it), loads
  the motion, then runs `TAortaSim` in-process on that csv for the
  pictures. That replay reproduces the coupled tree (root pressure
  within ~0.2 mmHg, bar one sample at valve closure). A beat already in
  `out/` for the same settings is reused; any change needs the whole
  run.
- **The coupling** (`Aorta/uAortaAfterload.pas`, `TAortaAfterload`;
  hooks `TLVCirc.Afterload` and `TLVHeart.OnStep`; lvrun now builds with
  `-Fu../Aorta`):
  - The valve's flow goes into the tree's inlet junction, whose pressure
    replaces CRoot, LAo, Zc and the Windkessel.
  - Inside a ventricle step `RootPressure(Q)` solves the tree's own inlet
    equations with the arriving characteristic frozen (extrapolated one
    step) plus the wall's viscous pressure at node 0, so the aorta's
    local impedance is implicit and reflected waves lag one 2 ms step.
  - After each accepted step `Advance` takes the tree over it in its
    explicit steps with the inflow ramped.
  - **Settling**: a ventricle beat costs ~8 s on the mac since newVM
    `bd14b27` (~27 s before it), a tree beat 0.4-1 s, and
    the beds need ~20 beats. So between ventricle beats `Settle` runs the
    tree alone on the last beat's flow (25 beats after the first, then 6;
    `--settle`). The converged beat is a periodic coupled solution; the
    beats before it are not a physical transient. Converges in 4-5 beats
    (stroke volume change < 0.05 mL); at T0 65 it oscillates and is still
    changing by 0.3 mL at beat 8.
  - **`TLVCirc.SolveRoot`**: with an afterload the root pressure is one
    monotone equation; it is bracketed and solved by bisection with
    secant steps before Trial's Newton. Plain Newton failed in beat 1
    against the stiff elderly aorta ("circulation step did not
    converge").
  - FPC's `Format` has no `%+`: it shifted the arguments silently.
  - `lvcheck` passes unchanged; lvrun without `--arteries` is as before.
- **Settings changed for it**: "mean pressure" became "peripheral
  resistance, mmHg s/mL" (`seRTot`; a mean pressure cannot be imposed
  when the flow is an outcome). "Stroke volume x" scales the valve flow
  into the tree and the ventricle feels the scaled flow's pressure - a
  stand-in for a smaller ventricle. `--t0=<kPa>` on the command line.
- **What it does not have**: no venous return or right heart (pulmonary
  venous pressure fixed at 9.9 mmHg, so preload hardly changes), no
  baroreflex (heart rate and T0 are inputs), coronary flow does not feed
  back on contractility.
- **Results** (adult preset, 70 /min; SV mL, EF %, CO L/min, root mmHg,
  LV EDP):
  - T0 145, PVR x1: 70.6, 58, 4.94, 120/71, 9.2
  - T0 145, x0.6: 77.7, 64, 5.44, 96/35, 8.8
  - T0 65, x1: 50.9, 41, 3.56, 84/51, 10.6
  - T0 65, x0.6: 62.2, 51, 4.35, 71/29, 9.9
- **Presets refitted coupled** (R, aortic x, other x -> cf, cr m/s; root;
  SV at the valve): child 1.46, 0.31, 0.39 -> 4.84, 7.21; 96/50; 76.4.
  Adult 1.147, 0.90, 1.05 -> 6.91, 9.68; 120/71; 70.6. Aged 80 1.37,
  3.92, 1.78 -> 10.87, 11.29; 139/59; 67.4. Hypertensive 1.82, 7.9, 2.6
  -> 13.95, 13.25; 162/76; 60.8. The coupled ventricle ejects less into
  a stiff aorta, so the elderly pulse pressures are no longer double.
  The one-way figures in the bullets below are superseded.
- **Start**: each tab is shown once first (a tab's GL controls have no
  context until then). With nothing in `out/` for the default settings
  it shows `../LeftVentricle/out/anim_default.txt` and `beat.csv`, which
  have those settings.
- Only the visible tab animates (`SetActive` on both forms). The two
  tabs' playback positions are independent.
- **Elderly hypertensive preset** (2026-11-25, `--preset=3`): flow 0.9, mean 120 mmHg
  (assumed), aortic x 7.6 fitted to carotid-femoral 14.0 m/s, the Collaboration's
  mean for 70+ with grade II/III hypertension. Iliacs and arm x 2.3 is chosen, not
  fitted: with it at the normotensive 1.76 the cf velocity saturates near 13.8
  however stiff the aorta (the iliacs are on the path), and scaling both factors
  together gives cr 14.4. Result: cf 14.02, cr 12.82 (no published target), root
  189/71, brachial 212/69 - pulse pressure far too wide, as in the other elderly
  preset.
- **Vascular resistance x** (2026-11-25, `sePVR`, 0.3..3, `--pvr=<x>`; `aortarun --pvr`):
  `TAortaSim.RFactor` multiplies the total peripheral resistance (RTotal, or the one
  set by MeanP), so every Windkessel bed's resistance in proportion. Each bed keeps
  its matched entry resistance and its compliance. It mimics vasoconstriction (>1)
  and vasodilatation (<1). It is not part of the age presets and they don't reset
  it. The inflow is imposed, so mean pressure follows it in proportion and the
  stroke volume does not fall. Adult preset, root / brachial / cf velocity:
  x0.6 88/32, 104/31, 6.57 m/s; x1 122/72, 137/69, 6.91; x1.5 167/121, 181/119,
  7.36 (the velocity moves because the wall stiffens with pressure).
- **Age presets** (same day, the "typical of" list; `--preset=<0..2>`):
  child of 7, adult of 40 (the start-up choice), aged 80. A preset fills
  every arterial setting; editing one switches the list to "(my own
  values)". The arterial settings now take three rows, with three new
  ones: body size x, stroke volume x, mean pressure.
  - **Targets**, foot-to-foot, m/s, carotid-femoral / carotid-radial:
    4.8 / 7.3, 6.9 / 9.7, 10.9 / 11.3. Carotid-femoral at 40 and 80 is
    from the Reference Values for Arterial Stiffness' Collaboration (Eur
    Heart J 2010;31:2338; normal values 30-39 6.5, 40-49 7.2, 70+ 10.9).
    The child's, and all carotid-radial, are Zocalo & Bia's 50th
    centiles (J Cardiovasc Dev Dis 2021;8:3; 5 y 4.6 and 7.0, 10 y 5.0
    and 7.7). Zocalo's own carotid-femoral at 40 and 80 is higher, 7.7
    and 11.3. The tables were read from Europe PMC's full-text XML
    (`.../europepmc/webservices/rest/PMC2948201/fullTextXML`,
    `PMC7827252`); PMC itself blocks fetches.
  - **Fitted**: the two elastance factors, by running `aortarun` on the
    default beat and scaling each by (target/model)^2 until both
    velocities matched: 0.31 / 0.39, 0.91 / 1.07, 3.77 / 1.76. The model
    gives 4.82 / 7.31, 6.91 / 9.70, 10.88 / 11.31.
  - **Assumed** (round typical values, mine): body size 0.70 for the
    child; stroke volume x 0.55 and 0.9 (child, 80); mean pressure 72
    and 98; bed compliance 0.4, 0.8, 0.6; wall viscosity 5 ms for all.
  - **Pressures that result**, root and brachial: child 92/51 and
    101/50; adult 122/72 and 137/69; aged 80 152/57 and 175/54. The
    last pulse pressure is about twice a typical one: the aorta is
    stiffened but not widened, and the ventricle's flow is the adult's
    (one-way coupling).
  - The fit is for 70 /min. The ventricle is the adult's in all three.
- `--compute`, `--hr=<n>`, `--lvbeats=<n>`, `--tab=<0|1>`,
  `--snapshot=<prefix>` (both tabs' pictures and the window per tab).
  Checked with `--compute --hr=80 --lvbeats=2` (78 s) and by snapshot.

### `FEM4/Examples/Asthma`

Started 2026-11-26. The aim: finite elements for one alveolus and one
bronchiole (compliance, resistance, Starling-resistor collapse under
raised pleural pressure), then a lung and chest wall summing many such
units, to give peak flow, pleural pressure, end-expiratory lung volume
and work of breathing over the cycle, in normal people and asthma.
**Stage 1, the single unit, and stage 2, the symmetric lung and chest
wall, are done; stage 3, a heterogeneous (patchy) lung, is next.**
Console programs,
plain `fpc -O3 -FUlib -Fu../../../newVM -Fi../../../newVM`. Units mm,
kPa, s inside; cmH2O in the output. Each unit's header has the
equations.

The user's choices (asked 2026-11-26): the asthma mechanisms are smooth
muscle tone, wall thickening, mucus and oedema, and patchy distribution.
Two questions went unanswered and the recommended options were taken:
a ring FE of the wall's cross-section feeding a 1-D flow model (not a
3-D shell, not a published tube law), and a symmetric Weibel tree first,
then a heterogeneous tree of many units on OpenCL.

- `uAirwayRing.pas` (`TAirwayRing`): the bronchiole wall in cross-section,
  plane strain, finite strain. Its result is the tube law.
  - **Mesh**: concentric layers (mucosa, submucosa, muscle, adventitia);
    half of one fold, the sector 0..pi/Lobes, with symmetry lines.
    9-node quadrilaterals with a discontinuous linear pressure,
    eliminated (bending and incompressibility both need it: Q1/P0 locks
    in the thin stiff mucosa).
  - **Material**: `Mu/(2b)(exp(b(I1-3))-1) - Mu ln J` per layer. Neo-Hookean
    alone has a pressure ceiling (`Mu t/R`), past which the tube inflates
    without limit.
  - **Muscle**: circumferential, isometric force-length only,
    `Act T0 (1 - ((lambda-1)/(1-LMin))^2)`, so it has an energy.
  - **Load**: `Ptm dA/du`, A the exact area inside the quadratic inner
    edges. Pressure or area control; area control passes through
    buckling.
  - **Tethering**: outward traction `TetherK (TetherR - r)` on the outer
    surface, from Lai-Fook's `2 mu dD/D`, `mu = 0.7 Ptp` (`SetTether`).
  - **Contact**: penalty on inner nodes that cross a symmetry line.
  - **Solver**: its own banded `L D L'` without pivoting (everything has
    an energy, so the tangent is symmetric). The negative pivots count
    negative eigenvalues, and **an equilibrium that is not stable is
    refused**. This matters: before it, a 2 % area step past buckling
    landed on the unfolded, uniformly compressed state (still a
    solution) and the thin ring "collapsed" at a thousand times the
    right pressure. `MoveTo` halves the step after a failure and doubles
    it after a success; a fixed-depth bisection couldn't get past a
    bifurcation.
  - **Folds**: `BestLobes` picks the fold number of least strain energy
    at one area (half the unloaded one). The real wall can change mode
    as it collapses; this can't. With these walls 2 or 3 folds win
    (whole-wall collapse), not the 20 of mucosal folding: at 60 % area
    with tone the energies of 2 and 20 folds differ by 1 %.
  - `NormalBronchiole`/`AsthmaBronchiole`: **layer thicknesses and
    moduli are assumed** (orders of magnitude, after Wiggs 1997 and
    Hrousis & Kamm 2002), `T0` 100 kPa. Thickening adds wall outwards,
    the lumen's unloaded radius kept.
- `uTubeLaw.pas`: the law as a table with monotone cubic interpolation
  (continuous slope, for the wave speed), and the liquid lining:
  `AWall = Law(Ptm - Gamma/a)`, closed if there is no root or the film is
  over 12 % of the radius (Gauglitz & Radke). Reopening isn't modelled.
- `uBronchiole.pas` (`TBronchiole`): steady 1-D flow, Lambert 1982's
  `dP/dx = -f/(1 - S^2)` with Reynolds' loss (1.5 + 0.0035 Re). `Flow`
  bisects on the flow; the largest flow that reaches the airway's end is
  the limit.
- `uAlveolus.pas` (`TAlveolus`): an axisymmetric membrane cap with a
  mouth ring, Fung tissue, and a surfactant film whose tension depends
  on its area (fixed deflation and inflation limbs, assumed shapes).
  Dense Newton with newVM's `LinearSolve` (the film's term is a full
  rank-one matrix). **It is a lone balloon**: real septa have gas on
  both sides.
- `asthmacheck.lpr`, all passing (1 s): residual against energy and
  tangent against residual for wall and alveolus; mesh area and volume;
  a thick stiffening tethered tube against the exact radial integral;
  isometric muscle against `m Act T0 ln(Ro/Ri)`; thin-ring buckling into
  2 and 3 folds against `(n^2-1) E'I/Rm^3` (0.2 %, 0.02 %); first wall
  contact against the elastica's 5.247 and 0.27 (1.7 %, 2.2 % early: the
  inner surfaces meet before the centre lines); the sphere against
  `2(T+gamma)/r`; table interpolation; Poiseuille; a compliant tube's
  closed form; the wave-speed limit; flow independent of downstream
  pressure; the lining.
  - The buckling formula uses the mean radius cubed. `Rm^2 Ri` was 2 %
    out: suction inside and pressure outside differ by a hydrostatic
    stress, so the first-order thickness correction must vanish.
  - The thick tube's uniform state at half its area is unstable (it
    wrinkles), so that check stops at 0.8.
  - Volumetric stiffness 1000 `Mu` leaves 0.7 % error in a hard
    compression; the checks use 20000.
- `asthmarun.lpr` (3 min, nearly all in `BestLobes`; `--lobes=<n>` skips
  it): tube laws, alveolar P-V, and the unit's isovolume pressure-flow
  curve, to `out/*.csv`; `plot_asthma.py` draws `out/unit.png`. Options
  `--ri`, `--length`, `--act`, `--thick`, `--mucus`, `--out`.
- **Results** (unloaded lumen radius 0.25 mm, tethered at Ptp 5 cmH2O,
  asthma = activation 0.3, wall x 1.5, lining x 3):
  - Lumen area over the unloaded normal area at Ptm -5 / 0 / +5 / +30
    cmH2O: normal 0.41 / 1.03 / 1.27 / 1.93; tone 0.09 / 0.77 / 0.89 /
    1.84; thick 0.34 / 1.00 / 1.16 / 1.77; both 0.53 / 0.67 / 0.73 /
    1.48. All collapse between -3 and -10. "Both" stopped converging at
    0.40 of the area, so below that its law is the table's exponential
    tail.
  - Resistance of 30 000 such bronchioles in parallel at rest: 0.0075
    cmH2O s/L normal, 0.016 tone, 0.0089 thick, 0.023 both, 0.030 with
    mucus: four-fold, and still small, as the peripheral airways are.
  - Starling behaviour: with recoil 5 and the far end at 0, flow stops
    rising once pleural pressure passes about +2 cmH2O: 5074 mm3/s
    normal (at the wave speed, 22 m/s), 3784 tone, 3425 both, 2791 with
    mucus. That is 150 L/s for 30 000, far above any real flow: one
    terminal bronchiole with the whole recoil across it is a test of the
    mechanism, not a prediction. The lung's limit will come from the
    tree.
  - Alveolus (R 0.1 mm at FRC): deflation limb 6.2 cmH2O at FRC, 30.2 at
    twice the volume; inflation 10.1 and 30.2; 480 million hold 1.84 L
    with compliance 0.13 L/cmH2O.
- **Open after stage 1** (the first two fixed in stage 2):
  - The balloon under-represented surface forces: saline-filled it was
    26.5 cmH2O at capacity against 30 air-filled, where a real lung
    loses about two thirds of its recoil. Stage 2 fits it instead
    (`FitAlveolus`).
  - Wall properties weren't fitted to anything. Stage 2 fits the
    cartilaginous generations to Lambert.
  - Muscle has no force-velocity or fluidisation; the lining can't
    reopen; a collapsed lumen's extra viscous loss is left out.
  - FPC traps hit: a local `fr` beside the field `FR`, and `Rm` beside
    `rm`, are duplicate identifiers.

#### Stage 2: the lung and chest wall (2026-11-26)

- `uLungModel.pas` (`TLung`, `TLungSim`; header has every equation):
  - **Tree**: Weibel's symmetric generations 0-16, 2^g airways each,
    lengths Weibel's. Lumen at full dilation Lambert's (as tabulated by
    Florens et al., arXiv 2011.09740, table 1), put at the normal wall's
    area at Ptm 40 cmH2O. The wall's law is scale-free (thicknesses go
    with the radius), so one FE law serves every generation with the
    same wall type, scaled.
  - **Wall types** (`WallM`, modulus scales): generations 0-1 fitted to
    Lambert's FRC/full area ratio 0.888 (x13.94), generation 2 to 0.711
    (x3.886), `lungrun --fitwall`; 3-16 the stage-1 membranous wall
    (0.62). **Lambert's small airways can't be matched**: his ratio falls
    to 0.15 by generation 16, and no wall here gets below about 0.22
    (the scan over modulus and stiffening is in the session notes, not
    the repo). Pinning our lumen at Lambert's FRC size instead made
    every flow far too small (PEF 6 L/s, FEV1/FVC 58 % for a normal
    lung), so the lumen is pinned at full dilation, which Lambert and
    Weibel agree on.
  - **Lining** on every generation: a film of 5 um (`Film`, times
    `Mucus` in asthma) on the lumen at FRC; the gas area and the
    pressure below which it closes (`PClose`) are tabulated per
    generation at construction.
  - **Flow**: quasi-steady, the stage-1 equation per generation with the
    pleural pressure outside, junctions losing the speed-up (none
    recovered), Rohrer upper airway (K1 0.3, K2 0.05). `Flow` brackets
    and uses Illinois regula falsi, bisection when the upper end chokes;
    a choke anywhere is flow limitation and `ChokeGen` says where.
    Closed at zero flow returns 0 at once (it once made a closed-airway
    run take over ten minutes).
  - **Recoil** from `FitAlveolus(30, 10 cmH2O, r 0.126 mm)`: the tissue
    constant so the saline-filled alveolus holds 10 cmH2O at TLC, then a
    surface factor (x4.8 on the film's tension) so the air-filled one
    holds 30. The factor stands in for the septa's and ducts' surface,
    which a lone sphere lacks. Scaled so the alveoli hold TLC - dead
    space (6.5 - 0.15 L).
  - **Chest wall**: relaxed at 4.1 L, 0.2 L/cmH2O in its middle,
    stiffening exponentially below 1.7 L and above 7 L (assumed; the low
    end sets RV near 1.5 L under full expiratory effort).
  - `TLungSim`: Heun's method on volume; Ppl = Pcw - Pmus, Palv = Ppl +
    Pel; each state's flow solved for.
  - `BuildWallLaws` builds the three wall types' tube laws in threads
    (about 3 s); `WallRing` applies the asthma.
- `lungcheck.lpr`, all passing (7 s): a near-rigid tree's resistance
  against the Poiseuille sum (1e-4, at 1e-5 cmH2O: at 1e-3 the
  junctions' quadratic speed-up losses add 1 %); the fitted alveolus
  (30 and 10 cmH2O at TLC); passive emptying against exp(-t/RC) (3e-4,
  from 5 uL above FRC, again to stay linear); the flow solver inverting
  the expiratory and inspiratory marches; isovolume flow independent of
  pleural pressure once limited.
- `lungrun.lpr` (80 s for the four cases): for each, FRC, resistance,
  where the linings close; forced expiration from TLC (effort 40-160
  cmH2O by volume, 30 ms rise): PEF, FEV1, FVC, RV, MEF50 at full and
  60 % effort, choke generation; tidal breathing at rest (15 /min,
  500 mL) and fast (30 /min, 600 mL), I:E 1:2, Pmus a half sine then
  post-inspiratory decay, peak Pmus adjusted until the breath repeats:
  EELV against FRC, intrinsic PEEP, pleural pressures, peak flows,
  fraction of expiration flow-limited, inspiratory work split elastic /
  resistive. `--act/--thick/--mucus` add a custom case, `--only=<name>`,
  `--dt`, `--fitwall`. CSVs to `out/`; `plot_lung.py` draws
  `out/lung.png`.
- **Results**. Asthma grades are assumed: mild activation 0.15, wall
  x1.25; moderate 0.3, x1.5, lining x1.5; severe 0.5, x1.75, lining x2.

  | | normal | mild | moderate | severe |
  |---|---|---|---|---|
  | Raw at FRC, cmH2O s/L | 0.68 | 0.94 | 1.43 | 2.23 |
  | PEF, L/s | 8.06 | 7.48 | 5.95 | 3.87 |
  | FEV1, L | 4.55 | 4.15 | 3.55 | 2.94 |
  | FEV1/FVC | 91 % | 83 % | 71 % | 59 % |
  | MEF50, L/s | 5.22 | 4.12 | 3.04 | 2.46 |
  | fast breathing: peak Pmus, cmH2O | 6.8 | 7.1 | 8.1 | 10.3 |
  | fast: lowest Ppl, cmH2O | -9.3 | -9.7 | -10.8 | -13.0 |
  | fast: EELV above FRC, mL | 0 | 0 | 2 | 21 |
  | fast: work, J/min (resistive J/breath) | 7.8 (0.07) | 8.5 (0.10) | 10.2 (0.15) | 13.5 (0.25) |

  At rest: FRC 3.01 L everywhere, Ptp there 5.4 cmH2O, work 0.30 J/L
  normal (0.39 severe), no flow limitation and no intrinsic PEEP in any
  grade. FVC is 5.02 L and RV 1.48 L in all four: RV is set by the chest
  wall. MEF50 at 60 % effort is within 3 % of full effort: the forced
  flows are limited, choking in generations 0-2 (the trachea and main
  bronchi, wave speed), as Lambert found.
- **What it shows, and doesn't**:
  - Up to "severe" the asthma is an obstructive spirometry pattern with
    the work and pleural swings it costs, but **no dynamic hyperinflation
    or tidal flow limitation**: tidal flows stay well under the maximal
    flows, because a symmetric tree narrows everywhere at once and its
    central airways still limit. Real hyperinflation in asthma needs
    either far more obstruction or the heterogeneity of stage 3 (some
    units nearly shut, with long time constants, while others carry
    the flow).
  - FVC and RV don't change with these grades, against the gas
    trapping of real asthma: RV is the chest wall's here, unless the
    linings close first (the extreme case below).
  - The normal FEV1/FVC (91 %) is high and its MEFV curve straight;
    Lambert's more distensible small airways would lower and scoop it.
  - The chest wall, upper airway, effort curve and asthma grades are
    assumed round values.
  - Expiration is quasi-steady: no gas inertance or compressibility, so
    the PEF transient is not modelled.
- **An extreme case** (`--act=0.7 --thick=2 --mucus=2`, 20 s): the
  linings now close generations 15 and 16 at positive transmural
  pressure (+1.5 and +13 cmH2O), so at FRC the small airways are shut
  and airway resistance is infinite. Forced expiration stops at 2.26 L
  exhaled, RV 4.24 L (FEV1 2.24 L, PEF 2.7 L/s). Breathing settles at
  EELV 4.24 L, 1.2 L above FRC, with intrinsic PEEP 13.7 cmH2O, pleural
  pressure +0.7 at end expiration and -20 (rest) to -28 (fast) at its
  lowest, about 40 % of expiration flow-limited, and inspiratory work
  15 J/min at rest and 47 fast (normal 2.3 and 7.8). EELV equals that
  RV: **the hyperinflation is closure trapping** (expiration stops when
  the linings shut, and inspiration must first lift the trapped
  pressure), not a time constant too long for the breath. With no
  closure hysteresis the airways reopen as soon as Ptm passes `PClose`.
- **The tidal controller** brackets Pmax and uses the secant inside the
  bracket. A plain `Pmax (VT target / VT)^0.8` update oscillated
  between 205 and 1217 mL in the extreme case, where VT is very steep in
  Pmax once the trapped pressure is overcome. The bracket is reset every
  10 breaths in case EELV is still moving; 60 cmH2O is the muscles' cap,
  and `--verbose` prints every breath.

#### Stage 3: the patchy lung (2026-11-26)

`uPatchyLung.pas` (its header has the model), `patchyrun.lpr`,
`patchycheck.lpr`, `plot_patchy.py` (`out/patchy.png`: severity and
ventilation maps). Same build line.

- **Model**. The stage-2 tree, split at generation K (default 8) into
  2^K = 256 units, each a symmetric subtree of generations K..16 with its
  own severity s, height in the chest and alveolar volume. The trunk
  (generations 0..K-1) is the case's asthma at s = 1 and is shared:
  asthma's patchiness is peripheral (Venegas, Nature 2005). A unit's
  asthma is s times the case's (activation s A.Act, thickening and lining
  1 + s (x - 1)). s is log-normal, mean 1, built as a cascade down the
  tree: one normal draw per airway of generations 1..K, summed along a
  unit's path, so units sharing more of their path are more alike and
  severe units come in patches. s is rounded to steps of 0.25 (one set of
  FE tube laws per step, capped at 3).
- **Layout and gravity**. The first branching splits the chest left and
  right, the next top and bottom, alternately: K = 8 is a 16 x 16 grid
  in a 30 x 24 cm frontal section. Upright, the pleural pressure rises
  0.2 cmH2O per cm down (`--gravity`), so lower units start smaller and
  ventilate more.
- **Unit tables**. In a symmetric subtree only transmural pressures
  matter, so each severity level's expiratory and inspiratory marches
  are tabulated once (`TUnitTable`): the drop against flow as a fraction
  of the subtree's largest flow (choke or lining closure), every
  0.5 cmH2O from -40 to +80, on 41 flow points crowded towards the
  choke. Inverted linearly. Tables are built in parallel, one thread per
  level.
- **Solve**. The pressure at the trunk's lower end is the one unknown:
  each unit's flow follows from it and its alveolar pressure, and their
  sum must run up (or down) the trunk to 0 at the mouth. Illinois regula
  falsi, bisecting when the trunk chokes. Units may flow in opposite
  directions (pendelluft). Heun's method on all unit volumes.
- **Tube-law cache**. `uLungModel.BuildLaws` now builds any set of rings
  (16 threads at a time) and keeps each law in `cache/` (gitignored),
  keyed on every ring parameter (FNV-1a of the key, which is also the
  file's first line). A run that has built its laws once starts in
  seconds. Delete `cache/` after changing the ring FE. `BuildWallLaws`
  goes through it too.
- **Other `uLungModel` changes**. The expiratory and inspiratory
  marches are `MarchUp`/`MarchDown` between any two generations
  (`MouthPressure`/`AlveolarEnd` call them over the whole tree, with
  unchanged results). `TLung.CreateAirways` builds the airways without
  the recoil table. A generation its lining closes at every pressure is
  now `PClose = +Infinity` (it carries no flow) rather than an
  exception.
- **Checks** (`patchycheck`, about 5 s once the laws are cached):
  - with s = 1 everywhere and no gravity, the patchy lung's flow equals
    the symmetric lung's (the whole tree marched directly) to 0.2 % at
    six states, tidal and forced, two of them flow-limited (moderate
    asthma, so the linings matter);
  - the static state with gravity: each unit's recoil holds its own
    pleural pressure, the chest wall balances, upper units are bigger
    (12.0 against 10.2 mL);
  - patchy: unit flows sum to the mouth flow (one unit filling while
    another empties at zero mouth pressure gradient).
- **Results** (`patchyrun`, 2 min for six cases; seed 1, gravity 0.2;
  `out/patchyrun.txt`). The patchy cases have the same mean severity as
  the uniform ones. Fast breathing is 30 /min, 600 mL. A ventilation
  defect is a unit below half the mean specific ventilation (my
  threshold):

  | | normal | moderate | moderate, sigma 0.5 | moderate, sigma 1 | severe | severe, sigma 0.5 |
  |---|---|---|---|---|---|---|
  | PEF (L/s) | 7.98 | 5.85 | 5.90 | 5.95 | 3.83 | 4.12 |
  | FEV1/FVC | 91 % | 71 % | 71 % | 71 % | 59 % | 58 % |
  | units shut at FRC | 0 | 0 | 10 | 13 | 0 | 51 |
  | fast: EELV above FRC (mL) | 0 | 3 | 4 | 3 | 24 | 11 |
  | fast: work (J/min) | 7.8 | 10.2 | 10.1 | 9.9 | 13.5 | 13.5 |
  | fast: CV of specific ventilation | 0.17 | 0.14 | 0.23 | 0.29 | 0.12 | 0.52 |
  | fast: defects, % of lung volume | 0 | 0 | 2 | 5 | 0 | 19 |

  The normal lung's 0.17 CV is gravity alone; obstruction slightly
  evens it out (the stiffer airways set the distribution, not the
  dependent units' compliance).
- **What patchiness does here, and doesn't**:
  - Spirometry, work and EELV barely move from the uniform lung at the
    same mean severity, since the shared trunk sets most of them.
  - It makes **ventilation defects**: 19 % of the lung at severe,
    sigma 0.5, in clusters (the cascade), like the defects of
    hyperpolarised-gas MRI and PET in asthma.
  - It still makes **no dynamic hyperinflation**. The units are binary:
    the severities that would give a long time constant are beyond the
    lining's closure, so a unit is either near-normal or shut for the
    whole breath. The shut units sit at their static FRC volume, with no
    gas absorption; the real ones would be trapped at whatever volume
    they shut at and then absorb.
  - Getting time-constant hyperinflation would need a severity range
    that narrows the airways without closing them (more muscle, less
    mucus), closure with hysteresis (shut on expiration at a higher
    volume than they reopen), or Venegas's mechanism, where narrowing
    is self-reinforcing through the parenchymal tethering a poorly
    ventilated unit loses.
- Options: `--k`, `--seed`, `--gravity`, `--sigma` with `--act/--thick/
  --mucus` for a custom case, `--only`, `--dt`, `--verbose`, `--out`.
  Files: `out/patchy_<case>_units.csv` (one row per unit, with its
  place, severity, volumes and ventilation), `_fv.csv`, `_rest.csv`,
  `_fast.csv`.

#### Stage 4: airway tone that answers to stretch (2026-11-26)

`tonerun.lpr` (its header has the model), `plot_tone.py`
(`out/tone.png`), check 4 in `patchycheck`. `uPatchyLung` gained
`ActMode`. Its levels are then muscle activations 0, 0.05, .. 0.9, every
unit has the case's thickening and lining, all levels are built, and a
unit's `Level` may change between steps.

- **Model** (Venegas et al., Nature 2005, built on Fredberg's perturbed
  equilibrium: smooth muscle stretched every breath develops less force
  than muscle held still). After every breath each unit's activation
  relaxes (time constant 20 s) towards
  `Act0 Sev_u (1 - Fmax e^2/(e^2 + e50^2))`, e being the unit's tidal
  volume strain, which stands for its airways' stretch through
  tethering. Fmax 0.75 and e50 0.1 are assumed; a normal unit's e in
  fast breathing is about 0.2. Sev_u is a clustered spread of sigma
  0.1, and gravity is as in stage 3. A poorly ventilated unit stretches
  less, contracts more and narrows further. The protocol is fast
  breathing (30 /min, drive adjusted towards 600 mL), with dose Act0
  either raised 0.3 .. 0.9 over 40 breaths each (gradual) or given as
  0.9 at once (sudden). The feedback is on, or off (Fmax 0: tone
  ignores stretch).
- **What the FE wall allows** (found while building this): muscle
  alone narrows the membranous airways only to about 0.3 of their full
  area, because the folded mucosa fills the lumen (Wiggs and Lambert's
  folding limit). At full activation the units' conductance is about a
  quarter of normal and nothing closes with a normal wall and lining.
  With the severe wall (x 1.75) and lining (x 2), the lining closes the
  airways from about activation 0.65. Because the floor lies almost at
  the lining's closing area, the closing pressure jumps between
  neighbouring levels (0.75 shuts at +8 cmH2O, 0.8 at +4).
- **Results** (fast breathing, last breath of the final dose):

  | | EELV above FRC (mL) | PEEPi (cmH2O) | work (J/min) | defects (% of lung) | units shut / trapped | mean activation |
  |---|---|---|---|---|---|---|
  | moderate, off, gradual | 17 | 0.2 | 12.0 | 0 | 0 / 0 | 0.87 |
  | moderate, on, gradual | 3 | 0 | 10.3 | 0 | 0 / 0 | 0.34 |
  | severe, off, gradual | 545 | 6.3 | 24.2 | 34 | 0 / 169 | 0.87 |
  | severe, on, gradual | 7 | 0.1 | 11.2 | 0 | 0 / 0 | 0.34 |
  | severe, off, sudden | 565 | 6.5 | 28.8 | 35 | 0 / 173 | 0.88 |
  | severe, on, sudden | 41 | 0.4 | 16.3 | 22 | 59 / 9 | 0.45 |
  | severe, on, sudden, deep breaths | 108 | 1.3 | 16.0 | 20 | 32 / 44 | 0.42 |

  "Trapped" means end-expiratory volume more than 10 % above its FRC
  volume; normal fast breathing costs 7.8 J/min.
- **What it shows**:
  - **Dynamic hyperinflation at last**, and the kind a time constant
    gives rather than closure trapping: with tone that ignores stretch,
    the severe wall at activation 0.9 holds end expiration 545 mL above
    FRC with intrinsic PEEP 6.3 cmH2O. Two thirds of the units are
    trapped and none is shut all breath, and the work is three times
    normal. In stages 2 and 3 only closure produced this.
  - **Stretch-responsive muscle protects**: with the feedback on, tidal
    breathing holds activation at about 0.4 of the dose and a gradual
    challenge never closes anything. This is the bronchoprotection of
    breathing that Fredberg argued asthmatic muscle loses, so "off" can
    be read as the asthmatic muscle and "on" as the normal one.
  - **Bistability, so history matters**: a sudden full dose shuts 59
    units before stretch can act. A shut unit gets no stretch and stays
    shut, while the rest relax, leaving 22 % of the lung as clustered
    defects that are stable for 120 breaths. The same dose given
    gradually gives none. The shut units gather in the dependent lung.
  - **Deep breaths** (one per 40 breaths, 30 cmH2O, about 1.2 L)
    reopen every unit, and about half stay open (59 to 32 shut). The
    ones that close again shut on the deep breath's gas, so trapping
    rises (EELV +41 to +108 mL).
- **Limits**: one feedback law with assumed constants; stretch taken
  from the unit's volume strain, not the airway's own; activation
  quantised to 0.05; the folding floor caps narrowing; the trunk's tone
  is fixed at the case's 0.3.
- **Checks**: `patchycheck` 4: in activation mode with no spread or
  gravity, the patchy lung's flow equals the symmetric lung's (0.2 %).
  Moving half the units to 0.9 lowers their flow and raises the others'.
- Options: `--doses=<a,b,..>`, `--breaths=<per dose>` (40), `--sigh`
  (`--sighp`), `--fmax`, `--e50`, `--tau`, `--sigma`, `--seed`, `--rest`,
  `--only`, `--tag`, `--dt`, `--out`. Files: `out/tone_<run><tag>.csv`
  (one row per breath), `_units.csv` (each unit at the end of every
  dose). The seven runs above take about 7 minutes.

#### Stage 5: the ventilated asthmatic (2026-11-26)

`ventrun.lpr` (its header has the protocol), `plot_vent.py`
(`out/vent.png`), check 5 in `patchycheck`. This is the paralysed
patient with severe asthma on a ventilator, after Tuxen and Lane (Am
Rev Respir Dis 1987).

- **`uPatchyLung` changes**:
  - `Pao`: the airway opening pressure that `Solve` works to (0 when
    breathing).
  - `SolveFlow(V, Ppl, Q)`: the airway opening pressure at which the
    mouth flow is Q. It bisects on the trunk's lower-end pressure for
    the units' summed flow, then inverts the trunk march.
  - `TPatchySim.Mode`: `smPressure` (Paw held) or `smFlow` (QSet held,
    Paw follows; QSet 0 is an occlusion).
- **Setup**: 256 units, gravity, no muscle pressure, so the pleural
  pressure is the chest wall's recoil. An endotracheal tube replaces
  the upper airway (Rohrer K1 1, K2 4, about 5 cmH2O at 1 L/s, assumed
  for an 8 mm tube). Volume control, square wave at 60 L/min.
- **Measurement**: each setting starts relaxed at its PEEP and runs to
  steady end-expiratory volume (at most 60 breaths). Then:
  - peak pressure;
  - plateau after a 0.5 s end-inspiratory hold;
  - total PEEP after a 2 s end-expiratory hold;
  - VEI as Tuxen measured it: the volume exhaled in a 30 s apnoea from
    end-inspiration, plus the volume still left above the relaxed FRC
    after it.
- **Lungs**:
  - normal;
  - status asthmaticus: tone 0.8 in units and trunk, tone ignoring
    stretch (stage 4's asthmatic muscle), wall x 3 (the thickening of
    fatal asthma, James et al. 1989), normal lining;
  - the same with lining x 1.5 (`--name=asthma_mucus --mucus=1.5`).
- **Why wall x 3**: with stage 4's severe wall (x 1.75, lining x 2) at
  tone 0.8 the ventilated peak was only 18 cmH2O. That is the mucosal
  folding floor again: at x 1.75 the lumen at full tone stops at 0.28
  of its full area, while a thicker wall folds into fewer, larger
  folds and narrows further (Wiggs), to 0.13 at x 3.25. Wall x 3 gives
  peaks of 32-37 cmH2O at 60 L/min, an airway resistance of about
  20 cmH2O s/L, in the range of ventilated status asthmaticus.
- **Results**, 500 mL breaths unless stated; EEV is end-expiratory gas
  above the relaxed FRC:

  | lung | setting | VE | Ppeak | Pplat | PEEPi (hold) | EEV (mL) | VEI (mL) | VEI by apnoea | left after apnoea |
  |---|---|---|---|---|---|---|---|---|---|
  | normal | 8-24 /min | 4-12 | 11.2 | 5.3 | 0 | 0 | 500 | 500 | 0 |
  | normal | 1 L at 10 /min | 10 | 16.7 | 11.0 | 0 | 0 | 1000 | 1000 | 0 |
  | asthma | 8 /min | 4 | 31.8 | 10.7 | 0.2 | 523 | 1022 | 501 | 513 |
  | asthma | 16 /min | 8 | 32.1 | 11.2 | 1.0 | 573 | 1069 | 512 | 523 |
  | asthma | 24 /min | 12 | 32.7 | 12.2 | 2.6 | 656 | 1150 | 539 | 541 |
  | asthma | 1 L at 10 /min | 10 | 36.6 | 18.2 | 0.7 | 634 | 1634 | 1006 | 594 |
  | asthma | 16 /min, PEEP 5 | 8 | 33.8 | 13.9 | 0.4 | 802 | 1301 | 706 | 581 |
  | asthma | 16 /min, PEEP 10 | 8 | 36.1 | 17.4 | 0.3 | 1067 | 1566 | 957 | 593 |

  The lining x 1.5 lung shuts every unit at FRC. Ventilation pumps it
  up to 2.1 L above FRC (VEI 2.6 L), where the linings stay open, with
  peak 52, plateau 35.6 and total PEEP 15.9 cmH2O identical from 4 to
  12 L/min. A 1 L tidal volume gives VEI 3.4 L and plateau 43. Applied
  PEEP 5 and 10 lowers the measured intrinsic PEEP to 11.5 and 7.0 but
  adds 120 and 220 mL. Every setting reached the 60-breath cap still
  creeping by a fraction of a mL a breath.
- **What it shows**:
  - **Tuxen's direction is reproduced**: more minute ventilation (a
    shorter expiration) raises trapped gas, VEI, plateau and intrinsic
    PEEP. A larger tidal volume raises VEI and plateau most.
  - **The size of the effect is smaller than his**: trapped gas rises
    only 130 mL from 4 to 12 L/min. Most of the trapping is airway
    closure: 202 of 256 units are shut at FRC.
  - **Hidden auto-PEEP**: 500-650 mL of gas is trapped behind shut
    airways, yet the end-expiratory hold reads 0.2-2.6 cmH2O, because
    the shut units don't communicate with the airway opening
    (Leatherman and Ravenscraft, Crit Care Med 1996). The apnoea
    likewise leaves half a litre behind, so Tuxen's apnoea measure
    under-reads VEI by that much.
  - **Extrinsic PEEP**: 5 and 10 cmH2O lower the measured intrinsic
    PEEP a little but add their own volume (EEV +230 and +490 mL, VEI
    1.30 and 1.57 L at 8 L/min), as Tuxen found for PEEP in asthma.
  - With more lining (x 1.5) the closure is total and the
    hyperinflation is set by the linings' closing volume, not by the
    ventilator.
- **Limits**: no closure hysteresis, so a unit reopens as soon as its
  transmural pressure passes `PClose`; no gas absorption behind shut
  airways; the tube coefficients and tone are assumed; supine posture
  and the lower FRC of anaesthesia aren't modelled (the upright
  gravity gradient is kept); quasi-steady flow.
- **Checks**: `patchycheck` 5.
  - The airway opening pressure from `SolveFlow`, fed back to `Solve`,
    returns the set flow, in and out (1e-8).
  - In the normal lung with gravity, the plateau after 500 mL and a
    3 s hold equals the static pressure for that volume from
    `StaticState` (1e-9).
- Options: `--only`, `--dose`, `--thick`, `--mucus`, `--name`, `--flow`,
  `--k`, `--seed`, `--dt`, `--quick`, `--out`. Files: `out/vent_<lung>.csv`
  (a row per setting) and `out/vent_<lung>_<n>.csv` (the measured
  breath, holds and apnoea). About 15 minutes for all three lungs.

#### Stage 6: closure hysteresis and absorption atelectasis (2026-11-26)

`absorbrun.lpr` (its header has the model), `plot_absorb.py`
(`out/absorb.png`), check 6 in `patchycheck`.

- **Hysteresis** (`uPatchyLung`): `TUnitTable.PReopen` is 2 gamma / r
  for the airway that closes first, r its gas radius just above
  `PClose`: the pressure to push the liquid bridge back out (about
  6 cmH2O in the status asthmaticus lung). With `Hysteresis` > 0 a unit
  whose flow has stopped at a closing pressure is `Shut` and carries
  nothing until the transmural pressure at either end reaches
  `PClose + Hysteresis * PReopen + ExtraOpen[u]`. `UpdateClosure`
  runs after every step. Off by default, so stages 3-5 are unchanged.
- **Gas** (`absorbrun`):
  - Each unit carries an oxygen fraction; gas flowing in has the
    alveolar fraction of the inspired gas, `0.938 FiO2 - 0.05`.
  - Behind shut airways oxygen is absorbed with time constant 90 s and
    the rest (mostly nitrogen) with 3 h. Both are assumed: an
    obstructed unit on oxygen collapses within minutes, one on air over
    hours. This applies only to units shut at that moment; units that
    reopen each inspiration are refilled.
  - Below 40 % of its relaxed FRC volume a unit has **collapsed**. It
    needs 20 cmH2O transmural to reopen (assumed; recruitment studies
    put alveolar opening at 20-40).
  - Perfusion goes with FRC volume times 1 + 2 y/H, three times as
    much at the bottom as at the top (assumed linear). Reported: the
    share to units shut all breath that still hold gas (unventilated,
    still oxygenating), and to collapsed units (true shunt).
- **Protocol**: the stage-5 status asthmaticus lung, 500 mL at 12 /min,
  60 L/min, PEEP 0, for 20 min, then a recruitment manoeuvre (CPAP
  35 cmH2O, 30 s) and 3 min more. About 6 min a run; the four runs
  were run in parallel.
- **Results**:

  | run | at 20 min: EEV (mL) | collapsed units (perfusion) | shut, gas left (perfusion) | 3 min after recruitment: EEV | collapsed (perfusion) | shut, gas left (perfusion) |
  |---|---|---|---|---|---|---|
  | asthma, FiO2 1.0 | -86 | 60 (24.3 %) | 0 | +204 | 25 (9.1 %) | 8 (3.9 %) |
  | asthma, FiO2 0.4 | +83 | 0 | 58 (23.8 %) | +507 | 0 | 33 (12.9 %) |
  | asthma, FiO2 1.0, no hysteresis | +230 | 22 (10.6 %) | 0 | +379 | 0 | 2 (1.0 %) |
  | normal, FiO2 1.0 | 0 | 0 | 0 | 0 | 0 | 0 |

- **What it shows**:
  - **Absorption atelectasis on oxygen**: at FiO2 1.0, the 60 units
    that stay shut through the breath (a quarter of the perfusion, the
    dependent lung) collapse within 2 minutes. End-expiratory volume
    falls below FRC, so the hyperinflation is traded for shunt.
  - **At FiO2 0.4** the same units stay shut but don't collapse: their
    oxygen is gone within about 8 minutes, and the nitrogen left holds
    them open. They are still unventilated, so on the model's terms
    they are still a shunt until the nitrogen goes, hours later.
  - **Recruitment reopens everything, and the oxygen run loses it
    again**: 25 of the 60 units collapse again within 3 minutes. This
    is Rothen's finding in anaesthetised patients (atelectasis back
    within minutes after recruitment on 100 % oxygen, absent for 40 min
    on 40 %).
  - **On 40 % recruitment worsens hyperinflation**: the units that shut
    again trap the manoeuvre's gas (EEV +83 to +507 mL), since there is
    no fast-absorbing oxygen to let it go.
  - **Hysteresis matters**: without it a shut unit reopens as soon as
    inspiration lifts its pressure past `PClose`. Only 22 units collapse
    then, and trapped gas creeps up instead (+230 mL at 20 min).
  - The normal lung never shuts anything.
- **Limits**:
  - The absorption time constants, collapse volume, 20 cmH2O opening
    pressure and the perfusion gradient are assumed.
  - Open units take up no oxygen (their composition is set by
    ventilation alone), and there is no blood-gas calculation (PaO2),
    only perfusion shares.
  - A collapsed unit's volume is held at 40 % of FRC, not taken lower.
  - Reopening is all at once for a unit, with no sequential recruitment
    down its subtree.
- **Checks**: `patchycheck` 6. A unit marked shut between its closing
  and opening pressures carries nothing; unmarked, it empties.
  `UpdateClosure` keeps it shut there, opens it above the opening
  pressure, and marks a unit shut below its closing pressure.
- Options: `--only`, `--minutes`, `--fio2`/`--hyst` (custom run),
  `--tauo2`, `--taun2`, `--rm`, `--dt`, `--out`. Files:
  `out/absorb_<run>.csv`, a row per breath.

## demos/

Each is a standalone Lazarus project (own `.lpi`/`.lpr`/form unit/`.lfm`), built against newVM in the submodule.

- **`JetVent`** — jet-ventilation cannula calculator, the Lazarus port of
  a Delphi/MtxVec/TeeChart project (`prjJetVent.dpr`, `uJetCalc.pas`,
  `uMain.pas/.dfm`, kept in the same folder untouched for reference; the
  port is `JetVent.lpi/.lpr`, `uJetCalcVM.pas`, `uJetMain.pas/.lfm`).
  Six cannulae (Lindholm, Cook, Biro, 14/16/18G Venflon) with bench
  measurements at seven driving pressures (0.5-3.5 bar gauge) - jet flow,
  entrained flow, stall pressures into 15 and 22 mm - against a
  Darcy-Weisbach/Crane 3-20 flow estimate. Two `TCheckGroup`s pick which
  cannulae to show calculated and/or measured, a radio group picks the
  variable, and a `TVMPlot2D` redraws on every change (no Plot button
  now), coloured by cannula and styled by kind (calculated solid, measured
  dashed with circle markers); a memo lists Reynolds numbers and, for the
  Mach/exit-velocity plots, the exit state at 3.5 bar. Four things worth
  knowing:
  - **MtxVec -> newVM/newPolymath**: measured vectors are `TVMobj` row
    vectors; MtxVec's `PolyFit`/`PolyEval` cubic over the Crane A-22
    tables (critical pressure ratio and expansion factor `Y` against `K`,
    gamma 1.4) is `TPolynomial.Fit(..., 3)`/`Evaluate`, fitted once
    lazily rather than per call. Since 2026-10-28 the cubic is on `ln K`
    (K clamped to 1.2..100): the cubic on `K` was up to 0.045 off the
    critical ratio where the cannulae sit (K 2-7), and a higher order on
    `K` is no cure - only two table points above K 20, and a 5th-order
    fit swings to 8 (7th: 650) between K 40 and 100.
  - **Resistance (2026-10-28)**: `ResistanceK` = `InletK` + f L/D +
    `BendExcessK` + outlet 1. `InletK` is 1.0 for the metal cannulae
    (abrupt Luer step) and 0.5 for the Venflons (tapered hub). The
    Lindholm is its overall 11 cm (was 9.5 cm, lengthened to stand in
    for the bend) with a 45 degree bend, r/d 2 assumed, by Rennels &
    Hudson's smooth-bend K less its arc-friction term. Venflon bores are
    the user's measurements - keep them. Mean error against measured
    flow: Lindholm +19 %, Biro +3 %, 14G +3 %, 16G -8 %, 18G -26 %.
  - **The Mach number is corrected.** The original used `(Q/A)/342`:
    ambient-density velocity over a fixed speed of sound (roughly air at
    room temperature; oxygen at 293 K is ~326 m/s, at a choked exit
    ~298 m/s). `TCatheter.ExitState` works from the mass flow
    `rho_amb*Q` and the exit conditions in oxygen: unchoked, continuity
    `V = G R T_e/p_amb` with energy `T_e = T0 - V^2/(2 cp)` is a quadratic
    in `V` solved in closed form, then `M = V/sqrt(gamma R T_e)`; if that
    reaches 1 the exit is sonic (a constant-bore cannula cannot exceed
    M = 1 at its exit), so `M = 1`, `T_e` from NACA 1135 `Eq43`, and the
    exit density/pressure follow from `G/V` - the under-expanded jet. A
    probe over the measured flows showed the old Mach running to 2.0 for
    the 18G at 3.5 bar while the corrected one saturates at 1 with exit
    pressure 1.9 atm; below choking the two agree within a few percent,
    the colder exit roughly cancelling the density change. A new "true
    exit velocity" option plots `V_e` against the old `Q/A`.
  - **Two original quirks fixed rather than ported**: the "mass flow"
    option computed `DP - 0.5 rho V^2/1 bar`, not a mass flow, and now is
    `rho_amb*Q` in g/s as its label said; and "calculated" entrainment
    plotted the measured jet flow (ratio: zero) - entrainment has no
    model, so those two options draw measured series only, grey out the
    Calculated check group unticked (`SetGroupAvailability`, which
    remembers the ticks and restores them on return; an `FUpdating`
    flag stops the programmatic unticks re-entering `Replot`), and say so.
    The TeeChart SVG export and cursor tool are dropped.
  - **FPC gotchas**: `naca1135.pas` (Carmichael's public-domain NACA 1135
    unit, used for `Eq43`) had an unterminated `(*` comment that Delphi
    tolerates but FPC, which nests `(* *)`, reads as swallowing the
    interface - closed, and noted in its revision history. `rayfanno.pas`
    is left in the folder but out of the project: it uses `result :=` in
    default FPC mode and `Dialogs`, and nothing here needs it.
    `VMPlotMaxSeries` had to rise from 10 to 16 for the 12 possible
    series (see `Graphs/uVMPlot2D.pas` above).
- **`JetFlow`** (added 2026-10-28) — a calculator built on JetVent's
  `uJetCalcVM.pas` (on the unit path via `OtherUnitFiles=../../newVM;../JetVent`,
  not copied): driving pressure (bar gauge), bore (mm) and length (cm) in,
  for oxygen at 20 C into 1 atm; out, the flow (`CalcFlow`), a choked
  indicator, the highest Mach number, lowest temperature and lowest
  pressure in the jet, and the thrust, with the working in a memo.
  Recalculates on every change; `--p`/`--d`/`--l` set the inputs. A
  cannula box (`--cannula=<1..6>`, 0 Custom) fills in the bore and length
  of one of JetVent's six bench cannulae; editing either afterwards sets
  it back to Custom unless the pair still matches one (`MatchCannula`,
  with an `FUpdating` flag so the programmatic edits don't recalculate or
  reset the box part-way). With a cannula selected, a check box
  (`--measured`) shows its bench jet flow beside the calculated one,
  linear between JetVent's 0.5 .. 3.5 bar points and not extrapolated
  outside them, plus the whole bench series against the calculated flows
  in the memo; the results still all come from the calculated flow.
  JetVent's Cook measured flows are a copy of the Lindholm's. FPC's
  `Format` has no `+` flag (`%+.0f` prints garbage), hence `SignedPct`.
  A local `Sel` beside the field `seL` is a duplicate identifier. Added
  to `uJetCalcVM.pas` for it (JetVent unchanged in behaviour):
  `CreateCustom` (any bore and length, no measured data), `ResistanceK`
  and a `CalcFlow(DP, out Sonic)` overload exposing the Crane choking
  test, `FreeJet` and `Thrust`. A selected bench cannula is built with
  `TCatheter.Create`, not `CreateCustom`, so it keeps JetVent's per-
  cannula inlet loss and the Lindholm's bend; a custom one is straight
  with inlet loss 1.0. Things worth knowing:
  - **Two choking tests can disagree near the threshold**: Crane's
    pressure ratio against the critical one (inside `CalcFlow`) and the
    sonic exit from the mass flow (`ExitState`). The indicator follows the
    exit state, which the Mach number rests on: red for a sonic exit,
    amber when only Crane says choked (Lindholm at 2.25 bar: exit Mach
    0.996), green otherwise.
  - **The extremes are in the free jet when choked.** A sonic exit is
    under-expanded (exit pressure above ambient), so `FreeJet` expands it
    isentropically from the exit's stagnation pressure `p_e / (p/pt at
    M=1)` (NACA 1135 `Eq44`) to ambient: Mach 1.36 and 214 K for a 14G
    Venflon at 3.5 bar, against the exit's 1 and 244 K. Unchoked, the
    exit values are the extremes. The lowest pressure is therefore always
    ambient; the form gives the exit pressure beside it. Shock-cell
    overshoot below ambient in a real under-expanded jet is not modelled.
  - **Thrust** is the exit-plane `m V_e + (p_e - p_amb) A`: 0.50 N for
    that 14G case, 0.10 N of it pressure thrust.
  - **Stall pressure into the trachea**: three editable diameters, adult
    male, adult female and 7-year-old child (defaults 20, 16, 10 mm -
    typical values, not from one reference), by JetVent's formula
    `rho Q^2 / (A_jet A_trachea) / 100` (`TCatheter.StallPressure`, a
    scalar twin of `Stall`). Chosen over thrust/area (also in the memo)
    by checking both against the bench stall pressures into 22 mm at
    3.5 bar: the original is 4 % high for 14G, 10 % high for Biro,
    11 % low for Lindholm and 18-33 % low for Cook, 16G and 18G;
    thrust/area is 29-52 % low (Biro 9 %). The Cook's 15 mm data
    (75 cmH2O at 3.5 bar against ~51) suggest it underestimates in
    narrow airways, which the memo says. (Figures as of JetVent's
    2026-10-28 resistance changes - bend, inlet, ln K Crane fit; before
    them the first three were within a few per cent.)
- **`BioSpectra`** — frequency spectra of three biological signals from
  PhysioNet: an ECG (MIT-BIH Arrhythmia record 100, MLII, 360 Hz), an EEG
  (MIT-BIH Polysomnographic record slp01a, C4-A1, 250 Hz) and an invasive
  arterial pressure (slp01a, BP). One `TPageControl` tab per signal, each
  with a 20 s time trace on one `TVMPlot2D`, its Hamming-windowed power
  spectral density up to the Nyquist frequency on a second one beneath,
  and the recording parameters in a memo alongside - sampling frequency,
  ADC resolution, gain, baseline, units, the excerpt's position, and the
  record's raw `.hea` header. A spin edit (0 = Nyquist) caps the plotted
  frequency on all tabs, for looking at the EEG's 0-40 Hz on its own, and
  a "linear scale" check box switches every spectrum between dB and plain
  units^2/Hz. A fourth tab, "Square and triangle waves", generates both
  at a chosen fundamental (1000 Hz, 20 s, unit amplitude, a loop over the
  phase since newVM has no elementwise `Sign`/`Frac`) and shows either or
  both (a Square/Triangle/Both radio group; series styles are assigned per
  call since the triangle's series index depends on whether the square is
  shown) on both plots - the time plot showing the first four periods only - with
  the memo tabulating each odd harmonic's textbook amplitude (`4/(pi n)`
  for the square, `8/(pi^2 n^2)` for the triangle) against the value
  recovered by integrating the linear PSD over +-5 bins around the peak;
  they agree to three decimals, which doubles as a check of the PSD
  scaling. A fifth tab, "Square wave synthesis", goes the other way:
  the partial sums `(4/pi) sum sin(2 pi n f0 t)/n` over the odd
  harmonics, each term one `(4/(pi n)) * Sin((2 pi n f0) * T)` added to
  the running sum, with a spin edit for how many terms (1 to 10, i.e.
  up to the 19th harmonic), the ideal square wave dashed grey, a check
  box overlaying every partial sum shaded light to dark blue with the
  last in red, the PSD of the current sum beneath (exactly K lines),
  and the memo giving each term, the RMS error and the peak overshoot -
  which stays near 9 % however many terms are added (Gibbs). Two
  Pascal gotchas hit writing it: `K`/`k` and `N`/`n` are the same
  identifier (case-insensitive), and a `{` inside a `{ }` comment
  (a `sum_{k=1..K}` in the header) opens a nested comment level.
  A sixth tab, "EEG bispectrum", puts a `TVMPlot3D` to use: a separate
  300 s EEG excerpt (`data/slp01a_600s_300s.dat`, 450 KB, same start as
  the 20 s one so its first 20 s are identical - the bispectrum needs
  epochs to average, and 20 s gave only 19 with a bicoherence floor of
  0.23; 300 s gives 299 and a floor of 0.06) is cut into overlapping
  epochs (length from a spin edit, default 2 s at 50 % overlap), each
  mean-removed, Hamming-windowed and `FFT_R2C`'d, and
  the triple product `X(f1) X(f2) X*(f1+f2)` accumulated on the (f1, f2)
  grid up to a chosen limit (default 30 Hz; capped at a quarter of fs so
  f1+f2 stays below Nyquist). A radio group picks the bispectrum
  magnitude or the bicoherence, which divides out the power at the three
  frequencies and lies in [0, 1] with a `1/sqrt(epochs)` bias floor the
  memo quotes. Only the f2 <= f1 triangle is computed, the grid being
  filled symmetrically, and the square `TVMobj` goes to `SetData` with
  `XAxisMin/Max`/`YAxisMin/Max` set to the frequency range so the ticks
  read in Hz, and `ZAxisMin/Max` fixed to 0..1 for bicoherence. A
  "Signal" radio group swaps the EEG for a synthetic test signal - two
  tones at `fa`/`fb` (spin edits, default 6 and 10 Hz) with random
  phases drawn once, through the memoryless nonlinearity `y = x + k x^2`
  (`k` from a spin edit, default 0.5) plus a little white noise, at the
  EEG's own length and rate so the two are comparable. The square term
  makes intermodulation products at `2fa`, `2fb`, `fa+fb` and `fb-fa`
  whose phases are fixed combinations of the tones' phases, i.e.
  genuinely phase-coupled, so the bicoherence peaks near 1 at `(fa,fa)`,
  `(fb,fb)`, `(fb,fa)` and `(fb,fb-fa)` on a flat floor - the textbook
  picture, which the EEG does not show - and at `k = 0` the peaks vanish
  while the power spectrum would still show both tones: the memo spells
  out the expected positions. The
  inner accumulation is a plain loop over `GetRealPart`/`GetImagPart`
  values - no BLAS primitive forms a triple product on a grid. The
  project gained `../../newVM/Graphs/uVMPlot3D.pas` (and so `GLU`) for it.
  Since 2026-10-13 the tab opens on the two-tone signal
  (`rgBiSignal.ItemIndex = 1` in the `.lfm`, widened to 400 px so both
  captions fit now its spin edits show from the start). A row above the
  surface, built in code (`FBiTop`, 36 % of `pnlBi`, sized by
  `BiPanelResize`), shows the analysed signal's first 2 s (`FBiTime`)
  and its PSD (`FBiSpec`, `EpochPSD`). The PSD is the mean of
  `ComputePSD`'s linear PSDs over the bispectrum's own epochs and overlap,
  taken to `2 * KMax * Fres` so the `f1 + f2` sum tones show. Snapshot
  mode saves this tab for both signals (`_eegbi<n>_time/_psd.png`,
  `_eegbi<n>.bmp`).
  - **Tab order** (since 2026-10-13; the "fourth/fifth/sixth tab" wording
    above is the order the tabs were added): Square wave synthesis, Square
    and triangle waves, ECG, Arterial pressure, EEG, Anaesthesia EEG,
    Guitar distortion, EEG bispectrum, Anaesthesia bispectrum. The order
    is the order of the `TTabSheet` blocks in `ubiospectramain.lfm`; no
    code uses a page index. The form opens on the first tab
    (`ActivePage = tsSynthesis`, and the same assignment at the end of
    `FormCreate`, which is needed because creating each sheet's GL
    controls brings that sheet forward).
  - **Data** lives in `data/` as 20 s excerpts fetched by HTTP range
    request (about 50 KB in all) plus the unmodified `.hea` headers, so the
    demo runs offline; `data/README.md` has the byte ranges, re-fetch
    commands, licence (ODC-BY) and citations. Both records are WFDB
    format 212 - two 12-bit two's-complement samples packed in three
    bytes, signals interleaved - decoded by the form's own `LoadWFDB212`,
    which also parses the `gain(baseline)/units` field (baseline
    defaulting to the ADC-zero column) and the `fs/counter(base)` form
    of the sampling frequency. Decoded ranges were checked in Python
    before the Pascal was written: ECG +-1 mV, pressure 39-128 mmHg,
    EEG +-150 uV.
  - **Spectrum**: mean removed, Hamming window as
    `AddScalar(-0.46 * Cos(Theta), 0.54)`, `FFT_R2C` from
    `newVMComplex.pas` (FFTW) for the packed half-spectrum, one-sided PSD
    `2|X|^2/(fs sum w^2)` (not doubled at DC/Nyquist) via
    `Sqr(GetRealPart(X)) + Sqr(GetImagPart(X))`, plotted in dB as
    `(10/ln 10) * Ln(P)` against `k fs/N`, all in one `ComputePSD` shared
    by the four tabs; the frequency axis is cut with `SubMatrix`. The dB
    floor is 150 dB below the spectrum's own peak, not an absolute
    constant: with the mean removed the DC bin is exactly zero, and a
    first absolute floor of 1e-30 put it at -300 dB, stretching every dB
    axis. Both plots call `ClearSeries` before `SetData`.
  - **Checked by screenshot**: the ECG spectrum shows QRS energy below
    40 Hz and the 60 Hz US mains spike of the MIT-BIH recording; the
    pressure spectrum shows heart-rate harmonics; the EEG a 1/f fall with
    narrow interference lines.
  - **Gotcha**: creating the OpenGL plot controls on each `TTabSheet` in
    `FormCreate` brings that sheet forward, so the form opened on the last
    tab filled until `pcSignals.ActivePage := tsECG` was set at the end.
  - **Anaesthesia EEG tab** (added 2026-10-11, fourth of seven): frontal
    EEG through one anaesthetic (plus a sedated state from a second case -
    see below) from **VitalDB**, Seoul National University
    Hospital's open intra-operative database (CC BY 4.0, also PhysioNet
    `vitaldb`). It's the only open-access raw anaesthesia EEG on PhysioNet:
    the eeg-gaba-anesthesia, eeg-power-anesthesia and JSMF sets are
    restricted and mostly processed. Case 655: a 52-year-old man, liver
    sectionectomy, propofol and remifentanil TCI, no volatile. The BIS
    Vista channel 1 (`BIS/EEG1_WAV`) is 128 Hz in uV, with three 20 s
    excerpts: awake before induction (BIS 94), maintenance (BIS 46,
    propofol Ce 4.0) and burst suppression (BIS 16, SR 61 %). There is a
    whole-case trend of BIS, SR and propofol Ce x10 with a dashed line at
    each excerpt, drawn with `PlotXY` so each series skips its own gaps.
    Below it are the chosen excerpt's trace and its PSD (originally all
    three overlaid; changed to follow the radio group at the user's
    request, 2026-10-11).
    The memo gives the band shares from the linear PSD (`ComputePSD`'s new
    `LinearFull` flag). Propofol shows power x8, slow-delta waves, an
    11.2 Hz frontal alpha at ten times the awake alpha power (which peaks
    at 8.7 Hz), and beta halved. Data files are plain CSV (VitalDB isn't
    WFDB), made by `data/fetch_vitaldb.py`; the case-selection criteria
    are in `data/README.md`. Things worth knowing:
    - **VitalDB's web API needs no login**: `api.vitaldb.net/cases` and
      `/trks` (gzipped CSV) give the case table and every case's track
      ids, and `api.vitaldb.net/<tid>` gives one track. A **wave** track
      is one row per sample on an implicit 1/fs grid (the Time column is
      filled only on the first and last rows), with empty values for
      gaps. A **numeric** track carries its own times.
    - **Most cases start recording after induction** (`anestart` < 0), and
      many attach the BIS sensor after induction too. Only about 155 of
      the propofol-TCI cases aged 18-65 have usable awake EEG.
    - **BIS reads 0, not missing, before the sensor is on and in signal
      dropouts.** The data file blanks BIS/SQI/SR where SQI is 0, and the
      plot skips any remaining BIS of 0.
    - BioSpectra now has **`--snapshot=<prefix>`**: it opens this tab,
      saves the trend, each excerpt's trace and the spectra via
      `SaveToPNG` plus the window, prints the memo, and exits.
    - **Layout gotcha**: two `alTop` plots created in code stack in an
      arbitrary order (the trace came out above the trend). Set each
      `Top` explicitly in the panel's `OnResize`.
    - **Anaesthesia bispectrum tab** (eighth, after "EEG bispectrum";
      same date): the anaesthesia trend and trace on top, with no legends
      at that height (the trend's title names the colours). In place of the
      PSD is the chosen state's bispectrum or bicoherence on a
      `TVMPlot3D`, computed from 300 s of each state
      (`vitaldb_655_eeg300.csv`, 299 epochs of 2 s, floor 0.06). The
      calculation moved out of `ShowBispectrum` into `ComputeBispectrum`,
      shared by both tabs. Results, which matched an independent numpy
      calculation to two decimals:
      - propofol: coupling gathers in alpha, peaking 0.49 at
        (11.5, 10.5) Hz, with beta at the floor
      - awake: only the eye-movement corner (delta x delta 0.38)
      - burst suppression: high everywhere (0.92 peak), since each burst
        is a phase-aligned transient
      The awake window starts at the 745 s excerpt. The cleaner-looking
      1000-1300 s turned out to carry ECG spikes about once a second, and
      bicoherence ~0.9 everywhere: perfectly phase-locked harmonics. A
      bicoherence that high across the whole plane means artefact.
      - **The low-frequency peak**: drift and eye movement in the
        0-0.5 Hz bins put a huge peak near (0, 0) that set the height
        scale and flattened the surface. `ComputeBispectrum` now takes
        an `Fmin`, and the grid starts at bin `KMin`. The tab draws from
        1 Hz by default (spin edit); the memo's region means still use
        the full grid. Even from 1 Hz, linear |B| is dominated by the
        delta corner, because |B| scales with amplitude cubed. So the
        display offers `|B| (dB)` as well: 10 log10 re the surface's
        maximum, floored at -60 dB, since -40 left awake and burst
        suppression mostly flat on the floor. Bicoherence, the default,
        is self-normalising and needed only the lower limit.
      - **SynchFastSlow** (BIS's bispectral sub-parameter, Rampil 1998)
        is in the surface's title for the chosen state, and in the memo
        for all three. It's ln( sum|B| over 0.5-47 Hz / sum|B| over
        40-47 Hz ). The literature never says how a band maps onto the
        (f1, f2) plane, and the openibis reimplementation's code couldn't
        be reached. Here a band is the band of the **sum frequency**
        f1 + f2, the only reading that fits a 128 Hz EEG: both f1 and f2
        in 40-47 Hz would put the sum past Nyquist. Sums run over f2 <=
        f1 with both >= 0.5 Hz, natural log. It's a separate pass
        (`SynchFastSlow`), since it needs X up to 47 Hz, beyond the
        plotted grid. Values: awake 5.35, propofol 7.05, burst
        suppression 4.11, matching numpy exactly. It rises as fast
        activity falls under propofol, then drops in burst suppression,
        where broadband bursts refill 40-47 Hz and BIS relies on the
        suppression ratio instead. Not the monitor's own number.
    - **Sedated state** (added the same day, at the user's request): a
      fourth state on both anaesthesia tabs, in depth order awake,
      sedated, propofol, burst suppression. It comes from a second
      VitalDB patient, **case 574**, because case 655 never sat at
      sedation depth. Case 574 is a 67-year-old woman under
      sedation-analgesia, with propofol Ce held at 1.0 ug/ml,
      remifentanil at 1.0 ng/ml and BIS ~84. The excerpt starts at
      3440 s (SQI 100 %) and the 300 s window is 3300-3600 s.
      `fetch_vitaldb.py` now writes both cases from a `CASES` table, and
      reproduces the case 655 files byte for byte. In the code each case
      is a `TAnaesCase` (trend plus details). `AnaesStateCase` maps each
      state to its case, and the trend plot follows the chosen state's
      case. Things worth knowing:
      - **Why case 574**: VitalDB has 72 "Sedationalgesia" cases. 50
        have raw BIS EEG and a propofol pump, about 26 h at BIS 70-90 in
        all, and 31 of them have at least 10 min. The selection details
        are in `data/README.md`.
      - **Spikes**: several 300 s windows near the one used each hold a
        single huge spike, with kurtosis over 1000 and bicoherence ~0.7
        everywhere. Screen windows by kurtosis before trusting a
        bicoherence.
      - **What it shows**: at this depth the EEG is still awake-like.
        Power is 29 against 36 uV^2 awake, and the alpha peak is still
        9.2 Hz rather than the 11 Hz frontal alpha. Beta is a little
        higher (20 %). Bicoherence sits at the floor everywhere (peak
        0.22). SynchFastSlow is the lowest of the four (3.69), most
        likely from forehead EMG.
      - **Layout**: both memos widened from 440 to 510 px for the
        four-column tables.
  - **Guitar distortion tab** (ninth, added 2026-10-12): linear against
    nonlinear amplification on one note - the open G string (196 Hz)
    picked clean on a nylon-string guitar and through heavy distortion on
    an electric, by the same Freesound player (SpeedY, CC0;
    `data/guitar_*.wav`, 4 s, 44.1 kHz, made by `data/fetch_guitar.py`
    from the public HQ Ogg previews, since originals need a login). The
    left column is always the clean note; the right is the distorted
    recording, the clean note times a gain (identical in shape, as
    linearity demands - the memo's figures match exactly) or
    `tanh(g x)` - the controlled comparison, since the recordings also
    differ in instrument. Each column has 25 ms of waveform (or the whole
    note), the PSD re its own peak, linear or dB per "Linear scale",
    and |B| in dB or bicoherence via `ComputeBispectrum` (0.1 s epochs,
    50-2000 Hz, grid capped at 400 bins a side). Play buttons write the
    note, peak-normalised, to a temp WAV and play it asynchronously:
    `PlaySound` (`MMSystem`) on Windows, `paplay`/`aplay` through
    `TProcess` on Linux. Things worth knowing:
    - **Bicoherence doesn't separate clean from distorted here**: a
      plucked string's harmonics are already phase-locked, so any
      periodic note scores high on the harmonic lattice (clean 0.58 mean,
      distorted 0.31). What distortion changes is |B|'s spread: 0.8 % of
      the triangle within 30 dB of the maximum clean, 4.2 % distorted
      (numpy agreed). The memo says so.
    - **f0 is not the strongest line**: the distorted note's 2nd and 3rd
      harmonics outweigh its fundamental, so `ShowGuitar` takes the
      largest divisor of the strongest 80 Hz-1 kHz line that still has a
      line within 20 dB.
    - `--snapshot` also writes this tab's 2D plots as PNGs and its window
      as `_guitar_<dB|bicoh><n>.bmp`. Not `B`/`b`, as the anaesthesia
      bispectrum's names are: Windows file names ignore case, so
      `_bispectrumb*.bmp` overwrites `_bispectrumB*.bmp` there. On Windows
      `GetFormImage` leaves the GL areas blank, and `TVMPlot3D` has no
      `SaveToPNG`, so the surfaces can only be checked on screen.
    - Fixed in both plot components along the way: `ComputeTicks`
      accumulated `v := v + step`, so a tick at zero could come out as
      `-5.551E-17` and be labelled so. Ticks are now `first + n*step`,
      with near-zero snapped to 0.
    - **Spectrum defaults (whole demo)**: "Linear scale" is ticked by
      default. The upper-frequency spin edit's 0 now means "the signal's
      own default": 40 Hz for the ECG and both EEGs and 20 Hz for the
      arterial pressure (`TSignalTab.DefaultFmax`, and `ComputePSD`'s
      `DefaultFmax` parameter), Nyquist for the synthetic tabs. These
      were 30 Hz for the EEGs only at first; the user asked for 40/20/40
      the same day. EEG
      spectra start at 0.5 Hz (`Fmin`). Below 0.5 Hz, drift and eye
      movement in the frontal lead peak 2-16x above anything in the
      bands, which flattened the linear plot. Both EEG spectra carry the
      delta/theta/alpha/beta/gamma bars (`AddEEGBands`, on `TVMPlot2D`'s
      new `AddXBand`).
- **`O2Entrainment`** (added 2026-10-20) — the O2 % delivered when an
  oxygen jet entrains room air, `F = (Fs + Fa R)/(1 + R)`, against the
  entrainment ratio R (volumes of air per volume of O2), on one
  `TVMPlot2D`. The curve is one vector expression over a `linspace`, with
  `1/(1 + R)` as `Exp(-Ln(...))` (no elementwise division). Spin edits set
  the source and room-air O2 %, the axis range and a ratio of your own
  (a green point plus an `AddXMarker` read-out). Blue diamonds are the six
  Venturi valve ratings (24-60 %, nominal ratio `(100 - F)/(F - 21)`), and
  black circles are the trachLESpeep LES's measured ratios (2.42 over
  14-15 ms, 2.01 over 10-15 ms; 44.0 and 47.2 % if the jet were O2). The
  LES points get no X marker of their own, because its caption collided
  with the user's. The memo tabulates the valves and the inverse rule
  `R = (Fs - F)/(F - Fa)`. `--snapshot=<file.png>` saves the plot, prints
  the memo and exits.
- **`GlassSpine`** (added 2026-11-15) — spinal anaesthesia in real time:
  bupivacaine spreading under gravity through a transparent dural sac,
  on the GPU by OpenCL, drawn by OpenGL. Two sacs run side by side in one
  grid, each with its own solution: hyperbaric 1.020 (blue) and plain
  0.999 (amber) by default. Gravity is fixed, pointing down the screen,
  and the sacs rotate under it.
  - **Units**:
    - `uspinegeom.pas` (`TSpineGeom`): the sac and cord from S2 to T1
      (19 levels, about 544 mm long).
    - `glassspine.cl`: the kernels.
    - `glassspine_cl.inc`: `glassspine.cl` as a string constant
      (`GlassSpineKernelSource`), generated by `tools/cl2inc.py` - do not edit;
      regenerate it after changing the kernels. `TSpineSim.Create` uses a
      `glassspine.cl` beside the executable if there is one, else this, and
      says which in `KernelOrigin` (the Methodology tab's last section and
      spinecheck's first line show it). `release/build-release.sh` refuses a
      stale include.
    - `uglassspinesim.pas` (`TSpineSim`): the simulation.
    - `uspineview.pas` (`TSpineView`, a `TOpenGLControl`): the view.
    - `uglassspinemain.pas`: the form, with its controls built in code.
      The view and profile sit on a "Simulation" tab beside a
      "Methodology" tab: a word-wrapped memo filled by
      `uglassspinemethod.pas` (`FillMethodology`), plain prose for a
      reader, ending with this run's grid and solver figures read from
      `TSpineSim`. `--tab=method` opens on it.
    - `spinecheck.lpr`: the headless check.
  - **Build and run**:
    - the demo: `lazbuild --ws=gtk2 demos/GlassSpine/GlassSpine.lpi`;
    - the check: `fpc -O2 -FUlib -Fu../../newVM -Fi../../newVM spinecheck.lpr`, which
      takes `--time --tilt --roll --dx --level --iters --jet --cfl --dt
      --b0 --b1 --every --pulse --cardiac --hr --resp --rr --displace
      --diff --fluxcheck` (`--diff` in mm^2/s); `--fluxcheck=1` also prints the axial flux at each
      report while injecting. Before the
      injection it runs pulsation alone and prints the computed against
      the prescribed axial flux at L3, L1, T8 and T2, and where the
      divergence residual is worst.
    - It needs `HAVE_OPENCL`, because it uses
      `OpenCLAPI.InitializeOpenCLContext`. That picks the GPU with the
      most compute units (the RTX 5070 here), a vendor driver before
      Mesa's rusticl, and also requires clFFT.
  - **Posture**:
    - **Tilt** is head up or down: +90 is sitting, negative is
      Trendelenburg. **Roll** is about the long axis: +90 is left
      lateral, 180 prone.
    - `PostureMatrix(Tilt, Roll)` is `Rz(tilt) Rx(-roll) Base`. Base maps
      body x (the patient's left) to world -Z, y (anterior) to +Y and z
      (head) to +X.
    - The fluid feels `g_body = R^T (0, -9810, 0)` mm/s^2. There are no
      fictitious forces, since the turning is taken as slow.
    - Right-drag in the view sets the posture (`OnPosture`), and so do
      the sliders and presets (supine, sitting, left and right lateral,
      prone, head down 15, head up 15). Left-drag only orbits the camera.
  - **Geometry**:
    - Sections are ellipses (`LevelAX`/`LevelAY`), with the cord down to
      the conus at L1-L2. The sagittal curve has its apex at L3 and its
      nadir at T8 (Hirabayashi 1995), about 34 mm deep.
    - These figures are typical estimates, not one patient's.
    - At dx 1.25 mm the grid is 38 x 44 x 441 with about 72k fluid
      cells, 69.8 mL of CSF per sac. Every kernel runs only over the
      compacted fluid-cell list.
    - `Flags` bits: `FlagFluid`, `FlagCord`, `FlagSac1`, `FlagRoots`
      (the cauda equina), `FlagRing`/`FlagKey` (the level rings drawn).
  - **Fluid: Stam's Stable Fluids on a MAC grid.** Velocity uses
    semi-Lagrangian advection (RK2 backtrace), implicit Jacobi viscosity
    (nu 0.7 mm^2/s) and two projections, the first with half the
    iterations. Pressure is red-black SOR (omega 1.7, 30 iterations,
    warm-started), with Neumann conditions at the walls. Each colour has
    its own cell list and its own bound `pressure_rb` kernel
    (`FBColour`/`FKColour`), so a half-sweep is one launch over that
    colour's cells with no argument set; output is unchanged from one
    list with a colour test.
    - Storage is a float4 per cell whose `.x/.y/.z` are the velocities on
      its -x/-y/-z faces. Closed faces stay 0 and are never written.
    - **Why staggered**: on Stam's collocated grid, the central-difference
      divergence left the flow far from divergence-free next to the dura.
      Now |div| dx is about 1e-3 of |u|.
    - Buoyancy is Boussinesq, `(baricity - 1) C g_body`, against CSF
      density 1.00059.
    - **Section flux correction** (`plane_flux`/`plane_correct`, before
      every projection). The SOR residual, ~1e-3 of the speed per cell,
      is smooth and of one sign over long stretches. Summed over the
      thousands of cells below a level, it let the net flux through that
      level drift by tens of per cent, because SOR barely touches the
      long axial mode. One work-item per (sac, section) sums the section's
      flux, and a uniform plug brings it to its prescribed value: `q G_k`
      with pulsation, zero without, as a closed sac requires. The
      projection then only works within each section. This also changes
      the pulsation-free runs slightly; the supine, sitting and lateral
      figures in Results came out the same to the level reported.
  - **The drug is not transported by Stam's method.** C, the injectate
    volume fraction, is conservative finite volumes: MUSCL with the MC
    limiter and SSP-RK2 (`c_flux`/`c_update`).
    - It is sub-cycled to CFL 0.3. The step's largest face speed comes
      from an `atomic_max` reduction (`max_speed`), read back each step.
    - Semi-Lagrangian and MacCormack transport of C were both tried, and
      both gained or lost 10-90 % of the dose. The finite-volume scheme
      is exact: 3.00 mL injected, 3.00 mL present.
  - **Injection**:
    - The source is a 2.5 mm sphere 3 mm inside the posterior dura at
      L2-3, L3-4 or L4-5 (`InjectionPoint`).
    - The dose, duration and needle (22/25/27G, IDs 0.41/0.26/0.21 mm)
      are set on the form.
    - The bookkeeping (pending, injected, fraction f) runs on the GPU in
      `inject_prepare`, a single work-item kernel writing a state buffer,
      and `inject` sets `C += f (1 - C)`. On the host it went wrong: the
      per-frame capacity it used was stale.
    - The jet is a body force on the source cells,
      `Q^2/(A_needle V_source)`, cephalad, caudad or off.
  - **CSF pulsation** (2026-11-15, on by default; a group on the form,
    `--pulse=0` to start with it off).
    - The flow into the sac through T1 is `q(t) = pi f V sin(2 pi f t)`
      for a cardiac and a respiratory wave. V is the volume per cycle:
      0.3 mL a beat at 70 /min and 0.3 mL a breath at 12 /min. These
      are estimates; cervical MRI stroke volumes are 0.5-0.8 mL, and
      they fall down the canal.
    - The CSF enters through a 10 mm band at the T1 end
      (`PulseBandMM`) and is taken up evenly by every fluid cell, as the
      dura's compliance. So the volume crossing a level falls linearly
      with the CSF below it, to nothing at S2.
    - The projection targets `div u = q pw.x` instead of zero. The
      `pw.x` term is `w/Vcell`, with `w = 1/N_band - 1/N_sac`, so it
      sums to zero over each sac.
    - **The flow is built as a plug.** SOR alone would take thousands of
      sweeps to set up a flow along the whole sac, so `forces` adds each
      step's change of q as a uniform flow on every open z face:
      `pw.y = G_k/(A_k dx^2)`, with `G_k` the volume crossing section k
      per unit q (`FPlaneG`). The Womersley number is about 20 (Stokes
      layer 0.4 mm, below dx), so the real profile is nearly flat. The
      projection only tidies each section, and the section correction
      above keeps the totals exact.
    - **Check** (`spinecheck`): the computed flux at L3, L1, T8 and T2 is
      within 0.5 % of the prescribed one, and |div - s| dx is under 1e-3
      of the largest speed.
    - **Isolated cells.** Before the flood fill was added, the flux
      drifted as much as 160 mm^3/s at L3, and the worst divergence sat
      at the top cap at 100 % of the speed. The cause is 10 fluid cells
      at the closed ends that touch the rest only by an edge or a corner.
      A source there can't drain, and it makes the Neumann problem
      incompatible. `BuildPulse` floods each sac face by face from a
      cell half way up and gives the cells it doesn't reach no source.
    - **Drug** (`c_update` adds `C div u`). Concentration is carried with
      the fluid (DC/Dt = 0) as a cell "dilates", so `sum C Vcell`
      oscillates. `Dilation(s) = exp(Phi/V_sac)`, with Phi the volume
      taken up (`PulseDisp`), converts it back. `Present` and `Profile`
      are multiplied by it, and the injection's owed volume is divided by
      it. `Injected` is the true volume owed less the pending. Without
      that, `Present` read 3.01 mL for 3.00 injected.
    - **Effect** (supine, 120-125 s): hyperbaric reaches T9-T8 rather
      than T5, and more of it stays at T12-L2 (at 180 s: L1 0.38 against
      0.17 mL, T7 0.02 against 0.14). The heartbeat does almost all of
      this; breathing alone gives T9 at 65 s, against T11 with both. That
      the oscillation stirs and dilutes the thin heavy sheet on the
      posterior dura is a reading of the numbers, not tested. Plain
      0.999 is unchanged (L5-T12).
    - **Sitting and left lateral** (rerun the same day, 125 s, off/on):
      sitting is unchanged, hyperbaric S2-L1 and plain L5-L4..T12-T11
      both ways. Left lateral, hyperbaric reaches T9 rather than T7 (T10
      rather than T9 at 65 s), and plain S1..T12-T11 both ways. So
      pulsation slows the hyperbaric spread wherever it runs a long way
      downhill along the sac, and does nothing when sitting, where the
      solution has only a short way to fall to the sacrum.
    - The cost is the headless check at about 10x real time (17x
      before); the window still draws about 150 fps.
  - **Injected volume displaces CSF** (2026-11-15, `Displace`, on by
    default; a check box in the Injection group read at Inject,
    `--displace=0`). Off is the first scheme: the injectate replaces CSF
    in place (`inject_prepare`/`inject`).
    - A second prescribed source like the pulsation's, `pwi` (float4,
      `BuildInjectionField`, rebuilt with the source cells at each
      Inject): `w = +1/n_src` in the source sphere,
      `-HeadFraction/N_band` in the T1 band and `-(1 - HeadFraction)/N_sac`
      everywhere. `.y` is its plug and `.z` the source part alone.
      `plane_flux` targets `q G + qi Gi`.
    - `HeadFraction` 0.67 is an estimate: the spinal canal holds roughly a
      third of the craniospinal compliance. The dura's share adds to
      `PulseDisp`, so `Dilation` covers it.
    - `c_update` brings in pure injectate through `.z` (C = 1, divided by
      `Dilation(0)`); the rest of the divergence leaves or dilates at the
      local C. So the dose goes in exactly (3.00 mL in, 3.00 present)
      with no capacity bookkeeping, and `Injected` is the volume owed.
    - `BuildPulse` now keeps its flood fill (`FConn`), the T1 band
      (`FTopK`, `FNTop`) and the open faces per plane (`FFaces`) for this,
      and `Setup` builds the pulse before the source cells.
    - **Check** (`--fluxcheck=1`, pulsation off): during the injection
      the computed flux at L3, L1, T8 and T2 is 176/177, 162/163, 150/150
      and 137/137 mm^3/s against prescribed. That is 1-2 mm/s up the sac:
      0.9 at L3, about 200 mm^2, and more where the thoracic sac is
      narrow.
    - **Effect** (pulsation on), small:
      - Supine at 155 s: plain reaches T11 rather than T12-T11, and at
        180 s 0.10 against 0.06 mL at T12. Hyperbaric is at T8 rather than
        T8-T7, with 0.013 against 0.022 mL at T7.
      - Sitting at 65 s: hyperbaric reaches T12 rather than L1, and plain
        T12-T11 rather than T12.
  - **Head-down tilt** (2026-11-15, `spinecheck --tilt=<-deg>`, pulsation
    and displacement on, 3 mL at L3-4). Run to compare with Der
    Anaesthesist 2009 (doi 10.1007/s00101-009-1661-6), which tested
    hyperbaric bupivacaine in straight and curved subarachnoid models at
    0-15 deg head down. Hyperbaric cephalad edge (C 1 %):

    | Head down | 65 s | 95 s | 125 s | 185 s | 245 s |
    |---|---|---|---|---|---|
    | 0 | T11 | T10 | T9 | T7 | T6-T5 |
    | 5 | T11 | T10-T9 | | | |
    | 10 | T11-T10 | T9 | | | |
    | 15 | T11 | T10 | T7 | T4-T3 | T2 |

    - 5 and 10 deg were run to 120 s only.
    - Up to about 35 s every tilt is the same, because the jet dominates.
    - The tilt mainly empties the sacrum. S1+S2 holds 0.68 mL flat at
      120 s, 0.46 at 10 deg and 0.17 at 15 deg. The thorax (T1-T11) holds
      0.48 against 0.68 mL at 300 s.
    - Plain 0.999 drifts towards the sacrum, uphill when head down: S2-S1
      to T11 at 15 deg.
    - **Against the paper**:
      - It agrees that 15 deg is what moves the sacral pool.
      - It disagrees about lying flat. The paper found diffusion governed
        the supine spread, and spill over the lordosis into the thorax
        only at 15 deg. GlassSpine has no diffusion, yet the solution
        crosses into the thorax supine, by gravity along the curve.
        Injecting near the lordosis apex may explain it; the paper's
        injection site and geometry weren't checked, from the abstract
        only.
      - The 3-4 extra levels at 15 deg by 4 min may be more than
        clinical trials show; their head-down results are mixed.
  - **Drug diffusion** (2026-11-15, off by default; "Drug diffusion" in the
    Run group: none, molecular 7e-4, 0.1, 1 or 10 mm^2/s, applied live).
    Added to test the paper's claim that diffusion decides the supine
    spread.
    - `c_flux` adds Fick's `D dt/dx^2 (C_L - C_R)` on every open face, so
      the dura and cord are no-flux and the dose is still exact.
    - It is explicit, so the drug's sub-steps also keep `D dt/dx^2 <= 0.15`
      (cap raised from 64 to 256 sub-steps). 10 mm^2/s still needs only
      one sub-step at Dt 0.01.
    - Molecular (7e-4 mm^2/s, under 1 mm in 5 min) gives the same figures
      as none, to the third decimal.
    - **Results**: hyperbaric cephalad edge at 245 s, and mL in the sacrum
      (S1+S2) and thorax (T1-T11) at 300 s:

      | D, mm^2/s | Flat: edge | sacrum | thorax | 15 deg down: edge | sacrum | thorax |
      |---|---|---|---|---|---|---|
      | 0 | T6-T5 | 0.63 | 0.48 | T2 | 0.17 | 0.68 |
      | 0.1 | T6 | 0.57 | 0.37 | T3-T2 | 0.19 | 0.62 |
      | 1 | T9 | 0.33 | 0.16 | T7 | 0.20 | 0.28 |
      | 10 | T9 | 0.24 | 0.21 | T9 | 0.22 | 0.22 |

    - **Diffusion takes posture out, not in.** It dilutes the injectate,
      and with it the density excess that buoyancy acts on. So the
      cephalad spread shrinks rather than grows, and at 10 mm^2/s flat and
      15 deg give the same answer. There, hyperbaric and plain are almost
      identical blobs (S2..T9).
    - 1 mm^2/s sits between the two: 15 deg still adds two levels.
    - So the paper's "diffusion decides it supine", and gravity winning
      only from 10 deg, would need an effective D of about 1-10 mm^2/s.
      That is 10^3-10^4 times molecular, and would have to come from
      mixing that GlassSpine resolves explicitly (jet, pulsation) or
      leaves out (the nerve roots' stirring, the real waveform).
    - **30 minutes supine** (2026-11-16, `--time=1800 --every=300`, about
      7 min of wall time each). Cephalad edge (C 1 %):

      | D, mm^2/s | Solution | 5 min | 10 min | 15 min | 20 min | 25 min |
      |---|---|---|---|---|---|---|
      | 0 | hyperbaric | T5 | T4-T3 | T3 | T3 | T3 |
      | 0.1 | hyperbaric | T6-T5 | T5-T4 | T4 | T4 | T4 |
      | 1 | hyperbaric | T9 | T9-T8 | T8 | T8-T7 | T7 |
      | 0, 0.1 | plain | T11 | T11 | T11-T10 | T10 | T10 |
      | 1 | plain | T11 | T11-T10 | T10 | T10-T9 | T9 |

      At 30 min:

      | D, mm^2/s | Hyperbaric thorax (T1-T11) | Hyperbaric sacrum (S1+S2) | Plain thorax | Plain sacrum |
      |---|---|---|---|---|
      | 0 | 0.67 | 0.50 | 0.12 | 0 |
      | 0.1 | 0.49 | 0.36 | 0.13 | 0.06 |
      | 1 | 0.30 | 0.32 | 0.22 | 0.15 |

      Values are in mL, and the dose stayed at 3.00 mL throughout.
      - **Against typical clinical figures** (from memory, not one trial):
        hyperbaric 0.5 % peaks at T4-T6 by 20-30 min, and plain at T7-T10.
        - At D 0 the edge has stopped rising by 15 min, a level or two
          high.
        - 0.1 holds at T4 from 15 min, the best match.
        - At 1 the edge is still creeping at T7 at 30 min, and hyperbaric
          and plain converge to about 2 levels apart.
      - Somewhere between 0.1 and 1 mm^2/s would probably give a peak
        near T5 with a gap of about 4 levels. That hasn't been run.
      - The 1 % edge is arbitrary, and a block usually reaches a level or
        two above the drug, so read the edges between runs rather than as
        block heights.
    - The model carries one scalar, so diffusing the drug also diffuses
      the glucose that makes it heavy. Glucose's molecular D is similar
      (about 6.7e-4 mm^2/s).
  - **Rendering** (`uspineview.pas`):
    - C is read back each frame into a LUMINANCE16 3-D texture. The
      geometry is an RGBA8 3-D texture: inside dura, cord, level ring
      and key ring.
    - A GLSL 1.20 ray-march draws the dura as glass with a Fresnel rim,
      the cord as opaque Lambert, and the drug by emission and absorption
      with opacity proportional to sqrt C.
    - The dura's normals come from a gradient at 1.5 dx, which stopped
      them sparkling. The cord hit is refined by 5 bisection steps, which
      removed its speckle.
    - Each sac has its own model-view, offset perpendicular to its long
      axis on screen.
    - Text labels are LCL bitmap textures, and a gravity arrow is drawn
      in pixel space.
    - The level rings are cream, and red at the lower borders of T4, T10
      and L1 (the nipple, umbilicus and groin dermatomes). A key in the
      bottom right says so, shown with the labels.
    - `ResetView`: yaw 0, pitch 12, distance 1000.
  - **Real-time stepping** (`AppIdle`): simulated time is owed to the
    clock (`FDebt`, wall time x the speed choice of 0.5-20x), and whole
    `Dt` = 0.01 s steps are taken, with the remainder carried to the
    next frame.
    - At most 40 steps are taken a frame, and a shortfall beyond that is
      dropped, so the window stays responsive.
    - An earlier `Advance(dt)` per frame rounded the remainder away and
      ran about 1.5x fast.
    - Stepping also stops once a frame has spent `StepBudgetMs` (30 ms)
      on it, the shortfall dropped likewise (2026-11-17). Without that, a
      GPU that can't reach the chosen speed took all 40 steps before each
      draw.
    - The headless check runs about 17x real time. The window draws at
      about 150 fps, still 42 fps at 10x.
    - **On the P620** (Radeon Pro W6600, 2026-11-17; `spinecheck
      --time=20`, pulsation on, the output identical on both drivers):
      - Mesa rusticl: 18.7 s, about real time. The window at the default
        x5 drew 2.4-3 fps before the step budget and 22-27 fps with it.
      - AMD ROCm OpenCL 7.2.4 (`rocm-opencl` from repo.radeon.com, device
        `gfx1032`): 4.3 s. The window draws 38 fps and simulates 90 s in
        20 s of wall time.
      - On rusticl the cost is the launches, not the arithmetic: about
        50 us for each of a step's hundred-odd kernels, 90 of them
        pressure half-sweeps. Halving the cells a half-sweep visits gave
        4 %, and an explicit work-group size nothing.
    - `Advance` accumulates a Single `Time`, so loop on
      `T < tEnd - 0.5 Dt`, not `T < tEnd`. The plain test once never
      ended.
  - **Results** (3 mL over 15 s at L3-4, 25G, jet cephalad; without
    pulsation - see above for what it changes):
    - **Supine**: at 120 s the hyperbaric solution covers S2-T5,
      pooling in the sacrum and the T6-T9 kyphosis, and reaches T3 (C 1 %)
      by about 4 min. Plain stays at L5-T12.
    - **Sitting**, 120 s: hyperbaric S2-L1; plain rises to T11.
    - **Left lateral**, 120 s: hyperbaric S2-T7.
  - **Left out**: the pressure rise an injection causes and how it shares
    the compliance (a fixed 2/3 to the head), the pulse's real waveform,
    and compliance that varies along the canal.
    The cauda equina drag (`RootsDrag` 5 /s on `FlagRoots` cells, a check
    box) is a guess and off by default.
  - **Command line**:
    - `--snapshot=<prefix> --time=<s>` saves the view, the profile plot
      (mL per level, a `TVMPlot2D`) and the window, prints the memo and
      exits.
    - `--autorun=<s> [--png=<file>]` runs interactively for s seconds of
      wall time and prints the fps.
    - Also `--tilt --roll --sol0 --sol1 --level --speed --pulse=0
      --displace=0 --diff=<0..4> --tab=method` (`--diff` an index into
      the diffusion list).
  - `GlassSpine.lpr` has no `{$R *.res}`: an empty `.res` broke the
    resource compile.
  - FPC duplicate identifiers hit again: `T`/`t`, `l`/`L`, and `Color`,
    `Caption`, `Parent` and `Tag` as parameters on a control or form.
