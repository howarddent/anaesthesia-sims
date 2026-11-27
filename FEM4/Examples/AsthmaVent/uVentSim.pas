unit uVentSim;

{ The ventilator and patient behind AsthmaVent: the stage 5-9 patchy lung
  (../Asthma/uPatchyLung, 256 units, gravity, closure hysteresis) behind
  an endotracheal tube (Rohrer K1 1, K2 4, as ventrun), breathing with
  its own inspiratory muscles, on a ventilator with these modes:

    VC-CMV (A/C)     volume-controlled mandatory breaths, square flow
                     VT / Ti; a patient trigger brings the next one
                     forward (assist-control).
    PC-CMV (A/C)     the same, pressure-controlled: PEEP + Pinsp for Ti.
    VC-SIMV + PS     mandatory VC breaths at the set rate, synchronised
                     to a patient trigger inside the trigger window (the
                     last half of each mandatory period, at most 5 s);
                     a trigger outside it gets a pressure-supported
                     breath.
    PC-SIMV + PS     the same with PC mandatory breaths.
    CPAP + PS        every breath patient-triggered and pressure
                     supported; after 20 s of apnoea a PC backup breath.

  Ti of a mandatory breath is 60/rate x I/(I+E). Pressure-controlled and
  supported breaths rise linearly to their pressure over the rise time.
  A supported breath ends when inspiratory flow falls below the
  expiratory trigger (a fraction of its peak flow) or after 3 s. A VC
  breath ends early, with an alarm, if the airway pressure passes the
  pressure limit.

  TRIGGER   flow: inspiratory flow at the Y-piece above the trigger flow,
  from 0.2 s into expiration. With intrinsic PEEP the patient must first
  overcome it before flow reverses, so efforts can fail to trigger; an
  effort that starts in expiration and ends without a trigger is counted
  as missed.

  PATIENT   the inspiratory muscle pressure of spontrun: a half-sine of
  the set peak over Ti = TiFrac x period, decaying with time constant
  0.15 s after it, at the patient's own rate with an 8 % jitter of the
  period. Effort 0 is a paralysed patient. Pleural pressure (mid-height)
  is the chest wall's recoil less the muscle pressure.

  POSTURE   upright (the Asthma stages' chest wall, relaxed at 4.1 L,
  0.2 L/cmH2O) or supine and ventilated (the default): the abdomen's load
  lowers the relaxed volume to 2.6 L and halves the compliance, so FRC
  falls to 2.3 L and more of each breath's pressure reaches the pleura.
  Pleural pressure is then about 0 at end-expiration with PEEP 5 and
  +6 cmH2O at the end of a 500 mL breath (upright: -3 and -0.6). Changing
  posture re-references the volume trace to the new relaxed FRC.

  HOLDS   an inspiratory hold (0.5 s occlusion after the next mandatory
  breath) gives the plateau pressure; an expiratory hold (2 s occlusion
  in place of the start of the next mandatory breath) gives total PEEP,
  and intrinsic PEEP = total - set PEEP. As in stage 5, units shut behind
  closed airways do not show in the hold.

  Units: the lung works in kPa, mm3/s and litres; everything here that
  is shown is cmH2O, L/min and mL. }

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Math, uTubeLaw, uAirwayRing, uAlveolus, uLungModel, uPatchyLung;

