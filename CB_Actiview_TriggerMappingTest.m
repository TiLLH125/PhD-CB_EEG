function CB_Actiview_TriggerMappingTest
% CB_Actiview_TriggerMappingTest
% Slow step-through mapping: byte sent on the serial trigger port -> Actiview.
%
% HARDWARE (current lab path)
% -----------------------------
% BioSemi trigger box is connected to the stimulus PC via the DB25/DB37 cable.
% MATLAB sends bytes with IOPort to a serial port (default COM3) that drives
% that interface (same pattern as CB_4xGratings_EEG.m).
%
% Pixel / ViewPixx trigger mode is OFF by default (set cfg.usePixel = true
% only if you need dual-path tests again).
%
% ACTIVIEW
% --------
% Digital trigger readout: type the decimal you see.
% Analog view: each horizontal trace is one bit; see header in older docs or
% BioSemi notes for bit-to-line mapping.
%
% Usage
% -----
%   1) Start Actiview recording; watch trigger channel.
%   2) Edit cfg.serialPort if needed (default COM3).
%   3) Run: CB_Actiview_TriggerMappingTest
%   4) Press Enter to arm each code; after each send, type Actiview value
%      (decimal or 8-char binary). Enter alone -> NaN in CSV.
%   5) CSV: ./data/Actiview_CodeMapping_*.csv
%
% Serial timing
% -------------
% Default: no auto-reset pulse (sendResetAfterCode=false); each code is held
% on the bus for cfg.serialHoldSec so Actiview is easy to read. Between codes
% an explicit 0 is sent. Match CB_4xGratings_EEG by setting
% sendResetAfterCode=true and a short pulseWidthSec if your box needs pulses.

close all;
clc;

cfg = struct();
% --- Serial (primary path to BioSemi trigger box) ---
cfg.useSerial = true;
cfg.serialPort = 'COM3';
cfg.baudRate = 115200;
cfg.pulseWidthSec = 0.005;
cfg.sendResetAfterCode = false;  % true = pulse like main EEG script
cfg.warnOnSendError = true;
cfg.resetAtEnd = true;
cfg.serialHoldSec = 2.00;  % visible hold when sendResetAfterCode is false

% --- Pixel (optional; off for serial-only) ---
cfg.usePixel = false;
cfg.screenNumber = 2;
cfg.skipSyncTests = 1;
cfg.debugWindow = false;
cfg.pixelPos = [0 0];
cfg.pixelSize = 1;
cfg.minRNorm = 19/255;
cfg.holdCodeSec = 2.00;

cfg.waitBeforeReadSec = 0.20;
cfg.resetHoldSec = 1.00;
cfg.manualAdvance = true;
cfg.doStartupSanity = true;   % serial: brief 255 then 0 at start

sendList = [1 2 4 8 16 32 64 128 11 21 31 41 51 127 255];

outDir = fullfile(pwd, 'data');
if ~exist(outDir, 'dir')
    mkdir(outDir);
end
timestamp = datestr(now, 'yyyymmdd_HHMMSS');
outCsv = fullfile(outDir, sprintf('Actiview_CodeMapping_%s.csv', timestamp));

fprintf('\n=== Actiview Trigger Mapping Test (SERIAL path) ===\n');
fprintf('BioSemi trigger box <- DB25/DB37 <- stimulus PC serial trigger (IOPort).\n');
fprintf('Serial: %s @ %d | usePixel=%d\n', cfg.serialPort, cfg.baudRate, cfg.usePixel);
fprintf('sendResetAfterCode=%d  pulseWidthSec=%.3f  serialHoldSec=%.2f\n\n', ...
    cfg.sendResetAfterCode, cfg.pulseWidthSec, cfg.serialHoldSec);
fprintf('Total codes: %d\n\n', numel(sendList));
fprintf('After each send, type Actiview decimal OR 8-bit binary; Enter alone = NaN.\n');
if cfg.manualAdvance
    fprintf('Manual: press Enter in MATLAB before each code.\n\n');
end

KbName('UnifyKeyNames');

trigger = struct('enabled', false, 'handle', []);
if cfg.useSerial
    trigger = initSerialTrigger(cfg);
    if ~trigger.enabled
        error('Serial trigger not available. Check COM port, cable, and that no other app has the port open.');
    end
end

window = [];
windowRect = [];
pixelState = struct('datapixxOpen', false, 'pixelModeEnabled', false);
if cfg.usePixel
    PsychDefaultSetup(2);
    Screen('Preference', 'SkipSyncTests', cfg.skipSyncTests);
    Screen('Preference', 'VisualDebugLevel', 1);
    pixelState = initPixelPath(cfg);
end

cleanupObj = onCleanup(@() cleanupAll(window, trigger, pixelState, cfg)); %#ok<NASGU>

if cfg.usePixel
    if cfg.debugWindow
        [window, windowRect] = PsychImaging('OpenWindow', cfg.screenNumber, 0.5, [100 100 900 700]);
    else
        [window, windowRect] = PsychImaging('OpenWindow', cfg.screenNumber, 0.5);
    end
    Screen('BlendFunction', window, 'GL_SRC_ALPHA', 'GL_ONE_MINUS_SRC_ALPHA');
    Screen('TextSize', window, 26);
    Screen('TextFont', window, 'Arial');
