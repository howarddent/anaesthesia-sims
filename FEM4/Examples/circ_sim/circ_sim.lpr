program circ_sim;

{ The finite-element left ventricle and the arterial pulse wave it
  drives, in one window: the ventricle's wall motion and loop on one
  tab, the aortic pulse on another, and one Compute for both. The window
  is uCircSimForm; the models and viewers are LeftVentricle's and
  Aorta's own units, and the ventricle ejecting into the arterial tree
  is computed by ../LeftVentricle/lvrun --arteries, which must be built.

    circ_sim [--compute] [--hr=<n>] [--lvbeats=<n>] [--t0=<kPa>] [--tab=<0|1>]
             [--preset=<0..3>] [--pvr=<x>] [--snapshot=<prefix>]

    --compute            press Compute at the start
    --preset=<0..3>      the arteries of a child of 7, an adult of 40 [default], a person of 80,
                         a person of 80 with hypertension
    --pvr=<x>            peripheral resistance x: vasoconstriction above 1, dilatation below [1]
    --hr, --lvbeats      the heart rate and the ventricle's beats to run
    --t0=<kPa>           peak active fibre stress: contractility [145]
    --tab=<0|1>          open on the ventricle (0) or the aortic pulse (1)
    --snapshot=<prefix>  wait for the computation, save both tabs'
                         pictures as <prefix>_lv_*.png, <prefix>_aorta_*.png
                         and the window as <prefix>_tab0.bmp, _tab1.bmp, exit

  Build:  lazbuild --ws=gtk2 circ_sim.lpi }

{$mode delphi}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces,
  Forms, SysUtils, Graphics, cblas,
  uLVViewForm, uAortaViewForm, uCircSimForm;

var
  Form: TCircSimForm;
  Snapshot, Arg: string;
  i, k, Tab, HR, LVBeats, Preset: Integer;
  PVR, T0: Double;
  DoCompute: Boolean;
  Bmp: TBitmap;

procedure Pump(Ms: Integer);
var
  t: QWord;
begin
  t := GetTickCount64;
  while GetTickCount64 - t < QWord(Ms) do
  begin
    Application.ProcessMessages;
    Sleep(10);
  end;
end;

begin
  InitializeCBLAS;
  DefaultFormatSettings.DecimalSeparator := '.';
  Snapshot := ''; Tab := 0; DoCompute := False; HR := 0; LVBeats := 0; Preset := -1; PVR := 1; T0 := 0;
  for i := 1 to ParamCount do
  begin
    Arg := ParamStr(i);
    if Copy(Arg, 1, 11) = '--snapshot=' then Snapshot := Copy(Arg, 12, MaxInt)
    else if Copy(Arg, 1, 6) = '--tab=' then Tab := StrToInt(Copy(Arg, 7, MaxInt))
    else if Copy(Arg, 1, 5) = '--hr=' then HR := StrToInt(Copy(Arg, 6, MaxInt))
    else if Copy(Arg, 1, 10) = '--lvbeats=' then LVBeats := StrToInt(Copy(Arg, 11, MaxInt))
    else if Copy(Arg, 1, 9) = '--preset=' then Preset := StrToInt(Copy(Arg, 10, MaxInt))
    else if Copy(Arg, 1, 5) = '--t0=' then T0 := StrToFloat(Copy(Arg, 6, MaxInt))
    else if Copy(Arg, 1, 6) = '--pvr=' then PVR := StrToFloat(Copy(Arg, 7, MaxInt))
    else if Arg = '--compute' then DoCompute := True
    else
    begin
      WriteLn('Usage: circ_sim [--compute] [--hr=<n>] [--lvbeats=<n>] [--t0=<kPa>] [--tab=<0|1>] [--preset=<0..3>] [--pvr=<x>] [--snapshot=<prefix>]');
      Halt(1);
    end;
  end;
  Application.Initialize;
  Form := TCircSimForm.CreateNew(Application);
  Form.SetVentricle(HR, LVBeats, T0);
  if Preset >= 0 then Form.SetPreset(Preset);
  Form.SetResistance(PVR);
  Form.Show;
  Pump(200);
  Form.Start;
  if DoCompute then
  begin
    Form.Compute;
    while Form.Computing do Pump(100);
  end;
  Form.ShowTab(Tab);
  if Snapshot <> '' then
  begin
    for k := 0 to 1 do
    begin
      Form.ShowTab(k);
      Pump(600);
      if k = 0 then
      begin
        Form.LVForm.ShowFrameAt(Form.LVForm.Anim.FrameAtTime(0.23));
        Pump(200);
        Form.LVForm.SaveSnapshot(Snapshot + '_lv');
      end
      else
      begin
        Form.AoForm.ShowFrameAt(Form.AoForm.FrameAtTime(0.23));
        Pump(200);
        Form.AoForm.SaveSnapshot(Snapshot + '_aorta');
      end;
      Bmp := Form.GetFormImage;
      Bmp.SaveToFile(Snapshot + '_tab' + IntToStr(k) + '.bmp');
      Bmp.Free;
    end;
    Halt(0);
  end;
  Application.Run;
end.
