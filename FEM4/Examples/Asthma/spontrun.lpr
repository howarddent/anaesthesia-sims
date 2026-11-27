program spontrun;

{ Stage 9: the spontaneously breathing acute asthmatic, before
  intubation, and what treatment does for the work of breathing.

  LUNG   stage 8's: the patchy lung (256 units) with wall x 3, normal
  lining, airway muscle tone 0.8 that ignores stretch (10 % clustered
  spread), closure hysteresis on; the natural upper airway (Rohrer K1
  0.3, K2 0.05), not a tube.

  BREATHING   the inspiratory muscles' pressure is a half-sine over Ti,
  decaying with time constant 0.15 s after it (as tonerun), at 25 /min
  with Ti/Ttot 0.35: the fast, short-inspiration pattern of acute
  asthma. Expiration is passive (expiratory muscle effort can't speed a
  flow-limited expiration, only raise its pleural pressure). The drive
  is set breath by breath towards a tidal volume of 500 mL (12.5 L/min),
  capped at 50 cmH2O (--pmax); a patient who can't reach the target at
  the cap is shown so.

  MEASURED over the last 10 of 60 breaths (--breaths):
    VT, the muscle pressure that drives it, and the work it does
      (integral of Pmus dV over inspiration, J/min; normal 0.3-0.6 J
      per litre ventilated);
    end-expiratory lung volume above FRC, and above the relaxed volume
      at the CPAP (the dynamic hyperinflation alone: CPAP raises the
      relaxed volume itself, by StaticState with muscle pressure equal
      to the CPAP, which sets the same transpulmonary pressure); and
      intrinsic PEEP (mean alveolar pressure over the open units at
      end expiration, above the airway pressure): the threshold load
      the inspiratory muscles must overcome before any gas moves;
    pleural pressure swing (the drop from end expiration to its lowest
      in inspiration): the cause of pulsus paradoxus, which tracks it
      (Martin, Am Rev Respir Dis 1981);
    tension-time index TTI = (mean Pmus / Pimax) (Ti / Ttot), with mean
      Pmus 2/pi times the peak of the half-sine and Pimax 100 cmH2O at
      FRC falling linearly to 0 at TLC (hyperinflated muscles are
      shorter and weaker; assumed). Above 0.15 the diaphragm fatigues
      (Bellemare and Grassino, J Appl Physiol 1982);
    units shut all breath, and blood gases (uGasExchange, with hypoxic
      vasoconstriction, from the last 10 breaths' unit inflows; VO2 300,
      VCO2 240 mL/min for the work of breathing, assumed).

  TREATMENTS (FiO2 0.3 except the first): asthma on air; asthma on 30 %;
  salbutamol (tone 0.6, --salb); heliox 70:30 (density x 0.46,
  viscosity x 1.09, in the lung and upper airway); CPAP 5 and 10 cmH2O;
  salbutamol + heliox; salbutamol + CPAP 5. Normal lung for reference.
  Options: --only=<run>, --salb, --pmax, --breaths, --dt (0.004),
  --out (out). Writes <out>/spont_<run>.csv (one row per breath),
  <out>/spont_<run>_sum.csv (the summary row) and
  <out>/spont_<run>_trace.csv: every step of the last breath - pleural
  pressure at mid-height, airway pressure, lung volume above FRC, muscle
  pressure, and the volume-weighted alveolar pressure of the units in
  each quarter of the lung's height (shut units included: their trapped
  gas squeezes the vessels too). Stage 10's pulsusrun reads it.

  Build:  fpc -O3 -FUlib -Fu../../../newVM -Fi../../../newVM spontrun.lpr }

{$mode delphi}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Classes, Math, StrUtils, cblas, newVM, uTubeLaw, uAirwayRing, uAlveolus, uLungModel, uPatchyLung,
  uGasExchange;

type
  TMuscles = class
  public
    Pmax, Ti, Ttot, Tau: Double;
    function P(t, V: Double): Double;
  end;

  TCase = record
    Name: string;
    Asthma, Heliox: Boolean;
    Tone, CPAP, FiO2: Double;
  end;

function TMuscles.P(t, V: Double): Double;
var
  tb: Double;
