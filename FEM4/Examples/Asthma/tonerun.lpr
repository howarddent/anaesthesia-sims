program tonerun;

{ Stage 4: airway tone that answers to tidal stretch (the mechanism of
  Venegas et al., Nature 2005, built on Fredberg's perturbed
  equilibrium of myosin binding: tidal stretching of airway smooth
  muscle detaches cross-bridges, so a muscle that is stretched each
  breath develops less force than one held still).

  The patchy lung of uPatchyLung in activation mode: every unit has the
  case's wall thickening and lining, and its own muscle activation a_u,
  one of the levels 0, 0.05, .. 0.9. After each breath every unit's
  activation relaxes towards
     a*_u = Act0 Sev_u (1 - Fmax e_u^2 / (e_u^2 + e50^2)),
     a_u <- a_u + (a*_u - a_u) (1 - exp(-Ttot / Tau)),
  e_u the unit's tidal volume strain (tidal volume over end-expiratory
  volume, standing for the airway's tidal stretch, which the parenchyma
  imposes through tethering), Sev_u a small clustered spread (sigma 0.1)
  to break the symmetry gravity leaves. Assumed: Fmax 0.75 (a muscle
  held still develops four times the force of one at full tidal
  stretch), e50 0.1 (half of a normal unit's 0.2 in fast breathing),
  Tau 20 s.
  A unit that is poorly ventilated stretches less, contracts more and
  narrows further: positive feedback, which can make a lung with almost
  the same constriction everywhere split into units that are shut and
  units that carry the breath.

  Protocol (a bronchial challenge): fast breathing (30 /min, Ti/Ttot
  1/3, the drive adjusted breath by breath towards 600 mL), the dose
  Act0 raised 0.3, 0.45, 0.6, 0.75, 0.9 every 40 breaths. Four runs:
  moderate (wall x 1.5, lining x 1.5) and severe (x 1.75, x 2) walls,
  each with the feedback on and off (Fmax 0: activation Act0 Sev_u).
  --sigh: one deep breath half-way through each dose (peak muscle
  pressure --sighp, 30 cmH2O, for that breath; the drive control skips
  it). Options: --doses=<a,b,..> (the doses in turn; a single high dose is a
  sudden exposure), --tag=<s> (added to the file names), --only=<run>, --breaths=<per dose> (40), --rest (15 /min,
  500 mL), --fmax, --e50, --tau, --sigma, --seed, --dt (0.004),
  --out (out).
  Writes <out>/tone_<run>.csv (one row per breath) and
  <out>/tone_<run>_units.csv (each unit's activation and ventilation at
  the end of every dose).

  Build:  fpc -O3 -FUlib -Fu../../../newVM -Fi../../../newVM tonerun.lpr }

{$mode delphi}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Classes, Math, cblas, newVM, uTubeLaw, uAirwayRing, uAlveolus, uLungModel, uPatchyLung;

type
  TMuscles = class
  public
    Pmax, Ti, Ttot, Tau: Double;
    function P(t, V: Double): Double;
  end;

function TMuscles.P(t, V: Double): Double;
var
  tb: Double;
begin
  tb := t - Ttot * Floor(t / Ttot + 1e-9);
  if tb < Ti then Result := Pmax * Sin(0.5 * Pi * tb / Ti)
  else Result := Pmax * Exp(-(tb - Ti) / Tau);
end;

type
  TRun = record
    Name: string;
    Thick, Mucus, Fmax: Double;
  end;

var
  Doses: array of Double;

var
  OutDir: string = 'out';
  Tag: string = '';
  Sigh: Boolean = False;
  SighP: Double = 30;
  Dt: Double = 0.004;
  PerDose: Integer = 40;
  Rest: Boolean = False;
  Fmax: Double = 0.75;
  E50: Double = 0.1;
  TauA: Double = 20;
  Prm: TLungParams;
  Alv: TAlveolusParams;
  PPBase: TPatchyParams;
  RefLaws: array[0..NWall - 1] of TTubeLaw;

