program lungrun;

{ The whole lung (uLungModel), normal and in three grades of asthma.

  For each case:
  STATIC     FRC (where lung and chest wall recoil balance), the
             transpulmonary pressure there, airway resistance at FRC
             and the pressure at which the terminal bronchioles' lining
             closes them.
  FORCED EXPIRATION   from TLC with maximal expiratory effort, rising
             with a 30 ms time constant to PEmax(V) = 40 + 120 (V - 1.3)
             / 5.2 cmH2O (assumed): PEF, FEV1, FVC, FEV1/FVC, RV, the
             flow at half the FVC exhaled (MEF50) at full and at 60 %
             effort (equal if the flow is limited), and the generation
             where the flow chokes.
  TIDAL BREATHING     at rest, 15 /min and 500 mL, and fast, 30 /min
             and 600 mL; I:E 1:2. Inspiratory muscle pressure
             Pmax sin(pi t / (2 Ti)) during inspiration, then decaying
             with a time constant of 0.3 s (fast 0.15 s: post-
             inspiratory activity); expiration passive. Pmax is
             adjusted breath by breath for the tidal volume, until the
             breath repeats. Then: end-
             expiratory lung volume (EELV, against FRC: dynamic
             hyperinflation), intrinsic PEEP (alveolar pressure at end
             expiration), pleural pressure, peak flows, how much of
             expiration is flow limited, and the inspiratory muscles'
             work, split into elastic (lung and chest wall) and
             resistive (airways).

  Cases: normal; mild (activation 0.15, wall x 1.25); moderate (0.3,
  x 1.5, lining x 1.5); severe (0.5, x 1.75, lining x 2). Options
  --act, --thick, --mucus add a custom case; --only=<name> runs one
  case; --fitwall refits WallM; --dt=<s> the tidal time step (0.004);
  --verbose prints each breath; --out=<dir> (out). Writes <out>/lung_<case>_fv.csv (forced expiration),
  _rest.csv and _fast.csv (the last breath).

  Build:  fpc -O3 -FUlib -Fu../../../newVM -Fi../../../newVM lungrun.lpr }

{$mode delphi}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Classes, Math, cblas, newVM, uTubeLaw, uAirwayRing, uAlveolus, uLungModel;

type
  TCase = record
    Name: string;
    A: TAsthma;
  end;

  TMuscles = class
  public
    Mode: Integer;          { 0 forced expiration, 1 tidal }
    Effort: Double;
    TLC: Double;
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
  Dt: Double = 0.004;
  Verbose: Boolean = False;
  OutDir: string = 'out';
  Alv: TAlveolusParams;
  Prm: TLungParams;
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