begin
  tb := t - Ttot * Floor(t / Ttot + 1e-9);
  if tb < Ti then Result := Pmax * Sin(0.5 * Pi * tb / Ti)
  else Result := Pmax * Exp(-(tb - Ti) / Tau);
end;

const
  Rate = 25; TiFrac = 0.35; VTTarget = 0.5;
  HelioxRho = 0.554 / 1.20;
  HelioxVisc = 1.09;
  HPVMax = 0.6; HPV50 = 60;
  Pimax0 = 100;
  NAvg = 10;

var
  OutDir: string = 'out';
  Dt: Double = 0.004;
  Salb: Double = 0.6;
  PCap: Double = 50;
  NBreaths: Integer = 60;
  Alv: TAlveolusParams;
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

function Cm(p: Double): Double;
begin
  Result := p / CmH2O;
end;

procedure DoCase(const C: TCase);
var
  Prm: TLungParams;
  PP: TPatchyParams;
  A: TAsthma;
  L: TPatchyLung;
  Sim: TPatchySim;
  Mus: TMuscles;
  NU, u, b, st, n, nOpen, nShut, it: Integer;
  VF, VIn, VAu, Perf, Qp, PAO2, PACO2: array of Double;
  OpenB: array of Boolean;
  frc, frcC, vlung, vt, wk, x, pplEE, pplMin, swing, eelv, peepi, pimax, tti, vinTot, qs, qShunt, sat: Double;
  VC: array of Double;
  sVT, sPm, sWk, sEE, sPi, sSw, sTTI: Double;
  capped: Boolean;
  BG: TBloodGases;
  GP: TGasParams;
  F, S, Tr: TStringList;
  t1: QWord;
  band: Integer;
  pb, vb: array[0..3] of Double;
