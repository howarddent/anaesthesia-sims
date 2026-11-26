unit uLungModel;

{ The whole lung and chest wall, summing the single units: a symmetric
  tree of generations 0 to 16 (Weibel's model A, as Lambert et al. 1982
  used), each generation's airways sharing one tube law from the
  finite-element wall (uAirwayRing) with a liquid lining, the acini
  beyond them sharing one pressure-volume curve from the finite-element
  alveolus (uAlveolus), a chest wall and the respiratory muscles.
  Units inside: mm, kPa, s (volumes mm3, flows mm3/s); litres and cmH2O
  only at the interface.

  GEOMETRY   generation g has 2^g airways. Their lumen at full
  dilation is Lambert's (as tabulated by Florens et al., arXiv
  2011.09740, table 1, from Lambert et al. 1982), which is Weibel's
  model A to within a few per cent: taken as the normal wall's lumen at
  a transmural pressure of 40 cmH2O. The lengths are Weibel's, held
  constant. Lambert's own airways at FRC are far narrower (0.15 to 0.3
  of full dilation from generation 8 on), because his small airways are
  more distensible than any wall of real-tissue strains here can be
  (see WallM): pinning ours at his FRC size instead made every flow too
  small (PEF 6 L/s, FEV1/FVC 58 %).

  TUBE LAWS   the wall's law is scale-free: thicknesses go with the
  lumen radius, moduli and tethering do not depend on it. So one law
  serves every generation with the same wall, and generation g's lumen is
     A_g(Ptm) = A_max,g  Law(Ptm) / LawNormal(40 cmH2O)
  where LawNormal is the normal wall of the same type: asthma's
  thickening adds wall outwards, keeping the unloaded lumen. Three wall
  types, differing in the modulus scale WallM: the cartilaginous
  generations 0-1 and 2 are fitted (FitWallM) to Lambert's area ratio
  between FRC and full dilation, the rest are the membranous wall of
  stage 1 (see WallM). The tethering is that at a transpulmonary
  pressure of 5 cmH2O at every lung volume. The lining (uTubeLaw) is a
  film of Film mm, Mucus times that in asthma, on the lumen at FRC: its
  liquid area is fixed, and below the transmural pressure where it
  closes (PClose) the airway passes no gas.

  FLOW   quasi-steady, each generation by uBronchiole's equation
     dP/dx = -f / (1 - S^2),  f = 8 pi Visc q (Ka + Kb Re) / A^2,
  S^2 = Rho q^2 (dA/dPtm) / A^3, q the flow of one airway, with the
  outside pressure the pleural one. At each junction the gas speeds up
  or slows down; speeding up costs 1/2 Rho (u1^2 - u0^2), slowing down
  recovers nothing (a jet). Above generation 0 an upper airway, Rohrer
  K1 Q + K2 Q^2. Expiration marches from the alveoli to the mouth (at
  0), inspiration from the mouth to the alveoli. Flow is found for the
  alveolar pressure; if the march chokes (S = 1, or a lumen closed)
  before the end, the largest flow that gets through is the answer:
  flow limitation, and ChokeGen says where.

  LUNG AND CHEST WALL   one gas volume V (litres, dead space included).
     Palv = Ppl + Pel(V)
     Ppl  = Pcw(V) - Pmus(t)
  Pel is the alveolus's deflation limb, scaled to the lung's alveoli;
  Pcw a chest wall relaxation curve, linear in its middle and stiffening
  at both ends; Pmus the muscles, positive inspiring. dV/dt = -Q, Heun's
  method. The gas is incompressible. }

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Math, uTubeLaw, uAirwayRing, uAlveolus;

