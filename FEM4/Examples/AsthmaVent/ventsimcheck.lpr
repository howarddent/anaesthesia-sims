program ventsimcheck;

{ Checks of uVentSim, headless. Each case runs 40 s and prints its
  breaths, then the monitor:
    1 VC-SIMV + PS, normal lung, paralysed: every breath mandatory at the
      set rate, VTi = set VT;
    2 PC-SIMV + PS, normal lung, paralysed: Paw reaches PEEP + Pinsp;
    3 VC-SIMV + PS, normal lung, breathing 18 /min: mandatory breaths at
      the set rate, the rest pressure supported, no missed efforts;
    4 the same in status asthmaticus (tone 0.8): intrinsic PEEP, missed
      efforts;
    5 CPAP + PS in status asthmaticus;
    6 holds: VC-CMV, asthma, paralysed - plateau and total PEEP;
    7 a change of lung mid-run (salbutamol + heliox);
    8 supine, ventilated: FRC 2.3 L and positive pleural pressure in each
      breath; sitting up mid-run puts both back.
  Cases 1-7 are upright.
  Build:  fpc -O3 -FUlib -Fu../Asthma -Fu../../../newVM -Fi../../../newVM ventsimcheck.lpr }

{$mode delphi}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Math, cblas, newVM, uLungModel, uVentSim;

var
  E: TVentEngine;
  NFail: Integer = 0;

procedure Check(const What: string; OK: Boolean; const Detail: string);
begin
  if OK then Writeln('  ok    ', What, '  ', Detail)
  else begin Writeln('  FAIL  ', What, '  ', Detail); Inc(NFail); end;
end;

procedure RunFor(Sec: Double);
var
  t0: Double;
begin
  t0 := E.T;
  while E.T < t0 + Sec do E.Step;
end;

procedure Show(const Title: string; T0: Double; out NMand, NSpont: Integer; out VTiMand, PpkMax: Double);
var
  i: Integer;
  B: TBreathRec;
begin
  Writeln(Title);
  NMand := 0; NSpont := 0; VTiMand := 0; PpkMax := 0;
  for i := 0 to E.BreathCount - 1 do
  begin
    B := E.Breath(i);
    if B.TStart < T0 then Continue;
    Writeln(Format('    t %6.2f  %-2s %-4s  Ti %.2f  Ppeak %5.1f  VTi %5.0f  VTe %5.0f  EELV %5.0f  VEI %5.0f',
      [B.TStart, KindNames[B.Kind], Copy('    trig', 1 + 4 * Ord(B.Triggered), 4), B.TEndInsp - B.TStart, B.Ppeak, B.VTi, B.VTe, B.EELV, B.VEI]));
    if B.Mandatory then begin Inc(NMand); if B.Done then VTiMand := B.VTi; end else Inc(NSpont);
    PpkMax := Max(PpkMax, B.Ppeak);
  end;
  with E.Mon do
    Writeln(Format('    RR %.1f (spont %.1f)  MV %.2f  Pmean %.1f  EELV %.0f  dyn %.0f  efforts %d missed %d  WOB %.1f  shut %d  Ppl %.1f..%.1f  Pplat %.1f  PEEPtot %.1f  %s',
      [RRTot, RRSpont, MV, Pmean, EELV, DynHyper, Efforts, Missed, WOB, UnitsShut, PplMin, PplMax, Pplat, PEEPtot, Alarm]));
end;

var
  P: TPatientSettings;
  V: TVentSettings;
  nm, ns: Integer;
  vti, ppk: Double;
  tw: QWord;