type
  TVentMode = (vmVCCMV, vmPCCMV, vmVCSIMV, vmPCSIMV, vmCPAPPS);
  TBreathKind = (bkNone, bkVC, bkPC, bkPS);
  TVentPhase = (phExp, phInsp, phInspHold, phExpHold);

  TVentSettings = record
    Mode: TVentMode;
    Rate: Double;      { mandatory, /min }
    VT: Double;        { mL }
    PInsp: Double;     { cmH2O above PEEP }
    PS: Double;        { cmH2O above PEEP }
    PEEP: Double;      { cmH2O }
    IE: Double;        { E of I:E = 1:E }
    Rise: Double;      { s }
    TrigFlow: Double;  { L/min }
    ExpTrig: Double;   { % of peak inspiratory flow }
    PLimit: Double;    { cmH2O }
  end;

  TPatientSettings = record
    Tone: Double;       { airway smooth muscle activation 0..0.9 }
    AsthmaWall: Boolean;{ wall x 3 and a 10 % clustered spread of tone }
    Heliox: Boolean;
    Supine: Boolean;    { supine, ventilated: the abdomen's load on a stiffer chest wall }
    Effort: Double;     { peak muscle pressure, cmH2O }
    PatRate: Double;    { /min }
    PatTiFrac: Double;
  end;

  TVentSample = record
    T, Paw, Palv, Flow, Vol, Ppl, Pmus: Double;  { s, cmH2O, cmH2O, L/min, mL, cmH2O, cmH2O }
  end;

  TBreathRec = record
    Kind: TBreathKind;
    Mandatory, Triggered: Boolean;
    TStart, TEndInsp, Ppeak, VTi, VTe, EELV, VEI: Double;
    Done: Boolean;      { its expiration has ended }
  end;

  TVentMonitor = record
    Kind: TBreathKind;
    Mandatory, Triggered: Boolean;
    Ppeak, Pmean, VTi, VTe, Ti: Double;
    RRTot, RRSpont, MV: Double;
    EELV, DynHyper, VEI: Double;  { mL: end-expiratory above FRC, above relaxed at PEEP; end-inspiratory above FRC }
    PplMin, PplMax: Double;
    WOB: Double;                  { patient, J/min }
    Efforts, Missed: Integer;     { in the last minute }
    Pplat, PEEPtot: Double;       { NaN until a hold is done }
    UnitsShut, NU: Integer;
    FRC, FRCPeep: Double;         { L }
    Alarm: string;
  end;

  TPatientMuscle = class
  public
    Pmax, Rate, TiFrac, Tau: Double;
    CycleStart, CycleLen: Double;
    Index: Integer;
    constructor Create;
    function P(t, V: Double): Double;
    function InEffort(t: Double): Boolean;
    function Ti: Double;
  end;

  TSampleEvent = procedure(const S: TVentSample) of object;

  TVentEngine = class
  private
    FLungs: TStringList;        { built lungs by key, owned }
    FAlv: TAlveolusParams;
    FRefLaws: array[0..NWall - 1] of TTubeLaw;
    FSim: TPatchySim;
    FLung: TPatchyLung;
    FMus: TPatientMuscle;
    FPhase: TVentPhase;
    FKind: TBreathKind;
    FMandatory, FTriggered: Boolean;
    FBreathStart, FExpStart, FPhaseStart, FTi, FPeakFlow, FDue, FLastBreath: Double;
    FHoldInsp, FHoldExp: Boolean;
    FPendingMand: Boolean;       { the breath to give after an expiratory hold }
    FBreaths: array of TBreathRec;
    FEffortStart: array of Double;
    FEffortMissed: array of Boolean;
    FCurEffort: Integer;
    FEffortTrig, FEffortInExp: Boolean;
    FPawSum: array of Double;    { per 0.02 s for Pmean }
    FWork: array of Double;      { per breath start time / work pairs }
    FWorkT: array of Double;
    FWorkAcc: Double;
    FStepN: Integer;
    FPplMin, FPplMax: Double;
    FFRCPeepAt: Double;
    FAlarmUntil: Double;
    FRunStart: Double;
    procedure BuildLaws;
    function GetLung(const P: TPatientSettings): TPatchyLung;
    function GetT: Double;
    procedure SetControl;
    procedure StartBreath(AKind: TBreathKind; AMand, ATrig: Boolean);
    procedure EndInspiration;
    procedure UpdateMonitor;
    procedure SetAlarm(const S: string);
    function Inflow: Double;
  public
    VS: TVentSettings;           { the settings in force }
    PendingVS: TVentSettings;    { taken up at the start of each breath (PEEP at once) }
    PS_: TPatientSettings;
    Dt: Double;
    Mon: TVentMonitor;
    OnSample: TSampleEvent;
    Missed: array of Double;     { times of missed efforts, last minute }
    constructor Create(const ACacheDir: string);
    destructor Destroy; override;
    { build or fetch the lung and start relaxed at PEEP }
    procedure Reset(const P: TPatientSettings; const V: TVentSettings);
    { change the lung (tone, wall, heliox) keeping the state }
    procedure ChangeLung(const P: TPatientSettings);
    procedure SetEffort(const P: TPatientSettings);
    procedure RequestInspHold;
    procedure RequestExpHold;
    procedure Step;
    function BreathCount: Integer;
    function Breath(i: Integer): TBreathRec;
    property T: Double read GetT;
    property Phase: TVentPhase read FPhase;
    property Lung: TPatchyLung read FLung;
  end;

const
  ModeNames: array[TVentMode] of string = ('VC-CMV (A/C)', 'PC-CMV (A/C)', 'VC-SIMV + PS', 'PC-SIMV + PS', 'CPAP + PS');
  KindNames: array[TBreathKind] of string = ('', 'VC', 'PC', 'PS');
  HelioxRho = 0.554 / 1.20;
  HelioxVisc = 1.09;
  { supine, ventilated (assumed round values): the chest wall and abdomen
    relaxed at 2.6 L, not 4.1, with half the compliance, 0.1 L/cmH2O;
    the gravity gradient across an 18 cm front-to-back depth, not 24 cm
    top to bottom. Relaxed FRC 2.3 L against 3.0 upright. }
  SupineCwRelax = 2.6;
  SupineCwComp = 0.1;
  SupineHeight = 18;
  SampleDt = 0.02;

function DefaultVentSettings: TVentSettings;
function DefaultPatientSettings: TPatientSettings;

implementation

function DefaultVentSettings: TVentSettings;
begin
  Result.Mode := vmVCSIMV;
  Result.Rate := 12; Result.VT := 500; Result.PInsp := 20; Result.PS := 10; Result.PEEP := 5;
  Result.IE := 2; Result.Rise := 0.1; Result.TrigFlow := 2; Result.ExpTrig := 25; Result.PLimit := 50;
end;

function DefaultPatientSettings: TPatientSettings;
begin
  Result.Tone := 0.8; Result.AsthmaWall := True; Result.Heliox := False; Result.Supine := True;
  Result.Effort := 8; Result.PatRate := 18; Result.PatTiFrac := 0.35;
end;

{ ---------------------------------------------------------------- }

constructor TPatientMuscle.Create;
begin
  inherited Create;
  Pmax := 0; Rate := 18; TiFrac := 0.35; Tau := 0.15;
  CycleStart := 0.7; CycleLen := 60 / Rate; Index := 0;
end;

function TPatientMuscle.P(t, V: Double): Double;
var
  tb, ti: Double;
begin
  while t >= CycleStart + CycleLen do
  begin
    CycleStart := CycleStart + CycleLen;
    CycleLen := 60 / Max(1, Rate) * EnsureRange(1 + 0.08 * RandG(0, 1), 0.8, 1.2);
    Inc(Index);
  end;
  tb := t - CycleStart;
  ti := TiFrac * 60 / Max(1, Rate);
  if Pmax <= 0 then Exit(0);
  if tb < 0 then Result := 0
  else if tb < ti then Result := Pmax * Sin(0.5 * Pi * tb / ti)
  else Result := Pmax * Exp(-(tb - ti) / Tau);
end;

function TPatientMuscle.Ti: Double;
begin
  Result := TiFrac * 60 / Max(1, Rate);
end;

function TPatientMuscle.InEffort(t: Double): Boolean;
begin
  Result := (Pmax > 0) and (t >= CycleStart) and (t - CycleStart < TiFrac * 60 / Max(1, Rate));
end;

{ ---------------------------------------------------------------- }

constructor TVentEngine.Create(const ACacheDir: string);
var
  Prm: TLungParams;
begin
  inherited Create;
  if ACacheDir <> '' then LawCacheDir := ACacheDir;
  FLungs := TStringList.Create;
  FLungs.OwnsObjects := True;
  FLungs.Sorted := True;
  Prm := DefaultLungParams;
  FAlv := FitAlveolus(Prm.PTLC * CmH2O, Prm.PSalineTLC * CmH2O, 0.126);
  BuildLaws;
  FMus := TPatientMuscle.Create;
  Dt := 0.004;
  VS := DefaultVentSettings; PendingVS := VS;
  PS_ := DefaultPatientSettings;
  RandSeed := 12345;
end;

destructor TVentEngine.Destroy;
var
  i: Integer;
begin
  FSim.Free;
  FMus.Free;
  FLungs.Free;
  for i := 0 to NWall - 1 do FRefLaws[i].Free;
  inherited;
end;

procedure TVentEngine.BuildLaws;
var
  nt: string;
begin
  BuildWallLaws(NormalAsthma, FRefLaws, nt);
end;

function TVentEngine.GetLung(const P: TPatientSettings): TPatchyLung;
var
  key: string;
  i: Integer;
  Prm: TLungParams;
  PP: TPatchyParams;
  A: TAsthma;
begin
  key := Format('%.2f_%d_%d_%d', [P.Tone, Ord(P.AsthmaWall), Ord(P.Heliox), Ord(P.Supine)]);
  i := FLungs.IndexOf(key);
  if i >= 0 then Exit(TPatchyLung(FLungs.Objects[i]));
  Prm := DefaultLungParams;
  Prm.K1 := 1; Prm.K2 := 4;     { the endotracheal tube }
  if P.Heliox then
  begin
    Prm.Rho := Prm.Rho * HelioxRho; Prm.Visc := Prm.Visc * HelioxVisc;
    Prm.K1 := Prm.K1 * HelioxVisc; Prm.K2 := Prm.K2 * HelioxRho;
  end;
  PP := DefaultPatchyParams;
  PP.ActMode := True; PP.DS := 0.05; PP.SMax := 0.9;
  if P.Supine then
  begin
    Prm.CwRelax := SupineCwRelax; Prm.CwComp := SupineCwComp; PP.Height := SupineHeight;
  end;
  A.Act := EnsureRange(Round(P.Tone / 0.05) * 0.05, 0, 0.9); A.Mucus := 1;
  if P.AsthmaWall then begin A.Thick := 3; PP.Sigma := 0.1; end
  else begin A.Thick := 1; PP.Sigma := 0; end;
  Result := TPatchyLung.Create(Prm, PP, A, FAlv, FRefLaws);
  Result.Hysteresis := 1;
  FLungs.AddObject(key, Result);
end;

function TVentEngine.GetT: Double;
begin
  if FSim = nil then Result := 0 else Result := FSim.T;
end;

procedure TVentEngine.Reset(const P: TPatientSettings; const V: TVentSettings);
var
  VF: array of Double;
  u: Integer;
begin
  PS_ := P; VS := V; PendingVS := V;
  FLung := GetLung(P);
  FreeAndNil(FSim);
  SetLength(VF, FLung.NU);
  FLung.StaticState(0, VF);
  Mon.FRC := FLung.Prm.VDead;
  for u := 0 to FLung.NU - 1 do Mon.FRC := Mon.FRC + VF[u];
  FLung.StaticState(VS.PEEP, VF);
  Mon.FRCPeep := FLung.Prm.VDead;
  for u := 0 to FLung.NU - 1 do Mon.FRCPeep := Mon.FRCPeep + VF[u];
  FFRCPeepAt := VS.PEEP;
  for u := 0 to FLung.NU - 1 do
    FLung.Shut[u] := FLung.UnitPel(VF[u]) <= FLung.Tables[FLung.Level[u]].PClose;
  FMus.Free;
  FMus := TPatientMuscle.Create;
  SetEffort(P);
  FSim := TPatchySim.Create(FLung, FMus.P, VF, Dt);
  FSim.Paw := VS.PEEP * CmH2O;
  FSim.Evaluate;
  FPhase := phExp; FKind := bkNone;
  FExpStart := 0; FPhaseStart := 0; FBreathStart := -1; FLastBreath := 0;
  FDue := 0.5; FHoldInsp := False; FHoldExp := False; FPendingMand := False;
  SetLength(FBreaths, 0); SetLength(FEffortStart, 0); SetLength(FEffortMissed, 0);
  SetLength(Missed, 0); SetLength(FPawSum, 0); SetLength(FWork, 0); SetLength(FWorkT, 0);
  FCurEffort := -1; FWorkAcc := 0; FStepN := 0; FAlarmUntil := -1; FRunStart := 0;
  FPplMin := 1e9; FPplMax := -1e9;
  Mon.Pplat := NaN; Mon.PEEPtot := NaN; Mon.Alarm := '';
  Mon.Ppeak := 0; Mon.VTi := 0; Mon.VTe := 0; Mon.Ti := 0; Mon.RRTot := 0; Mon.RRSpont := 0; Mon.MV := 0;
  Mon.Pmean := VS.PEEP; Mon.EELV := 1000 * (FSim.VTot - Mon.FRC); Mon.DynHyper := 0; Mon.VEI := Mon.EELV;
  Mon.WOB := 0; Mon.Efforts := 0; Mon.Missed := 0; Mon.Kind := bkNone; Mon.NU := FLung.NU;
  Mon.PplMin := FSim.Ppl / CmH2O; Mon.PplMax := Mon.PplMin;
end;

procedure TVentEngine.ChangeLung(const P: TPatientSettings);
var
  NL: TPatchyLung;
  V: array of Double;
  tNow: Double;
  u: Integer;
begin
  NL := GetLung(P);
  PS_ := P;
  SetEffort(P);
  if NL = FLung then Exit;
  SetLength(V, FLung.NU);
  for u := 0 to FLung.NU - 1 do
  begin
    V[u] := FSim.V[u];
    NL.Shut[u] := FLung.Shut[u];
  end;
  tNow := FSim.T;
  FreeAndNil(FSim);
  FLung := NL;
  FSim := TPatchySim.Create(FLung, FMus.P, V, Dt);
  FSim.T := tNow;
  { the relaxed volumes for this lung's chest wall }
  FLung.StaticState(0, V);
  Mon.FRC := FLung.Prm.VDead;
  for u := 0 to FLung.NU - 1 do Mon.FRC := Mon.FRC + V[u];
  FFRCPeepAt := NaN;
  SetControl;
  FLung.UpdateClosure;
  FSim.Evaluate;
end;

procedure TVentEngine.SetEffort(const P: TPatientSettings);
begin
  PS_.Effort := P.Effort; PS_.PatRate := P.PatRate; PS_.PatTiFrac := P.PatTiFrac;
  FMus.Pmax := Max(0, P.Effort);
  FMus.Rate := Max(4, P.PatRate);
  FMus.TiFrac := EnsureRange(P.PatTiFrac, 0.2, 0.6);
end;

procedure TVentEngine.RequestInspHold;
begin
  FHoldInsp := True;
end;

procedure TVentEngine.RequestExpHold;
begin
  FHoldExp := True;
end;

function TVentEngine.Inflow: Double;
begin
  Result := -FSim.Q / LitreMM3;   { L/s into the patient }
end;

procedure TVentEngine.SetAlarm(const S: string);
begin
  Mon.Alarm := S;
  FAlarmUntil := FSim.T + 8;
end;

{ the ventilator's control for the coming step }
procedure TVentEngine.SetControl;
var
  tin, dp: Double;
begin
  case FPhase of
    phExp:
      begin
        FSim.Mode := smPressure; FSim.Paw := VS.PEEP * CmH2O;
      end;
    phInspHold, phExpHold:
      begin
        FSim.Mode := smFlow; FSim.QSet := 0;
      end;
    phInsp:
      begin
        tin := FSim.T + Dt - FBreathStart;
        if FKind = bkVC then
        begin
          FSim.Mode := smFlow; FSim.QSet := -(VS.VT / 1000) / FTi * LitreMM3;
        end
        else
        begin
          if FKind = bkPC then dp := VS.PInsp else dp := VS.PS;
          FSim.Mode := smPressure;
          FSim.Paw := (VS.PEEP + dp * Min(1, tin / Max(Dt, VS.Rise))) * CmH2O;
        end;
      end;
  end;
end;

procedure TVentEngine.StartBreath(AKind: TBreathKind; AMand, ATrig: Boolean);
var
  n: Integer;
  tNow, tm: Double;
begin
  tNow := FSim.T;
  { close the breath before: its expiration ends here }
  n := Length(FBreaths);
  if n > 0 then FBreaths[n - 1].Done := True;
  VS := PendingVS;
  FKind := AKind; FMandatory := AMand; FTriggered := ATrig;
  FPhase := phInsp; FBreathStart := tNow; FPhaseStart := tNow; FPeakFlow := 0;
  FLastBreath := tNow;
  tm := 60 / Max(1, VS.Rate);
  if AKind = bkPS then FTi := 3 else FTi := tm / (1 + Max(0.1, VS.IE));
  SetLength(FBreaths, n + 1);
  with FBreaths[n] do
  begin
    Kind := AKind; Mandatory := AMand; Triggered := ATrig;
    TStart := tNow; TEndInsp := tNow; Ppeak := FSim.Paw / CmH2O; VTi := 0; VTe := 0;
    EELV := 1000 * (FSim.VTot - Mon.FRC); VEI := EELV; Done := False;
  end;
  if ATrig and (FCurEffort >= 0) then FEffortTrig := True;
  { work and Ppl range per breath }
  SetLength(FWork, Length(FWork) + 1); SetLength(FWorkT, Length(FWorkT) + 1);
  FWork[High(FWork)] := FWorkAcc; FWorkT[High(FWorkT)] := tNow; FWorkAcc := 0;
  Mon.PplMin := FPplMin / CmH2O; Mon.PplMax := FPplMax / CmH2O;
  FPplMin := 1e9; FPplMax := -1e9;
  UpdateMonitor;
end;

procedure TVentEngine.EndInspiration;
var
  n: Integer;
begin
  n := High(FBreaths);
  if n >= 0 then
  begin
    FBreaths[n].TEndInsp := FSim.T;
    FBreaths[n].VEI := 1000 * (FSim.VTot - Mon.FRC);
    Mon.Ppeak := FBreaths[n].Ppeak; Mon.VTi := FBreaths[n].VTi; Mon.Ti := FSim.T - FBreathStart;
    Mon.VEI := FBreaths[n].VEI;
    Mon.Kind := FBreaths[n].Kind; Mon.Mandatory := FBreaths[n].Mandatory; Mon.Triggered := FBreaths[n].Triggered;
  end;
  FPhase := phExp; FExpStart := FSim.T; FPhaseStart := FSim.T;
end;

procedure TVentEngine.UpdateMonitor;
var
  i, n, ns, k: Integer;
  tNow, w, vte, wk, x: Double;
begin
  tNow := FSim.T;
  { rate and minute volume over the completed breaths of the last minute:
    from the first one's start to the current breath's start }
  w := Min(60, tNow - FRunStart);
  n := 0; ns := 0; vte := 0; x := -1;
  for i := 0 to High(FBreaths) - 1 do
    if FBreaths[i].TStart >= tNow - 60 then
    begin
      if x < 0 then x := FBreaths[i].TStart;
      Inc(n);
      if not FBreaths[i].Mandatory then Inc(ns);
      vte := vte + FBreaths[i].VTe;
    end;
  if (n > 0) and (Length(FBreaths) > 0) and (FBreaths[High(FBreaths)].TStart - x > 1) then
  begin
    x := FBreaths[High(FBreaths)].TStart - x;
    Mon.RRTot := 60 * n / x; Mon.RRSpont := 60 * ns / x; Mon.MV := vte / 1000 * 60 / x;
  end;
  if w > 5 then
  begin
    wk := 0;
    for i := 0 to High(FWork) do if FWorkT[i] >= tNow - w then wk := wk + FWork[i];
    Mon.WOB := wk * JPerCmH2OL * 60 / w;
  end;
  k := High(FBreaths) - 1;    { the last breath whose expiration is over }
  if k >= 0 then Mon.VTe := FBreaths[k].VTe;
  Mon.EELV := 1000 * (FSim.VTot - Mon.FRC);
  Mon.DynHyper := 1000 * (FSim.VTot - Mon.FRCPeep);
  if Length(FPawSum) > 0 then
  begin
    x := 0;
    k := Max(0, Length(FPawSum) - Round(w / SampleDt));
    for i := k to High(FPawSum) do x := x + FPawSum[i];
    Mon.Pmean := x / (Length(FPawSum) - k);
  end;
  { efforts in the last minute }
  n := 0; ns := 0;
  for i := 0 to High(FEffortStart) do
    if FEffortStart[i] >= tNow - 60 then
    begin
      Inc(n);
      if FEffortMissed[i] then Inc(ns);
    end;
  Mon.Efforts := n; Mon.Missed := ns;
  { trim the history to two minutes }
  k := 0;
  while (k < Length(FBreaths) - 2) and (FBreaths[k].TStart < tNow - 120) do Inc(k);
  if k > 0 then Delete(FBreaths, 0, k);
  k := 0;
  while (k < Length(FEffortStart) - 2) and (FEffortStart[k] < tNow - 120) do Inc(k);
  if k > 0 then
  begin
    Delete(FEffortStart, 0, k); Delete(FEffortMissed, 0, k);
    FCurEffort := FCurEffort - k;
  end;
  k := 0;
  while (k < Length(FWork) - 1) and (FWorkT[k] < tNow - 120) do Inc(k);
  if k > 0 then begin Delete(FWork, 0, k); Delete(FWorkT, 0, k); end;
  k := Length(FPawSum) - Round(120 / SampleDt);
  if k > 0 then Delete(FPawSum, 0, k);
  k := 0;
  while (k < Length(Missed)) and (Missed[k] < tNow - 120) do Inc(k);
  if k > 0 then Delete(Missed, 0, k);
end;

procedure TVentEngine.Step;
var
  tNow, qin, tm, tw, v0, x, palv, vs_: Double;
  trig, wantMand, timeMand: Boolean;
  u, n, idx: Integer;
  kindM: TBreathKind;
  S: TVentSample;
  VF: array of Double;
begin
  { PEEP changes at once; the relaxed volume at the new PEEP for the monitor }
  VS.PEEP := PendingVS.PEEP;
  VS.TrigFlow := PendingVS.TrigFlow; VS.ExpTrig := PendingVS.ExpTrig; VS.PLimit := PendingVS.PLimit;
  if IsNan(FFRCPeepAt) or (Abs(VS.PEEP - FFRCPeepAt) > 1e-9) then
  begin
    SetLength(VF, FLung.NU);
    FLung.StaticState(VS.PEEP, VF);
    Mon.FRCPeep := FLung.Prm.VDead;
    for u := 0 to FLung.NU - 1 do Mon.FRCPeep := Mon.FRCPeep + VF[u];
    FFRCPeepAt := VS.PEEP;
  end;
  SetControl;
  FSim.Evaluate;
  v0 := FSim.VTot;
  FSim.Step;
  tNow := FSim.T;
  qin := Inflow;
  if FMus.Pmax > 0 then
    if FSim.VTot > v0 then FWorkAcc := FWorkAcc + FSim.Pmus * (FSim.VTot - v0);
  FPplMin := Min(FPplMin, FSim.Ppl); FPplMax := Max(FPplMax, FSim.Ppl);
  n := High(FBreaths);
  if n >= 0 then
  begin
    FBreaths[n].Ppeak := Max(FBreaths[n].Ppeak, FSim.Paw / CmH2O);
    if FPhase = phInsp then
    begin
      if qin > 0 then FBreaths[n].VTi := FBreaths[n].VTi + 1000 * qin * Dt;
    end
    else if qin < 0 then FBreaths[n].VTe := FBreaths[n].VTe - 1000 * qin * Dt;
  end;
  { the patient's efforts }
  if FMus.Pmax > 0 then
  begin
    if FMus.InEffort(tNow) and ((FCurEffort < 0) or (FEffortStart[FCurEffort] < FMus.CycleStart - 1e-9)) then
    begin
      if (FCurEffort >= 0) and FEffortInExp and not FEffortTrig and not FEffortMissed[FCurEffort] then
      begin
        FEffortMissed[FCurEffort] := True;
        SetLength(Missed, Length(Missed) + 1);
        Missed[High(Missed)] := FEffortStart[FCurEffort];
      end;
      idx := Length(FEffortStart);
      SetLength(FEffortStart, idx + 1); SetLength(FEffortMissed, idx + 1);
      FEffortStart[idx] := FMus.CycleStart; FEffortMissed[idx] := False;
      FCurEffort := idx; FEffortTrig := False;
      FEffortInExp := FPhase = phExp;
    end
    else if (FCurEffort >= 0) and (tNow - FEffortStart[FCurEffort] >= FMus.Ti + 3 * FMus.Tau)
      and FEffortInExp and not FEffortTrig and not FEffortMissed[FCurEffort] then
    begin
      FEffortMissed[FCurEffort] := True;
      FEffortInExp := False;
      SetLength(Missed, Length(Missed) + 1);
      Missed[High(Missed)] := FEffortStart[FCurEffort];
    end;
  end;
  if (FCurEffort >= 0) and (FPhase = phExp) and (tNow - FExpStart >= 0.2) and FMus.InEffort(tNow) then
    FEffortInExp := True;
  { the ventilator's transitions }
  case FPhase of
    phInsp:
      begin
        FPeakFlow := Max(FPeakFlow, qin);
        x := tNow - FBreathStart;
        if (FKind = bkVC) and (FSim.Paw / CmH2O > VS.PLimit) then
        begin
          SetAlarm('HIGH PRESSURE: breath cut short');
          EndInspiration;
        end
        else if FKind = bkPS then
        begin
          if ((x > VS.Rise) and (qin < 0.01 * VS.ExpTrig * FPeakFlow)) or (x >= FTi) then
          begin
            if x >= FTi then SetAlarm('PS breath reached max Ti 3 s');
            EndInspiration;
          end;
        end
        else if x >= FTi - 1e-9 then
        begin
          if FHoldInsp and FMandatory then
          begin
            FHoldInsp := False;
            FPhase := phInspHold; FPhaseStart := tNow;
            if n >= 0 then FBreaths[n].VEI := 1000 * (FSim.VTot - Mon.FRC);
          end
          else EndInspiration;
        end;
      end;
    phInspHold:
      if tNow - FPhaseStart >= 0.5 - 1e-9 then
      begin
        Mon.Pplat := FSim.Paw / CmH2O;
        EndInspiration;
      end;
    phExpHold:
      if tNow - FPhaseStart >= 2 - 1e-9 then
      begin
        Mon.PEEPtot := FSim.Paw / CmH2O;
        FPhase := phExp;
        if VS.Mode in [vmVCCMV, vmVCSIMV] then kindM := bkVC else kindM := bkPC;
        StartBreath(kindM, True, False);
        FDue := tNow + 60 / Max(1, VS.Rate);
      end;
    phExp:
      begin
        trig := (tNow - FExpStart >= 0.2) and (qin * 60 >= VS.TrigFlow);
        tm := 60 / Max(1, PendingVS.Rate);
        if PendingVS.Mode in [vmVCCMV, vmVCSIMV] then kindM := bkVC else kindM := bkPC;
        wantMand := False; timeMand := False;
        case PendingVS.Mode of
          vmVCCMV, vmPCCMV:
            begin
              if trig then wantMand := True
              else if (tNow >= FDue) and (tNow - FExpStart >= 0.3) then begin wantMand := True; timeMand := True; end;
              if wantMand then
              begin
                if timeMand and FHoldExp then
                begin
                  FHoldExp := False; FPhase := phExpHold; FPhaseStart := tNow;
                end
                else
                begin
                  StartBreath(kindM, True, trig);
                  FDue := tNow + tm;
                end;
              end;
            end;
          vmVCSIMV, vmPCSIMV:
            begin
              tw := Min(5, 0.5 * tm);
              if trig and (tNow >= FDue - tw) then
              begin
                StartBreath(kindM, True, True);
                FDue := Max(FDue + tm, tNow + 0.5 * tm);
              end
              else if trig then StartBreath(bkPS, False, True)
              else if (tNow >= FDue) and (tNow - FExpStart >= 0.3) then
              begin
                if FHoldExp then
                begin
                  FHoldExp := False; FPhase := phExpHold; FPhaseStart := tNow;
                end
                else
                begin
                  StartBreath(kindM, True, False);
                  FDue := Max(FDue + tm, tNow + 0.5 * tm);
                end;
              end;
            end;
          vmCPAPPS:
            begin
              FDue := tNow + tm;
              if trig then StartBreath(bkPS, False, True)
              else if tNow - FLastBreath > 20 then
              begin
                SetAlarm('APNOEA: backup PC breath');
                StartBreath(bkPC, True, False);
              end;
            end;
        end;
      end;
  end;
  if (FAlarmUntil > 0) and (tNow > FAlarmUntil) then begin Mon.Alarm := ''; FAlarmUntil := -1; end;
  { a sample every SampleDt }
  Inc(FStepN);
  if FStepN mod Max(1, Round(SampleDt / Dt)) = 0 then
  begin
    palv := 0; vs_ := 0; n := 0;
    for u := 0 to FLung.NU - 1 do
      if FLung.Shut[u] then Inc(n)
      else begin palv := palv + FLung.Pu[u] * FSim.V[u]; vs_ := vs_ + FSim.V[u]; end;
    Mon.UnitsShut := n;
    if vs_ > 0 then palv := palv / vs_ else palv := FSim.Paw;
    S.T := tNow; S.Paw := FSim.Paw / CmH2O; S.Palv := palv / CmH2O;
    S.Flow := 60 * qin; S.Vol := 1000 * (FSim.VTot - Mon.FRC);
    S.Ppl := FSim.Ppl / CmH2O; S.Pmus := FSim.Pmus;
    SetLength(FPawSum, Length(FPawSum) + 1);
    FPawSum[High(FPawSum)] := S.Paw;
    if Assigned(OnSample) then OnSample(S);
  end;
end;

function TVentEngine.BreathCount: Integer;
begin
  Result := Length(FBreaths);
end;

function TVentEngine.Breath(i: Integer): TBreathRec;
begin
  Result := FBreaths[i];
end;

end.
