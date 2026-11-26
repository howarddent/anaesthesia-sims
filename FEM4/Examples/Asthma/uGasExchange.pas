unit uGasExchange;

{ Stage 7: steady-state gas exchange over many lung units (the West
  compartment model). Pressures mmHg, contents mL/dL blood, ventilation
  and perfusion L/min, uptake mL/min STPD.

  Each unit u, alveolar ventilation VA_u (BTPS) and perfusion Q_u, is in
  steady state with end-capillary blood equal to alveolar gas:
    O2:   K VA (PIO2 - PAO2) = 10 Q (Cc(PAO2) - CvO2)
    CO2:  K VA  PACO2        = 10 Q (CvCO2 - Cc(PACO2))
  K = 0.826 / 713 converts a BTPS volume times a dry partial pressure to
  mL STPD (sea level, 37 C): inspired and expired volumes are taken as
  equal (no nitrogen correction), so an ideal lung obeys the alveolar gas
  equation in its simple form PAO2 = PIO2 - PACO2 VO2 / VCO2. A unit
  with no ventilation is a shunt: its blood leaves as mixed venous.
  The two equations are independent (no Bohr or Haldane effect); each
  left side minus right side falls with the pressure, so each is solved
  by bisection.

  O2 content  1.34 Hb S + 0.003 P, S from Severinghaus (1979):
              S = 1 / (23400 / (P^3 + 150 P) + 1)  (pH 7.4, 37 C).
  CO2 content 11.2 P^0.4 (49 mL/dL at 40 mmHg, about the arterial
              value; slope 0.49 mL/dL/mmHg there). Assumed.

  Mixed venous blood follows from Fick: CvO2 = CaO2 - VO2 / (10 Qt),
  CvCO2 = CaCO2 + VCO2 / (10 Qt), arterial blood being the
  perfusion-weighted mean of the units' end-capillary blood; iterated
  with damping to a fixed point. }

{$mode delphi}{$H+}

interface

uses
  SysUtils, Math;

type
  TGasParams = record
    PB: Double;       { mmHg }
    FiO2: Double;
    Hb: Double;       { g/dL }
    VO2, VCO2: Double;  { mL/min STPD }
    Qt: Double;       { L/min }
  end;

  TBloodGases = record
    PaO2, PaCO2, PvO2, PvCO2: Double;  { mmHg }
    SaO2, SvO2: Double;
    CaO2, CvO2: Double;                { mL/dL }
    Shunt: Double;                     { perfusion share with no ventilation }
    Converged: Boolean;
  end;

