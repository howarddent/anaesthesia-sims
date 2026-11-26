program asthmacheck;

{ Console checks of the asthma model's single-unit parts.

  Airway wall (uAirwayRing)
   1. Residual against energy: layered ring with active muscle,
      tethering and lumen pressure, random displacement; nodal forces
      against central differences of the energy.
   2. Tangent against central differences of the residual, same state.
   3. Lumen area of the mesh against pi Ri^2.
   4. Inflation of a thick, stiffening, tethered tube: pressure for a
      given lumen area against the exact radial integral.
   5. Isometric muscle: the pressure a ring of active muscle holds at
      its unloaded area, against m Act T0 ln(Ro/Ri).
   6. Buckling of a thin ring under suction into 2 and 3 folds: the
      critical pressure, from the growth of the imperfection at two
      pressures (Southwell), against (n^2 - 1) E' I / Rm^3, Rm the mean
      radius. (Suction inside and pressure outside differ by a
      hydrostatic stress, which does nothing to an incompressible wall,
      so the first correction in thickness/radius must vanish.)
   7. The collapsed ring: pressure and area when opposite walls first
      touch, against the elastica (Flaherty, Keller & Rubinow 1972:
      5.247 E'I/R^3, area 0.27 of the circle's). The elastica is a
      line; here the inner surfaces meet, a little sooner.

  Alveolus (uAlveolus)
   8. Residual against energy (tissue, constant film tension, mouth ring).
   9. Tangent against residual, with the area-dependent film.
  10. Volume of the unstressed mesh against the spherical cap's.
  11. A closed sphere with a constant film: pressure at twice the
      unstressed volume against 2 (T + gamma) / r.

  Tube law and flow (uTubeLaw, uBronchiole)
  12. The table's interpolation against the function it samples.
  13. Rigid tube: Poiseuille flow.
  14. Compliant tube, area linear in pressure, no inertia: the closed
      form (Aup^3 - Adown^3) / (24 pi Visc L k).
  15. Wave-speed limit: the largest flow of a short, nearly frictionless
      tube against A c at its entrance.
  16. Flow limitation: flow unchanged when the downstream pressure is
      lowered further.
  17. Lining: gas area in a rigid tube, and closure by a thick film.

  Build:  fpc -O3 -FUlib -Fu../../../newVM -Fi../../../newVM asthmacheck.lpr }

{$mode delphi}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Math, cblas, newVM, uTubeLaw, uAirwayRing, uAlveolus, uBronchiole;

var
  Fails: Integer = 0;

procedure Report(const Name: string; Got, Want, Tol: Double);
var
  err: Double;
begin
  if Want <> 0 then err := Abs(Got / Want - 1) else err := Abs(Got);
  Write(Format('  %-50s %12.6g  want %12.6g  err %8.2e', [Name, Got, Want, err]));
  if err <= Tol then Writeln('  ok') else begin Writeln('  FAIL'); Inc(Fails); end;
end;

procedure Fail(const Msg: string);
begin
  Writeln('  ', Msg, '  FAIL'); Inc(Fails);
end;

function CheckRingParams: TRingParams;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Ri := 1;
  Result.NLayers := 2;
  Result.Layers[0].Thick := 0.1; Result.Layers[0].Mu := 20; Result.Layers[0].Stiffen := 2;
  Result.Layers[0].NR := 1;
  Result.Layers[1].Thick := 0.3; Result.Layers[1].Mu := 2; Result.Layers[1].Stiffen := 1;
  Result.Layers[1].Muscle := 0.7; Result.Layers[1].NR := 1;
  Result.Lobes := 3; Result.NT := 3;
  Result.KappaRatio := 50;
  Result.T0 := 50; Result.LMin := 0.25; Result.Act := 0.6;
  Result.TetherK := 3; Result.TetherR := 1.6;
  Result.Imperfection := 0.01;
  Result.ContactK := 0;
end;

procedure RingDerivatives;
var
  R: TAirwayRing;
  Uv: array of Double;
  i, n: Integer;
  wp, wm, fd, worst, big, err: Double;
const
  h = 1e-6;
  Pt = 0.8;
