program absorbrun;

{ Stage 6: closure hysteresis and gas absorption behind shut airways, in
  the ventilated asthmatic of stage 5.

  HYSTERESIS   a unit whose airways have shut stays shut until the
  transmural pressure at either end reaches PClose + 2 gamma / r, r the
  gas radius of the airway that closed (uPatchyLung.Hysteresis 1): the
  pressure to push the liquid bridge out of it, a few cmH2O.

  GAS   each unit carries an oxygen fraction. Gas flowing in has the
  alveolar fraction of the inspired gas, FIn = 0.938 FiO2 - 0.05 (water
  vapour and CO2 replacing some); gas flowing out leaves it unchanged.
  Behind shut airways the blood takes up the gas: oxygen with time
  constant TauO2 (90 s) and the rest, mostly nitrogen, with TauN2 (3 h),
  both assumed: an obstructed unit on oxygen collapses within minutes,
  one on air over hours. Absorbing shrinks the unit's volume (applied
  every 0.1 s, exactly as exponentials). A unit that shrinks below 40 %
  of its relaxed FRC volume has COLLAPSED (atelectasis): its volume stops
  there and it needs 20 cmH2O transmural to reopen (assumed; recruitment
  studies put alveolar opening at 20-40), after which it fills with
  fresh gas.

  PERFUSION   in proportion to each unit's FRC volume times 1 + 2 y/H
  (three times as much at the bottom as at the top: West's zones,
  assumed linear). Reported: the share of perfusion to units shut all
  breath with gas still in them (unventilated, still oxygenating while
  it lasts), and to collapsed ones (true shunt). Units shut only at end
  expiration reopen each inspiration and are counted apart.

  PROTOCOL   the stage-5 status asthmaticus lung (tone 0.8 ignoring
  stretch, wall x 3, normal lining), volume control 500 mL at 12 /min,
  60 L/min, PEEP 0, for 20 min; then a recruitment manoeuvre (CPAP
  35 cmH2O for 30 s) and 3 min more ventilation. Runs: FiO2 1.0 and 0.4
  with hysteresis, FiO2 1.0 without, and the normal lung at FiO2 1.0.
  Options: --only=<run>, --minutes (20), --fio2/--hyst for a custom run
  (name custom), --tauo2, --taun2, --rm=<cmH2O> (35), --dt (0.004),
  --out (out). Writes <out>/absorb_<run>.csv, a row per breath.

  BLOOD GASES (stage 7)   after every breath, uGasExchange's
  steady-state compartment model over the 256 units gives PaO2, PaCO2
  and SaO2 (VO2 250, VCO2 200 mL/min, cardiac output 5 L/min, Hb 15).
  A unit's alveolar ventilation is the gas it took in that breath times
  the rate, less its share of the 150 mL dead space (each unit's in
  proportion to its inflow); a unit that took in nothing is a shunt.
  Hypoxic pulmonary vasoconstriction (HPV) scales each unit's perfusion
  by 1 - HPVMax (1 - s), s = PAO2^4 / (PAO2^4 + HPV50^4) (HPVMax 0.6,
  HPV50 60 mmHg, assumed: a fully hypoxic unit keeps 40 % of its
  perfusion), iterated with the gases to a fixed point; collapsed and
  unventilated units see mixed venous gas and constrict. Options
  --hpvmax, --hpv50. Units shut all breath still hold gas and give up
  oxygen for a few minutes, which the steady-state model ignores, so it
  counts them as shunt from the start.

  Build:  fpc -O3 -FUlib -Fu../../../newVM -Fi../../../newVM absorbrun.lpr }

{$mode delphi}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Classes, Math, StrUtils, cblas, newVM, uTubeLaw, uAirwayRing, uAlveolus, uLungModel, uPatchyLung, uGasExchange;

type
  TZero = class
    function P(t, V: Double): Double;
  end;

  TRun = record
    Name: string;
    Asthma: Boolean;
    FiO2, Hyst, HPV: Double;
  end;

function TZero.P(t, V: Double): Double;
begin
  Result := 0;
end;

var
  OutDir: string = 'out';
  Dt: Double = 0.004;
  Minutes: Double = 20;
  TauO2: Double = 90;
  TauN2: Double = 3 * 3600;
  PRM_: Double = 35;
  HPVMax: Double = 0.6;
  HPV50: Double = 60;
  Prm: TLungParams;
  Alv: TAlveolusParams;
  RefLaws: array[0..NWall - 1] of TTubeLaw;
  Z: TZero;

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

function Cm(p: Double): Double;
begin
  Result := p / CmH2O;
end;

function Signed(x: Double): string;
begin
  if x >= 0 then Result := '+' + Format('%.0f', [x]) else Result := Format('%.0f', [x]);
