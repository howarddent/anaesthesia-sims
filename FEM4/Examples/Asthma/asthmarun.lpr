program asthmarun;

{ The single unit of the asthma model: one bronchiole and one alveolus,
  normal and asthmatic.

  1. Tube laws of the bronchiole's wall (uAirwayRing): lumen area
     against transmural pressure for the normal wall and for muscle
     tone, wall thickening and both, each tethered by the parenchyma at
     a transpulmonary pressure of 5 cmH2O. The number of folds is the
     one, from 2 to 12, of least strain energy at half the unloaded area.
  2. The alveolus (uAlveolus): pressure against volume on the deflation
     and inflation limbs and saline-filled, and its compliance.
  3. The unit as a Starling resistor (uBronchiole): at a fixed lung
     volume (alveolar recoil 5 cmH2O) the pleural pressure is raised, so
     the alveolar pressure is pleural + recoil while the pleural
     pressure squeezes the bronchiole; the far end is at 0. Flow
     against pleural pressure is the unit's isovolume pressure-flow
     curve.

  Options: --ri=<mm> unloaded lumen radius (0.25), --length=<mm> (1.7),
  --act=<0..1> muscle activation in asthma (0.3), --thick=<x> wall
  thickening in asthma (1.5), --mucus=<x> lining liquid in asthma as a
  multiple of normal (3), --lobes=<n> fix the number of folds,
  --out=<dir> for the CSV files (out).

  Build:  fpc -O3 -FUlib -Fu../../../newVM -Fi../../../newVM asthmarun.lpr }

{$mode delphi}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Classes, Math, cblas, newVM, uTubeLaw, uAirwayRing, uAlveolus, uBronchiole;

const
  NCase = 4;
  CaseName: array[0..NCase - 1] of string = ('normal', 'muscle tone', 'thick wall', 'tone + thick wall');
  PtpFRC = 5 * CmH2O;

var
  Ri: Double = 0.25;
  Len: Double = 1.7;
  Act: Double = 0.3;
  Thick: Double = 1.5;
  Mucus: Double = 3;
  FixLobes: Integer = 0;
  OutDir: string = 'out';
  Laws: array[0..NCase - 1] of TTubeLaw;
  Prms: array[0..NCase - 1] of TRingParams;

function Opt(const Name: string; var V: Double): Boolean; overload;
var
  i: Integer;
  s: string;
begin
  Result := False;
  for i := 1 to ParamCount do
  begin
    s := ParamStr(i);
    if Pos('--' + Name + '=', s) = 1 then
    begin
      V := StrToFloat(Copy(s, Length(Name) + 4, MaxInt));
      Result := True;
    end;
  end;
end;

function OptStr(const Name: string; var V: string): Boolean;
var
  i: Integer;
  s: string;
begin
  Result := False;
  for i := 1 to ParamCount do
  begin
    s := ParamStr(i);
    if Pos('--' + Name + '=', s) = 1 then
    begin
      V := Copy(s, Length(Name) + 4, MaxInt);
      Result := True;
    end;
  end;
end;

procedure TubeLaws;
const
  PShow: array[0..9] of Double = (-30, -20, -10, -5, -2, 0, 2, 5, 10, 30);
var
  c, i: Integer;
  notes: string;
  F: TStringList;
  line: string;
  p, AUn: Double;