function Signed(x: Double): string;
begin
  { FPC's Format has no '+' flag }
  if x >= 0 then Result := '+' + Format('%.0f', [x]) else Result := Format('%.0f', [x]);
end;

function Cm(p: Double): Double;
begin
  Result := p / CmH2O;
end;

function LpS(q: Double): Double;
begin
  Result := q / LitreMM3;
end;

procedure RunCase(const C: TCase);
var
  Laws: array[0..NWall - 1] of TTubeLaw;
  WL, RL: array[0..NGen - 1] of TTubeLaw;
  Lung: TLung;
  Sim: TLungSim;
  Mus: TMuscles;
  notes: string;
  g, iw, n, breath, k, limN, expN, gpef: Integer;
  vtT, pLo, pHi, vLo, vHi, pn: Double;
  pat: Integer;
  frc, raw, pef, fev1, fvc, rv, v0, mef50, mef50b, vmax, vt, eelv, eelvOld, peepi,
  pplMin, pplEE, qi, qe, Wk, Wres, Wel, dv, t0, frac: Double;
  F: TStringList;
  s: string;
  t1: QWord;

  function ForcedMEF50(Effort: Double; out PEF_, FEV1_, FVC_, RV_: Double; out GPEF: Integer; Save: Boolean): Double;
  var
    vs, vl: array of Double;
    i, m: Integer;
    target, qprev, vprev: Double;
  begin
    Mus.Mode := 0; Mus.Effort := Effort; Mus.TLC := Prm.TLC;
    Sim := TLungSim.Create(Lung, Mus.P, Prm.TLC, 0.001);
    PEF_ := 0; FEV1_ := NaN; GPEF := -1;
    if Save then
    begin
      F := TStringList.Create;
      F.Add('t_s,volume_exhaled_L,flow_Lps,Palv_cmH2O,Ppl_cmH2O,choke_gen');
    end;
    m := 0;
    SetLength(vs, 0); SetLength(vl, 0);
    while Sim.T < 8 do
    begin
      Sim.Step;
      if LpS(Sim.Q) > PEF_ then begin PEF_ := LpS(Sim.Q); GPEF := Sim.ChokeGen; end;
      if IsNan(FEV1_) and (Sim.T >= 1 - 1e-9) then FEV1_ := Prm.TLC - Sim.V;
      SetLength(vs, m + 1); SetLength(vl, m + 1);
      vs[m] := Prm.TLC - Sim.V; vl[m] := LpS(Sim.Q); Inc(m);
      if Save and (Round(Sim.T * 1000) mod 5 = 0) then
        F.Add(Format('%.3f,%.5f,%.5f,%.3f,%.3f,%d', [Sim.T, Prm.TLC - Sim.V, LpS(Sim.Q),
          Cm(Sim.Palv), Cm(Sim.Ppl), Sim.ChokeGen]));
      if (Sim.T > 0.3) and (LpS(Sim.Q) < 0.02) then Break;
    end;
    FVC_ := Prm.TLC - Sim.V;
    RV_ := Sim.V;
    if IsNan(FEV1_) then FEV1_ := FVC_;
    Sim.Free;
    if Save then
    begin
      F.SaveToFile(Format('%s/lung_%s_fv.csv', [OutDir, C.Name]));
      F.Free;
    end;
    { flow when half the FVC is out }
    target := 0.5 * FVC_;
    Result := NaN;
    for i := 1 to m - 1 do
      if (vs[i - 1] < target) and (vs[i] >= target) then
      begin
        Result := vl[i - 1] + (vl[i] - vl[i - 1]) * (target - vs[i - 1]) / (vs[i] - vs[i - 1]);
        Break;
      end;
  end;

begin
  t1 := GetTickCount64;
  Writeln('=== ', C.Name, Format(' (activation %.2f, wall x %.2f, lining x %.1f)', [C.A.Act, C.A.Thick, C.A.Mucus]));
  if (C.A.Act = 0) and (C.A.Thick = 1) then
    for iw := 0 to NWall - 1 do Laws[iw] := RefLaws[iw]
  else
  begin
    BuildWallLaws(C.A, Laws, notes);
    if notes <> '' then Writeln('  tube laws: ', notes);
  end;
  for g := 0 to NGen - 1 do
  begin
    WL[g] := Laws[GenWall[g]]; RL[g] := RefLaws[GenWall[g]];
  end;
  Lung := TLung.Create(Prm, WL, RL, C.A.Mucus, Alv);
  Mus := TMuscles.Create;

  { static }
  frc := Lung.StaticVolume(0);
  raw := Lung.Resistance(Lung.Pcw(frc)) / CmH2O * LitreMM3;
  if IsInfinite(raw) or IsNan(raw) then s := 'infinite: the linings close the small airways'
  else s := Format('%.2f cmH2O s/L', [raw]);
  Writeln(Format('  FRC %.2f L, Ptp there %.1f cmH2O, airway resistance %s', [frc, Cm(Lung.Pel(frc)), s]));
  Write('  lining closes the airway below Ptm (cmH2O): ');
  for g := 12 to NGen - 1 do
    if IsInfinite(Lung.Gens[g].PClose) then Write(Format('g%d never  ', [g]))
    else Write(Format('g%d %.1f  ', [g, Cm(Lung.Gens[g].PClose)]));
  Writeln;
  Write('  lumen area at FRC / normal: ');
  for g := 0 to NGen - 1 do
    if g mod 4 = 0 then Write(Format('g%d %.2f  ', [g, Lung.Gens[g].Gas.Area(Lung.Pel(frc)) / Lung.Gens[g].AF]));
  Writeln;

  { forced expiration }
  mef50 := ForcedMEF50(1, pef, fev1, fvc, rv, gpef, True);
  mef50b := ForcedMEF50(0.6, qi, qe, Wk, Wres, k, False);
  Writeln(Format('  forced expiration: PEF %.2f L/s (%.0f L/min), FEV1 %.2f L, FVC %.2f L, FEV1/FVC %.0f %%, RV %.2f L',
    [pef, 60 * pef, fev1, fvc, 100 * fev1 / fvc, rv]));
  if gpef >= 0 then s := Format('at PEF the flow chokes in generation %d', [gpef])
  else s := 'PEF is reached before the flow chokes';
  Writeln(Format('    MEF50 %.2f L/s at full effort, %.2f at 60 %%; %s', [mef50, mef50b, s]));

  { tidal breathing, at rest and fast }
  for pat := 0 to 1 do
  begin
    Mus.Mode := 1; Mus.Tau := 0.3;
    if pat = 0 then begin Mus.Ttot := 4; vtT := 0.5; Mus.Pmax := 4; end
    else begin Mus.Ttot := 2; vtT := 0.6; Mus.Pmax := 8; Mus.Tau := 0.15; end;
    Mus.Ti := Mus.Ttot / 3;
    Sim := TLungSim.Create(Lung, Mus.P, frc, Dt);
    eelvOld := frc;
    pLo := 0; pHi := 0; vLo := 0; vHi := 0;
    n := Round(Mus.Ttot / Sim.Dt);
    for breath := 1 to 60 do
    begin
      vmax := Sim.V; v0 := Sim.V;
      Wk := 0; Wres := 0; Wel := 0; pplMin := 1e9; qi := 0; qe := 0; limN := 0; expN := 0;
      for k := 1 to n do
      begin
        dv := Sim.V;
        Sim.Step;
        dv := Sim.V - dv;
        vmax := Max(vmax, Sim.V);
        if dv > 0 then
        begin
          Wk := Wk + Sim.Pmus * dv;
          Wres := Wres - Cm(Sim.Palv) * dv;
          Wel := Wel + Cm(Lung.Pel(Sim.V) + Lung.Pcw(Sim.V)) * dv;
        end;
        pplMin := Min(pplMin, Cm(Sim.Ppl));
        qi := Max(qi, -LpS(Sim.Q)); qe := Max(qe, LpS(Sim.Q));
        if Sim.Q > 0 then
        begin
          Inc(expN);
          if Sim.Limited then Inc(limN);
        end;
      end;
      eelv := Sim.V; peepi := Cm(Sim.Palv); pplEE := Cm(Sim.Ppl);
      vt := vmax - v0;
      if (breath >= 8) and (Abs(vt / vtT - 1) < 0.005) and (Abs(eelv - eelvOld) < 0.001) then Break;
      eelvOld := eelv;
      if Verbose then
        Writeln(Format('    %s breath %d: Pmus %.2f, VT %.0f mL, EELV %.3f L, Palv %.2f, limited %d/%d',
          [PatName[pat], breath, Mus.Pmax, 1000 * vt, eelv, peepi, limN, expN]));
      { Pmax for the target VT. VT rises with Pmax, steeply once the
        muscles must first overcome gas trapped behind closed airways,
        so a plain power-law update oscillates: keep a bracket and use
        the secant within it (bisection if that leaves the middle 80 %).
        The muscles' strongest effort is taken as 60 cmH2O. }
      if vt < vtT then begin pLo := Mus.Pmax; vLo := vt; end
      else begin pHi := Mus.Pmax; vHi := vt; end;
      if (pLo > 0) and (pHi > 0) then
      begin
        pn := pLo + (pHi - pLo) * (vtT - vLo) / (vHi - vLo);
        if (pn < pLo + 0.1 * (pHi - pLo)) or (pn > pHi - 0.1 * (pHi - pLo)) then
          pn := 0.5 * (pLo + pHi);
        { the bracket can go stale while EELV is still settling }
        if breath mod 10 = 0 then begin pLo := 0; pHi := 0; end;
      end
      else if vt < 0.05 * vtT then pn := 2 * Mus.Pmax
      else pn := Mus.Pmax * Power(vtT / vt, 0.8);
      Mus.Pmax := pn;
      if Mus.Pmax > 60 then
      begin
        Mus.Pmax := 60;
        if (breath > 8) and (vt < 0.98 * vtT) and (pLo >= 60) then
        begin
          Writeln(Format('    %s breathing: the muscles at 60 cmH2O move only %.0f mL', [PatName[pat], 1000 * vt]));
          Break;
        end;
      end;
    end;
    { the converged breath once more, recorded }
    F := TStringList.Create;
    F.Add('t_s,V_L,flow_Lps,Palv_cmH2O,Ppl_cmH2O,Pmus_cmH2O,limited');
    t0 := Sim.T;
    for k := 1 to n do
    begin
      Sim.Step;
      if k mod Max(1, Round(0.02 / Sim.Dt)) = 0 then
        F.Add(Format('%.3f,%.5f,%.5f,%.4f,%.4f,%.4f,%d', [Sim.T - t0, Sim.V, LpS(Sim.Q),
          Cm(Sim.Palv), Cm(Sim.Ppl), Sim.Pmus, Ord(Sim.Limited)]));
    end;
    F.SaveToFile(Format('%s/lung_%s_%s.csv', [OutDir, C.Name, PatName[pat]]));
    F.Free;
    Sim.Free;
    if expN > 0 then frac := limN / expN else frac := 0;
    Writeln(Format('  %s breathing, %.0f /min (%d breaths): Pmus peak %.1f cmH2O, VT %.0f mL, EELV %.2f L (FRC %s mL), intrinsic PEEP %.1f cmH2O',
      [PatName[pat], 60 / Mus.Ttot, breath, Mus.Pmax, 1000 * vt, eelv, Signed(1000 * (eelv - frc)), peepi]));
    Writeln(Format('    pleural pressure %.1f at end expiration, %.1f at its lowest; peak flow in %.2f, out %.2f L/s; %.0f %% of expiration flow limited',
      [pplEE, pplMin, qi, qe, 100 * frac]));
    Writeln(Format('    inspiratory work %.3f J/breath (%.2f J/min, %.2f J/L): elastic %.3f, resistive %.3f',
      [Wk * JPerCmH2OL, 60 / Mus.Ttot * Wk * JPerCmH2OL, Wk * JPerCmH2OL / vt, Wel * JPerCmH2OL, Wres * JPerCmH2OL]));
  end;
  Writeln(Format('  (%.1f s)', [(GetTickCount64 - t1) / 1000]));
  Writeln;
  Mus.Free;
  Lung.Free;
  if not ((C.A.Act = 0) and (C.A.Thick = 1)) then
    for iw := 0 to NWall - 1 do Laws[iw].Free;
end;

var
  Cases: array of TCase;
  i, w: Integer;
  notes, only: string;
  cust: TAsthma;
  any: Boolean;
  L: TTubeLaw;

procedure AddCase(const N: string; Act, Thick, Mucus: Double);
begin
  SetLength(Cases, Length(Cases) + 1);
  Cases[High(Cases)].Name := N;
  Cases[High(Cases)].A.Act := Act; Cases[High(Cases)].A.Thick := Thick; Cases[High(Cases)].A.Mucus := Mucus;
end;

begin
  InitializeCBLAS;
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  DefaultFormatSettings.DecimalSeparator := '.';
  OptStr('out', OutDir);
  OptVal('dt', Dt);
  Verbose := HasOpt('verbose');
  ForceDirectories(OutDir);
  if HasOpt('fitwall') then
  begin
    Writeln(Format('WallM for generations 0-1 (Lambert 0.888): %.4g', [FitWallM(0.888)]));
    Writeln(Format('WallM for generation 2 (Lambert 0.711): %.4g', [FitWallM(0.711)]));
    for w := 0 to NWall - 1 do
      Writeln(Format('  wall %d: ratio A(5)/A(40) %.3f', [w, WallRatio(WallRing(w, NormalAsthma))]));
    Exit;
  end;
  Prm := DefaultLungParams;
  Alv := FitAlveolus(Prm.PTLC * CmH2O, Prm.PSalineTLC * CmH2O, 0.126);
  Writeln(Format('Alveolus fitted: tissue C %.4g kPa, surface factor %.3g', [Alv.C, Alv.SurfFactor]));
  BuildWallLaws(NormalAsthma, RefLaws, notes);
  if notes <> '' then Writeln('Normal tube laws: ', notes);
  AddCase('normal', 0, 1, 1);
  AddCase('mild', 0.15, 1.25, 1);
  AddCase('moderate', 0.3, 1.5, 1.5);
  AddCase('severe', 0.5, 1.75, 2);
  cust := NormalAsthma;
  any := OptVal('act', cust.Act);
  any := OptVal('thick', cust.Thick) or any;
  any := OptVal('mucus', cust.Mucus) or any;
  if any then AddCase('custom', cust.Act, cust.Thick, cust.Mucus);
  only := '';
  OptStr('only', only);
  Writeln;
  for i := 0 to High(Cases) do
    if (only = '') or (only = Cases[i].Name) then RunCase(Cases[i]);
  for w := 0 to NWall - 1 do RefLaws[w].Free;
end.