begin
  InitializeCBLAS;
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  DefaultFormatSettings.DecimalSeparator := '.';
  E := TVentEngine.Create(ExpandFileName('../Asthma/cache'));
  { 1 }
  P := DefaultPatientSettings; P.Supine := False; P.Tone := 0; P.AsthmaWall := False; P.Effort := 0;
  V := DefaultVentSettings; V.Mode := vmVCSIMV; V.Rate := 12; V.VT := 500; V.PEEP := 5;
  E.Reset(P, V);
  tw := GetTickCount64;
  RunFor(40);
  Show('1 VC-SIMV + PS, normal, paralysed', 20, nm, ns, vti, ppk);
  Writeln(Format('    40 s simulated in %.1f s', [(GetTickCount64 - tw) / 1000]));
  Check('all mandatory at 12 /min', (ns = 0) and (nm = 4), Format('%d mandatory, %d spontaneous in 20 s', [nm, ns]));
  Check('VTi = 500 mL', Abs(vti - 500) < 10, Format('%.1f', [vti]));
  { 2 }
  V.Mode := vmPCSIMV; V.PInsp := 15;
  E.Reset(P, V);
  RunFor(40);
  Show('2 PC-SIMV + PS, normal, paralysed, Pinsp 15', 20, nm, ns, vti, ppk);
  Check('Ppeak = PEEP + Pinsp', Abs(ppk - 20) < 0.1, Format('%.2f', [ppk]));
  { 3 }
  P.Effort := 6; P.PatRate := 18;
  V.Mode := vmVCSIMV; V.Rate := 8; V.PS := 8;
  E.Reset(P, V);
  RunFor(60);
  Show('3 VC-SIMV + PS, normal, breathing 18 /min, SIMV 8 /min', 20, nm, ns, vti, ppk);
  Check('mandatory near 8 /min, the rest PS', (Abs(nm - 5) <= 1) and (ns >= 6), Format('%d mandatory, %d PS in 40 s', [nm, ns]));
  Check('no missed efforts', E.Mon.Missed = 0, Format('%d', [E.Mon.Missed]));
  { 4 }
  P.Tone := 0.8; P.AsthmaWall := True; P.Effort := 10; P.PatRate := 22;
  V.PEEP := 0;
  E.Reset(P, V);
  tw := GetTickCount64;
  RunFor(60);
  Show('4 VC-SIMV + PS, status asthmaticus, breathing 22 /min, PEEP 0', 20, nm, ns, vti, ppk);
  Writeln(Format('    60 s simulated in %.1f s', [(GetTickCount64 - tw) / 1000]));
  { 5 }
  V.Mode := vmCPAPPS; V.PS := 12; V.PEEP := 5;
  E.Reset(P, V);
  RunFor(40);
  Show('5 CPAP 5 + PS 12, status asthmaticus', 20, nm, ns, vti, ppk);
  { 6 }
  P.Effort := 0;
  V := DefaultVentSettings; V.Mode := vmVCCMV; V.Rate := 14; V.PEEP := 0;
  E.Reset(P, V);
  RunFor(40);
  E.RequestInspHold; RunFor(6);
  E.RequestExpHold; RunFor(8);
  Show('6 VC-CMV, asthma, paralysed, holds', 40, nm, ns, vti, ppk);
  Check('plateau and total PEEP measured', not IsNan(E.Mon.Pplat) and not IsNan(E.Mon.PEEPtot),
    Format('Pplat %.1f, PEEPtot %.1f', [E.Mon.Pplat, E.Mon.PEEPtot]));
  { 7 }
  P := DefaultPatientSettings; P.Supine := False; P.Effort := 8; P.PatRate := 20;
  V := DefaultVentSettings; V.Mode := vmPCSIMV;
  E.Reset(P, V);
  RunFor(30);
  tw := Round(E.Mon.EELV);
  P.Tone := 0.6; P.Heliox := True;
  E.ChangeLung(P);
  RunFor(40);
  Show('7 PC-SIMV + PS, asthma, then salbutamol + heliox at 30 s', 50, nm, ns, vti, ppk);
  Check('the lung changes mid-run and the run carries on', E.T > 69, Format('t %.1f; EELV %d mL before, %.0f after', [E.T, Integer(tw), E.Mon.EELV]));
  { 8 }
  P := DefaultPatientSettings; P.Effort := 0; P.Supine := True;
  V := DefaultVentSettings; V.Mode := vmVCCMV; V.Rate := 14; V.PEEP := 5;
  E.Reset(P, V);
  RunFor(40);
  Show('8 VC-CMV 500 mL, PEEP 5, status asthmaticus, supine ventilated, paralysed', 30, nm, ns, vti, ppk);
  Check('supine: relaxed FRC near 2.3 L, pleural pressure positive in each breath',
    (Abs(E.Mon.FRC - 2.3) < 0.15) and (E.Mon.PplMax > 3),
    Format('FRC %.2f L, Ppl %.1f .. %.1f', [E.Mon.FRC, E.Mon.PplMin, E.Mon.PplMax]));
  P.Supine := False;
  E.ChangeLung(P);
  RunFor(30);
  Check('sitting up mid-run: FRC back to 3.0 L, Ppl negative', (Abs(E.Mon.FRC - 3.0) < 0.1) and (E.Mon.PplMax < 0.5),
    Format('FRC %.2f L, Ppl %.1f .. %.1f', [E.Mon.FRC, E.Mon.PplMin, E.Mon.PplMax]));
  E.Free;
  if NFail = 0 then Writeln('all passed') else Writeln(NFail, ' FAILED');
end.
