unit uBronchiole;

{ Steady flow of gas along one collapsible airway whose area follows a
  tube law: its resistance, and the Starling-resistor limit on its flow.
  Units: mm, kPa, s (so flow is mm3/s, density kg/mm3, viscosity kPa s).

  EQUATION   for the lateral pressure P(x), x from the upstream end,
     dP/dx = -f / (1 - S^2)
     f   = 8 pi Visc Q / A^2 (Ka + Kb Re)        viscous loss per length
     S^2 = Rho Q^2 (dA/dPtm) / A^3               speed over wave speed, squared
  with A = A(P - PExt) the gas area (uTubeLaw, lining included) and
  Re = Rho Q D / (Visc A), D = 2 sqrt(A/pi). This is the equation of
  Lambert, Wilson, Hyatt & Rodarte (1982) for one airway. Ka = 1, Kb = 0
  is Poiseuille flow; Reynolds (1982) fitted 1.5 and 0.0035 to casts of
  the bronchial tree on expiration. A collapsed, folded lumen loses more
  than a round one of its area: not included.

  FLOW LIMITATION   as P falls along the airway the wall narrows, the
  loss rises, and P falls faster. For each upstream and outside pressure
  there is a largest flow for which the airway's end is reached at all
  (the area collapsing, or S reaching 1, before it): lowering the
  downstream pressure further gains nothing. Flow finds the flow for a
  given downstream pressure, or that largest flow if the downstream
  pressure is below what it can deliver. RK4 in x. }

{$mode delphi}{$H+}

interface

uses
  SysUtils, Math, uTubeLaw;

type
  TBronchiole = class
  public
    Law: TTubeLaw;      { not owned }
    Lining: TLining;
    Len: Double;        { mm }
    Rho, Visc: Double;
    Ka, Kb: Double;
    Steps: Integer;
    constructor Create(ALaw: TTubeLaw; ALength: Double);
    { Pressure at the downstream end for flow Q (mm3/s); Choked if the
      end is not reached. }
    function OutletPressure(Q, PUp, PExt: Double; out Choked: Boolean): Double;
    { Flow from PUp to PDown (PUp >= PDown) with PExt outside. Limited:
      the downstream pressure is below what the largest flow leaves. }
    function Flow(PUp, PDown, PExt: Double; out Limited: Boolean): Double;
    function MaxFlow(PUp, PExt: Double): Double;
    function Area(P, PExt: Double; out Closed: Boolean): Double;
  end;

const
  AirRho = 1.14e-9;    { kg/mm3: saturated air at 37 C }
  AirVisc = 1.85e-8;   { kPa s }

implementation

constructor TBronchiole.Create(ALaw: TTubeLaw; ALength: Double);
begin
  inherited Create;
  Law := ALaw; Len := ALength;
  Lining := NoLining;
  Rho := AirRho; Visc := AirVisc;
  Ka := 1.5; Kb := 0.0035;
  Steps := 200;
end;

function TBronchiole.Area(P, PExt: Double; out Closed: Boolean): Double;
var
  aw: Double;
begin
  Result := GasArea(Law, Lining, P - PExt, aw, Closed);
end;

function TBronchiole.OutletPressure(Q, PUp, PExt: Double; out Choked: Boolean): Double;
var
  i: Integer;
  h, P, k1, k2, k3, k4, AMin: Double;

  function Grad(Pl: Double): Double;
  var
    A, dA, Re, S2, aw, dp: Double;
    cl, cl2: Boolean;
  begin
    A := GasArea(Law, Lining, Pl - PExt, aw, cl);
    if cl or (A < AMin) then begin Choked := True; Exit(0); end;
    if (Lining.ALiq > 0) or (Lining.Gamma > 0) then
    begin
      dp := 1e-4;
      dA := (GasArea(Law, Lining, Pl - PExt + dp, aw, cl2) - A) / dp;
    end
    else
      dA := Law.Slope(Pl - PExt);
    Re := Rho * Q * 2 * Sqrt(A / Pi) / (Visc * A);
    S2 := Rho * Q * Q * dA / (A * A * A);
    if S2 >= 0.98 then begin Choked := True; Exit(0); end;
    Result := -8 * Pi * Visc * Q / (A * A) * (Ka + Kb * Re) / (1 - S2);
  end;

begin
  Choked := False;
  AMin := 1e-3 * Law.A0;
  P := PUp;
  h := Len / Steps;
  for i := 1 to Steps do
  begin
    k1 := Grad(P); if Choked then Exit(P);
    k2 := Grad(P + 0.5 * h * k1); if Choked then Exit(P);
    k3 := Grad(P + 0.5 * h * k2); if Choked then Exit(P);
    k4 := Grad(P + h * k3); if Choked then Exit(P);
    P := P + h / 6 * (k1 + 2 * k2 + 2 * k3 + k4);
  end;
  Grad(P);
  Result := P;
end;

function TBronchiole.Flow(PUp, PDown, PExt: Double; out Limited: Boolean): Double;
var
  lo, hi, mid, pl, A: Double;
  ch, cl: Boolean;
  it: Integer;
begin
  Limited := False;
  if PUp <= PDown then Exit(0);
  A := Area(PUp, PExt, cl);
  if cl then Exit(0);
  { an upper bound: Poiseuille flow through the upstream area, doubled
    until it is too much }
  hi := A * A * (PUp - PDown) / (8 * Pi * Visc * Len * Ka);
  lo := 0;
  for it := 1 to 60 do
  begin
    pl := OutletPressure(hi, PUp, PExt, ch);
    if ch or (pl < PDown) then Break;
    lo := hi; hi := 2 * hi;
  end;
  Limited := True;
  for it := 1 to 60 do
  begin
    mid := 0.5 * (lo + hi);
    pl := OutletPressure(mid, PUp, PExt, ch);
    if ch then
      hi := mid
    else if pl < PDown then
    begin
      hi := mid; Limited := False;
    end
    else
      lo := mid;
    if hi - lo <= 1e-10 * hi then Break;
  end;
  Result := lo;
end;

function TBronchiole.MaxFlow(PUp, PExt: Double): Double;
var
  lim: Boolean;
begin
  Result := Flow(PUp, -1e6, PExt, lim);
end;

end.
