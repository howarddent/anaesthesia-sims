program patchyrun;

{ The patchy lung (uPatchyLung): 2^K units with log-normal severities
  clustered down the tree, upright with a pleural pressure gradient.
  For each case, as lungrun does for the symmetric lung:

  STATIC     FRC, and how many units' small airways are shut there.
  FORCED EXPIRATION   from TLC, effort as in lungrun: PEF, FEV1, FVC,
             RV, MEF50, FEV1/FVC.
  TIDAL BREATHING     at rest (15 /min, 500 mL) and fast (30 /min,
             600 mL), the peak muscle pressure adjusted (bracketed
             secant, as lungrun) until the breath repeats. Then: EELV
             against FRC; volume-weighted mean alveolar pressure at end
             expiration (intrinsic PEEP); pleural pressure; the work of
             the inspiratory muscles, elastic (lung, chest wall and the
             gravitational term) and resistive; and the distribution of
             ventilation. A unit's specific ventilation is its tidal
             volume over its end-expiratory volume; a VENTILATION DEFECT
             here is a unit below half the mean specific ventilation (my
             threshold: imaging studies use 60 % of the mean signal and
             others). Reported: the defects' share of units and of lung
             volume, the CV of specific ventilation, units shut all
             breath, units trapped (end-expiratory volume more than 10 %
             above their static FRC volume).

  Cases: normal; moderate asthma (activation 0.3, wall x 1.5, lining
  x 1.5) uniform, and patchy with sigma 0.5 and 1.0; severe (0.5, 1.75,
  2) uniform and patchy with sigma 0.5. The patchy cases have the same
  mean severity as the uniform ones.
  Options: --k=<K> (8: 256 units), --seed=<n> (1), --gravity=<cmH2O/cm>
  (0.2), --sigma=<s> with --act/--thick/--mucus for a custom case,
  --only=<name>, --dt=<s> (0.004), --verbose, --out=<dir> (out).
  Writes <out>/patchy_<case>_units.csv (one row per unit), _fv.csv,
  _rest.csv, _fast.csv.

  Build:  fpc -O3 -FUlib -Fu../../../newVM -Fi../../../newVM patchyrun.lpr }

{$mode delphi}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Classes, Math, cblas, newVM, uTubeLaw, uAirwayRing, uAlveolus, uLungModel, uPatchyLung;

type
  TCase = record
    Name: string;
    A: TAsthma;
    Sigma: Double;
  end;

  TMuscles = class
  public
    Mode: Integer;
    Effort, TLC: Double;
    Pmax, Ti, Ttot, Tau: Double;
    function P(t, V: Double): Double;
  end;

function TMuscles.P(t, V: Double): Double;
var
  pe, tb: Double;
begin
  if Mode = 0 then
  begin
    pe := 40 + 120 * Max(0, V - 1.3) / (TLC - 1.3);
    Result := -Effort * pe * (1 - Exp(-t / 0.03));
  end
  else
  begin
    tb := t - Ttot * Floor(t / Ttot + 1e-9);
    if tb < Ti then Result := Pmax * Sin(0.5 * Pi * tb / Ti)
    else Result := Pmax * Exp(-(tb - Ti) / Tau);
  end;
end;

const
  PatName: array[0..1] of string = ('rest', 'fast');

var
  OutDir: string = 'out';
  Dt: Double = 0.004;
  Verbose: Boolean = False;
  Alv: TAlveolusParams;
  Prm: TLungParams;
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

function LpS(q: Double): Double;
begin
  Result := q / LitreMM3;
end;

function Signed(x: Double): string;
begin
  if x >= 0 then Result := '+' + Format('%.0f', [x]) else Result := Format('%.0f', [x]);
end;

