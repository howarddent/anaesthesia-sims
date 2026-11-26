program treatrun;

{ Stage 8: treating the ventilated asthmatic.

  The stage-5 status asthmaticus lung (256 units, wall x 3, normal
  lining, tone 0.8 that ignores stretch, 10 % clustered spread),
  paralysed, volume control 500 mL with a 60 L/min square wave, PEEP 0,
  closure hysteresis on (stage 6). Treatments:

    baseline     rate 12 /min, FiO2 0.3 in nitrogen (air-oxygen);
    salbutamol   tone 0.8 -> 0.4 (--salb): beta-agonist relaxation of
                 the muscle, assumed half; the thickened wall is left;
    heliox       70 % helium, 30 % oxygen: density 0.554 against air's
                 1.20 g/L (x 0.46), viscosity x 1.09. Both enter the
                 airway pressure drops and the wave-speed choke of every
                 generation (uLungModel), and the tube: K1 goes with
                 viscosity, K2 (turbulent) with density;
    salbutamol + heliox;
    rate 8 /min  the ventilator answer (Tuxen), on the baseline lung;
    salbutamol + heliox at 8 /min.

  Each runs to steady end-expiratory volume (as ventrun: less than
  0.5 mL a breath twice running, at most 60 breaths), then a measured
  breath with an end-inspiratory hold of 0.5 s (plateau) and an
  end-expiratory hold of 2 s (total PEEP). Blood gases from the
  measured breath's unit inflows by uGasExchange, with hypoxic
  vasoconstriction as in absorbrun (no absorption: the steady state
  before any collapse; units shut all breath count as shunt). The normal
  lung on air-oxygen 0.3 is the reference.

  Options: --only=<run>, --salb (0.4), --dt (0.004), --out (out).
  Writes <out>/treat.csv, a row per run.

  Build:  fpc -O3 -FUlib -Fu../../../newVM -Fi../../../newVM treatrun.lpr }

{$mode delphi}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Classes, Math, cblas, newVM, uTubeLaw, uAirwayRing, uAlveolus, uLungModel, uPatchyLung,
  uGasExchange;

type
  TZero = class
    function P(t, V: Double): Double;
  end;

  TTreat = record
    Name: string;
    Asthma, Heliox: Boolean;
    Tone, Rate: Double;
  end;

function TZero.P(t, V: Double): Double;
begin
  Result := 0;
end;

const
  VT = 0.5; Flow = 1.0; FiO2 = 0.3;
  HelioxRho = 0.554 / 1.20;
  HelioxVisc = 1.09;
  HPVMax = 0.6; HPV50 = 60;

var
  OutDir: string = 'out';
  Dt: Double = 0.004;
  Salb: Double = 0.4;
  Alv: TAlveolusParams;
  RefLaws: array[0..NWall - 1] of TTubeLaw;
  Z: TZero;
  Res: TStringList;

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

procedure DoTreat(const T: TTreat);
var
  Prm: TLungParams;
  PP: TPatchyParams;
  A: TAsthma;
  L: TPatchyLung;
  Sim: TPatchySim;
  NU, u, b, conv, nShutAll, it: Integer;
  VF, VIn, VAu, Perf, Qp, PAO2, PACO2: array of Double;
  OpenB: array of Boolean;
  frc, Ti, Te, eev, eevOld, ppk, pplat, ptot, vEndInsp, vinTot, qs, qShunt, sat: Double;
  BG: TBloodGases;
  GP: TGasParams;
  t1: QWord;

  function Run(Dur: Double; Track: Boolean): Double;
  var
    n, k, w: Integer;
  begin
    Result := -1e30;
    n := Max(1, Round(Dur / Sim.Dt));
    for k := 1 to n do
    begin
      Sim.Step;
      Result := Max(Result, Sim.Paw);
      if Track then
        for w := 0 to NU - 1 do
        begin
          if not L.Shut[w] then OpenB[w] := True;
          if L.Qu[w] < 0 then VIn[w] := VIn[w] - L.Qu[w] * Sim.Dt / LitreMM3;
        end;
    end;
  end;

  procedure Inspire;
  begin
    Sim.Mode := smFlow; Sim.QSet := -Flow * LitreMM3; Sim.Evaluate;
  end;

  procedure Expire;
  begin
    Sim.Mode := smPressure; Sim.Paw := 0; Sim.Evaluate;
  end;

  procedure Hold;
  begin
    Sim.Mode := smFlow; Sim.QSet := 0; Sim.Evaluate;
  end;

