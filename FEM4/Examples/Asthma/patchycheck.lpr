program patchycheck;

{ Checks of the patchy lung (uPatchyLung).

  1. With no heterogeneity and no gravity every unit is the same, so the
     patchy lung must give the symmetric lung's flow (TLung.Flow, the
     whole tree marched directly) at every state: tidal expiration and
     inspiration, a forced expiration where the flow is limited, low
     volume. Tests the unit tables, their inversion and the solve for
     the trunk's pressure. Moderate asthma, so the linings matter.
  2. The same with gravity: the static state's units hold their recoil
     against their own pleural pressure, the chest wall balances, and
     the top units are bigger than the bottom ones.
  3. Patchy, with the mouth flow held at zero by equal alveolar
     pressures apart from two units: the flows sum to the mouth flow.
  4. Activation mode (stage 4's levels): every unit at the case's
     activation, no spread or gravity, again equals the symmetric lung;
     and moving units between levels moves only their own flows.

  Build:  fpc -O3 -FUlib -Fu../../../newVM -Fi../../../newVM patchycheck.lpr }

{$mode delphi}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Classes, Math, cblas, newVM, uTubeLaw, uAirwayRing, uAlveolus, uLungModel, uPatchyLung;

var
  Fails: Integer = 0;

procedure Check(const What: string; Got, Want, Tol: Double);
var
  e: Double;
  r: string;
begin
  if Want <> 0 then e := Abs(Got / Want - 1) else e := Abs(Got);
  if e <= Tol then r := 'ok' else begin r := 'FAIL'; Inc(Fails); end;
  Writeln(Format('  %-56s %12.6g  want %12.6g  err %.1e  %s', [What, Got, Want, e, r]));
end;

var
  Prm: TLungParams;
  Alv: TAlveolusParams;
  RefLaws: array[0..NWall - 1] of TTubeLaw;
  PP: TPatchyParams;
  A: TAsthma;
  L: TPatchyLung;
  V: array of Double;
  notes: string;
  i, u, top, bot: Integer;
  vl, ppl, q, qs, palv, sum, ppl0, vt: Double;
  vtop, vbot: Double;
const
  States: array[0..5, 0..1] of Double = (
    (3.0, -5.0),    { at rest, a little expiration }
    (3.3, -8.5),    { inspiring }
    (3.5, -3.0),    { expiring }
    (5.5, 40.0),    { forced, high volume }
    (2.5, 30.0),    { forced, low volume }
    (4.0, -12.0));  { inspiring hard }