end

if cfg.doStartupSanity && cfg.useSerial
    fprintf('Startup: serial bytes 255 (1 s) then 0.\n');
    sendTriggerHold(trigger, cfg, 255, 1.0);
    sendTriggerHold(trigger, cfg, 0, 0.3);
end

n = numel(sendList);
sentCode = nan(n, 1);
sentBinaryStr = strings(n, 1);
activiewObserved = nan(n, 1);
activiewParsedFromBinary = nan(n, 1);
trialIdx = (1:n)';

for i = 1:n
    if cfg.manualAdvance
        input(sprintf('Press Enter to send code %d of %d...', i, n), 's');
    end

    code = sendList(i);
    sentCode(i) = code;
    sentBinaryStr(i) = padLeadingBinary(code, 8);

    label = sprintf('Mapping %d of %d', i, n);
    emitMark(window, windowRect, trigger, pixelState, cfg, code, label);

    WaitSecs(cfg.waitBeforeReadSec);

    prompt = sprintf('[%02d/%02d] Sent %3d (bin %s). Actiview (decimal OR 8-bit binary): ', ...
        i, n, code, sentBinaryStr(i));
    s = strtrim(input(prompt, 's'));
    if ~isempty(s)
        vBin = parseBinaryInput(s);
        if ~isnan(vBin)
            activiewParsedFromBinary(i) = vBin;
            activiewObserved(i) = vBin;
        else
            vDec = str2double(s);
            if ~isnan(vDec)
                activiewObserved(i) = vDec;
            end
        end
    end

    emitMark(window, windowRect, trigger, pixelState, cfg, 0, 'Reset 0');
    WaitSecs(cfg.resetHoldSec);
end

delta = activiewObserved - sentCode;
T = table(trialIdx, sentCode, sentBinaryStr, activiewObserved, activiewParsedFromBinary, delta, ...
    'VariableNames', {'idx', 'sentCode', 'sentBinaryMSB', 'activiewObserved', 'fromBinaryInput', 'delta'});
writetable(T, outCsv);

fprintf('\nSaved mapping CSV:\n%s\n', outCsv);

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

function emitMark(window, ~, trigger, pixelState, cfg, code, label)
if cfg.useSerial
    if code == 0 && ~cfg.sendResetAfterCode
        sendTriggerHold(trigger, cfg, 0, 0.05);
    else
        sendTriggerHold(trigger, cfg, code, cfg.serialHoldSec);
    end
end
if cfg.usePixel && ~isempty(window)
    Screen('FillRect', window, 0.5);
    bin8 = padLeadingBinary(code, 8);
    if ~isempty(label)
        text = sprintf('%s\nByte=%d  bin=%s\nSER=%d PIX=%d', ...
            label, code, bin8, cfg.useSerial, cfg.usePixel && pixelState.pixelModeEnabled);
        DrawFormattedText(window, text, 'center', 'center', 0, 90);
    end
    Screen('BlendFunction', window, 'GL_ONE', 'GL_ZERO');
    drawViewPixxPixelIfNeeded(window, cfg, pixelState, code);
    Screen('BlendFunction', window, 'GL_SRC_ALPHA', 'GL_ONE_MINUS_SRC_ALPHA');
    Screen('Flip', window);
    WaitSecs(cfg.holdCodeSec);
end
end

function sendTriggerHold(trigger, cfg, code, holdSec)
if ~trigger.enabled || isempty(trigger.handle)
    return;
end
if isnan(code) || code < 0 || code > 255
    return;
end
try
    IOPort('Write', trigger.handle, uint8(code), 0);
    if cfg.sendResetAfterCode
        WaitSecs(trigger.pulseWidthSec);
        IOPort('Write', trigger.handle, uint8(0), 0);
    elseif nargin >= 4 && ~isempty(holdSec) && holdSec > 0
        WaitSecs(holdSec);
    end
catch ME
    if cfg.warnOnSendError
        warning('Trigger send failed (%d): %s', code, mExceptionText(ME));
    end
end
end

function s = padLeadingBinary(code, nBits)
if isnan(code) || code < 0 || code > 255
    s = repmat('?', 1, nBits);
    return;
end
s = dec2bin(code, nBits);
end

function v = parseBinaryInput(s)
v = NaN;
t = strrep(strrep(strtrim(s), ' ', ''), '_', '');
if numel(t) ~= 8 || ~all(t == '0' | t == '1')
    return;
end
v = bin2dec(t);
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
    fprintf('Serial trigger port OPEN: %s\n', cfg.serialPort);
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

function cleanupAll(window, trigger, pixelState, cfg)
if cfg.useSerial && cfg.resetAtEnd
    try sendTriggerHold(trigger, cfg, 0, 0.05); catch, end
end

if cfg.usePixel && ~isempty(window)
    try
        Screen('FillRect', window, 0.5);
        Screen('BlendFunction', window, 'GL_ONE', 'GL_ZERO');
        drawViewPixxPixelIfNeeded(window, cfg, pixelState, 0);
        Screen('BlendFunction', window, 'GL_SRC_ALPHA', 'GL_ONE_MINUS_SRC_ALPHA');
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
        try Screen('CloseAll'); catch, end
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
