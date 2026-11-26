unit uAlveolus;

{ One alveolus as an axisymmetric membrane with a surfactant film: its
  pressure-volume curve and compliance. Units: mm, kPa (tensions are
  kPa mm = N/m; 0.025 is 25 mN/m).

  IDEALISATION   a lone balloon: a spherical cap of unstressed radius R0
  open at a mouth, gas inside at the alveolar pressure and the pleural
  pressure outside, so its pressure P is the transpulmonary one. A real
  alveolar wall is a septum shared with the next alveolus, with the same
  gas pressure on both faces, and the lung's recoil is carried through
  the network of septa and duct rings. The balloon is the classical
  stand-in; see the notes on what it gets wrong.

  GEOMETRY   the meridian from the pole (r = 0) to the mouth, N two-node
  conical elements. The mouth is at MouthAngle (degrees, seen from the
  centre) from the axis; its rim stays in its plane and carries an
  elastic ring (the alveolar entrance ring), energy
  pi rm EA (r/rm - 1)^2. MouthAngle = 90 with no ring is a hemisphere on
  a symmetry plane, i.e. a closed sphere (for the checks).

  TISSUE   membrane energy per unstressed area, Fung's form,
     w = C/2 (exp Q - 1),  Q = A1 (E1^2 + E2^2) + 2 A2 E1 E2,
  E = (stretch^2 - 1)/2 along the meridian (1) and round the hoop (2),
  evaluated at each element's middle.

  SURFACTANT   surface tension gamma times the current area. gamma
  depends on the film's area relative to ARef (the area at total lung
  capacity), x = (A/ARef - ALow)/(1 - ALow) clipped to 0..1:
     deflation  gamma = GammaMin + (GammaMax - GammaMin) x^2
     inflation  gamma = GammaMax - (GammaMax - GammaMinInfl) (1 - x)^3
  two fixed limbs, not a kinetic model of the film: assumed shapes after
  the measurements of Bachofen, Schurch et al. (about 30 mN/m at
  capacity, a few mN/m at functional residual capacity on deflation).
  sfConstant uses Gamma throughout; sfNone is the saline-filled lung.

  LOAD   P dV/dq with V the exact volume inside the cones up to the
  mouth's plane. P is prescribed (amPressure) or found for a prescribed
  volume (amVolume).

  SOLUTION   Newton; the matrix is small and, with the film's
  area-dependent tension, full: newVM's dense LinearSolve. }

{$mode delphi}{$H+}

interface

uses
  SysUtils, Math, newVM;

