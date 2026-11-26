unit uTubeLaw;

{ An airway's tube law: lumen area against transmural pressure, as a
  table (from uAirwayRing's finite-element wall, or a formula sampled for
  the checks), with the liquid lining on top of it.
  Units: mm, kPa (so areas are mm2 and surface tension is kPa mm = N/m).

  TABLE   monotone cubic interpolation (Fritsch & Carlson's slopes), so
  dA/dP is continuous: the flow model's wave speed needs it. Below the
  table the area decays exponentially at the first point's slope, above
  it rises linearly at the last point's.

  LINING   a liquid layer of cross-section ALiq on the wall, surface
  tension Gamma. The air-liquid interface is a cylinder of radius a, so
  the liquid, and through it the wall, is at a pressure Gamma/a below the
  gas (Laplace):
     AWall = Law(Ptm - Gamma/a),   pi a^2 = AWall - ALiq .
  The open state is the largest root a. It is lost in two ways, and both
  count as closed: no root (the wall's narrowing raises Gamma/a faster
  than the wall resists: the compliant collapse of Kamm & Schroter 1989
  and Halpern & Grotberg 1992), or a film thicker than FilmCrit of the
  wall's radius, which is unstable to a liquid bridge whatever the wall
  does (Gauglitz & Radke 1988: 0.12). Reopening is not modelled here. }

{$mode delphi}{$H+}

interface

uses
  SysUtils, Math;

type
  TTubeLaw = class
  private
    FP, FA, FM: array of Double;
  public
    Monotone: Boolean;   { False if SetTable had to drop points to make it so }
    A0: Double;          { area at Ptm = 0 }
    { Points in any order; sorted by pressure. Points whose area does not
      rise with pressure are dropped. }
    procedure SetTable(const P, A: array of Double);
    function Count: Integer;
    function TableP(i: Integer): Double;
    function TableA(i: Integer): Double;
    function Area(Ptm: Double): Double;
    function Slope(Ptm: Double): Double;  { dA/dPtm }
  end;

  TLining = record
    ALiq: Double;      { liquid cross-section, mm2 }
    Gamma: Double;     { surface tension, kPa mm (0.025 = 25 mN/m) }
    FilmCrit: Double;  { film thickness over wall radius at which a bridge forms }
  end;

function NoLining: TLining;
{ Gas area of a lined airway at gas-to-outside pressure Ptm; AWall is
  the wall's lumen area. Closed: no open state. }
function GasArea(Law: TTubeLaw; const Lin: TLining; Ptm: Double;
  out AWall: Double; out Closed: Boolean): Double;

implementation

procedure TTubeLaw.SetTable(const P, A: array of Double);
var
  n, i, j, k: Integer;
  tp, ta, h, d: array of Double;
  t, w1, w2: Double;
begin
  n := Length(P);
  SetLength(tp, n); SetLength(ta, n);
  for i := 0 to n - 1 do begin tp[i] := P[i]; ta[i] := A[i]; end;
  for i := 1 to n - 1 do
  begin
    j := i;
    while (j > 0) and (tp[j - 1] > tp[j]) do
    begin
      t := tp[j]; tp[j] := tp[j - 1]; tp[j - 1] := t;
      t := ta[j]; ta[j] := ta[j - 1]; ta[j - 1] := t;
      Dec(j);
    end;
  end;
  Monotone := True;
  SetLength(FP, n); SetLength(FA, n);
  k := 0;
  for i := 0 to n - 1 do
    if (k = 0) or ((tp[i] > FP[k - 1]) and (ta[i] > FA[k - 1])) then
    begin
      FP[k] := tp[i]; FA[k] := ta[i]; Inc(k);
    end
    else
      Monotone := False;
  n := k;
  if n < 2 then raise Exception.Create('TTubeLaw.SetTable : fewer than two usable points');
  SetLength(FP, n); SetLength(FA, n); SetLength(FM, n);
  SetLength(h, n); SetLength(d, n);
  for i := 0 to n - 2 do
  begin
    h[i] := FP[i + 1] - FP[i];
    d[i] := (FA[i + 1] - FA[i]) / h[i];
  end;
  FM[0] := d[0]; FM[n - 1] := d[n - 2];
  for i := 1 to n - 2 do
  begin
    { weighted harmonic mean: monotone, and every d is positive here }
    w1 := 2 * h[i] + h[i - 1];
    w2 := h[i] + 2 * h[i - 1];
    FM[i] := (w1 + w2) / (w1 / d[i - 1] + w2 / d[i]);
  end;
  A0 := Area(0);
end;

function TTubeLaw.Count: Integer;
begin
  Result := Length(FP);
end;

function TTubeLaw.TableP(i: Integer): Double;
begin
  Result := FP[i];
end;

function TTubeLaw.TableA(i: Integer): Double;
begin
  Result := FA[i];
end;

function TTubeLaw.Area(Ptm: Double): Double;
var
  lo, hi, mid, n: Integer;
  h, t, t2, t3: Double;
begin
  n := Length(FP);
  if Ptm <= FP[0] then
    Exit(FA[0] * Exp(FM[0] * (Ptm - FP[0]) / FA[0]));
  if Ptm >= FP[n - 1] then
    Exit(FA[n - 1] + FM[n - 1] * (Ptm - FP[n - 1]));
  lo := 0; hi := n - 1;
  while hi - lo > 1 do
  begin
    mid := (lo + hi) div 2;
    if FP[mid] <= Ptm then lo := mid else hi := mid;
  end;
  h := FP[hi] - FP[lo];
  t := (Ptm - FP[lo]) / h; t2 := t * t; t3 := t2 * t;
  Result := (2 * t3 - 3 * t2 + 1) * FA[lo] + (t3 - 2 * t2 + t) * h * FM[lo]
    + (-2 * t3 + 3 * t2) * FA[hi] + (t3 - t2) * h * FM[hi];
end;

function TTubeLaw.Slope(Ptm: Double): Double;
var
  lo, hi, mid, n: Integer;
  h, t, t2: Double;
begin
  n := Length(FP);
  if Ptm <= FP[0] then
    Exit(FM[0] * Exp(FM[0] * (Ptm - FP[0]) / FA[0]));
  if Ptm >= FP[n - 1] then
    Exit(FM[n - 1]);
  lo := 0; hi := n - 1;
  while hi - lo > 1 do
  begin
    mid := (lo + hi) div 2;
    if FP[mid] <= Ptm then lo := mid else hi := mid;
  end;
  h := FP[hi] - FP[lo];
  t := (Ptm - FP[lo]) / h; t2 := t * t;
  Result := (6 * t2 - 6 * t) * (FA[lo] - FA[hi]) / h + (3 * t2 - 4 * t + 1) * FM[lo]
    + (3 * t2 - 2 * t) * FM[hi];
end;

function NoLining: TLining;
begin
  Result.ALiq := 0; Result.Gamma := 0; Result.FilmCrit := 0.12;
end;

function GasArea(Law: TTubeLaw; const Lin: TLining; Ptm: Double;
  out AWall: Double; out Closed: Boolean): Double;
var
  aHi, aLo, am, gHi, gLo, gm, aw: Double;
  k, it: Integer;

  function G(a: Double): Double;
  begin
    Result := Law.Area(Ptm - Lin.Gamma / a) - Lin.ALiq - Pi * a * a;
  end;

begin
  Closed := False;
  AWall := Law.Area(Ptm);
  if (Lin.ALiq <= 0) and (Lin.Gamma <= 0) then Exit(AWall);
  if AWall <= Lin.ALiq then begin Closed := True; Exit(0); end;
  aHi := Sqrt((AWall - Lin.ALiq) / Pi);
  if Lin.Gamma > 0 then
  begin
    { G(aHi) <= 0; walk down to the first a with G >= 0 }
    gHi := G(aHi);
    aLo := aHi; gLo := gHi;
    k := 0;
    while (gLo < 0) and (k < 150) do
    begin
      aHi := aLo; gHi := gLo;
      aLo := aLo * 0.97; gLo := G(aLo);
      Inc(k);
    end;
    if gLo < 0 then begin Closed := True; Exit(0); end;
    if gHi < 0 then
      for it := 1 to 60 do
      begin
        am := 0.5 * (aLo + aHi); gm := G(am);
        if gm >= 0 then aLo := am else aHi := am;
      end;
    aHi := aLo;
    AWall := Law.Area(Ptm - Lin.Gamma / aHi);
  end;
  aw := Sqrt(AWall / Pi);
  if 1 - aHi / aw > Lin.FilmCrit then begin Closed := True; Exit(0); end;
  Result := Pi * aHi * aHi;
end;

end.
