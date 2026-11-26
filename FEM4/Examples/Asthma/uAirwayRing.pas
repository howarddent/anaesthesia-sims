unit uAirwayRing;

{ Finite-strain mechanics of a bronchiole's wall in cross-section: the
  source of its tube law (lumen area against transmural pressure), with
  smooth muscle tone, wall thickening and parenchymal tethering in it.
  Plane strain, unit length of airway. FEM4's structural engine is
  small-strain, so this is self-contained, its own banded solver included.
  Units: mm, kPa (forces mN per mm of airway).

  GEOMETRY   concentric layers from the lumen outwards (mucosa,
  submucosa, smooth muscle, adventitia: any number up to MaxLayers).
  The wall buckles into Lobes folds round the circumference, so only half
  a fold is meshed: the sector 0 <= theta <= pi/Lobes with symmetry lines
  at both ends. A radial imperfection eps cos(Lobes theta) starts the
  fold. 9-node quadrilaterals, NR per layer, NT round the sector.

  MATERIAL   each layer isotropic, nearly incompressible, stiffening:
     W = Mu/(2b) (exp(b (I1 - 3)) - 1) - Mu ln J   (b = 0: neo-Hookean)
  plus a volumetric energy Kappa/2 (theta - 1)^2, theta being the L2
  projection of J onto 1, xi, eta in each element (Q2 with discontinuous
  linear pressure, the pressure eliminated). Kappa = KappaRatio Mu.

  SMOOTH MUSCLE   circumferential fibres in the layers with Muscle > 0
  (the fraction of the layer that is muscle). Nominal active stress
     Tn = Act T0 fl(lambda),  fl = 1 - ((lambda - 1)/(1 - LMin))^2  (>= 0)
  lambda the fibre stretch from the unloaded state: isometric
  force-length only, so it has an energy (Act T0 times the integral of
  fl). No force-velocity, no fluidisation by tidal stretch.

  LUMEN   the transmural pressure Ptm (lumen less peribronchial) acts on
  the inner surface. With an incompressible wall a pressure common to
  both surfaces does nothing, so only the difference matters. The load
  is Ptm dA/du with A the exact area inside the quadratic inner edges, so
  it follows the wall and is conservative. Ptm is prescribed
  (rmPressure) or found for a prescribed area (rmArea), which passes
  through buckling without trouble.

  TETHERING   the parenchyma pulls on the outer surface: an outward
  traction TetherK (TetherR - r) per unit unloaded surface, r the current
  radius. After Lai-Fook (1979): a hole in the parenchyma narrower than
  uniform expansion would make it, by dD/D, is pulled out by 2 mu dD/D,
  mu = 0.7 Ptp. So TetherR is the outer radius under uniform expansion
  and TetherK = 1.4 Ptp / TetherR (SetTether).

  CONTACT   inner-surface nodes that cross a symmetry line (meeting the
  mirror image of the wall) are pushed back by a penalty ContactK.

  SOLUTION   Newton on the displacements (and Ptm in rmArea). The tangent
  is symmetric and banded: L D L' without pivoting, whose negative
  pivots count the negative eigenvalues. An equilibrium that is not
  stable (the unfolded state past buckling, which a long step can land
  on) is refused, and a refused or failed step is halved (MoveTo). }

{$mode delphi}{$H+}

interface

uses
  SysUtils, Math, uTubeLaw;

const
  MaxLayers = 6;
  CmH2O = 0.0980665;  { kPa }

