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
    3.2 iterations a step and 19-35 s a beat.
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
