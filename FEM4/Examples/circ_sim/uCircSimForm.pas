unit uCircSimForm;

{ circ_sim's window: the finite-element left ventricle and the arterial
  pulse wave it drives, computed in one step and shown on two tabs.

    Left ventricle   LVView's window (../LeftVentricle/uLVViewForm): the
                     wall in motion, the pressure-volume loop, pressures
                     and valve flows.
    Aortic pulse     AortaView's window (../Aorta/uAortaViewForm): the
                     arterial tree coloured by pressure, the pressure at
                     root, elbow, wrist and groin, the wave along the
                     paths, flows.

  Both windows are the viewers' own forms, placed inside the tabs with
  their own compute rows hidden. The rows above the tabs hold every
  setting, and "Compute" does one coupled calculation:

    1  ../LeftVentricle/lvrun --arteries runs the ventricle ejecting
       into the arterial tree, coupled both ways at the aortic valve
       (../Aorta/uAortaAfterload), to a steady beat: about four minutes
       for eight beats. It writes the beat's motion and its pressures
       and flows into out/cs_<every setting>.txt and .csv; a beat
       already there for the same settings is reused.
    2  the arterial tree is run again in this program on that beat's
       valve flow, for the pictures (8 to 25 s). With the same arterial
       settings it reproduces the coupled tree: its root pressure is
       within about 0.2 mmHg of the one the ventricle worked against,
       but for one sample at the valve's closure.

  So the ventricle's stroke volume, pressures and loop are those for
  the vascular settings, and any change to them needs the whole
  calculation. Impaired contractility is a lower peak active stress T0;
  vasodilatation a "vascular resistance x" below 1.

  The peripheral resistance is given directly (mmHg s/mL): with the
  flow no longer imposed, a mean pressure cannot be. "Stroke volume x"
  scales the valve's flow on its way into the tree, and the ventricle
  feels the pressure of the scaled flow: a stand-in for a smaller
  ventricle, since the ventricle model itself is the adult's.

  PRESETS   The "typical of" list fills every arterial setting for a
  child of 7, an adult of 40, a person of 80 and a person of 80 with
  hypertension (Presets below). The elastance factors were fitted with
  the coupled model (the tree re-run on the coupled beat's flow, then
  the coupled beat again to confirm) until the carotid-femoral and
  carotid-radial foot-to-foot velocities (uAortaTree: CFPWV, CRPWV)
  were the published ones, m/s:

                      carotid-femoral     carotid-radial    root mmHg
                      published  model    published  model  (coupled)
      child 7            4.8     4.84        7.3     7.21     96/50
      adult 40           6.9     6.91        9.7     9.68    120/71
      aged 80           10.9    10.87       11.3    11.29    139/59
      aged 80, grade II/III hypertension
                        14.0    13.95        none   13.25    162/76

  Carotid-femoral at 40 and 80: Reference Values for Arterial Stiffness'
  Collaboration, Eur Heart J 2010;31:2338, normal values (30-39 6.5,
  40-49 7.2; 70 and over 10.9). The child's, and all three carotid-
  radial: Zocalo & Bia, J Cardiovasc Dev Dis 2021;8:3, 50th centiles
  (5 y 4.6 and 7.0, 10 y 5.0 and 7.7; 40 y 9.7; 80 y 11.3). The body
  size, stroke volume factor and bed compliance beside them are my
  round typical values, not from those papers. The resistances put the
  coupled mean pressure near my round 72, 98 and 118 mmHg (73, 98, 117);
  the adult's is the ventricle model's own. The wall viscosity is left
  at 5 ms for all. The child's velocities are not refitted closer: at
  that size the foot-to-foot figure jumps by about 0.1 m/s between
  neighbouring factors. The fit holds for the normal ventricle at
  70 /min; the velocities move with the pressure, so with T0, the heart
  rate and the vascular resistance.

  The hypertensive preset: 14.0 m/s is the same Collaboration's mean
  for 70 and over with grade II/III hypertension (+-2 SD 7.4-20.6). Only
  the aortic factor is fitted. The iliac and arm factor, 2.6, is a round
  value that lets the carotid-femoral velocity reach 14 inside the
  aortic control's range (the iliacs are on that path; at 2.3 the aortic
  factor would have to be 10), and the carotid-radial velocity is what
  follows, with no published target.

  Only the visible tab's animation runs. }

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Math, Forms, Controls, Graphics, StdCtrls, ExtCtrls,
  ComCtrls, Spin, Dialogs, Process,
  uLVViewForm, uAortaViewForm;