begin
  t1 := GetTickCount64;
  Prm := DefaultLungParams;
  if C.Heliox then
  begin
    Prm.Rho := Prm.Rho * HelioxRho; Prm.Visc := Prm.Visc * HelioxVisc;
    Prm.K1 := Prm.K1 * HelioxVisc; Prm.K2 := Prm.K2 * HelioxRho;
  end;
  PP := DefaultPatchyParams;
  PP.ActMode := True; PP.DS := 0.05; PP.SMax := 0.9;
  if C.Asthma then
  begin
    A.Act := C.Tone; A.Thick := 3; A.Mucus := 1; PP.Sigma := 0.1;
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
    VIn[u] := 0; OpenB[u] := False;
  end;
  SetLength(VC, NU);
  L.StaticState(C.CPAP, VC);
  frcC := Prm.VDead;
  for u := 0 to NU - 1 do frcC := frcC + VC[u];
  Mus := TMuscles.Create;
  Mus.Ttot := 60 / Rate; Mus.Ti := TiFrac * Mus.Ttot; Mus.Tau := 0.15;
  if C.Asthma then Mus.Pmax := 20 else Mus.Pmax := 8;
  Sim := TPatchySim.Create(L, Mus.P, VF, Dt);
  Sim.Paw := C.CPAP * CmH2O;
  Sim.Evaluate;
  n := Round(Mus.Ttot / Dt);
  F := TStringList.Create;
  F.Add('breath,t_s,VT_mL,Pmus_peak_cmH2O,work_J_per_min,EELV_above_FRC_mL,PEEPi_cmH2O,Ppl_swing_cmH2O,TTI,units_shut_all_breath');
  sVT := 0; sPm := 0; sWk := 0; sEE := 0; sPi := 0; sSw := 0; sTTI := 0; nShut := 0;
  capped := False;
  Tr := TStringList.Create;
  Tr.Add(Format('# height_cm=%.1f bands=4 frc_L=%.4f', [PP.Height, frc]));
  Tr.Add('t_s,Ppl_cmH2O,Paw_cmH2O,V_above_FRC_mL,Pmus_cmH2O,Palv0_cmH2O,Palv1_cmH2O,Palv2_cmH2O,Palv3_cmH2O');
  for b := 1 to NBreaths do
  begin
    vlung := Sim.VTot; vt := 0; wk := 0;
    pplEE := Sim.Ppl; pplMin := Sim.Ppl;
    for u := 0 to NU - 1 do OpenB[u] := False;
    for st := 1 to n do
    begin
      x := Sim.VTot;
      Sim.Step;
      if Sim.VTot > x then wk := wk + Sim.Pmus * (Sim.VTot - x);
      vt := Max(vt, Sim.VTot - vlung);
      pplMin := Min(pplMin, Sim.Ppl);
      if b = NBreaths then
      begin
        for band := 0 to 3 do begin pb[band] := 0; vb[band] := 0; end;
        for u := 0 to NU - 1 do
        begin
          band := Min(3, Trunc(4 * L.PY[u] / PP.Height));
          pb[band] := pb[band] + L.Pu[u] * Sim.V[u]; vb[band] := vb[band] + Sim.V[u];
        end;
        Tr.Add(Format('%.4f,%.4f,%.4f,%.2f,%.4f,%.4f,%.4f,%.4f,%.4f', [st * Sim.Dt, Cm(Sim.Ppl), Cm(Sim.Paw),
          1000 * (Sim.VTot - frc), Sim.Pmus, Cm(pb[0] / vb[0]), Cm(pb[1] / vb[1]), Cm(pb[2] / vb[2]), Cm(pb[3] / vb[3])]));
      end;
      for u := 0 to NU - 1 do
      begin
        if not L.Shut[u] then OpenB[u] := True;
        if (b > NBreaths - NAvg) and (L.Qu[u] < 0) then VIn[u] := VIn[u] - L.Qu[u] * Sim.Dt / LitreMM3;
      end;
    end;
    eelv := Sim.VTot;
    { intrinsic PEEP: mean alveolar pressure of the open units above the airway pressure }
    peepi := 0; x := 0; nOpen := 0;
    for u := 0 to NU - 1 do
      if not L.Shut[u] then
      begin
        peepi := peepi + (L.Pu[u] - Sim.Paw) * Sim.V[u]; x := x + Sim.V[u]; Inc(nOpen);
      end;
    if x > 0 then peepi := Cm(peepi / x);
    swing := Cm(pplEE - pplMin);
    pimax := Pimax0 * Max(0.05, 1 - (eelv - frc) / (Prm.TLC - frc));
    tti := (2 / Pi * Mus.Pmax / pimax) * TiFrac;
    nShut := 0;
    for u := 0 to NU - 1 do if not OpenB[u] then Inc(nShut);
    F.Add(Format('%d,%.2f,%.1f,%.2f,%.3f,%.1f,%.2f,%.2f,%.4f,%d', [b, Sim.T, 1000 * vt, Mus.Pmax,
      Rate * wk * JPerCmH2OL, 1000 * (eelv - frc), peepi, swing, tti, nShut]));
    if b > NBreaths - NAvg then
    begin
      sVT := sVT + vt / NAvg; sPm := sPm + Mus.Pmax / NAvg; sWk := sWk + Rate * wk * JPerCmH2OL / NAvg;
      sEE := sEE + (eelv - frc) / NAvg; sPi := sPi + peepi / NAvg; sSw := sSw + swing / NAvg;
      sTTI := sTTI + tti / NAvg;
    end;
    { the drive, towards the target tidal volume, within the cap }
    if vt > 1e-4 then x := Mus.Pmax * Power(VTTarget / vt, 0.5) else x := 1.5 * Mus.Pmax;
    if x > PCap then
    begin
      x := PCap;
      if b > NBreaths - NAvg then capped := True;
    end;
    Mus.Pmax := Max(1, x);
  end;
  { blood gases from the last NAvg breaths }
  GP := DefaultGasParams; GP.FiO2 := C.FiO2; GP.VO2 := 300; GP.VCO2 := 240;
  vinTot := 0;
  for u := 0 to NU - 1 do vinTot := vinTot + VIn[u] / NAvg;
  for u := 0 to NU - 1 do
  begin
    if (vinTot > Prm.VDead) and (VIn[u] > 0) then VAu[u] := Rate * VIn[u] / NAvg * (1 - Prm.VDead / vinTot)
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
  Writeln(Format('%-20s %4.0f%s %5.1f  %5.1f   %5.0f  %5.0f   %5.1f   %5.1f   %5.3f   %3d  %4.1f  %5.1f  %4.1f  %4.0f  (%.0f s)',
    [C.Name, 1000 * sVT, IfThen(capped, '*', ' '), sPm, sWk, 1000 * sEE, 1000 * (sEE + frc - frcC), sPi, sSw, sTTI, nShut, 100 * qShunt,
     BG.PaO2, BG.PaCO2, 100 * BG.SaO2, (GetTickCount64 - t1) / 1000]));
  S := TStringList.Create;
  S.Add('run,FiO2,CPAP_cmH2O,tone,heliox,VT_mL,capped,Pmus_peak_cmH2O,work_J_per_min,EELV_above_FRC_mL,'
    + 'EELV_above_relaxed_at_CPAP_mL,PEEPi_cmH2O,Ppl_swing_cmH2O,TTI,units_shut_all_breath,shunt_pct,PaO2_mmHg,PaCO2_mmHg,SaO2');
  S.Add(Format('%s,%.2f,%.1f,%.2f,%d,%.1f,%d,%.2f,%.3f,%.1f,%.1f,%.2f,%.2f,%.4f,%d,%.2f,%.1f,%.2f,%.4f', [C.Name, C.FiO2,
    C.CPAP, C.Tone, Ord(C.Heliox), 1000 * sVT, Ord(capped), sPm, sWk, 1000 * sEE, 1000 * (sEE + frc - frcC), sPi, sSw, sTTI, nShut,
    100 * qShunt, BG.PaO2, BG.PaCO2, BG.SaO2]));
  S.SaveToFile(Format('%s/spont_%s_sum.csv', [OutDir, C.Name]));
  F.SaveToFile(Format('%s/spont_%s.csv', [OutDir, C.Name]));
  Tr.SaveToFile(Format('%s/spont_%s_trace.csv', [OutDir, C.Name]));
  S.Free; F.Free; Tr.Free;
  Sim.Free; Mus.Free; L.Free;