type
  TSurfactant = (sfNone, sfConstant, sfDeflation, sfInflation);
  TAlvMode = (amPressure, amVolume);

  TAlveolusParams = record
    R0: Double;
    MouthAngle: Double;
    N: Integer;
    C, A1, A2: Double;
    RingEA: Double;
    Surf: TSurfactant;
    Gamma, GammaMin, GammaMax, GammaMinInfl, ALow, ARef: Double;
    { the film's tension is multiplied by this: a lone sphere has far
      less surface per volume, and less change of surface with volume,
      than the septa and ducts of a real acinus (see FitAlveolus) }
    SurfFactor: Double;
  end;

  TAlveolus = class
  private
    FQ0, FQT, FR, FdV, FAbs, FK: array of Double;
    FPT, FVol, FArea, FEnergy: Double;
    FFixed: array of Boolean;
    function Assemble(BuildK: Boolean): Boolean;
  public
    Prm: TAlveolusParams;
    NN, NDof: Integer;
    Q: array of Double;   { accepted coordinates: r, z of each node }
    P: Double;            { accepted pressure, kPa }
    Iterations: Integer;
    Tolerance: Double;
    constructor Create(const AP: TAlveolusParams);
    function SurfaceTension(Area: Double; out dGdA: Double): Double;
    function Solve(Mode: TAlvMode; Target: Double): Boolean;
    function MoveTo(Mode: TAlvMode; Target: Double): Boolean;
    function Volume: Double;      { mm3, accepted state }
    function Area: Double;        { mm2 }
    function UnstressedVolume: Double;
    function PoleDepth: Double;      { pole to the mouth's plane }
    function MouthRadius: Double;
    { for the checks }
    procedure SetTrial(const AQ: array of Double; AP: Double);
    function TrialEnergy: Double;  { valid for sfNone and sfConstant }
    function TrialResidual(n: Integer): Double;
    function IsFixed(n: Integer): Boolean;
    procedure CheckTangent(out MaxErr, MaxK: Double);
  end;

{ An alveolus of radius 0.1 mm at functional residual capacity. The
  tissue constants were set so that the sphere's deflation limb gives 5
  cmH2O at that radius and 30 at 0.126 mm (twice the volume): assumed,
  see the notes. }
function NormalAlveolus: TAlveolusParams;
{ NormalAlveolus refitted for the whole lung: the tissue constant C so
  that the saline-filled alveolus holds PSaline at the volume of a
  sphere of radius RTLC, and the surface factor so that the air-filled
  one on its deflation limb holds PAir there (kPa). Surface forces then
  carry 1 - PSaline/PAir of the recoil at total lung capacity, as they
  do in a real lung (about two thirds, from saline against air
  inflation), which the lone sphere cannot do with the measured tension. }
function FitAlveolus(PAir, PSaline, RTLC: Double): TAlveolusParams;

implementation

function NormalAlveolus: TAlveolusParams;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.R0 := 0.08;
  Result.MouthAngle := 50;
  Result.N := 60;
  Result.C := 0.0473; Result.A1 := 0.8; Result.A2 := 0.4;
  Result.RingEA := 0.02;
  Result.Surf := sfDeflation;
  Result.Gamma := 0.025;
  Result.SurfFactor := 1;
  Result.GammaMin := 0.001; Result.GammaMax := 0.030; Result.GammaMinInfl := 0.010;
  Result.ALow := 0.4;
  { the cap's area when the sphere's radius is 0.126 mm }
  Result.ARef := 2 * Pi * Sqr(0.126) * (1 + Cos(DegToRad(Result.MouthAngle)));
end;

function FitAlveolus(PAir, PSaline, RTLC: Double): TAlveolusParams;
var
  M: TAlveolus;
  F: TAlveolusParams;
  V0, VT, ps, pa: Double;
  it: Integer;

  function PAt(Surf: TSurfactant): Double;
  var
    Q: TAlveolusParams;
  begin
    Q := F; Q.Surf := Surf;
    M := TAlveolus.Create(Q);
    try
      if not M.MoveTo(amVolume, VT) then raise Exception.Create('FitAlveolus : no solution');
      Result := M.P;
    finally
      M.Free;
    end;
  end;

begin
  F := NormalAlveolus;
  M := TAlveolus.Create(F);
  V0 := M.UnstressedVolume;
  M.Free;
  VT := V0 * Power(RTLC / F.R0, 3);
  { the saline pressure is proportional to C; the surface's share nearly
    so to the factor, the shape at a fixed volume changing a little }
  { the saline pressure is nearly proportional to C (the mouth ring is
    not scaled with it) }
  for it := 1 to 30 do
  begin
    ps := PAt(sfNone);
    if Abs(ps / PSaline - 1) < 1e-7 then Break;
    F.C := F.C * PSaline / ps;
  end;
  for it := 1 to 8 do
  begin
    pa := PAt(sfDeflation);
    ps := PAt(sfNone);
    if Abs(pa / PAir - 1) < 1e-6 then Break;
    F.SurfFactor := F.SurfFactor * (PAir - ps) / (pa - ps);
  end;
  Result := F;
end;

constructor TAlveolus.Create(const AP: TAlveolusParams);
var
  k: Integer;
  phi, phiMax: Double;
begin
  inherited Create;
  Prm := AP;
  Tolerance := 1e-9;
  NN := Prm.N + 1;
  NDof := 2 * NN;
  SetLength(Q, NDof); SetLength(FQ0, NDof); SetLength(FQT, NDof);
  SetLength(FR, NDof); SetLength(FdV, NDof); SetLength(FAbs, NDof);
  SetLength(FFixed, NDof + 1);
  SetLength(FK, (NDof + 1) * (NDof + 1));
  phiMax := Pi - DegToRad(Prm.MouthAngle);
  for k := 0 to NN - 1 do
  begin
    phi := phiMax * k / Prm.N;
    FQ0[2 * k] := Prm.R0 * Sin(phi);
    FQ0[2 * k + 1] := -Prm.R0 * Cos(phi);
  end;
  FQ0[0] := 0;
  for k := 0 to NDof - 1 do Q[k] := FQ0[k];
  FFixed[0] := True;          { pole on the axis }
  FFixed[NDof - 1] := True;   { mouth in its plane }
  P := 0;
end;

function TAlveolus.SurfaceTension(Area: Double; out dGdA: Double): Double;
var
  x: Double;
begin
  dGdA := 0;
  case Prm.Surf of
    sfNone: Result := 0;
    sfConstant: Result := Prm.Gamma;
  else
    begin
      x := (Area / Prm.ARef - Prm.ALow) / (1 - Prm.ALow);
      if x <= 0 then
      begin
        if Prm.Surf = sfDeflation then Result := Prm.GammaMin else Result := Prm.GammaMinInfl;
      end
      else if x >= 1 then
        Result := Prm.GammaMax
      else if Prm.Surf = sfDeflation then
      begin
        Result := Prm.GammaMin + (Prm.GammaMax - Prm.GammaMin) * x * x;
        dGdA := 2 * (Prm.GammaMax - Prm.GammaMin) * x / ((1 - Prm.ALow) * Prm.ARef);
      end
      else
      begin
        Result := Prm.GammaMax - (Prm.GammaMax - Prm.GammaMinInfl) * (1 - x) * Sqr(1 - x);
        dGdA := 3 * (Prm.GammaMax - Prm.GammaMinInfl) * Sqr(1 - x) / ((1 - Prm.ALow) * Prm.ARef);
      end;
    end;
  end;
  Result := Result * Prm.SurfFactor;
  dGdA := dGdA * Prm.SurfFactor;
end;

function TAlveolus.Assemble(BuildK: Boolean): Boolean;
var
  e, i, j, n, m: Integer;
  r1, z1, r2, z2, dr, dz, L, L0, Rm0, rm, A0e, l1, l2, E1, E2, Qe, ex, g1, g2: Double;
  wE1, wE2, w11, w12, w22, w1, w2, s, gam, dgam, lr, f, v: Double;
  tL, dl2, dA, dV: array[0..3] of Double;
  d2L, d2A, d2V, ke: array[0..3, 0..3] of Double;
  gA: array of Double;
  idx: array[0..3] of Integer;
begin
  Result := False;
  n := NDof + 1;
  for i := 0 to NDof - 1 do begin FR[i] := 0; FdV[i] := 0; FAbs[i] := 0; end;
  if BuildK then
    for i := 0 to n * n - 1 do FK[i] := 0;
  SetLength(gA, NDof);
  FVol := 0; FArea := 0; FEnergy := 0;
  { the film's tension depends on the whole area: find it first }
  for e := 0 to Prm.N - 1 do
  begin
    dr := FQT[2 * e + 2] - FQT[2 * e]; dz := FQT[2 * e + 3] - FQT[2 * e + 1];
    FArea := FArea + Pi * (FQT[2 * e] + FQT[2 * e + 2]) * Sqrt(dr * dr + dz * dz);
  end;
  gam := SurfaceTension(FArea, dgam);
  for e := 0 to Prm.N - 1 do
  begin
    for i := 0 to 3 do idx[i] := 2 * e + i;
    r1 := FQT[idx[0]]; z1 := FQT[idx[1]]; r2 := FQT[idx[2]]; z2 := FQT[idx[3]];
    dr := r2 - r1; dz := z2 - z1;
    L := Sqrt(dr * dr + dz * dz);
    rm := 0.5 * (r1 + r2);
    if (L <= 0) or (rm <= 0) then Exit;
    L0 := Sqrt(Sqr(FQ0[idx[2]] - FQ0[idx[0]]) + Sqr(FQ0[idx[3]] - FQ0[idx[1]]));
    Rm0 := 0.5 * (FQ0[idx[0]] + FQ0[idx[2]]);
    A0e := 2 * Pi * Rm0 * L0;
    l1 := L / L0; l2 := rm / Rm0;
    tL[0] := -dr / L; tL[1] := -dz / L; tL[2] := dr / L; tL[3] := dz / L;
    dl2[0] := 0.5 / Rm0; dl2[1] := 0; dl2[2] := 0.5 / Rm0; dl2[3] := 0;
    for i := 0 to 3 do
      for j := 0 to 3 do
      begin
        if (i mod 2) = (j mod 2) then
        begin
          if i = j then s := 1 else s := -1;
        end
        else
          s := 0;
        d2L[i, j] := (s - tL[i] * tL[j]) / L;
      end;
    { tissue }
    E1 := 0.5 * (l1 * l1 - 1); E2 := 0.5 * (l2 * l2 - 1);
    Qe := Prm.A1 * (E1 * E1 + E2 * E2) + 2 * Prm.A2 * E1 * E2;
    ex := 0.5 * Prm.C * Exp(Qe);
    g1 := 2 * Prm.A1 * E1 + 2 * Prm.A2 * E2; g2 := 2 * Prm.A1 * E2 + 2 * Prm.A2 * E1;
    wE1 := ex * g1; wE2 := ex * g2;
    w1 := wE1 * l1; w2 := wE2 * l2;
    w11 := ex * (g1 * g1 + 2 * Prm.A1) * l1 * l1 + wE1;
    w12 := ex * (g1 * g2 + 2 * Prm.A2) * l1 * l2;
    w22 := ex * (g2 * g2 + 2 * Prm.A1) * l2 * l2 + wE2;
    FEnergy := FEnergy + A0e * (ex - 0.5 * Prm.C);
    { area and volume of the cone, and their derivatives }
    for i := 0 to 3 do dA[i] := 2 * Pi * (L * dl2[i] * Rm0 + rm * tL[i]);
    s := r1 * r1 + r1 * r2 + r2 * r2;
    FVol := FVol + Pi / 3 * dz * s;
    dV[0] := Pi / 3 * (2 * r1 + r2) * dz; dV[1] := -Pi / 3 * s;
    dV[2] := Pi / 3 * (r1 + 2 * r2) * dz; dV[3] := Pi / 3 * s;
    for i := 0 to 3 do
    begin
      f := A0e * (w1 * tL[i] / L0 + w2 * dl2[i]) + gam * dA[i];
      FR[idx[i]] := FR[idx[i]] + f;
      FAbs[idx[i]] := FAbs[idx[i]] + Abs(A0e * w1 * tL[i] / L0) + Abs(A0e * w2 * dl2[i]) + Abs(gam * dA[i]);
      FdV[idx[i]] := FdV[idx[i]] + dV[i];
      gA[idx[i]] := gA[idx[i]] + dA[i];
    end;
    if BuildK then
    begin
      FillChar(d2V, SizeOf(d2V), 0);
      d2V[0, 0] := 2 * Pi / 3 * dz; d2V[0, 2] := Pi / 3 * dz;
      d2V[2, 0] := Pi / 3 * dz; d2V[2, 2] := 2 * Pi / 3 * dz;
      d2V[0, 1] := -Pi / 3 * (2 * r1 + r2); d2V[1, 0] := d2V[0, 1];
      d2V[0, 3] := Pi / 3 * (2 * r1 + r2); d2V[3, 0] := d2V[0, 3];
      d2V[2, 1] := -Pi / 3 * (r1 + 2 * r2); d2V[1, 2] := d2V[2, 1];
      d2V[2, 3] := Pi / 3 * (r1 + 2 * r2); d2V[3, 2] := d2V[2, 3];
      for i := 0 to 3 do
        for j := 0 to 3 do
        begin
          d2A[i, j] := 2 * Pi * (Rm0 * (dl2[i] * tL[j] + tL[i] * dl2[j]) + rm * d2L[i, j]);
          ke[i, j] := A0e * (w11 * tL[i] * tL[j] / (L0 * L0)
            + w12 * (tL[i] * dl2[j] + dl2[i] * tL[j]) / L0
            + w22 * dl2[i] * dl2[j] + w1 * d2L[i, j] / L0)
            + gam * d2A[i, j] - FPT * d2V[i, j];
          FK[idx[i] * n + idx[j]] := FK[idx[i] * n + idx[j]] + ke[i, j];
        end;
    end;
  end;
  { the film's change of tension with area }
  if BuildK and (dgam <> 0) then
    for i := 0 to NDof - 1 do
      if gA[i] <> 0 then
        for j := 0 to NDof - 1 do
          FK[i * n + j] := FK[i * n + j] + dgam * gA[i] * gA[j];
  if Prm.Surf = sfConstant then FEnergy := FEnergy + gam * FArea;
  { mouth ring }
  if Prm.RingEA > 0 then
  begin
    m := NDof - 2;
    lr := FQT[m] / FQ0[m];
    FEnergy := FEnergy + Pi * FQ0[m] * Prm.RingEA * Sqr(lr - 1);
    v := 2 * Pi * Prm.RingEA * (lr - 1);
    FR[m] := FR[m] + v; FAbs[m] := FAbs[m] + Abs(v);
    if BuildK then FK[m * n + m] := FK[m * n + m] + 2 * Pi * Prm.RingEA / FQ0[m];
  end;
  Result := True;
end;

function TAlveolus.Solve(Mode: TAlvMode; Target: Double): Boolean;
var
  it, i, j, n, nn1: Integer;
  rmax, fmax, cerr, dmax, sc: Double;
  A, B: TVMobj;
  pa, pb: PDouble;
begin
  Result := False;
  for i := 0 to NDof - 1 do FQT[i] := Q[i];
  FPT := P;
  if Mode = amPressure then FPT := Target;
  nn1 := NDof + 1;
  n := NDof + Ord(Mode = amVolume);
  for it := 1 to 40 do
  begin
    if not Assemble(True) then Exit;
    rmax := 0; fmax := 1e-12 * Prm.C * Prm.R0;
    for i := 0 to NDof - 1 do
      if not FFixed[i] then
      begin
        FR[i] := FR[i] - FPT * FdV[i];
        rmax := Max(rmax, Abs(FR[i]));
        fmax := Max(fmax, FAbs[i] + Abs(FPT * FdV[i]));
      end
      else
        FR[i] := 0;
    cerr := 0;
    if Mode = amVolume then cerr := FVol - Target;
    if (rmax <= Tolerance * fmax) and (Abs(cerr) <= 1e-12 * Power(Prm.R0, 3)) then
    begin
      for i := 0 to NDof - 1 do Q[i] := FQT[i];
      P := FPT;
      Iterations := it - 1;
      Exit(True);
    end;
    A := TVMobj.Create(n, n);
    B := TVMobj.Create(n, 1);
    pa := A.DataPtr; pb := B.DataPtr;
    for i := 0 to NDof - 1 do
    begin
      if FFixed[i] then
      begin
        pa[i * n + i] := 1; pb[i] := 0;
        Continue;
      end;
      for j := 0 to NDof - 1 do
        if not FFixed[j] then pa[i * n + j] := FK[i * nn1 + j];
      pb[i] := -FR[i];
      if Mode = amVolume then
      begin
        pa[i * n + NDof] := -FdV[i];
        pa[NDof * n + i] := -FdV[i];
      end;
    end;
    if Mode = amVolume then pb[NDof] := cerr;
    if LinearSolve(A, B) <> 0 then Exit;
    dmax := 0;
    for i := 0 to NDof - 1 do dmax := Max(dmax, Abs(pb[i]));
    if IsNan(dmax) then Exit;
    sc := 1;
    if dmax > 0.2 * Prm.R0 then sc := 0.2 * Prm.R0 / dmax;
    for i := 0 to NDof - 1 do FQT[i] := FQT[i] + sc * pb[i];
    if Mode = amVolume then FPT := FPT + sc * pb[NDof];
  end;
end;

function TAlveolus.MoveTo(Mode: TAlvMode; Target: Double): Boolean;

  function Go(T: Double; Depth: Integer): Boolean;
  var
    cur: Double;
  begin
    if Solve(Mode, T) then Exit(True);
    if Depth >= 8 then Exit(False);
    if Mode = amVolume then cur := Volume else cur := P;
    Result := Go(0.5 * (cur + T), Depth + 1) and Go(T, Depth + 1);
  end;

begin
  Result := Go(Target, 0);
end;

function TAlveolus.Volume: Double;
var
  e: Integer;
  r1, r2: Double;
begin
  Result := 0;
  for e := 0 to Prm.N - 1 do
  begin
    r1 := Q[2 * e]; r2 := Q[2 * e + 2];
    Result := Result + Pi / 3 * (Q[2 * e + 3] - Q[2 * e + 1]) * (r1 * r1 + r1 * r2 + r2 * r2);
  end;
end;

function TAlveolus.Area: Double;
var
  e: Integer;
begin
  Result := 0;
  for e := 0 to Prm.N - 1 do
    Result := Result + Pi * (Q[2 * e] + Q[2 * e + 2])
      * Sqrt(Sqr(Q[2 * e + 2] - Q[2 * e]) + Sqr(Q[2 * e + 3] - Q[2 * e + 1]));
end;

function TAlveolus.UnstressedVolume: Double;
var
  e: Integer;
  r1, r2: Double;
begin
  Result := 0;
  for e := 0 to Prm.N - 1 do
  begin
    r1 := FQ0[2 * e]; r2 := FQ0[2 * e + 2];
    Result := Result + Pi / 3 * (FQ0[2 * e + 3] - FQ0[2 * e + 1]) * (r1 * r1 + r1 * r2 + r2 * r2);
  end;
end;

function TAlveolus.PoleDepth: Double;
begin
  Result := Q[NDof - 1] - Q[1];
end;

function TAlveolus.MouthRadius: Double;
begin
  Result := Q[NDof - 2];
end;

procedure TAlveolus.SetTrial(const AQ: array of Double; AP: Double);
var
  i: Integer;
begin
  for i := 0 to NDof - 1 do
    if FFixed[i] then FQT[i] := FQ0[i] else FQT[i] := AQ[i];
  FPT := AP;
  if not Assemble(False) then raise Exception.Create('TAlveolus.SetTrial : degenerate element');
end;

function TAlveolus.TrialEnergy: Double;
begin
  Result := FEnergy - FPT * FVol;
end;

function TAlveolus.TrialResidual(n: Integer): Double;
begin
  Result := FR[n] - FPT * FdV[n];
end;

function TAlveolus.IsFixed(n: Integer): Boolean;
begin
  Result := FFixed[n];
end;

procedure TAlveolus.CheckTangent(out MaxErr, MaxK: Double);
var
  K, rp, rm, q0: array of Double;
  i, j, n: Integer;
  fd: Double;
const
  h = 1e-8;
begin
  n := NDof + 1;
  SetLength(K, NDof * NDof); SetLength(rp, NDof); SetLength(rm, NDof); SetLength(q0, NDof);
  for i := 0 to NDof - 1 do q0[i] := FQT[i];
  Assemble(True);
  for i := 0 to NDof - 1 do
    for j := 0 to NDof - 1 do K[i * NDof + j] := FK[i * n + j];
  MaxErr := 0; MaxK := 0;
  for j := 0 to NDof - 1 do
  begin
    if FFixed[j] then Continue;
    FQT[j] := q0[j] + h; Assemble(False);
    for i := 0 to NDof - 1 do rp[i] := FR[i] - FPT * FdV[i];
    FQT[j] := q0[j] - h; Assemble(False);
    for i := 0 to NDof - 1 do rm[i] := FR[i] - FPT * FdV[i];
    FQT[j] := q0[j];
    for i := 0 to NDof - 1 do
    begin
      if FFixed[i] then Continue;
      fd := (rp[i] - rm[i]) / (2 * h);
      MaxErr := Max(MaxErr, Abs(fd - K[i * NDof + j]));
      MaxK := Max(MaxK, Abs(K[i * NDof + j]));
    end;
  end;
  Assemble(False);
end;

end.
