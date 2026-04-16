function CB_Photodiode_Ergo1_Test
% CB_Photodiode_Ergo1_Test
% Standalone photodiode timing test for BioSemi Ergo1 input.
%
% What it does:
% - Opens a PTB window.
% - Draws a small diode patch (default top-left).
% - Alternates OFF (black) and ON (white) in a regular pulse train.
% - Sends serial triggers for run start/stop and diode ON/OFF transitions.
%
% Use this to confirm:
% 1) Ergo1 sees clean photodiode pulses in Actiview.
% 2) Pulse timing is aligned with screen flips.
%
% Controls:
% - SPACE: start/stop pulsing
% - ESC: quit
%
% Notes:
% - This script does not read BioSemi data in MATLAB; pulses appear in Actiview/BDF.
% - Keep diode physically taped over the patch region.
% - After recording, measure trigger-to-photodiode latency on the continuous BDF with
%   CB_Photodiode_Ergo1_LatencyFromEEG (see that file for usage; set pdChan to your Ergo1 channel).

close all;
try ListenChar(0); catch, end
try KbQueueRelease(-1); catch, end
if exist('sca', 'file') == 2
    sca;
elseif exist('Screen', 'file') == 2
    Screen('CloseAll');
end

cfg = struct();
cfg.screenNumber = 2;
cfg.skipSyncTests = 1;
cfg.visualDebugLevel = 1;
cfg.debugWindow = false;
cfg.bg = 0.5;

% Photodiode patch settings (PsychDefaultSetup(2): 0..1 colors)
cfg.pd.enable = true;
cfg.pd.sizePx = 100;
cfg.pd.corner = 'top-left'; % 'top-left' | 'top-right' | 'bottom-left' | 'bottom-right'
cfg.pd.onColor = 1.0;       % white
cfg.pd.offColor = 0.0;      % black

% Pulse timing (longer inter-pulse spacing to reduce overlap between trials)
cfg.pulse.onSec = 0.10;     % diode ON duration
cfg.pulse.offSec = 1.40;    % diode OFF duration

% Serial markers (enabled by default)
cfg.eeg.enable = true;
cfg.eeg.serialPort = 'COM4';
cfg.eeg.baudRate = 115200;
cfg.eeg.pulseWidthSec = 0.005;
cfg.eeg.sendResetAfterCode = true;
cfg.eeg.warnOnSendError = true;
cfg.eeg.codeRunStart = 200;
cfg.eeg.codeOn = 201;
cfg.eeg.codeOff = 202;
cfg.eeg.codeRunStop = 203;

KbName('UnifyKeyNames');
keys.escape = KbName('ESCAPE');
keys.space = KbName('space');

try
    PsychDefaultSetup(2);
catch
    error('Psychtoolbox not found.');
end

Screen('Preference', 'VisualDebugLevel', cfg.visualDebugLevel);
Screen('Preference', 'SkipSyncTests', cfg.skipSyncTests);

trigger = initSerialTrigger(cfg.eeg);
window = [];
try
    if cfg.debugWindow
        [window, windowRect] = PsychImaging('OpenWindow', cfg.screenNumber, cfg.bg, [100 100 1000 800]);
    else
        [window, windowRect] = PsychImaging('OpenWindow', cfg.screenNumber, cfg.bg);
    end
    cleanupObj = onCleanup(@() localCleanup(window, trigger)); %#ok<NASGU>

    Screen('TextFont', window, 'Arial');
    Screen('TextSize', window, 28);
    Screen('BlendFunction', window, 'GL_SRC_ALPHA', 'GL_ONE_MINUS_SRC_ALPHA');

    ifi = Screen('GetFlipInterval', window);
    pdRect = makePdRect(windowRect, cfg.pd.sizePx, cfg.pd.corner);

    try KbQueueRelease(-1); catch, end
    KbQueueCreate(-1);
    KbQueueStart(-1);
    KbQueueFlush(-1);

    running = true;
    pulsing = false;
    stateOn = false;
    nextSwitch = GetSecs + 0.25;
    nOn = 0;

    while running
        nowT = GetSecs;

        [pressed, firstPress] = KbQueueCheck(-1);
        if pressed
            if firstPress(keys.escape) > 0
                running = false;
            elseif firstPress(keys.space) > 0
                pulsing = ~pulsing;
                stateOn = false;
                nextSwitch = nowT + 0.05;
                if pulsing
                    sendTrigger(trigger, cfg.eeg.codeRunStart);
                else
                    sendTrigger(trigger, cfg.eeg.codeRunStop);
                end
            end
            KbQueueFlush(-1);
        end

        if pulsing && nowT >= nextSwitch
            stateOn = ~stateOn;
            if stateOn
                nOn = nOn + 1;
                sendTrigger(trigger, cfg.eeg.codeOn);
                nextSwitch = nowT + cfg.pulse.onSec;
            else
                sendTrigger(trigger, cfg.eeg.codeOff);
                nextSwitch = nowT + cfg.pulse.offSec;
            end
        elseif ~pulsing
            stateOn = false;
        end

        Screen('FillRect', window, cfg.bg);
        drawStatus(window, windowRect, pulsing, stateOn, nOn, trigger.enabled, cfg);
        if cfg.pd.enable
            if stateOn
                Screen('FillRect', window, cfg.pd.onColor, pdRect);
            else
                Screen('FillRect', window, cfg.pd.offColor, pdRect);
            end
        end
        Screen('Flip', window);

        WaitSecs(max(0, ifi * 0.25));
    end