end;

var
  Cases: array of TCase;
  i: Integer;
  notes, only: string;
  Prm0: TLungParams;
  d: Double;

procedure Add(const N: string; As_, He: Boolean; ATone, ACPAP, AFiO2: Double);
begin
  SetLength(Cases, Length(Cases) + 1);
  Cases[High(Cases)].Name := N; Cases[High(Cases)].Asthma := As_; Cases[High(Cases)].Heliox := He;
  Cases[High(Cases)].Tone := ATone; Cases[High(Cases)].CPAP := ACPAP; Cases[High(Cases)].FiO2 := AFiO2;
end;

begin
  InitializeCBLAS;
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  DefaultFormatSettings.DecimalSeparator := '.';
  OptStr('out', OutDir);
  ForceDirectories(OutDir);
  OptVal('dt', Dt);
  OptVal('salb', Salb);
  OptVal('pmax', PCap);
  d := NBreaths; if OptVal('breaths', d) then NBreaths := Round(d);
  Prm0 := DefaultLungParams;
  Alv := FitAlveolus(Prm0.PTLC * CmH2O, Prm0.PSalineTLC * CmH2O, 0.126);
  BuildWallLaws(NormalAsthma, RefLaws, notes);
  Add('normal', False, False, 0, 0, 0.21);
  Add('asthma_air', True, False, 0.8, 0, 0.21);
  Add('asthma', True, False, 0.8, 0, 0.3);
  Add('salbutamol', True, False, Salb, 0, 0.3);
  Add('heliox', True, True, 0.8, 0, 0.3);
  Add('cpap5', True, False, 0.8, 5, 0.3);
  Add('cpap10', True, False, 0.8, 10, 0.3);
  Add('salbutamol_heliox', True, True, Salb, 0, 0.3);
  Add('salbutamol_cpap5', True, False, Salb, 5, 0.3);
  only := '';
  OptStr('only', only);
  Writeln('run                    VT   Pmus   work  EEV-FRC  dyn.  PEEPi  Ppl swing  TTI  shut shunt  PaO2 PaCO2 SaO2');
  for i := 0 to High(Cases) do
    if (only = '') or (only = Cases[i].Name) then DoCase(Cases[i]);
  for i := 0 to NWall - 1 do RefLaws[i].Free;
end.