begin
  Writeln('1. Bronchiole wall: lumen area / unloaded normal lumen area, against transmural pressure');
  Writeln(Format('   unloaded lumen radius %.3g mm, tethered at Ptp = 5 cmH2O', [Ri]));
  AUn := Pi * Ri * Ri;
  for c := 0 to NCase - 1 do
  begin
    case c of
      0: Prms[c] := NormalBronchiole(Ri);
      1: Prms[c] := AsthmaBronchiole(Ri, 1, Act);
      2: Prms[c] := AsthmaBronchiole(Ri, Thick, 0);
      3: Prms[c] := AsthmaBronchiole(Ri, Thick, Act);
    end;
    { the parenchyma's hole is the normal airway's, 10 % larger than
      unloaded at this lung volume, whatever the wall has become }
    Prms[c].TetherR := 1.1 * (Ri + WallThickness(Prms[0]));
    Prms[c].TetherK := 1.4 * PtpFRC / Prms[c].TetherR;
    if FixLobes > 0 then Prms[c].Lobes := FixLobes
    else Prms[c].Lobes := BestLobes(Prms[c], 0.5, 2, 12);
    Laws[c] := BuildTubeLaw(Prms[c], -40 * CmH2O, 40 * CmH2O, notes);
    Writeln(Format('   %-18s wall %.0f %% of lumen radius, %d folds, %d points  %s',
      [CaseName[c], 100 * WallThickness(Prms[c]) / Ri, Prms[c].Lobes, Laws[c].Count, notes]));
  end;
  Write('   Ptm cmH2O      ');
  for i := 0 to High(PShow) do Write(Format('%7.0f', [PShow[i]]));
  Writeln;
  for c := 0 to NCase - 1 do
  begin
    Write(Format('   %-15s', [CaseName[c]]));
    for i := 0 to High(PShow) do Write(Format('%7.3f', [Laws[c].Area(PShow[i] * CmH2O) / AUn]));
    Writeln;
  end;
  F := TStringList.Create;
  F.Add('Ptm_cmH2O,normal,tone,thick,tone_thick');
  for i := 0 to 160 do
  begin
    p := -40 + 0.5 * i;
    line := Format('%.2f', [p]);
    for c := 0 to NCase - 1 do line := line + Format(',%.5f', [Laws[c].Area(p * CmH2O) / AUn]);
    F.Add(line);
  end;
  F.SaveToFile(OutDir + '/tubelaw.csv');
  F.Free;
  Writeln;
end;

procedure AlveolusCurves;
const
  NAlv = 480e6;
var
  M: TAlveolus;
  P: TAlveolusParams;
  V0, VFRC, VTLC, v, pd, pinf, ps: Double;
  k: Integer;
  F: TStringList;
  Kind: TSurfactant;
  Res: array[0..2, 0..20] of Double;
  cFRC: array[0..2] of Double;