begin
  Writeln('1-2. Airway wall: residual against energy, tangent against residual');
  R := TAirwayRing.Create(CheckRingParams);
  SetLength(Uv, R.NDof);
  RandSeed := 2468;
  for i := 0 to High(Uv) do Uv[i] := 0.03 * (Random - 0.5);
  R.SetTrial(Uv, Pt);
  worst := 0; big := 0;
  for n := 0 to R.NDof - 1 do
  begin
    if R.IsFixed(n) then Continue;
    Uv[n] := Uv[n] + h; R.SetTrial(Uv, Pt); wp := R.TrialEnergy;
    Uv[n] := Uv[n] - 2 * h; R.SetTrial(Uv, Pt); wm := R.TrialEnergy;
    Uv[n] := Uv[n] + h; R.SetTrial(Uv, Pt);
    fd := (wp - wm) / (2 * h);
    worst := Max(worst, Abs(fd - R.TrialResidual(n)));
    big := Max(big, Abs(fd));
  end;
  Report('largest force difference / largest force', worst / big, 0, 1e-6);
  R.CheckTangent(err, big);
  Report('largest K error / largest K', err / big, 0, 1e-6);
  R.Free;
end;

procedure RingArea;
var
  R: TAirwayRing;
  P: TRingParams;
begin
  Writeln('3. Lumen area of the mesh');
  P := NormalBronchiole(0.3);
  P.Imperfection := 0;
  R := TAirwayRing.Create(P);
  Report(Format('area, %d elements round half a fold', [R.Prm.NT]), R.LumenArea, Pi * 0.09, 1e-6);
  R.Free;
end;

{ exact pressure difference across an incompressible tube whose lumen
  area has grown by pi c }
function TubeIntegral(A, B, Mu, bs, c: Double): Double;
var
  i: Integer;
  Rr, r2, lt2, lr2, f: Double;
const
  n = 4000;
begin
  Result := 0;
  for i := 0 to n do
  begin
    Rr := A + (B - A) * i / n;
    r2 := Rr * Rr + c;
    lt2 := r2 / (Rr * Rr); lr2 := 1 / lt2;
    f := Mu * Exp(bs * (lt2 + lr2 - 2)) * (lt2 - lr2) * Rr / r2;
    if (i = 0) or (i = n) then Result := Result + f
    else if Odd(i) then Result := Result + 4 * f
    else Result := Result + 2 * f;
  end;
  Result := Result * (B - A) / (3 * n);
end;

procedure RingInflation;
var
  R: TAirwayRing;
  P: TRingParams;
  c, ro, exact: Double;
begin
  Writeln('4. Thick stiffening tube with tethering: pressure at a given area');
  FillChar(P, SizeOf(P), 0);
  P.Ri := 1; P.NLayers := 1;
  P.Layers[0].Thick := 0.5; P.Layers[0].Mu := 3; P.Layers[0].Stiffen := 2; P.Layers[0].NR := 4;
  P.Lobes := 4; P.NT := 4; P.KappaRatio := 20000;
  P.TetherK := 2; P.TetherR := 1.8;
  R := TAirwayRing.Create(P);
  c := 0.8;
  if not R.MoveTo(rmArea, Pi * (1 + c)) then Fail('no solution')
  else
  begin
    ro := Sqrt(1.5 * 1.5 + c);
    exact := TubeIntegral(1, 1.5, 3, 2, c) - P.TetherK * (P.TetherR - ro) * 1.5 / ro;
    Report('Ptm, lumen area 1.8 times unloaded', R.Ptm, exact, 2e-3);
    Report('outer radius', R.OuterRadius, ro, 1e-3);
  end;
  R.Free;
  { more compression than this and the tube wrinkles: the uniform state
    is then refused as unstable }
  P.TetherK := 0; c := -0.2;
  R := TAirwayRing.Create(P);
  if not R.MoveTo(rmArea, Pi * (1 + c)) then Fail('no solution')
  else
    Report('Ptm, lumen area 0.8 times unloaded, untethered', R.Ptm, TubeIntegral(1, 1.5, 3, 2, c), 2e-3);
  R.Free;
