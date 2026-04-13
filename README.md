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

ERROR 4:

=== VPixx Preflight Start ===


PTB-INFO: This is Psychtoolbox-3 for Microsoft Windows, under Matlab 64-Bit Intel (Version 3.0.22 - Build date: May 24 2025).
PTB-INFO: OS support status: Windows 11 (Version 11.0) is not supported.
PTB-INFO: For information about paid support and other commercial services, please type 'PsychPaidSupportAndServices'.
PTB-INFO: Most parts of the Psychtoolbox distribution are licensed to you under terms of the MIT license, with some
PTB-INFO: restrictions. See file 'License.txt' in the Psychtoolbox root folder for the exact licensing conditions.
PTB-INFO: Psychtoolbox and its prebuilt mex files are distributed in the hope that they will be useful, but WITHOUT
PTB-INFO: ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

PTB-INFO: The detected endline of the vertical blank interval is equal or lower than the startline. This indicates
PTB-INFO: that i couldn't detect the duration of the vertical blank interval and won't be able to correct timestamps
PTB-INFO: for it. This will introduce a very small and constant offset (typically << 1 msec). Read 'help BeampositionQueries'
PTB-INFO: for how to correct this, should you really require that last few microseconds of precision.
PTB-INFO: Btw. this can also mean that your systems beamposition queries are slightly broken. It may help timing precision to
PTB-INFO: enable the beamposition workaround, as explained in 'help ConserveVRAMSettings', section 'kPsychUseBeampositionQueryWorkaround'.


PTB-INFO: OpenGL-Renderer is ATI Technologies Inc. :: AMD Radeon RX 6500M :: 4.6.0 Compatibility Profile Context 24.6.1.240619
PTB-INFO: Screen 2 : Window 10 : VBL startline = 1080 : VBL Endline = 1079
PTB-INFO: Measured monitor refresh interval from beamposition = 8.333649 ms [119.995455 Hz].
PTB-INFO: Will use beamposition query for accurate Flip time stamping.
PTB-INFO: Measured monitor refresh interval from VBLsync = 8.332562 ms [120.011108 Hz]. (50 valid samples taken, stddev=0.030865 ms.)
PTB-INFO: Reported monitor refresh interval from operating system = 8.333333 ms [120.000000 Hz].
PTB-INFO: ==============================================================================================================================
PTB-INFO: WINDOWS DWM DESKTOP COMPOSITOR IS ACTIVE. On this Windows-10 or later system, Psychtoolbox can no longer reliably detect if
PTB-INFO: this will cause trouble for timing and integrity of visual stimuli or not. You might be just fine, or you could be in trouble.
PTB-INFO: Use external measurement equipment and independent procedures to verify reliability of timing if you care about proper timing.
PTB-INFO: ==============================================================================================================================


PTB-ERROR: Screen('Flip'); beamposition timestamping computed an *impossible stimulus onset value* of 1837156.031525 secs, which would indicate that
PTB-ERROR: stimulus onset happened *before* it was actually requested! (Earliest theoretically possible 1837156.032805 secs).

PTB-ERROR: Some more diagnostic values (only for experts): rawTimestamp = 1837156.034097, scanline = 333
PTB-ERROR: Some more diagnostic values (only for experts): line_pre_swaprequest = 141, line_post_swaprequest = 301, time_post_swaprequest = 1837156.033879
PTB-ERROR: Some more diagnostic values (only for experts): preflip_vblcount = 0, preflip_vbltimestamp = 1837156.031721
PTB-ERROR: Some more diagnostic values (only for experts): postflip_vblcount = 0, postflip_vbltimestamp = -1.000000, vbltimestampquery_retrycount = 0

PTB-ERROR: This error can be due to either of the following causes:
PTB-ERROR: Very unlikely: Something is broken in your systems beamposition timestamping. I've disabled high precision
PTB-ERROR: timestamping for now. Returned timestamps will be less robust and accurate.

PTB-ERROR: The most likely cause would be that Synchronization of stimulus onset (buffer swap) to the
PTB-ERROR: vertical blank interval VBL is not working properly, or swap completion signalling to PTB is broken.
PTB-ERROR: Please run the script PerceptualVBLSyncTest to check this. With non-working sync to VBL, all stimulus timing
PTB-ERROR: is futile. Also run OSXCompositorIdiocyTest on macOS. Also read 'help SyncTrouble' !
OK: PTB OpenWindow succeeded on screen 2.
Datapixx MEX path: C:\psychtoolbox\3.0.22.1\Psychtoolbox\PsychBasic\Datapixx.mexw64
OK: Datapixx('Open') returned.
Datapixx('IsReady') = 0

=== VPixx Preflight FAILED ===
Error using ViewPixx_PixelModeTest (line 51)
Datapixx opened but IsReady==0. Control link is not working.\nCheck USB/control cable, power, drivers, and ensure no other app has the device open.

Checklist:
 - Video cable connected to ViewPixx and correct display selected
 - USB/control cable from stimulus PC to VPixx hardware
 - Device powered on
 - VPixx drivers/software installed
 - No other app (e.g., LabMaestro) holding device open
 - Restart MATLAB after driver changes



WARNING: This session of your experiment was run by you with the setting Screen('Preference', 'SkipSyncTests', 1).
WARNING: This means that some internal self-tests and calibrations were skipped. Your stimulus presentation timing
WARNING: may have been wrong. This is fine for development and debugging of your experiment, but for running the real
WARNING: study, please make sure to set Screen('Preference', 'SkipSyncTests', 0) for maximum accuracy and reliability.
Error using ViewPixx_PixelModeTest (line 51)
Datapixx opened but IsReady==0. Control link is not working.\nCheck USB/control cable, power, drivers, and ensure no other app has the device open.

ERRORS 7:
>> CB_4xGratings_EEG
Enter Participant ID (e.g., S001): TEST
IOPort-Info: Configuration for device COM3:
IOPort-Info: Current baud rate is 1200
IOPort-Info: Baud rate changed to 115200
EEG serial trigger enabled on COM3 @ 115200 baud.
Reached: OpenWindow OK
ViewPixx Pixel Mode ENABLED (R = marker/255 on top-left pixel).
Display geometry (viewpixx): pxPerCm=36.158 | pxPerDeg=37.866 | square=6.90deg->261px | spacing=3.40deg->129px | fix=0.37deg->14px | fixLW=0.08deg->3px

TRIGGER CODES:

Observed mapping summary (sent -> observed set):
   21 -> 3
   31 -> 3
   32 -> 0
   41 -> 0
   64 -> 4
  127 -> 7
  128 -> 0
  255 -> 7
