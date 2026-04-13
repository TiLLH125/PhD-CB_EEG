function CB_Actiview_TriggerMappingTest
% CB_Actiview_TriggerMappingTest
% Send a known sequence of dual-path trigger bytes to map:
%   "code sent by MATLAB" -> "code shown in Actiview".
%
% Usage:
%   1) Start Actiview and watch trigger display.
%   2) Run this function.
%   3) Type the Actiview code you observed for each prompt.
%   4) A CSV mapping file is saved in ./data.
%
% Notes:
% - This script can send SERIAL and ViewPixx PIXEL markers together.
% - Defaults are set for Actiview visibility (hold codes longer, no immediate reset).
% - This is for mapping/debugging, not exact experiment timing.

close all;
clc;

cfg = struct();
cfg.useSerial = true;
cfg.serialPort = 'COM3';
cfg.baudRate = 115200;
cfg.pulseWidthSec = 0.050;
cfg.sendResetAfterCode = false;
cfg.warnOnSendError = true;
cfg.resetAtEnd = true;

cfg.usePixel = true;
cfg.screenNumber = 2;
cfg.skipSyncTests = 1;
cfg.debugWindow = false;
cfg.pixelPos = [0 0];
cfg.pixelSize = 1;
cfg.minRNorm = 19/255;

cfg.holdCodeSec = 0.60;       % visible code duration
cfg.waitBeforeReadSec = 0.60; % time to read Actiview display
cfg.waitBetweenCodesSec = 0.20;
cfg.repeatsPerCode = 2;

% Bit-walk + common diagnostics + experiment codes
bitwalkCodes = [1 2 4 8 16 32 64 128];
mainCodes = [11 12 21 22 23 31 32 41 42 43 44 51 52 53 54];
diagCodes = [3 5 10 15 63 127 255];

allCodes = unique([bitwalkCodes mainCodes diagCodes], 'stable');
sendList = repelem(allCodes, cfg.repeatsPerCode);

outDir = fullfile(pwd, 'data');
if ~exist(outDir, 'dir')
    mkdir(outDir);
end
timestamp = datestr(now, 'yyyymmdd_HHMMSS');
outCsv = fullfile(outDir, sprintf('Actiview_CodeMapping_%s.csv', timestamp));

fprintf('\n=== Actiview Trigger Mapping Test ===\n');
fprintf('Serial enabled: %d\n', cfg.useSerial);
fprintf('Pixel enabled:  %d\n', cfg.usePixel);
if cfg.useSerial
    fprintf('Port: %s @ %d baud\n', cfg.serialPort, cfg.baudRate);
    fprintf('sendResetAfterCode: %d\n', cfg.sendResetAfterCode);
end
fprintf('Total sends: %d (%d codes x %d repeats)\n\n', numel(sendList), numel(allCodes), cfg.repeatsPerCode);
fprintf('For each send, type what Actiview shows.\n');
fprintf('If missed/unclear, press Enter for NaN.\n\n');

KbName('UnifyKeyNames');
PsychDefaultSetup(2);
Screen('Preference', 'SkipSyncTests', cfg.skipSyncTests);
Screen('Preference', 'VisualDebugLevel', 1);

trigger = struct('enabled', false, 'handle', []);
if cfg.useSerial
    trigger = initSerialTrigger(cfg);
    if ~trigger.enabled
        warning('Serial trigger not available; continuing pixel-only.');
    end
end

window = [];
windowRect = [];
pixelState = initPixelPath(cfg);
cleanupObj = onCleanup(@() cleanupAll(window, trigger, pixelState, cfg)); %#ok<NASGU>

if cfg.usePixel
    if cfg.debugWindow
        [window, windowRect] = PsychImaging('OpenWindow', cfg.screenNumber, 0.5, [100 100 900 700]);
    else
        [window, windowRect] = PsychImaging('OpenWindow', cfg.screenNumber, 0.5);
    end
    Screen('TextSize', window, 26);
    Screen('TextFont', window, 'Arial');
end

fprintf('Sending startup sanity code 255 for 1 second...\n');
emitDualCode(window, windowRect, trigger, pixelState, cfg, 255, 'Startup sanity code 255');
WaitSecs(1.0);
emitDualCode(window, windowRect, trigger, pixelState, cfg, 0, 'Reset to 0');
WaitSecs(0.5);

n = numel(sendList);
sentCode = nan(n,1);
activiewObserved = nan(n,1);
trialIdx = (1:n)';