type

  TCircSimForm = class(TForm)
  private
    FDir, FLVDir: string;
    pnlTop, pnlRows, pnlCO, pnlRow1, pnlRow2, pnlRow3: TPanel;
    lblCO: TLabel;
    FPages: TPageControl;
    tsLV, tsAorta: TTabSheet;
    seHR, seLVBeats, seAoBeats: TSpinEdit;
    seT0, seStiff, seOther, seCPer, seTau, seSize, seFlow, seRTot, sePVR: TFloatSpinEdit;
    cbPreset: TComboBox;
    FPresetting: Boolean;
    edExtra: TEdit;
    btnCompute: TButton;
    pbRun: TProgressBar;
    lblRun: TLabel;
    FPoll: TTimer;
    FProc: TProcess;
    FProcOut, FAnimFile, FCsvFile, FShownAnim: string;
    function AddLabel(AParent: TWinControl; const S: string; Bold: Boolean = False): TLabel;
    procedure Place(C: TControl; AParent: TWinControl; W: Integer);
    function IntSpin(AParent: TWinControl; Lo, Hi, Step, V, W: Integer): TSpinEdit;
    function FloatSpin(AParent: TWinControl; Lo, Hi, Step, V: Double; Dec, W: Integer): TFloatSpinEdit;
    procedure ComputeClick(Sender: TObject);
    procedure PollTick(Sender: TObject);
    procedure PageChange(Sender: TObject);
    procedure PresetChange(Sender: TObject);
    procedure ArterialEdited(Sender: TObject);
    procedure SetRunning(R: Boolean);
    function FileTag: string;
    procedure ShowOutput(const CsvFile: string);
    // the ventricle's beat is in AnimFile and CsvFile: show it, run the arteries
    procedure ShowBeat(const AnimFile, CsvFile, Note: string);
  public
    LVForm: TLVViewForm;
    AoForm: TAortaViewForm;
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    destructor Destroy; override;
    { after Show: gives each tab its OpenGL context, then shows the
      default beat if it has been computed (here or by LVView) }
    procedure Start;
    procedure Compute;
    { before Start; 0 leaves a setting alone }
    procedure SetVentricle(HR, Beats: Integer; T0: Double = 0);
    function Computing: Boolean;
    procedure ShowTab(Index: Integer);
    { 0 child of 7, 1 adult of 40, 2 aged 80, 3 aged 80 with hypertension }
    procedure SetPreset(Index: Integer);
    { the peripheral resistance multiplier: vasoconstriction above 1 }
    procedure SetResistance(X: Double);
  end;

implementation

type
  TPreset = record
    Name: string;
    Size, Flow, RTot, Stiff, Other, CPer, Tau: Double;
  end;
const
  { Stiff and Other fitted to the velocities in the header; the rest assumed }
  Presets: array[0..3] of TPreset = (
    (Name: 'child, 7 years'; Size: 0.70; Flow: 0.55; RTot: 1.46; Stiff: 0.31; Other: 0.39; CPer: 0.4; Tau: 5),
    (Name: 'adult, 40 years'; Size: 1; Flow: 1; RTot: 1.147; Stiff: 0.90; Other: 1.05; CPer: 0.8; Tau: 5),
    (Name: 'elderly, 80 years'; Size: 1; Flow: 0.9; RTot: 1.37; Stiff: 3.92; Other: 1.78; CPer: 0.6; Tau: 5),
    (Name: 'elderly, 80 years, hypertensive'; Size: 1; Flow: 0.9; RTot: 1.82; Stiff: 7.9; Other: 2.6; CPer: 0.6; Tau: 5));

function DotFS: TFormatSettings;
begin
  Result := DefaultFormatSettings;
  Result.DecimalSeparator := '.';
end;

