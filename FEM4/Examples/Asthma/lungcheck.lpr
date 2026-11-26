program lungcheck;

{ Checks of the whole-lung model (uLungModel) against closed forms.

  1. A near-rigid tree at a tiny flow (Reynolds term off, no upper
     airway, no lining): resistance against the sum over generations of
     Poiseuille's 8 pi mu L Ka / (N A^2).
  2. The fitted alveolus: recoil at TLC is PTLC air-filled and
     PSalineTLC saline-filled.
  3. Passive emptying of the near-rigid lung from 5 uL above FRC with
     no muscle pressure: against exp(-t/(R C)), R from check 1 and C the
     local compliance of lung and chest wall in series.
  4. The flow solver: at a flow it returns, the expiratory march ends at
     the mouth at 0; and with the normal walls, isovolume flow stops
     rising with pleural pressure once it is limited (to 0.5 %).

  Build:  fpc -O3 -FUlib -Fu../../../newVM -Fi../../../newVM lungcheck.lpr }

{$mode delphi}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Classes, Math, cblas, newVM, uTubeLaw, uAirwayRing, uAlveolus, uLungModel;

var
  Fails: Integer = 0;

procedure Check(const What: string; Got, Want, Tol: Double);
var
  e: Double;
  ok: Boolean;
  r: string;
begin
  if Want <> 0 then e := Abs(Got / Want - 1) else e := Abs(Got);
  ok := e <= Tol;
  if not ok then Inc(Fails);
  if ok then r := 'ok' else r := 'FAIL';
  Writeln(Format('  %-52s %12.6g  want %12.6g  err %.1e  %s', [What, Got, Want, e, r]));
end;

type
  TZero = class
    function P(t, V: Double): Double;
  end;

function TZero.P(t, V: Double): Double;
begin
  Result := 0;
end;

var
  Prm: TLungParams;
  Alv: TAlveolusParams;
  Rigid: TTubeLaw;
  RL, WL: array[0..NGen - 1] of TTubeLaw;
  Laws: array[0..NWall - 1] of TTubeLaw;
  Lung: TLung;
  Sim: TLungSim;
  Z: TZero;
  M: TAlveolus;
  g, i: Integer;
  Rp, R, A, frc, C, dv, v0, tau, ppl, q, qLim, qHi, p: Double;
  ch: Boolean;
  notes: string;
  pp, aa: array of Double;
