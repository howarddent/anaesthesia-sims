program lvrun;

{ The left ventricle through the cardiac cycle: a finite-element wall
  with Hill-type fibres (uLVMech) filled from a left atrium through the
  mitral valve and ejecting through the aortic valve into the aortic
  root and a Windkessel (uLVCirc). See those units' headers.

  Options (defaults in brackets):
    --beats=<n>      cycles to run [8]; the last is reported and written
    --dt=<s>         time step [0.002]
    --mesh=<r,l,c>   elements through the wall, apex to base, round [3,10,16]
    --hr=<1/min>     heart rate [70]
    --kvc=<k>        aortic valve's closing rate, 1/(mmHg s) [16]; lower
                     gives more backflow before it shuts
    --nosnap         Mynard's closing law for the aortic valve (Kvc 26.7)
    --csv=<file>     write the last beat (t, pressures, volumes, flows, ...)
    --anim=<file>    write the last beat's motion for LVView: the wall's
                     state every --animevery steps [2], and the samples
    --fitpassive     scale C to put the passive pressure at EDV on the
                     Klotz relation, print the curve and stop
    --edv --edp      the fit's end-diastolic volume, mL [125] and pressure, mmHg [9]
    --passive        fill passively to --edv, print the shape ring by ring and stop
    --rings          print the final state ring by ring
    --sync           the whole wall depolarises at once
    --threads=<n>    threads for the element loop [8]
    --profile        time spent in assembly and solution, beat by beat
    parameter overrides:
      geometry   --v0 --wall (mL)  --length (mm)  --aendo --aepi (deg)
      passive    --c (kPa)  --kappa (kPa)
      active     --t0 (kPa)  --ls0 (um)  --cross  --b --taur --taud (s)  --v0c (um/s)
      circuit    --ppv (mmHg)  --rp (mmHg s/mL)  --cwk (mL/mmHg)
      solver     --tol  --mtype  --mkl  --nopredictor  --verbose

  --arteries       eject into the arterial tree (../Aorta) in place of
                   the Windkessel, coupled both ways at the valve: see
                   ../Aorta/uAortaAfterload. Its options:
      --stiff --stiffother   elastance x of the aorta and carotid, of the rest [1, 1]
      --rtot=<R>       total peripheral resistance, mmHg s/mL [1.147]
      --pvr=<x>        multiplies it: vasoconstriction above 1, dilatation below [1]
      --size=<x>       body size: every arterial length and radius x [1]
      --flow=<x>       valve flow x on its way into the tree [1]
      --cperiph=<C>    compliance of the beds, mL/mmHg [0.8]
      --walltau=<ms>   wall retardation time [5]
      --settle=<n>     tree-only beats between ventricle beats [6; 25 after the first]

  Build:  fpc -O3 -FUlib -Fu../../../newVM -Fi../../../newVM -Fu../Aorta lvrun.lpr }

{$mode delphi}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, StrUtils, Math, cblas, newVM, newVMsparse, uAortaAfterload,
  uLVMech, uLVCirc, uLVHeart;

type
  { hands each accepted ventricle step on to the arterial tree }
  TCoupling = class
    Heart: TLVHeart;
    Art: TAortaAfterload;
    procedure Step(dt: Double);
  end;

procedure TCoupling.Step(dt: Double);
begin
  Art.Advance(dt, Heart.Circ.S.QAV);
end;


function Opt(const Name: string; Def: Double): Double;
var
  i: Integer;
begin
  Result := Def;
  for i := 1 to ParamCount do
    if StartsText('--' + Name + '=', ParamStr(i)) then
      Result := StrToFloat(Copy(ParamStr(i), Length(Name) + 4, MaxInt));
end;

function OptS(const Name, Def: string): string;
var
  i: Integer;
begin
  Result := Def;
  for i := 1 to ParamCount do
    if StartsText('--' + Name + '=', ParamStr(i)) then
      Result := Copy(ParamStr(i), Length(Name) + 4, MaxInt);
end;