begin
  t1 := GetTickCount64;
  Prm := DefaultLungParams;
  Prm.K1 := 1; Prm.K2 := 4;
  if T.Heliox then
  begin
    Prm.Rho := Prm.Rho * HelioxRho; Prm.Visc := Prm.Visc * HelioxVisc;
    Prm.K1 := Prm.K1 * HelioxVisc; Prm.K2 := Prm.K2 * HelioxRho;
  end;
  PP := DefaultPatchyParams;
  PP.ActMode := True; PP.DS := 0.05; PP.SMax := 0.9;
  if T.Asthma then
  begin
    A.Act := T.Tone; A.Thick := 3; A.Mucus := 1; PP.Sigma := 0.1;
  end
  else
  begin
    A.Act := 0; A.Thick := 1; A.Mucus := 1; PP.Sigma := 0;
  end;
  L := TPatchyLung.Create(Prm, PP, A, Alv, RefLaws);
  L.Hysteresis := 1;
  NU := L.NU;
  SetLength(VF, NU); SetLength(VIn, NU); SetLength(VAu, NU); SetLength(Perf, NU); SetLength(Qp, NU);
  SetLength(PAO2, NU); SetLength(PACO2, NU); SetLength(OpenB, NU);
  L.StaticState(0, VF);
  frc := Prm.VDead;
  for u := 0 to NU - 1 do
  begin
    frc := frc + VF[u];
    Perf[u] := VF[u] * (1 + 2 * L.PY[u] / PP.Height);
    L.Shut[u] := L.UnitPel(VF[u]) <= L.Tables[L.Level[u]].PClose;
  end;
  Sim := TPatchySim.Create(L, Z.P, VF, Dt);
  Ti := VT / Flow; Te := 60 / T.Rate - Ti;
  eevOld := Sim.VTot; conv := 0;
  for b := 1 to 60 do
  begin
    Inspire; Run(Ti, False);
    Expire; Run(Te, False);
    eev := Sim.VTot;
    if Abs(eev - eevOld) < 0.0005 then Inc(conv) else conv := 0;
    eevOld := eev;
    if conv >= 2 then Break;
  end;
  { the measured breath }
  for u := 0 to NU - 1 do
  begin
    VIn[u] := 0; OpenB[u] := False;
  end;
  Inspire; ppk := Run(Ti, True);
  vEndInsp := Sim.VTot;
  Hold; Run(0.5, True); pplat := Sim.Paw;
  Expire; Run(Te, True);
  eev := Sim.VTot;
  Hold; Run(2, False); ptot := Sim.Paw;
  nShutAll := 0;
  for u := 0 to NU - 1 do if not OpenB[u] then Inc(nShutAll);
  { blood gases }
  GP := DefaultGasParams; GP.FiO2 := FiO2;
  vinTot := 0;
  for u := 0 to NU - 1 do vinTot := vinTot + VIn[u];
  for u := 0 to NU - 1 do
  begin
    if (vinTot > Prm.VDead) and (VIn[u] > 0) then VAu[u] := T.Rate * VIn[u] * (1 - Prm.VDead / vinTot)
    else VAu[u] := 0;
    Qp[u] := Perf[u];
  end;
  for it := 1 to 8 do
  begin
    BG := BloodGases(VAu, Qp, GP, PAO2, PACO2);
    for u := 0 to NU - 1 do
    begin
      sat := Power(PAO2[u], 4) / (Power(PAO2[u], 4) + Power(HPV50, 4));
      Qp[u] := Sqrt(Qp[u] * Perf[u] * (1 - HPVMax * (1 - sat)));
    end;
  end;
  qs := 0; qShunt := 0;
  for u := 0 to NU - 1 do
  begin
    qs := qs + Qp[u];
    if VAu[u] <= 0 then qShunt := qShunt + Qp[u];
  end;
  qShunt := qShunt / qs;
  Writeln(Format('%-22s %4.0f  %5.2f  %5.1f  %5.1f  %5.1f   %6.0f %6.0f   %3d  %5.1f  %5.1f  %4.1f  %4.0f  (%d breaths, %.0f s)',
    [T.Name, T.Rate, T.Tone, Cm(ppk), Cm(pplat), Cm(ptot), 1000 * (eev - frc), 1000 * (vEndInsp - frc), nShutAll,
     100 * qShunt, BG.PaO2, BG.PaCO2, 100 * BG.SaO2, b, (GetTickCount64 - t1) / 1000]));
  Res.Add(Format('%s,%.0f,%.2f,%d,%.3f,%.3f,%.3f,%.1f,%.1f,%d,%.2f,%.1f,%.2f,%.4f', [T.Name, T.Rate, T.Tone,
    Ord(T.Heliox), Cm(ppk), Cm(pplat), Cm(ptot), 1000 * (eev - frc), 1000 * (vEndInsp - frc), nShutAll,
    100 * qShunt, BG.PaO2, BG.PaCO2, BG.SaO2]));
  Sim.Free; L.Free;
