program gascheck;

{ Checks of the gas exchange model (uGasExchange) against closed forms.

  1. One ideal unit, VA 4 L/min, on air: PACO2 = VCO2 / (K VA) and the
     alveolar gas equation PAO2 = PIO2 - PACO2 VO2/VCO2; arterial equals
     alveolar.
  2. Fick: the converged mixed venous contents give back VO2 and VCO2.
  3. The shunt equation: a second unit with no ventilation and 30 % of
     the perfusion gives CaO2 = 0.7 Cc'O2 + 0.3 CvO2 exactly.
  4. The dissociation curves: Severinghaus' S(26.8) = 0.5 to a few
     tenths of a per cent (P50 26.8 mmHg), O2Pressure inverts O2Content.
  5. Ventilation-perfusion mismatch alone (two units, V/Q 0.2 and 3,
     no shunt) lowers PaO2 and raises PaCO2 against the matched lung
     with the same totals, and more oxygen corrects the PaO2.

  Build:  fpc -O3 -FUlib gascheck.lpr }

{$mode delphi}{$H+}

uses
  SysUtils, Math, uGasExchange;

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

procedure Expect(const What: string; Ok: Boolean);
begin
  if Ok then Writeln('  ', What, ': ok')
  else begin Writeln('  ', What, ': FAIL'); Inc(Fails); end;
end;

var
  G: TGasParams;
  B, B2: TBloodGases;
  VA, Q, PA, PC: array of Double;
  pac, pao, cc: Double;
begin
  DefaultFormatSettings.DecimalSeparator := '.';
  G := DefaultGasParams;
  SetLength(VA, 1); SetLength(Q, 1); SetLength(PA, 1); SetLength(PC, 1);
  Writeln('1. One ideal unit on air');
  VA[0] := 4; Q[0] := 5;
  B := BloodGases(VA, Q, G, PA, PC);
  pac := G.VCO2 * 713 / (826 * 4);
  pao := G.FiO2 * 713 - pac * G.VO2 / G.VCO2;
  Check('PaCO2, mmHg', B.PaCO2, pac, 1e-6);
  Check('PaO2 (alveolar gas equation), mmHg', B.PaO2, pao, 1e-6);
  Writeln(Format('    PvO2 %.1f, PvCO2 %.1f, SaO2 %.3f, SvO2 %.3f', [B.PvO2, B.PvCO2, B.SaO2, B.SvO2]));
  Writeln('2. Fick');
  Check('VO2 from the contents, mL/min', 10 * G.Qt * (B.CaO2 - B.CvO2), G.VO2, 1e-6);
  Check('VCO2 from the contents, mL/min', 10 * G.Qt * (CO2Content(B.PvCO2) - CO2Content(B.PaCO2)), G.VCO2, 1e-4);
  Writeln('3. Shunt equation, 30 % shunt on oxygen');
  G.FiO2 := 1;
  SetLength(VA, 2); SetLength(Q, 2); SetLength(PA, 2); SetLength(PC, 2);
  VA[0] := 4; Q[0] := 0.7; VA[1] := 0; Q[1] := 0.3;
  B := BloodGases(VA, Q, G, PA, PC);
  cc := O2Content(PA[0], G.Hb);
  Check('CaO2 = 0.7 Cc''O2 + 0.3 CvO2, mL/dL', B.CaO2, 0.7 * cc + 0.3 * B.CvO2, 1e-6);
  Check('shunt fraction', B.Shunt, 0.3, 1e-12);
  Writeln(Format('    PaO2 %.0f mmHg, PaCO2 %.1f, SaO2 %.3f', [B.PaO2, B.PaCO2, B.SaO2]));
  Writeln('4. Dissociation curves');
  Check('S(26.8 mmHg)', O2Sat(26.8), 0.5, 5e-3);
  Check('O2Pressure(O2Content(80))', O2Pressure(O2Content(80, 15), 15), 80, 1e-6);
  Check('CO2Content(40), mL/dL', CO2Content(40), 49, 2e-3);
  Writeln('5. Ventilation-perfusion mismatch');
  G := DefaultGasParams;
  VA[0] := 0.5; Q[0] := 2.5; VA[1] := 3.5; Q[1] := 2.5;   { V/Q 0.2 and 1.4 }
  B := BloodGases(VA, Q, G, PA, PC);
  VA[0] := 2; Q[0] := 2.5; VA[1] := 2; Q[1] := 2.5;
  B2 := BloodGases(VA, Q, G, PA, PC);
  Writeln(Format('    mismatched: PaO2 %.1f, PaCO2 %.1f; matched: PaO2 %.1f, PaCO2 %.1f', [B.PaO2, B.PaCO2,
    B2.PaO2, B2.PaCO2]));
  Expect('mismatch lowers PaO2', B.PaO2 < B2.PaO2 - 5);
  Expect('mismatch raises PaCO2', B.PaCO2 > B2.PaCO2);
  G.FiO2 := 0.4;
  VA[0] := 0.5; Q[0] := 2.5; VA[1] := 3.5; Q[1] := 2.5;
  B := BloodGases(VA, Q, G, PA, PC);
  Writeln(Format('    mismatched on 40 %%: PaO2 %.1f', [B.PaO2]));
  Expect('oxygen corrects the mismatch (PaO2 > 100)', B.PaO2 > 100);
  Writeln;
  if Fails = 0 then Writeln('All checks passed.')
  else
  begin
    Writeln(Fails, ' check(s) FAILED.');
    Halt(1);
  end;
end.