end;

procedure DoRun(const R: TRun);
const
  VT = 0.5; Rate = 12; Flow = 1.0;
  CollapseFrac = 0.4;
  AtelOpen = 20;  { cmH2O }
var
  PP: TPatchyParams;
  A: TAsthma;
  L: TPatchyLung;
  Sim: TPatchySim;
  NU, u, k, nStep, b, nb, nShut, nEE, nColl, nEver: Integer;
  VF, FO2, Perf: array of Double;
  Coll, Ever, OpenB: array of Boolean;
  VIn, VAu, Qu, PAO2, PACO2: array of Double;
  BG: TBloodGases;
  GP: TGasParams;
  vinTot, qShunt: Double;
  frc, Ti, Te, FIn, perfTot, pShut, pColl, eev, ppk, vo2, vi, dV, tAbs, fo2Shut, t1s: Double;
  phase: Integer;
  F: TStringList;
  t1: QWord;

  { mix, absorb, collapse; every step for the mixing, every 25 for the rest }
  procedure Gas(Absorb: Boolean);
  var
    w: Integer;
    vn, dtA: Double;
  begin
    for w := 0 to NU - 1 do
    begin
      if not Coll[w] then
      begin
        dV := -L.Qu[w] * Sim.Dt / LitreMM3;
        if dV > 0 then FO2[w] := (FO2[w] * Sim.V[w] + dV * FIn) / (Sim.V[w] + dV);
      end;
    end;
    if not Absorb then Exit;
    dtA := tAbs;
    for w := 0 to NU - 1 do
    begin
      if Coll[w] then
      begin
        { reopened? }
        if not L.Shut[w] then
        begin
          Coll[w] := False; L.ExtraOpen[w] := 0; FO2[w] := FIn;
        end;
        Continue;
      end;
      if not L.Shut[w] then Continue;
      Ever[w] := True;
      vo2 := Sim.V[w] * FO2[w] * Exp(-dtA / TauO2);
      vi := Sim.V[w] * (1 - FO2[w]) * Exp(-dtA / TauN2);
      vn := vo2 + vi;
      if vn <= CollapseFrac * VF[w] then
      begin
        Coll[w] := True;
        Sim.V[w] := CollapseFrac * VF[w];
        FO2[w] := 0;
        L.ExtraOpen[w] := Max(0, AtelOpen * CmH2O - (L.Tables[L.Level[w]].PClose
          + L.Hysteresis * L.Tables[L.Level[w]].PReopen));
      end
      else
      begin
        Sim.V[w] := vn;
        FO2[w] := vo2 / vn;
      end;
    end;
    Sim.Evaluate;
  end;

  { blood gases from this breath's unit inflows, with HPV }
  procedure Gases;
  var
    w, it: Integer;
    sat, h: Double;
  begin
    vinTot := 0;
    for w := 0 to NU - 1 do vinTot := vinTot + VIn[w];
    for w := 0 to NU - 1 do
    begin
      if (vinTot > Prm.VDead) and (VIn[w] > 0) then
        VAu[w] := Rate * VIn[w] * (1 - Prm.VDead / vinTot)
      else VAu[w] := 0;
      Qu[w] := Perf[w];
    end;
    for it := 1 to 8 do
    begin
      BG := BloodGases(VAu, Qu, GP, PAO2, PACO2);
      if R.HPV <= 0 then Break;
      for w := 0 to NU - 1 do
      begin
        sat := Power(PAO2[w], 4) / (Power(PAO2[w], 4) + Power(HPV50, 4));
        h := 1 - HPVMax * (1 - sat);
        Qu[w] := Sqrt(Qu[w] * Perf[w] * h);   { damped }
      end;
    end;
    qShunt := 0;
    h := 0;
    for w := 0 to NU - 1 do
    begin
      h := h + Qu[w];
      if VAu[w] <= 0 then qShunt := qShunt + Qu[w];
    end;
    qShunt := qShunt / h;
  end;

  procedure Advance(Dur: Double);
  var
    s, n, w: Integer;
  begin
    n := Max(1, Round(Dur / Sim.Dt));
    for s := 1 to n do
    begin
      Sim.Step;
      ppk := Max(ppk, Sim.Paw);
      for w := 0 to NU - 1 do
      begin
        if not L.Shut[w] then OpenB[w] := True;
        if L.Qu[w] < 0 then VIn[w] := VIn[w] - L.Qu[w] * Sim.Dt / LitreMM3;
      end;
      Inc(nStep);
      Gas(nStep mod 25 = 0);
    end;
  end;

begin
  t1 := GetTickCount64;
  PP := DefaultPatchyParams;
  PP.ActMode := True; PP.DS := 0.05; PP.SMax := 0.9;
  if R.Asthma then
  begin
    A.Act := 0.8; A.Thick := 3; A.Mucus := 1; PP.Sigma := 0.1;
  end
  else
  begin
    A.Act := 0; A.Thick := 1; A.Mucus := 1; PP.Sigma := 0;
  end;
  FIn := 0.938 * R.FiO2 - 0.05;
  Writeln(Format('=== %s: FiO2 %.2f (alveolar O2 fraction of fresh gas %.3f), hysteresis %.1f, HPV %s, tau O2 %.0f s, N2 %.0f min',
    [R.Name, R.FiO2, FIn, R.Hyst, IfThen(R.HPV > 0, 'on', 'off'), TauO2, TauN2 / 60]));
  L := TPatchyLung.Create(Prm, PP, A, Alv, RefLaws);
  { with no hysteresis the closure state is still tracked (a unit
    reopens at its closing pressure), so a collapsed unit can be held }
  L.Hysteresis := Max(R.Hyst, 1e-12);
  NU := L.NU;
  SetLength(VF, NU); SetLength(FO2, NU); SetLength(Perf, NU); SetLength(Coll, NU); SetLength(Ever, NU); SetLength(OpenB, NU);
  SetLength(VIn, NU); SetLength(VAu, NU); SetLength(Qu, NU); SetLength(PAO2, NU); SetLength(PACO2, NU);
  GP := DefaultGasParams;
  GP.FiO2 := R.FiO2;
  L.StaticState(0, VF);
  frc := Prm.VDead; perfTot := 0;
  for u := 0 to NU - 1 do
  begin
    frc := frc + VF[u];
    FO2[u] := FIn;
    Perf[u] := VF[u] * (1 + 2 * L.PY[u] / PP.Height);
    perfTot := perfTot + Perf[u];
  end;
  { the airways that are shut at FRC start shut }
  for u := 0 to NU - 1 do
    L.Shut[u] := L.UnitPel(VF[u]) <= L.Tables[L.Level[u]].PClose;
  if R.Hyst > 0 then
  begin
    tAbs := 0;
    for u := 0 to NU - 1 do tAbs := tAbs + L.Tables[L.Level[u]].PReopen / NU;
    Writeln(Format('  reopening pressure above closing: mean %.1f cmH2O', [Cm(tAbs)]));
  end;
  tAbs := 25 * Dt;
  Sim := TPatchySim.Create(L, Z.P, VF, Dt);
  Ti := VT / Flow; Te := 60 / Rate - Ti;
  nb := Round(Minutes * Rate);
  F := TStringList.Create;
  F.Add('breath,t_min,phase,EEV_above_FRC_mL,Ppeak_cmH2O,units_shut_all_breath,units_shut_end_exp,units_collapsed,units_ever_absorbing,'
    + 'perf_shut_pct,perf_collapsed_pct,FO2_shut_mean,PaO2_mmHg,PaCO2_mmHg,SaO2,PvO2_mmHg,shunt_after_HPV_pct');
  nStep := 0;
  b := 0;
  phase := 0;
  while True do
  begin
    Inc(b);
    for u := 0 to NU - 1 do
    begin
      OpenB[u] := False; VIn[u] := 0;
    end;
    if (phase = 0) and (b > nb) then
    begin
      { recruitment manoeuvre }
      Sim.Mode := smPressure; Sim.Paw := PRM_ * CmH2O; Sim.Evaluate;
      ppk := -1e30;
      Advance(30);
      Sim.Paw := 0; Sim.Evaluate;
      Advance(Te);
      phase := 1;
    end
    else
    begin
      if (phase = 1) and (b > nb + 1 + Round(3 * Rate)) then Break;
      ppk := -1e30;
      Sim.Mode := smFlow; Sim.QSet := -Flow * LitreMM3; Sim.Evaluate;
      Advance(Ti);
      Sim.Mode := smPressure; Sim.Paw := 0; Sim.Evaluate;
      Advance(Te);
    end;
    eev := Sim.VTot;
    nShut := 0; nEE := 0; nColl := 0; nEver := 0; pShut := 0; pColl := 0; fo2Shut := 0;
    for u := 0 to NU - 1 do
    begin
      if Ever[u] then Inc(nEver);
      if Coll[u] then
      begin
        Inc(nColl); pColl := pColl + Perf[u];
      end
      else if not OpenB[u] then
      begin
        Inc(nShut); pShut := pShut + Perf[u]; fo2Shut := fo2Shut + FO2[u];
      end;
      if (not Coll[u]) and L.Shut[u] then Inc(nEE);
    end;
    if nShut > 0 then fo2Shut := fo2Shut / nShut;
    t1s := Sim.T / 60;
    { the recruitment breath's inflow is the manoeuvre, not a breath }
    if not ((phase = 1) and (b = nb + 1)) then Gases;
    F.Add(Format('%d,%.3f,%d,%.1f,%.2f,%d,%d,%d,%d,%.2f,%.2f,%.4f,%.1f,%.2f,%.4f,%.1f,%.2f', [b, t1s, phase,
      1000 * (eev - frc), Cm(ppk), nShut, nEE, nColl, nEver, 100 * pShut / perfTot, 100 * pColl / perfTot, fo2Shut,
      BG.PaO2, BG.PaCO2, BG.SaO2, BG.PvO2, 100 * qShunt]));
    if (b mod Round(Rate * 2) = 0) or (b = 1) or (phase = 1) and (b = nb + 1) or
       (phase = 1) and (b = nb + 1 + Round(3 * Rate)) then
      Writeln(Format('  %5.1f min%s: EEV %5s mL, peak %4.1f; shut all breath %3d (O2 %.2f), at end exp. %3d, collapsed %3d; perfusion unventilated %4.1f %%, collapsed %4.1f %%',
        [t1s, IfThen(phase = 1, ' (after RM)', ''), Signed(1000 * (eev - frc)), Cm(ppk), nShut, fo2Shut, nEE, nColl,
         100 * pShut / perfTot, 100 * pColl / perfTot]));
    if (b mod Round(Rate * 2) = 0) or (b = 1) or (phase = 1) and (b = nb + 1 + Round(3 * Rate)) then
      Writeln(Format('           PaO2 %5.1f mmHg (P/F %3.0f), PaCO2 %4.1f, SaO2 %.3f, PvO2 %4.1f; shunt %4.1f %% of the cardiac output',
        [BG.PaO2, BG.PaO2 / R.FiO2, BG.PaCO2, BG.SaO2, BG.PvO2, 100 * qShunt]));
  end;
  F.SaveToFile(Format('%s/absorb_%s.csv', [OutDir, R.Name]));
  F.Free;
  Sim.Free; L.Free;
  Writeln(Format('  (%.0f s)', [(GetTickCount64 - t1) / 1000]));
  Writeln;
end;

var
  Runs: array of TRun;
  i: Integer;
  notes, only: string;
  cust: TRun;

procedure AddRun(const N: string; As_: Boolean; FiO2, Hyst: Double; HPV: Double = 1);
begin

  SetLength(Runs, Length(Runs) + 1);
  Runs[High(Runs)].Name := N; Runs[High(Runs)].Asthma := As_;
  Runs[High(Runs)].FiO2 := FiO2; Runs[High(Runs)].Hyst := Hyst;
  Runs[High(Runs)].HPV := HPV;
end;

begin
  InitializeCBLAS;
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  DefaultFormatSettings.DecimalSeparator := '.';
  OptStr('out', OutDir);
  ForceDirectories(OutDir);
  OptVal('dt', Dt);
  OptVal('minutes', Minutes);
  OptVal('tauo2', TauO2);
  OptVal('taun2', TauN2);
  OptVal('rm', PRM_);
  OptVal('hpvmax', HPVMax);
  OptVal('hpv50', HPV50);
  Prm := DefaultLungParams;
  Prm.K1 := 1; Prm.K2 := 4;
  Alv := FitAlveolus(Prm.PTLC * CmH2O, Prm.PSalineTLC * CmH2O, 0.126);
  BuildWallLaws(NormalAsthma, RefLaws, notes);
  Z := TZero.Create;
  AddRun('asthma_o2', True, 1.0, 1);
  AddRun('asthma_fio2_04', True, 0.4, 1);
  AddRun('asthma_o2_nohyst', True, 1.0, 0);
  AddRun('normal_o2', False, 1.0, 1);
  AddRun('asthma_air', True, 0.21, 1);
  AddRun('asthma_o2_nohpv', True, 1.0, 1, 0);
  AddRun('normal_air', False, 0.21, 1);
  cust.FiO2 := 1; cust.Hyst := 1;
  if OptVal('fio2', cust.FiO2) or OptVal('hyst', cust.Hyst) then
  begin
    OptVal('hyst', cust.Hyst);
    AddRun('custom', True, cust.FiO2, cust.Hyst);
  end;
  only := '';
  OptStr('only', only);
  for i := 0 to High(Runs) do
    if (only = '') or (only = Runs[i].Name) then DoRun(Runs[i]);
  Z.Free;
  for i := 0 to NWall - 1 do RefLaws[i].Free;
end.