procedure RunCase(const C: TCase);
var
  PP: TPatchyParams;
  L: TPatchyLung;
  Sim: TPatchySim;
  Mus: TMuscles;
  NU, u, k, n, pat, breath, m, nclFRC, i: Integer;
  V0, VFRC, VEE, VMax, VMin, vprev: array of Double;
  frc, pplFRC, pef, fev1, fvc, rv, mef50, target, vt, vtT, eelv, eelvOld, Wk, Wres, Wel,
  dvt, pplMin, peepi, sv, svMean, svSq, defU, defV, vtot, frac, pLo, pHi, vLo, vHi, pn, pelEE: Double;
  limN, expN, nShut, nTrap, nDefect, t1: QWord;
  vs, vl: array of Double;
  F: TStringList;
  s: string;
  t0: Double;
  SV_: array of Double;
  shutAll: array of Boolean;
begin
  t1 := GetTickCount64;
  PP := PPBase;
  PP.Sigma := C.Sigma;
  Writeln('=== ', C.Name, Format(' (activation %.2f, wall x %.2f, lining x %.1f; sigma %.2f)',
    [C.A.Act, C.A.Thick, C.A.Mucus, C.Sigma]));
  L := TPatchyLung.Create(Prm, PP, C.A, Alv, RefLaws);
  if L.Notes <> '' then Writeln('  tube laws: ', L.Notes);
  NU := L.NU;
  SetLength(V0, NU); SetLength(VFRC, NU); SetLength(VEE, NU); SetLength(VMax, NU); SetLength(VMin, NU);
  SetLength(vprev, NU); SetLength(SV_, NU); SetLength(shutAll, NU);
  Mus := TMuscles.Create;

  { static }
  pplFRC := L.StaticState(0, VFRC);
  frc := Prm.VDead;
  for u := 0 to NU - 1 do frc := frc + VFRC[u];
  nclFRC := 0;
  for u := 0 to NU - 1 do
    if L.UnitPel(VFRC[u]) <= L.Tables[L.Level[u]].PClose then Inc(nclFRC);
  s := '';
  for i := 0 to High(L.Tables) do
    if L.Tables[i] <> nil then
    begin
      k := 0;
      for u := 0 to NU - 1 do if L.Level[u] = i then Inc(k);
      if IsInfinite(L.Tables[i].PClose) and (L.Tables[i].PClose > 0) then
        s := s + Format('  s %.2f: %d (always shut)', [i * PP.DS, k])
      else s := s + Format('  s %.2f: %d', [i * PP.DS, k]);
    end;
  Writeln('  units by severity:', s);
  Writeln(Format('  FRC %.2f L, Ppl at mid-height %.1f cmH2O; %d of %d units shut at FRC',
    [frc, Cm(pplFRC), nclFRC, NU]));

  { forced expiration from TLC: every unit at its static volume with the
    muscles holding TLC }
  Mus.Mode := 0; Mus.Effort := 1; Mus.TLC := Prm.TLC;
  { the inspiratory pressure holding TLC }
  pLo := 0; pHi := 100;
  for k := 1 to 60 do
  begin
    pn := 0.5 * (pLo + pHi);
    L.StaticState(pn, V0);
    vtot := Prm.VDead;
    for u := 0 to NU - 1 do vtot := vtot + V0[u];
    if vtot < Prm.TLC then pLo := pn else pHi := pn;
  end;
  Sim := TPatchySim.Create(L, Mus.P, V0, 0.001);
  pef := 0; fev1 := NaN; m := 0;
  SetLength(vs, 0); SetLength(vl, 0);
  F := TStringList.Create;
  F.Add('t_s,volume_exhaled_L,flow_Lps,Ppl_cmH2O,units_limited,units_shut');
  while Sim.T < 8 do
  begin
    Sim.Step;
    pef := Max(pef, LpS(Sim.Q));
    if IsNan(fev1) and (Sim.T >= 1 - 1e-9) then fev1 := vtot - Sim.VTot;
    SetLength(vs, m + 1); SetLength(vl, m + 1);
    vs[m] := vtot - Sim.VTot; vl[m] := LpS(Sim.Q); Inc(m);
    if Round(Sim.T * 1000) mod 5 = 0 then
      F.Add(Format('%.3f,%.5f,%.5f,%.3f,%d,%d', [Sim.T, vtot - Sim.VTot, LpS(Sim.Q), Cm(Sim.Ppl),
        Sim.NLim, Sim.NClosed]));
    if (Sim.T > 0.3) and (LpS(Sim.Q) < 0.02) then Break;
  end;
  F.SaveToFile(Format('%s/patchy_%s_fv.csv', [OutDir, C.Name]));
  F.Free;
  fvc := vtot - Sim.VTot; rv := Sim.VTot;
  if IsNan(fev1) then fev1 := fvc;
  Sim.Free;
  target := 0.5 * fvc; mef50 := NaN;
  for k := 1 to m - 1 do
    if (vs[k - 1] < target) and (vs[k] >= target) then
    begin
      mef50 := vl[k - 1] + (vl[k] - vl[k - 1]) * (target - vs[k - 1]) / (vs[k] - vs[k - 1]);
      Break;
    end;
  Writeln(Format('  forced expiration: PEF %.2f L/s (%.0f L/min), FEV1 %.2f L, FVC %.2f L, FEV1/FVC %.0f %%, RV %.2f L, MEF50 %.2f L/s',
    [pef, 60 * pef, fev1, fvc, 100 * fev1 / fvc, rv, mef50]));

  { tidal breathing }
  F := TStringList.Create;
  F.Add('u,x_cm,y_cm,severity,level,V_FRC_mL,V_EE_rest_mL,VT_rest_mL,SV_rest,V_EE_fast_mL,VT_fast_mL,SV_fast');
  for u := 0 to NU - 1 do
    F.Add(Format('%d,%.3f,%.3f,%.5f,%d,%.5f', [u, L.PX[u], L.PY[u], L.Sev[u], L.Level[u], 1000 * VFRC[u]]));
  for pat := 0 to 1 do
  begin
    Mus.Mode := 1;
    if pat = 0 then begin Mus.Ttot := 4; vtT := 0.5; Mus.Pmax := 5; Mus.Tau := 0.3; end
    else begin Mus.Ttot := 2; vtT := 0.6; Mus.Pmax := 8; Mus.Tau := 0.15; end;
    Mus.Ti := Mus.Ttot / 3;
    Sim := TPatchySim.Create(L, Mus.P, VFRC, Dt);
    n := Round(Mus.Ttot / Dt);
    eelvOld := frc;
    pLo := 0; pHi := 0; vLo := 0; vHi := 0;
    for breath := 1 to 60 do
    begin
      vt := 0;
      VMax[0] := Sim.VTot; VMin[0] := Sim.VTot;
      for k := 1 to n do
      begin
        Sim.Step;
        VMax[0] := Max(VMax[0], Sim.VTot);
      end;
      vt := VMax[0] - VMin[0];
      eelv := Sim.VTot;
      if (breath >= 8) and (Abs(vt / vtT - 1) < 0.005) and (Abs(eelv - eelvOld) < 0.001) then Break;
      eelvOld := eelv;
      if Verbose then
        Writeln(Format('    %s breath %d: Pmus %.2f, VT %.0f mL, EELV %.3f L', [PatName[pat], breath, Mus.Pmax,
          1000 * vt, eelv]));
      if vt < vtT then begin pLo := Mus.Pmax; vLo := vt; end
      else begin pHi := Mus.Pmax; vHi := vt; end;
      if (pLo > 0) and (pHi > 0) then
      begin
        pn := pLo + (pHi - pLo) * (vtT - vLo) / (vHi - vLo);
        if (pn < pLo + 0.1 * (pHi - pLo)) or (pn > pHi - 0.1 * (pHi - pLo)) then pn := 0.5 * (pLo + pHi);
        if breath mod 10 = 0 then begin pLo := 0; pHi := 0; end;
      end
      else if vt < 0.05 * vtT then pn := 2 * Mus.Pmax
      else pn := Mus.Pmax * Power(vtT / vt, 0.8);
      Mus.Pmax := Min(60, pn);
    end;
    { the converged breath, recorded }
    for u := 0 to NU - 1 do
    begin
      VMax[u] := Sim.V[u]; VMin[u] := Sim.V[u]; shutAll[u] := True;
    end;
    Wk := 0; Wres := 0; Wel := 0; pplMin := 1e9; limN := 0; expN := 0;
    t0 := Sim.T;
    vprev := Copy(Sim.V);
    F.Insert(0, '');
    F.Delete(0);
    with TStringList.Create do
    try
      Add('t_s,V_L,flow_Lps,Ppl_cmH2O,Pmus_cmH2O,Pc_cmH2O,units_limited,units_shut,units_inspiring,units_expiring');
      vtot := Sim.VTot;
      for k := 1 to n do
      begin
        dvt := Sim.VTot;
        for u := 0 to NU - 1 do vprev[u] := Sim.V[u];
        Sim.Step;
        dvt := Sim.VTot - dvt;
        if dvt > 0 then
        begin
          Wk := Wk + Sim.Pmus * dvt;
          for u := 0 to NU - 1 do
            Wres := Wres - Cm(L.Pu[u]) * (Sim.V[u] - vprev[u]);
        end;
        pplMin := Min(pplMin, Cm(Sim.Ppl));
        if Sim.Q > 0 then
        begin
          Inc(expN);
          if L.TrunkLimited or (Sim.NLim > 0) then Inc(limN);
        end;
        i := 0; m := 0;
        for u := 0 to NU - 1 do
        begin
          VMax[u] := Max(VMax[u], Sim.V[u]); VMin[u] := Min(VMin[u], Sim.V[u]);
          if L.Qu[u] <> 0 then shutAll[u] := False;
          if L.Qu[u] < 0 then Inc(i) else if L.Qu[u] > 0 then Inc(m);
        end;
        if k mod Max(1, Round(0.02 / Dt)) = 0 then
          Add(Format('%.3f,%.5f,%.5f,%.4f,%.4f,%.4f,%d,%d,%d,%d', [Sim.T - t0, Sim.VTot, LpS(Sim.Q),
            Cm(Sim.Ppl), Sim.Pmus, Cm(L.Pc), Sim.NLim, Sim.NClosed, i, m]));
      end;
      SaveToFile(Format('%s/patchy_%s_%s.csv', [OutDir, C.Name, PatName[pat]]));
    finally
      Free;
    end;
    Wel := Wk - Wres;
    eelv := Sim.VTot;
    vt := 0;
    { end expiration: volume-weighted mean alveolar pressure }
    peepi := 0;
    for u := 0 to NU - 1 do
    begin
      VEE[u] := Sim.V[u];
      peepi := peepi + Cm(L.Pu[u]) * Sim.V[u];
    end;
    peepi := peepi / (eelv - Prm.VDead);
    { ventilation }
    svMean := 0;
    for u := 0 to NU - 1 do
    begin
      SV_[u] := (VMax[u] - VMin[u]) / Max(1e-12, VMin[u]);
      svMean := svMean + SV_[u] * VMin[u];
    end;
    svMean := svMean / (eelv - Prm.VDead);
    svSq := 0; defU := 0; defV := 0; nShut := 0; nTrap := 0; nDefect := 0;
    for u := 0 to NU - 1 do
    begin
      svSq := svSq + Sqr(SV_[u] - svMean) * VMin[u];
      if SV_[u] < 0.5 * svMean then
      begin
        Inc(nDefect); defV := defV + VMin[u];
      end;
      if shutAll[u] then Inc(nShut);
      if VEE[u] > 1.1 * VFRC[u] then Inc(nTrap);
      F[u + 1] := F[u + 1] + Format(',%.5f,%.5f,%.5f', [1000 * VMin[u], 1000 * (VMax[u] - VMin[u]), SV_[u]]);
    end;
    if expN > 0 then frac := limN / expN else frac := 0;
    Writeln(Format('  %s, %.0f /min (%d breaths): Pmus peak %.1f cmH2O, EELV %.2f L (FRC %s mL), intrinsic PEEP %.1f cmH2O, Ppl lowest %.1f',
      [PatName[pat], 60 / Mus.Ttot, breath, Mus.Pmax, eelv, Signed(1000 * (eelv - frc)), peepi, pplMin]));
    Writeln(Format('    work %.3f J/breath (%.2f J/min): elastic %.3f, resistive %.3f; %.0f %% of expiration flow-limited somewhere',
      [Wk * JPerCmH2OL, 60 / Mus.Ttot * Wk * JPerCmH2OL, Wel * JPerCmH2OL, Wres * JPerCmH2OL, 100 * frac]));
    Writeln(Format('    ventilation: CV of specific ventilation %.2f; defects (< half the mean) %d units, %.0f %% of lung volume; shut all breath %d; trapped %d',
      [Sqrt(svSq / (eelv - Prm.VDead)) / svMean, nDefect, 100 * defV / (eelv - Prm.VDead), nShut, nTrap]));
    Sim.Free;
  end;
  F.SaveToFile(Format('%s/patchy_%s_units.csv', [OutDir, C.Name]));
  F.Free;
  Writeln(Format('  (%.1f s)', [(GetTickCount64 - t1) / 1000]));
  Writeln;
  Mus.Free;
  L.Free;