end;

var
  Runs: array of TTreat;
  i: Integer;
  notes, only: string;
  Prm0: TLungParams;

procedure Add(const N: string; As_, He: Boolean; ATone, ARate: Double);
begin
  SetLength(Runs, Length(Runs) + 1);
  Runs[High(Runs)].Name := N; Runs[High(Runs)].Asthma := As_; Runs[High(Runs)].Heliox := He;
  Runs[High(Runs)].Tone := ATone; Runs[High(Runs)].Rate := ARate;
end;

begin
  InitializeCBLAS;
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  DefaultFormatSettings.DecimalSeparator := '.';
  OptStr('out', OutDir);
  ForceDirectories(OutDir);
  OptVal('dt', Dt);
  OptVal('salb', Salb);
  Prm0 := DefaultLungParams;
  Alv := FitAlveolus(Prm0.PTLC * CmH2O, Prm0.PSalineTLC * CmH2O, 0.126);
  BuildWallLaws(NormalAsthma, RefLaws, notes);
  Z := TZero.Create;
  Add('normal', False, False, 0, 12);
  Add('normal_heliox', False, True, 0, 12);
  Add('baseline', True, False, 0.8, 12);
  Add('salbutamol', True, False, Salb, 12);
  Add('tone_0.7', True, False, 0.7, 12);
  Add('tone_0.6', True, False, 0.6, 12);
  Add('tone_0.5', True, False, 0.5, 12);
  Add('heliox', True, True, 0.8, 12);
  Add('salbutamol_heliox', True, True, Salb, 12);
  Add('rate8', True, False, 0.8, 8);
  Add('salbutamol_heliox_rate8', True, True, Salb, 8);
  only := '';
  OptStr('only', only);
  Res := TStringList.Create;
  Res.Add('run,rate_pmin,tone,heliox,Ppeak_cmH2O,Pplat_cmH2O,PEEPtot_cmH2O,EEV_above_FRC_mL,VEI_mL,'
    + 'units_shut_all_breath,shunt_pct,PaO2_mmHg,PaCO2_mmHg,SaO2');
  Writeln('run                    rate  tone   Ppeak  Pplat  PEEPtot  EEV-FRC   VEI   shut  shunt%  PaO2  PaCO2  SaO2');
  for i := 0 to High(Runs) do
    if (only = '') or (only = Runs[i].Name) then DoTreat(Runs[i]);
  if only = '' then Res.SaveToFile(OutDir + '/treat.csv')
  else Res.SaveToFile(Format('%s/treat_%s.csv', [OutDir, only]));
  Res.Free;
  Z.Free;
  for i := 0 to NWall - 1 do RefLaws[i].Free;
end.
