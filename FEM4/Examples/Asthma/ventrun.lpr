program ventrun;

{ Stage 5: the paralysed patient with severe asthma on a ventilator.

  The patchy lung of uPatchyLung in activation mode (256 units, gravity,
  a clustered 10 % spread of tone), with no muscle pressure, so the
  pleural pressure is the chest wall's recoil. An endotracheal tube
  replaces the upper airway: Rohrer K1 1, K2 4 cmH2O/(L/s)^n, about
  5 cmH2O at 1 L/s, assumed for an 8 mm tube with its connectors.

  VENTILATOR   volume control with a square flow wave, inspiratory flow
  60 L/min (1 L/s; --flow); then expiration to the set PEEP. Settings,
  after Tuxen and Lane (Am Rev Respir Dis 1987), who varied minute
  ventilation, tidal volume and expiratory time in ventilated
  asthmatics: tidal volume 0.5 L at 8, 12, 16, 20 and 24 /min, 1.0 L at
  10 /min, and 0.5 L at 16 /min with PEEP 5 and 10 cmH2O.

  Each setting starts from the relaxed lung at its PEEP and runs until
  the end-expiratory volume moves less than 0.5 mL a breath (at most 60
  breaths). Then, as at the bedside:
    PEAK       the largest airway opening pressure;
    PLATEAU    an end-inspiratory hold of 0.5 s;
    TOTAL PEEP an end-expiratory hold of 2 s; intrinsic PEEP = total -
               set PEEP;
    VEI        Tuxen's end-inspiratory volume above FRC, measured as he
               did: from an end-inspiration the circuit is opened to
               the air for 30 s and the volume exhaled is VEI (FRC being
               where the apnoea ends). Also the volume left above the
               relaxed FRC after it: gas the apnoea can't empty.
  Tuxen and Lane found VEI over 1.4 L (20 mL/kg) went with hypotension
  and barotrauma, and that lowering minute ventilation, mainly by
  lengthening expiration, lowered VEI, plateau and intrinsic PEEP.

  Lungs: normal (no tone, normal wall and lining), and status asthmaticus
  (wall x 3, the thickening of fatal asthma (James et al. 1989), normal
  lining, tone --dose (0.8) in the units and the trunk, tone that
  ignores stretch: stage 4's asthmatic muscle).
  Options: --only=<lung>, --dose, --thick (3), --mucus (1), --name
  (asthma: the asthmatic lung's name in the files), --flow=<L/s>, --k, --seed, --dt
  (0.004), --out (out), --quick (settings 2 and 5 only).
  Writes <out>/vent_<lung>.csv (a row per setting) and
  <out>/vent_<lung>_<n>.csv (the measured breath, holds included, and
  the apnoea).

  Build:  fpc -O3 -FUlib -Fu../../../newVM -Fi../../../newVM ventrun.lpr }

{$mode delphi}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Classes, Math, cblas, newVM, uTubeLaw, uAirwayRing, uAlveolus, uLungModel, uPatchyLung;

type
  TZero = class
    function P(t, V: Double): Double;
  end;

  TSetting = record
    VT, Rate, PEEP: Double;   { L, /min, cmH2O }
  end;

function TZero.P(t, V: Double): Double;
begin
  Result := 0;
end;

const
  Settings: array[0..7] of TSetting = (
    (VT: 0.5; Rate: 8; PEEP: 0), (VT: 0.5; Rate: 12; PEEP: 0), (VT: 0.5; Rate: 16; PEEP: 0),
    (VT: 0.5; Rate: 20; PEEP: 0), (VT: 0.5; Rate: 24; PEEP: 0), (VT: 1.0; Rate: 10; PEEP: 0),
    (VT: 0.5; Rate: 16; PEEP: 5), (VT: 0.5; Rate: 16; PEEP: 10));

var
  OutDir: string = 'out';
  Dt: Double = 0.004;
  Flow: Double = 1.0;
  Dose: Double = 0.8;
  AThick: Double = 3;
  AMucus: Double = 1;
  AName: string = 'asthma';
  Quick: Boolean = False;
  Prm: TLungParams;
  Alv: TAlveolusParams;
  PPBase: TPatchyParams;
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

var
  Log: TStringList;
  LogT0: Double;
  Logging: Boolean;

{ advance Sim for time Dur in its current mode; returns the largest Paw }
function Run(Sim: TPatchySim; Dur: Double): Double;
var
  n, k: Integer;
begin
  Result := -1e30;
  n := Max(1, Round(Dur / Sim.Dt));
  for k := 1 to n do
  begin
    Sim.Step;
    Result := Max(Result, Sim.Paw);
    if Logging and (k mod 5 = 0) then
      Log.Add(Format('%.3f,%.4f,%.5f,%.5f,%.4f,%d,%d', [Sim.T - LogT0, Cm(Sim.Paw), Sim.Q / LitreMM3,
        Sim.VTot, Cm(Sim.Ppl), Sim.NLim, Sim.NClosed]));
  end;
end;

procedure Inspire(Sim: TPatchySim; Ti: Double);
begin
  Sim.Mode := smFlow; Sim.QSet := -Flow * LitreMM3;
  Sim.Evaluate;
end;

procedure Expire(Sim: TPatchySim; PEEP: Double);
begin
  Sim.Mode := smPressure; Sim.Paw := PEEP * CmH2O;
  Sim.Evaluate;
end;

procedure Hold(Sim: TPatchySim);
begin
  Sim.Mode := smFlow; Sim.QSet := 0;
  Sim.Evaluate;
end;

procedure DoLung(const Name: string; const A: TAsthma; Sigma: Double);
var
  PP: TPatchyParams;
  L: TPatchyLung;
  Sim: TPatchySim;
  NU, u, si, b, nl: Integer;
  V0, VF: array of Double;
  frc0, frcP, Ti, Te, eev, eevOld, ppk, pplat, ptot, vei, veiA, vLeft, vEndInsp, x: Double;
  F: TStringList;
  t1: QWord;
  conv: Integer;
begin
  PP := PPBase;
  PP.ActMode := True; PP.DS := 0.05; PP.SMax := 0.9; PP.Sigma := Sigma;
  Writeln(Format('=== %s: tone %.2f, wall x %.2f, lining x %.1f; %d units; inspiratory flow %.0f L/min; tube K1 %.1f K2 %.1f',
    [Name, A.Act, A.Thick, A.Mucus, 1 shl PP.K, 60 * Flow, Prm.K1, Prm.K2]));
  L := TPatchyLung.Create(Prm, PP, A, Alv, RefLaws);
  NU := L.NU; nl := L.LevelCount;
  SetLength(V0, NU); SetLength(VF, NU);
  L.StaticState(0, VF);
  frc0 := Prm.VDead;
  for u := 0 to NU - 1 do frc0 := frc0 + VF[u];
  nl := 0;
  for u := 0 to NU - 1 do
    if L.UnitPel(VF[u]) <= L.Tables[L.Level[u]].PClose then Inc(nl);
  Writeln(Format('  relaxed FRC %.2f L; %d of %d units shut there', [frc0, nl, NU]));
  F := TStringList.Create;
  F.Add('setting,VT_L,rate_pmin,PEEP_cmH2O,VE_Lpmin,Ti_s,Te_s,breaths,Ppeak_cmH2O,Pplat_cmH2O,PEEPtot_cmH2O,'
    + 'PEEPi_cmH2O,EEV_above_FRC_mL,VEI_mL,VEI_apnoea_mL,left_after_apnoea_mL');
  Writeln('  VT    rate  PEEP   VE    Te   breaths  Ppeak  Pplat  PEEPtot  PEEPi   EEV-FRC  VEI   VEI(apnoea)  left');
  for si := 0 to High(Settings) do
  begin
    if Quick and (si <> 1) and (si <> 4) then Continue;
    t1 := GetTickCount64;
    Ti := Settings[si].VT / Flow;
    Te := 60 / Settings[si].Rate - Ti;
    { relaxed at the PEEP }
    L.StaticState(Settings[si].PEEP, V0);
    frcP := Prm.VDead;
    for u := 0 to NU - 1 do frcP := frcP + V0[u];
    Sim := TPatchySim.Create(L, Z.P, V0, Dt);
    eevOld := Sim.VTot; conv := 0;
    for b := 1 to 60 do
    begin
      Inspire(Sim, Ti); Run(Sim, Ti);
      Expire(Sim, Settings[si].PEEP); Run(Sim, Te);
      eev := Sim.VTot;
      if Abs(eev - eevOld) < 0.0005 then Inc(conv) else conv := 0;
      eevOld := eev;
      if conv >= 2 then Break;
    end;
    { the measured breath: inspiration, 0.5 s hold, expiration, 2 s hold }
    Log := TStringList.Create;
    Log.Add('t_s,Paw_cmH2O,flow_Lps,V_L,Ppl_cmH2O,units_limited,units_shut');
    Logging := True; LogT0 := Sim.T;
    Inspire(Sim, Ti); ppk := Run(Sim, Ti);
    vEndInsp := Sim.VTot;
    Hold(Sim); Run(Sim, 0.5); pplat := Sim.Paw;
    Expire(Sim, Settings[si].PEEP); Run(Sim, Te);
    eev := Sim.VTot;
    Hold(Sim); Run(Sim, 2); ptot := Sim.Paw;
    { one more breath, then the apnoea from its end-inspiration }
    Expire(Sim, Settings[si].PEEP); Run(Sim, Te);
    Inspire(Sim, Ti); Run(Sim, Ti);
    x := Sim.VTot;
    Expire(Sim, 0); Run(Sim, 30);
    veiA := x - Sim.VTot;
    vLeft := Sim.VTot - frc0;
    vei := vEndInsp - frc0;
    Logging := False;
    Log.SaveToFile(Format('%s/vent_%s_%d.csv', [OutDir, Name, si]));
    Log.Free;
    Writeln(Format('  %.1f   %4.0f   %4.0f  %5.1f  %4.2f   %3d    %5.1f  %5.1f   %5.1f   %5.1f   %6.0f  %5.0f    %5.0f    %5.0f   (%.0f s)',
      [Settings[si].VT, Settings[si].Rate, Settings[si].PEEP, Settings[si].VT * Settings[si].Rate, Te, b,
       Cm(ppk), Cm(pplat), Cm(ptot), Cm(ptot) - Settings[si].PEEP, 1000 * (eev - frc0), 1000 * vei,
       1000 * veiA, 1000 * vLeft, (GetTickCount64 - t1) / 1000]));
    F.Add(Format('%d,%.2f,%.1f,%.1f,%.2f,%.3f,%.3f,%d,%.3f,%.3f,%.3f,%.3f,%.1f,%.1f,%.1f,%.1f',
      [si, Settings[si].VT, Settings[si].Rate, Settings[si].PEEP, Settings[si].VT * Settings[si].Rate, Ti, Te,
       b, Cm(ppk), Cm(pplat), Cm(ptot), Cm(ptot) - Settings[si].PEEP, 1000 * (eev - frc0), 1000 * vei,
       1000 * veiA, 1000 * vLeft]));
    Sim.Free;
  end;
  F.SaveToFile(Format('%s/vent_%s.csv', [OutDir, Name]));
  F.Free;
  L.Free;
  Writeln;
end;

var
  i: Integer;
  notes, only: string;
  d: Double;
  A: TAsthma;
begin
  InitializeCBLAS;
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  DefaultFormatSettings.DecimalSeparator := '.';
  OptStr('out', OutDir);
  ForceDirectories(OutDir);
  OptVal('dt', Dt);
  OptVal('flow', Flow);
  OptVal('dose', Dose);
  OptVal('thick', AThick);
  OptVal('mucus', AMucus);
  OptStr('name', AName);
  Quick := HasOpt('quick');
  PPBase := DefaultPatchyParams;
  d := PPBase.K; if OptVal('k', d) then PPBase.K := Round(d);
  d := PPBase.Seed; if OptVal('seed', d) then PPBase.Seed := Round(d);
  Prm := DefaultLungParams;
  Prm.K1 := 1; Prm.K2 := 4;
  Alv := FitAlveolus(Prm.PTLC * CmH2O, Prm.PSalineTLC * CmH2O, 0.126);
  BuildWallLaws(NormalAsthma, RefLaws, notes);
  Z := TZero.Create;
  only := '';
  OptStr('only', only);
  if (only = '') or (only = 'normal') then
  begin
    A.Act := 0; A.Thick := 1; A.Mucus := 1;
    DoLung('normal', A, 0);
  end;
  if (only = '') or (only = 'asthma') or (only = AName) then
  begin
    A.Act := Dose; A.Thick := AThick; A.Mucus := AMucus;
    DoLung(AName, A, 0.1);
  end;
  Z.Free;
  for i := 0 to NWall - 1 do RefLaws[i].Free;
end.