const
  NGen = 17;
  LitreMM3 = 1e6;
  { Lambert's radii (mm) at FRC and at full dilation, generations 0-16 }
  LambertRFRC: array[0..NGen - 1] of Double = (8.18, 5.79, 3.98, 2.85, 2.11, 1.50,
    1.10, 0.810, 0.612, 0.462, 0.347, 0.267, 0.213, 0.177, 0.150, 0.131, 0.115);
  LambertRMax: array[0..NGen - 1] of Double = (8.69, 6.14, 4.72, 3.73, 2.99, 2.30,
    1.80, 1.41, 1.13, 0.889, 0.704, 0.567, 0.473, 0.416, 0.367, 0.331, 0.296);
  { Weibel's model A lengths, mm }
  WeibelLen: array[0..NGen - 1] of Double = (120, 47.6, 19.0, 7.6, 12.7, 10.7, 9.0,
    7.6, 6.4, 5.4, 4.6, 3.9, 3.3, 2.7, 2.3, 2.0, 1.65);
  NWall = 3;
  { wall type of each generation }
  GenWall: array[0..NGen - 1] of Integer = (0, 0, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2);
  { modulus scale of each wall type: 0 and 1 from FitWallM (lungrun
    --fitwall) against Lambert's mean ratio for generations 0-1 (0.888)
    and generation 2's (0.711); 2 is stage 1's membranous wall, whose
    ratio (0.62) is above Lambert's for generations 3-16 (0.58 falling to
    0.15), which no wall of real-tissue strains reaches }
  WallM: array[0..NWall - 1] of Double = (13.94, 3.886, 1);

type
  TAsthma = record
    Act: Double;    { smooth muscle activation, 0..1 }
    Thick: Double;  { wall thickening factor (muscle by its square) }
    Mucus: Double;  { lining liquid, times normal }
  end;

  TLungParams = record
    TLC, VDead: Double;            { L }
    PTLC: Double;                  { recoil at TLC, cmH2O }
    PSalineTLC: Double;            { saline-filled recoil at TLC, cmH2O }
    CwRelax, CwComp: Double;       { L, L/cmH2O }
    CwLo, CwHi, CwB, CwW: Double;  { L, L, cmH2O, L }
    K1, K2: Double;                { cmH2O/(L/s), cmH2O/(L/s)^2 }
    Film, Gamma: Double;           { mm, kPa mm }
    Steps: Integer;                { integration steps per generation }
    Ka, Kb: Double;
    Rho, Visc: Double;
  end;

  TMuscleFn = function(t, V: Double): Double of object;  { Pmus, cmH2O }

  TGeneration = record
    N, Len, AF: Double;
    Gas: TTubeLaw;      { gas area against transmural pressure, owned }
    PClose: Double;     { kPa; -Infinity if it never closes, +Infinity if always }
  end;

  TLung = class
  private
    FVTab, FPTab: array of Double;  { lung volume (L), recoil (kPa) }
    FGrad: Double;
    FChoke: Boolean;
    FQ: Double;
    function Grad(g: Integer; P, q, Ppl: Double): Double;
    function March(g: Integer; P, q, Ppl: Double; out Choked: Boolean): Double;
    function Junction(gFrom, gTo: Integer; P, Q, Ppl: Double; out Choked: Boolean): Double;
    function Residual(q, Palv, Ppl: Double; out Choked: Boolean): Double;
    procedure BuildAirways(const P: TLungParams; const WallLaw, RefLaw: array of TTubeLaw; Mucus: Double);
  public
    Prm: TLungParams;
    Gens: array[0..NGen - 1] of TGeneration;
    ChokeGen: Integer;     { where the last choked march stopped; -1 none }
    Limited: Boolean;      { the last Flow was at its limit }
    { WallLaw[g] is the tube law of generation g's wall, RefLaw[g] that
      of the normal wall of the same type (lumen areas in any unit: only
      ratios are used). AlvP holds the fitted alveolus. }
    constructor Create(const P: TLungParams; const WallLaw, RefLaw: array of TTubeLaw;
      Mucus: Double; const Alv: TAlveolusParams);
    { the airways alone: no recoil, so Pel and StaticVolume are unusable }
    constructor CreateAirways(const P: TLungParams; const WallLaw, RefLaw: array of TTubeLaw;
      Mucus: Double);
    destructor Destroy; override;
    { Expiratory march, flow Q (mm3/s, as if every airway of each
      generation carried Q / 2^g) from pressure P at the deep end of
      generation GDeep up to the top of GTop; JunctionIn first takes the
      junction from GDeep + 1 into GDeep; the upper airway is added when
      GTop = 0. Choked, and ChokeGen, if the march can't carry Q. }
    function MarchUp(Q, P, Ppl: Double; GDeep, GTop: Integer; JunctionIn: Boolean;
      out Choked: Boolean): Double;
    { Inspiratory march, flow Q > 0 into the lung, from pressure P at the
      top of GTop (above the upper airway when GTop = 0) down to the deep
      end of GDeep; JunctionOut ends with the junction into GDeep + 1. }
    function MarchDown(Q, P, Ppl: Double; GTop, GDeep: Integer; JunctionOut: Boolean;
      out Choked: Boolean): Double;
    function Pel(V: Double): Double;      { kPa, V in L }
    function Pcw(V: Double): Double;      { kPa }
    function StaticVolume(PNet: Double): Double;  { V where Pel + Pcw = PNet (kPa) }
    { expiratory march: mouth pressure for an expiratory flow Q (mm3/s) }
    function MouthPressure(Q, Palv, Ppl: Double; out Choked: Boolean): Double;
    { inspiratory march: pressure at the alveolar end for an inspiratory flow }
    function AlveolarEnd(Q, Ppl: Double; out Choked: Boolean): Double;
    { Flow out of the mouth (mm3/s, negative inspiring) for alveolar and
      pleural pressures (kPa). Guess speeds it up. }
    function Flow(Palv, Ppl, Guess: Double): Double;
    function Resistance(Ppl: Double): Double;  { airway resistance at a tiny flow, kPa s/mm3 }
  end;

  { The lung in time: Heun's method on V, each state's flow found with
    the last as the guess. State is the instant T, with Ppl, Palv, Pmus,
    Q and the flow limitation consistent with V. }
  TLungSim = class
  public
    Lung: TLung;      { not owned }
    Musc: TMuscleFn;
    Dt, T, V: Double;           { s, s, L }
    Q, Ppl, Palv, Pmus: Double; { mm3/s, kPa, kPa, cmH2O }
    Limited: Boolean;
    ChokeGen: Integer;
    constructor Create(ALung: TLung; AMusc: TMuscleFn; V0, ADt: Double);
    procedure Evaluate;
    procedure Step;
  end;

function DefaultLungParams: TLungParams;
function NormalAsthma: TAsthma;
{ The ring of wall type w, normal or with asthma A, with the lumen radius 1 }
function WallRing(w: Integer; const A: TAsthma): TRingParams;
{ the wall's area ratio between transmural pressures of 5 and 40 cmH2O,
  and the modulus scale giving a target ratio }
function WallRatio(const P: TRingParams): Double;
function FitWallM(Target: Double): Double;
{ Builds the NWall tube laws for A in parallel threads. }
procedure BuildWallLaws(const A: TAsthma; var Laws: array of TTubeLaw; out Notes: string);
{ Builds the tube law of every ring, at most MaxThreads at once. Each is
  first looked for in LawCacheDir, keyed on every ring parameter, and
  saved there once built. }
procedure BuildLaws(const Rings: array of TRingParams; var Laws: array of TTubeLaw;
  out Notes: string; MaxThreads: Integer = 16);

var
  { where BuildLaws keeps tube laws between runs; '' for none }
  LawCacheDir: string = 'cache';

const
  JPerCmH2OL = 0.0980665;   { J per cmH2O L }

implementation

function DefaultLungParams: TLungParams;
begin
  FillChar(Result, SizeOf(Result), 0);
  { a 70 kg man; all assumed round values }
  Result.TLC := 6.5; Result.VDead := 0.15;
  Result.PTLC := 30; Result.PSalineTLC := 10;
  { chest wall relaxed at 63 % TLC, 0.2 L/cmH2O in its middle (Agostoni
    & Hyatt), stiffening sharply below 1.7 L (so that maximal expiratory
    effort leaves a residual volume near 1.6 L) and above 7 L }
  Result.CwRelax := 4.1; Result.CwComp := 0.2;
  Result.CwLo := 1.7; Result.CwHi := 7.0; Result.CwB := 5; Result.CwW := 0.12;
  Result.K1 := 0.3; Result.K2 := 0.05;
  Result.Film := 0.005; Result.Gamma := 0.025;
  Result.Steps := 8;
  Result.Ka := 1.5; Result.Kb := 0.0035;
  Result.Rho := 1.14e-9; Result.Visc := 1.85e-8;
end;

function NormalAsthma: TAsthma;
begin
  Result.Act := 0; Result.Thick := 1; Result.Mucus := 1;
end;

function WallRing(w: Integer; const A: TAsthma): TRingParams;
var
  l: Integer;
  wn: Double;
begin
  Result := NormalBronchiole(1);
  wn := WallThickness(Result);
  for l := 0 to Result.NLayers - 1 do
    Result.Layers[l].Mu := Result.Layers[l].Mu * WallM[w];
  if (A.Thick <> 1) or (A.Act <> 0) then
  begin
    Result := AsthmaBronchiole(1, A.Thick, A.Act);
    for l := 0 to Result.NLayers - 1 do
      Result.Layers[l].Mu := Result.Layers[l].Mu * WallM[w];
  end;
  { stage 1's least-energy fold numbers: 3 for the normal wall, 2 once
    there is tone or thickening }
  if (A.Thick = 1) and (A.Act = 0) then Result.Lobes := 3 else Result.Lobes := 2;
  Result.TetherR := 1.1 * (1 + wn);
  Result.TetherK := 1.4 * 5 * CmH2O / Result.TetherR;
end;

function WallRatio(const P: TRingParams): Double;
var
  R: TAirwayRing;
  a5: Double;
begin
  R := TAirwayRing.Create(P);
  try
    if not R.MoveTo(rmPressure, 5 * CmH2O) then Exit(NaN);
    a5 := R.LumenArea;
    if not R.MoveTo(rmPressure, 40 * CmH2O) then Exit(NaN);
    Result := a5 / R.LumenArea;
  finally
    R.Free;
  end;
end;

function FitWallM(Target: Double): Double;
var
  lo, hi, mid, r: Double;
  it, l: Integer;
  P: TRingParams;
begin
  { on the stiff side of its minimum the ratio rises with the modulus }
  lo := Ln(1); hi := Ln(300);
  for it := 1 to 24 do
  begin
    mid := 0.5 * (lo + hi);
    P := NormalBronchiole(1);
    for l := 0 to P.NLayers - 1 do P.Layers[l].Mu := P.Layers[l].Mu * Exp(mid);
    P.Lobes := 3;
    P.TetherR := 1.1 * (1 + WallThickness(P));
    P.TetherK := 1.4 * 5 * CmH2O / P.TetherR;
    r := WallRatio(P);
    if r < Target then lo := mid else hi := mid;
  end;
  Result := Exp(0.5 * (lo + hi));
end;

const
  LawPLo = -150 * CmH2O;
  LawPHi = 60 * CmH2O;

{ every parameter the law depends on, as text }
function RingKey(const P: TRingParams): string;
var
  l: Integer;
begin
  Result := Format('v1 Ri %.9g NL %d Lobes %d NT %d Kap %.9g T0 %.9g LMin %.9g Act %.9g TK %.9g TR %.9g Imp %.9g CK %.9g P %.6g %.6g',
    [P.Ri, P.NLayers, P.Lobes, P.NT, P.KappaRatio, P.T0, P.LMin, P.Act, P.TetherK, P.TetherR,
     P.Imperfection, P.ContactK, LawPLo, LawPHi]);
  for l := 0 to P.NLayers - 1 do
    Result := Result + Format(' L %.9g %.9g %.9g %.9g %d', [P.Layers[l].Thick, P.Layers[l].Mu,
      P.Layers[l].Stiffen, P.Layers[l].Muscle, P.Layers[l].NR]);
end;

function KeyFile(const Key: string): string;
var
  h: QWord;
  i: Integer;
begin
  { FNV-1a }
  h := QWord($cbf29ce484222325);
  for i := 1 to Length(Key) do
  begin
    h := h xor Ord(Key[i]);
    {$PUSH}{$Q-}{$R-}
    h := h * QWord($100000001b3);
    {$POP}
  end;
  Result := IncludeTrailingPathDelimiter(LawCacheDir) + 'law_' + IntToHex(h, 16) + '.txt';
end;

function LoadLaw(const P: TRingParams; out Notes: string): TTubeLaw;
var
  F: TStringList;
  pp, aa: array of Double;
  i, n, k: Integer;
  fn: string;
begin
  Result := nil; Notes := '';
  if LawCacheDir = '' then Exit;
  fn := KeyFile(RingKey(P));
  if not FileExists(fn) then Exit;
  F := TStringList.Create;
  try
    F.LoadFromFile(fn);
    if (F.Count < 4) or (F[0] <> RingKey(P)) then Exit;
    Notes := F[1];
    n := F.Count - 2;
    SetLength(pp, n); SetLength(aa, n);
    for i := 0 to n - 1 do
    begin
      k := Pos(' ', F[i + 2]);
      pp[i] := StrToFloat(Copy(F[i + 2], 1, k - 1));
      aa[i] := StrToFloat(Copy(F[i + 2], k + 1, MaxInt));
    end;
    Result := TTubeLaw.Create;
    Result.SetTable(pp, aa);
  finally
    F.Free;
  end;
end;

procedure SaveLaw(const P: TRingParams; L: TTubeLaw; const Notes: string);
var
  F: TStringList;
  i: Integer;
begin
  if LawCacheDir = '' then Exit;
  ForceDirectories(LawCacheDir);
  F := TStringList.Create;
  try
    F.Add(RingKey(P));
    F.Add(Notes);
    for i := 0 to L.Count - 1 do F.Add(Format('%.17g %.17g', [L.TableP(i), L.TableA(i)]));
    F.SaveToFile(KeyFile(RingKey(P)));
  finally
    F.Free;
  end;
end;

type
  TLawJob = class(TThread)
  public
    P: TRingParams;
    Law: TTubeLaw;
    Notes: string;
    Err: string;
    procedure Execute; override;
  end;

procedure TLawJob.Execute;
begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  try
    Law := BuildTubeLaw(P, LawPLo, LawPHi, Notes);
  except
    on E: Exception do Err := E.Message;
  end;
end;

procedure BuildLaws(const Rings: array of TRingParams; var Laws: array of TTubeLaw;
  out Notes: string; MaxThreads: Integer);
var
  Jobs: array of TLawJob;
  Idx: array of Integer;
  i, next, running, k: Integer;
  nt: string;
  DFS: TFormatSettings;
begin
  Notes := '';
  DFS := DefaultFormatSettings;
  DefaultFormatSettings.DecimalSeparator := '.';
  try
    SetLength(Jobs, 0); SetLength(Idx, 0);
    for i := 0 to High(Rings) do
    begin
      Laws[i] := LoadLaw(Rings[i], nt);
      if Laws[i] <> nil then
      begin
        if nt <> '' then Notes := Notes + Format('law %d: %s', [i, nt]);
        Continue;
      end;
      SetLength(Idx, Length(Idx) + 1);
      Idx[High(Idx)] := i;
    end;
    { run the missing ones, MaxThreads at a time, in order of index }
    SetLength(Jobs, Length(Idx));
    next := 0; running := 0;
    k := 0;
    while k < Length(Idx) do
    begin
      while (next < Length(Idx)) and (next - k < MaxThreads) do
      begin
        Jobs[next] := TLawJob.Create(True);
        Jobs[next].P := Rings[Idx[next]];
        Jobs[next].Start;
        Inc(next);
      end;
      Jobs[k].WaitFor;
      if Jobs[k].Err <> '' then raise Exception.Create('BuildLaws : ' + Jobs[k].Err);
      Laws[Idx[k]] := Jobs[k].Law;
      SaveLaw(Rings[Idx[k]], Jobs[k].Law, Jobs[k].Notes);
      if Jobs[k].Notes <> '' then Notes := Notes + Format('law %d: %s', [Idx[k], Jobs[k].Notes]);
      Jobs[k].Free;
      Inc(k);
    end;
  finally
    DefaultFormatSettings := DFS;
  end;
end;

procedure BuildWallLaws(const A: TAsthma; var Laws: array of TTubeLaw; out Notes: string);
var
  R: array[0..NWall - 1] of TRingParams;
  w: Integer;
begin
  for w := 0 to NWall - 1 do R[w] := WallRing(w, A);
  BuildLaws(R, Laws, Notes);
end;

{ ---------------------------------------------------------------- }

function ScaledLaw(L: TTubeLaw; F: Double): TTubeLaw;
var
  P, A: array of Double;
  i: Integer;
begin
  SetLength(P, L.Count); SetLength(A, L.Count);
  for i := 0 to L.Count - 1 do
  begin
    P[i] := L.TableP(i); A[i] := F * L.TableA(i);
  end;
  Result := TTubeLaw.Create;
  Result.SetTable(P, A);
end;

procedure TLung.BuildAirways(const P: TLungParams; const WallLaw, RefLaw: array of TTubeLaw;
  Mucus: Double);
var
  g, i, n: Integer;
  Abs_: TTubeLaw;
  Lin: TLining;
  pt, aw, ga: Double;
  cl: Boolean;
  gp, gaa: array of Double;
begin
  Prm := P;
  for g := 0 to NGen - 1 do
  begin
    Gens[g].N := Power(2, g);
    Gens[g].Len := WeibelLen[g];
    Gens[g].AF := Pi * Sqr(LambertRMax[g]) * RefLaw[g].Area(5 * CmH2O) / RefLaw[g].Area(40 * CmH2O);
    Abs_ := ScaledLaw(WallLaw[g], Pi * Sqr(LambertRMax[g]) / RefLaw[g].Area(40 * CmH2O));
    Lin := NoLining;
    Lin.Gamma := P.Gamma;
    Lin.ALiq := Mucus * P.Film * 2 * Sqrt(Pi * Gens[g].AF);
    { the gas area, sampled every 0.25 cmH2O; closed below PClose }
    Gens[g].PClose := -Infinity;
    SetLength(gp, 0); SetLength(gaa, 0);
    n := 0;
    for i := 0 to 840 do
    begin
      pt := (-150 + 0.25 * i) * CmH2O;
      ga := GasArea(Abs_, Lin, pt, aw, cl);
      if cl then
      begin
        Gens[g].PClose := pt; n := 0;
        SetLength(gp, 0); SetLength(gaa, 0);
      end
      else
      begin
        SetLength(gp, n + 1); SetLength(gaa, n + 1);
        gp[n] := pt; gaa[n] := ga; Inc(n);
      end;
    end;
    Gens[g].Gas := TTubeLaw.Create;
    if n < 2 then
    begin
      { closed by its lining at every transmural pressure up to 60
        cmH2O: nothing ever passes (a placeholder law for the area) }
      Gens[g].PClose := Infinity;
      SetLength(gp, 2); SetLength(gaa, 2);
      gp[0] := 0; gp[1] := 1; gaa[0] := 1e-9; gaa[1] := 2e-9;
    end;
    Gens[g].Gas.SetTable(gp, gaa);
    Abs_.Free;
  end;
end;

constructor TLung.CreateAirways(const P: TLungParams; const WallLaw, RefLaw: array of TTubeLaw;
  Mucus: Double);
begin
  inherited Create;
  BuildAirways(P, WallLaw, RefLaw, Mucus);
end;

constructor TLung.Create(const P: TLungParams; const WallLaw, RefLaw: array of TTubeLaw;
  Mucus: Double; const Alv: TAlveolusParams);
var
  i, n: Integer;
  VT, v, scale: Double;
  M: TAlveolus;
  tv, tp: array of Double;
begin
  inherited Create;
  BuildAirways(P, WallLaw, RefLaw, Mucus);
  { recoil: the alveolus's deflation limb, its volume at RTLC (where it
    holds PTLC) scaled to the lung's alveolar gas at TLC }
  M := TAlveolus.Create(Alv);
  VT := M.UnstressedVolume * Power(0.126 / Alv.R0, 3);
  scale := (P.TLC - P.VDead) / VT;
  n := 0;
  if not M.MoveTo(amVolume, VT) then raise Exception.Create('TLung : alveolus at TLC');
  v := 1.05;
  while v >= 0.15 do
  begin
    if not M.MoveTo(amVolume, v * VT) then Break;
    SetLength(tv, n + 1); SetLength(tp, n + 1);
    tv[n] := P.VDead + scale * v * VT; tp[n] := M.P; Inc(n);
    v := v - 0.025;
  end;
  M.Free;
  if n < 4 then raise Exception.Create('TLung : alveolar curve');
  SetLength(FVTab, n); SetLength(FPTab, n);
  for i := 0 to n - 1 do
  begin
    FVTab[i] := tv[n - 1 - i]; FPTab[i] := tp[n - 1 - i];
  end;
end;

destructor TLung.Destroy;
var
  g: Integer;
begin
  for g := 0 to NGen - 1 do Gens[g].Gas.Free;
  inherited;
end;

function TLung.Pel(V: Double): Double;
var
  i, n: Integer;
begin
  n := Length(FVTab);
  if V <= FVTab[0] then
    Exit(FPTab[0] + (V - FVTab[0]) * (FPTab[1] - FPTab[0]) / (FVTab[1] - FVTab[0]));
  if V >= FVTab[n - 1] then
    Exit(FPTab[n - 1] + (V - FVTab[n - 1]) * (FPTab[n - 1] - FPTab[n - 2]) / (FVTab[n - 1] - FVTab[n - 2]));
  i := 0;
  while FVTab[i + 1] < V do Inc(i);
  Result := FPTab[i] + (V - FVTab[i]) * (FPTab[i + 1] - FPTab[i]) / (FVTab[i + 1] - FVTab[i]);
end;

function TLung.Pcw(V: Double): Double;
begin
  Result := CmH2O * ((V - Prm.CwRelax) / Prm.CwComp
    + Prm.CwB * (Exp((V - Prm.CwHi) / Prm.CwW) - Exp((Prm.CwLo - V) / Prm.CwW)));
end;

function TLung.StaticVolume(PNet: Double): Double;
var
  lo, hi, mid: Double;
  it: Integer;
begin
  lo := 0.2; hi := 9;
  for it := 1 to 80 do
  begin
    mid := 0.5 * (lo + hi);
    if Pel(mid) + Pcw(mid) < PNet then lo := mid else hi := mid;
  end;
  Result := 0.5 * (lo + hi);
end;

function TLung.Grad(g: Integer; P, q, Ppl: Double): Double;
var
  Ptm, A, dA, Re, S2: Double;
begin
  Ptm := P - Ppl;
  if Ptm <= Gens[g].PClose then begin FChoke := True; Exit(0); end;
  A := Gens[g].Gas.Area(Ptm);
  if A < 1e-4 * Gens[g].AF then begin FChoke := True; Exit(0); end;
  dA := Gens[g].Gas.Slope(Ptm);
  Re := Prm.Rho * q * 2 * Sqrt(A / Pi) / (Prm.Visc * A);
  S2 := Prm.Rho * q * q * dA / (A * A * A);
  if S2 >= 0.98 then begin FChoke := True; Exit(0); end;
  Result := -8 * Pi * Prm.Visc * q / (A * A) * (Prm.Ka + Prm.Kb * Re) / (1 - S2);
end;

function TLung.March(g: Integer; P, q, Ppl: Double; out Choked: Boolean): Double;
var
  i: Integer;
  h, k1, k2, k3, k4: Double;
begin
  FChoke := False;
  Result := P;
  if q <= 0 then begin Grad(g, P, 0, Ppl); Choked := FChoke; Exit; end;
  h := Gens[g].Len / Prm.Steps;
  for i := 1 to Prm.Steps do
  begin
    k1 := Grad(g, Result, q, Ppl); if FChoke then Break;
    k2 := Grad(g, Result + 0.5 * h * k1, q, Ppl); if FChoke then Break;
    k3 := Grad(g, Result + 0.5 * h * k2, q, Ppl); if FChoke then Break;
    k4 := Grad(g, Result + h * k3, q, Ppl); if FChoke then Break;
    Result := Result + h / 6 * (k1 + 2 * k2 + 2 * k3 + k4);
  end;
  if not FChoke then Grad(g, Result, q, Ppl);
  Choked := FChoke;
end;

function TLung.Junction(gFrom, gTo: Integer; P, Q, Ppl: Double; out Choked: Boolean): Double;
var
  a0, a1, u0, u1, dp, Ptm: Double;
  it: Integer;
begin
  Choked := False;
  Result := P;
  Ptm := P - Ppl;
  if (Ptm <= Gens[gFrom].PClose) or (Ptm <= Gens[gTo].PClose) then begin Choked := True; Exit; end;
  a0 := Gens[gFrom].Gas.Area(Ptm);
  u0 := Q / Gens[gFrom].N / a0;
  for it := 1 to 3 do
  begin
    Ptm := Result - Ppl;
    if Ptm <= Gens[gTo].PClose then begin Choked := True; Exit; end;
    a1 := Gens[gTo].Gas.Area(Ptm);
    u1 := Q / Gens[gTo].N / a1;
    dp := 0.5 * Prm.Rho * (u1 * u1 - u0 * u0);
    if dp <= 0 then Exit(P);
    Result := P - dp;
  end;
end;

function TLung.MarchUp(Q, P, Ppl: Double; GDeep, GTop: Integer; JunctionIn: Boolean;
  out Choked: Boolean): Double;
var
  g: Integer;
  ql: Double;
begin
  ChokeGen := -1;
  Choked := False;
  if JunctionIn then
  begin
    P := Junction(GDeep + 1, GDeep, P, Q, Ppl, Choked);
    if Choked then begin ChokeGen := GDeep; Exit(P); end;
  end;
  for g := GDeep downto GTop do
  begin
    P := March(g, P, Q / Gens[g].N, Ppl, Choked);
    if Choked then begin ChokeGen := g; Exit(P); end;
    if g > GTop then
    begin
      P := Junction(g, g - 1, P, Q, Ppl, Choked);
      if Choked then begin ChokeGen := g - 1; Exit(P); end;
    end;
  end;
  if GTop = 0 then
  begin
    ql := Q / LitreMM3;
    P := P - CmH2O * (Prm.K1 * ql + Prm.K2 * ql * ql);
  end;
  Result := P;
end;

function TLung.MarchDown(Q, P, Ppl: Double; GTop, GDeep: Integer; JunctionOut: Boolean;
  out Choked: Boolean): Double;
var
  g: Integer;
  ql: Double;
begin
  ChokeGen := -1;
  Choked := False;
  if GTop = 0 then
  begin
    ql := Q / LitreMM3;
    P := P - CmH2O * (Prm.K1 * ql + Prm.K2 * ql * ql);
  end;
  for g := GTop to GDeep do
  begin
    P := March(g, P, Q / Gens[g].N, Ppl, Choked);
    if Choked then begin ChokeGen := g; Exit(P); end;
    if (g < GDeep) or JunctionOut then
    begin
      P := Junction(g, g + 1, P, Q, Ppl, Choked);
      if Choked then begin ChokeGen := g + 1; Exit(P); end;
    end;
  end;
  Result := P;
end;

function TLung.MouthPressure(Q, Palv, Ppl: Double; out Choked: Boolean): Double;
begin
  Result := MarchUp(Q, Palv, Ppl, NGen - 1, 0, False, Choked);
end;

function TLung.AlveolarEnd(Q, Ppl: Double; out Choked: Boolean): Double;
begin
  Result := MarchDown(Q, 0, Ppl, 0, NGen - 1, False, Choked);
end;

{ positive at q = 0, falling with q; Choked past the limit }
function TLung.Residual(q, Palv, Ppl: Double; out Choked: Boolean): Double;
begin
  if Palv > 0 then Result := MouthPressure(q, Palv, Ppl, Choked)
  else Result := AlveolarEnd(q, Ppl, Choked) - Palv;
end;

function TLung.Flow(Palv, Ppl, Guess: Double): Double;
var
  lo, hi, rlo, rhi, q, r, qn: Double;
  chHi, ch: Boolean;
  it, side: Integer;
  cg: Integer;
begin
  Limited := False;
  if Abs(Palv) < 1e-9 then Exit(0);
  { closed by its lining even without flow: nothing passes }
  Residual(0, Palv, Ppl, ch);
  if ch then
  begin
    Limited := True;
    Exit(0);
  end;
  { start from the last flow if it had the same sign }
  q := Abs(Guess);
  if (q = 0) or ((Guess > 0) <> (Palv > 0)) then q := 1e4;
  lo := 0; rlo := Abs(Palv);
  r := Residual(q, Palv, Ppl, ch);
  if (not ch) and (r > 0) then
  begin
    lo := q; rlo := r;
    hi := q;
    repeat
      hi := hi * 1.5;
      rhi := Residual(hi, Palv, Ppl, chHi);
      if (not chHi) and (rhi > 0) then begin lo := hi; rlo := rhi; end;
    until chHi or (rhi <= 0) or (hi > 1e9);
  end
  else
  begin
    hi := q; rhi := r; chHi := ch;
    while hi > 1e-3 do
    begin
      q := hi / 1.5;
      r := Residual(q, Palv, Ppl, ch);
      if (not ch) and (r > 0) then begin lo := q; rlo := r; Break; end;
      hi := q; rhi := r; chHi := ch;
    end;
  end;
  { Illinois regula falsi while both ends are finite, bisection when the
    upper end is choked }
  side := 0;
  cg := -1;
  for it := 1 to 80 do
  begin
    if hi - lo <= 1e-7 * hi + 1e-6 then Break;
    if chHi then qn := 0.5 * (lo + hi)
    else
    begin
      qn := (lo * rhi - hi * rlo) / (rhi - rlo);
      if (qn <= lo) or (qn >= hi) then qn := 0.5 * (lo + hi);
    end;
    r := Residual(qn, Palv, Ppl, ch);
    if ch then
    begin
      hi := qn; chHi := True; cg := ChokeGen;
    end
    else if r > 0 then
    begin
      lo := qn; rlo := r;
      if side = 1 then rhi := 0.5 * rhi;
      side := 1;
    end
    else
    begin
      hi := qn; rhi := r; chHi := False;
      if side = -1 then rlo := 0.5 * rlo;
      side := -1;
      if Abs(r) < 1e-9 then begin lo := qn; Break; end;
    end;
    if (not chHi) and (Abs(rlo) < 1e-9) then Break;
  end;
  Limited := chHi;
  if Limited then ChokeGen := cg else ChokeGen := -1;
  if Limited then Result := lo
  else if chHi or (rhi = rlo) then Result := lo
  else Result := (lo * rhi - hi * rlo) / (rhi - rlo);
  if Palv < 0 then Result := -Result;
end;

function TLung.Resistance(Ppl: Double): Double;
var
  dp, q: Double;
begin
  dp := 0.001 * CmH2O;
  q := Flow(dp, Ppl, 0);
  Result := dp / q;
end;

{ ---------------------------------------------------------------- }

constructor TLungSim.Create(ALung: TLung; AMusc: TMuscleFn; V0, ADt: Double);
begin
  inherited Create;
  Lung := ALung; Musc := AMusc; V := V0; Dt := ADt; T := 0; Q := 0;
  Evaluate;
end;

procedure TLungSim.Evaluate;
begin
  Pmus := Musc(T, V);
  Ppl := Lung.Pcw(V) - CmH2O * Pmus;
  Palv := Ppl + Lung.Pel(V);
  Q := Lung.Flow(Palv, Ppl, Q);
  Limited := Lung.Limited;
  ChokeGen := Lung.ChokeGen;
end;

procedure TLungSim.Step;
var
  q1, v0: Double;
begin
  q1 := Q; v0 := V;
  V := v0 - Dt * q1 / LitreMM3;
  T := T + Dt;
  Evaluate;
  V := v0 - 0.5 * Dt * (q1 + Q) / LitreMM3;
  Evaluate;
end;

end.