constructor TCircSimForm.CreateNew(AOwner: TComponent; Num: Integer);

  function Row(AAlign: TAlign): TPanel;
  begin
    Result := TPanel.Create(Self);
    Result.Parent := pnlRows;
    Result.Align := AAlign;
    Result.Height := 36;
    Result.BevelOuter := bvNone;
    Result.ChildSizing.Layout := cclLeftToRightThenTopToBottom;
    Result.ChildSizing.ControlsPerLine := 100;
    Result.ChildSizing.HorizontalSpacing := 6;
    Result.ChildSizing.LeftRightSpacing := 6;
    Result.ChildSizing.TopBottomSpacing := 4;
  end;

var
  i: Integer;
begin
  inherited CreateNew(AOwner, Num);
  FDir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  FLVDir := ExpandFileName(FDir + '..' + PathDelim + 'LeftVentricle') + PathDelim;
  Caption := 'circ_sim - left ventricle and arterial pulse';
  Width := 1460;
  Height := 1000;
  Position := poScreenCenter;

  pnlTop := TPanel.Create(Self);
  pnlTop.Parent := Self;
  pnlTop.Align := alTop;
  pnlTop.Height := 108;
  pnlTop.BevelOuter := bvNone;
  { the cardiac output, on the right of the settings }
  pnlCO := TPanel.Create(Self);
  pnlCO.Parent := pnlTop;
  pnlCO.Align := alRight;
  pnlCO.Width := 190;
  pnlCO.BevelOuter := bvNone;
  lblCO := TLabel.Create(Self);
  lblCO.Parent := pnlCO;
  lblCO.Align := alClient;
  lblCO.Alignment := taCenter;
  lblCO.Layout := tlCenter;
  lblCO.Font.Style := [fsBold];
  lblCO.Font.Size := 14;
  lblCO.Hint := 'Mean flow through the aortic valve over the beat shown, times "stroke volume x": '
    + 'what enters the arteries';
  lblCO.ShowHint := True;
  pnlRows := TPanel.Create(Self);
  pnlRows.Parent := pnlTop;
  pnlRows.Align := alClient;
  pnlRows.BevelOuter := bvNone;
  pnlRow3 := Row(alBottom);
  pnlRow1 := Row(alTop);
  pnlRow2 := Row(alClient);

  AddLabel(pnlRow1, 'Ventricle', True);
  AddLabel(pnlRow1, 'heart rate /min');
  seHR := IntSpin(pnlRow1, 40, 180, 5, 70, 60);
  AddLabel(pnlRow1, 'beats to run');
  seLVBeats := IntSpin(pnlRow1, 1, 30, 1, 8, 55);
  AddLabel(pnlRow1, 'peak active stress T0, kPa');
  seT0 := FloatSpin(pnlRow1, 20, 400, 5, 145, 0, 65);
  AddLabel(pnlRow1, 'other lvrun options');
  edExtra := TEdit.Create(Self);
  edExtra.Hint := 'e.g. --cross=0  --sync  --mesh=4,16,24  --ppv=12  --kvc=24  (see lvrun.lpr)';
  edExtra.ShowHint := True;
  Place(edExtra, pnlRow1, 170);
  btnCompute := TButton.Create(Self);
  btnCompute.Caption := 'Compute';
  btnCompute.OnClick := ComputeClick;
  Place(btnCompute, pnlRow1, 90);
  pbRun := TProgressBar.Create(Self);
  pbRun.Min := 0;
  pbRun.Max := 8;
  Place(pbRun, pnlRow1, 100);
  lblRun := AddLabel(pnlRow1, '');

  AddLabel(pnlRow2, 'Arteries', True);
  AddLabel(pnlRow2, 'typical of');
  cbPreset := TComboBox.Create(Self);
  cbPreset.Style := csDropDownList;
  for i := 0 to High(Presets) do cbPreset.Items.Add(Presets[i].Name);
  cbPreset.Items.Add('(my own values)');
  cbPreset.Hint := 'Fills the arterial settings. The elastances are fitted so that the carotid-femoral and '
    + 'carotid-radial velocities match published values for the age';
  cbPreset.ShowHint := True;
  Place(cbPreset, pnlRow2, 250);
  cbPreset.OnChange := PresetChange;
  AddLabel(pnlRow2, 'body size x');
  seSize := FloatSpin(pnlRow2, 0.4, 1.3, 0.05, 1, 2, 65);
  seSize.Hint := 'Multiplies every arterial length and radius. 1: an adult of about 175 cm';
  seSize.ShowHint := True;
  AddLabel(pnlRow2, 'stroke volume x');
  seFlow := FloatSpin(pnlRow2, 0.2, 1.5, 0.05, 1, 2, 65);
  seFlow.Hint := 'Multiplies the ventricle''s valve flow before it enters the arteries';
  seFlow.ShowHint := True;
  AddLabel(pnlRow2, 'peripheral resistance, mmHg s/mL');
  seRTot := FloatSpin(pnlRow2, 0.3, 4, 0.01, 1.147, 3, 75);
  seRTot.Hint := 'Total resistance of the arterial beds, typical of the age. Mean pressure is this times the cardiac output';
  seRTot.ShowHint := True;
  AddLabel(pnlRow2, 'vascular resistance x');
  sePVR := FloatSpin(pnlRow2, 0.3, 3, 0.05, 1, 2, 65);
  sePVR.Hint := 'Multiplies the peripheral resistance of every arterial bed. Above 1: vasoconstriction; below 1: '
    + 'vasodilatation. The ventricle ejects against the result. Not changed by the "typical of" list';
  sePVR.ShowHint := True;

  AddLabel(pnlRow3, '', True);
  AddLabel(pnlRow3, 'aortic and carotid elastance x');
  seStiff := FloatSpin(pnlRow3, 0.1, 8, 0.05, 1, 2, 65);
  AddLabel(pnlRow3, 'iliacs and arm x');
  seOther := FloatSpin(pnlRow3, 0.1, 8, 0.05, 1, 2, 65);
  AddLabel(pnlRow3, 'bed compliance, mL/mmHg');
  seCPer := FloatSpin(pnlRow3, 0, 3, 0.1, 0.8, 2, 65);
  seCPer.Hint := 'Above 0 each bed is a Windkessel matched to its artery (allow about 25 beats). 0: pure resistances';
  seCPer.ShowHint := True;
  AddLabel(pnlRow3, 'wall viscosity, ms');
  seTau := FloatSpin(pnlRow3, 0, 30, 1, 5, 1, 60);
  seTau.Hint := 'Kelvin-Voigt wall: its retardation time, wall viscosity over Young''s modulus. 0: elastic wall';
  seTau.ShowHint := True;
  AddLabel(pnlRow3, 'beats to run');
  seAoBeats := IntSpin(pnlRow3, 2, 80, 1, 25, 55);
  seSize.OnChange := ArterialEdited; seFlow.OnChange := ArterialEdited; seRTot.OnChange := ArterialEdited;
  seStiff.OnChange := ArterialEdited; seOther.OnChange := ArterialEdited;
  seCPer.OnChange := ArterialEdited; seTau.OnChange := ArterialEdited;
  SetPreset(1);

  FPages := TPageControl.Create(Self);
  FPages.Parent := Self;
  FPages.Align := alClient;
  tsLV := FPages.AddTabSheet;
  tsLV.Caption := 'Left ventricle';
  tsAorta := FPages.AddTabSheet;
  tsAorta.Caption := 'Aortic pulse';
  FPages.OnChange := PageChange;

  LVForm := TLVViewForm.CreateNew(Self);
  LVForm.Embed(tsLV);
  AoForm := TAortaViewForm.CreateNew(Self);
  AoForm.Embed(tsAorta);
  AoForm.SetActive(False);

  FPoll := TTimer.Create(Self);
  FPoll.Interval := 150;
  FPoll.OnTimer := PollTick;
  FPoll.Enabled := False;