type
  TRingLayer = record
    Thick: Double;    { mm, unloaded }
    Mu: Double;       { kPa }
    Stiffen: Double;  { b }
    Muscle: Double;   { fraction of the layer that is smooth muscle }
    NR: Integer;      { elements through it }
  end;

  TRingParams = record
    Ri: Double;       { unloaded lumen radius, mm }
    NLayers: Integer;
    Layers: array[0..MaxLayers - 1] of TRingLayer;
    Lobes: Integer;   { folds round the circumference, >= 2 }
    NT: Integer;      { elements round half a fold; 0 = chosen from the thinnest element }
    KappaRatio: Double;
    T0, LMin, Act: Double;
    TetherK, TetherR: Double;
    Imperfection: Double;
    ContactK: Double;
  end;

  TRingMode = (rmPressure, rmArea);

  TAirwayRing = class
  private
    FNRn, FNTn: Integer;
    FConn: array of array[0..8] of Integer;
    FEMu, FEB, FEMus, FEKap: array of Double;
    FEMinv: array of Double;           { 9 per element }
    FGW, FGdN, FGFib: array of Double; { per Gauss point: 1, 18, 2 }
    FPhi: array[0..8, 0..2] of Double;
    FS: array[0..2, 0..2] of Double;   { area form of a quadratic edge }
    FEdgeN: array[0..2, 0..2] of Double;
    FTW: array of Double;              { outer edges: reference weight per Gauss point }
    FFixed: array of Boolean;
    FUT, FR, FdA, FAbs, FSaveU: array of Double;
    FPT, FSaveP, FSaveAct: Double;
    FAs: Double;                       { trial sector area }
    FKB, FX1, FX2: array of Double;    { lower band of the symmetric tangent; work }
    FHB: Integer;                      { half band width }
    FNx, FNy, FPen, FMuMax: Double;
    FMusSum, FMusW, FEnergy: Double;
    procedure BuildMesh;
    procedure AddT(i, j: Integer; v: Double);
    function Assemble(BuildK: Boolean): Boolean;
    function InnerNode(j: Integer): Integer;
    function Factor(out Neg: Integer): Boolean;
    procedure BandSolve(var V: array of Double);
  public
    Prm: TRingParams;
    NN, NE, NDof: Integer;
    X, U: array of Double;   { reference coordinates, accepted displacements }
    Ptm: Double;             { accepted transmural pressure, kPa }
    Iterations: Integer;
    Stable: Boolean;         { the last equilibrium Solve found was a stable one }
    LastFail: string;        { why the last Solve failed }
    Tolerance: Double;       { largest force imbalance over largest nodal force }
    constructor Create(const P: TRingParams);
    { One Newton solve from the accepted state to a pressure (kPa) or a
      whole-lumen area (mm2); accepted only on success. }
    function Solve(Mode: TRingMode; Target: Double): Boolean;
    { The same, halving the step when it fails. }
    function MoveTo(Mode: TRingMode; Target: Double): Boolean;
    { Change the muscle's activation at the present area. }
    function RampAct(Target: Double; Steps: Integer): Boolean;
    function LumenArea: Double;       { accepted state, whole lumen, mm2 }
    function StrainEnergy: Double;    { accepted state, whole ring, mN }
    function MuscleStretch: Double;   { mean fibre stretch of the muscle, last assembly }
    function OuterRadius: Double;     { mean of the outer nodes }
    procedure InnerPos(j: Integer; out px, py: Double); { j = 0 .. 2 NT }
    function InnerCount: Integer;
    procedure SaveState;
    procedure RestoreState;
    { for the checks: all on the trial state }
    procedure SetTrial(const AU: array of Double; AP: Double);
    function TrialEnergy: Double;     { sector: internal energy less AP times area }
    function TrialResidual(n: Integer): Double;
    function IsFixed(n: Integer): Boolean;
    procedure CheckTangent(out MaxErr, MaxK: Double);
  end;

{ A membranous bronchiole of about generation 14, unloaded lumen radius
  Ri mm, and its asthmatic counterpart: Thickening multiplies the
  thickness of every layer (the muscle's by its square, as muscle mass
  rises most), Act is the muscle's activation. All values assumed: see
  the implementation. }
function NormalBronchiole(Ri: Double): TRingParams;
function AsthmaBronchiole(Ri, Thickening, Act: Double): TRingParams;
function WallThickness(const P: TRingParams): Double;
{ Tethering for transpulmonary pressure Ptp (kPa) when uniform expansion
  would give Expansion times the unloaded outer radius. }
procedure SetTether(var P: TRingParams; Ptp, Expansion: Double);
{ The tube law from PLo to PHi (kPa), by marching the area up and down
  from the unloaded one. Notes describes what happened. }
function BuildTubeLaw(const P: TRingParams; PLo, PHi: Double; out Notes: string): TTubeLaw;
{ The number of folds, NMin..NMax, with the least strain energy when the
  lumen is AFrac of its unloaded area. }
function BestLobes(const P: TRingParams; AFrac: Double; NMin, NMax: Integer): Integer;

implementation

const
  G3: array[0..2] of Double = (-0.77459666924148338, 0, 0.77459666924148338);
  W3: array[0..2] of Double = (0.55555555555555556, 0.88888888888888889, 0.55555555555555556);

procedure Quad1D(xi: Double; out N, dN: array of Double);
begin
  N[0] := 0.5 * xi * (xi - 1); N[1] := 1 - xi * xi; N[2] := 0.5 * xi * (xi + 1);
  dN[0] := xi - 0.5; dN[1] := -2 * xi; dN[2] := xi + 0.5;
end;

function WallThickness(const P: TRingParams): Double;
var
  l: Integer;
begin
  Result := 0;
  for l := 0 to P.NLayers - 1 do Result := Result + P.Layers[l].Thick;
end;

function NormalBronchiole(Ri: Double): TRingParams;

  procedure Layer(l: Integer; Thick, Mu, b, Muscle: Double; NR: Integer);
  begin
    Result.Layers[l].Thick := Thick; Result.Layers[l].Mu := Mu;
    Result.Layers[l].Stiffen := b; Result.Layers[l].Muscle := Muscle;
    Result.Layers[l].NR := NR;
  end;

begin
  { Assumed, in the spirit of the two-layer folding models (Wiggs et al.
    1997; Hrousis & Kamm 2002): a thin stiff inner layer (epithelium,
    basement membrane and the collagen under it) on a soft submucosa,
    then the muscle and a soft adventitia. Thicknesses are fractions of
    the lumen radius, roughly a small airway's wall area fractions
    (James et al. 1989); the moduli are orders of magnitude only. }
  FillChar(Result, SizeOf(Result), 0);
  Result.Ri := Ri;
  Result.NLayers := 4;
  Layer(0, 0.03 * Ri, 30, 3, 0, 2);     { mucosa }
  Layer(1, 0.08 * Ri, 1.5, 3, 0, 2);    { submucosa }
  Layer(2, 0.04 * Ri, 3, 3, 0.8, 1);    { smooth muscle }
  Layer(3, 0.08 * Ri, 1.5, 3, 0, 1);    { adventitia }
  Result.Lobes := 3;
  Result.NT := 0;
  Result.KappaRatio := 1000;
  Result.T0 := 100;      { kPa: airway smooth muscle's maximal isometric stress }
  Result.LMin := 0.25;   { it can shorten to a quarter of its length }
  Result.Act := 0;
  Result.Imperfection := 2e-3;
  Result.ContactK := 2000;
end;

function AsthmaBronchiole(Ri, Thickening, Act: Double): TRingParams;
var
  l: Integer;
begin
  Result := NormalBronchiole(Ri);
  for l := 0 to Result.NLayers - 1 do
    if Result.Layers[l].Muscle > 0 then
      Result.Layers[l].Thick := Result.Layers[l].Thick * Sqr(Thickening)
    else
      Result.Layers[l].Thick := Result.Layers[l].Thick * Thickening;
  Result.Act := Act;
end;

procedure SetTether(var P: TRingParams; Ptp, Expansion: Double);
begin
  P.TetherR := Expansion * (P.Ri + WallThickness(P));
  P.TetherK := 1.4 * Ptp / P.TetherR;
end;

{ ---------------------------------------------------------------- }

constructor TAirwayRing.Create(const P: TRingParams);
begin
  inherited Create;
  Prm := P;
  Tolerance := 1e-8;
  BuildMesh;
end;

function TAirwayRing.InnerNode(j: Integer): Integer;
begin
  Result := j * FNRn;
end;

function TAirwayRing.InnerCount: Integer;
begin
  Result := FNTn;
end;

procedure TAirwayRing.BuildMesh;
var
  l, i, j, e, er, et, a, b, g, gi, gj, nrTot, k, c, d: Integer;
  alpha, hmin, rmid, th, r, det, xi, eta, w, gx, gy, gr, sx, sy: Double;
  rn: array of Double;
  elLayer: array of Integer;
  Nr, dNr, Nt, dNt: array[0..2] of Double;
  dNxi: array[0..8, 0..1] of Double;
  J0, Ji: array[0..3] of Double;
  M, Mi: array[0..8] of Double;
begin
  if Prm.Lobes < 2 then raise Exception.Create('TAirwayRing : Lobes must be at least 2');
  alpha := Pi / Prm.Lobes;
  nrTot := 0; hmin := 1e30; FMuMax := 0;
  for l := 0 to Prm.NLayers - 1 do
  begin
    nrTot := nrTot + Prm.Layers[l].NR;
    hmin := Min(hmin, Prm.Layers[l].Thick / Prm.Layers[l].NR);
    FMuMax := Max(FMuMax, Prm.Layers[l].Mu);
  end;
  rmid := Prm.Ri + 0.5 * WallThickness(Prm);
  if Prm.NT <= 0 then
    Prm.NT := EnsureRange(Ceil(alpha * rmid / (5 * hmin)), 4, 40);
  FNRn := 2 * nrTot + 1;
  FNTn := 2 * Prm.NT + 1;
  NN := FNRn * FNTn;
  NE := nrTot * Prm.NT;
  NDof := 2 * NN;
  { radial node positions, and the layer of each radial element }
  SetLength(rn, FNRn); SetLength(elLayer, nrTot);
  r := Prm.Ri; k := 0; e := 0;
  rn[0] := r;
  for l := 0 to Prm.NLayers - 1 do
    for i := 1 to Prm.Layers[l].NR do
    begin
      rn[k + 1] := r + 0.5 * Prm.Layers[l].Thick / Prm.Layers[l].NR;
      rn[k + 2] := r + Prm.Layers[l].Thick / Prm.Layers[l].NR;
      r := rn[k + 2]; Inc(k, 2);
      elLayer[e] := l; Inc(e);
    end;
  { node (i radial, j angular) = j FNRn + i: the band is narrow }
  SetLength(X, NDof); SetLength(U, NDof); SetLength(FUT, NDof);
  SetLength(FR, NDof); SetLength(FdA, NDof); SetLength(FAbs, NDof);
  SetLength(FSaveU, NDof); SetLength(FFixed, NDof + 1);
  SetLength(FX1, NDof); SetLength(FX2, NDof);
  FHB := 4 * FNRn + 5;
  SetLength(FKB, NDof * (FHB + 1));
  for j := 0 to FNTn - 1 do
  begin
    th := alpha * j / (FNTn - 1);
    for i := 0 to FNRn - 1 do
    begin
      r := rn[i] * (1 + Prm.Imperfection * Cos(Prm.Lobes * th));
      X[2 * (j * FNRn + i)] := r * Cos(th);
      X[2 * (j * FNRn + i) + 1] := r * Sin(th);
    end;
  end;
  for i := 0 to FNRn - 1 do
  begin
    X[2 * i + 1] := 0;
    FFixed[2 * i + 1] := True;   { theta = 0: no y displacement }
  end;
  FNx := -Sin(alpha); FNy := Cos(alpha);  { normal of the far symmetry line }
  FPen := 1e3 * Prm.KappaRatio * FMuMax;
  { elements }
  SetLength(FConn, NE);
  SetLength(FEMu, NE); SetLength(FEB, NE); SetLength(FEMus, NE); SetLength(FEKap, NE);
  SetLength(FEMinv, 9 * NE);
  SetLength(FGW, 9 * NE); SetLength(FGdN, 9 * NE * 18); SetLength(FGFib, 9 * NE * 2);
  for g := 0 to 8 do
  begin
    FPhi[g, 0] := 1; FPhi[g, 1] := G3[g mod 3]; FPhi[g, 2] := G3[g div 3];
  end;
  for et := 0 to Prm.NT - 1 do
    for er := 0 to nrTot - 1 do
    begin
      e := et * nrTot + er;
      for b := 0 to 2 do
        for a := 0 to 2 do
          FConn[e][a + 3 * b] := (2 * et + b) * FNRn + 2 * er + a;
      l := elLayer[er];
      FEMu[e] := Prm.Layers[l].Mu; FEB[e] := Prm.Layers[l].Stiffen;
      FEMus[e] := Prm.Layers[l].Muscle; FEKap[e] := Prm.KappaRatio * Prm.Layers[l].Mu;
      FillChar(M, SizeOf(M), 0);
      for gj := 0 to 2 do
        for gi := 0 to 2 do
        begin
          g := gi + 3 * gj;
          xi := G3[gi]; eta := G3[gj];
          Quad1D(xi, Nr, dNr); Quad1D(eta, Nt, dNt);
          FillChar(J0, SizeOf(J0), 0);
          gx := 0; gy := 0;
          for b := 0 to 2 do
            for a := 0 to 2 do
            begin
              k := a + 3 * b;
              dNxi[k, 0] := dNr[a] * Nt[b];
              dNxi[k, 1] := Nr[a] * dNt[b];
              sx := X[2 * FConn[e][k]]; sy := X[2 * FConn[e][k] + 1];
              J0[0] := J0[0] + sx * dNxi[k, 0]; J0[1] := J0[1] + sx * dNxi[k, 1];
              J0[2] := J0[2] + sy * dNxi[k, 0]; J0[3] := J0[3] + sy * dNxi[k, 1];
              gx := gx + sx * Nr[a] * Nt[b]; gy := gy + sy * Nr[a] * Nt[b];
            end;
          det := J0[0] * J0[3] - J0[1] * J0[2];
          if det <= 0 then raise Exception.Create('TAirwayRing : inverted element in the mesh');
          Ji[0] := J0[3] / det; Ji[1] := -J0[1] / det;
          Ji[2] := -J0[2] / det; Ji[3] := J0[0] / det;
          w := det * W3[gi] * W3[gj];
          FGW[9 * e + g] := w;
          for k := 0 to 8 do
          begin
            { dN/dX = dN/dxi dxi/dX }
            FGdN[(9 * e + g) * 18 + 2 * k] := dNxi[k, 0] * Ji[0] + dNxi[k, 1] * Ji[2];
            FGdN[(9 * e + g) * 18 + 2 * k + 1] := dNxi[k, 0] * Ji[1] + dNxi[k, 1] * Ji[3];
          end;
          gr := Sqrt(gx * gx + gy * gy);
          FGFib[(9 * e + g) * 2] := -gy / gr;
          FGFib[(9 * e + g) * 2 + 1] := gx / gr;
          for c := 0 to 2 do
            for d := 0 to 2 do
              M[3 * c + d] := M[3 * c + d] + w * FPhi[g, c] * FPhi[g, d];
        end;
      det := M[0] * (M[4] * M[8] - M[5] * M[7]) - M[1] * (M[3] * M[8] - M[5] * M[6])
        + M[2] * (M[3] * M[7] - M[4] * M[6]);
      Mi[0] := (M[4] * M[8] - M[5] * M[7]) / det; Mi[1] := (M[2] * M[7] - M[1] * M[8]) / det;
      Mi[2] := (M[1] * M[5] - M[2] * M[4]) / det; Mi[3] := (M[5] * M[6] - M[3] * M[8]) / det;
      Mi[4] := (M[0] * M[8] - M[2] * M[6]) / det; Mi[5] := (M[2] * M[3] - M[0] * M[5]) / det;
      Mi[6] := (M[3] * M[7] - M[4] * M[6]) / det; Mi[7] := (M[1] * M[6] - M[0] * M[7]) / det;
      Mi[8] := (M[0] * M[4] - M[1] * M[3]) / det;
      for k := 0 to 8 do FEMinv[9 * e + k] := Mi[k];
    end;
  { edges: shape functions at the Gauss points, and the area form
    S[a,b] = 1/2 integral (Na Nb' - Na' Nb), so that the area swept from
    the origin by an edge is sum x[a] S[a,b] y[b] }
  FillChar(FS, SizeOf(FS), 0);
  for g := 0 to 2 do
  begin
    Quad1D(G3[g], Nr, dNr);
    for a := 0 to 2 do
    begin
      FEdgeN[g, a] := Nr[a];
      for b := 0 to 2 do
        FS[a, b] := FS[a, b] + 0.5 * W3[g] * (Nr[a] * dNr[b] - dNr[a] * Nr[b]);
    end;
  end;
  SetLength(FTW, 3 * Prm.NT);
  for et := 0 to Prm.NT - 1 do
    for g := 0 to 2 do
    begin
      Quad1D(G3[g], Nr, dNr);
      sx := 0; sy := 0;
      for a := 0 to 2 do
      begin
        k := (2 * et + a) * FNRn + FNRn - 1;
        sx := sx + dNr[a] * X[2 * k]; sy := sy + dNr[a] * X[2 * k + 1];
      end;
      FTW[3 * et + g] := W3[g] * Sqrt(sx * sx + sy * sy);
    end;
  for i := 0 to NDof - 1 do FUT[i] := 0;
  FPT := 0;
end;

procedure TAirwayRing.AddT(i, j: Integer; v: Double);
begin
  { the tangent is symmetric (everything here has an energy): the lower
    band is kept. CheckTangent compares it, mirrored, with differences
    of the residual. }
  if (j > i) or FFixed[i] or FFixed[j] then Exit;
  FKB[i * (FHB + 1) + j - i + FHB] := FKB[i * (FHB + 1) + j - i + FHB] + v;
end;

{ L D L' in place, no pivoting. Neg is the number of negative pivots,
  which by Sylvester's law is the number of negative eigenvalues. }
function TAirwayRing.Factor(out Neg: Integer): Boolean;
var
  i, j, k, j0, k0, w: Integer;
  s, d, uu, ll: Double;
begin
  Result := False;
  Neg := 0;
  w := FHB + 1;
  for i := 0 to NDof - 1 do
  begin
    j0 := Max(0, i - FHB);
    for j := j0 to i - 1 do
    begin
      s := FKB[i * w + j - i + FHB];
      k0 := Max(j0, j - FHB);
      for k := k0 to j - 1 do
        s := s - FKB[i * w + k - i + FHB] * FKB[j * w + k - j + FHB];
      FKB[i * w + j - i + FHB] := s;
    end;
    d := FKB[i * w + FHB];
    for j := j0 to i - 1 do
    begin
      uu := FKB[i * w + j - i + FHB];
      ll := uu / FKB[j * w + FHB];
      d := d - uu * ll;
      FKB[i * w + j - i + FHB] := ll;
    end;
    if IsNan(d) or (Abs(d) < 1e-300) then Exit;
    if d < 0 then Inc(Neg);
    FKB[i * w + FHB] := d;
  end;
  Result := True;
end;

procedure TAirwayRing.BandSolve(var V: array of Double);
var
  i, k, w: Integer;
  s: Double;
begin
  w := FHB + 1;
  for i := 0 to NDof - 1 do
  begin
    s := V[i];
    for k := Max(0, i - FHB) to i - 1 do s := s - FKB[i * w + k - i + FHB] * V[k];
    V[i] := s;
  end;
  for i := 0 to NDof - 1 do V[i] := V[i] / FKB[i * w + FHB];
  for i := NDof - 1 downto 0 do
  begin
    s := V[i];
    for k := i + 1 to Min(NDof - 1, i + FHB) do s := s - FKB[k * w + i - k + FHB] * V[k];
    V[i] := s;
  end;
end;

function TAirwayRing.Assemble(BuildK: Boolean): Boolean;
var
  e, g, a, b, c, d, i, k, jj, ll, p, q, et, n, base: Integer;
  ue, re: array[0..17] of Double;
  ke: array[0..17, 0..17] of Double;
  Gm: array[0..2, 0..17] of Double;
  F, Fi: array[0..8, 0..3] of Double;
  Jd: array[0..8] of Double;
  jv, th, pa: array[0..2] of Double;
  Pk, Ff, f0: array[0..3] of Double;
  AA: array[0..3, 0..3] of Double;
  dN: PDouble;
  w, mu, bq, mue, ph, lam, Tn, dTn, s, t2, wd, x1, y1, r, ftr, kk, dd, v, sum, tw, dq: Double;
  xe, ye: array[0..2] of Double;
  nd: array[0..2] of Integer;
begin
  Result := False;
  for i := 0 to NDof - 1 do begin FR[i] := 0; FdA[i] := 0; FAbs[i] := 0; end;
  FAs := 0; FMusSum := 0; FMusW := 0; FEnergy := 0;
  if BuildK then
  begin
    for i := 0 to High(FKB) do FKB[i] := 0;
    for i := 0 to NDof - 1 do
      if FFixed[i] then FKB[i * (FHB + 1) + FHB] := 1;
  end;
  wd := 1 - Prm.LMin;
  for e := 0 to NE - 1 do
  begin
    for a := 0 to 8 do
    begin
      ue[2 * a] := FUT[2 * FConn[e][a]];
      ue[2 * a + 1] := FUT[2 * FConn[e][a] + 1];
    end;
    jv[0] := 0; jv[1] := 0; jv[2] := 0;
    for g := 0 to 8 do
    begin
      dN := @FGdN[(9 * e + g) * 18];
      F[g, 0] := 1; F[g, 1] := 0; F[g, 2] := 0; F[g, 3] := 1;
      for a := 0 to 8 do
      begin
        F[g, 0] := F[g, 0] + ue[2 * a] * dN[2 * a];
        F[g, 1] := F[g, 1] + ue[2 * a] * dN[2 * a + 1];
        F[g, 2] := F[g, 2] + ue[2 * a + 1] * dN[2 * a];
        F[g, 3] := F[g, 3] + ue[2 * a + 1] * dN[2 * a + 1];
      end;
      Jd[g] := F[g, 0] * F[g, 3] - F[g, 1] * F[g, 2];
      if Jd[g] <= 1e-3 then Exit;
      Fi[g, 0] := F[g, 3] / Jd[g]; Fi[g, 1] := -F[g, 1] / Jd[g];
      Fi[g, 2] := -F[g, 2] / Jd[g]; Fi[g, 3] := F[g, 0] / Jd[g];
      w := FGW[9 * e + g];
      for c := 0 to 2 do jv[c] := jv[c] + w * FPhi[g, c] * Jd[g];
    end;
    for c := 0 to 2 do
    begin
      th[c] := 0;
      for d := 0 to 2 do th[c] := th[c] + FEMinv[9 * e + 3 * c + d] * jv[d];
    end;
    th[0] := th[0] - 1;
    for c := 0 to 2 do pa[c] := FEKap[e] * th[c];
    { Kappa/2 (theta - 1) M (theta - 1) = Kappa/2 (theta - 1).(j - m1) }
    FEnergy := FEnergy + 0.5 * FEKap[e] * (th[0] * jv[0] + th[1] * jv[1] + th[2] * jv[2]);
    for g := 0 to 8 do
      FEnergy := FEnergy - 0.5 * FEKap[e] * FGW[9 * e + g]
        * (th[0] + th[1] * FPhi[g, 1] + th[2] * FPhi[g, 2]);
    for i := 0 to 17 do re[i] := 0;
    FillChar(Gm, SizeOf(Gm), 0);
    if BuildK then FillChar(ke, SizeOf(ke), 0);
    mu := FEMu[e];
    for g := 0 to 8 do
    begin
      dN := @FGdN[(9 * e + g) * 18];
      w := FGW[9 * e + g];
      ph := pa[0] + pa[1] * FPhi[g, 1] + pa[2] * FPhi[g, 2];
      dq := F[g, 0] * F[g, 0] + F[g, 1] * F[g, 1] + F[g, 2] * F[g, 2] + F[g, 3] * F[g, 3] - 2;
      bq := FEB[e] * dq;
      mue := mu * Exp(bq);
      if FEB[e] > 0 then
        FEnergy := FEnergy + w * (mu / (2 * FEB[e]) * (Exp(bq) - 1) - mu * Ln(Jd[g]))
      else
        FEnergy := FEnergy + w * (0.5 * mu * dq - mu * Ln(Jd[g]));
      { first Piola-Kirchhoff stress, Pk[i*2+J]; F^-T[i,J] = Fi[J*2+i] }
      for i := 0 to 1 do
        for jj := 0 to 1 do
          Pk[i * 2 + jj] := mue * F[g, i * 2 + jj] + (ph * Jd[g] - mu) * Fi[g, jj * 2 + i];
      s := 0; t2 := 0;
      if (FEMus[e] > 0) and (Prm.Act > 0) then
      begin
        f0[0] := FGFib[(9 * e + g) * 2]; f0[1] := FGFib[(9 * e + g) * 2 + 1];
        Ff[0] := F[g, 0] * f0[0] + F[g, 1] * f0[1];
        Ff[1] := F[g, 2] * f0[0] + F[g, 3] * f0[1];
        lam := Sqrt(Ff[0] * Ff[0] + Ff[1] * Ff[1]);
        FMusSum := FMusSum + w * lam; FMusW := FMusW + w;
        if Abs(lam - 1) < wd then
        begin
          Tn := Prm.T0 * (1 - Sqr((lam - 1) / wd));
          dTn := -2 * Prm.T0 * (lam - 1) / (wd * wd);
          FEnergy := FEnergy + w * FEMus[e] * Prm.Act * Prm.T0
            * ((lam - 1) - (lam - 1) * Sqr(lam - 1) / (3 * wd * wd) + 2 * wd / 3);
        end
        else
        begin
          Tn := 0; dTn := 0;
          if lam > 1 then
            FEnergy := FEnergy + w * FEMus[e] * Prm.Act * Prm.T0 * 4 * wd / 3;
        end;
        s := FEMus[e] * Prm.Act * Tn / lam;
        t2 := FEMus[e] * Prm.Act * (dTn / lam - Tn / (lam * lam)) / lam;
        for i := 0 to 1 do
          for jj := 0 to 1 do
            Pk[i * 2 + jj] := Pk[i * 2 + jj] + s * Ff[i] * f0[jj];
      end
      else if FEMus[e] > 0 then
      begin
        f0[0] := FGFib[(9 * e + g) * 2]; f0[1] := FGFib[(9 * e + g) * 2 + 1];
        Ff[0] := F[g, 0] * f0[0] + F[g, 1] * f0[1];
        Ff[1] := F[g, 2] * f0[0] + F[g, 3] * f0[1];
        FMusSum := FMusSum + w * Sqrt(Ff[0] * Ff[0] + Ff[1] * Ff[1]); FMusW := FMusW + w;
      end;
      for a := 0 to 8 do
        for i := 0 to 1 do
        begin
          re[2 * a + i] := re[2 * a + i] + w * (Pk[i * 2] * dN[2 * a] + Pk[i * 2 + 1] * dN[2 * a + 1]);
          for c := 0 to 2 do
            Gm[c, 2 * a + i] := Gm[c, 2 * a + i] + w * FPhi[g, c] * Jd[g]
              * (Fi[g, i] * dN[2 * a] + Fi[g, 2 + i] * dN[2 * a + 1]);
        end;
      if BuildK then
      begin
        for i := 0 to 1 do
          for jj := 0 to 1 do
            for k := 0 to 1 do
              for ll := 0 to 1 do
              begin
                v := mue * 2 * FEB[e] * F[g, i * 2 + jj] * F[g, k * 2 + ll]
                  + mu * Fi[g, jj * 2 + k] * Fi[g, ll * 2 + i]
                  + ph * Jd[g] * (Fi[g, jj * 2 + i] * Fi[g, ll * 2 + k] - Fi[g, jj * 2 + k] * Fi[g, ll * 2 + i]);
                if (i = k) and (jj = ll) then v := v + mue;
                if s <> 0 then
                begin
                  if i = k then v := v + s * f0[jj] * f0[ll];
                  v := v + t2 * Ff[i] * f0[jj] * Ff[k] * f0[ll];
                end;
                AA[i * 2 + jj, k * 2 + ll] := v;
              end;
        for a := 0 to 8 do
          for i := 0 to 1 do
            for b := 0 to 8 do
              for k := 0 to 1 do
              begin
                sum := 0;
                for jj := 0 to 1 do
                  for ll := 0 to 1 do
                    sum := sum + dN[2 * a + jj] * AA[i * 2 + jj, k * 2 + ll] * dN[2 * b + ll];
                ke[2 * a + i, 2 * b + k] := ke[2 * a + i, 2 * b + k] + w * sum;
              end;
      end;
    end;
    for a := 0 to 8 do
      for i := 0 to 1 do
      begin
        n := 2 * FConn[e][a] + i;
        FR[n] := FR[n] + re[2 * a + i];
        FAbs[n] := FAbs[n] + Abs(re[2 * a + i]);
      end;
    if BuildK then
      for p := 0 to 17 do
        for q := 0 to 17 do
        begin
          v := ke[p, q];
          for c := 0 to 2 do
            for d := 0 to 2 do
              v := v + FEKap[e] * Gm[c, p] * FEMinv[9 * e + 3 * c + d] * Gm[d, q];
          AddT(2 * FConn[e][p div 2] + p mod 2, 2 * FConn[e][q div 2] + q mod 2, v);
        end;
  end;
  { lumen: sector area, its gradient, and the pressure's stiffness }
  for et := 0 to Prm.NT - 1 do
  begin
    for a := 0 to 2 do
    begin
      nd[a] := InnerNode(2 * et + a);
      xe[a] := X[2 * nd[a]] + FUT[2 * nd[a]];
      ye[a] := X[2 * nd[a] + 1] + FUT[2 * nd[a] + 1];
    end;
    for a := 0 to 2 do
      for b := 0 to 2 do
      begin
        FAs := FAs + xe[a] * FS[a, b] * ye[b];
        FdA[2 * nd[a]] := FdA[2 * nd[a]] + FS[a, b] * ye[b];
        FdA[2 * nd[b] + 1] := FdA[2 * nd[b] + 1] + xe[a] * FS[a, b];
        if BuildK and (FPT <> 0) then
        begin
          AddT(2 * nd[a], 2 * nd[b] + 1, -FPT * FS[a, b]);
          AddT(2 * nd[b] + 1, 2 * nd[a], -FPT * FS[a, b]);
        end;
      end;
  end;
  { tethering on the outer surface }
  if Prm.TetherK > 0 then
    for et := 0 to Prm.NT - 1 do
    begin
      for a := 0 to 2 do
      begin
        nd[a] := (2 * et + a) * FNRn + FNRn - 1;
        xe[a] := X[2 * nd[a]] + FUT[2 * nd[a]];
        ye[a] := X[2 * nd[a] + 1] + FUT[2 * nd[a] + 1];
      end;
      for g := 0 to 2 do
      begin
        x1 := 0; y1 := 0;
        for a := 0 to 2 do
        begin
          x1 := x1 + FEdgeN[g, a] * xe[a]; y1 := y1 + FEdgeN[g, a] * ye[a];
        end;
        r := Sqrt(x1 * x1 + y1 * y1);
        tw := FTW[3 * et + g];
        ftr := Prm.TetherK * (r - Prm.TetherR);
        FEnergy := FEnergy + 0.5 * tw * Prm.TetherK * Sqr(r - Prm.TetherR);
        x1 := x1 / r; y1 := y1 / r;
        for a := 0 to 2 do
        begin
          v := tw * FEdgeN[g, a] * ftr;
          FR[2 * nd[a]] := FR[2 * nd[a]] + v * x1;
          FR[2 * nd[a] + 1] := FR[2 * nd[a] + 1] + v * y1;
          FAbs[2 * nd[a]] := FAbs[2 * nd[a]] + Abs(v * x1);
          FAbs[2 * nd[a] + 1] := FAbs[2 * nd[a] + 1] + Abs(v * y1);
          if BuildK then
            for b := 0 to 2 do
            begin
              kk := tw * FEdgeN[g, a] * FEdgeN[g, b];
              AddT(2 * nd[a], 2 * nd[b], kk * (Prm.TetherK * x1 * x1 + ftr / r * (1 - x1 * x1)));
              AddT(2 * nd[a], 2 * nd[b] + 1, kk * (Prm.TetherK - ftr / r) * x1 * y1);
              AddT(2 * nd[a] + 1, 2 * nd[b], kk * (Prm.TetherK - ftr / r) * x1 * y1);
              AddT(2 * nd[a] + 1, 2 * nd[b] + 1, kk * (Prm.TetherK * y1 * y1 + ftr / r * (1 - y1 * y1)));
            end;
        end;
      end;
    end;
  { far symmetry line: no displacement across it }
  base := (FNTn - 1) * FNRn;
  for i := 0 to FNRn - 1 do
  begin
    n := 2 * (base + i);
    dd := FNx * FUT[n] + FNy * FUT[n + 1];
    FEnergy := FEnergy + 0.5 * FPen * dd * dd;
    FR[n] := FR[n] + FPen * dd * FNx;
    FR[n + 1] := FR[n + 1] + FPen * dd * FNy;
    if BuildK then
    begin
      AddT(n, n, FPen * FNx * FNx); AddT(n, n + 1, FPen * FNx * FNy);
      AddT(n + 1, n, FPen * FNx * FNy); AddT(n + 1, n + 1, FPen * FNy * FNy);
    end;
  end;
  { contact of the inner surface with its mirror images }
  if Prm.ContactK > 0 then
    for i := 0 to FNTn - 1 do
    begin
      n := 2 * InnerNode(i);
      if i > 0 then
      begin
        y1 := X[n + 1] + FUT[n + 1];
        if y1 < 0 then
        begin
          FEnergy := FEnergy + 0.5 * Prm.ContactK * y1 * y1;
          FR[n + 1] := FR[n + 1] + Prm.ContactK * y1;
          if BuildK then AddT(n + 1, n + 1, Prm.ContactK);
        end;
      end;
      if i < FNTn - 1 then
      begin
        dd := FNx * (X[n] + FUT[n]) + FNy * (X[n + 1] + FUT[n + 1]);
        if dd > 0 then
        begin
          FEnergy := FEnergy + 0.5 * Prm.ContactK * dd * dd;
          FR[n] := FR[n] + Prm.ContactK * dd * FNx;
          FR[n + 1] := FR[n + 1] + Prm.ContactK * dd * FNy;
          if BuildK then
          begin
            AddT(n, n, Prm.ContactK * FNx * FNx); AddT(n, n + 1, Prm.ContactK * FNx * FNy);
            AddT(n + 1, n, Prm.ContactK * FNx * FNy); AddT(n + 1, n + 1, Prm.ContactK * FNy * FNy);
          end;
        end;
      end;
    end;
  for i := 0 to NDof - 1 do
    if FFixed[i] then begin FR[i] := 0; FdA[i] := 0; end;
  Result := True;
end;

function TAirwayRing.Solve(Mode: TRingMode; Target: Double): Boolean;
var
  it, i, neg: Integer;
  rmax, fmax, cerr, ats, dmax, sc, a0s, ax1, ax2, dp: Double;
  conv: Boolean;
begin
  Result := False;
  LastFail := 'no convergence';
  for i := 0 to NDof - 1 do FUT[i] := U[i];
  FPT := Ptm;
  ats := 0;
  if Mode = rmPressure then FPT := Target
  else ats := Target / (2 * Prm.Lobes);
  a0s := Pi * Sqr(Prm.Ri) / (2 * Prm.Lobes);
  for it := 1 to 20 do
  begin
    if not Assemble(True) then begin LastFail := 'inverted element'; Exit; end;
    rmax := 0; fmax := 1e-10 * FMuMax * Prm.Ri;
    for i := 0 to NDof - 1 do
      if not FFixed[i] then
      begin
        FR[i] := FR[i] - FPT * FdA[i];
        rmax := Max(rmax, Abs(FR[i]));
        fmax := Max(fmax, FAbs[i] + Abs(FPT * FdA[i]));
      end;
    cerr := 0;
    if Mode = rmArea then cerr := FAs - ats;
    conv := (rmax <= Tolerance * fmax) and (Abs(cerr) <= 1e-11 * a0s);
    if not Factor(neg) then begin LastFail := 'singular'; Exit; end;
    { [K, -a; -a', 0] [du; dp] = [-R; A - At], K = Kint - p H, by
      elimination: du = x1 + dp x2, K x1 = -R, K x2 = a }
    ax1 := 0; ax2 := 0; dp := 0;
    for i := 0 to NDof - 1 do FX1[i] := -FR[i];
    BandSolve(FX1);
    if Mode = rmArea then
    begin
      for i := 0 to NDof - 1 do FX2[i] := FdA[i];
      BandSolve(FX2);
      for i := 0 to NDof - 1 do
      begin
        ax1 := ax1 + FdA[i] * FX1[i]; ax2 := ax2 + FdA[i] * FX2[i];
      end;
      if ax2 = 0 then Exit;
      dp := -(cerr + ax1) / ax2;
      { the bordered matrix's last pivot is -a'x2: stable on the
        constraint if it has exactly one negative eigenvalue in all }
      if ax2 > 0 then Inc(neg);
    end;
    if conv then
    begin
      { an equilibrium, but a stable one? Past buckling the unfolded
        state is still a solution, and a long step can land on it. }
      Stable := neg = Ord(Mode = rmArea);
      if not Stable then begin LastFail := 'unstable equilibrium'; Exit; end;
      LastFail := '';
      for i := 0 to NDof - 1 do U[i] := FUT[i];
      Ptm := FPT;
      Iterations := it - 1;
      Exit(True);
    end;
    dmax := 0;
    for i := 0 to NDof - 1 do
    begin
      FX1[i] := FX1[i] + dp * FX2[i];
      dmax := Max(dmax, Abs(FX1[i]));
    end;
    if IsNan(dmax) then Exit;
    { no more than a fifth of a fold's width at once }
    sc := 1;
    if dmax > 0.2 * Prm.Ri * Pi / Prm.Lobes then sc := 0.2 * Prm.Ri * Pi / Prm.Lobes / dmax;
    for i := 0 to NDof - 1 do FUT[i] := FUT[i] + sc * FX1[i];
    FPT := FPT + sc * dp;
  end;
end;

function TAirwayRing.MoveTo(Mode: TRingMode; Target: Double): Boolean;
var
  cur, span, step, next: Double;
  n: Integer;
begin
  if Mode = rmArea then cur := LumenArea else cur := Ptm;
  span := Target - cur;
  if span = 0 then Exit(Solve(Mode, Target));
  { the whole way if it will go; half as far after a failure, twice as
    far after a success. Near a bifurcation the steps must be small for
    Newton to stay on the stable branch, and can grow again beyond it. }
  step := span;
  for n := 1 to 3000 do
  begin
    if Abs(Target - cur) <= Abs(step) then next := Target else next := cur + step;
    if Solve(Mode, next) then
    begin
      if next = Target then Exit(True);
      cur := next; step := 2 * step;
    end
    else
    begin
      step := 0.5 * step;
      if Abs(step) < 1e-6 * Abs(span) then Exit(False);
    end;
  end;
  Result := False;
end;

function TAirwayRing.RampAct(Target: Double; Steps: Integer): Boolean;
var
  A, step, old, first: Double;
begin
  A := LumenArea;
  first := Target - Prm.Act;
  if first = 0 then Exit(Solve(rmArea, A));
  step := first / Steps;
  while Abs(Target - Prm.Act) > 1e-12 do
  begin
    old := Prm.Act;
    if Abs(Target - old) <= Abs(step) then Prm.Act := Target else Prm.Act := old + step;
    if not Solve(rmArea, A) then
    begin
      Prm.Act := old;
      step := 0.5 * step;
      if Abs(step) < 1e-4 * Abs(first) then Exit(False);
    end;
  end;
  Result := True;
end;

function TAirwayRing.LumenArea: Double;
var
  et, a, b, n1, n2: Integer;
begin
  Result := 0;
  for et := 0 to Prm.NT - 1 do
    for a := 0 to 2 do
      for b := 0 to 2 do
      begin
        n1 := InnerNode(2 * et + a); n2 := InnerNode(2 * et + b);
        Result := Result + (X[2 * n1] + U[2 * n1]) * FS[a, b] * (X[2 * n2 + 1] + U[2 * n2 + 1]);
      end;
  Result := Result * 2 * Prm.Lobes;
end;

function TAirwayRing.StrainEnergy: Double;
var
  i: Integer;
begin
  for i := 0 to NDof - 1 do FUT[i] := U[i];
  FPT := Ptm;
  if not Assemble(False) then Exit(NaN);
  Result := FEnergy * 2 * Prm.Lobes;
end;

function TAirwayRing.MuscleStretch: Double;
begin
  if FMusW > 0 then Result := FMusSum / FMusW else Result := 1;
end;

function TAirwayRing.OuterRadius: Double;
var
  j, n: Integer;
begin
  Result := 0;
  for j := 0 to FNTn - 1 do
  begin
    n := j * FNRn + FNRn - 1;
    Result := Result + Sqrt(Sqr(X[2 * n] + U[2 * n]) + Sqr(X[2 * n + 1] + U[2 * n + 1]));
  end;
  Result := Result / FNTn;
end;

procedure TAirwayRing.InnerPos(j: Integer; out px, py: Double);
var
  n: Integer;
begin
  n := InnerNode(j);
  px := X[2 * n] + U[2 * n]; py := X[2 * n + 1] + U[2 * n + 1];
end;

procedure TAirwayRing.SaveState;
var
  i: Integer;
begin
  for i := 0 to NDof - 1 do FSaveU[i] := U[i];
  FSaveP := Ptm; FSaveAct := Prm.Act;
end;

procedure TAirwayRing.RestoreState;
var
  i: Integer;
begin
  for i := 0 to NDof - 1 do U[i] := FSaveU[i];
  Ptm := FSaveP; Prm.Act := FSaveAct;
end;

procedure TAirwayRing.SetTrial(const AU: array of Double; AP: Double);
var
  i: Integer;
begin
  for i := 0 to NDof - 1 do
    if FFixed[i] then FUT[i] := 0 else FUT[i] := AU[i];
  FPT := AP;
  if not Assemble(False) then raise Exception.Create('TAirwayRing.SetTrial : inverted element');
end;

function TAirwayRing.TrialEnergy: Double;
begin
  Result := FEnergy - FPT * FAs;
end;

function TAirwayRing.TrialResidual(n: Integer): Double;
begin
  Result := FR[n] - FPT * FdA[n];
end;

function TAirwayRing.IsFixed(n: Integer): Boolean;
begin
  Result := FFixed[n];
end;

procedure TAirwayRing.CheckTangent(out MaxErr, MaxK: Double);
var
  K, rp, rm, u0: array of Double;
  i, j, t: Integer;
  fd: Double;
const
  h = 1e-7;
begin
  SetLength(K, NDof * NDof); SetLength(rp, NDof); SetLength(rm, NDof); SetLength(u0, NDof);
  for i := 0 to NDof - 1 do u0[i] := FUT[i];
  if not Assemble(True) then raise Exception.Create('CheckTangent : inverted element');
  for i := 0 to NDof - 1 do
    for t := Max(0, i - FHB) to i do
    begin
      K[i * NDof + t] := FKB[i * (FHB + 1) + t - i + FHB];
      K[t * NDof + i] := K[i * NDof + t];
    end;
  MaxErr := 0; MaxK := 0;
  for j := 0 to NDof - 1 do
  begin
    if FFixed[j] then Continue;
    FUT[j] := u0[j] + h; Assemble(False);
    for i := 0 to NDof - 1 do rp[i] := FR[i] - FPT * FdA[i];
    FUT[j] := u0[j] - h; Assemble(False);
    for i := 0 to NDof - 1 do rm[i] := FR[i] - FPT * FdA[i];
    FUT[j] := u0[j];
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

{ ---------------------------------------------------------------- }

function BuildTubeLaw(const P: TRingParams; PLo, PHi: Double; out Notes: string): TTubeLaw;
var
  R: TAirwayRing;
  Q: TRingParams;
  tp, ta: array of Double;
  n, k: Integer;
  A0, A: Double;

  procedure Rec;
  begin
    if n = Length(tp) then begin SetLength(tp, n + 64); SetLength(ta, n + 64); end;
    tp[n] := R.Ptm; ta[n] := R.LumenArea; Inc(n);
  end;

begin
  Notes := '';
  Q := P; Q.Act := 0;
  R := TAirwayRing.Create(Q);
  try
    n := 0;
    A0 := R.LumenArea;
    if not R.MoveTo(rmArea, A0) then raise Exception.Create('BuildTubeLaw : no start');
    if (P.Act > 0) and not R.RampAct(P.Act, 10) then
      raise Exception.Create('BuildTubeLaw : activation failed');
    Rec;
    R.SaveState;
    A := A0; k := 0;
    while (R.Ptm < PHi) and (k < 200) do
    begin
      A := A * 1.04;
      if not R.MoveTo(rmArea, A) then
      begin
        Notes := Notes + Format('stopped rising at %.3g of the unloaded area; ', [A / A0]);
        Break;
      end;
      Rec; Inc(k);
    end;
    R.RestoreState;
    A := A0; k := 0;
    while (R.Ptm > PLo) and (A > 0.03 * A0) and (k < 200) do
    begin
      A := A * 0.95;
      if not R.MoveTo(rmArea, A) then
      begin
        Notes := Notes + Format('stopped falling at %.3g of the unloaded area; ', [A / A0]);
        Break;
      end;
      Rec; Inc(k);
    end;
  finally
    R.Free;
  end;
  SetLength(tp, n); SetLength(ta, n);
  Result := TTubeLaw.Create;
  Result.SetTable(tp, ta);
  if not Result.Monotone then Notes := Notes + 'pressure not monotone in area: points dropped; ';
end;

function BestLobes(const P: TRingParams; AFrac: Double; NMin, NMax: Integer): Integer;
var
  R: TAirwayRing;
  Q: TRingParams;
  nl: Integer;
  e, best, A0: Double;
begin
  Result := NMin; best := Infinity;
  for nl := NMin to NMax do
  begin
    Q := P; Q.Lobes := nl; Q.Act := 0; Q.NT := 0;
    R := TAirwayRing.Create(Q);
    try
      A0 := R.LumenArea;
      if R.MoveTo(rmArea, A0) and ((P.Act = 0) or R.RampAct(P.Act, 10))
        and R.MoveTo(rmArea, 0.5 * (1 + AFrac) * A0) and R.MoveTo(rmArea, AFrac * A0) then
      begin
        e := R.StrainEnergy;
        if e < best then begin best := e; Result := nl; end;
      end;
    finally
      R.Free;
    end;
  end;
end;

end.
