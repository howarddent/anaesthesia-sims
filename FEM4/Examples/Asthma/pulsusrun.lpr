program pulsusrun;

{ Stage 10: pulsus paradoxus. The circulation of uCirculation (both
  ventricles, septum, pericardium, intra- and extrathoracic vessels,
  West's zones in the lung) is driven by the pleural and alveolar
  pressures of stage 9's spontaneously breathing lung: spontrun's last
  breath (out/spont_<run>_trace.csv, which spontrun writes), repeated.
  The lung does not feel the circulation back.

  Heart rate 107 /min in every case (--hr), against breathing at 25 /min:
  107 and 25 share no factor, so over 25 breaths the beats fall at 107
  different phases of the breath (at 110 they fall at only 22, 4.4 beats
  a breath, and some phase bins stay empty).
  10 breaths settle the circulation, then 40 (--breaths) are measured.

  MEASURED, beat by beat, in the systemic arteries outside the chest
  (where a cuff is): systolic and diastolic pressure, and both
  ventricles' stroke volumes, each beat placed in the breath by the time
  of its systolic peak (phase 0 = start of inspiration, which lasts 0.35
  of the breath).
    pulsus paradoxus, as at the bedside: within each breath, the highest
    systolic pressure less the lowest, averaged over the breaths;
    the envelope: the beats' systolic pressures averaged in 24 bins of
    phase, highest bin less lowest - the same quantity without the
    beat sampling;
    pulse pressure variation (max - min)/mean, over the bins;
    the phases of the lowest systolic pressure, the largest right and
    the smallest left stroke volume;
    the share of time the great veins are collapsed at the thoracic
    inlet.
  Ppl swing is the pleural pressure's range over the breath, mmHg.

  MECHANISMS, on every case (--only=<run> for one):
    full          the model;
    rigid         no direct ventricular interdependence: rigid septum
                  and no pericardium;
    veins         the systemic veins (and the collapse pressure at the
                  thoracic inlet) follow the pleural pressure's swing
                  about its mean, so inspiration draws no extra blood
                  into the chest while the mean filling is unchanged;
    nozones       the pulmonary vessels a plain resistance, not squeezed
                  by the alveolar pressure;
    steady        Ppl and Palv held at their means over the breath: the
                  measurement floor (beat sampling, the heart's own
                  slow transients);
    dry, wet      the full model with 300 mL less or more stressed
                  blood volume (1500, 2100 against 1800 mL);
    aorta         the thoracic share of the arterial compliance raised
                  from 0.41 (0.6 of 1.45 mL/mmHg) to 0.6, the total kept.

  Writes out/pulsus.csv (a row per case and mechanism),
  out/pulsus_<run>_beats.csv (the full model's beats) and
  out/pulsus_<run>_wave.csv (the full model's last two breaths, every
  5 ms).

  Build:  fpc -O3 -FUlib -Fu../../../newVM -Fi../../../newVM pulsusrun.lpr }

{$mode delphi}{$H+}

uses
  SysUtils, Classes, Math, uCirculation;

const
  NBin = 24;
  NBand = 4;

type
  TTrace = class
  public
    N: Integer;
    TB, Height: Double;
    Tt, Ppl: array of Double;
    Palv: array[0..NBand - 1] of array of Double;
    Steady: Boolean;
    MeanPpl: Double;
    MeanPalv: array[0..NBand - 1] of Double;
    procedure Load(const FN: string);
    procedure At(t: Double; var P: Double; var Pa: array of Double);
  end;

  TExp = (exFull, exRigid, exVeins, exNoZones, exSteady, exDry, exWet, exAorta);

const
  ExpName: array[TExp] of string = ('full', 'rigid', 'veins', 'nozones', 'steady', 'dry', 'wet', 'aorta');

var
  OutDir: string = 'out';
  HR: Double = 107;
  NMeas: Integer = 40;
  Dt: Double = 0.0005;
  Summary: TStringList;

procedure TTrace.Load(const FN: string);
var
  L, F: TStringList;
  i, k: Integer;
  s: string;
begin
  L := TStringList.Create; F := TStringList.Create;
  L.LoadFromFile(FN);
  s := L[0];
  Height := StrToFloat(Copy(s, Pos('height_cm=', s) + 10, Pos(' bands', s) - Pos('height_cm=', s) - 10));
  N := L.Count - 2;
  SetLength(Tt, N); SetLength(Ppl, N);
  for k := 0 to NBand - 1 do SetLength(Palv[k], N);
  F.StrictDelimiter := True; F.Delimiter := ',';
  for i := 0 to N - 1 do
  begin
    F.DelimitedText := L[i + 2];
    Tt[i] := StrToFloat(F[0]);
    Ppl[i] := StrToFloat(F[1]) * MmHgPerCmH2O;
    for k := 0 to NBand - 1 do Palv[k][i] := StrToFloat(F[5 + k]) * MmHgPerCmH2O;
  end;
  TB := Tt[N - 1];
  MeanPpl := 0;
  for k := 0 to NBand - 1 do MeanPalv[k] := 0;
  for i := 0 to N - 1 do
  begin
    MeanPpl := MeanPpl + Ppl[i] / N;
    for k := 0 to NBand - 1 do MeanPalv[k] := MeanPalv[k] + Palv[k][i] / N;
  end;
  Steady := False;
  L.Free; F.Free;
end;

{ linear in time, periodic: sample i is at Tt[i] = (i+1) dt, the last at TB = 0 }
procedure TTrace.At(t: Double; var P: Double; var Pa: array of Double);
var
  tIn, x, w: Double;
  i0, i1, k: Integer;
  dts: Double;
begin
  if Steady then
  begin
    P := MeanPpl;
    for k := 0 to NBand - 1 do Pa[k] := MeanPalv[k];
    Exit;
  end;
  tIn := t - TB * Floor(t / TB);
  dts := TB / N;
  x := tIn / dts - 1;          { index position: sample i at x = i }
  if x < 0 then begin i0 := N - 1; i1 := 0; w := x + 1; end
  else
  begin
    i0 := Min(N - 1, Trunc(x)); i1 := (i0 + 1) mod N; w := x - i0;
  end;
  P := Ppl[i0] + w * (Ppl[i1] - Ppl[i0]);
  for k := 0 to NBand - 1 do Pa[k] := Palv[k][i0] + w * (Palv[k][i1] - Palv[k][i0]);
end;

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

procedure DoRun(const Run: string; Tr: TTrace; E: TExp);
var
  Prm: TCircParams;
  C: TCirculation;
  nSet, nTot, st, beat, lastBeat, nb, b, k, bin, nBr, cBr: Integer;
  t, tc, sbp, dbp, svl, svr, tPk, pplMin, pplMax, ph, co, map, cvp, mpa, edv, edvB,
    collapsed, tMeas, pul, sMax, sMin, ppv, ppMean: Double;
  BSbp, BDbp, BSvl, BSvr, BPh, BT: array of Double;
  binS, binP, binL, binR, binN: array[0..NBin - 1] of Double;
  phMinS, phMaxR, phMinL, x, svlMax, svlMin, svrMax, svrMin, vsMin, vsMax: Double;
  F, W: TStringList;
  brMax, brMin: Double;
  pa: array[0..NBand - 1] of Double;
begin
  Prm := DefaultCircParams;
  Prm.HR := HR;
  Prm.Height := Tr.Height;
  case E of
    exRigid: begin Prm.Septum := False; Prm.Pericardium := False; end;
    exVeins: begin Prm.VeinsInChest := True; Prm.PplMean := Tr.MeanPpl; end;
    exDry: Prm.VStressed := Prm.VStressed - 300;
    exWet: Prm.VStressed := Prm.VStressed + 300;
    exAorta:
      begin
        x := Prm.C[cAO] + Prm.C[cSA];
        Prm.C[cAO] := 0.6 * x; Prm.C[cSA] := 0.4 * x;
      end;
  end;
  C := TCirculation.Create(Prm);
  C.Thorax := Tr.At;
  if E = exNoZones then C.NBands := 0 else C.NBands := NBand;
  Tr.Steady := E = exSteady;
  { Ppl swing from the trace itself }
  pplMin := 1e9; pplMax := -1e9;
  for k := 0 to Tr.N - 1 do begin pplMin := Min(pplMin, Tr.Ppl[k]); pplMax := Max(pplMax, Tr.Ppl[k]); end;
  if E = exSteady then begin pplMin := Tr.MeanPpl; pplMax := Tr.MeanPpl; end;
  nSet := Round(10 * Tr.TB / Dt);
  nTot := nSet + Round(NMeas * Tr.TB / Dt);
  lastBeat := -1; sbp := -1e9; dbp := 1e9; svl := 0; svr := 0; tPk := 0; edvB := 0;
  SetLength(BSbp, 0); SetLength(BDbp, 0); SetLength(BSvl, 0); SetLength(BSvr, 0); SetLength(BPh, 0); SetLength(BT, 0);
  co := 0; map := 0; cvp := 0; mpa := 0; edv := 0; collapsed := 0; tMeas := 0; vsMin := 1e9; vsMax := -1e9;
  W := TStringList.Create;
  W.Add('t_s,phase,Ppl_mmHg,Psa_mmHg,Pao_mmHg,Plv_mmHg,Prv_mmHg,Ppa_mmHg,Ppu_mmHg,Pvc_mmHg,Vlv_mL,Vrv_mL,Vspt_mL,Qav_mLs,Qpv_mLs,Qvr_mLs,Qpul_mLs');
  for st := 1 to nTot do
  begin
    C.Step(Dt);
    t := C.T;
    beat := Floor(t / C.Period);
    if beat <> lastBeat then
    begin
      if (lastBeat >= 0) and (st > nSet + 1) and (svl > 0) then
      begin
        nb := Length(BSbp);
        SetLength(BSbp, nb + 1); SetLength(BDbp, nb + 1); SetLength(BSvl, nb + 1); SetLength(BSvr, nb + 1);
        SetLength(BPh, nb + 1); SetLength(BT, nb + 1);
        BSbp[nb] := sbp; BDbp[nb] := dbp; BSvl[nb] := svl; BSvr[nb] := svr; BT[nb] := tPk;
        BPh[nb] := (tPk - Tr.TB * Floor(tPk / Tr.TB)) / Tr.TB;
        edv := edv + edvB;
      end;
      lastBeat := beat; sbp := -1e9; dbp := 1e9; svl := 0; svr := 0; edvB := 0;
    end;
    if C.P[cSA] > sbp then begin sbp := C.P[cSA]; tPk := t; end;
    dbp := Min(dbp, C.P[cSA]);
    svl := svl + C.Qav * Dt; svr := svr + C.Qpv * Dt;
    edvB := Max(edvB, C.V[cLV]);
    if st > nSet then
    begin
      tMeas := tMeas + Dt;
      co := co + C.Qav * Dt; map := map + C.P[cSA] * Dt; cvp := cvp + C.P[cVC] * Dt; mpa := mpa + C.P[cPA] * Dt;
      if C.P[cVC] < Prm.PCollapse + IfThen(Prm.VeinsInChest, C.Ppl - Prm.PplMean, 0) then collapsed := collapsed + Dt;
      vsMin := Min(vsMin, C.Vspt); vsMax := Max(vsMax, C.Vspt);
    end;
    if (E = exFull) and (st > nTot - Round(2 * Tr.TB / Dt)) and (st mod 10 = 0) then
      W.Add(Format('%.4f,%.4f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.4f,%.2f,%.2f,%.2f,%.2f',
        [t - (nTot * Dt - 2 * Tr.TB), (t - Tr.TB * Floor(t / Tr.TB)) / Tr.TB, C.Ppl, C.P[cSA], C.P[cAO], C.P[cLV], C.P[cRV],
         C.P[cPA], C.P[cPU], C.P[cVC], C.V[cLV], C.V[cRV], C.Vspt, C.Qav, C.Qpv, C.Qvr, C.Qpul]));
  end;
  nb := Length(BSbp);
  co := co / tMeas * 60 / 1000; map := map / tMeas; cvp := cvp / tMeas; mpa := mpa / tMeas;
  edv := edv / Max(1, nb); collapsed := collapsed / tMeas;
  { bedside pulsus: breath by breath }
  pul := 0; nBr := 0;
  for b := 0 to NMeas - 1 do
  begin
    brMax := -1e9; brMin := 1e9; cBr := 0;
    for k := 0 to nb - 1 do
      if Floor(BT[k] / Tr.TB) = 10 + b then
      begin
        brMax := Max(brMax, BSbp[k]); brMin := Min(brMin, BSbp[k]); Inc(cBr);
      end;
    if cBr >= 2 then begin pul := pul + brMax - brMin; Inc(nBr); end;
  end;
  if nBr > 0 then pul := pul / nBr;
  { envelope over the phase bins }
  for bin := 0 to NBin - 1 do begin binS[bin] := 0; binP[bin] := 0; binL[bin] := 0; binR[bin] := 0; binN[bin] := 0; end;
  for k := 0 to nb - 1 do
  begin
    bin := Min(NBin - 1, Trunc(BPh[k] * NBin));
    binS[bin] := binS[bin] + BSbp[k]; binP[bin] := binP[bin] + BSbp[k] - BDbp[k];
    binL[bin] := binL[bin] + BSvl[k]; binR[bin] := binR[bin] + BSvr[k]; binN[bin] := binN[bin] + 1;
  end;
  sMax := -1e9; sMin := 1e9; svlMax := -1e9; svlMin := 1e9; svrMax := -1e9; svrMin := 1e9;
  ppv := 0; ppMean := 0; x := 1e9; phMinS := 0; phMaxR := 0; phMinL := 0;
  brMax := -1e9; brMin := 1e9;
  for bin := 0 to NBin - 1 do
    if binN[bin] > 0 then
    begin
      ph := (bin + 0.5) / NBin;
      binS[bin] := binS[bin] / binN[bin]; binP[bin] := binP[bin] / binN[bin];
      binL[bin] := binL[bin] / binN[bin]; binR[bin] := binR[bin] / binN[bin];
      if binS[bin] > sMax then sMax := binS[bin];
      if binS[bin] < sMin then begin sMin := binS[bin]; phMinS := ph; end;
      if binR[bin] > svrMax then begin svrMax := binR[bin]; phMaxR := ph; end;
      svrMin := Min(svrMin, binR[bin]);
      if binL[bin] < svlMin then begin svlMin := binL[bin]; phMinL := ph; end;
      svlMax := Max(svlMax, binL[bin]);
      brMax := Max(brMax, binP[bin]); brMin := Min(brMin, binP[bin]);
      ppMean := ppMean + binP[bin]; x := x + 0;
    end;
  k := 0;
  for bin := 0 to NBin - 1 do if binN[bin] > 0 then Inc(k);
  ppMean := ppMean / Max(1, k);
  ppv := 100 * (brMax - brMin) / ppMean;
  Writeln(Format('%-18s %-8s %5.1f   %5.1f  %5.1f   %5.0f-%-5.0f %5.1f  %4.2f %4.2f %4.2f  %5.1f-%-5.1f %5.1f-%-5.1f %5.2f %5.1f %5.1f %5.1f %5.0f  %4.2f %5.2f',
    [Run, ExpName[E], pplMax - pplMin, pul, sMax - sMin, sMin, sMax, ppv, phMinS, phMaxR, phMinL,
     svrMin, svrMax, svlMin, svlMax, co, map, cvp, mpa, edv, collapsed, vsMax - vsMin]));
  Summary.Add(Format('%s,%s,%.2f,%.2f,%.2f,%.1f,%.1f,%.2f,%.3f,%.3f,%.3f,%.2f,%.2f,%.2f,%.2f,%.3f,%.2f,%.2f,%.2f,%.1f,%.4f,%.3f,%d',
    [Run, ExpName[E], pplMax - pplMin, pul, sMax - sMin, sMin, sMax, ppv, phMinS, phMaxR, phMinL,
     svrMin, svrMax, svlMin, svlMax, co, map, cvp, mpa, edv, collapsed, vsMax - vsMin, nb]));
  if E = exFull then
  begin
    F := TStringList.Create;
    F.Add('beat,t_s,phase,SBP_mmHg,DBP_mmHg,LVSV_mL,RVSV_mL');
    for k := 0 to nb - 1 do
      F.Add(Format('%d,%.4f,%.4f,%.2f,%.2f,%.2f,%.2f', [k, BT[k], BPh[k], BSbp[k], BDbp[k], BSvl[k], BSvr[k]]));
    F.SaveToFile(Format('%s/pulsus_%s_beats.csv', [OutDir, Run]));
    F.Free;
    W.SaveToFile(Format('%s/pulsus_%s_wave.csv', [OutDir, Run]));
  end;
  W.Free;
  C.Free;
end;

const
  Runs: array[0..7] of string = ('normal', 'asthma', 'salbutamol', 'heliox', 'cpap5', 'cpap10',
    'salbutamol_heliox', 'salbutamol_cpap5');
var
  i: Integer;
  E: TExp;
  Tr: TTrace;
  only, fn: string;
  d: Double;
begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  DefaultFormatSettings.DecimalSeparator := '.';
  OptStr('out', OutDir);
  OptVal('hr', HR);
  OptVal('dt', Dt);
  d := NMeas; if OptVal('breaths', d) then NMeas := Round(d);
  only := ''; OptStr('only', only);
  Summary := TStringList.Create;
  Summary.Add('run,mechanism,Ppl_swing_mmHg,pulsus_mmHg,pulsus_envelope_mmHg,SBP_min_mmHg,SBP_max_mmHg,PPV_pct,'
    + 'phase_SBP_min,phase_RVSV_max,phase_LVSV_min,RVSV_min_mL,RVSV_max_mL,LVSV_min_mL,LVSV_max_mL,CO_L_min,MAP_mmHg,'
    + 'CVP_mmHg,mPAP_mmHg,LVEDV_mL,veins_collapsed_frac,septum_shift_mL,beats');
  Writeln(Format('HR %.0f /min; phases are fractions of the breath from the start of inspiration (Ti = 0.35)', [HR]));
  Writeln('run                mech.    Ppl sw  pulsus  envel.  SBP range    PPV%  phase: SBPmin RVmax LVmin   RVSV        LVSV        CO    MAP   CVP   mPAP LVEDV  coll. septum');
  Tr := TTrace.Create;
  for i := 0 to High(Runs) do
  begin
    if (only <> '') and (only <> Runs[i]) then Continue;
    fn := Format('%s/spont_%s_trace.csv', [OutDir, Runs[i]]);
    if not FileExists(fn) then
    begin
      Writeln(fn, ' missing: run spontrun first');
      Continue;
    end;
    Tr.Load(fn);
    for E := Low(TExp) to High(TExp) do DoRun(Runs[i], Tr, E);
  end;
  if only = '' then Summary.SaveToFile(OutDir + '/pulsus.csv')
  else Summary.SaveToFile(Format('%s/pulsus_%s.csv', [OutDir, only]));
  Summary.Free; Tr.Free;
end.