end;

destructor TCircSimForm.Destroy;
begin
  FPoll.Enabled := False;
  if FProc <> nil then
  begin
    if FProc.Running then FProc.Terminate(1);
    FProc.Free;
  end;
  inherited Destroy;
end;

function TCircSimForm.AddLabel(AParent: TWinControl; const S: string; Bold: Boolean): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Caption := S;
  Result.Layout := tlCenter;
  if Bold then
  begin
    Result.Font.Style := [fsBold];
    Result.AutoSize := False;
    Result.Width := 75;
    Result.Constraints.MinWidth := 75;
  end;
  Result.Parent := AParent;
end;

procedure TCircSimForm.Place(C: TControl; AParent: TWinControl; W: Integer);
begin
  C.Width := W;
  C.Constraints.MinWidth := W;
  C.Parent := AParent;
end;

function TCircSimForm.IntSpin(AParent: TWinControl; Lo, Hi, Step, V, W: Integer): TSpinEdit;
begin
  Result := TSpinEdit.Create(Self);
  Result.MinValue := Lo;
  Result.MaxValue := Hi;
  Result.Increment := Step;
  Result.Value := V;
  Place(Result, AParent, W);
end;

function TCircSimForm.FloatSpin(AParent: TWinControl; Lo, Hi, Step, V: Double; Dec, W: Integer): TFloatSpinEdit;
begin
  Result := TFloatSpinEdit.Create(Self);
  Result.MinValue := Lo;
  Result.MaxValue := Hi;
  Result.Increment := Step;
  Result.DecimalPlaces := Dec;
  Result.Value := V;
  Place(Result, AParent, W);