begin
  InitializeCBLAS;
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  DefaultFormatSettings.DecimalSeparator := '.';
  Prm := DefaultLungParams;
  Alv := FitAlveolus(Prm.PTLC * CmH2O, Prm.PSalineTLC * CmH2O, 0.126);

  Writeln('1. Near-rigid tree at a tiny flow against Poiseuille');
  SetLength(pp, 3); SetLength(aa, 3);
  for i := 0 to 2 do
  begin
    pp[i] := (-200 + 200 * i) * CmH2O; aa[i] := 1 + 1e-7 * pp[i];
  end;
  Rigid := TTubeLaw.Create;
  Rigid.SetTable(pp, aa);
  for g := 0 to NGen - 1 do begin WL[g] := Rigid; RL[g] := Rigid; end;
  Prm.Gamma := 0; Prm.Kb := 0; Prm.Ka := 1; Prm.K1 := 0; Prm.K2 := 0;
  Lung := TLung.Create(Prm, WL, RL, 0, Alv);
  Rp := 0;
  for g := 0 to NGen - 1 do
  begin
    A := Lung.Gens[g].Gas.Area(5 * CmH2O);
    Rp := Rp + 8 * Pi * Prm.Visc * WeibelLen[g] / (Lung.Gens[g].N * A * A);
  end;
  { at 1e-5 cmH2O: the junctions' speed-up losses, quadratic in the flow,
    are 1 % of the drop at Resistance's own 1e-3 cmH2O }
  p := 1e-5 * CmH2O;
  R := p / Lung.Flow(p, -5 * CmH2O, 0);
  Check('resistance, cmH2O s/L', R / CmH2O * LitreMM3, Rp / CmH2O * LitreMM3, 1e-3);

  Writeln('2. Fitted alveolus at TLC');
  M := TAlveolus.Create(Alv);
  v0 := M.UnstressedVolume * Power(0.126 / Alv.R0, 3);
  M.MoveTo(amVolume, v0);
  Check('air-filled recoil, cmH2O', M.P / CmH2O, Prm.PTLC, 1e-4);
  M.Free;
  Alv.Surf := sfNone;
  M := TAlveolus.Create(Alv);
  M.MoveTo(amVolume, v0);
  Check('saline-filled recoil, cmH2O', M.P / CmH2O, Prm.PSalineTLC, 1e-4);
  M.Free;
  Alv.Surf := sfDeflation;
  Check('lung recoil at TLC, cmH2O', Lung.Pel(Prm.TLC) / CmH2O, Prm.PTLC, 1e-3);

  Writeln('3. Passive emptying against exp(-t/RC)');
  frc := Lung.StaticVolume(0);
  dv := 1e-4;
  C := 2 * dv / (Lung.Pel(frc + dv) + Lung.Pcw(frc + dv) - Lung.Pel(frc - dv) - Lung.Pcw(frc - dv));
  tau := Rp * LitreMM3 * C;
  Z := TZero.Create;
  { 5 uL, so that the flow (about 0.5 mL/s) stays where the junctions'
    quadratic losses are negligible }
  Sim := TLungSim.Create(Lung, Z.P, frc + 5e-6, tau / 200);
  while Sim.T < tau - 1e-12 do Sim.Step;
  Check('volume above FRC after one time constant, uL', 1e6 * (Sim.V - frc), 5 * Exp(-1), 2e-3);
  Writeln(Format('    (R %.3f cmH2O s/L, C %.3f L/cmH2O, RC %.4f s)', [Rp / CmH2O * LitreMM3, C * CmH2O, tau]));
  Sim.Free;
  Z.Free;
  Lung.Free;
  Rigid.Free;

  Writeln('4. Flow solver, normal walls');
  Prm := DefaultLungParams;
  BuildWallLaws(NormalAsthma, Laws, notes);
  for g := 0 to NGen - 1 do begin WL[g] := Laws[GenWall[g]]; RL[g] := Laws[GenWall[g]]; end;
  Lung := TLung.Create(Prm, WL, RL, 1, Alv);
  v0 := 3.5;
  ppl := -2 * CmH2O;
  q := Lung.Flow(ppl + Lung.Pel(v0), ppl, 0);
  p := Lung.MouthPressure(q, ppl + Lung.Pel(v0), ppl, ch);
  Check('mouth pressure at the returned flow, cmH2O', p / CmH2O, 0, 1e-6);
  ppl := -Lung.Pel(v0) - 3 * CmH2O;
  q := Lung.Flow(ppl + Lung.Pel(v0), ppl, 0);
  p := Lung.AlveolarEnd(-q, ppl, ch) - (ppl + Lung.Pel(v0));
  Check('inspiring: alveolar-end pressure error, cmH2O', p / CmH2O, 0, 1e-6);
  qLim := Lung.Flow(20 * CmH2O + Lung.Pel(v0), 20 * CmH2O, 0);
  ch := Lung.Limited;
  qHi := Lung.Flow(60 * CmH2O + Lung.Pel(v0), 60 * CmH2O, qLim);
  Writeln(Format('    at %.1f L: flow %.2f L/s at Ppl 20 cmH2O (limited %s, choke in generation %d), %.2f at 60',
    [v0, qLim / LitreMM3, BoolToStr(ch, True), Lung.ChokeGen, qHi / LitreMM3]));
  Check('isovolume flow at Ppl 60 / at 20', qHi / qLim, 1, 5e-3);
  Lung.Free;
  for i := 0 to NWall - 1 do Laws[i].Free;

  Writeln;
  if Fails = 0 then Writeln('All checks passed.')
  else
  begin
    Writeln(Fails, ' check(s) FAILED.');
    Halt(1);
  end;
end.
