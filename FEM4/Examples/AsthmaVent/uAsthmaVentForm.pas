unit uAsthmaVentForm;

{ AsthmaVent's window. Left: the ventilator's settings, the patient, and
  run controls. Right: a monitor of the last breath and four strip charts
  of the last 15 s - airway pressure (with the mean alveolar pressure of
  the open units), flow, lung volume above the relaxed FRC (with the
  relaxed volume at the set PEEP), and pleural pressure at mid-height
  (with the patient's muscle pressure). Inspirations are shaded by breath
  type on the pressure chart, and efforts that failed to trigger are
  marked on the pleural chart.

  The model runs in TVentThread (uVentSim's engine) paced to the wall
  clock at the chosen speed; the timer copies its samples and monitor and
  redraws. Ventilator settings take effect at the next breath (PEEP,
  triggers and the pressure limit at once), the patient's effort at
  once. A change of lung (tone, wall, heliox) builds that lung - a couple
  of seconds the first time, cached after - and carries the state over.

  Command line: --snapshot=<prefix> runs --time=<s> (60) at full speed,
  saves <prefix>_<chart>.png and <prefix>_window.bmp, prints the monitor
  and exits; --mode=<0..4>, --patient=<0..3> (presets), --effort,
  --patrate, --peep, --rate, --vt, --pinsp, --ps, --ie, --upright. }

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Math, SyncObjs, Forms, Controls, Graphics, StdCtrls, ExtCtrls, Spin, Dialogs,
  newVM, uVMPlot2D, uLungModel, uVentSim;

const
  RingN = 4000;
  LoopBreaths = 4;
  WindowSec = 15;

type
  TVentThread = class(TThread)
  private
    FEngine: TVentEngine;
    FCacheDir: string;
    FWallBase: QWord;
    FSimBase, FRunWall, FRunSim: Double;
    procedure Sample(const S: TVentSample);
    procedure Rebase;
  public
    Lock: TCriticalSection;
    Ring: array[0..RingN - 1] of TVentSample;
    RingTotal: Int64;
    Mon: TVentMonitor;
    Breaths: array of TBreathRec;
    Missed: array of Double;
    { requests, under Lock }
    ReqVS: TVentSettings; ReqVSNew: Boolean;
    ReqPat: TPatientSettings; ReqLung, ReqEffort, ReqReset: Boolean;
    ReqInspHold, ReqExpHold: Boolean;
    Paused: Boolean;
    Speed: Double;        { 0 = as fast as possible }
    StopAt: Double;       { pause when the model reaches this time (snapshot) }
    Status: string;
    Ready: Boolean;
    SimT, RealFactor: Double;
    constructor Create(const ACacheDir: string; const P: TPatientSettings; const V: TVentSettings);
    destructor Destroy; override;
    procedure Execute; override;
  end;

  TMonCell = record
    Name, Value: TLabel;
  end;

  TVentForm = class(TForm)
  private
    FThread: TVentThread;
    FTimer: TTimer;
    FLeft, FRight, FMonPanel, FPlotPanel: TPanel;
    FPlots: array[0..3] of TVMPlot2D;
    FLoop: TVMPlot2D;      { flow-volume loop of the last LoopBreaths breaths }
    FMode, FPreset, FSpeed: TComboBox;
    FRate, FVT, FPInsp, FPS, FPEEP, FIE, FRise, FTrig, FExpTrig, FPLimit: TFloatSpinEdit;
    FTone, FEffort, FPatRate, FPatTi: TFloatSpinEdit;
    FWall, FHeliox, FSupine: TCheckBox;
    FInfo, FStatus, FAlarm: TLabel;
    FRunBtn: TButton;
    FCells: array of TMonCell;
    FUpdating: Boolean;
    FSnapPrefix: string;
    FSnapTime: Double;
    FSnapDone: Integer;
    function AddSpin(AParent: TWinControl; var Y: Integer; const ACaption: string; AMin, AMax, AStep, AVal: Double;
      ADigits: Integer): TFloatSpinEdit;
    function AddCell(Col, Row: Integer; const AName: string): Integer;
    procedure BuildControls;
    procedure PlotPanelResize(Sender: TObject);
    procedure VentChanged(Sender: TObject);
    procedure PatientChanged(Sender: TObject);
    procedure EffortChanged(Sender: TObject);
    procedure PresetChanged(Sender: TObject);
    procedure RunClick(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure InspHoldClick(Sender: TObject);
    procedure ExpHoldClick(Sender: TObject);
    procedure SpeedChanged(Sender: TObject);
    procedure TimerTick(Sender: TObject);
    function ReadVent: TVentSettings;
    function ReadPatient: TPatientSettings;
    procedure UpdateEnabled;
    procedure Redraw;
    procedure DrawLoop(const S: array of TVentSample; const Br: array of TBreathRec; FRCPeep: Double);
    procedure ShowMonitor(const M: TVentMonitor; const VS: TVentSettings);
    procedure DoSnapshot;
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
  public
    { built in code, no .lfm: Create goes straight to CreateNew }
    constructor Create(AOwner: TComponent); override;
  end;

var
  VentForm: TVentForm;

implementation

function OptStr(const Name: string; var V: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 1 to ParamCount do
    if Pos('--' + Name + '=', ParamStr(i)) = 1 then
    begin
      V := Copy(ParamStr(i), Length(Name) + 4, MaxInt);
      Result := True;
    end;
end;

function HasOpt(const Name: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 1 to ParamCount do
    if ParamStr(i) = '--' + Name then Result := True;
end;

function OptVal(const Name: string; var V: Double): Boolean;
var
  s: string;
begin
  s := '';
  Result := OptStr(Name, s);
  if Result then V := StrToFloat(s);
end;

{ ---------------------------------------------------------------- }

constructor TVentThread.Create(const ACacheDir: string; const P: TPatientSettings; const V: TVentSettings);
begin
  Lock := TCriticalSection.Create;
  FCacheDir := ACacheDir;
  ReqPat := P; ReqVS := V; ReqReset := True;
  Speed := 1; StopAt := -1;
  Status := 'Building the lung...';
  inherited Create(False);
end;

destructor TVentThread.Destroy;
begin
  FEngine.Free;
  Lock.Free;
  inherited;
end;

procedure TVentThread.Sample(const S: TVentSample);
begin
  Lock.Enter;
  try
    Ring[RingTotal mod RingN] := S;
    Inc(RingTotal);
  finally
    Lock.Leave;
  end;
end;

procedure TVentThread.Rebase;
begin
  FWallBase := GetTickCount64;
  FSimBase := FEngine.T;
end;

procedure TVentThread.Execute;
var
  vs: TVentSettings;
  pat: TPatientSettings;
  doVS, doLung, doEffort, doReset, doIH, doEH, paus: Boolean;
  spd, target, st0: Double;
  k, i: Integer;
  w0: QWord;
begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  try
    FEngine := TVentEngine.Create(FCacheDir);
    FEngine.OnSample := Sample;
    while not Terminated do
    begin
      Lock.Enter;
      try
        vs := ReqVS; doVS := ReqVSNew; ReqVSNew := False;
        pat := ReqPat; doLung := ReqLung; doEffort := ReqEffort; doReset := ReqReset;
        ReqLung := False; ReqEffort := False; ReqReset := False;
        doIH := ReqInspHold; doEH := ReqExpHold; ReqInspHold := False; ReqExpHold := False;
        paus := Paused; spd := Speed;
      finally
        Lock.Leave;
      end;
      if doReset then
      begin
        Lock.Enter; Status := 'Building the lung...'; Ready := False; Lock.Leave;
        FEngine.Reset(pat, vs);
        Lock.Enter; RingTotal := 0; SetLength(Breaths, 0); SetLength(Missed, 0); Status := ''; Ready := True; Lock.Leave;
        Rebase;
      end
      else
      begin
        if doVS then FEngine.PendingVS := vs;
        if doLung then
        begin
          Lock.Enter; Status := 'Building the lung...'; Lock.Leave;
          FEngine.ChangeLung(pat);
          Lock.Enter; Status := ''; Lock.Leave;
          Rebase;
        end
        else if doEffort then FEngine.SetEffort(pat);
      end;
      if doIH then FEngine.RequestInspHold;
      if doEH then FEngine.RequestExpHold;
      if paus or ((StopAt > 0) and (FEngine.T >= StopAt)) then
      begin
        Sleep(20);
        Rebase;
        Continue;
      end;
      if spd > 0 then
      begin
        target := FSimBase + spd * (GetTickCount64 - FWallBase) / 1000;
        if FEngine.T > target + 0.25 then begin Sleep(5); Continue; end;
        if FEngine.T < target - 1 then Rebase;   { can't keep up: run slower than asked }
      end;
      w0 := GetTickCount64; st0 := FEngine.T;
      for k := 1 to 25 do FEngine.Step;
      Lock.Enter;
      try
        Mon := FEngine.Mon;
        SimT := FEngine.T;
        FRunWall := FRunWall + (GetTickCount64 - w0) / 1000; FRunSim := FRunSim + FEngine.T - st0;
        if FRunWall > 2 then
        begin
          RealFactor := FRunSim / FRunWall;
          FRunWall := 0; FRunSim := 0;
        end;
        SetLength(Breaths, 0);
        for i := 0 to FEngine.BreathCount - 1 do
          if FEngine.Breath(i).TStart >= FEngine.T - WindowSec - 5 then
          begin
            SetLength(Breaths, Length(Breaths) + 1);
            Breaths[High(Breaths)] := FEngine.Breath(i);
          end;
        Missed := Copy(FEngine.Missed);
      finally
        Lock.Leave;
      end;
    end;
  except
    on E: Exception do
    begin
      Lock.Enter; Status := 'Model stopped: ' + E.Message; Lock.Leave;
    end;
  end;
end;

{ ---------------------------------------------------------------- }

constructor TVentForm.Create(AOwner: TComponent);
var
  P: TPatientSettings;
  V: TVentSettings;
  d: Double;
  s: string;
begin
  inherited CreateNew(AOwner);
  Caption := 'AsthmaVent: mechanical ventilation in acute severe asthma';
  Width := 1400; Height := 920;
  Position := poScreenCenter;
  OnClose := FormClose;
  BuildControls;
  { command line }
  FSnapPrefix := '';
  OptStr('snapshot', FSnapPrefix);
  FSnapTime := 60; OptVal('time', FSnapTime);
  FUpdating := True;
  d := 0; s := '';
  if OptVal('patient', d) then begin FPreset.ItemIndex := Round(d); PresetChanged(nil); end;
  if OptVal('mode', d) then FMode.ItemIndex := Round(d);
  if OptVal('effort', d) then FEffort.Value := d;
  if OptVal('patrate', d) then FPatRate.Value := d;
  if OptVal('peep', d) then FPEEP.Value := d;
  if OptVal('rate', d) then FRate.Value := d;
  if OptVal('vt', d) then FVT.Value := d;
  if OptVal('pinsp', d) then FPInsp.Value := d;
  if OptVal('ps', d) then FPS.Value := d;
  if OptVal('ie', d) then FIE.Value := d;
  if HasOpt('upright') then FSupine.Checked := False;
  FUpdating := False;
  UpdateEnabled;
  P := ReadPatient; V := ReadVent;
  FThread := TVentThread.Create(ExpandFileName(ExtractFilePath(ParamStr(0)) + '../Asthma/cache'), P, V);
  if FSnapPrefix <> '' then
  begin
    FThread.Speed := 0; FThread.StopAt := FSnapTime;
    FSpeed.ItemIndex := FSpeed.Items.Count - 1;
  end;
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 80;
  FTimer.OnTimer := TimerTick;
  FTimer.Enabled := True;
end;

procedure TVentForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  FTimer.Enabled := False;
  if FThread <> nil then
  begin
    FThread.Terminate;
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
end;

function TVentForm.AddSpin(AParent: TWinControl; var Y: Integer; const ACaption: string; AMin, AMax, AStep, AVal: Double;
  ADigits: Integer): TFloatSpinEdit;
var
  L: TLabel;
begin
  L := TLabel.Create(Self);
  L.Parent := AParent; L.Left := 8; L.Top := Y + 4; L.Caption := ACaption;
  Result := TFloatSpinEdit.Create(Self);
  Result.Parent := AParent;
  Result.Left := 190; Result.Top := Y; Result.Width := 78;
  Result.MinValue := AMin; Result.MaxValue := AMax; Result.Increment := AStep;
  Result.DecimalPlaces := ADigits; Result.Value := AVal;
  Inc(Y, 28);
end;

function TVentForm.AddCell(Col, Row: Integer; const AName: string): Integer;
var
  C: TMonCell;
begin
  C.Name := TLabel.Create(Self);
  C.Name.Parent := FMonPanel;
  C.Name.Left := 10 + Col * 160; C.Name.Top := 6 + Row * 44;
  C.Name.Caption := AName;
  C.Name.Font.Size := 8; C.Name.Font.Color := RGBToColor(150, 170, 190);
  C.Value := TLabel.Create(Self);
  C.Value.Parent := FMonPanel;
  C.Value.Left := 10 + Col * 160; C.Value.Top := 20 + Row * 44;
  C.Value.Caption := '-';
  C.Value.Font.Size := 13; C.Value.Font.Style := [fsBold]; C.Value.Font.Color := RGBToColor(240, 240, 120);
  SetLength(FCells, Length(FCells) + 1);
  FCells[High(FCells)] := C;
  Result := High(FCells);
end;

procedure TVentForm.BuildControls;
var
  G: TGroupBox;
  Y, i: Integer;
  B: TButton;
  L: TLabel;
  m: TVentMode;
  V: TVentSettings;
  P: TPatientSettings;
const
  PlotTitles: array[0..3] of string = ('Airway pressure at the Y-piece (solid), mean alveolar of open units (dashed)',
    'Flow at the Y-piece (inspiration positive)', 'Lung volume above the relaxed FRC (dashed: relaxed volume at the set PEEP)',
    'Pleural pressure at mid-height (solid), inspiratory muscle pressure (dashed)');
  PlotY: array[0..3] of string = ('cmH2O', 'L/min', 'mL', 'cmH2O');
begin
  V := DefaultVentSettings; P := DefaultPatientSettings;
  FLeft := TPanel.Create(Self);
  FLeft.Parent := Self; FLeft.Align := alLeft; FLeft.Width := 290; FLeft.BevelOuter := bvNone;

  { ventilator }
  G := TGroupBox.Create(Self);
  G.Parent := FLeft; G.Left := 4; G.Top := 4; G.Width := 280; G.Height := 400; G.Caption := 'Ventilator';
  Y := 4;
  L := TLabel.Create(Self); L.Parent := G; L.Left := 8; L.Top := Y + 4; L.Caption := 'Mode';
  FMode := TComboBox.Create(Self);
  FMode.Parent := G; FMode.Left := 100; FMode.Top := Y; FMode.Width := 168; FMode.Style := csDropDownList;
  for m := Low(TVentMode) to High(TVentMode) do FMode.Items.Add(ModeNames[m]);
  FMode.ItemIndex := Ord(V.Mode);
  FMode.OnChange := VentChanged;
  Inc(Y, 32);
  FRate := AddSpin(G, Y, 'Mandatory rate (/min)', 4, 40, 1, V.Rate, 0);
  FVT := AddSpin(G, Y, 'Tidal volume (mL)', 100, 1200, 25, V.VT, 0);
  FPInsp := AddSpin(G, Y, 'Pinsp above PEEP (cmH2O)', 0, 50, 1, V.PInsp, 0);
  FPS := AddSpin(G, Y, 'PS above PEEP (cmH2O)', 0, 40, 1, V.PS, 0);
  FPEEP := AddSpin(G, Y, 'PEEP (cmH2O)', 0, 20, 1, V.PEEP, 0);
  FIE := AddSpin(G, Y, 'I:E   1 :', 0.5, 6, 0.5, V.IE, 1);
  FRise := AddSpin(G, Y, 'Rise time (s)', 0.0, 0.5, 0.05, V.Rise, 2);
  FTrig := AddSpin(G, Y, 'Flow trigger (L/min)', 0.5, 10, 0.5, V.TrigFlow, 1);
  FExpTrig := AddSpin(G, Y, 'PS cycle-off (% peak flow)', 5, 70, 5, V.ExpTrig, 0);
  FPLimit := AddSpin(G, Y, 'Pressure limit (cmH2O)', 20, 70, 1, V.PLimit, 0);
  for i := 0 to G.ControlCount - 1 do
    if G.Controls[i] is TFloatSpinEdit then TFloatSpinEdit(G.Controls[i]).OnChange := VentChanged;
  FInfo := TLabel.Create(Self);
  FInfo.Parent := G; FInfo.Left := 8; FInfo.Top := Y + 2; FInfo.Font.Size := 8;
  Inc(Y, 22);
  B := TButton.Create(Self); B.Parent := G; B.Left := 8; B.Top := Y; B.Width := 126; B.Caption := 'Insp. hold (Pplat)';
  B.OnClick := InspHoldClick;
  B := TButton.Create(Self); B.Parent := G; B.Left := 142; B.Top := Y; B.Width := 126; B.Caption := 'Exp. hold (PEEPtot)';
  B.OnClick := ExpHoldClick;
  G.Height := Y + 54;

  { patient }
  i := G.Top + G.Height + 6;
  G := TGroupBox.Create(Self);
  G.Parent := FLeft; G.Left := 4; G.Top := i; G.Width := 280; G.Caption := 'Patient';
  Y := 4;
  FPreset := TComboBox.Create(Self);
  FPreset.Parent := G; FPreset.Left := 8; FPreset.Top := Y; FPreset.Width := 260; FPreset.Style := csDropDownList;
  FPreset.Items.Add('Normal lung');
  FPreset.Items.Add('Status asthmaticus (tone 0.8)');
  FPreset.Items.Add('After salbutamol (tone 0.6)');
  FPreset.Items.Add('Near-fatal asthma (tone 0.9)');
  FPreset.ItemIndex := 1;
  FPreset.OnChange := PresetChanged;
  Inc(Y, 32);
  FTone := AddSpin(G, Y, 'Airway tone (0 - 0.9)', 0, 0.9, 0.05, P.Tone, 2);
  FTone.OnChange := PatientChanged;
  FWall := TCheckBox.Create(Self); FWall.Parent := G; FWall.Left := 8; FWall.Top := Y;
  FWall.Caption := 'Asthmatic airway wall (x 3)'; FWall.Checked := P.AsthmaWall; FWall.OnChange := PatientChanged;
  Inc(Y, 24);
  FHeliox := TCheckBox.Create(Self); FHeliox.Parent := G; FHeliox.Left := 8; FHeliox.Top := Y;
  FHeliox.Caption := 'Heliox 70:30'; FHeliox.Checked := P.Heliox; FHeliox.OnChange := PatientChanged;
  Inc(Y, 24);
  FSupine := TCheckBox.Create(Self); FSupine.Parent := G; FSupine.Left := 8; FSupine.Top := Y;
  FSupine.Caption := 'Supine, ventilated (stiff chest wall)'; FSupine.Checked := P.Supine; FSupine.OnChange := PatientChanged;
  FSupine.Hint := 'Chest wall and abdomen relaxed at 2.6 L (upright 4.1), 0.1 L/cmH2O (upright 0.2): FRC 2.3 L against 3.0';
  FSupine.ShowHint := True;
  Inc(Y, 28);
  FEffort := AddSpin(G, Y, 'Effort: peak Pmus (cmH2O)', 0, 40, 1, P.Effort, 0);
  FPatRate := AddSpin(G, Y, 'Patient''s rate (/min)', 4, 40, 1, P.PatRate, 0);
  FPatTi := AddSpin(G, Y, 'Patient''s Ti / Ttot', 0.2, 0.6, 0.05, P.PatTiFrac, 2);
  FEffort.OnChange := EffortChanged; FPatRate.OnChange := EffortChanged; FPatTi.OnChange := EffortChanged;
  L := TLabel.Create(Self); L.Parent := G; L.Left := 8; L.Top := Y; L.Font.Size := 8;
  L.Caption := 'Effort 0 = paralysed. 8 mm tube.';
  G.Height := Y + 40;

  { run }
  i := G.Top + G.Height + 6;
  G := TGroupBox.Create(Self);
  G.Parent := FLeft; G.Left := 4; G.Top := i; G.Width := 280; G.Height := 120; G.Caption := 'Simulation';
  FRunBtn := TButton.Create(Self); FRunBtn.Parent := G; FRunBtn.Left := 8; FRunBtn.Top := 4; FRunBtn.Width := 80;
  FRunBtn.Caption := 'Pause'; FRunBtn.OnClick := RunClick;
  B := TButton.Create(Self); B.Parent := G; B.Left := 94; B.Top := 4; B.Width := 80; B.Caption := 'Restart';
  B.OnClick := ResetClick;
  FSpeed := TComboBox.Create(Self); FSpeed.Parent := G; FSpeed.Left := 182; FSpeed.Top := 4; FSpeed.Width := 86;
  FSpeed.Style := csDropDownList;
  FSpeed.Items.CommaText := '"x 0.5","x 1","x 2","x 4","fastest"';
  FSpeed.ItemIndex := 1; FSpeed.OnChange := SpeedChanged;
  FStatus := TLabel.Create(Self); FStatus.Parent := G; FStatus.Left := 8; FStatus.Top := 40; FStatus.Font.Size := 8;
  FStatus.Width := 260; FStatus.AutoSize := False; FStatus.Height := 50; FStatus.WordWrap := True;

  { right: monitor and plots }
  FRight := TPanel.Create(Self);
  FRight.Parent := Self; FRight.Align := alClient; FRight.BevelOuter := bvNone;
  FMonPanel := TPanel.Create(Self);
  FMonPanel.Parent := FRight; FMonPanel.Align := alTop; FMonPanel.Height := 140;
  FMonPanel.Color := RGBToColor(20, 28, 40); FMonPanel.BevelOuter := bvNone;
  AddCell(0, 0, 'Last breath');           { 0 }
  AddCell(1, 0, 'Ppeak / Pmean');         { 1 }
  AddCell(2, 0, 'Pplat (hold)');          { 2 }
  AddCell(3, 0, 'PEEP set / total / PEEPi'); { 3 }
  AddCell(4, 0, 'VTi / VTe (mL)');        { 4 }
  AddCell(5, 0, 'RR total / spont');      { 5 }
  AddCell(6, 0, 'Minute volume');         { 6 }
  AddCell(0, 1, 'Ti (s) / I:E set');      { 7 }
  AddCell(1, 1, 'EELV above FRC');        { 8 }
  AddCell(2, 1, 'Dynamic hyperinflation');{ 9 }
  AddCell(3, 1, 'VEI (end-insp. vol)');   { 10 }
  AddCell(4, 1, 'Ppl min / max');         { 11 }
  AddCell(5, 1, 'Efforts / missed (min)');{ 12 }
  AddCell(6, 1, 'Patient WOB / units shut'); { 13 }
  FAlarm := TLabel.Create(Self);
  FAlarm.Parent := FMonPanel; FAlarm.Left := 10; FAlarm.Top := 112;
  FAlarm.Font.Size := 11; FAlarm.Font.Style := [fsBold]; FAlarm.Font.Color := RGBToColor(255, 90, 80);
  FAlarm.Caption := '';
  FPlotPanel := TPanel.Create(Self);
  FPlotPanel.Parent := FRight; FPlotPanel.Align := alClient; FPlotPanel.BevelOuter := bvNone;
  FPlotPanel.OnResize := PlotPanelResize;
  for i := 0 to 3 do
  begin
    FPlots[i] := TVMPlot2D.Create(Self);
    FPlots[i].Parent := FPlotPanel;
    FPlots[i].Title := PlotTitles[i];
    FPlots[i].YAxisTitle := PlotY[i];
    if i = 3 then FPlots[i].XAxisTitle := 'time (s)' else FPlots[i].XAxisTitle := '';
    FPlots[i].LegendCorner := lcTopLeft;
    FPlots[i].ClearSeries;
  end;
  FLoop := TVMPlot2D.Create(Self);
  FLoop.Parent := FPlotPanel;
  FLoop.Title := Format('Flow-volume loop, last %d breaths', [LoopBreaths]);
  FLoop.XAxisTitle := 'volume above relaxed FRC (mL)';
  FLoop.YAxisTitle := 'flow (L/min), insp. up';
  FLoop.ClearSeries;
  PlotPanelResize(nil);
end;

procedure TVentForm.PlotPanelResize(Sender: TObject);
var
  i, h, lw: Integer;
begin
  { the loop sits to the right of the pressure and flow traces }
  h := FPlotPanel.ClientHeight div 4;
  lw := Min(Round(2.6 * h), FPlotPanel.ClientWidth div 3);
  for i := 0 to 3 do
    if i < 2 then FPlots[i].SetBounds(0, i * h, FPlotPanel.ClientWidth - lw, h)
    else FPlots[i].SetBounds(0, i * h, FPlotPanel.ClientWidth, h);
  FLoop.SetBounds(FPlotPanel.ClientWidth - lw, 0, lw, 2 * h);
end;

function TVentForm.ReadVent: TVentSettings;
begin
  Result.Mode := TVentMode(Max(0, FMode.ItemIndex));
  Result.Rate := FRate.Value; Result.VT := FVT.Value; Result.PInsp := FPInsp.Value; Result.PS := FPS.Value;
  Result.PEEP := FPEEP.Value; Result.IE := FIE.Value; Result.Rise := FRise.Value; Result.TrigFlow := FTrig.Value;
  Result.ExpTrig := FExpTrig.Value; Result.PLimit := FPLimit.Value;
end;

function TVentForm.ReadPatient: TPatientSettings;
begin
  Result.Tone := FTone.Value; Result.AsthmaWall := FWall.Checked; Result.Heliox := FHeliox.Checked;
  Result.Supine := FSupine.Checked;
  Result.Effort := FEffort.Value; Result.PatRate := FPatRate.Value; Result.PatTiFrac := FPatTi.Value;
end;

procedure TVentForm.UpdateEnabled;
var
  m: TVentMode;
  V: TVentSettings;
  tm, ti: Double;
begin
  m := TVentMode(Max(0, FMode.ItemIndex));
  FVT.Enabled := m in [vmVCCMV, vmVCSIMV];
  FPInsp.Enabled := m in [vmPCCMV, vmPCSIMV, vmCPAPPS];
  FPS.Enabled := m in [vmVCSIMV, vmPCSIMV, vmCPAPPS];
  FExpTrig.Enabled := FPS.Enabled;
  V := ReadVent;
  tm := 60 / V.Rate; ti := tm / (1 + V.IE);
  if m = vmCPAPPS then
    FInfo.Caption := Format('Apnoea backup after 20 s: PC, Ti %.2f s', [ti])
  else if m in [vmVCCMV, vmVCSIMV] then
    FInfo.Caption := Format('Ti %.2f s, Te %.2f s, insp. flow %.0f L/min', [ti, tm - ti, V.VT / 1000 / ti * 60])
  else
    FInfo.Caption := Format('Ti %.2f s, Te %.2f s', [ti, tm - ti]);
end;

procedure TVentForm.VentChanged(Sender: TObject);
begin
  if FUpdating then Exit;
  UpdateEnabled;
  if FThread = nil then Exit;
  FThread.Lock.Enter;
  FThread.ReqVS := ReadVent; FThread.ReqVSNew := True;
  FThread.Lock.Leave;
end;

procedure TVentForm.PatientChanged(Sender: TObject);
begin
  if FUpdating or (FThread = nil) then Exit;
  FThread.Lock.Enter;
  FThread.ReqPat := ReadPatient; FThread.ReqLung := True;
  FThread.Lock.Leave;
end;

procedure TVentForm.EffortChanged(Sender: TObject);
begin
  if FUpdating or (FThread = nil) then Exit;
  FThread.Lock.Enter;
  FThread.ReqPat := ReadPatient; FThread.ReqEffort := True;
  FThread.Lock.Leave;
end;

procedure TVentForm.PresetChanged(Sender: TObject);
var
  was: Boolean;
begin
  was := FUpdating;
  FUpdating := True;
  case FPreset.ItemIndex of
    0: begin FTone.Value := 0; FWall.Checked := False; end;
    1: begin FTone.Value := 0.8; FWall.Checked := True; end;
    2: begin FTone.Value := 0.6; FWall.Checked := True; end;
    3: begin FTone.Value := 0.9; FWall.Checked := True; end;
  end;
  FUpdating := was;
  PatientChanged(nil);
end;

procedure TVentForm.RunClick(Sender: TObject);
begin
  FThread.Lock.Enter;
  FThread.Paused := not FThread.Paused;
  if FThread.Paused then FRunBtn.Caption := 'Run' else FRunBtn.Caption := 'Pause';
  FThread.Lock.Leave;
end;

procedure TVentForm.ResetClick(Sender: TObject);
begin
  FThread.Lock.Enter;
  FThread.ReqPat := ReadPatient; FThread.ReqVS := ReadVent; FThread.ReqReset := True;
  FThread.Lock.Leave;
end;

procedure TVentForm.InspHoldClick(Sender: TObject);
begin
  FThread.Lock.Enter; FThread.ReqInspHold := True; FThread.Lock.Leave;
end;

procedure TVentForm.ExpHoldClick(Sender: TObject);
begin
  FThread.Lock.Enter; FThread.ReqExpHold := True; FThread.Lock.Leave;
end;

procedure TVentForm.SpeedChanged(Sender: TObject);
const
  Speeds: array[0..4] of Double = (0.5, 1, 2, 4, 0);
begin
  FThread.Lock.Enter;
  FThread.Speed := Speeds[EnsureRange(FSpeed.ItemIndex, 0, 4)];
  FThread.Lock.Leave;
end;

function Fmt1(x: Double): string;
begin
  if IsNan(x) then Result := '-' else Result := Format('%.1f', [x]);
end;

procedure TVentForm.ShowMonitor(const M: TVentMonitor; const VS: TVentSettings);
var
  s: string;
begin
  if M.Kind = bkNone then s := '-'
  else
  begin
    s := KindNames[M.Kind];
    if M.Mandatory then s := s + ' mand.' else s := s + ' spont.';
    if M.Triggered then s := s + ' (trig)';
  end;
  FCells[0].Value.Caption := s;
  FCells[1].Value.Caption := Format('%.1f / %.1f', [M.Ppeak, M.Pmean]);
  FCells[2].Value.Caption := Fmt1(M.Pplat);
  if IsNan(M.PEEPtot) then FCells[3].Value.Caption := Format('%.0f / - / -', [VS.PEEP])
  else FCells[3].Value.Caption := Format('%.0f / %.1f / %.1f', [VS.PEEP, M.PEEPtot, M.PEEPtot - VS.PEEP]);
  FCells[4].Value.Caption := Format('%.0f / %.0f', [M.VTi, M.VTe]);
  FCells[5].Value.Caption := Format('%.0f / %.0f', [M.RRTot, M.RRSpont]);
  FCells[6].Value.Caption := Format('%.1f L/min', [M.MV]);
  FCells[7].Value.Caption := Format('%.2f / 1:%.1f', [M.Ti, VS.IE]);
  FCells[8].Value.Caption := Format('%.0f mL', [M.EELV]);
  FCells[9].Value.Caption := Format('%.0f mL', [M.DynHyper]);
  FCells[10].Value.Caption := Format('%.0f mL', [M.VEI]);
  FCells[11].Value.Caption := Format('%.1f / %.1f', [M.PplMin, M.PplMax]);
  FCells[12].Value.Caption := Format('%d / %d', [M.Efforts, M.Missed]);
  FCells[13].Value.Caption := Format('%.1f J/min / %d', [M.WOB, M.UnitsShut]);
  s := M.Alarm;
  if M.VEI > 1400 then s := Trim(s + '   VEI > 1.4 L (Tuxen): risk of hypotension and barotrauma');
  if (not IsNan(M.Pplat)) and (M.Pplat > 30) then s := Trim(s + '   Pplat > 30 cmH2O');
  FAlarm.Caption := s;
end;

function NiceLo(x, Step: Double): Double;
begin
  Result := Step * Floor(x / Step - 1e-9);
end;

function NiceHi(x, Step: Double): Double;
begin
  Result := Step * Ceil(x / Step + 1e-9);
end;

procedure TVentForm.Redraw;
var
  n, i, j, first: Integer;
  total: Int64;
  S: array of TVentSample;
  X, Y0, Y1, Sc: TVMobj;
  M: TVentMonitor;
  Br: array of TBreathRec;
  Ms: array of Double;
  tEnd, lo, hi, frcPeep, v: Double;
  st, cap: string;
  VS: TVentSettings;
  col: TColor;

  procedure ScaleSeries(var AY: TVMobj; ALo, AHi: Double);
  var
    k: Integer;
  begin
    AY := TVMobj.Create(1, n);
    for k := 0 to n - 1 do AY[0, k] := ALo;
    AY[0, 0] := AHi;
  end;

begin
  FThread.Lock.Enter;
  try
    total := FThread.RingTotal;
    n := Min(total, Round(WindowSec / SampleDt));
    n := Min(n, RingN);
    SetLength(S, n);
    for i := 0 to n - 1 do S[i] := FThread.Ring[(total - n + i) mod RingN];
    M := FThread.Mon;
    Br := Copy(FThread.Breaths);
    Ms := Copy(FThread.Missed);
    st := FThread.Status;
    if st = '' then
      if FThread.Paused then st := 'Paused'
      else st := Format('t = %.0f s; model runs at %.1f x real time', [FThread.SimT, FThread.RealFactor]);
  finally
    FThread.Lock.Leave;
  end;
  FStatus.Caption := st;
  VS := ReadVent;
  if n < 3 then Exit;
  ShowMonitor(M, VS);
  tEnd := S[n - 1].T;
  X := TVMobj.Create(1, n);
  for i := 0 to n - 1 do X[0, i] := S[i].T;
  { pressure }
  Y0 := TVMobj.Create(1, n); Y1 := TVMobj.Create(1, n);
  lo := 0; hi := 30;
  for i := 0 to n - 1 do
  begin
    Y0[0, i] := S[i].Paw; Y1[0, i] := S[i].Palv;
    lo := Min(lo, Min(S[i].Paw, S[i].Palv)); hi := Max(hi, Max(S[i].Paw, S[i].Palv));
  end;
  ScaleSeries(Sc, NiceLo(lo, 10), NiceHi(hi, 10));
  FPlots[0].ClearSeries;
  FPlots[0].SetSeriesStyle(0, RGBToColor(200, 120, 0), 2, plsSolid, '');
  FPlots[0].SetSeriesStyle(1, RGBToColor(120, 40, 160), 1.5, plsDash, '');
  FPlots[0].SetSeriesStyle(2, clWhite, 1, plsNone, '');
  FPlots[0].SetData(X, [Y0, Y1, Sc]);
  FPlots[0].ClearXBands;
  first := 0;
  for j := 0 to High(Br) do
  begin
    if Br[j].TEndInsp < S[0].T then Continue;
    if (j = High(Br)) or (Br[j].TEndInsp <= Br[j].TStart) then v := tEnd else v := Br[j].TEndInsp;
    if (j < High(Br)) and (Br[j].TEndInsp <= Br[j].TStart) then v := Br[j + 1].TStart;
    case Br[j].Kind of
      bkVC: col := RGBToColor(110, 160, 230);
      bkPC: col := RGBToColor(110, 200, 120);
    else col := RGBToColor(240, 180, 90);
    end;
    cap := KindNames[Br[j].Kind];
    if Br[j].Mandatory and Br[j].Triggered then cap := cap + ' (s)';
    FPlots[0].AddXBand(Max(S[0].T, Br[j].TStart), Min(tEnd, v), col, cap);
    Inc(first);
  end;
  { flow }
  Y0 := TVMobj.Create(1, n);
  lo := -60; hi := 60;
  for i := 0 to n - 1 do
  begin
    Y0[0, i] := S[i].Flow; lo := Min(lo, S[i].Flow); hi := Max(hi, S[i].Flow);
  end;
  ScaleSeries(Sc, NiceLo(lo, 30), NiceHi(hi, 30));
  FPlots[1].ClearSeries;
  FPlots[1].SetSeriesStyle(0, RGBToColor(0, 130, 90), 2, plsSolid, '');
  FPlots[1].SetSeriesStyle(1, clWhite, 1, plsNone, '');
  FPlots[1].SetData(X, [Y0, Sc]);
  { volume }
  Y0 := TVMobj.Create(1, n); Y1 := TVMobj.Create(1, n);
  frcPeep := 1000 * (M.FRCPeep - M.FRC);
  lo := 0; hi := 1000;
  for i := 0 to n - 1 do
  begin
    Y0[0, i] := S[i].Vol; Y1[0, i] := frcPeep;
    lo := Min(lo, S[i].Vol); hi := Max(hi, S[i].Vol);
  end;
  ScaleSeries(Sc, NiceLo(lo, 250), NiceHi(hi, 250));
  FPlots[2].ClearSeries;
  FPlots[2].SetSeriesStyle(0, RGBToColor(30, 90, 200), 2, plsSolid, '');
  FPlots[2].SetSeriesStyle(1, RGBToColor(120, 120, 120), 1.5, plsDash, '');
  FPlots[2].SetSeriesStyle(2, clWhite, 1, plsNone, '');
  FPlots[2].SetData(X, [Y0, Y1, Sc]);
  { pleural }
  Y0 := TVMobj.Create(1, n); Y1 := TVMobj.Create(1, n);
  lo := -10; hi := 10;
  for i := 0 to n - 1 do
  begin
    Y0[0, i] := S[i].Ppl; Y1[0, i] := S[i].Pmus;
    lo := Min(lo, Min(S[i].Ppl, S[i].Pmus)); hi := Max(hi, Max(S[i].Ppl, S[i].Pmus));
  end;
  ScaleSeries(Sc, NiceLo(lo, 5), NiceHi(hi, 5));
  FPlots[3].ClearSeries;
  FPlots[3].SetSeriesStyle(0, RGBToColor(200, 30, 40), 2, plsSolid, '');
  FPlots[3].SetSeriesStyle(1, RGBToColor(150, 150, 150), 1.5, plsDash, '');
  FPlots[3].SetSeriesStyle(2, clWhite, 1, plsNone, '');
  FPlots[3].SetData(X, [Y0, Y1, Sc]);
  FPlots[3].ClearXMarkers;
  for j := 0 to High(Ms) do
    if (Ms[j] >= S[0].T) and (Ms[j] <= tEnd) then FPlots[3].AddXMarker(Ms[j], RGBToColor(220, 0, 0), 'missed trigger');
  DrawLoop(S, Br, frcPeep);
end;

{ Flow against volume for the last LoopBreaths breaths in the window, one
  series each from its start to the next breath's start (the newest is the
  breath in progress, so its loop grows live). Volume is above the relaxed
  FRC, as in the volume trace, so gas trapping moves the loops right, and
  expiratory flow still running when the next breath starts shows as a
  loop that does not close on the zero-flow line. }
procedure TVentForm.DrawLoop(const S: array of TVentSample; const Br: array of TBreathRec; FRCPeep: Double);
var
  i, j, k, j0, nb, ser: Integer;
  t0, t1, vlo, vhi, flo, fhi, f: Double;
  inB: array of Integer;  { breath of each sample, or -1 }
begin
  FLoop.ClearSeries;
  FLoop.ClearXMarkers;
  { breaths that start inside the window, newest LoopBreaths of them }
  j0 := Length(Br);
  nb := 0;
  while (j0 > 0) and (nb < LoopBreaths) and (Br[j0 - 1].TStart >= S[0].T) do
  begin
    Dec(j0); Inc(nb);
  end;
  if nb = 0 then Exit;
  SetLength(inB, Length(S));
  vlo := FRCPeep; vhi := FRCPeep + 500; flo := -30; fhi := 30;
  for i := 0 to High(S) do
  begin
    inB[i] := -1;
    for k := 0 to nb - 1 do
    begin
      j := j0 + k;
      t0 := Br[j].TStart;
      if j < High(Br) then t1 := Br[j + 1].TStart else t1 := S[High(S)].T + 1;
      if (S[i].T >= t0) and (S[i].T <= t1) then inB[i] := k;
    end;
    if inB[i] >= 0 then
    begin
      vlo := Min(vlo, S[i].Vol); vhi := Max(vhi, S[i].Vol);
      flo := Min(flo, S[i].Flow); fhi := Max(fhi, S[i].Flow);
    end;
  end;
  { the axis range first, in round steps, as a hidden series, so the ticks
    are settled before the loops go in (PlotXY refits on every point) }
  FLoop.SetSeriesStyle(0, clWhite, 1, plsNone, '');
  FLoop.PlotXY(NiceLo(vlo, 250), NiceLo(flo, 30), 0);
  FLoop.PlotXY(NiceHi(vhi, 250), NiceHi(fhi, 30), 0);
  for k := 0 to nb - 1 do
  begin
    { oldest palest, newest dark and thick }
    f := (k + 1) / nb;
    FLoop.SetSeriesStyle(k + 1, RGBToColor(Round(200 - 200 * f), Round(225 - 115 * f), Round(210 - 140 * f)),
      1 + Ord(k = nb - 1) * 1.5, plsSolid, '');
  end;
  { every third sample (0.06 s), plus any where the flow jumps, so square
    flow edges stay square: PlotXY costs a refit per point }
  for i := 0 to High(S) do
    if inB[i] >= 0 then
      if (i mod 3 = 0) or (i = High(S)) or ((i > 0) and (Abs(S[i].Flow - S[i - 1].Flow) > 4))
        or ((i < High(S)) and (Abs(S[i + 1].Flow - S[i].Flow) > 4)) or ((i > 0) and (inB[i - 1] <> inB[i]))
        or ((i < High(S)) and (inB[i + 1] <> inB[i])) then
        FLoop.PlotXY(S[i].Vol, S[i].Flow, inB[i] + 1);
  FLoop.AddXMarker(FRCPeep, RGBToColor(120, 120, 120), 'relaxed at PEEP');
end;

procedure TVentForm.TimerTick(Sender: TObject);
var
  rdy: Boolean;
  t: Double;
begin
  Redraw;
  if FSnapPrefix = '' then Exit;
  FThread.Lock.Enter;
  rdy := FThread.Ready; t := FThread.SimT;
  FThread.Lock.Leave;
  if rdy and (t >= FSnapTime) then
  begin
    Inc(FSnapDone);
    if FSnapDone = 3 then DoSnapshot;
  end;
end;

procedure TVentForm.DoSnapshot;
const
  Names: array[0..3] of string = ('pressure', 'flow', 'volume', 'pleural');
var
  i: Integer;
  bmp: TBitmap;
  M: TVentMonitor;
begin
  FTimer.Enabled := False;
  for i := 0 to 3 do FPlots[i].SaveToPNG(Format('%s_%s.png', [FSnapPrefix, Names[i]]));
  FLoop.SaveToPNG(FSnapPrefix + '_loop.png');
  bmp := GetFormImage;
  bmp.SaveToFile(FSnapPrefix + '_window.bmp');
  bmp.Free;
  FThread.Lock.Enter; M := FThread.Mon; FThread.Lock.Leave;
  for i := 0 to High(FCells) do Writeln(Format('%-28s %s', [FCells[i].Name.Caption, FCells[i].Value.Caption]));
  Writeln('alarm: ', FAlarm.Caption);
  Close;
end;

end.