end;

procedure TCircSimForm.PageChange(Sender: TObject);
begin
  LVForm.SetActive(FPages.ActivePage = tsLV);
  AoForm.SetActive(FPages.ActivePage = tsAorta);
end;

procedure TCircSimForm.SetPreset(Index: Integer);
begin
  FPresetting := True;
  try
    cbPreset.ItemIndex := Index;
    with Presets[Index] do
    begin
      seSize.Value := Size; seFlow.Value := Flow; seRTot.Value := RTot;
      seStiff.Value := Stiff; seOther.Value := Other; seCPer.Value := CPer; seTau.Value := Tau;
    end;
  finally
    FPresetting := False;
  end;
end;

procedure TCircSimForm.PresetChange(Sender: TObject);
begin
  if cbPreset.ItemIndex <= High(Presets) then SetPreset(cbPreset.ItemIndex);
end;

procedure TCircSimForm.ArterialEdited(Sender: TObject);
begin
  if not FPresetting then cbPreset.ItemIndex := Length(Presets);
end;

procedure TCircSimForm.ShowTab(Index: Integer);
begin
  FPages.ActivePageIndex := Index;
  PageChange(nil);
end;

procedure TCircSimForm.Start;
var
  i, k: Integer;
  a, c: string;
begin
  // a tab's OpenGL controls get their context when the tab is first shown
  for k := 1 downto 0 do
  begin
    ShowTab(k);
    for i := 1 to 5 do begin Application.ProcessMessages; Sleep(20); end;
  end;
  a := FDir + 'out' + PathDelim + FileTag + '.txt';
  c := ChangeFileExt(a, '.csv');
  if FileExists(a) and FileExists(c) then
    ShowBeat(a, c, 'computed earlier')
  else
  begin
    // LVView's own default beat, which has these settings
    a := FLVDir + 'out' + PathDelim + 'anim_default.txt';
    c := FLVDir + 'out' + PathDelim + 'beat.csv';
    if FileExists(a) and FileExists(c) then
      ShowBeat(a, c, 'NOT COUPLED: LeftVentricle''s default beat, ejecting into its own Windkessel. Press Compute')
    else
      lblRun.Caption := 'Nothing computed yet: press Compute (about four minutes)';
  end;
end;

function TCircSimForm.FileTag: string;
var
  Extra: string;
  i: Integer;
begin
  Extra := Trim(edExtra.Text);
  { the beat depends on the arteries too }
  Result := Format('cs_hr%d_t0%.0f_b%d_a%.2f_%.2f_r%.3f_x%.2f_z%.2f_f%.2f_c%.2f_w%.1f',
    [seHR.Value, seT0.Value, seLVBeats.Value, seStiff.Value, seOther.Value, seRTot.Value, sePVR.Value,
     seSize.Value, seFlow.Value, seCPer.Value, seTau.Value], DotFS);
  for i := 1 to Length(Extra) do
    if Extra[i] in ['0'..'9', 'a'..'z', 'A'..'Z', '.', ','] then
      Result := Result + Extra[i]
    else if (Extra[i] = ' ') or (Extra[i] = '=') then
      Result := Result + '_';
