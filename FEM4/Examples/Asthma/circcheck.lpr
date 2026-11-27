program circcheck;

{ Stage 10 checks of uCirculation:
    1 resting haemodynamics at 75 /min, Ppl -4 mmHg, within normal
      adult ranges;
    2 blood volume conserved while the pleural pressure swings;
    3 the septum solve: its residual, and interdependence - at a fixed
      left ventricular volume in diastole, a fuller right ventricle
      pushes the septum left and raises the left ventricular pressure,
      and does not with a rigid septum and no pericardium;
    4 Frank-Starling: more stressed volume, more stroke volume;
    5 West's zones: with the alveoli at atmospheric pressure every band
      is zone 3 and the flow equals the plain resistance's; raised above
      the arterial pressure, a band carries nothing;
    6 a sinusoidal pleural swing of 15 mmHg: the systolic pressure's
      range changes by less than 0.05 mmHg when the step is halved.

  Build:  fpc -O3 -FUlib -Fu../../../newVM -Fi../../../newVM circcheck.lpr }

{$mode delphi}{$H+}

uses
  SysUtils, Math, uCirculation;

type
  TSine = class
    Amp, Mean, TB: Double;
    procedure At(t: Double; var P: Double; var Pa: array of Double);
  end;

procedure TSine.At(t: Double; var P: Double; var Pa: array of Double);
var
  k: Integer;
begin
  P := Mean - Amp * 0.5 * (1 - Cos(2 * Pi * t / TB));
  for k := 0 to High(Pa) do Pa[k] := 0;
end;

var
  NFail: Integer = 0;

procedure Check(const What: string; OK: Boolean; const Detail: string);
begin
  if OK then Writeln('  ok    ', What, '  ', Detail)
  else
  begin
    Writeln('  FAIL  ', What, '  ', Detail);
    Inc(NFail);
  end;
end;

type
  TBeat = record
    SBP, DBP, MAP, SV, EDV, ESV, CVP, LAP, PAs, PAd, PAm, CO, LVEDP: Double;
  end;

function OneBeat(C: TCirculation; Dt: Double): TBeat;
var
  n, i: Integer;
begin
  n := Round(C.Period / Dt);
  with Result do
  begin
    SBP := -1e9; DBP := 1e9; MAP := 0; SV := 0; EDV := 0; ESV := 1e9; CVP := 0; LAP := 0;
    PAs := -1e9; PAd := 1e9; PAm := 0; LVEDP := 0;
  end;
  for i := 1 to n do
  begin
    C.Step(Dt);
    with Result do
    begin
      SBP := Max(SBP, C.P[cSA]); DBP := Min(DBP, C.P[cSA]); MAP := MAP + C.P[cSA] / n;
      SV := SV + C.Qav * Dt;
      if C.V[cLV] > EDV then begin EDV := C.V[cLV]; LVEDP := C.P[cLV]; end;
      ESV := Min(ESV, C.V[cLV]);
      CVP := CVP + C.P[cVC] / n; LAP := LAP + C.P[cPU] / n;
      PAs := Max(PAs, C.P[cPA]); PAd := Min(PAd, C.P[cPA]); PAm := PAm + C.P[cPA] / n;
    end;
  end;
  Result.CO := Result.SV * C.Prm.HR / 1000;
end;

function Settle(const Prm: TCircParams; Seconds: Double): TBeat;
var
  C: TCirculation;
  i: Integer;
begin
  C := TCirculation.Create(Prm);
  C.PplConst := -4;
  for i := 1 to Round(Seconds / 0.0005) do C.Step(0.0005);
  Result := OneBeat(C, 0.0005);
  C.Free;
end;

function SineRange(Dt: Double): Double;
var
  C: TCirculation;
  S: TSine;
  i, n: Integer;
  lo, hi, sbp: Double;
  beat, last: Integer;
begin
  S := TSine.Create; S.Amp := 15; S.Mean := -3; S.TB := 2.4;
  C := TCirculation.Create(DefaultCircParams);
  C.Prm.HR := 110;
  C.Thorax := S.At; C.NBands := 0;
  n := Round(48 / Dt);
  lo := 1e9; hi := -1e9; sbp := -1e9; last := -1;
  for i := 1 to n do
  begin
    C.Step(Dt);
    beat := Floor(C.T / C.Period);
    if beat <> last then
    begin
      if (last >= 0) and (C.T > 24) then begin lo := Min(lo, sbp); hi := Max(hi, sbp); end;
      sbp := -1e9; last := beat;
    end;
    sbp := Max(sbp, C.P[cSA]);
  end;
  Result := hi - lo;
  C.Free; S.Free;
end;

var
  Prm: TCircParams;
  B, B2: TBeat;
  C: TCirculation;
  S: TSine;
  i, k: Integer;
  v0, drift, x, r, p1, p2, q0, q1: Double;
  dV: array[0..NComp - 1] of Double;
begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  DefaultFormatSettings.DecimalSeparator := '.';
  Writeln('circcheck: uCirculation');

  { 1 rest }
  Prm := DefaultCircParams; Prm.HR := 75;
  B := Settle(Prm, 30);
  Writeln(Format('  rest: %.0f/%.0f (MAP %.0f) mmHg, PA %.0f/%.0f (%.0f), CVP %.1f, LAP %.1f, LVEDV %.0f, ESV %.0f, SV %.0f mL, EF %.2f, CO %.2f L/min, LVEDP %.1f',
    [B.SBP, B.DBP, B.MAP, B.PAs, B.PAd, B.PAm, B.CVP, B.LAP, B.EDV, B.ESV, B.SV, B.SV / B.EDV, B.CO, B.LVEDP]));
  Check('systolic 100-140, diastolic 60-90', InRange(B.SBP, 100, 140) and InRange(B.DBP, 60, 90), '');
  Check('cardiac output 4.5-6.5 L/min', InRange(B.CO, 4.5, 6.5), Format('%.2f', [B.CO]));
  Check('ejection fraction 0.5-0.7', InRange(B.SV / B.EDV, 0.5, 0.7), Format('%.2f', [B.SV / B.EDV]));
  Check('mean PA 10-20, CVP 0-8 mmHg', InRange(B.PAm, 10, 20) and InRange(B.CVP, 0, 8), '');

  { 2 conservation }
  S := TSine.Create; S.Amp := 20; S.Mean := -3; S.TB := 2.4;
  C := TCirculation.Create(DefaultCircParams);
  C.Thorax := S.At; C.NBands := 4;
  v0 := C.TotalVolume; drift := 0;
  for i := 1 to Round(30 / 0.0005) do
  begin
    C.Step(0.0005);
    drift := Max(drift, Abs(C.TotalVolume - v0));
  end;
  Check('volume conserved over 30 s of 20 mmHg swings', drift < 1e-8, Format('max drift %.2e mL', [drift]));

  { 3 septum }
  r := 0;
  for i := 0 to 20 do
    for k := 0 to 4 do
    begin
      x := C.SeptumVolume(60 + 5 * i, 40 + 20 * k, k / 4, 0);
      r := Max(r, Abs(C.ChamberP(C.Prm.SPT, x, k / 4) - C.ChamberP(C.Prm.LVF, 60 + 5 * i - x, k / 4)
        + C.ChamberP(C.Prm.RVF, 40 + 20 * k + x, k / 4)));
    end;
  Check('septum residual over a grid of volumes and activations', r < 1e-8, Format('%.1e mmHg', [r]));
  q0 := C.SeptumVolume(110, 80, 0, 0); q1 := C.SeptumVolume(110, 160, 0, 0);
  p1 := C.ChamberP(C.Prm.LVF, 110 - q0, 0) + C.Prm.PcdP0 * (Exp(C.Prm.PcdLam * (190 - C.Prm.PcdV0)) - 1);
  p2 := C.ChamberP(C.Prm.LVF, 110 - q1, 0) + C.Prm.PcdP0 * (Exp(C.Prm.PcdLam * (270 - C.Prm.PcdV0)) - 1);
  Check('RV 80 -> 160 mL moves the septum left and raises diastolic LV pressure at LV 110 mL',
    (q1 < q0) and (p2 > p1 + 1), Format('Vspt %.2f -> %.2f mL, Plv %.2f -> %.2f mmHg', [q0, q1, p1, p2]));
  C.Prm.Septum := False; C.Prm.Pericardium := False;
  C.PplConst := 0; C.Thorax := nil;
  C.V[cLV] := 110; C.V[cRV] := 80; C.T := 0; C.Evaluate(0, C.V, dV); p1 := C.P[cLV];
  C.V[cRV] := 160; C.Evaluate(0, C.V, dV); p2 := C.P[cLV];
  Check('with a rigid septum and no pericardium it does not', Abs(p2 - p1) < 1e-12, Format('%.4f -> %.4f', [p1, p2]));
  C.Free;

  { 4 Starling }
  Prm := DefaultCircParams; Prm.HR := 75; Prm.VStressed := 1500;
  B := Settle(Prm, 30);
  Prm.VStressed := 2100;
  B2 := Settle(Prm, 30);
  Check('stressed volume 1500 -> 2100 mL raises stroke volume and LVEDP', (B2.SV > B.SV + 2) and (B2.LVEDP > B.LVEDP),
    Format('SV %.1f -> %.1f mL, LVEDP %.1f -> %.1f mmHg', [B.SV, B2.SV, B.LVEDP, B2.LVEDP]));

  { 5 zones }
  C := TCirculation.Create(DefaultCircParams);
  C.NBands := 4;
  for k := 0 to 3 do C.Palv[k] := 0;
  p1 := C.PulmonaryFlow(15, 8);
  Check('alveoli at 0: all zone 3, flow = plain resistance', Abs(p1 - 7 / C.Prm.Rpul) < 1e-9,
    Format('%.4f against %.4f mL/s', [p1, 7 / C.Prm.Rpul]));
  C.Palv[0] := 30;
  p2 := C.PulmonaryFlow(15, 8);
  Check('top band alveoli at 30 mmHg: that band carries nothing (zone 1)', (C.BandQ[0] = 0) and (p2 < p1),
    Format('band flows %.1f %.1f %.1f %.1f', [C.BandQ[0], C.BandQ[1], C.BandQ[2], C.BandQ[3]]));
  C.Palv[0] := 0; C.Palv[1] := 10;
  p2 := C.PulmonaryFlow(15, 8);
  x := 1 / (4 * C.Prm.Rpul) * (15 + C.Prm.RhoG * (-0.125) * C.Prm.Height - 10);
  Check('band 1 alveoli at 10 mmHg: zone 2, driven by Ppa + h - Palv', Abs(C.BandQ[1] - x) < 1e-9,
    Format('%.3f against %.3f mL/s', [C.BandQ[1], x]));
  C.Free;

  { 6 time step }
  p1 := SineRange(0.0005); p2 := SineRange(0.00025);
  Check('15 mmHg sinusoidal swing: SBP range independent of the step', Abs(p1 - p2) < 0.05,
    Format('%.3f (0.5 ms), %.3f (0.25 ms) mmHg', [p1, p2]));

  S.Free;
  if NFail = 0 then Writeln('all passed') else Writeln(NFail, ' FAILED');
  if NFail > 0 then Halt(1);
end.