end;

procedure RingMuscle;
var
  R: TAirwayRing;
  P: TRingParams;
begin
  Writeln('5. Isometric muscle ring');
  FillChar(P, SizeOf(P), 0);
  P.Ri := 1; P.NLayers := 1;
  P.Layers[0].Thick := 0.3; P.Layers[0].Mu := 2; P.Layers[0].Muscle := 0.6; P.Layers[0].NR := 3;
  P.Lobes := 4; P.NT := 4; P.KappaRatio := 2000;
  P.T0 := 100; P.LMin := 0.25;
  R := TAirwayRing.Create(P);
  if not R.RampAct(0.5, 5) then Fail('no solution')
  else
    Report('Ptm holding the unloaded area', R.Ptm, 0.6 * 0.5 * 100 * Ln(1.3), 2e-3);
  R.Free;
end;

function ThinRing(Lobes: Integer): TRingParams;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Ri := 0.98; Result.NLayers := 1;
  Result.Layers[0].Thick := 0.04; Result.Layers[0].Mu := 1; Result.Layers[0].NR := 2;
  Result.Lobes := Lobes; Result.NT := 0; Result.KappaRatio := 2000;
  Result.Imperfection := 1e-3;
end;

procedure RingBuckling;
var
  R: TAirwayRing;
  n: Integer;
  pcr, w1, w2, p1, p2, x0, y0, x1, y1, est: Double;

  function Amplitude: Double;
  begin
    R.InnerPos(0, x0, y0); R.InnerPos(R.InnerCount - 1, x1, y1);
    Result := 0.5 * (Sqrt(x0 * x0 + y0 * y0) - Sqrt(x1 * x1 + y1 * y1));
  end;

