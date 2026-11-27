program asthmavent;

{ AsthmaVent: mechanical ventilation of the asthmatic patient, live, on
  the stage 5-9 patchy lung (../Asthma). See uVentSim for the ventilator
  and patient, uAsthmaVentForm for the window.
  Build:  lazbuild --lazarusdir=<path> --ws=gtk2 asthmavent.lpi }

{$mode delphi}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, SysUtils, Math, cblas, uAsthmaVentForm;

begin
  InitializeCBLAS;
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  DefaultFormatSettings.DecimalSeparator := '.';
  Application.Initialize;
  Application.CreateForm(TVentForm, VentForm);
  Application.Run;
end.
