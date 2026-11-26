unit uPatchyLung;

{ Stage 3: the patchy lung. The symmetric lung of uLungModel split, below
  generation K, into NU = 2^K units, each a symmetric subtree of
  generations K..16 with its own asthma severity, its own height in the
  chest, and its own alveolar volume. Units mm, kPa, s inside; litres for
  volumes.

  TRUNK   generations 0..K-1, one symmetric tree at the mean severity
  (s = 1), seeing the pleural pressure at mid-height. Patchiness in
  asthma is peripheral (Venegas et al., Nature 2005): the trunk is shared.

  UNITS   severity s_u multiplies the case's asthma (activation s A.Act,
  thickening 1 + s (A.Thick - 1), lining 1 + s (A.Mucus - 1)). s_u is
  log-normal with mean 1, built as a cascade down the tree:
     s_u = exp(sigma Z_u - sigma^2/2),
     Z_u = (xi_1 + ... + xi_K) / sqrt(K),
  xi_g a standard normal drawn once for each airway of generation g and
  shared by every unit below it. Units that share more of their path are
  more alike, so the severe ones come in patches at every scale. s is
  rounded to levels 0, DS, 2 DS, ... (DS = 0.25), each level one set of
  finite-element tube laws.

  LAYOUT   unit u's place follows its path: the first branching splits
  the chest left/right, the next top/bottom, alternately, so K = 8 gives a
  16 x 16 grid in a frontal section of Width x Height cm. Upright, the
  pleural pressure rises Gravity cmH2O per cm down from the top
  (about 0.2-0.25: West), so lower units are smaller and nearer closure.

  UNIT TABLES   in a symmetric subtree only the transmural pressures
  matter, so for each level the expiratory march from the alveolar end
  (transmural Pa) to the subtree's top is tabulated once:
     DE(Pa, x) = Pa - Ptop,  flow q = x QmaxE(Pa),  x in [0, 1],
  QmaxE(Pa) the largest flow the subtree carries (choke or lining
  closure), and likewise inspiration from the top (transmural Pt):
     DI(Pt, x) = Pt - Palv,  q = x QmaxI(Pt).
  Pressures every 0.5 cmH2O, x on 41 points crowded towards 1 (where the
  drop steepens to the choke). A flow is found by inverting the column
  at Pa (or Pt), linear in both directions; a drop beyond the column's
  end is a limited flow at Qmax. Flows in the tables are lung-equivalent
  (as if every unit carried the same), so a unit's own flow is q / NU.
  The junction from the unit's generation K into the trunk is the
  trunk's (mean severity).

  SOLVE   given alveolar pressures and pleural pressures, the pressure Pc
  at the trunk's lower end is the one unknown: each unit's flow follows
  from Pc and its alveolar pressure by its table, their sum Q runs
  through the trunk to the mouth at 0. F(Pc) = mouth pressure (Q >= 0)
  or Pc - pressure the trunk delivers (Q < 0) rises with Pc; Illinois
  regula falsi, bisection when the trunk chokes. Units may flow in
  opposite directions (pendelluft). }

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Math, uTubeLaw, uAirwayRing, uAlveolus, uLungModel;

const
  NX = 41;
  PtLo = -40 * CmH2O;
  PtStep = 0.5 * CmH2O;
  NPt = 241;   { to +80 cmH2O }

