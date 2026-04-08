# PhD-CB_EEG

Error1
Error in function EnablePixelMode: 	Usage error
Datapixx is not open! Call: Datapixx('Open').
Error using Datapixx
Usage:

Datapixx('EnablePixelMode', [mode = 0]);

Error in ViewPixx_PixelModeTest>datapixxEnablePixelMode (line 153)
        Datapixx('EnablePixelMode', 0);
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Error in ViewPixx_PixelModeTest (line 70)
    datapixxEnablePixelMode(pixelMode);
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

ERROR 2:
Error in function EnablePixelMode: 	Usage error
Datapixx is not open! Call: Datapixx('Open').
Error using Datapixx
Usage:

Datapixx('EnablePixelMode', [mode = 0]);

Error in ViewPixx_PixelModeTest>datapixxEnablePixelMode (line 155)
        Datapixx('EnablePixelMode', 0);
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Error in ViewPixx_PixelModeTest (line 68)
    datapixxEnablePixelMode(pixelMode);
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
ERROR 3
>> ViewPixx_PixelModeTest
Warning: PsychDataPixx: Device connection not ready after init! TROUBLE AHEAD!! 
> In PsychDataPixx (line 897)
In PsychImaging>FinalizeConfiguration (line 3089)
In PsychImaging (line 1981)
In ViewPixx_PixelModeTest (line 60) 

ViewPixx_PixelMode_Test ERROR:
Error using Datapixx
Usage:

Datapixx('SetVideoMode' [, mode=0]);

Error in PsychDataPixx>doDatapixx (line 1151)
            Datapixx(varargin{:});
            ^^^^^^^^^^^^^^^^^^^^^
Error in PsychDataPixx (line 916)
    doDatapixx('SetVideoMode', varargin{1});
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Error in PsychImaging>FinalizeConfiguration (line 3093)
        PsychDataPixx('SetVideoMode', 0);
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Error in PsychImaging (line 1981)
    [imagingMode, needStereoMode, reqs] = FinalizeConfiguration(reqs, stereomode, screenid);
                                          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Error in ViewPixx_PixelModeTest (line 60)
    [window, ~] = PsychImaging('OpenWindow', screenid, bgColor);
                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Error in function SetVideoMode: 	Usage error
Datapixx is not open! Call: Datapixx('Open').
Error using Datapixx
Usage:

Datapixx('SetVideoMode' [, mode=0]);

Error in PsychDataPixx>doDatapixx (line 1151)
            Datapixx(varargin{:});
            ^^^^^^^^^^^^^^^^^^^^^
Error in PsychDataPixx (line 916)
    doDatapixx('SetVideoMode', varargin{1});
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Error in PsychImaging>FinalizeConfiguration (line 3093)
        PsychDataPixx('SetVideoMode', 0);
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Error in PsychImaging (line 1981)
    [imagingMode, needStereoMode, reqs] = FinalizeConfiguration(reqs, stereomode, screenid);
                                          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Error in ViewPixx_PixelModeTest (line 60)
    [window, ~] = PsychImaging('OpenWindow', screenid, bgColor);
                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