function OptVal(const Name: string; var V: Double): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 1 to ParamCount do
    if Pos('--' + Name + '=', ParamStr(i)) = 1 then
    begin
      V := StrToFloat(Copy(ParamStr(i), Length(Name) + 4, MaxInt));
      Result := True;
    end;
end;

function OptStr(const Name: string; var V: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 1 to ParamCount do
    if Pos('--' + Name + '=', ParamStr(i)) = 1 then
    begin
      V := Copy(ParamStr(i), Length(Name) + 4, MaxInt);
      Result := True;
    end;
end;

function HasOpt(const Name: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 1 to ParamCount do
    if ParamStr(i) = '--' + Name then Result := True;
end;

function Cm(p: Double): Double;
begin
  Result := p / CmH2O;
end;

function Signed(x: Double): string;
begin
  if x >= 0 then Result := '+' + Format('%.0f', [x]) else Result := Format('%.0f', [x]);
end;

procedure DoRun(const R: TRun);
var
  PP: TPatchyParams;
  A: TAsthma;
  L: TPatchyLung;
  Sim: TPatchySim;
  Mus: TMuscles;
  NU, u, d, b, k, st, n, nl, nShut, nTrap, nDef, nHi: Integer;
  VFRC, VMax, VMin, Act, E, vprev: array of Double;
  shut: array of Boolean;
  pSave: Double;
  isSigh: Boolean;
  frc, vtT, vt, eelv, peepi, Wk, svMean, svSq, defV, aMean, tgt, rel, vlung, pplMin, x: Double;
  F, FU: TStringList;
  t1: QWord;
begin
  t1 := GetTickCount64;
  PP := PPBase;
  PP.ActMode := True; PP.DS := 0.05; PP.SMax := 0.9;
  A.Act := Doses[0]; A.Thick := R.Thick; A.Mucus := R.Mucus;
  Writeln(Format('=== %s: wall x %.2f, lining x %.1f, Fmax %.2f, e50 %.2f, tau %.0f s, sigma %.2f',
    [R.Name, R.Thick, R.Mucus, R.Fmax, E50, TauA, PP.Sigma]));
  L := TPatchyLung.Create(Prm, PP, A, Alv, RefLaws);
  NU := L.NU; nl := L.LevelCount;
  SetLength(VFRC, NU); SetLength(VMax, NU); SetLength(VMin, NU); SetLength(Act, NU);
  SetLength(E, NU); SetLength(vprev, NU); SetLength(shut, NU);
  L.StaticState(0, VFRC);
  frc := Prm.VDead;
  for u := 0 to NU - 1 do
  begin
    frc := frc + VFRC[u];
    Act[u] := Min(PP.SMax, Doses[0] * L.Sev[u]);
  end;
  Mus := TMuscles.Create;
  if Rest then begin Mus.Ttot := 4; vtT := 0.5; Mus.Pmax := 6; Mus.Tau := 0.3; end
  else begin Mus.Ttot := 2; vtT := 0.6; Mus.Pmax := 9; Mus.Tau := 0.15; end;
  Mus.Ti := Mus.Ttot / 3;
  for u := 0 to NU - 1 do L.Level[u] := EnsureRange(Round(Act[u] / PP.DS), 0, nl - 1);
  Sim := TPatchySim.Create(L, Mus.P, VFRC, Dt);
  n := Round(Mus.Ttot / Dt);
  F := TStringList.Create;
  F.Add('breath,t_s,dose,act_mean,units_act_ge_0p6,EELV_L,EELV_above_FRC_mL,PEEPi_cmH2O,VT_mL,Pmus_peak_cmH2O,'
    + 'Ppl_min_cmH2O,work_J_per_min,CV_SV,defect_vol_pct,units_shut,units_trapped');
  FU := TStringList.Create;
  FU.Add('dose,u,x_cm,y_cm,act,V_EE_mL,VT_mL,strain');
  b := 0;
  for d := 0 to High(Doses) do
  begin
    for k := 1 to PerDose do
    begin
      Inc(b);
      for u := 0 to NU - 1 do
      begin
        VMax[u] := Sim.V[u]; VMin[u] := Sim.V[u]; shut[u] := True;
      end;
      Wk := 0; pplMin := 1e9;
      vlung := Sim.VTot; vt := 0;
      isSigh := Sigh and (k = PerDose div 2);
      if isSigh then begin pSave := Mus.Pmax; Mus.Pmax := SighP; end;
      for st := 1 to n do
      begin
        x := Sim.VTot;
        Sim.Step;
        if Sim.VTot > x then Wk := Wk + Sim.Pmus * (Sim.VTot - x);
        vt := Max(vt, Sim.VTot - vlung);
        pplMin := Min(pplMin, Cm(Sim.Ppl));
        for u := 0 to NU - 1 do
        begin
          VMax[u] := Max(VMax[u], Sim.V[u]); VMin[u] := Min(VMin[u], Sim.V[u]);
          if L.Qu[u] <> 0 then shut[u] := False;
        end;
      end;
      eelv := Sim.VTot;
      peepi := 0;
      for u := 0 to NU - 1 do peepi := peepi + Cm(L.Pu[u]) * Sim.V[u];
      peepi := peepi / (eelv - Prm.VDead);
      svMean := 0;
      for u := 0 to NU - 1 do
      begin
        E[u] := (VMax[u] - VMin[u]) / Max(1e-12, VMin[u]);
        svMean := svMean + E[u] * VMin[u];
      end;
      svMean := svMean / (eelv - Prm.VDead);
      svSq := 0; defV := 0; nShut := 0; nTrap := 0; nHi := 0; aMean := 0;
      for u := 0 to NU - 1 do
      begin
        svSq := svSq + Sqr(E[u] - svMean) * VMin[u];
        if E[u] < 0.5 * svMean then defV := defV + VMin[u];
        if shut[u] then Inc(nShut);
        if Sim.V[u] > 1.1 * VFRC[u] then Inc(nTrap);
        aMean := aMean + Act[u] / NU;
        if Act[u] >= 0.6 - 1e-9 then Inc(nHi);
      end;
      F.Add(Format('%d,%.2f,%.2f,%.4f,%d,%.4f,%.1f,%.3f,%.1f,%.3f,%.3f,%.3f,%.4f,%.2f,%d,%d',
        [b, Sim.T, Doses[d], aMean, nHi, eelv, 1000 * (eelv - frc), peepi, 1000 * vt, Mus.Pmax, pplMin,
         60 / Mus.Ttot * Wk * JPerCmH2OL, Sqrt(svSq / (eelv - Prm.VDead)) / svMean,
         100 * defV / (eelv - Prm.VDead), nShut, nTrap]));
      { the muscles of the airways: relax towards their targets }
      rel := 1 - Exp(-Mus.Ttot / TauA);
      for u := 0 to NU - 1 do
      begin
        tgt := Doses[d] * L.Sev[u] * (1 - R.Fmax * Sqr(E[u]) / (Sqr(E[u]) + Sqr(E50)));
        Act[u] := Act[u] + (tgt - Act[u]) * rel;
        L.Level[u] := EnsureRange(Round(Min(PP.SMax, Act[u]) / PP.DS), 0, nl - 1);
      end;
      { the drive, towards the target tidal volume }
      if isSigh then
      begin
        Mus.Pmax := pSave;
        Writeln(Format('    deep breath at breath %d: %.0f mL; %d units shut through it', [b, 1000 * vt, nShut]));
      end
      else if vt > 1e-4 then Mus.Pmax := EnsureRange(Mus.Pmax * Power(vtT / vt, 0.4), 1, 60)
      else Mus.Pmax := Min(60, 1.5 * Mus.Pmax);
      if k = PerDose then
      begin
        Writeln(Format('  dose %.2f (breath %3d): activation mean %.2f, %3d units >= 0.6; EELV %.2f L (FRC %s mL), PEEPi %.1f cmH2O; VT %.0f mL at Pmus %.1f; Ppl lowest %.1f; work %.1f J/min',
          [Doses[d], b, aMean, nHi, eelv, Signed(1000 * (eelv - frc)), peepi, 1000 * vt, Mus.Pmax, pplMin,
           60 / Mus.Ttot * Wk * JPerCmH2OL]));
        Writeln(Format('      ventilation: CV %.2f, defects %.0f %% of lung volume, %d units shut all breath, %d trapped',
          [Sqrt(svSq / (eelv - Prm.VDead)) / svMean, 100 * defV / (eelv - Prm.VDead), nShut, nTrap]));
        for u := 0 to NU - 1 do
          FU.Add(Format('%.2f,%d,%.3f,%.3f,%.4f,%.4f,%.4f,%.5f', [Doses[d], u, L.PX[u], L.PY[u], Act[u],
            1000 * VMin[u], 1000 * (VMax[u] - VMin[u]), E[u]]));
      end;
    end;
  end;
  F.SaveToFile(Format('%s/tone_%s%s.csv', [OutDir, R.Name, Tag]));
  FU.SaveToFile(Format('%s/tone_%s%s_units.csv', [OutDir, R.Name, Tag]));
  F.Free; FU.Free;
  Sim.Free; Mus.Free; L.Free;
  Writeln(Format('  (%.0f s)', [(GetTickCount64 - t1) / 1000]));
  Writeln;
end;

var
  Runs: array[0..3] of TRun;
  i: Integer;
  notes, only: string;
  d: Double;
begin
  InitializeCBLAS;
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  DefaultFormatSettings.DecimalSeparator := '.';
  OptStr('out', OutDir);
  ForceDirectories(OutDir);
  OptVal('dt', Dt);
  d := PerDose; if OptVal('breaths', d) then PerDose := Round(d);
  Rest := HasOpt('rest');
  Sigh := HasOpt('sigh');
  OptVal('sighp', SighP);
  OptVal('fmax', Fmax);
  OptVal('e50', E50);
  OptVal('tau', TauA);
  PPBase := DefaultPatchyParams;
  PPBase.Sigma := 0.1;
  OptVal('sigma', PPBase.Sigma);
  d := PPBase.Seed; if OptVal('seed', d) then PPBase.Seed := Round(d);
  Prm := DefaultLungParams;
  Alv := FitAlveolus(Prm.PTLC * CmH2O, Prm.PSalineTLC * CmH2O, 0.126);
  BuildWallLaws(NormalAsthma, RefLaws, notes);
  only := '0.3,0.45,0.6,0.75,0.9';
  OptStr('doses', only);
  with TStringList.Create do
  try
    CommaText := only;
    SetLength(Doses, Count);
    for i := 0 to Count - 1 do Doses[i] := StrToFloat(Strings[i]);
  finally
    Free;
  end;
  Runs[0].Name := 'moderate_off'; Runs[0].Thick := 1.5; Runs[0].Mucus := 1.5; Runs[0].Fmax := 0;
  Runs[1].Name := 'moderate_on'; Runs[1].Thick := 1.5; Runs[1].Mucus := 1.5; Runs[1].Fmax := Fmax;
  Runs[2].Name := 'severe_off'; Runs[2].Thick := 1.75; Runs[2].Mucus := 2; Runs[2].Fmax := 0;
  Runs[3].Name := 'severe_on'; Runs[3].Thick := 1.75; Runs[3].Mucus := 2; Runs[3].Fmax := Fmax;
  only := '';
  OptStr('only', only);
  OptStr('tag', Tag);
  for i := 0 to High(Runs) do
    if (only = '') or (only = Runs[i].Name) then DoRun(Runs[i]);
  for i := 0 to NWall - 1 do RefLaws[i].Free;
end.