begin
  Writeln('6. Buckling of a thin ring under suction (t/R = 0.04)');
  for n := 2 to 3 do
  begin
    { E' = 4 mu, I = t^3/12, Rm = 1 }
    pcr := (n * n - 1) * 4 * 1 * Power(0.04, 3) / 12;
    R := TAirwayRing.Create(ThinRing(n));
    p1 := 0.4 * pcr; p2 := 0.6 * pcr;
    if R.MoveTo(rmPressure, -p1) then
    begin
      w1 := Amplitude;
      if R.MoveTo(rmPressure, -p2) then
      begin
        w2 := Amplitude;
        est := (w2 * p2 - w1 * p1) / (w2 - w1);
        Report(Format('critical pressure, %d folds', [n]), est, pcr, 0.005);
      end
      else Fail('no solution at the second pressure');
    end
    else Fail('no solution at the first pressure');
    R.Free;
  end;
end;

procedure RingCollapse;
var
  R: TAirwayRing;
  A0, A, pOld, aOld, yOld, x, y, f, pc, ac, unitP: Double;
  k: Integer;
  found: Boolean;
begin
  Writeln('7. Collapsed thin ring: first contact of opposite walls');
  R := TAirwayRing.Create(ThinRing(2));
  A0 := R.LumenArea; A := A0;
  unitP := 4 * 1 * Power(0.04, 3) / 12;   { E'I / Rm^3 }
  found := False;
  pOld := 0; aOld := A0;
  R.InnerPos(R.InnerCount - 1, x, yOld);
  for k := 1 to 80 do
  begin
    A := A - 0.02 * A0;
    if not R.MoveTo(rmArea, A) then Break;
    R.InnerPos(R.InnerCount - 1, x, y);
    if y <= 0 then
    begin
      f := yOld / (yOld - y);
      pc := pOld + f * (R.Ptm - pOld);
      ac := aOld + f * (A - aOld);
      Report('contact pressure / (E''I/R^3)', -pc / unitP, 5.247, 0.05);
      Report('area at contact / unloaded area', ac / A0, 0.27, 0.06);
      found := True;
      Break;
    end;
    pOld := R.Ptm; aOld := A; yOld := y;
  end;
  if not found then Fail('the walls never met');
  R.Free;
end;

{ ---------------------------------------------------------------- }

procedure AlveolusDerivatives;
var
  M: TAlveolus;
  P: TAlveolusParams;
  Qv: array of Double;
  i, n: Integer;
  wp, wm, fd, worst, big, err: Double;
const
  h = 1e-7;
  Pa = 0.6;
begin
  Writeln('8-9. Alveolus: residual against energy, tangent against residual');
  P := NormalAlveolus;
  P.N := 12; P.Surf := sfConstant;
  M := TAlveolus.Create(P);
  SetLength(Qv, M.NDof);
  RandSeed := 1357;
  for i := 0 to High(Qv) do Qv[i] := 1.2 * M.Q[i] + 0.004 * (Random - 0.5);
  M.SetTrial(Qv, Pa);
  worst := 0; big := 0;
  for n := 0 to M.NDof - 1 do
  begin
    if M.IsFixed(n) then Continue;
    Qv[n] := Qv[n] + h; M.SetTrial(Qv, Pa); wp := M.TrialEnergy;
    Qv[n] := Qv[n] - 2 * h; M.SetTrial(Qv, Pa); wm := M.TrialEnergy;
    Qv[n] := Qv[n] + h; M.SetTrial(Qv, Pa);
    fd := (wp - wm) / (2 * h);
    worst := Max(worst, Abs(fd - M.TrialResidual(n)));
    big := Max(big, Abs(fd));
  end;
  Report('largest force difference / largest force', worst / big, 0, 1e-6);
  M.Free;
  P.Surf := sfDeflation;
  P.ARef := P.ARef * 0.9;
  M := TAlveolus.Create(P);
  M.SetTrial(Qv, Pa);
  M.CheckTangent(err, big);
  Report('largest K error / largest K (deflation film)', err / big, 0, 1e-6);
  M.Free;
end;

procedure AlveolusSphere;
var
  M: TAlveolus;
  P: TAlveolusParams;
  V0, lam, E, T, exact, cm: Double;
begin
  Writeln('10-11. Alveolus: mesh volume, and a closed sphere with a constant film');
  P := NormalAlveolus;
  M := TAlveolus.Create(P);
  cm := Cos(DegToRad(P.MouthAngle));
  { sphere less the cap cut off by the mouth's plane }
  V0 := Pi * Power(P.R0, 3) * (4 / 3 - (1 - cm) * (1 - cm) * (2 + cm) / 3);
  Report('unstressed volume, 60 elements', M.UnstressedVolume, V0, 1e-3);
  M.Free;
  P.MouthAngle := 90; P.RingEA := 0; P.Surf := sfConstant; P.N := 80;
  M := TAlveolus.Create(P);
  V0 := M.UnstressedVolume;
  if not M.MoveTo(amVolume, 2 * V0) then Fail('no solution')
  else
  begin
    lam := Power(2, 1 / 3);
    E := 0.5 * (lam * lam - 1);
    T := P.C * (P.A1 + P.A2) * E * Exp(2 * (P.A1 + P.A2) * E * E);
    exact := 2 * (T + P.Gamma) / (lam * P.R0);
    Report('pressure at twice the unstressed volume', M.P, exact, 1e-3);
  end;
  M.Free;
end;

{ ---------------------------------------------------------------- }

function LinearLaw(A0, k, PLo, PHi: Double): TTubeLaw;
var
  P, A: array[0..40] of Double;
  i: Integer;
begin
  for i := 0 to 40 do
  begin
    P[i] := PLo + (PHi - PLo) * i / 40;
    A[i] := A0 + k * P[i];
  end;
  Result := TTubeLaw.Create;
  Result.SetTable(P, A);
end;

procedure FlowChecks;
var
  L: TTubeLaw;
  Br: TBronchiole;
  P, A: array[0..60] of Double;
  i: Integer;
  worst, x, q, aup, adn, exact, c, q1, q2, aw: Double;
  lim, cl: Boolean;
  Lin: TLining;
begin
  Writeln('12. Tube law table');
  for i := 0 to 60 do
  begin
    P[i] := -3 + 6 * i / 60;
    A[i] := 1 + 0.9 * Tanh(P[i]);
  end;
  L := TTubeLaw.Create;
  L.SetTable(P, A);
  worst := 0;
  for i := 0 to 599 do
  begin
    x := -3 + 6 * (i + 0.5) / 600;
    worst := Max(worst, Abs(L.Area(x) - (1 + 0.9 * Tanh(x))));
  end;
  Report('largest interpolation error', worst, 0, 1e-4);
  worst := 0;
  for i := 0 to 599 do
  begin
    x := -3 + 6 * (i + 0.5) / 600;
    worst := Max(worst, Abs(L.Slope(x) - 0.9 / Sqr(Cosh(x))));
  end;
  Report('largest slope error', worst, 0, 5e-3);
  L.Free;

  Writeln('13. Rigid tube');
  L := LinearLaw(0.5, 1e-9, -50, 50);
  Br := TBronchiole.Create(L, 3);
  Br.Ka := 1; Br.Kb := 0;
  q := Br.Flow(0.2, 0.19, 0, lim);
  Report('Poiseuille flow, mm3/s', q, 0.25 * 0.01 / (8 * Pi * AirVisc * 3), 1e-5);
  Br.Free; L.Free;

  Writeln('14. Compliant tube, linear law, no inertia');
  L := LinearLaw(0.5, 0.4, -1, 1);
  Br := TBronchiole.Create(L, 3);
  Br.Ka := 1; Br.Kb := 0; Br.Rho := 0;
  q := Br.Flow(0.5, -0.6, 0, lim);
  aup := 0.5 + 0.4 * 0.5; adn := 0.5 - 0.4 * 0.6;
  exact := (aup * aup * aup - adn * adn * adn) / (3 * 0.4 * 8 * Pi * AirVisc * 3);
  Report('flow, mm3/s', q, exact, 1e-5);
  Br.Free;

  Writeln('15. Wave-speed limit');
  Br := TBronchiole.Create(L, 0.01);
  Br.Ka := 1; Br.Kb := 0; Br.Visc := 1e-12;
  q := Br.MaxFlow(0.5, 0);
  c := Sqrt(aup / (AirRho * 0.4));
  { the solver stops at S^2 = 0.98 }
  Report('largest flow / (A c)', q / (aup * c), Sqrt(0.98), 0.01);
  Br.Free; L.Free;

  Writeln('16. Flow limitation');
  for i := 0 to 60 do
  begin
    P[i] := -3 + 6 * i / 60;
    A[i] := 0.3 * (1 + 0.95 * Tanh(2 * P[i]));
  end;
  L := TTubeLaw.Create;
  L.SetTable(P, A);
  Br := TBronchiole.Create(L, 3);
  q1 := Br.Flow(1.0, -5, 1.0, lim);
  q2 := Br.Flow(1.0, -50, 1.0, lim);
  Report('flow at -50 kPa downstream / flow at -5', q2 / q1, 1, 1e-3);
  q := Br.Flow(1.0, 0.9, 1.0, lim);
  if (q > 0) and (q < 0.9 * q1) then Writeln('  flow rises with driving pressure below the limit  ok')
  else Fail('no rising part');
  Br.Free; L.Free;

  Writeln('17. Liquid lining');
  L := LinearLaw(0.5, 1e-9, -50, 50);
  Lin := NoLining;
  Lin.ALiq := 0.05; Lin.Gamma := 0.025;
  x := GasArea(L, Lin, 0, aw, cl);
  Report('gas area, rigid tube', x, 0.45, 1e-6);
  Lin.ALiq := 0.2;
  x := GasArea(L, Lin, 0, aw, cl);
  if cl then Writeln('  a film 23 % of the radius closes it  ok') else Fail('thick film did not close');
  L.Free;
end;

begin
  InitializeCBLAS;
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  RingDerivatives;
  RingArea;
  RingInflation;
  RingMuscle;
  RingBuckling;
  RingCollapse;
  AlveolusDerivatives;
  AlveolusSphere;
  FlowChecks;
  Writeln;
  if Fails = 0 then Writeln('All checks passed.')
  else Writeln(Fails, ' check(s) FAILED.');
  if Fails > 0 then Halt(1);
end.