for i = 1:n
    code = sendList(i);
    sentCode(i) = code;

    label = sprintf('Mapping code %d (%d/%d)', code, i, n);
    emitDualCode(window, windowRect, trigger, pixelState, cfg, code, label);
    WaitSecs(cfg.waitBeforeReadSec);

    prompt = sprintf('[%02d/%02d] Sent %3d. Actiview shows: ', i, n, code);
    s = input(prompt, 's');
    v = str2double(strtrim(s));
    if ~isempty(strtrim(s)) && ~isnan(v)
        activiewObserved(i) = v;
    end

    WaitSecs(cfg.waitBetweenCodesSec);
end

delta = activiewObserved - sentCode;
T = table(trialIdx, sentCode, activiewObserved, delta, ...
    'VariableNames', {'idx', 'sentCode', 'activiewObserved', 'delta'});
writetable(T, outCsv);

fprintf('\nSaved mapping CSV:\n%s\n', outCsv);

% Quick summary in console
valid = ~isnan(activiewObserved);
if any(valid)
    U = unique(T.sentCode(valid));
    fprintf('\nObserved mapping summary (sent -> observed set):\n');
    for k = 1:numel(U)
        c = U(k);
        obs = unique(T.activiewObserved(T.sentCode == c & valid));
        obsStr = sprintf('%g ', obs);
        fprintf('  %3d -> %s\n', c, strtrim(obsStr));
    end
else
    fprintf('No observed values entered (all NaN).\n');
end

fprintf('\nDone.\n');
end

function emitDualCode(window, windowRect, trigger, pixelState, cfg, code, label)
if cfg.useSerial
    sendTrigger(trigger, code);
end
if cfg.usePixel && ~isempty(window)
    Screen('FillRect', window, 0.5);
    if ~isempty(label)
        text = sprintf('%s\nCode=%d\nSER=%d  PIX=%d', label, code, cfg.useSerial, cfg.usePixel && pixelState.pixelModeEnabled);
        DrawFormattedText(window, text, 'center', 'center', 0, 90);
    end
    drawViewPixxPixelIfNeeded(window, cfg, pixelState, code);
    Screen('Flip', window);
    WaitSecs(cfg.holdCodeSec);
end
end

function trigger = initSerialTrigger(cfg)
trigger = struct('enabled', false, 'handle', [], ...
    'pulseWidthSec', cfg.pulseWidthSec, ...
    'sendResetAfterCode', cfg.sendResetAfterCode, ...
    'warnOnSendError', cfg.warnOnSendError);

try
    cfgString = sprintf('BaudRate=%d DTR=1 RTS=1', cfg.baudRate);
    trigger.handle = IOPort('OpenSerialPort', cfg.serialPort, cfgString);
    trigger.enabled = true;
catch ME
    warning('Serial init failed: %s', mExceptionText(ME));
end
end

function pixelState = initPixelPath(cfg)
pixelState = struct('datapixxOpen', false, 'pixelModeEnabled', false);
if ~cfg.usePixel
    return;
end
try
    Datapixx('Open');
    if ~logical(Datapixx('IsReady'))
        warning('Datapixx IsReady==0. Continuing without Pixel Mode.');
        try Datapixx('Close'); catch, end
        return;
    end
    pixelState.datapixxOpen = true;
    try
        Datapixx('EnablePixelMode');
    catch
        Datapixx('EnablePixelMode', 0);
    end
    Datapixx('RegWrRd');
    pixelState.pixelModeEnabled = true;
    fprintf('ViewPixx Pixel Mode ENABLED.\n');
catch ME
    warning('Pixel mode init failed: %s', mExceptionText(ME));
    try Datapixx('Close'); catch, end
end
end

function drawViewPixxPixelIfNeeded(window, cfg, pixelState, code)
if ~pixelState.pixelModeEnabled
    return;
end
if isnan(code) || code < 0 || code > 255
    return;
end
rVal = double(code) / 255;
rVal = max(rVal, cfg.minRNorm);
rgb = [rVal, 0, 0];
Screen('DrawDots', window, cfg.pixelPos, cfg.pixelSize, rgb, [], 1);
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

function cleanupAll(window, trigger, pixelState, cfg)
if cfg.useSerial && cfg.resetAtEnd
    try sendTrigger(trigger, 0); catch, end
end

if cfg.usePixel && ~isempty(window)
    try
        Screen('FillRect', window, 0.5);
        drawViewPixxPixelIfNeeded(window, cfg, pixelState, 0);
        Screen('Flip', window);
    catch
    end
end

if pixelState.datapixxOpen
    try
        if pixelState.pixelModeEnabled
            Datapixx('DisablePixelMode');
            Datapixx('RegWrRd');
        end
    catch
    end
    try Datapixx('Close'); catch, end
end

closeSerialTrigger(trigger);
try
    if ~isempty(window)
        sca;
    else
        Screen('CloseAll');
    end
catch
end
end

function closeSerialTrigger(trigger)
try
    if trigger.enabled && ~isempty(trigger.handle)
        IOPort('Close', trigger.handle);
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