begin
  Writeln('2. Alveolus: recoil pressure (cmH2O) against volume');
  P := NormalAlveolus;
  M := TAlveolus.Create(P);
  V0 := M.UnstressedVolume;
  M.Free;
  { volumes of the cap when the sphere's radius is 0.1 and 0.126 mm }
  VFRC := V0 * Power(0.1 / P.R0, 3); VTLC := V0 * Power(0.126 / P.R0, 3);
  for Kind := sfNone to sfInflation do
  begin
    if Kind = sfConstant then Continue;
    P.Surf := Kind;
    M := TAlveolus.Create(P);
    for k := 0 to 20 do
    begin
      v := VFRC * 0.6 + (VTLC - 0.6 * VFRC) * k / 20;
      if M.MoveTo(amVolume, v) then Res[Max(0, Ord(Kind) - 1), k] := M.P / CmH2O
      else Res[Max(0, Ord(Kind) - 1), k] := NaN;
    end;
    { compliance at FRC by a central difference }
    M.MoveTo(amVolume, 0.98 * VFRC); pd := M.P;
    M.MoveTo(amVolume, 1.02 * VFRC);
    cFRC[Max(0, Ord(Kind) - 1)] := 0.04 * VFRC / ((M.P - pd) / CmH2O);
    M.Free;
  end;
  Writeln('   V/V_FRC   saline  deflation  inflation');
  F := TStringList.Create;
  F.Add('V_over_VFRC,saline,deflation,inflation');
  for k := 0 to 20 do
  begin
    v := 0.6 + (VTLC / VFRC - 0.6) * k / 20;
    ps := Res[0, k]; pd := Res[1, k]; pinf := Res[2, k];
    if k mod 2 = 0 then Writeln(Format('   %7.2f %8.2f %10.2f %10.2f', [v, ps, pd, pinf]));
    F.Add(Format('%.4f,%.4f,%.4f,%.4f', [v, ps, pd, pinf]));
  end;
  F.SaveToFile(OutDir + '/alveolus.csv');
  F.Free;
  Writeln(Format('   volume at FRC %.3g mm3; %.3g alveoli hold %.2f L', [VFRC, NAlv, NAlv * VFRC * 1e-6]));
  Writeln(Format('   compliance at FRC, deflation limb: %.3g mm3/cmH2O each, %.2f L/cmH2O for the lung',
    [cFRC[1], NAlv * cFRC[1] * 1e-6]));
  Writeln(Format('   saline-filled: %.2f L/cmH2O', [NAlv * cFRC[0] * 1e-6]));
  Writeln;
end;

procedure StarlingCurves;
const
  PplShow: array[0..9] of Double = (-5, 0, 2, 5, 10, 20, 30, 50, 80, 120);
var
  Br: array[0..NCase] of TBronchiole;
  c, i: Integer;
  ppl, q, a: Double;
  lim, cl: Boolean;
  F: TStringList;
  line: string;
  film: Double;
begin
  Writeln('3. The unit as a Starling resistor: flow (mm3/s) against pleural pressure');
  Writeln(Format('   alveolar recoil 5 cmH2O, far end at 0, bronchiole %.3g mm long', [Len]));
  { 5 um of lining liquid on the normal airway }
  film := 2 * Pi * Ri * 0.005;
  for c := 0 to NCase do
  begin
    Br[c] := TBronchiole.Create(Laws[Min(c, NCase - 1)], Len);
    Br[c].Lining.Gamma := 0.025;
    Br[c].Lining.ALiq := film;
  end;
  Br[NCase].Lining.ALiq := Mucus * film;
  Write('   Ppl cmH2O           ');
  for i := 0 to High(PplShow) do Write(Format('%8.0f', [PplShow[i]]));
  Writeln;
  for c := 0 to NCase do
  begin
    if c < NCase then Write(Format('   %-20s', [CaseName[c]]))
    else Write(Format('   %-20s', ['tone + thick + mucus']));
    for i := 0 to High(PplShow) do
    begin
      ppl := PplShow[i] * CmH2O;
      q := Br[c].Flow(ppl + PtpFRC, 0, ppl, lim);
      Write(Format('%8.1f', [q]));
    end;
    Writeln;
  end;
  Writeln('   at rest (lumen at 0, pleural pressure -5 cmH2O): gas area / unloaded normal lumen area,');
  Writeln('   resistance of one bronchiole and of 30 000 in parallel (cmH2O s/L)');
  for c := 0 to NCase do
  begin
    if c < NCase then Write(Format('   %-20s', [CaseName[c]]))
    else Write(Format('   %-20s', ['tone + thick + mucus']));
    a := Br[c].Area(0, -PtpFRC, cl);
    if cl then Writeln('  closed by its lining')
    else
    begin
      q := Br[c].Flow(0.001 * CmH2O, 0, -PtpFRC, lim);
      Writeln(Format('%8.3f %10.1f %10.5f', [a / (Pi * Ri * Ri), 0.001 / (q * 1e-6), 0.001 / (q * 1e-6) / 30000]));
    end;
  end;
  F := TStringList.Create;
  F.Add('Ppl_cmH2O,normal,tone,thick,tone_thick,tone_thick_mucus');
  for i := 0 to 125 do
  begin
    ppl := (-5 + i) * CmH2O;
    line := Format('%d', [-5 + i]);
    for c := 0 to NCase do
      line := line + Format(',%.4f', [Br[c].Flow(ppl + PtpFRC, 0, ppl, lim)]);
    F.Add(line);
  end;
  F.SaveToFile(OutDir + '/starling.csv');
  F.Free;
  for c := 0 to NCase do Br[c].Free;
end;

var
  d: Double;
begin
  InitializeCBLAS;
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  DefaultFormatSettings.DecimalSeparator := '.';
  Opt('ri', Ri); Opt('length', Len); Opt('act', Act); Opt('thick', Thick); Opt('mucus', Mucus);
  d := 0;
  if Opt('lobes', d) then FixLobes := Round(d);
  OptStr('out', OutDir);
  ForceDirectories(OutDir);
  TubeLaws;
  AlveolusCurves;
  StarlingCurves;
end.