catch ME
    try localCleanup(window, trigger); catch, end
    rethrow(ME);
end
end

function drawStatus(window, windowRect, pulsing, stateOn, nOn, serialEnabled, cfg)
if pulsing
    runTxt = 'RUNNING';
else
    runTxt = 'STOPPED';
end
if stateOn
    pdTxt = 'ON';
else
    pdTxt = 'OFF';
end

txt = sprintf([ ...
    'Photodiode Ergo1 Test\\n\\n' ...
    'SPACE: start/stop pulses\\n' ...
    'ESC: quit\\n\\n' ...
    'Pulse state: %s\\n' ...
    'Patch state: %s\\n' ...
    'ON pulses sent: %d\\n\\n' ...
    'ON duration: %.3f s   OFF duration: %.3f s\\n' ...
    'Serial trigger enabled: %d\\n' ...
    'Codes: runStart=%d  on=%d  off=%d  runStop=%d\\n'], ...
    runTxt, pdTxt, nOn, cfg.pulse.onSec, cfg.pulse.offSec, serialEnabled, ...
    cfg.eeg.codeRunStart, cfg.eeg.codeOn, cfg.eeg.codeOff, cfg.eeg.codeRunStop);

DrawFormattedText(window, txt, 'center', windowRect(4) * 0.18, 0, 90);
end

function pdRect = makePdRect(windowRect, sizePx, cornerName)
switch lower(cornerName)
    case 'top-left'
        pdRect = [0 0 sizePx sizePx];
    case 'top-right'
        pdRect = [windowRect(3)-sizePx 0 windowRect(3) sizePx];
    case 'bottom-left'
        pdRect = [0 windowRect(4)-sizePx sizePx windowRect(4)];
    case 'bottom-right'
        pdRect = [windowRect(3)-sizePx windowRect(4)-sizePx windowRect(3) windowRect(4)];
    otherwise
        error('Unknown cfg.pd.corner: %s', cornerName);
end
end

function trigger = initSerialTrigger(eegCfg)
trigger = struct('enabled', false, 'handle', [], ...
    'pulseWidthSec', 0, 'sendResetAfterCode', false, 'warnOnSendError', true);
if ~isfield(eegCfg, 'enable') || ~eegCfg.enable
    return;
end

trigger.pulseWidthSec = eegCfg.pulseWidthSec;
trigger.sendResetAfterCode = eegCfg.sendResetAfterCode;
trigger.warnOnSendError = eegCfg.warnOnSendError;
try
    cfgString = sprintf('BaudRate=%d DTR=1 RTS=1', eegCfg.baudRate);
    trigger.handle = IOPort('OpenSerialPort', eegCfg.serialPort, cfgString);
    trigger.enabled = true;
    fprintf('Serial trigger enabled on %s @ %d baud.\\n', eegCfg.serialPort, eegCfg.baudRate);
catch ME
    warning('Serial trigger disabled: %s', mExceptionText(ME));
end
end

function sendTrigger(trigger, code)
if ~trigger.enabled || isempty(trigger.handle)
    return;
end
if isnan(code) || code < 0 || code > 255
    return;
end
try
    IOPort('Write', trigger.handle, uint8(code), 0);
    if trigger.sendResetAfterCode
        WaitSecs(trigger.pulseWidthSec);
        IOPort('Write', trigger.handle, uint8(0), 0);
    end
catch ME
    if trigger.warnOnSendError
        warning('Trigger send failed (%d): %s', code, mExceptionText(ME));
    end
end
end

function localCleanup(window, trigger)
try ListenChar(0); catch, end
try KbQueueRelease(-1); catch, end
try
    if trigger.enabled && ~isempty(trigger.handle)
        IOPort('Close', trigger.handle);
    end
catch
end
try
    if ~isempty(window)
        sca;
    else
        Screen('CloseAll');
    end
catch
end
end

function txt = mExceptionText(ME)
txt = 'unknown error';
if isa(ME, 'MException') && ~isempty(ME.message)
    txt = ME.message;
end
end
