unit uCirculation;

{ Stage 10: a lumped closed-loop circulation with both ventricles, the
  septum and the pericardium, set in the thorax so that the pleural and
  alveolar pressures of the breathing lung act on it. Pressures mmHg,
  volumes mL (stressed volumes: above each compartment's unstressed
  volume), flows mL/s, time s.

  THE HEART is the minimal model of Smith, Chase, Nokes, Shaw and Wake
  (Med Eng Phys 2004;26:131), whose ventricular interaction follows
  Chung et al. (1997) and Olansen et al. (2000). Each free wall and the
  septum is a time-varying elastance between an end-systolic line and
  an exponential end-diastolic curve,
    P(V) = e(t) Ees (V - Vd) + (1 - e(t)) P0 (exp(lambda (V - V0)) - 1),
  with the same activation e(t) = exp(-B ((tc - C)/s)^2) for all three
  (tc the time in the cardiac cycle; B 80, C 0.27 s at 80 /min; the
  width and the peak's time are scaled by s = sqrt(T / 0.75), so
  systole shortens less than diastole as the rate rises - assumed).
  The septum's volume Vspt (its displacement towards the right
  ventricle) satisfies
    Pspt(Vspt) = Plvf(Vlv - Vspt) - Prvf(Vrv + Vspt),
  solved by Newton within a bracket at every evaluation: a fuller right
  ventricle pushes the septum left and stiffens the left ventricle's
  filling - direct ventricular interdependence. Both ventricles sit in
  the pericardium, P_pcd = P0 (exp(lambda (Vlv + Vrv - V0)) - 1), which
  sits in the pleural space:
    Plv = Plvf + P_pcd + Ppl,   Prv = Prvf + P_pcd + Ppl.
  Smith's parameters (Table 1, human) are used for the heart and valves.

  THE VESSELS are compliances. Smith's single aorta, vena cava,
  pulmonary artery and pulmonary vein are kept, but the aorta and vena
  cava are each split at the thoracic inlet, because which side of the
  chest wall a compartment lies on is the whole point here:
    AO  thoracic aorta, in the chest (Ppl around it);
    SA  systemic arteries, outside (atmospheric) - the cuff is here;
    SV  systemic veins, outside;
    VC  thoracic vena cava with the right atrium, in the chest;
    PA, PU  pulmonary artery, pulmonary veins with the left atrium, in
        the chest. (Smith's model has no atria.)
  Smith's arterial compliance (1/0.6913 = 1.45 mL/mmHg) is shared 0.6
  thoracic, 0.85 systemic, and his venous one (1/0.0059 = 170) 150
  outside and 20 inside (assumed); a small resistance R_ao joins the
  two arterial compartments and R_vr is the resistance to venous return.

  VENOUS RETURN through the thoracic inlet is a Starling resistor: the
  great veins collapse where they enter the chest once the pressure
  inside falls below the pressure around them (PCollapse, atmospheric),
    Qvr = (Psv - max(Pvc, PCollapse)) / R_vr,
  so a deep inspiration draws more blood into the chest only until the
  veins collapse (Guyton's plateau).

  PULMONARY FLOW passes the alveoli, whose vessels are squeezed by the
  alveolar pressure, not the pleural one: the lung is divided into
  horizontal bands (upright, so the vascular pressures carry a
  hydrostatic offset rho g (y - H/2) about the heart at mid-height), and
  in each band of conductance 1/(NB R_pul)
    zone 1  Ppa + h < Palv:           no flow;
    zone 2  Ppu + h < Palv < Ppa + h: (Ppa + h - Palv) g;
    zone 3  otherwise:                (Ppa - Ppu) g
  (West, J Appl Physiol 1964). Without bands it is a plain resistance.

  Valves are ideal diodes with Smith's resistances, without inertance. }

{$mode delphi}{$H+}

interface

uses
  SysUtils, Math;

const
  NComp = 8;
  cLV = 0; cAO = 1; cSA = 2; cSV = 3; cVC = 4; cRV = 5; cPA = 6; cPU = 7;
  CompName: array[0..NComp - 1] of string = ('LV', 'AO', 'SA', 'SV', 'VC', 'RV', 'PA', 'PU');
  MmHgPerCmH2O = 0.735559;
  MaxBands = 16;

type
  TChamber = record
    Ees, Vd, P0, Lam, V0: Double;
  end;

  TCircParams = record
    HR: Double;                        { /min }
    LVF, RVF, SPT: TChamber;
    PcdP0, PcdLam, PcdV0: Double;
    C: array[0..NComp - 1] of Double;  { mL/mmHg, vessels only }
    Rav, Rao, Rsys, Rvr, Rtc, Rpv, Rpul, Rmt: Double;  { mmHg s/mL }
    PCollapse: Double;                 { mmHg }
    VStressed: Double;                 { mL }
    RhoG: Double;                      { mmHg/cm }
    Height: Double;                    { cm, the lung's height }
    Septum, Pericardium: Boolean;      { False: rigid septum / no pericardium }
    VeinsInChest: Boolean;             { True: the systemic veins see Ppl - PplMean too }
    PplMean: Double;                   { mmHg, for VeinsInChest }
  end;

  { the thorax at time t: pleural pressure at mid-height and the alveolar
    pressure in each of NBands horizontal bands, top first; mmHg }
  TThoraxFn = procedure(t: Double; var Ppl: Double; var Palv: array of Double) of object;

  TCirculation = class
  public
    Prm: TCircParams;
    V: array[0..NComp - 1] of Double;
    T: Double;
    Vspt: Double;
    Thorax: TThoraxFn;     { nil: Ppl = PplConst, plain pulmonary resistance }
    NBands: Integer;
    PplConst: Double;
    { filled by Evaluate }
    P: array[0..NComp - 1] of Double;   { absolute (against atmosphere) }
    Qav, Qao, Qsys, Qvr, Qtc, Qpv, Qpul, Qmt: Double;
    Ppl, Ppcd, Act: Double;
    Palv: array[0..MaxBands - 1] of Double;
    BandQ: array[0..MaxBands - 1] of Double;
    constructor Create(const APrm: TCircParams);
    function Activation(at: Double): Double;
    function Period: Double;
    function SeptumVolume(Vlv, Vrv, e, Guess: Double): Double;
    function ChamberP(const Ch: TChamber; Vol, e: Double): Double;
    function PulmonaryFlow(Ppa, Ppu: Double): Double;
    procedure Evaluate(at: Double; const Vs: array of Double; var dV: array of Double);
    procedure Step(Dt: Double);
    function TotalVolume: Double;
    procedure Fill;
  end;

function DefaultCircParams: TCircParams;

implementation

function DefaultCircParams: TCircParams;
var
  i: Integer;
begin
  Result.HR := 80;
  with Result.LVF do begin Ees := 2.8798; Vd := 0; P0 := 0.1203; Lam := 0.033; V0 := 0; end;
  with Result.RVF do begin Ees := 0.585; Vd := 0; P0 := 0.2157; Lam := 0.023; V0 := 0; end;
  with Result.SPT do begin Ees := 48.754; Vd := 2; P0 := 1.1101; Lam := 0.435; V0 := 2; end;
  Result.PcdP0 := 0.5003; Result.PcdLam := 0.03; Result.PcdV0 := 200;
  for i := 0 to NComp - 1 do Result.C[i] := 0;
  Result.C[cAO] := 0.6; Result.C[cSA] := 0.85;
  Result.C[cSV] := 150; Result.C[cVC] := 20;
  Result.C[cPA] := 1 / 0.369; Result.C[cPU] := 20;
  Result.Rav := 0.018; Result.Rao := 0.02; Result.Rsys := 0.95; Result.Rvr := 0.04;
  Result.Rtc := 0.0237; Result.Rpv := 0.0055; Result.Rpul := 0.1552; Result.Rmt := 0.0158;
  Result.PCollapse := 0;
  Result.VStressed := 1800;
  Result.RhoG := 1.06 * 0.735559;   { blood, 1.06 g/mL }
  Result.Height := 24;
  Result.Septum := True; Result.Pericardium := True; Result.VeinsInChest := False; Result.PplMean := 0;
end;

constructor TCirculation.Create(const APrm: TCircParams);
begin
  inherited Create;
  Prm := APrm;
  T := 0; Vspt := Prm.SPT.Vd;
  Thorax := nil; NBands := 0; PplConst := -4;
  Fill;
end;

function TCirculation.Period: Double;
begin
  Result := 60 / Prm.HR;
end;

function TCirculation.Activation(at: Double): Double;
var
  Tc, s, tc_: Double;
begin
  Tc := Period;
  s := Sqrt(Tc / 0.75);
  tc_ := at - Tc * Floor(at / Tc);
  Result := Exp(-80 * Sqr((tc_ - 0.27 * s) / s));
end;

function TCirculation.ChamberP(const Ch: TChamber; Vol, e: Double): Double;
begin
  Result := e * Ch.Ees * (Vol - Ch.Vd) + (1 - e) * Ch.P0 * (Exp(Ch.Lam * (Vol - Ch.V0)) - 1);
end;

function TCirculation.SeptumVolume(Vlv, Vrv, e, Guess: Double): Double;
{ f(y) = Pspt(y) - Plvf(Vlv - y) + Prvf(Vrv + y) rises with y (each term
  does), so its one root is bracketed; Newton steps that leave the
  bracket, or fail to halve |f|, are replaced by bisection }
var
  lo, hi, x, f, df, fOld, xn: Double;
  it: Integer;

  procedure FD(y: Double; var fv, dv: Double);
  var
    a, b, c: Double;
  begin
    a := Exp(Prm.SPT.Lam * (y - Prm.SPT.V0));
    b := Exp(Prm.LVF.Lam * (Vlv - y - Prm.LVF.V0));
    c := Exp(Prm.RVF.Lam * (Vrv + y - Prm.RVF.V0));
    fv := e * Prm.SPT.Ees * (y - Prm.SPT.Vd) + (1 - e) * Prm.SPT.P0 * (a - 1)
        - e * Prm.LVF.Ees * (Vlv - y - Prm.LVF.Vd) - (1 - e) * Prm.LVF.P0 * (b - 1)
        + e * Prm.RVF.Ees * (Vrv + y - Prm.RVF.Vd) + (1 - e) * Prm.RVF.P0 * (c - 1);
    dv := e * (Prm.SPT.Ees + Prm.LVF.Ees + Prm.RVF.Ees)
        + (1 - e) * (Prm.SPT.P0 * Prm.SPT.Lam * a + Prm.LVF.P0 * Prm.LVF.Lam * b + Prm.RVF.P0 * Prm.RVF.Lam * c);
  end;

begin
  if not Prm.Septum then Exit(Prm.SPT.Vd);
  lo := -60; hi := 60;
  x := EnsureRange(Guess, lo, hi);
  fOld := Infinity;
  for it := 1 to 200 do
  begin
    FD(x, f, df);
    if f > 0 then hi := x else lo := x;
    if (Abs(f) < 1e-10) or (hi - lo < 1e-12) then Break;
    xn := x - f / df;
    if (xn <= lo) or (xn >= hi) or (Abs(f) > 0.5 * fOld) then xn := 0.5 * (lo + hi);
    fOld := Abs(f);
    x := xn;
  end;
  Result := x;
end;

function TCirculation.PulmonaryFlow(Ppa, Ppu: Double): Double;
var
  k: Integer;
  g, h, up, dn, q: Double;
begin
  if NBands = 0 then
  begin
    Result := (Ppa - Ppu) / Prm.Rpul;
    Exit;
  end;
  g := 1 / (NBands * Prm.Rpul);
  Result := 0;
  for k := 0 to NBands - 1 do
  begin
    h := Prm.RhoG * ((k + 0.5) / NBands - 0.5) * Prm.Height;
    up := Ppa + h; dn := Ppu + h;
    if up <= Palv[k] then q := 0
    else if dn < Palv[k] then q := (up - Palv[k]) * g
    else q := (up - dn) * g;
    BandQ[k] := q;
    Result := Result + q;
  end;
end;

procedure TCirculation.Evaluate(at: Double; const Vs: array of Double; var dV: array of Double);
var
  e, pc, pin: Double;
  k: Integer;
begin
  if Assigned(Thorax) then Thorax(at, Ppl, Palv)
  else
  begin
    Ppl := PplConst;
    for k := 0 to MaxBands - 1 do Palv[k] := 0;
  end;
  e := Activation(at);
  Act := e;
  Vspt := SeptumVolume(Vs[cLV], Vs[cRV], e, Vspt);
  if Prm.Pericardium then
    Ppcd := Prm.PcdP0 * (Exp(Prm.PcdLam * (Vs[cLV] + Vs[cRV] - Prm.PcdV0)) - 1)
  else Ppcd := 0;
  P[cLV] := ChamberP(Prm.LVF, Vs[cLV] - Vspt, e) + Ppcd + Ppl;
  P[cRV] := ChamberP(Prm.RVF, Vs[cRV] + Vspt, e) + Ppcd + Ppl;
  P[cAO] := Vs[cAO] / Prm.C[cAO] + Ppl;
  P[cSA] := Vs[cSA] / Prm.C[cSA];
  if Prm.VeinsInChest then pin := Ppl - Prm.PplMean else pin := 0;
  P[cSV] := Vs[cSV] / Prm.C[cSV] + pin;
  P[cVC] := Vs[cVC] / Prm.C[cVC] + Ppl;
  P[cPA] := Vs[cPA] / Prm.C[cPA] + Ppl;
  P[cPU] := Vs[cPU] / Prm.C[cPU] + Ppl;
  Qav := Max(0, P[cLV] - P[cAO]) / Prm.Rav;
  Qao := (P[cAO] - P[cSA]) / Prm.Rao;
  Qsys := (P[cSA] - P[cSV]) / Prm.Rsys;
  pc := Prm.PCollapse + pin;
  if P[cVC] >= pc then Qvr := (P[cSV] - P[cVC]) / Prm.Rvr
  else Qvr := Max(0, P[cSV] - pc) / Prm.Rvr;
  Qtc := Max(0, P[cVC] - P[cRV]) / Prm.Rtc;
  Qpv := Max(0, P[cRV] - P[cPA]) / Prm.Rpv;
  Qpul := PulmonaryFlow(P[cPA], P[cPU]);
  Qmt := Max(0, P[cPU] - P[cLV]) / Prm.Rmt;
  dV[cLV] := Qmt - Qav;
  dV[cAO] := Qav - Qao;
  dV[cSA] := Qao - Qsys;
  dV[cSV] := Qsys - Qvr;
  dV[cVC] := Qvr - Qtc;
  dV[cRV] := Qtc - Qpv;
  dV[cPA] := Qpv - Qpul;
  dV[cPU] := Qpul - Qmt;
end;

procedure TCirculation.Step(Dt: Double);
var
  k1, k2, k3, k4, y: array[0..NComp - 1] of Double;
  i: Integer;
begin
  Evaluate(T, V, k1);
  for i := 0 to NComp - 1 do y[i] := V[i] + 0.5 * Dt * k1[i];
  Evaluate(T + 0.5 * Dt, y, k2);
  for i := 0 to NComp - 1 do y[i] := V[i] + 0.5 * Dt * k2[i];
  Evaluate(T + 0.5 * Dt, y, k3);
  for i := 0 to NComp - 1 do y[i] := V[i] + Dt * k3[i];
  Evaluate(T + Dt, y, k4);
  for i := 0 to NComp - 1 do V[i] := V[i] + Dt / 6 * (k1[i] + 2 * k2[i] + 2 * k3[i] + k4[i]);
  T := T + Dt;
  Evaluate(T, V, k1);   { leaves P, Q at the new time }
end;

function TCirculation.TotalVolume: Double;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to NComp - 1 do Result := Result + V[i];
end;

procedure TCirculation.Fill;
var
  i: Integer;
  s, vv: Double;
begin
  { ventricles at 100 mL, the vessels at a common pressure sharing the rest }
  V[cLV] := 100; V[cRV] := 100;
  s := 0;
  for i := 0 to NComp - 1 do if (i <> cLV) and (i <> cRV) then s := s + Prm.C[i];
  vv := Prm.VStressed - 200;
  for i := 0 to NComp - 1 do if (i <> cLV) and (i <> cRV) then V[i] := vv * Prm.C[i] / s;
end;

end.