begin
  InitializeCBLAS;
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  DefaultFormatSettings.DecimalSeparator := '.';
  Prm := DefaultLungParams;
  Alv := FitAlveolus(Prm.PTLC * CmH2O, Prm.PSalineTLC * CmH2O, 0.126);
  BuildWallLaws(NormalAsthma, RefLaws, notes);
  A.Act := 0.3; A.Thick := 1.5; A.Mucus := 1.5;

  Writeln('1. Uniform patchy lung against the symmetric lung, moderate asthma');
  PP := DefaultPatchyParams;
  PP.Sigma := 0; PP.Gravity := 0;
  L := TPatchyLung.Create(Prm, PP, A, Alv, RefLaws);
  SetLength(V, L.NU);
  for i := 0 to High(States) do
  begin
    vl := States[i, 0]; ppl := States[i, 1] * CmH2O;
    for u := 0 to L.NU - 1 do V[u] := (vl - Prm.VDead) / L.NU;
    q := L.Solve(V, ppl);
    palv := ppl + L.Trunk.Pel(vl);
    qs := L.Trunk.Flow(palv, ppl, 0);
    Check(Format('V %.1f L, Ppl %5.1f cmH2O: flow, L/s (limited %s)', [vl, States[i, 1],
      BoolToStr(L.Trunk.Limited or L.TrunkLimited or L.LimU[0], True)]), q / LitreMM3, qs / LitreMM3, 5e-3);
  end;
  L.Free;

  Writeln('2. Static state with gravity');
  PP := DefaultPatchyParams;
  PP.Sigma := 0;
  L := TPatchyLung.Create(Prm, PP, A, Alv, RefLaws);
  SetLength(V, L.NU);
  ppl0 := L.StaticState(0, V);
  vt := Prm.VDead;
  for u := 0 to L.NU - 1 do vt := vt + V[u];
  Check('chest wall recoil at the lung volume = pleural pressure', L.Trunk.Pcw(vt) / CmH2O, ppl0 / CmH2O, 1e-6);
  vtop := 0; vbot := 0; top := 0; bot := 0;
  for u := 0 to L.NU - 1 do
  begin
    Check(Format('unit %d: recoil + own pleural pressure, cmH2O', [u]), (L.UnitPel(V[u]) + ppl0 + L.DPpl[u]) / CmH2O, 0, 1e-6);
    if u > 2 then Break;
  end;
  for u := 0 to L.NU - 1 do
  begin
    if L.PY[u] < 0.5 * PP.Height then begin vtop := vtop + V[u]; Inc(top); end
    else begin vbot := vbot + V[u]; Inc(bot); end;
  end;
  Writeln(Format('  FRC %.3f L (uniform %.3f); upper half units %.1f mL, lower %.1f mL', [vt,
    L.Trunk.StaticVolume(0), 1000 * vtop / top, 1000 * vbot / bot]));
  if not (vtop / top > vbot / bot) then begin Writeln('  FAIL: upper units not bigger'); Inc(Fails); end;
  L.Free;

  Writeln('3. Patchy: flows add up');
  PP := DefaultPatchyParams;
  L := TPatchyLung.Create(Prm, PP, A, Alv, RefLaws);
  SetLength(V, L.NU);
  L.StaticState(0, V);
  V[3] := V[3] * 1.2; V[200] := V[200] * 0.9;
  q := L.Solve(V, -5.4 * CmH2O);
  sum := 0;
  for u := 0 to L.NU - 1 do sum := sum + L.Qu[u];
  Check('sum of unit flows = mouth flow, mL/s', sum / 1000, q / 1000, 1e-12);
  Writeln(Format('  mouth %.3f mL/s; unit 3 %.3f, unit 200 %.3f; Pc %.4f cmH2O', [q / 1000, L.Qu[3] / 1000,
    L.Qu[200] / 1000, L.Pc / CmH2O]));
  L.Free;
  Writeln('4. Activation levels against the symmetric lung');
  PP := DefaultPatchyParams;
  PP.Sigma := 0; PP.Gravity := 0; PP.ActMode := True; PP.DS := 0.05; PP.SMax := 0.9;
  L := TPatchyLung.Create(Prm, PP, A, Alv, RefLaws);
  SetLength(V, L.NU);
  Check('every unit at level 6 (activation 0.3)', L.Level[17], 6, 0);
  for i := 0 to 2 do
  begin
    vl := States[i, 0]; ppl := States[i, 1] * CmH2O;
    for u := 0 to L.NU - 1 do V[u] := (vl - Prm.VDead) / L.NU;
    q := L.Solve(V, ppl);
    qs := L.Trunk.Flow(ppl + L.Trunk.Pel(vl), ppl, 0);
    Check(Format('V %.1f L, Ppl %5.1f cmH2O: flow, L/s', [vl, States[i, 1]]), q / LitreMM3, qs / LitreMM3, 5e-3);
  end;
  { half the units to activation 0.9: they carry less, the rest more }
  vl := 3.5; ppl := -3 * CmH2O;
  for u := 0 to L.NU - 1 do V[u] := (vl - Prm.VDead) / L.NU;
  q := L.Solve(V, ppl);
  sum := L.Qu[0];
  for u := 0 to L.NU div 2 - 1 do L.Level[u] := 18;
  qs := L.Solve(V, ppl);
  Writeln(Format('  half the units to activation 0.9: mouth flow %.3f -> %.3f L/s; a constricted unit %.2f -> %.2f mL/s, an unchanged one %.2f',
    [q / LitreMM3, qs / LitreMM3, sum / 1000, L.Qu[0] / 1000, L.Qu[L.NU - 1] / 1000]));
  if not ((L.Qu[0] < sum) and (L.Qu[L.NU - 1] > sum) and (qs < q)) then
  begin
    Writeln('  FAIL: constriction did not shift the flow'); Inc(Fails);
  end;
  L.Free;
  for i := 0 to NWall - 1 do RefLaws[i].Free;

  Writeln;
  if Fails = 0 then Writeln('All checks passed.')
  else
  begin
    Writeln(Fails, ' check(s) FAILED.');
    Halt(1);
  end;
end.
