function CB_Photodiode_Ergo1_Test(varargin)
% CB_Photodiode_Ergo1_Test  Photodiode timing test / calibration for BioSemi Ergo1.
%
% Two modes (name-value 'mode'):
%   'demo' (default) — Keyboard-driven sanity check: SPACE start/stop, ESC quit.
%     Status text, optional sync-test skipping, legacy loop timing (GetSecs gate).
%   'calibration' — Automated, flip-centred pulse train for real latency measurement.
%     No status text; strict PTB sync by default; serial code sent immediately before
%     each ON/OFF flip; optional line reset after flip (not before) to avoid blocking
%     the display. Primary offline metric: code 201 (onset) vs photodiode rise.
%     the display. Markers are sent only after WaitSecs yields to just before the
%     scheduled flip (not a full onSec/offSec early). Primary offline metric: code 201.
%
% Common name-value pairs:
%   'mode'           'demo' | 'calibration'
%   'screenNumber'   display index (default 2)
%   'debugWindow'    logical, small window (demo only; calibration always fullscreen)
%   'skipSyncTests'  0 = run sync tests (default in calibration); 1 = skip (demo default)
%   'visualDebugLevel'  PTB visual debug (default 1 demo, 3 calibration)
%   'sendTriggers'   [] = use cfg.eeg.enable default; true/false overrides at runtime
%   'conditionLabel' optional text label saved in metadata and log filename suffix
%   'logDir'         directory for timing logs (default pwd)
%   'saveCsv'        also write events table as CSV (default false)
%   'pdCorner'       photodiode patch corner: 'top-left'|'top-right'|'bottom-left'|'bottom-right'
%   'pdCenterPx'     optional [x y] patch centre in screen pixels; overrides pdCorner
%   'nOnPulses'      calibration: number of white onsets (default 150)
%   'leadInSec'      calibration: hold OFF after runStart before first ON (default 0.5)
%   'leadOutSec'     calibration: hold OFF after last OFF before runStop (default 0.5)
%
% Pulse timing uses cfg.pulse.onSec / cfg.pulse.offSec (defaults 0.10 / 1.40 s).
% Serial codes: runStart=200, on=201, off=202, runStop=203 (cfg.eeg.*).
%
% After recording, use CB_Photodiode_Ergo1_LatencyFromEEG on the BDF; prefer a
% causal search window for reported latency (see that file).
%
% READY-TO-RUN EEG CALIBRATIONS
% Start a new BioSemi recording before each command and stop/save it after the
% command finishes. These commands send the EEG triggers and save both MAT and
% CSV timing logs in the PhotodiodeLogs folder under the current MATLAB folder.
%
% Test 1: photodiode probe and flashing square at the physical top-left corner:
%   CB_Photodiode_Ergo1_Test('mode','calibration','screenNumber',2,'pdCorner','top-left','sendTriggers',true,'conditionLabel','top_left_corner','nOnPulses',150,'leadInSec',0.5,'leadOutSec',0.5,'logDir',fullfile(pwd,'PhotodiodeLogs'),'saveCsv',true);
%
% Test 2: probe and square centred on the experiment's top-left Gabor:
%   CB_Photodiode_Ergo1_Test('mode','calibration','screenNumber',2,'pdCenterPx',[873 453],'sendTriggers',true,'conditionLabel','top_left_gabor','nOnPulses',150,'leadInSec',0.5,'leadOutSec',0.5,'logDir',fullfile(pwd,'PhotodiodeLogs'),'saveCsv',true);
%
% The Gabor centre [873 453] matches CB_4xGratings_v3_Orientation.m on the
% 1920x1080 ViewPixx: screen centre [960 540], minus spacingPx=87 on x and y.
%
% Examples:
%   CB_Photodiode_Ergo1_Test();
%   CB_Photodiode_Ergo1_Test('mode', 'calibration', 'nOnPulses', 200, 'logDir', 'C:\data');
%   CB_Photodiode_Ergo1_Test('mode', 'calibration', 'sendTriggers', false, 'conditionLabel', 'display_only');
%   CB_Photodiode_Ergo1_Test('mode', 'calibration', 'pdCenterPx', [960 540]);
%   CB_Photodiode_Ergo1_Test('mode', 'calibration', 'screenNumber', 2, 'sendTriggers', false, 'conditionLabel', 'display_only', 'nOnPulses', 150, 'leadInSec', 0.5, 'leadOutSec', 0.5, 'logDir', pwd );