end;

var
  Cases: array of TCase;
  i: Integer;
  notes, only: string;
  d: Double;
  cust: TCase;
  any: Boolean;

procedure AddCase(const N: string; Act, Thick, Mucus, Sigma: Double);
begin
  SetLength(Cases, Length(Cases) + 1);
  Cases[High(Cases)].Name := N;
  Cases[High(Cases)].A.Act := Act; Cases[High(Cases)].A.Thick := Thick;
  Cases[High(Cases)].A.Mucus := Mucus; Cases[High(Cases)].Sigma := Sigma;
end;

begin
  InitializeCBLAS;
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  DefaultFormatSettings.DecimalSeparator := '.';
  OptStr('out', OutDir);
  ForceDirectories(OutDir);
  OptVal('dt', Dt);
  Verbose := HasOpt('verbose');
  PPBase := DefaultPatchyParams;
  d := PPBase.K; if OptVal('k', d) then PPBase.K := Round(d);
  d := PPBase.Seed; if OptVal('seed', d) then PPBase.Seed := Round(d);
  OptVal('gravity', PPBase.Gravity);
  Prm := DefaultLungParams;
  Alv := FitAlveolus(Prm.PTLC * CmH2O, Prm.PSalineTLC * CmH2O, 0.126);
  BuildWallLaws(NormalAsthma, RefLaws, notes);
  Writeln(Format('%d units at generation %d, gravity %.2f cmH2O/cm over %.0f cm, seed %d',
    [1 shl PPBase.K, PPBase.K, PPBase.Gravity, PPBase.Height, PPBase.Seed]));
  Writeln;
  AddCase('normal', 0, 1, 1, 0);
  AddCase('moderate', 0.3, 1.5, 1.5, 0);
  AddCase('moderate_p05', 0.3, 1.5, 1.5, 0.5);
  AddCase('moderate_p10', 0.3, 1.5, 1.5, 1.0);
  AddCase('severe', 0.5, 1.75, 2, 0);
  AddCase('severe_p05', 0.5, 1.75, 2, 0.5);
  cust.A := NormalAsthma; cust.Sigma := 0.5;
  any := OptVal('act', cust.A.Act);
  any := OptVal('thick', cust.A.Thick) or any;
  any := OptVal('mucus', cust.A.Mucus) or any;
  any := OptVal('sigma', cust.Sigma) or any;
  if any then AddCase('custom', cust.A.Act, cust.A.Thick, cust.A.Mucus, cust.Sigma);
  only := '';
  OptStr('only', only);
  for i := 0 to High(Cases) do
    if (only = '') or (only = Cases[i].Name) then RunCase(Cases[i]);
  for i := 0 to NWall - 1 do RefLaws[i].Free;
end.
