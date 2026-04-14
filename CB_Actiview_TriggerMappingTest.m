function CB_Actiview_TriggerMappingTest
% CB_Actiview_TriggerMappingTest
% Slow step-through mapping: sent byte -> what you see in Actiview.
%
% HARDWARE (your lab topology)
% ---------------------------
% If the BioSemi trigger input is fed ONLY from the ViewPixx DB25/DB37 path
% (Pixel Mode / digital out), then Actiview will NOT see USB serial (COM3).
% In that case set cfg.useSerial = false (default below). Serial is optional
% for other equipment (e.g. a separate TTL box); it does not go to BioSemi
% unless that cable exists.
%
% ACTIVIEW "ANALOG" TRIGGER DISPLAY — how to read it
% -------------------------------------------------
% In analog mode, Actiview draws one horizontal trace per digital TRIGGER BIT
% (often 8 or 16 lines). Each line is HIGH (coloured / non-baseline) or LOW
% (grey / baseline) for that sample.
%
% To match a sent BYTE (0–255) to the picture:
%   1) Note which line is bit0, bit1, ... (order depends on Actiview/BioSemi
%      labelling — use a known code to learn order: e.g. send 1 and see which
%      single line toggles; that line is bit 0 if your convention is LSB-first).
%   2) Read HIGH=1, LOW=0 for each line → binary pattern.
%   3) Decimal code = b0*2^0 + b1*2^1 + ... (once you know which physical bit
%      is which power of two).
%
% The numeric "trigger" field in digital mode is just those bits packed into
% a number; if only a subset of lines is wired or displayed, you will only
% ever see 0..(2^n-1) and high bytes will look "wrong".
%
% WHERE SETTINGS LIVE
% -------------------
% - Actiview trigger format (digital vs analog): Actiview (acquisition PC).
% - Pixel Mode enable from this script: stimulus PC (MATLAB + PTB + Datapixx).
% - Lab Maestro: optional for hardware checks / some modes; your experiment
%   path here is stimulus-driven unless you intentionally configure Maestro.
% - GPU dithering, HDR, colour profiles: stimulus PC (GPU control panel).
%
% Usage
% -----
%   1) Actiview: set trigger display to "Analog" for diagnosis (see above).
%   2) Run: CB_Actiview_TriggerMappingTest
%   3) Press Enter in MATLAB when prompted; read Actiview; type the DECIMAL
%      you see in digital mode, OR type the binary string you read from analog
%      lines (e.g. 00010101) — the script accepts both.
%   4) CSV is saved under ./data/Actiview_CodeMapping_*.csv
%
% Notes
% -----
% - Default: pixel path ON, serial OFF (matches ViewPixx->BioSemi cable only).
% - Trigger pixel uses GL_ONE/GL_ZERO blend when drawing the dot to reduce
%   accidental colour mixing with the background (identity-ish dot).
% - Startup sanity burst is OFF by default (reduces initial trigger spam).

close all;
clc;

cfg = struct();
% --- Path selection (edit if you add a serial->TTL path to BioSemi again) ---
cfg.useSerial = false;   % true only if COM (or similar) actually drives BioSemi triggers
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

cfg.holdCodeSec = 2.00;
cfg.waitBeforeReadSec = 0.20;
cfg.resetHoldSec = 1.00;
cfg.manualAdvance = true;
cfg.doStartupSanity = false;  % set true to send 255 then 0 once at start

% Compact diagnostic list (bit-walk + representative experiment codes)
sendList = [1 2 4 8 16 32 64 128 11 21 31 41 51 127 255];

outDir = fullfile(pwd, 'data');
if ~exist(outDir, 'dir')
    mkdir(outDir);
end
timestamp = datestr(now, 'yyyymmdd_HHMMSS');
outCsv = fullfile(outDir, sprintf('Actiview_CodeMapping_%s.csv', timestamp));

fprintf('\n=== Actiview Trigger Mapping Test ===\n');
fprintf('Expected setup: BioSemi trigger port <- ViewPixx digital out (DB cable).\n');
fprintf('Serial (COM) does NOT reach BioSemi unless that separate path exists.\n\n');
fprintf('Serial enabled: %d\n', cfg.useSerial);
fprintf('Pixel enabled:  %d\n', cfg.usePixel);
if cfg.useSerial
    fprintf('Port: %s @ %d baud\n', cfg.serialPort, cfg.baudRate);
    fprintf('sendResetAfterCode: %d\n', cfg.sendResetAfterCode);
end
fprintf('Total sends: %d\n\n', numel(sendList));
fprintf('ACTIVIEW: use Analog trigger view; read each horizontal line as one bit.\n');
fprintf('MATLAB:  after each hold, type either the decimal Actiview shows,\n');
fprintf('         or an 8-bit binary string like 00010101 (spaces ok).\n');
fprintf('Press Enter alone if unclear -> saved as NaN.\n\n');
if cfg.manualAdvance
    fprintf('Manual mode: press Enter in MATLAB to arm each next code.\n\n');
end

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
    Screen('BlendFunction', window, 'GL_SRC_ALPHA', 'GL_ONE_MINUS_SRC_ALPHA');
    Screen('TextSize', window, 26);
    Screen('TextFont', window, 'Arial');
end

if cfg.doStartupSanity
    fprintf('Startup: sending 255 then 0 (optional sanity).\n');
    emitDualCode(window, windowRect, trigger, pixelState, cfg, 255, 'Startup 255');
    WaitSecs(1.0);
    emitDualCode(window, windowRect, trigger, pixelState, cfg, 0, 'Reset 0');
    WaitSecs(0.5);
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
    emitDualCode(window, windowRect, trigger, pixelState, cfg, code, label);
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

    emitDualCode(window, windowRect, trigger, pixelState, cfg, 0, 'Reset 0');
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

function emitDualCode(window, windowRect, trigger, pixelState, cfg, code, label)
if cfg.useSerial
    sendTrigger(trigger, code);
end
if cfg.usePixel && ~isempty(window)
    Screen('FillRect', window, 0.5);
    bin8 = padLeadingBinary(code, 8);
    if ~isempty(label)
        text = sprintf([ ...
            '%s\n' ...
            'Byte=%d   binary(MSB..LSB)=%s\n' ...
            'SER=%d  PIX=%d\n\n' ...
            'Match Analog lines to these bits (order is lab-specific).' ...
            ], label, code, bin8, cfg.useSerial, cfg.usePixel && pixelState.pixelModeEnabled);
        DrawFormattedText(window, text, 'center', 'center', 0, 90);
    end
    % Identity blend for marker dot (reduces accidental blend with background)
    Screen('BlendFunction', window, 'GL_ONE', 'GL_ZERO');
    drawViewPixxPixelIfNeeded(window, cfg, pixelState, code);
    Screen('BlendFunction', window, 'GL_SRC_ALPHA', 'GL_ONE_MINUS_SRC_ALPHA');
    Screen('Flip', window);
    WaitSecs(cfg.holdCodeSec);
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
