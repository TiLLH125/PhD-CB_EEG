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
%   'logDir'         directory for timing logs (default pwd)
%   'saveCsv'        also write events table as CSV (default false)
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
% Examples:
%   CB_Photodiode_Ergo1_Test();
%   CB_Photodiode_Ergo1_Test('mode', 'calibration', 'nOnPulses', 200, 'logDir', 'C:\data');

close all;
try ListenChar(0); catch, end
try KbQueueRelease(-1); catch, end
if exist('sca', 'file') == 2
sca;
elseif exist('Screen', 'file') == 2
Screen('CloseAll');
end

cfg = defaultCfg();
p = inputParser;
p.FunctionName = mfilename;
p.addParameter('mode', cfg.mode, @(s) ischar(s) || isstring(s));
p.addParameter('screenNumber', cfg.screenNumber, @(x) isnumeric(x) && isscalar(x));
p.addParameter('debugWindow', cfg.debugWindow, @(x) islogical(x) || isnumeric(x));
p.addParameter('skipSyncTests', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
p.addParameter('visualDebugLevel', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
p.addParameter('logDir', cfg.logDir, @(s) ischar(s) || isstring(s));
p.addParameter('saveCsv', cfg.saveCsv, @(x) islogical(x) || isnumeric(x));
p.addParameter('nOnPulses', cfg.cal.nOnPulses, @(x) isnumeric(x) && isscalar(x) && x >= 1);
p.addParameter('leadInSec', cfg.cal.leadInSec, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.addParameter('leadOutSec', cfg.cal.leadOutSec, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.parse(varargin{:});

cfg.mode = char(lower(strtrim(string(p.Results.mode))));
if ~ismember(cfg.mode, {'demo', 'calibration'})
error('%s: mode must be ''demo'' or ''calibration''.', mfilename);
end
cfg.screenNumber = p.Results.screenNumber;
cfg.debugWindow = logical(p.Results.debugWindow);
cfg.logDir = char(p.Results.logDir);
cfg.saveCsv = logical(p.Results.saveCsv);
cfg.cal.nOnPulses = round(p.Results.nOnPulses);
cfg.cal.leadInSec = double(p.Results.leadInSec);
cfg.cal.leadOutSec = double(p.Results.leadOutSec);

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
cfg.screenNumber = 2;
cfg.debugWindow = false;
cfg.skipSyncTests = 1;
cfg.visualDebugLevel = 1;
cfg.bg = 0.5;
cfg.logDir = pwd;
cfg.saveCsv = false;

cfg.pd = struct('enable', true, 'sizePx', 100, 'corner', 'top-left', ...
'onColor', 1.0, 'offColor', 0.0);

cfg.pulse = struct('onSec', 0.10, 'offSec', 1.40);

cfg.cal = struct('nOnPulses', 150, 'leadInSec', 0.5, 'leadOutSec', 0.5);

cfg.eeg = struct('enable', true, 'serialPort', 'COM4', 'baudRate', 115200, ...
'pulseWidthSec', 0.005, 'sendResetAfterCode', true, 'warnOnSendError', true, ...
'codeRunStart', 200, 'codeOn', 201, 'codeOff', 202, 'codeRunStop', 203);
end

function runCalibration(window, windowRect, cfg, trigger, keys)
ifi = Screen('GetFlipInterval', window);
pdRect = makePdRect(windowRect, cfg.pd.sizePx, cfg.pd.corner);

nOnFrames = max(1, round(cfg.pulse.onSec / ifi));
nOffFrames = max(1, round(cfg.pulse.offSec / ifi));
leadInFrames = round(cfg.cal.leadInSec / ifi);
leadOutFrames = round(cfg.cal.leadOutSec / ifi);

T = table();
vn = {'event', 'code', 'pulseIndex', 'vbl', 'stimOnset', 'flipTimestamp', 'missed', 'sendTimeGetSecs', 'whenRequested'};
R = table();
rvn = {'event', 'code', 'pulseIndex', 'dueTimeGetSecs', 'execTimeGetSecs', 'serviceMode', 'waitedSec', 'forcedEarly', 'lateSec'};
resetState = initResetState(cfg.eeg);

sendTriggerFast(trigger, cfg.eeg.codeRunStart);
tSend = GetSecs;
resetState = armReset(resetState, tSend, 'runStart', cfg.eeg.codeRunStart, NaN);
T = appendTimingRow(T, vn, {'runStart'}, cfg.eeg.codeRunStart, NaN, NaN, NaN, NaN, NaN, tSend, NaN);

fillBackAndPatch(window, cfg, pdRect, false);
vbl = Screen('Flip', window);
[resetState, rLog] = serviceReset(trigger, resetState, 'opportunistic');
R = appendResetRow(R, rvn, rLog);

if leadInFrames > 0
whenNext = vbl + leadInFrames * ifi;
fillBackAndPatch(window, cfg, pdRect, false);
[vbl, stimOnset, ft, missed] = screenFlipLog(window, whenNext);
[resetState, rLog] = serviceReset(trigger, resetState, 'opportunistic');
R = appendResetRow(R, rvn, rLog);
T = appendTimingRow(T, vn, {'leadInFlip'}, NaN, NaN, vbl, stimOnset, ft, missed, NaN, whenNext);
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
T = appendTimingRow(T, vn, {'abort'}, NaN, NaN, NaN, NaN, NaN, NaN, GetSecs, NaN);
break;
end

% Ensure previous code reset reaches due time before next marker.
[resetState, rLog] = serviceReset(trigger, resetState, 'beforeNextCode');
R = appendResetRow(R, rvn, rLog);
fillBackAndPatch(window, cfg, pdRect, true);
    preFlipYield(nextWhenOn, ifi);
sendTriggerFast(trigger, cfg.eeg.codeOn);
tSend = GetSecs;
resetState = armReset(resetState, tSend, 'onset', cfg.eeg.codeOn, p);
[vbl, stimOnset, ft, missed] = screenFlipLog(window, nextWhenOn);
[resetState, rLog] = serviceReset(trigger, resetState, 'opportunistic');
R = appendResetRow(R, rvn, rLog);
T = appendTimingRow(T, vn, {'onset'}, cfg.eeg.codeOn, p, vbl, stimOnset, ft, missed, tSend, nextWhenOn);

whenOff = vbl + nOnFrames * ifi;
[resetState, rLog] = serviceReset(trigger, resetState, 'beforeNextCode');
R = appendResetRow(R, rvn, rLog);
fillBackAndPatch(window, cfg, pdRect, false);
    preFlipYield(whenOff, ifi);
sendTriggerFast(trigger, cfg.eeg.codeOff);
tSend = GetSecs;
resetState = armReset(resetState, tSend, 'offset', cfg.eeg.codeOff, p);
[vbl, stimOnset, ft, missed] = screenFlipLog(window, whenOff);
[resetState, rLog] = serviceReset(trigger, resetState, 'opportunistic');
R = appendResetRow(R, rvn, rLog);
T = appendTimingRow(T, vn, {'offset'}, cfg.eeg.codeOff, p, vbl, stimOnset, ft, missed, tSend, whenOff);

nextWhenOn = vbl + nOffFrames * ifi;
end

if ~aborted && leadOutFrames > 0
whenLeadOut = vbl + leadOutFrames * ifi;
fillBackAndPatch(window, cfg, pdRect, false);
[vbl, stimOnset, ft, missed] = screenFlipLog(window, whenLeadOut);
[resetState, rLog] = serviceReset(trigger, resetState, 'opportunistic');
R = appendResetRow(R, rvn, rLog);
T = appendTimingRow(T, vn, {'leadOutFlip'}, NaN, NaN, vbl, stimOnset, ft, missed, NaN, whenLeadOut);
end

[resetState, rLog] = serviceReset(trigger, resetState, 'beforeNextCode');
R = appendResetRow(R, rvn, rLog);
sendTriggerFast(trigger, cfg.eeg.codeRunStop);
tStop = GetSecs;
resetState = armReset(resetState, tStop, 'runStop', cfg.eeg.codeRunStop, NaN);
[resetState, rLog] = serviceReset(trigger, resetState, 'beforeNextCode');
R = appendResetRow(R, rvn, rLog);
T = appendTimingRow(T, vn, {'runStop'}, cfg.eeg.codeRunStop, NaN, NaN, NaN, NaN, NaN, tStop, NaN);

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
meta.resetPolicy = 'due-time reset; opportunistic after flip, enforced before next code';

saveTimingLog(T, R, meta, cfg);
printResetQcSummary(R);
end

function [vbl, stimOnset, ft, missed] = screenFlipLog(window, when)
[vbl, stimOnset, ft, missed] = Screen('Flip', window, when, 0);
end

function preFlipYield(targetWhen, ifi)
% Sleep until shortly before targetWhen so serial + Flip run immediately pre-VBL
% (avoids sending markers a full on/off interval before the scheduled flip).
lead = max(0.0005, 0.25 * ifi);
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

function T = appendTimingRow(T, vn, event, code, pulseIndex, vbl, stimOnset, flipTimestamp, missed, sendTimeGetSecs, whenRequested)
row = table(event, code, pulseIndex, vbl, stimOnset, flipTimestamp, missed, sendTimeGetSecs, whenRequested, 'VariableNames', vn);
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
base = fullfile(cfg.logDir, sprintf('CB_Photodiode_Ergo1_Test_log_%s', ts));
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

function state = initResetState(eegCfg)
state = struct();
state.enabled = logical(eegCfg.sendResetAfterCode);
state.pulseWidthSec = double(eegCfg.pulseWidthSec);
state.pending = false;
state.dueTime = NaN;
state.event = '';
state.code = NaN;
state.pulseIndex = NaN;
end

function state = armReset(state, sendTime, eventName, code, pulseIndex)
if ~state.enabled
return;
end
state.pending = true;
state.dueTime = sendTime + state.pulseWidthSec;
state.event = char(eventName);
state.code = code;
state.pulseIndex = pulseIndex;
end

function [state, rLog] = serviceReset(trigger, state, mode)
rLog = table();
if nargin < 3 || isempty(mode)
mode = 'opportunistic';
end
if ~state.enabled || ~state.pending || ~trigger.enabled || isempty(trigger.handle)
return;
end
nowT = GetSecs;
waitedSec = 0;
forcedEarly = false;
if strcmp(mode, 'opportunistic')
if nowT < state.dueTime
return;
end
elseif strcmp(mode, 'beforeNextCode')
if nowT < state.dueTime
WaitSecs('UntilTime', state.dueTime);
waitedSec = state.dueTime - nowT;
nowT = GetSecs;
end
else
error('Unknown reset service mode: %s', mode);
end
try
IOPort('Write', trigger.handle, uint8(0), 0);
execT = GetSecs;
lateSec = max(0, execT - state.dueTime);
rLog = table({state.event}, state.code, state.pulseIndex, state.dueTime, execT, {mode}, ...
waitedSec, forcedEarly, lateSec, ...
'VariableNames', {'event', 'code', 'pulseIndex', 'dueTimeGetSecs', 'execTimeGetSecs', 'serviceMode', 'waitedSec', 'forcedEarly', 'lateSec'});
state.pending = false;
state.dueTime = NaN;
state.event = '';
state.code = NaN;
state.pulseIndex = NaN;
catch ME
if trigger.warnOnSendError
warning('Trigger reset failed: %s', mExceptionText(ME));
end
end
end

function R = appendResetRow(R, rvn, rLog)
if isempty(rLog)
return;
end
if isempty(R)
R = rLog;
else
R = [R; rLog(:, rvn)]; %#ok<AGROW>
end
end

function printResetQcSummary(R)
if isempty(R)
fprintf('Reset QC: no reset events logged.\n');
return;
end
nReset = height(R);
nBefore = sum(strcmp(R.serviceMode, 'beforeNextCode'));
nOpp = sum(strcmp(R.serviceMode, 'opportunistic'));
nWaited = sum(R.waitedSec > 0);
maxWaitMs = max(R.waitedSec) * 1000;
maxLateMs = max(R.lateSec) * 1000;
nLateOver1ms = sum(R.lateSec > 0.001);
nForcedEarly = sum(R.forcedEarly ~= 0);
fprintf(['Reset QC: n=%d (beforeNextCode=%d, opportunistic=%d), ' ...
'waited=%d (max=%.3f ms), late>1ms=%d (maxLate=%.3f ms), forcedEarly=%d\n'], ...
nReset, nBefore, nOpp, nWaited, maxWaitMs, nLateOver1ms, maxLateMs, nForcedEarly);
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
