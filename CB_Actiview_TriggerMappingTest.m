function CB_Actiview_TriggerMappingTest
% CB_Actiview_TriggerMappingTest
% Send a known sequence of serial trigger bytes to map:
%   "code sent by MATLAB" -> "code shown in Actiview".
%
% Usage:
%   1) Start Actiview and watch trigger display.
%   2) Run this function.
%   3) Type the Actiview code you observed for each prompt.
%   4) A CSV mapping file is saved in ./data.
%
% Notes:
% - By default this script mirrors the main task's serial behavior:
%   short pulse + optional reset-to-0 after each code.
% - If matching is confusing, set sendResetAfterCode=false below.

close all;
clc;

cfg = struct();
cfg.serialPort = 'COM3';
cfg.baudRate = 115200;
cfg.pulseWidthSec = 0.005;
cfg.sendResetAfterCode = true;
cfg.warnOnSendError = true;

cfg.waitBeforeReadSec = 0.30; % time to read Actiview display
cfg.waitBetweenCodesSec = 0.35;
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
fprintf('Port: %s @ %d baud\n', cfg.serialPort, cfg.baudRate);
fprintf('sendResetAfterCode: %d\n', cfg.sendResetAfterCode);
fprintf('Total sends: %d (%d codes x %d repeats)\n\n', numel(sendList), numel(allCodes), cfg.repeatsPerCode);
fprintf('For each send, type what Actiview shows.\n');
fprintf('If missed/unclear, press Enter for NaN.\n\n');

trigger = initSerialTrigger(cfg);
cleanupObj = onCleanup(@() closeSerialTrigger(trigger)); %#ok<NASGU>

if ~trigger.enabled
    error('Could not open serial trigger. Check COM port and device connection.');
end

n = numel(sendList);
sentCode = nan(n,1);
activiewObserved = nan(n,1);
trialIdx = (1:n)';

for i = 1:n
    code = sendList(i);
    sentCode(i) = code;

    sendTrigger(trigger, code);
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