close all;
try ListenChar(0); catch, end
try KbQueueRelease(-1); catch, end
if exist('sca', 'file') == 2
    sca;
elseif exist('Screen', 'file') == 2
    Screen('CloseAll');
end

cfg = defaultCfg();
validCorners = {'top-left', 'top-right', 'bottom-left', 'bottom-right'};
p = inputParser;
p.FunctionName = mfilename;
p.addParameter('mode', cfg.mode, @(s) ischar(s) || isstring(s));
p.addParameter('screenNumber', cfg.screenNumber, @(x) isnumeric(x) && isscalar(x));
p.addParameter('debugWindow', cfg.debugWindow, @(x) islogical(x) || isnumeric(x));
p.addParameter('skipSyncTests', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
p.addParameter('visualDebugLevel', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
p.addParameter('sendTriggers', [], @(x) isempty(x) || islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter('conditionLabel', '', @(s) ischar(s) || isstring(s));
p.addParameter('logDir', cfg.logDir, @(s) ischar(s) || isstring(s));
p.addParameter('saveCsv', cfg.saveCsv, @(x) islogical(x) || isnumeric(x));
p.addParameter('pdCorner', cfg.pd.corner, ...
    @(s) (ischar(s) || isstring(s)) && ismember(char(lower(strtrim(string(s)))), validCorners));
p.addParameter('pdCenterPx', cfg.pd.centerPx, ...
    @(x) isempty(x) || (isnumeric(x) && isreal(x) && numel(x) == 2 && all(isfinite(x(:)))));
p.addParameter('nOnPulses', cfg.cal.nOnPulses, @(x) isnumeric(x) && isscalar(x) && x >= 1);
p.addParameter('leadInSec', cfg.cal.leadInSec, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.addParameter('leadOutSec', cfg.cal.leadOutSec, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.addParameter('preFlipWakeLeadSec', cfg.cal.preFlipWakeLeadSec, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.parse(varargin{:});

cfg.mode = char(lower(strtrim(string(p.Results.mode))));
if ~ismember(cfg.mode, {'demo', 'calibration'})
    error('%s: mode must be ''demo'' or ''calibration''.', mfilename);
end
cfg.screenNumber = p.Results.screenNumber;
cfg.debugWindow = logical(p.Results.debugWindow);
cfg.conditionLabel = strtrim(char(string(p.Results.conditionLabel)));
cfg.logDir = char(p.Results.logDir);
cfg.saveCsv = logical(p.Results.saveCsv);
cfg.pd.corner = char(lower(strtrim(string(p.Results.pdCorner))));
if isempty(p.Results.pdCenterPx)
    cfg.pd.centerPx = [];
else
    cfg.pd.centerPx = double(reshape(p.Results.pdCenterPx, 1, 2));
end
cfg.cal.nOnPulses = round(p.Results.nOnPulses);
cfg.cal.leadInSec = double(p.Results.leadInSec);
cfg.cal.leadOutSec = double(p.Results.leadOutSec);
cfg.cal.preFlipWakeLeadSec = double(p.Results.preFlipWakeLeadSec);
if ~isempty(p.Results.sendTriggers)
    cfg.eeg.enable = logical(p.Results.sendTriggers);
end

if isempty(p.Results.skipSyncTests)
    if strcmp(cfg.mode, 'calibration')
        cfg.skipSyncTests = 0;
    else
        cfg.skipSyncTests = 1;
    end
else
    cfg.skipSyncTests = double(p.Results.skipSyncTests);
end
if isempty(p.Results.visualDebugLevel)
    if strcmp(cfg.mode, 'calibration')
        cfg.visualDebugLevel = 3;
    else
        cfg.visualDebugLevel = 1;
    end
else
    cfg.visualDebugLevel = double(p.Results.visualDebugLevel);
end

KbName('UnifyKeyNames');
keys = struct('escape', KbName('ESCAPE'), 'space', KbName('space'));

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
    if strcmp(cfg.mode, 'demo') && cfg.debugWindow
        [window, windowRect] = PsychImaging('OpenWindow', cfg.screenNumber, cfg.bg, [100 100 1000 800]);
    else
        [window, windowRect] = PsychImaging('OpenWindow', cfg.screenNumber, cfg.bg);
    end
    cleanupObj = onCleanup(@() localCleanup(window, trigger)); %#ok<NASGU>

    if strcmp(cfg.mode, 'demo')
        Screen('TextFont', window, 'Arial');
        Screen('TextSize', window, 28);
        Screen('BlendFunction', window, 'GL_SRC_ALPHA', 'GL_ONE_MINUS_SRC_ALPHA');
        runDemo(window, windowRect, cfg, trigger, keys);
    else
        runCalibration(window, windowRect, cfg, trigger, keys);
    end

catch ME
    try localCleanup(window, trigger); catch, end
    rethrow(ME);
end
end

function cfg = defaultCfg()
cfg = struct();
cfg.mode = 'demo';
cfg.screenNumber = 0;
cfg.debugWindow = false;
cfg.skipSyncTests = 1;
cfg.visualDebugLevel = 1;
cfg.bg = 0.5;
cfg.conditionLabel = '';
cfg.logDir = pwd;
cfg.saveCsv = false;

cfg.pd = struct('enable', true, 'sizePx', 100, 'corner', 'bottom-left', 'centerPx', [], ...
    'onColor', 1.0, 'offColor', 0.0);

cfg.pulse = struct('onSec', 0.10, 'offSec', 1.40);

cfg.cal = struct('nOnPulses', 150, 'leadInSec', 0.5, 'leadOutSec', 0.5, ...
    'preFlipWakeLeadSec', 0.002);

cfg.eeg = struct('enable', true, 'serialPort', 'COM4', 'baudRate', 115200, ...
    'pulseWidthSec', 0.005, 'sendResetAfterCode', true, 'warnOnSendError', true, ...
    'codeRunStart', 200, 'codeOn', 201, 'codeOff', 202, 'codeRunStop', 203);
end

function runCalibration(window, windowRect, cfg, trigger, keys)
ifi = Screen('GetFlipInterval', window);
pdRect = makePdRect(windowRect, cfg.pd.sizePx, cfg.pd.corner, cfg.pd.centerPx);
oldPriority = Priority(MaxPriority(window));
priorityCleanup = onCleanup(@() Priority(oldPriority)); %#ok<NASGU>

nOnFrames = max(1, round(cfg.pulse.onSec / ifi));
nOffFrames = max(1, round(cfg.pulse.offSec / ifi));
leadInFrames = round(cfg.cal.leadInSec / ifi);
leadOutFrames = round(cfg.cal.leadOutSec / ifi);

T = table();
vn = {'event', 'code', 'pulseIndex', 'vbl', 'stimOnset', 'flipTimestamp', 'missed', ...
    'sendTimeGetSecs', 'resetTimeGetSecs', 'pulseWidthAchievedSec', 'whenRequested'};
R = table();

tSend = calibrationWriteByteBlocking(trigger, cfg.eeg.codeRunStart);
[tReset, pulseAchieved] = calibrationResetLineAfterSend(trigger, tSend, cfg.eeg.pulseWidthSec, cfg.eeg.sendResetAfterCode);
T = appendTimingRow(T, vn, {'runStart'}, cfg.eeg.codeRunStart, NaN, NaN, NaN, NaN, NaN, ...
    tSend, tReset, pulseAchieved, NaN);

fillBackAndPatch(window, cfg, pdRect, false);
vbl = Screen('Flip', window);

if leadInFrames > 0
    whenNext = vbl + leadInFrames * ifi;
    fillBackAndPatch(window, cfg, pdRect, false);
    [vbl, stimOnset, ft, missed] = screenFlipLog(window, whenNext);
    T = appendTimingRow(T, vn, {'leadInFlip'}, NaN, NaN, vbl, stimOnset, ft, missed, ...
        NaN, NaN, NaN, whenNext);
else
    stimOnset = NaN;
    ft = NaN;
    missed = 0;
end

% First onset is aligned to a full-frame step for consistency with all other transitions.
nextWhenOn = vbl + ifi;
aborted = false;

for p = 1:cfg.cal.nOnPulses
    if checkAbort(keys)
        aborted = true;
        T = appendTimingRow(T, vn, {'abort'}, NaN, NaN, NaN, NaN, NaN, NaN, ...
            NaN, NaN, NaN, NaN);
        break;
    end

    fillBackAndPatch(window, cfg, pdRect, true);
    preFlipYield(nextWhenOn, ifi, cfg.cal.preFlipWakeLeadSec);
    tSend = calibrationWriteByteBlocking(trigger, cfg.eeg.codeOn);
    [vbl, stimOnset, ft, missed] = screenFlipLog(window, nextWhenOn);
    [tReset, pulseAchieved] = calibrationResetLineAfterSend(trigger, tSend, cfg.eeg.pulseWidthSec, cfg.eeg.sendResetAfterCode);
    T = appendTimingRow(T, vn, {'onset'}, cfg.eeg.codeOn, p, vbl, stimOnset, ft, missed, ...
        tSend, tReset, pulseAchieved, nextWhenOn);

    whenOff = vbl + nOnFrames * ifi;
    fillBackAndPatch(window, cfg, pdRect, false);
    preFlipYield(whenOff, ifi, cfg.cal.preFlipWakeLeadSec);
    tSend = calibrationWriteByteBlocking(trigger, cfg.eeg.codeOff);
    [vbl, stimOnset, ft, missed] = screenFlipLog(window, whenOff);
    [tReset, pulseAchieved] = calibrationResetLineAfterSend(trigger, tSend, cfg.eeg.pulseWidthSec, cfg.eeg.sendResetAfterCode);
    T = appendTimingRow(T, vn, {'offset'}, cfg.eeg.codeOff, p, vbl, stimOnset, ft, missed, ...
        tSend, tReset, pulseAchieved, whenOff);

    nextWhenOn = vbl + nOffFrames * ifi;
end

if ~aborted && leadOutFrames > 0
    whenLeadOut = vbl + leadOutFrames * ifi;
    fillBackAndPatch(window, cfg, pdRect, false);
    [vbl, stimOnset, ft, missed] = screenFlipLog(window, whenLeadOut);
    T = appendTimingRow(T, vn, {'leadOutFlip'}, NaN, NaN, vbl, stimOnset, ft, missed, ...
        NaN, NaN, NaN, whenLeadOut);
end

tStop = calibrationWriteByteBlocking(trigger, cfg.eeg.codeRunStop);
[tReset, pulseAchieved] = calibrationResetLineAfterSend(trigger, tStop, cfg.eeg.pulseWidthSec, cfg.eeg.sendResetAfterCode);
T = appendTimingRow(T, vn, {'runStop'}, cfg.eeg.codeRunStop, NaN, NaN, NaN, NaN, NaN, ...
    tStop, tReset, pulseAchieved, NaN);

meta = struct();
try
    meta.ptbVersion = Screen('Version');
catch
    meta.ptbVersion = 'unknown';
end
meta.ifi = ifi;
meta.nOnFrames = nOnFrames;
meta.nOffFrames = nOffFrames;
meta.leadInFrames = leadInFrames;
meta.leadOutFrames = leadOutFrames;
meta.skipSyncTests = cfg.skipSyncTests;
meta.screenNumber = cfg.screenNumber;
meta.mode = cfg.mode;
meta.eegEnable = logical(cfg.eeg.enable);
meta.serialPort = cfg.eeg.serialPort;
meta.conditionLabel = cfg.conditionLabel;
meta.pdCorner = cfg.pd.corner;
meta.pdCenterPx = cfg.pd.centerPx;
meta.pdRect = pdRect;
meta.preFlipWakeLeadSec = cfg.cal.preFlipWakeLeadSec;
meta.resetPolicy = 'deterministic absolute-deadline reset: send-before-flip and reset-to-zero at tSend+pulseWidthSec after flip';

saveTimingLog(T, R, meta, cfg);
printPulseQcSummary(T, cfg);
end

function [vbl, stimOnset, ft, missed] = screenFlipLog(window, when)
[vbl, stimOnset, ft, missed] = Screen('Flip', window, when, 0);
end

function preFlipYield(targetWhen, ifi, wakeLeadSec)
% Sleep until shortly before targetWhen so serial + Flip run immediately pre-VBL
% (avoids sending markers a full on/off interval before the scheduled flip).
if nargin < 3 || isempty(wakeLeadSec)
    lead = max(0.0005, 0.25 * ifi);
else
    lead = max(0, double(wakeLeadSec));
end
tWake = targetWhen - lead;
nowT = GetSecs;
if nowT < tWake
    WaitSecs('UntilTime', tWake);
end
end

function abort = checkAbort(keys)
[~, ~, keyCode] = KbCheck(-1);
abort = logical(keyCode(keys.escape));
end

function T = appendTimingRow(T, vn, event, code, pulseIndex, vbl, stimOnset, flipTimestamp, missed, sendTimeGetSecs, resetTimeGetSecs, pulseWidthAchievedSec, whenRequested)
row = table(event, code, pulseIndex, vbl, stimOnset, flipTimestamp, missed, sendTimeGetSecs, resetTimeGetSecs, pulseWidthAchievedSec, whenRequested, 'VariableNames', vn);
if isempty(T)
    T = row;
else
    T = [T; row]; %#ok<AGROW>
end
end

function saveTimingLog(T, R, meta, cfg)
if isempty(T)
    warning('CB_Photodiode_Ergo1_Test: no timing rows to save.');
    return;
end
if ~exist(cfg.logDir, 'dir')
    mkdir(cfg.logDir);
end
ts = datestr(now, 'yyyymmdd_HHMMSS');
labelSuffix = sanitizeLabel(cfg.conditionLabel);
if isempty(labelSuffix)
    base = fullfile(cfg.logDir, sprintf('CB_Photodiode_Ergo1_Test_log_%s', ts));
else
    base = fullfile(cfg.logDir, sprintf('CB_Photodiode_Ergo1_Test_log_%s_%s', ts, labelSuffix));
end
save([base '.mat'], 'T', 'R', 'meta', 'cfg', '-v7.3');
fprintf('Timing log saved: %s.mat\n', base);
if cfg.saveCsv
    writetable(T, [base '_events.csv']);
    if ~isempty(R)
        writetable(R, [base '_resets.csv']);
    end
    fprintf('Events CSV: %s_events.csv\n', base);
end
end

function fillBackAndPatch(window, cfg, pdRect, stateOn)
Screen('FillRect', window, cfg.bg);
if cfg.pd.enable
    if stateOn
        Screen('FillRect', window, cfg.pd.onColor, pdRect);
    else
        Screen('FillRect', window, cfg.pd.offColor, pdRect);
    end
end
end

function runDemo(window, windowRect, cfg, trigger, keys)
ifi = Screen('GetFlipInterval', window);
pdRect = makePdRect(windowRect, cfg.pd.sizePx, cfg.pd.corner, cfg.pd.centerPx);

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
                sendTriggerFull(trigger, cfg.eeg.codeRunStart, cfg.eeg);
            else
                sendTriggerFull(trigger, cfg.eeg.codeRunStop, cfg.eeg);
            end
        end
        KbQueueFlush(-1);
    end

    if pulsing && nowT >= nextSwitch
        stateOn = ~stateOn;
        if stateOn
            nOn = nOn + 1;
            sendTriggerFull(trigger, cfg.eeg.codeOn, cfg.eeg);
            nextSwitch = nowT + cfg.pulse.onSec;
        else
            sendTriggerFull(trigger, cfg.eeg.codeOff, cfg.eeg);
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
    'Photodiode Ergo1 Test (demo)\\n\\n' ...
    'SPACE: start/stop pulses\\n' ...
    'ESC: quit\\n\\n' ...
    'Pulse state: %s\\n' ...
    'Patch state: %s\\n' ...
    'ON pulses sent: %d\\n\\n' ...
    'ON duration: %.3f s   OFF duration: %.3f s\\n' ...
    'Serial trigger enabled: %d\\n' ...
    'Codes: runStart=%d  on=%d  off=%d  runStop=%d\\n' ...
    'Use mode=''calibration'' for flip-centred timing run.\\n'], ...
    runTxt, pdTxt, nOn, cfg.pulse.onSec, cfg.pulse.offSec, serialEnabled, ...
    cfg.eeg.codeRunStart, cfg.eeg.codeOn, cfg.eeg.codeOff, cfg.eeg.codeRunStop);

DrawFormattedText(window, txt, 'center', windowRect(4) * 0.18, 0, 90);
end

function pdRect = makePdRect(windowRect, sizePx, cornerName, centerPx)
if ~isempty(centerPx)
    halfSize = sizePx / 2;
    pdRect = [centerPx(1)-halfSize, centerPx(2)-halfSize, ...
        centerPx(1)+halfSize, centerPx(2)+halfSize];
    if pdRect(1) < windowRect(1) || pdRect(2) < windowRect(2) || ...
            pdRect(3) > windowRect(3) || pdRect(4) > windowRect(4)
        error(['pdCenterPx [%g %g] places the %g-pixel photodiode patch outside ' ...
            'the screen rectangle [%g %g %g %g].'], ...
            centerPx(1), centerPx(2), sizePx, windowRect);
    end
    return;
end

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
    fprintf('Serial trigger enabled on %s @ %d baud.\n', eegCfg.serialPort, eegCfg.baudRate);
catch ME
    warning('Serial trigger disabled: %s', mExceptionText(ME));
end
end

function sendTriggerFast(trigger, code)
if ~trigger.enabled || isempty(trigger.handle)
    return;
end
if isnan(code) || code < 0 || code > 255
    return;
end
try
    IOPort('Write', trigger.handle, uint8(code), 0);
catch ME
    if trigger.warnOnSendError
        warning('Trigger send failed (%d): %s', code, mExceptionText(ME));
    end
end
end

function tWhen = calibrationWriteByteBlocking(trigger, code)
tWhen = NaN;
if ~trigger.enabled || isempty(trigger.handle)
    return;
end
if isnan(code) || code < 0 || code > 255
    return;
end
try
    [~, tWhen] = IOPort('Write', trigger.handle, uint8(code), 1);
    if isempty(tWhen) || ~isfinite(tWhen)
        tWhen = GetSecs;
    end
catch ME
    if trigger.warnOnSendError
        warning('Trigger send failed (%d): %s', code, mExceptionText(ME));
    end
end
end

function [tResetWhen, achievedSec] = calibrationResetLineAfterSend(trigger, tSendWhen, pulseWidthSec, doReset)
tResetWhen = NaN;
achievedSec = NaN;
if nargin < 4 || ~logical(doReset)
    return;
end
if ~trigger.enabled || isempty(trigger.handle) || ~isfinite(tSendWhen)
    return;
end
deadline = tSendWhen + pulseWidthSec;
if GetSecs < deadline
    WaitSecs('UntilTime', deadline);
end
try
    [~, tResetWhen] = IOPort('Write', trigger.handle, uint8(0), 1);
    if isempty(tResetWhen) || ~isfinite(tResetWhen)
        tResetWhen = GetSecs;
    end
    achievedSec = tResetWhen - tSendWhen;
catch ME
    if trigger.warnOnSendError
        warning('Trigger reset failed: %s', mExceptionText(ME));
    end
end
end

function printPulseQcSummary(T, cfg)
if isempty(T) || ~ismember('pulseWidthAchievedSec', T.Properties.VariableNames)
    fprintf('Pulse QC: no pulse-width rows logged.\n');
    return;
end
vals = T.pulseWidthAchievedSec;
vals = vals(isfinite(vals));
if isempty(vals)
    fprintf('Pulse QC: no finite pulse-width measurements logged.\n');
    return;
end
target = cfg.eeg.pulseWidthSec;
errMs = (vals - target) * 1000;
fprintf(['Pulse QC: n=%d, target=%.3f ms, mean=%.3f ms, min=%.3f ms, max=%.3f ms, ' ...
    'maxAbsErr=%.3f ms\n'], ...
    numel(vals), target * 1000, mean(vals) * 1000, min(vals) * 1000, max(vals) * 1000, max(abs(errMs)));
end

function sendTriggerFull(trigger, code, eegCfg)
if ~trigger.enabled || isempty(trigger.handle)
    return;
end
if isnan(code) || code < 0 || code > 255
    return;
end
try
    IOPort('Write', trigger.handle, uint8(code), 0);
    if eegCfg.sendResetAfterCode
        WaitSecs(eegCfg.pulseWidthSec);
        IOPort('Write', trigger.handle, uint8(0), 0);
    end
catch ME
    if eegCfg.warnOnSendError
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

function out = sanitizeLabel(in)
out = strtrim(char(string(in)));
if isempty(out)
    return;
end
out = lower(out);
out = regexprep(out, '[^a-z0-9]+', '_');
out = regexprep(out, '^_+|_+$', '');
end