function DefaultGasParams: TGasParams;
function O2Sat(P: Double): Double;
function O2Content(P, Hb: Double): Double;
function CO2Content(P: Double): Double;
function O2Pressure(C, Hb: Double): Double;   { inverse of O2Content }
function CO2Pressure(C: Double): Double;
{ VA, Q in L/min, one entry per unit; Q is scaled to G.Qt. PAO2/PACO2
  receive each unit's alveolar pressures (shunt units: mixed venous). }
function BloodGases(const VA, Q: array of Double; const G: TGasParams;
  var PAO2, PACO2: array of Double): TBloodGases;

implementation

const
  KGas = 0.826 / 713;

function DefaultGasParams: TGasParams;
begin
  Result.PB := 760; Result.FiO2 := 0.21; Result.Hb := 15;
  Result.VO2 := 250; Result.VCO2 := 200; Result.Qt := 5;
end;

function O2Sat(P: Double): Double;
begin
  if P <= 0 then Exit(0);
  Result := 1 / (23400 / (P * P * P + 150 * P) + 1);
end;

function O2Content(P, Hb: Double): Double;
begin
  Result := 1.34 * Hb * O2Sat(P) + 0.003 * Max(0, P);
end;

function CO2Content(P: Double): Double;
begin
  if P <= 0 then Exit(0);
  Result := 11.2 * Power(P, 0.4);
end;

function O2Pressure(C, Hb: Double): Double;
var
  lo, hi, mid: Double;
  i: Integer;
begin
  lo := 0; hi := 2000;
  for i := 1 to 80 do
  begin
    mid := 0.5 * (lo + hi);
    if O2Content(mid, Hb) < C then lo := mid else hi := mid;
  end;
  Result := 0.5 * (lo + hi);
end;

function CO2Pressure(C: Double): Double;
begin
  if C <= 0 then Exit(0);
  Result := Power(C / 11.2, 1 / 0.4);
end;

function BloodGases(const VA, Q: array of Double; const G: TGasParams;
  var PAO2, PACO2: array of Double): TBloodGases;
var
  n, u, it, k: Integer;
  PIO2, qs, cvo2, cvco2, cao2, caco2, lo, hi, mid, f, nv, nc, Qu, shunt: Double;
begin
  n := Length(VA);
  PIO2 := G.FiO2 * (G.PB - 47);
  qs := 0;
  for u := 0 to n - 1 do qs := qs + Q[u];
  { start from a typical mixed venous }
  cvo2 := O2Content(40, G.Hb); cvco2 := CO2Content(46);
  Result.Converged := False;
  for it := 1 to 400 do
  begin
    cao2 := 0; caco2 := 0; shunt := 0;
    for u := 0 to n - 1 do
    begin
      Qu := G.Qt * Q[u] / qs;
      if Qu <= 0 then Continue;
      if VA[u] <= 0 then
      begin
        cao2 := cao2 + Qu * cvo2; caco2 := caco2 + Qu * cvco2; shunt := shunt + Qu;
        PAO2[u] := O2Pressure(cvo2, G.Hb); PACO2[u] := CO2Pressure(cvco2);
        Continue;
      end;
      { O2: f(P) = K VA (PIO2 - P) - 10 Q (Cc(P) - Cv) falls with P }
      lo := 0; hi := PIO2;
      for k := 1 to 60 do
      begin
        mid := 0.5 * (lo + hi);
        f := KGas * VA[u] * 1000 * (PIO2 - mid) - 10 * Qu * (O2Content(mid, G.Hb) - cvo2);
        if f > 0 then lo := mid else hi := mid;
      end;
      PAO2[u] := 0.5 * (lo + hi);
      { CO2: g(P) = 10 Q (Cv - Cc(P)) - K VA P falls with P }
      lo := 0; hi := Max(CO2Pressure(cvco2), 1);
      for k := 1 to 60 do
      begin
        mid := 0.5 * (lo + hi);
        f := 10 * Qu * (cvco2 - CO2Content(mid)) - KGas * VA[u] * 1000 * mid;
        if f > 0 then lo := mid else hi := mid;
      end;
      PACO2[u] := 0.5 * (lo + hi);
      cao2 := cao2 + Qu * O2Content(PAO2[u], G.Hb);
      caco2 := caco2 + Qu * CO2Content(PACO2[u]);
    end;
    cao2 := cao2 / G.Qt; caco2 := caco2 / G.Qt;
    nv := cao2 - G.VO2 / (10 * G.Qt);
    nc := caco2 + G.VCO2 / (10 * G.Qt);
    if (Abs(nv - cvo2) < 1e-9) and (Abs(nc - cvco2) < 1e-9) then
    begin
      Result.Converged := True;
      cvo2 := nv; cvco2 := nc;
      Break;
    end;
    { damped: a large shunt makes the plain iteration oscillate }
    cvo2 := cvo2 + 0.5 * (nv - cvo2);
    cvco2 := cvco2 + 0.5 * (nc - cvco2);
    if cvo2 < 0.01 then cvo2 := 0.01;
  end;
  Result.CaO2 := cao2; Result.CvO2 := cvo2;
  Result.PaO2 := O2Pressure(cao2, G.Hb);
  Result.PaCO2 := CO2Pressure(caco2);
  Result.PvO2 := O2Pressure(cvo2, G.Hb);
  Result.PvCO2 := CO2Pressure(cvco2);
  Result.SaO2 := O2Sat(Result.PaO2);
  Result.SvO2 := O2Sat(Result.PvO2);
  Result.Shunt := shunt / G.Qt;
end;

end.