type
  TUnitTable = class
  public
    S: Double;                       { severity }
    PClose: Double;                  { kPa: the subtree closes at or below this transmural pressure }
    QmaxE, QmaxI: array of Double;   { lung-equivalent, mm3/s }
    DE, DI: array of Double;         { [i * NX + j], kPa }
    constructor Create(L: TLung; K: Integer);
    { lung-equivalent flows (>= 0) out of the alveoli for transmural
      pressures Pa at the alveolar end and Pt at the top (Pa > Pt), and
      into them (Pt > Pa) }
    function FlowOut(Pa, Pt: Double; out Lim: Boolean): Double;
    function FlowIn(Pt, Pa: Double; out Lim: Boolean): Double;
  end;

  TPatchyParams = record
    K: Integer;          { units at generation K: 2^K of them }
    Sigma: Double;       { log-normal sigma of the severity }
    Seed: Integer;
    Gravity: Double;     { cmH2O per cm }
    Width, Height: Double;  { cm }
    DS, SMax: Double;    { severity level step and cap }
    { ActMode: levels are muscle activations 0, DS, .. SMax (thickening
      and lining the case's everywhere), every level is built, and a
      unit starts at activation Sev * A.Act; its Level may be changed
      between steps (uToneLung) }
    ActMode: Boolean;
  end;

  TPatchyLung = class
  private
    FWork: array of Double;
    function UnitFlow(u: Integer; Pu, Pc, PplU: Double; out Lim: Boolean): Double;
    function Eval(Pc: Double; out Choked: Boolean): Double;
  public
    Prm: TLungParams;
    PP: TPatchyParams;
    A: TAsthma;
    NU: Integer;
    Trunk: TLung;                  { owned; its Pel and Pcw are the lung's }
    Tables: array of TUnitTable;   { per level, nil where unused }
    Level: array of Integer;
    Sev: array of Double;          { unrounded severity }
    PX, PY: array of Double;       { cm, PY from the top }
    DPpl: array of Double;         { kPa, pleural pressure against mid-height }
    { the last Solve }
    Pu, PplU: array of Double;
    Qu: array of Double;           { each unit's own flow, mm3/s, positive out }
    LimU: array of Boolean;
    Pc: Double;
    TrunkLimited: Boolean;
    { pressure at the airway opening (kPa, against atmosphere) that Solve
      works to: 0 breathing, the ventilator's when ventilated }
    Pao: Double;
    Notes: string;
    constructor Create(const AP: TLungParams; const APP: TPatchyParams; const AA: TAsthma;
      const Alv: TAlveolusParams; const RefLaws: array of TTubeLaw);
    destructor Destroy; override;
    function SevAsthma(s: Double): TAsthma;
    function LevelAsthma(j: Integer): TAsthma;
    function LevelCount: Integer;
    function UnitPel(V: Double): Double;   { unit alveolar volume V (L) }
    function UnitVolume(PelU: Double): Double;
    { static state: unit volumes with no flow for the muscle pressure
      Pmus (cmH2O); returns the pleural pressure at mid-height }
    function StaticState(Pmus: Double; var V: array of Double): Double;
    { mouth flow (mm3/s, positive out) for unit volumes V and the pleural
      pressure at mid-height Ppl; fills Pu, PplU, Qu, LimU, Pc }
    function Solve(const V: array of Double; Ppl: Double): Double;
    { the other way round, for a ventilator setting the flow: the airway
      opening pressure (kPa) at which the mouth flow is Q (mm3/s,
      positive out; 0 for an occlusion); fills what Solve fills. With
      an obstructed lung a large outward Q may be impossible: the
      pressure then runs to the bottom of its search, and Limited says
      so. }
    function SolveFlow(const V: array of Double; Ppl, Q: Double): Double;
  end;

  { smPressure: the airway opening is held at Paw (breathing: 0);
    smFlow: the mouth flow is held at QSet and Paw follows }
  TSimMode = (smPressure, smFlow);

  TPatchySim = class
  public
    Lung: TPatchyLung;   { not owned }
    Musc: TMuscleFn;
    Mode: TSimMode;
    QSet: Double;        { mm3/s, positive out }
    Paw: Double;         { kPa }
    Dt, T: Double;
    V: array of Double;  { L }
    Q, Ppl, Pmus, VTot: Double;
    NLim, NClosed: Integer;
    constructor Create(ALung: TPatchyLung; AMusc: TMuscleFn; const V0: array of Double; ADt: Double);
    procedure Evaluate;
    procedure Step;
  end;

function DefaultPatchyParams: TPatchyParams;

implementation

function DefaultPatchyParams: TPatchyParams;
begin
  Result.K := 8;
  Result.Sigma := 0.5;
  Result.Seed := 1;
  Result.Gravity := 0.2;
  Result.Width := 30;
  Result.Height := 24;
  Result.DS := 0.25;
  Result.SMax := 3;
  Result.ActMode := False;
end;

{ ---------------------------------------------------------------- }

function XAt(j: Integer): Double;
begin
  Result := 1 - Sqr(1 - j / (NX - 1));
end;

constructor TUnitTable.Create(L: TLung; K: Integer);
var
  i, j, g: Integer;
  pt, lo, hi, mid, p: Double;
  ch: Boolean;

  function Chokes(Exp: Boolean; q: Double): Boolean;
  begin
    if Exp then L.MarchUp(q, pt, 0, NGen - 1, K, False, Result)
    else L.MarchDown(q, pt, 0, K, NGen - 1, False, Result);
  end;

  function QMax(Exp: Boolean): Double;
  var
    it: Integer;
  begin
    lo := 0; hi := 1e4;
    while (not Chokes(Exp, hi)) and (hi < 1e10) do begin lo := hi; hi := 4 * hi; end;
    for it := 1 to 60 do
    begin
      mid := 0.5 * (lo + hi);
      if Chokes(Exp, mid) then hi := mid else lo := mid;
      if hi - lo < 1e-9 * hi then Break;
    end;
    Result := lo;
  end;

begin
  inherited Create;
  PClose := -Infinity;
  for g := K to NGen - 1 do PClose := Max(PClose, L.Gens[g].PClose);
  SetLength(QmaxE, NPt); SetLength(QmaxI, NPt);
  SetLength(DE, NPt * NX); SetLength(DI, NPt * NX);
  for i := 0 to NPt - 1 do
  begin
    pt := PtLo + i * PtStep;
    if pt <= PClose then
    begin
      QmaxE[i] := 0; QmaxI[i] := 0;
      for j := 0 to NX - 1 do begin DE[i * NX + j] := 0; DI[i * NX + j] := 0; end;
      Continue;
    end;
    QmaxE[i] := QMax(True);
    QmaxI[i] := QMax(False);
    for j := 0 to NX - 1 do
    begin
      p := L.MarchUp(XAt(j) * QmaxE[i], pt, 0, NGen - 1, K, False, ch);
      DE[i * NX + j] := pt - p;
      p := L.MarchDown(XAt(j) * QmaxI[i], pt, 0, K, NGen - 1, False, ch);
      DI[i * NX + j] := pt - p;
      { the drop rises with the flow }
      if j > 0 then
      begin
        DE[i * NX + j] := Max(DE[i * NX + j], DE[i * NX + j - 1]);
        DI[i * NX + j] := Max(DI[i * NX + j], DI[i * NX + j - 1]);
      end;
    end;
  end;
end;

{ invert a column of drops at row position f for drop d }
function Invert(const Q, D: array of Double; f, dd: Double; out Lim: Boolean): Double;
var
  i0, j: Integer;
  w, qm, c0, c1: Double;
begin
  Lim := False;
  f := EnsureRange(f, 0, NPt - 1.000001);
  i0 := Trunc(f); w := f - i0;
  qm := (1 - w) * Q[i0] + w * Q[i0 + 1];
  if qm <= 0 then begin Lim := True; Exit(0); end;
  c0 := 0;
  for j := 1 to NX - 1 do
  begin
    c1 := (1 - w) * D[i0 * NX + j] + w * D[(i0 + 1) * NX + j];
    if dd < c1 then
    begin
      if c1 > c0 then
        Exit(qm * (XAt(j - 1) + (XAt(j) - XAt(j - 1)) * (dd - c0) / (c1 - c0)))
      else
        Exit(qm * XAt(j));
    end;
    c0 := c1;
  end;
  Lim := True;
  Result := qm;
end;

function TUnitTable.FlowOut(Pa, Pt: Double; out Lim: Boolean): Double;
begin
  if Pa <= PClose then begin Lim := True; Exit(0); end;
  Result := Invert(QmaxE, DE, (Pa - PtLo) / PtStep, Pa - Pt, Lim);
end;

function TUnitTable.FlowIn(Pt, Pa: Double; out Lim: Boolean): Double;
begin
  if Pt <= PClose then begin Lim := True; Exit(0); end;
  Result := Invert(QmaxI, DI, (Pt - PtLo) / PtStep, Pt - Pa, Lim);
end;

{ ---------------------------------------------------------------- }

function TPatchyLung.LevelAsthma(j: Integer): TAsthma;
begin
  if PP.ActMode then
  begin
    Result := A;
    Result.Act := j * PP.DS;
  end
  else Result := SevAsthma(j * PP.DS);
end;

function TPatchyLung.LevelCount: Integer;
begin
  Result := Length(Tables);
end;

function TPatchyLung.SevAsthma(s: Double): TAsthma;
begin
  Result.Act := Min(0.95, s * A.Act);
  Result.Thick := 1 + s * (A.Thick - 1);
  Result.Mucus := 1 + s * (A.Mucus - 1);
end;

type
  TTableJob = class(TThread)
  public
    L: TLung;
    K: Integer;
    T: TUnitTable;
    Err: string;
    procedure Execute; override;
  end;

procedure TTableJob.Execute;
begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  try
    T := TUnitTable.Create(L, K);
  except
    on E: Exception do Err := E.Message;
  end;
end;

constructor TPatchyLung.Create(const AP: TLungParams; const APP: TPatchyParams; const AA: TAsthma;
  const Alv: TAlveolusParams; const RefLaws: array of TTubeLaw);
var
  u, g, j, nl, b, nb, w: Integer;
  xi: array of array of Double;
  z, x0, x1, y0, y1: Double;
  used: array of Boolean;
  Rings: array of TRingParams;
  Laws: array of TTubeLaw;
  WL, RL: array[0..NGen - 1] of TTubeLaw;
  LevL: array of TLung;
  Jobs: array of TTableJob;
  nt: string;
  sa: TAsthma;
  lawIdx: array of Integer;
begin
  inherited Create;
  Prm := AP; PP := APP; A := AA;
  NU := 1 shl PP.K;
  SetLength(Level, NU); SetLength(Sev, NU); SetLength(PX, NU); SetLength(PY, NU);
  SetLength(DPpl, NU); SetLength(Pu, NU); SetLength(PplU, NU); SetLength(Qu, NU);
  SetLength(LimU, NU); SetLength(FWork, NU);
  { the severity cascade }
  RandSeed := PP.Seed;
  SetLength(xi, PP.K + 1);
  for g := 1 to PP.K do
  begin
    SetLength(xi[g], 1 shl g);
    for b := 0 to (1 shl g) - 1 do xi[g][b] := RandG(0, 1);
  end;
  nl := Round(PP.SMax / PP.DS) + 1;
  SetLength(used, nl);
  for u := 0 to NU - 1 do
  begin
    z := 0;
    for g := 1 to PP.K do z := z + xi[g][u shr (PP.K - g)];
    z := z / Sqrt(PP.K);
    Sev[u] := Exp(PP.Sigma * z - 0.5 * Sqr(PP.Sigma));
    if PP.ActMode then
      Level[u] := EnsureRange(Round(Sev[u] * A.Act / PP.DS), 0, nl - 1)
    else
      Level[u] := EnsureRange(Round(Sev[u] / PP.DS), 0, nl - 1);
    used[Level[u]] := True;
    { place: bits from the top split x, y, x, ... }
    x0 := 0; x1 := PP.Width; y0 := 0; y1 := PP.Height;
    for g := 1 to PP.K do
    begin
      b := (u shr (PP.K - g)) and 1;
      if Odd(g) then
      begin
        if b = 0 then x1 := 0.5 * (x0 + x1) else x0 := 0.5 * (x0 + x1);
      end
      else
      begin
        if b = 0 then y1 := 0.5 * (y0 + y1) else y0 := 0.5 * (y0 + y1);
      end;
    end;
    PX[u] := 0.5 * (x0 + x1); PY[u] := 0.5 * (y0 + y1);
    DPpl[u] := PP.Gravity * CmH2O * (PY[u] - 0.5 * PP.Height);
  end;
  if PP.ActMode then
    for j := 0 to nl - 1 do used[j] := True;
  { tube laws: the trunk's three walls at s = 1, and the membranous wall
    at every level used (BuildLaws reads the cache, and builds the rest
    in parallel) }
  SetLength(Rings, NWall + nl); SetLength(Laws, NWall + nl);
  SetLength(lawIdx, nl);
  nb := 0;
  for w := 0 to NWall - 1 do begin Rings[nb] := WallRing(w, A); Inc(nb); end;
  for j := 0 to nl - 1 do
    if used[j] then
    begin
      sa := LevelAsthma(j);
      Rings[nb] := WallRing(2, sa); lawIdx[j] := nb; Inc(nb);
    end;
  SetLength(Rings, nb); SetLength(Laws, nb);
  BuildLaws(Rings, Laws, nt);
  Notes := nt;
  for g := 0 to NGen - 1 do
  begin
    WL[g] := Laws[GenWall[g]]; RL[g] := RefLaws[GenWall[g]];
  end;
  Trunk := TLung.Create(Prm, WL, RL, A.Mucus, Alv);
  { one airway lung per level, its unit table built in a thread }
  SetLength(Tables, nl); SetLength(LevL, nl); SetLength(Jobs, nl);
  for j := 0 to nl - 1 do
  begin
    Tables[j] := nil; LevL[j] := nil; Jobs[j] := nil;
    if not used[j] then Continue;
    sa := LevelAsthma(j);
    for g := 0 to NGen - 1 do
      if GenWall[g] = 2 then WL[g] := Laws[lawIdx[j]] else WL[g] := RefLaws[GenWall[g]];
    LevL[j] := TLung.CreateAirways(Prm, WL, RL, sa.Mucus);
    Jobs[j] := TTableJob.Create(True);
    Jobs[j].L := LevL[j]; Jobs[j].K := PP.K;
    Jobs[j].Start;
  end;
  for j := 0 to nl - 1 do
    if Jobs[j] <> nil then
    begin
      Jobs[j].WaitFor;
      if Jobs[j].Err <> '' then raise Exception.Create('TPatchyLung : ' + Jobs[j].Err);
      Tables[j] := Jobs[j].T;
      Tables[j].S := j * PP.DS;
      Jobs[j].Free;
      LevL[j].Free;
    end;
  for j := 0 to High(Laws) do Laws[j].Free;
end;

destructor TPatchyLung.Destroy;
var
  j: Integer;
begin
  for j := 0 to High(Tables) do Tables[j].Free;
  Trunk.Free;
  inherited;
end;

function TPatchyLung.UnitPel(V: Double): Double;
begin
  Result := Trunk.Pel(Prm.VDead + NU * V);
end;

function TPatchyLung.UnitVolume(PelU: Double): Double;
var
  lo, hi, mid: Double;
  it: Integer;
begin
  lo := -1 / NU; hi := 10 / NU;
  for it := 1 to 70 do
  begin
    mid := 0.5 * (lo + hi);
    if UnitPel(mid) < PelU then lo := mid else hi := mid;
  end;
  Result := 0.5 * (lo + hi);
end;

function TPatchyLung.StaticState(Pmus: Double; var V: array of Double): Double;
var
  lo, hi, ppl, vt: Double;
  it, u: Integer;
begin
  lo := -40 * CmH2O; hi := 20 * CmH2O;
  for it := 1 to 70 do
  begin
    ppl := 0.5 * (lo + hi);
    vt := Prm.VDead;
    for u := 0 to NU - 1 do
    begin
      V[u] := UnitVolume(-(ppl + DPpl[u]));
      vt := vt + V[u];
    end;
    { Pcw(vt) - Pmus falls as ppl rises }
    if Trunk.Pcw(vt) - CmH2O * Pmus > ppl then lo := ppl else hi := ppl;
  end;
  Result := 0.5 * (lo + hi);
  for u := 0 to NU - 1 do V[u] := UnitVolume(-(Result + DPpl[u]));
end;

function TPatchyLung.UnitFlow(u: Integer; Pu, Pc, PplU: Double; out Lim: Boolean): Double;
var
  T: TUnitTable;
begin
  T := Tables[Level[u]];
  if Pu > Pc then Result := T.FlowOut(Pu - PplU, Pc - PplU, Lim) / NU
  else if Pu < Pc then Result := -T.FlowIn(Pc - PplU, Pu - PplU, Lim) / NU
  else
  begin
    Lim := Pu - PplU <= T.PClose;
    Result := 0;
  end;
end;

{ F(Pc): rises with Pc; Choked when the trunk can't carry the units' flow }
function TPatchyLung.Eval(Pc: Double; out Choked: Boolean): Double;
var
  u: Integer;
  Q: Double;
  lim: Boolean;
begin
  Q := 0;
  for u := 0 to NU - 1 do
  begin
    FWork[u] := UnitFlow(u, Pu[u], Pc, PplU[u], lim);
    LimU[u] := lim;
    Q := Q + FWork[u];
  end;
  if Q >= 0 then
    Result := Trunk.MarchUp(Q, Pc, PplU[0] - DPpl[0], PP.K - 1, 0, True, Choked) - Pao
  else
    Result := Pc - Trunk.MarchDown(-Q, Pao, PplU[0] - DPpl[0], 0, PP.K - 1, True, Choked);
  if Choked then
  begin
    if Q >= 0 then Result := -1e30 else Result := 1e30;
  end;
end;

function TPatchyLung.Solve(const V: array of Double; Ppl: Double): Double;
var
  u, it, side: Integer;
  lo, hi, flo, fhi, x, fx: Double;
  ch, chLo, chHi: Boolean;
begin
  lo := Pao; hi := Pao;
  for u := 0 to NU - 1 do
  begin
    PplU[u] := Ppl + DPpl[u];
    Pu[u] := PplU[u] + UnitPel(V[u]);
    lo := Min(lo, Pu[u]); hi := Max(hi, Pu[u]);
  end;
  lo := lo - 1e-9; hi := hi + 1e-9;
  flo := Eval(lo, chLo); fhi := Eval(hi, chHi);
  side := 0;
  for it := 1 to 200 do
  begin
    if hi - lo < 1e-10 then Break;
    if chLo or chHi or (flo >= 0) or (fhi <= 0) then x := 0.5 * (lo + hi)
    else
    begin
      x := (lo * fhi - hi * flo) / (fhi - flo);
      if (x <= lo) or (x >= hi) then x := 0.5 * (lo + hi);
    end;
    fx := Eval(x, ch);
    if Abs(fx) < 1e-10 then begin lo := x; hi := x; Break; end;
    if fx < 0 then
    begin
      lo := x; flo := fx; chLo := ch;
      if side = -1 then fhi := 0.5 * fhi;
      side := -1;
    end
    else
    begin
      hi := x; fhi := fx; chHi := ch;
      if side = 1 then flo := 0.5 * flo;
      side := 1;
    end;
  end;
  { at the trunk's limit the root is the edge of the choked side: take
    the unchoked end }
  if chLo then x := hi else x := 0.5 * (lo + hi);
  Eval(x, ch);
  TrunkLimited := chLo;
  Pc := x;
  Result := 0;
  for u := 0 to NU - 1 do
  begin
    Qu[u] := FWork[u];
    Result := Result + Qu[u];
  end;
end;

function TPatchyLung.SolveFlow(const V: array of Double; Ppl, Q: Double): Double;
var
  u, it: Integer;
  lo, hi, mid, s, pTop, plo, phi, pm: Double;
  lim, ch: Boolean;

  function Sum(PcX: Double): Double;
  var
    k: Integer;
  begin
    Result := 0;
    for k := 0 to NU - 1 do
    begin
      FWork[k] := UnitFlow(k, Pu[k], PcX, PplU[k], lim);
      LimU[k] := lim;
      Result := Result + FWork[k];
    end;
  end;

begin
  lo := 1e30; hi := -1e30;
  for u := 0 to NU - 1 do
  begin
    PplU[u] := Ppl + DPpl[u];
    Pu[u] := PplU[u] + UnitPel(V[u]);
    lo := Min(lo, Pu[u]); hi := Max(hi, Pu[u]);
  end;
  { the units' outflow falls as Pc rises: find Pc giving Q. The tables
    end 80 cmH2O above pleural pressure, which bounds the search. }
  pTop := Ppl + 75 * CmH2O;
  lo := Max(lo - 1e-9, Ppl + PtLo + 1 * CmH2O); hi := Min(hi + 1e-9, pTop);
  while (Sum(hi) > Q) and (hi < pTop) do hi := Min(pTop, hi + Max(1e-3, hi - lo));
  while (Sum(lo) < Q) and (lo > Ppl + PtLo + 2 * CmH2O) do lo := Max(Ppl + PtLo + 1 * CmH2O, lo - Max(1e-3, hi - lo));
  for it := 1 to 100 do
  begin
    mid := 0.5 * (lo + hi);
    s := Sum(mid);
    if s > Q then lo := mid else hi := mid;
    if hi - lo < 1e-9 then Break;
  end;
  Pc := 0.5 * (lo + hi);
  s := Sum(Pc);
  TrunkLimited := False;
  { the trunk, from Pc to the airway opening with the units' flow s }
  if s >= 0 then
  begin
    Result := Trunk.MarchUp(s, Pc, Ppl, PP.K - 1, 0, True, ch);
    TrunkLimited := ch;
  end
  else
  begin
    { MarchDown(Pao) = Pc, rising in Pao }
    plo := Pc; phi := Pc + 1 * CmH2O;
    while Trunk.MarchDown(-s, phi, Ppl, 0, PP.K - 1, True, ch) < Pc do phi := phi + (phi - plo);
    for it := 1 to 80 do
    begin
      pm := 0.5 * (plo + phi);
      if Trunk.MarchDown(-s, pm, Ppl, 0, PP.K - 1, True, ch) < Pc then plo := pm else phi := pm;
      if phi - plo < 1e-9 then Break;
    end;
    Result := 0.5 * (plo + phi);
  end;
  Pao := Result;
  for u := 0 to NU - 1 do Qu[u] := FWork[u];
end;

{ ---------------------------------------------------------------- }

constructor TPatchySim.Create(ALung: TPatchyLung; AMusc: TMuscleFn; const V0: array of Double; ADt: Double);
var
  u: Integer;
begin
  inherited Create;
  Lung := ALung; Musc := AMusc; Dt := ADt; T := 0;
  Mode := smPressure; QSet := 0; Paw := 0;
  SetLength(V, Lung.NU);
  for u := 0 to Lung.NU - 1 do V[u] := V0[u];
  Evaluate;
end;

procedure TPatchySim.Evaluate;
var
  u: Integer;
begin
  VTot := Lung.Prm.VDead;
  for u := 0 to Lung.NU - 1 do VTot := VTot + V[u];
  Pmus := Musc(T, VTot);
  Ppl := Lung.Trunk.Pcw(VTot) - CmH2O * Pmus;
  if Mode = smFlow then
  begin
    Paw := Lung.SolveFlow(V, Ppl, QSet);
    Q := 0;
    for u := 0 to Lung.NU - 1 do Q := Q + Lung.Qu[u];
  end
  else
  begin
    Lung.Pao := Paw;
    Q := Lung.Solve(V, Ppl);
  end;
  NLim := 0; NClosed := 0;
  for u := 0 to Lung.NU - 1 do
    if Lung.LimU[u] then
    begin
      if Lung.Qu[u] = 0 then Inc(NClosed) else Inc(NLim);
    end;
end;

procedure TPatchySim.Step;
var
  u: Integer;
  v0, q1: array of Double;
begin
  SetLength(v0, Lung.NU); SetLength(q1, Lung.NU);
  for u := 0 to Lung.NU - 1 do
  begin
    v0[u] := V[u]; q1[u] := Lung.Qu[u];
    V[u] := v0[u] - Dt * q1[u] / LitreMM3;
  end;
  T := T + Dt;
  Evaluate;
  for u := 0 to Lung.NU - 1 do
    V[u] := v0[u] - 0.5 * Dt * (q1[u] + Lung.Qu[u]) / LitreMM3;
  Evaluate;
end;

end.
