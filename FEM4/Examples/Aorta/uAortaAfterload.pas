unit uAortaAfterload;

{ The arterial tree (uAortaTree, uArtery1D) as the afterload of the
  finite-element left ventricle (../LeftVentricle): two-way coupling at
  the aortic valve. lvrun --arteries uses it; the units here are the
  ventricle's, mL/s and mmHg.

  THE INTERFACE   The valve's flow enters the tree's inlet junction (the
  ascending aorta's first node, with the coronaries' bed), and the
  pressure there is what the valve and so the ventricle work against. It
  replaces the ventricle model's root compliance, inertance,
  characteristic impedance and Windkessel altogether.

  WITHIN A VENTRICLE STEP   The ventricle is implicit (backward Euler,
  steps of about 2 ms) and asks many times, inside its Newton iteration,
  what the root pressure would be for a trial valve flow. RootPressure
  answers with the tree's own inlet equations (TArterialTree.Step):

      A u = Q - G (p - Pc),   u = W + 4 (c(A) - c0),   p = P0 + beta (sqrt A - sqrt A0)

  solved for the area A, where W is the characteristic variable arriving
  at the inlet from inside the aorta, taken from the tree's state at the
  start of the step. So the local part of the load, the aorta's
  characteristic impedance (nonlinear here), is implicit, and the
  reflected waves are one ventricle step late. They change slowly on
  that scale; LagError is the largest difference between the pressure
  the ventricle was given and the one the tree has for the same flow
  once it has been advanced, and is a fraction of 1 mmHg.

  Once the ventricle has accepted a step, Advance takes the tree over it
  in its own explicit steps (about 0.1 ms), the inflow going linearly
  from the last accepted valve flow to the new one.

  SETTLING   The beds' Windkessels take some twenty beats to reach their
  mean pressure, and a ventricle beat costs about seventy times a tree
  beat. So between ventricle beats Settle runs the tree alone for a
  number of beats on the flow of the beat just done, repeated. Each
  coupled beat then starts from the tree's periodic state for the last
  beat's flow. When the ventricle's beats repeat, that is a periodic
  solution of the coupled system; the beats before it are not a physical
  transient.

  Scale multiplies the valve's flow on its way into the tree (circ_sim's
  "stroke volume x": a smaller ventricle for a smaller body). The
  ventricle then feels the pressure of the scaled flow. }

{$mode delphi}{$H+}

interface

uses
  SysUtils, Math, uArtery1D, uAortaTree;