function Flag(const Name: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 1 to ParamCount do
    if SameText('--' + Name, ParamStr(i)) then Result := True;
end;

var
  G: TLVGeom;
  Mat: TLVMaterial;
  H: TLVHeart;
  S: THeartSamples;
  B: TBeatSummary;
  beat, i, nBeats: Integer;
  dt, edv, edp, p, v, vn, t0: Double;
  mesh, csv: string;
  parts: TStringArray;
  f: TextFile;
  tick: QWord;
  Cpl: TCoupling;
  Art: TAortaAfterload;
  nSettle: Integer;
  svPrev: Double;
begin
  InitializeCBLAS;
  FormatSettings.DecimalSeparator := '.';
  SetMKLThreads(Round(Opt('mkl', 1)));
  G := AdultGeometry(Opt('v0', 68), Opt('wall', 118), Opt('length', 75));
  mesh := OptS('mesh', '');
  if mesh <> '' then
  begin
    parts := mesh.Split([',']);
    G.NR := StrToInt(parts[0]); G.NL := StrToInt(parts[1]); G.NC := StrToInt(parts[2]);
  end;
  Mat := DefaultMaterial;
  Mat.C := Opt('c', Mat.C);
  Mat.T0 := Opt('t0', Mat.T0);
  Mat.CrossFibre := Opt('cross', Mat.CrossFibre);
  Mat.Kappa := Opt('kappa', Mat.Kappa);
  Mat.b := Opt('b', Mat.b); Mat.tauR := Opt('taur', Mat.tauR); Mat.tauD := Opt('taud', Mat.tauD);
  Mat.v0 := Opt('v0c', Mat.v0);
  Mat.ls0 := Opt('ls0', Mat.ls0);
  G.AlphaEndo := Opt('aendo', G.AlphaEndo); G.AlphaEpi := Opt('aepi', G.AlphaEpi);
  if Flag('sync') then begin Mat.TApexBase := 0; Mat.TTransmural := 0; end;
  H := TLVHeart.Create(G, Mat);
  H.Model.Verbose := Flag('verbose');
  H.Model.Threads := Round(Opt('threads', 8));
  H.Model.MType := Round(Opt('mtype', 11));
  H.Model.Tolerance := Opt('tol', 1e-7);
  H.Model.Predictor := not Flag('nopredictor');
  H.Circ.Period := 60 / Opt('hr', 70);
  H.Circ.PPv := Opt('ppv', H.Circ.PPv);
  H.Circ.Rp := Opt('rp', H.Circ.Rp);
  H.Circ.CWk := Opt('cwk', H.Circ.CWk);
  H.Circ.Aortic.Kvc := Opt('kvc', H.Circ.Aortic.Kvc);
  if Flag('nosnap') then
  begin
    H.Circ.Aortic.SnapShut := False;
    H.Circ.Aortic.Kvc := Opt('kvc', 26.7);
  end;
  Writeln(Format('Unloaded ventricle: cavity %.1f mL, wall %.1f mL (%.0f g)',
    [H.Model.CavityVolume / 1000, H.Model.WallVolume / 1000, H.Model.WallVolume / 1000 * 1.055]));
  Writeln(Format('  endocardium %.1f x %.1f mm (short, long semi-axes), base %.1f mm above the equator',
    [G.AEn, G.CEn, G.ZB]));
  Writeln(Format('  wall %.1f mm at the equator, %.1f mm at the apex; %d elements, %d nodes',
    [G.AEp - G.AEn, G.CEp - G.CEn, H.Model.NE, H.Model.NN]));

  if Flag('fitpassive') then
  begin
    edv := Opt('edv', 125); edp := Opt('edp', 9);
    H.InflateToVolume(edv, 12);
    Writeln(Format('  %d assemblies: %.2f s (elements %.2f s), sparse build %.2f s, PARDISO %.2f s',
      [H.Model.NAssemble, H.Model.TimeAssemble, H.Model.TimeElems, H.Model.TimeSparse, H.Model.TimeSolve]));
    p := H.Model.Pcav / mmHg;
    Writeln(Format('C = %.4f kPa gives %.2f mmHg at %.0f mL; C = %.4f kPa gives %.1f mmHg',
      [Mat.C, p, edv, Mat.C * edp / p, edp]));
    Mat.C := Mat.C * edp / p;
    H.Free;
    H := TLVHeart.Create(G, Mat);
    H.Model.Verbose := Flag('verbose');
    H.Model.Threads := Round(Opt('threads', 8));
    { Klotz et al. 2006: (V - V0)/(V30 - V0) = (P/27.78)^(1/2.76) }
    v := H.Model.CavityVolume / 1000;
    vn := v + (edv - v) / Power(edp / 27.78, 1 / 2.76);
    Writeln(Format('Klotz: V0 %.1f mL, V30 %.1f mL (V0 predicted from EDV, EDP: %.1f mL)',
      [v, vn, edv * (0.6 - 0.006 * edp)]));
    Writeln('   P mmHg   V model   V Klotz');
    for i := 1 to 10 do
    begin
      H.InflateToPressure(3.0 * i, 2);
      Writeln(Format('   %6.1f   %7.1f   %7.1f', [3.0 * i, H.Model.CavityVolume / 1000,
        v + (vn - v) * Power(3.0 * i / 27.78, 1 / 2.76)]));
    end;
    Halt;
  end;

  if Flag('passive') then
  begin
    H.InflateToVolume(Opt('edv', 125), 12);
    Writeln(Format('Passive: %.2f mmHg at %.1f mL; wall %.2f mm, long axis %.2f mm',
      [H.Model.Pcav / mmHg, H.Model.CavityVolume / 1000, H.Model.WallThickness(H.JMid), H.Model.LongAxis]));
    Writeln('Ring by ring (apex to base): z mm, endocardial radius mm, rotation endo, epi deg');
    for i := 1 to G.NL do
      Writeln(Format('  %2d  %7.2f  %6.2f  %7.2f  %7.2f', [i,
        H.Model.X[3 * H.Model.NodeId(0, i, 0) + 2] + H.Model.U[3 * H.Model.NodeId(0, i, 0) + 2],
        H.Model.EndoRadius(i), H.Model.RingRotation(0, i) * 180 / Pi,
        H.Model.RingRotation(G.NR, i) * 180 / Pi]));
    Halt;
  end;
  dt := Opt('dt', 0.002);
  nBeats := Round(Opt('beats', 8));
  Art := nil; Cpl := nil; svPrev := 0;
  nSettle := Round(Opt('settle', 6));
  if Flag('arteries') then
  begin
    Art := TAortaAfterload.Create;
    Art.Sim.AorticStiff := Opt('stiff', 1);
    Art.Sim.OtherStiff := Opt('stiffother', 1);
    Art.Sim.RTotal := Opt('rtot', Art.Sim.RTotal);
    Art.Sim.RFactor := Opt('pvr', 1);
    Art.Sim.Size := Opt('size', 1);
    Art.Sim.CPeriph := Opt('cperiph', Art.Sim.CPeriph);
    Art.Sim.WallTau := Opt('walltau', Art.Sim.WallTau);
    Art.Scale := Opt('flow', 1);
    Art.Extrapolate := not Flag('noextrap');
    Art.WallViscous := not Flag('noviscroot');
    Art.Start(H.Circ.Period);
    Cpl := TCoupling.Create;
    Cpl.Heart := H; Cpl.Art := Art;
    H.Circ.Afterload := Art.RootPressure;
    H.OnStep := Cpl.Step;
    Writeln(Format('Ejecting into the arterial tree: peripheral resistance %.3f mmHg s/mL, valve flow x %.2f',
      [Art.RUsed, Art.Scale]));
  end;
  { start at end diastole: filled passively, the atrium at the same pressure }
  H.InflateToVolume(Opt('edv', 125), 12);
  H.Circ.S.VLA := H.Circ.LAV0 + H.Model.Pcav / mmHg / H.Circ.LAElastance(0);
  Writeln(Format('Start: %.1f mmHg, %.1f mL', [H.Model.Pcav / mmHg, H.Model.CavityVolume / 1000]));
  Writeln(' beat    EDV    ESV     SV    EF    CO   EDP  LVmax  Ao sys/dia   mean  LAmean  its/step   s');
  Flush(Output);
  for beat := 1 to nBeats do
  begin
    if (beat = nBeats) and (OptS('anim', '') <> '') then
      H.FrameEvery := Max(1, Round(Opt('animevery', 2)));
    tick := GetTickCount64;
    H.Steps := 0; H.NewtonIts := 0;
    if Art <> nil then Art.BeginBeat;
    H.RunBeat(dt, S);
    B := H.Summarise(S);
    Writeln(Format(' %3d  %6.1f %6.1f %6.1f %5.1f %5.2f %5.1f %6.1f  %5.1f/%5.1f %6.1f %6.1f   %5.2f  %5.1f',
      [beat, B.EDV, B.ESV, B.SV, 100 * B.EF, B.CO, B.EDP, B.PeakLV, B.AoSys, B.AoDia, B.AoMean,
       B.PLAMean, H.NewtonIts / H.Steps, (GetTickCount64 - tick) / 1000]));
    if Art <> nil then
    begin
      Writeln(Format('      arteries: root %.1f -> %.1f mmHg over the beat, stroke volume changed by %.2f mL; '
        + 'reflected waves late by at most %.2f mmHg', [S[0].PRoot, S[High(S)].PRoot, B.SV - svPrev, Art.LagError]));
      svPrev := B.SV;
      if beat < nBeats then
        if beat = 1 then Art.Settle(Max(25, nSettle)) else Art.Settle(nSettle);
    end;
    Flush(Output);  { LVView counts these lines for its progress bar }
    if Flag('profile') then
      Writeln(Format('      %d steps; assembly %.1f s, sparse build %.1f s, PARDISO %.1f s (cumulative)',
        [H.Steps, H.Model.TimeAssemble, H.Model.TimeSparse, H.Model.TimeSolve]));
  end;
  Writeln;
  Writeln(Format('End-diastolic volume %.1f mL, end-systolic %.1f mL, stroke volume %.1f mL, EF %.1f %%',
    [B.EDV, B.ESV, B.SV, 100 * B.EF]));
  Writeln(Format('Cardiac output %.2f L/min at %.0f /min', [B.CO, 60 / H.Circ.Period]));
  Writeln(Format('LV pressure: end-diastolic %.1f, peak %.1f mmHg; dP/dt max %.0f, min %.0f mmHg/s',
    [B.EDP, B.PeakLV, B.DPDtMax, B.DPDtMin]));
  Writeln(Format('Aortic root: %.1f / %.1f mmHg, mean %.1f; peak valve flow %.0f mL/s; ejection %.0f - %.0f ms',
    [B.AoSys, B.AoDia, B.AoMean, B.PeakFlow, 1000 * B.EjectStart, 1000 * B.EjectEnd]));
  Writeln(Format('Mean left atrial pressure %.1f mmHg', [B.PLAMean]));
  Writeln(Format('Equatorial wall thickness %.1f -> %.1f mm (%.0f %% thickening); long axis %.1f -> %.1f mm (%.1f %%)',
    [B.ThickED, B.ThickES, 100 * (B.ThickES / B.ThickED - 1), B.LongED, B.LongES, 100 * (1 - B.LongES / B.LongED)]));
  Writeln(Format('Mean fibre stretch %.3f -> %.3f (sarcomere %.2f -> %.2f um, shortening %.1f %%)',
    [B.StretchED, B.StretchES, Mat.ls0 * B.StretchED, Mat.ls0 * B.StretchES,
     100 * (1 - B.StretchES / B.StretchED)]));
  Writeln(Format('Apical slice rotation relative to the base: %.1f deg at end diastole, peak systolic twist %.1f deg beyond that',
    [B.TwistED, B.PeakTwist]));
  if Flag('rings') then
  begin
    Writeln('Final state, ring by ring (apex to base): z mm, endocardial radius mm, rotation endo, epi deg');
    for i := 1 to G.NL do
      Writeln(Format('  %2d  %7.2f  %6.2f  %7.2f  %7.2f', [i,
        H.Model.X[3 * H.Model.NodeId(0, i, 0) + 2] + H.Model.U[3 * H.Model.NodeId(0, i, 0) + 2],
        H.Model.EndoRadius(i), H.Model.RingRotation(0, i) * 180 / Pi,
        H.Model.RingRotation(G.NR, i) * 180 / Pi]));
  end;
  csv := OptS('csv', '');
  if csv <> '' then
  begin
    AssignFile(f, csv); Rewrite(f);
    Writeln(f, 't_s,PLV_mmHg,VLV_mL,PLA_mmHg,VLA_mL,Qmitral_mL_s,Qaortic_mL_s,Proot_mmHg,Qroot_out_mL_s,' +
      'Pwk_mmHg,zeta_mitral,zeta_aortic,fibre_stretch,active_stress_kPa,twist_deg,wall_mm,radius_mm,long_axis_mm');
    for i := 0 to High(S) do
      Writeln(f, Format('%.5f,%.4f,%.4f,%.4f,%.4f,%.3f,%.3f,%.4f,%.3f,%.4f,%.5f,%.5f,%.5f,%.3f,%.3f,%.3f,%.3f,%.3f',
        [S[i].T, S[i].PLV, S[i].VLV, S[i].PLA, S[i].VLA, S[i].QMV, S[i].QAV, S[i].PRoot, S[i].QAo,
         S[i].PWk, S[i].ZMV, S[i].ZAV, S[i].Stretch, S[i].Tact, S[i].Twist, S[i].Thick, S[i].Radius, S[i].LongAx]));
    CloseFile(f);
    Writeln('Last beat written to ', csv);
  end;
  if OptS('anim', '') <> '' then
  begin
    H.WriteAnim(OptS('anim', ''), S);
    Writeln(Format('Last beat''s motion (%d frames) written to %s', [Length(H.FrameSample), OptS('anim', '')]));
  end;
  H.Free;
end.