end;

procedure TCircSimForm.SetRunning(R: Boolean);
begin
  btnCompute.Enabled := not R;
  FPoll.Enabled := R;
  if not R then pbRun.Position := 0;
end;

procedure TCircSimForm.ShowBeat(const AnimFile, CsvFile, Note: string);
begin
  if AnimFile <> FShownAnim then
  begin
    LVForm.LoadAnim(AnimFile);
    FShownAnim := AnimFile;
  end;
  lblRun.Caption := 'running the arteries...';
  btnCompute.Enabled := False;
  Application.ProcessMessages;
  try
    AoForm.LVFile := CsvFile;
    AoForm.BodySize := seSize.Value;
    AoForm.FlowScale := seFlow.Value;
    AoForm.MeanP := 0;
    AoForm.RTotal := seRTot.Value;
    AoForm.Resistance := sePVR.Value;
    AoForm.SetModel(seStiff.Value, seOther.Value, seCPer.Value, seAoBeats.Value, seTau.Value);
    AoForm.Compute;
  finally
    btnCompute.Enabled := True;
  end;
  lblRun.Caption := Note;
  ShowOutput(CsvFile);
  PageChange(nil);
end;

{ the beat's csv: time in column 1, aortic valve flow, mL/s, in column 7 }
procedure TCircSimForm.ShowOutput(const CsvFile: string);
var
  L: TStringList;
  Parts: TStringArray;
  i, n: Integer;
  t, q, t0, tPrev, qPrev, Vol: Double;
begin
  lblCO.Caption := '';
  L := TStringList.Create;
  try
    L.LoadFromFile(CsvFile);
    n := 0; Vol := 0; t0 := 0; tPrev := 0; qPrev := 0;
    for i := 1 to L.Count - 1 do
    begin
      Parts := L[i].Split([',']);
      if Length(Parts) < 7 then Continue;
      if not (TryStrToFloat(Parts[0], t, DotFS) and TryStrToFloat(Parts[6], q, DotFS)) then Continue;
      if n = 0 then t0 := t else Vol := Vol + 0.5 * (q + qPrev) * (t - tPrev);
      tPrev := t; qPrev := q;
      Inc(n);
    end;
    if (n > 1) and (tPrev > t0) then
      lblCO.Caption := 'Cardiac output'#10
        + FormatFloat('0.00', Vol / (tPrev - t0) * 0.06 * seFlow.Value, DotFS) + ' L/min';
  finally
    L.Free;
  end;
end;

procedure TCircSimForm.ComputeClick(Sender: TObject);
var
  Exe: string;
  Parts: TStringArray;
  i: Integer;
begin
  ForceDirectories(FDir + 'out');
  FAnimFile := FDir + 'out' + PathDelim + FileTag + '.txt';
  FCsvFile := ChangeFileExt(FAnimFile, '.csv');
  if FileExists(FAnimFile) and FileExists(FCsvFile) then
  begin
    ShowBeat(FAnimFile, FCsvFile, 'computed earlier');
    Exit;
  end;
  Exe := FLVDir + 'lvrun';
  {$IFDEF WINDOWS}
  Exe := Exe + '.exe';
  {$ENDIF}
  if not FileExists(Exe) then
  begin
    MessageDlg('lvrun was not found (' + Exe + ').'#10
      + 'Build it first: see the header of LeftVentricle/lvrun.lpr.', mtError, [mbOK], 0);
    Exit;
  end;
  FProc.Free;
  FProc := TProcess.Create(nil);
  FProc.Executable := Exe;
  FProc.CurrentDirectory := FLVDir;
  FProc.Parameters.Add('--anim=' + FAnimFile);
  FProc.Parameters.Add('--csv=' + FCsvFile);
  FProc.Parameters.Add('--hr=' + IntToStr(seHR.Value));
  FProc.Parameters.Add('--beats=' + IntToStr(seLVBeats.Value));
  FProc.Parameters.Add('--t0=' + FormatFloat('0', seT0.Value, DotFS));
  FProc.Parameters.Add('--arteries');
  FProc.Parameters.Add('--stiff=' + FormatFloat('0.###', seStiff.Value, DotFS));
  FProc.Parameters.Add('--stiffother=' + FormatFloat('0.###', seOther.Value, DotFS));
  FProc.Parameters.Add('--rtot=' + FormatFloat('0.####', seRTot.Value, DotFS));
  FProc.Parameters.Add('--pvr=' + FormatFloat('0.###', sePVR.Value, DotFS));
  FProc.Parameters.Add('--size=' + FormatFloat('0.###', seSize.Value, DotFS));
  FProc.Parameters.Add('--flow=' + FormatFloat('0.###', seFlow.Value, DotFS));
  FProc.Parameters.Add('--cperiph=' + FormatFloat('0.###', seCPer.Value, DotFS));
  FProc.Parameters.Add('--walltau=' + FormatFloat('0.###', seTau.Value, DotFS));
  Parts := Trim(edExtra.Text).Split([' '], TStringSplitOptions.ExcludeEmpty);
  for i := 0 to High(Parts) do FProc.Parameters.Add(Parts[i]);
  FProc.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
  FProcOut := '';
  try
    FProc.Execute;
  except
    on E: Exception do
    begin
      MessageDlg('Could not start lvrun: ' + E.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;
  pbRun.Max := seLVBeats.Value;
  lblRun.Caption := 'ventricle: filling...';
  lblCO.Caption := '';
  SetRunning(True);
end;

procedure TCircSimForm.SetResistance(X: Double);
begin
  sePVR.Value := X;
end;

procedure TCircSimForm.SetVentricle(HR, Beats: Integer; T0: Double);
begin
  if T0 > 0 then seT0.Value := T0;
  if HR > 0 then seHR.Value := HR;
  if Beats > 0 then seLVBeats.Value := Beats;
end;

procedure TCircSimForm.Compute;
begin
  ComputeClick(nil);
end;

function TCircSimForm.Computing: Boolean;
begin
  Result := FPoll.Enabled;
end;

procedure TCircSimForm.PollTick(Sender: TObject);
var
  Buf: array[0..4095] of Char;
  n, p, q, beats: Integer;
  Tail: string;
begin
  if FProc = nil then Exit;
  // keep the pipe drained, or lvrun blocks on a full one
  while FProc.Output.NumBytesAvailable > 0 do
  begin
    n := FProc.Output.Read(Buf, Min(SizeOf(Buf), FProc.Output.NumBytesAvailable));
    if n <= 0 then Break;
    SetString(Tail, PChar(@Buf[0]), n);
    FProcOut := FProcOut + Tail;
  end;
  // progress: one line per beat after the table's heading
  p := Pos(' beat ', FProcOut);
  if p > 0 then
  begin
    beats := -1;
    q := PosEx(#10, FProcOut, p);
    while q > 0 do
    begin
      Inc(beats);
      q := PosEx(#10, FProcOut, q + 1);
    end;
    if beats > 0 then beats := beats div 2;   { two lines a beat: the ventricle's, the arteries' }
    beats := EnsureRange(beats, 0, pbRun.Max);
    pbRun.Position := beats;
    if beats < pbRun.Max then
      lblRun.Caption := Format('ventricle and arteries: beat %d of %d', [beats + 1, pbRun.Max]);
  end;
  if not FProc.Running then
  begin
    SetRunning(False);
    if (FProc.ExitStatus = 0) and FileExists(FAnimFile) and FileExists(FCsvFile) then
      ShowBeat(FAnimFile, FCsvFile, 'computed')
    else
    begin
      lblRun.Caption := 'lvrun failed';
      // a failed run may leave half a pair behind, which would be taken for a result
      DeleteFile(FAnimFile);
      DeleteFile(FCsvFile);
      MessageDlg('lvrun failed (exit ' + IntToStr(FProc.ExitStatus) + '):'#10
        + Copy(FProcOut, Max(1, Length(FProcOut) - 1500), MaxInt), mtError, [mbOK], 0);
    end;
  end;
end;

end.