type
  TAortaAfterload = class
  private
    FInlet: TVessel;
    FW: Double;                 { arriving characteristic at the inlet, extrapolated over the step }
    FWNow, FWPrev: Double;
    FVisc: Double;              { the wall's viscous pressure at the inlet, at the tree's time }      { at the tree's time and one ventricle step before }
    FTa, FTb, FQa, FQb: Double; { the inflow ramp of the step being taken }
    FRecT, FRecQ: array of Double;   { the beat's accepted flows, tree units }
    FNRec: Integer;
    FBeatStart, FReplayStart, FPeriod: Double;
    FReplay: Boolean;
    FHint: Integer;
    function Inflow(t: Double): Double;
    procedure FreezeInlet(Fresh: Boolean);
    procedure RunTo(tEnd: Double);
  public
    Sim: TAortaSim;             { set its parameters before Start }
    Scale: Double;
    WallViscous: Boolean;       { add the wall's viscous pressure at the root [True] }
    Extrapolate: Boolean;       { the arriving wave, linearly over the coming step [True] }
    LagError: Double;           { mmHg, largest since BeginBeat }
    TreeSteps: Integer;
    constructor Create;
    destructor Destroy; override;
    procedure Start(APeriod: Double);
    procedure BeginBeat;
    { pressure at the root, mmHg, for the valve flow Q, mL/s }
    function RootPressure(Q: Double): Double;
    { the ventricle accepted a step of dt ending with valve flow Q }
    procedure Advance(dt, Q: Double);
    { the tree alone for Beats periods on the last beat's flow }
    procedure Settle(Beats: Integer);
    function RUsed: Double;
  end;

implementation

constructor TAortaAfterload.Create;
begin
  inherited Create;
  Sim := TAortaSim.Create;
  Scale := 1;
  Extrapolate := True;
  WallViscous := True;
end;

destructor TAortaAfterload.Destroy;
begin
  Sim.Free;
  inherited Destroy;
end;

procedure TAortaAfterload.Start(APeriod: Double);
begin
  FPeriod := APeriod;
  Sim.MeanP := 0;   { the resistance is RTotal x RFactor: the flow is not known beforehand }
  Sim.BuildTree;
  Sim.Tree.Inflow := Inflow;
  FInlet := Sim.Tree.FindVessel('ascending aorta');
  FQa := 0; FQb := 0; FTa := 0; FTb := 0;
  FReplay := False;
  FreezeInlet(True);
  BeginBeat;
end;

function TAortaAfterload.RUsed: Double;
begin
  Result := Sim.RUsed;
end;

procedure TAortaAfterload.FreezeInlet(Fresh: Boolean);
begin
  FWNow := FInlet.Q[0] / FInlet.A[0] - 4 * (FInlet.Speed(0) - FInlet.C0[0]);
  if Fresh then FWPrev := FWNow;
  if Extrapolate then FW := 2 * FWNow - FWPrev else FW := FWNow;
  FWPrev := FWNow;
  if FInlet.Viscous and WallViscous then FVisc := FInlet.ViscousPressure(0) else FVisc := 0;
end;

procedure TAortaAfterload.BeginBeat;
begin
  FBeatStart := Sim.Tree.Time;
  FNRec := 0;
  if Length(FRecT) = 0 then
  begin
    SetLength(FRecT, 1024); SetLength(FRecQ, 1024);
  end;
  FRecT[0] := 0; FRecQ[0] := FQb; FNRec := 1;
  LagError := 0;
  TreeSteps := 0;
end;

function TAortaAfterload.RootPressure(Q: Double): Double;
var
  A, h, f, f1, dA, bet, a0, c0, G, Pc, P0: Double;
  it: Integer;

  function Res(x: Double): Double;
  var
    c, u, p: Double;
  begin
    c := Sqrt(bet * Sqrt(x) / (2 * Rho));
    u := FW + 4 * (c - c0);
    p := P0 + bet * (Sqrt(x) - Sqrt(a0));
    Result := Scale * Q - x * u - G * (p - Pc);
  end;

begin
  bet := FInlet.Beta[0]; a0 := FInlet.A0[0]; c0 := FInlet.C0[0];
  G := Sim.Tree.J[FInlet.JIn].G; Pc := Sim.Tree.J[FInlet.JIn].Pc; P0 := Sim.Tree.P0;
  A := FInlet.A[0];
  for it := 1 to 50 do
  begin
    f := Res(A);
    h := 1e-7 * A;
    f1 := Res(A + h);
    dA := -f * h / (f1 - f);
    A := A + dA;
    if A <= 0 then raise Exception.Create('RootPressure : the aortic root collapsed');
    if Abs(dA) < 1e-14 * A then Break;
  end;
  Result := (P0 + bet * (Sqrt(A) - Sqrt(a0)) + FVisc) / mmHg;
end;

function TAortaAfterload.Inflow(t: Double): Double;
var
  tau, f: Double;
begin
  if FReplay then
  begin
    tau := t - FReplayStart;
    tau := tau - FPeriod * Floor(tau / FPeriod);
    if FRecT[FHint] > tau then FHint := 0;
    while (FHint < FNRec - 2) and (FRecT[FHint + 1] < tau) do Inc(FHint);
    f := (tau - FRecT[FHint]) / (FRecT[FHint + 1] - FRecT[FHint]);
    Result := FRecQ[FHint] + EnsureRange(f, 0, 1) * (FRecQ[FHint + 1] - FRecQ[FHint]);
  end
  else if FTb > FTa then
    Result := FQa + (FQb - FQa) * EnsureRange((t - FTa) / (FTb - FTa), 0, 1)
  else
    Result := FQb;
end;

procedure TAortaAfterload.RunTo(tEnd: Double);
var
  dt: Double;
  n: Integer;
begin
  while Sim.Tree.Time < tEnd - 1e-12 do
  begin
    dt := Sim.Tree.StableDt(Sim.CFL);
    n := Ceil((tEnd - Sim.Tree.Time) / dt - 1e-9);
    dt := (tEnd - Sim.Tree.Time) / n;
    Sim.Tree.Step(dt);
    Inc(TreeSteps);
  end;
end;

procedure TAortaAfterload.Advance(dt, Q: Double);
var
  given, now_: Double;
begin
  given := RootPressure(Q);
  FTa := Sim.Tree.Time; FTb := FTa + dt;
  FQa := FQb; FQb := Scale * Q;
  FReplay := False;
  RunTo(FTb);
  FreezeInlet(False);
  { the pressure the tree now has for that flow }
  now_ := FW; FW := FWNow;
  LagError := Max(LagError, Abs(RootPressure(Q) - given));
  FW := now_;
  if FNRec = Length(FRecT) then
  begin
    SetLength(FRecT, 2 * FNRec); SetLength(FRecQ, 2 * FNRec);
  end;
  FRecT[FNRec] := Sim.Tree.Time - FBeatStart; FRecQ[FNRec] := FQb;
  Inc(FNRec);
end;

procedure TAortaAfterload.Settle(Beats: Integer);
begin
  if (Beats <= 0) or (FNRec < 2) then Exit;
  FReplay := True; FHint := 0;
  FReplayStart := Sim.Tree.Time;
  { the record runs from 0 to the period; close it on itself }
  FRecT[FNRec - 1] := FPeriod;
  RunTo(FReplayStart + Beats * FPeriod);
  FReplay := False;
  FQb := FRecQ[FNRec - 1];
  FreezeInlet(True);
end;

end.
