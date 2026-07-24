function out = CB_Photodiode_Ergo1_AnalyseBDF_RawRise(varargin)
% CB_Photodiode_Ergo1_AnalyseBDF_RawRise
% -------------------------------------------------------------------------
% Raw-waveform trigger-to-photon latency analysis for BioSemi BDF files
% recorded with CB_Photodiode_Ergo1_Test.
%
% This version deliberately applies NO low-pass filter and NO moving-average
% smoothing. For every selected onset marker it measures the first sustained
% crossings of 10%, 50%, and 90% of the trial-specific black-to-white signal
% range, using the raw Ergo1 samples. The 50% crossing is the primary latency
% metric. It also reports the 10-90% rise time.
%
% Basic use:
%   out = CB_Photodiode_Ergo1_AnalyseBDF_RawRise;
%
% Explicit BDF:
%   out = CB_Photodiode_Ergo1_AnalyseBDF_RawRise( ...
%       'bdfFile', 'C:\data\PhotodiodeTest2.bdf');
%
% Task-validation BDF: automatically run S1/code 21 and S2/code 23:
%   out = CB_Photodiode_Ergo1_AnalyseBDF_RawRise( ...
%       'analysisProfile', 'task-validation', ...
%       'bdfFile', 'C:\data\TaskValidation.bdf');
%   % Results are returned as out.S1 and out.S2.
%
% Common options:
%   'analysisProfile'      'calibration' (default), 'task-validation',
%                          'task-s1', or 'task-s2'.
%   'pdChan'               Ergo1 channel index. [] = find by label.
%   'pdLabel'              Preferred label fragment. Default 'Erg1'.
%   'excludePulseIndices'  Pulse numbers excluded from summaries. Default 1.
%   'monitorHz'            Display refresh rate. Default 120.
%   'onCode'               Override profile trigger code (201, 21, or 23).
%   'onsetLabel'           Override profile label used in outputs.
%   'searchWinMs'          Default [0 60] calibration; [-20 60] task.
%   'baselineWinMs'        Default [-100 -20] calibration; [-100 -30] task.
%   'plateauWinMs'         White reference window. Default [100 300].
%   'riseFractions'        Raw rise thresholds. Default [0.10 0.50 0.90].
%   'minRunSamples'        Consecutive samples beyond threshold. Default 3.
%   'minSignalToNoise'     Minimum |white-black| / baseline MAD. Default 10.
%   'expectedOnsets'       Default 150 calibration; 30 task.
%   'outputDir'            Output folder. Default *_PhotodiodeAnalysis_RawRise.
%   'saveFigures'          Save PNG and FIG files. Default true.
%   'showFigures'          Display figures. Default true.
%   'nExampleTraces'       Number of example traces. Default 8.
%
% Requirements:
%   EEGLAB and the BIOSIG importer (pop_biosig).
% -------------------------------------------------------------------------

analysisVersion = 'RawRise-v3.0';

%% Parse settings
p = inputParser;
p.FunctionName = mfilename;
p.addParameter('analysisProfile', 'calibration', @(x) ischar(x) || isstring(x));
p.addParameter('bdfFile', '', @(x) ischar(x) || isstring(x));
p.addParameter('pdChan', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 1));
p.addParameter('pdLabel', 'Erg1', @(x) ischar(x) || isstring(x));
p.addParameter('excludePulseIndices', 1, @(x) isempty(x) || isnumeric(x));
p.addParameter('monitorHz', 120, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
p.addParameter('onCode', 201, @(x) isnumeric(x) && isscalar(x) && isfinite(x));
p.addParameter('onsetLabel', '', @(x) ischar(x) || isstring(x));
p.addParameter('searchWinMs', [0 60], @(x) isnumeric(x) && numel(x) == 2 && x(1) <= x(2));
p.addParameter('baselineWinMs', [-100 -20], @(x) isnumeric(x) && numel(x) == 2 && x(1) < x(2));
p.addParameter('plateauWinMs', [100 300], @(x) isnumeric(x) && numel(x) == 2 && x(1) < x(2));
p.addParameter('riseFractions', [0.10 0.50 0.90], @(x) isnumeric(x) && numel(x) == 3 && all(isfinite(x)));
p.addParameter('minRunSamples', 3, @(x) isnumeric(x) && isscalar(x) && x >= 1);
p.addParameter('minSignalToNoise', 10, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
p.addParameter('expectedOnsets', 150, @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 1));
p.addParameter('outputDir', '', @(x) ischar(x) || isstring(x));
p.addParameter('saveFigures', true, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter('showFigures', true, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter('nExampleTraces', 8, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.parse(varargin{:});
cfg = p.Results;

cfg.analysisProfile = char(lower(strtrim(string(cfg.analysisProfile))));
cfg.bdfFile = char(string(cfg.bdfFile));
cfg.pdLabel = char(string(cfg.pdLabel));
cfg.onsetLabel = strtrim(char(string(cfg.onsetLabel)));
cfg.outputDir = char(string(cfg.outputDir));
cfg.excludePulseIndices = unique(round(cfg.excludePulseIndices(:)'));
cfg.excludePulseIndices = cfg.excludePulseIndices(cfg.excludePulseIndices >= 1);
cfg.minRunSamples = round(cfg.minRunSamples);
cfg.saveFigures = logical(cfg.saveFigures);
cfg.showFigures = logical(cfg.showFigures);
cfg.frameMs = 1000 / cfg.monitorHz;
cfg.riseFractions = sort(double(cfg.riseFractions(:)'));

validProfiles = {'calibration', 'task-validation', 'task-s1', 'task-s2'};
if ~ismember(cfg.analysisProfile, validProfiles)
    error(['analysisProfile must be ''calibration'', ''task-validation'', ' ...
        '''task-s1'', or ''task-s2''.']);
end

usedDefault = @(name) any(strcmpi(p.UsingDefaults, name));
isTaskProfile = ismember(cfg.analysisProfile, {'task-validation', 'task-s1', 'task-s2'});
if isTaskProfile
    if usedDefault('searchWinMs')
        cfg.searchWinMs = [-20 60];
    end
    if usedDefault('baselineWinMs')
        cfg.baselineWinMs = [-100 -30];
    end
    if usedDefault('expectedOnsets')
        cfg.expectedOnsets = 30;
    end
end

if strcmp(cfg.analysisProfile, 'task-s1')
    if usedDefault('onCode'), cfg.onCode = 21; end
    if usedDefault('onsetLabel'), cfg.onsetLabel = 'S1'; end
elseif strcmp(cfg.analysisProfile, 'task-s2')
    if usedDefault('onCode'), cfg.onCode = 23; end
    if usedDefault('onsetLabel'), cfg.onsetLabel = 'S2'; end
elseif strcmp(cfg.analysisProfile, 'calibration')
    if usedDefault('onCode'), cfg.onCode = 201; end
    if usedDefault('onsetLabel')
        if cfg.onCode == 201
            cfg.onsetLabel = 'Calibration onset';
        else
            cfg.onsetLabel = sprintf('Trigger %d', round(cfg.onCode));
        end
    end
else
    cfg.onsetLabel = 'S1/S2 task validation';
end

if cfg.onCode < 0 || cfg.onCode > 255 || cfg.onCode ~= round(cfg.onCode)
    error('onCode must be an integer in the range 0..255.');
end

if any(cfg.riseFractions <= 0 | cfg.riseFractions >= 1)
    error('riseFractions must all be strictly between 0 and 1.');
end
if max(abs(cfg.riseFractions - [0.10 0.50 0.90])) > 1e-10
    warning('This script labels the three thresholds as 10/50/90; using custom fractions %s.', ...
        mat2str(cfg.riseFractions, 3));
end
if cfg.baselineWinMs(2) >= cfg.searchWinMs(1)
    error('baselineWinMs must finish before searchWinMs begins.');
end
if cfg.plateauWinMs(1) <= cfg.searchWinMs(2)
    warning(['The plateau window begins at %.1f ms and the search window ends at %.1f ms. ' ...
        'A wider separation is usually preferable.'], cfg.plateauWinMs(1), cfg.searchWinMs(2));
end

%% Select BDF
if isempty(strtrim(cfg.bdfFile))
    [f, d] = uigetfile({'*.bdf', 'BioSemi BDF files (*.bdf)'}, ...
        'Select the photodiode calibration BDF');
    if isequal(f, 0)
        error('No BDF file selected.');
    end
    cfg.bdfFile = fullfile(d, f);
end
if ~isfile(cfg.bdfFile)
    error('BDF file not found: %s', cfg.bdfFile);
end

[bdfDir, bdfBase, ~] = fileparts(cfg.bdfFile);
if strcmp(cfg.analysisProfile, 'task-validation')
    out = runTaskValidationPair(cfg, bdfDir, bdfBase);
    return;
end

if isempty(strtrim(cfg.outputDir))
    if strcmp(cfg.analysisProfile, 'calibration') && cfg.onCode == 201
        cfg.outputDir = fullfile(bdfDir, [bdfBase '_PhotodiodeAnalysis_RawRise']);
    else
        cfg.outputDir = fullfile(bdfDir, sprintf('%s_%s_Code%d_PhotodiodeAnalysis_RawRise', ...
            bdfBase, sanitizeFileLabel(cfg.onsetLabel), cfg.onCode));
    end
end
if ~exist(cfg.outputDir, 'dir')
    mkdir(cfg.outputDir);
end

if strcmp(cfg.analysisProfile, 'calibration') && cfg.onCode == 201
    analysisStem = bdfBase;
else
    analysisStem = sprintf('%s_%s_Code%d', bdfBase, sanitizeFileLabel(cfg.onsetLabel), cfg.onCode);
end

fprintf('\n============================================================\n');
fprintf('CB photodiode BDF raw-rise latency analysis\n');
fprintf('Analysis version: %s\n', analysisVersion);
fprintf('Analysis profile: %s\n', cfg.analysisProfile);
fprintf('Onset marker: %s (code %d)\n', cfg.onsetLabel, cfg.onCode);
fprintf('Detector: raw 10%% / 50%% / 90%% sustained crossings; NO smoothing\n');
fprintf('BDF: %s\n', cfg.bdfFile);
fprintf('Output: %s\n', cfg.outputDir);
fprintf('============================================================\n\n');

%% Check EEGLAB/BIOSIG
if exist('pop_biosig', 'file') ~= 2
    if exist('eeglab', 'file') == 2
        fprintf('Initialising EEGLAB without the GUI...\n');
        try
            eeglab('nogui');
        catch ME
            warning('EEGLAB initialisation returned: %s', ME.message);
        end
    end
end
if exist('pop_biosig', 'file') ~= 2
    error(['pop_biosig was not found. Add EEGLAB and the BIOSIG plugin to the ' ...
        'MATLAB path, then run this function again.']);
end

%% Import raw BDF
fprintf('Importing raw BDF with pop_biosig...\n');
EEG = pop_biosig(cfg.bdfFile);
if exist('eeg_checkset', 'file') == 2
    EEG = eeg_checkset(EEG, 'eventconsistency');
end
if isempty(EEG) || ~isfield(EEG, 'data') || isempty(EEG.data)
    error('The BDF import did not return continuous data.');
end
if ~isfield(EEG, 'event') || isempty(EEG.event)
    error('No events were imported from the BDF; onset code %d is required.', cfg.onCode);
end

fprintf('Imported channels: %d\n', EEG.nbchan);
fprintf('Sampling rate: %.3f Hz (%.6f ms/sample)\n', EEG.srate, 1000 / EEG.srate);
fprintf('Duration: %.3f s\n', EEG.pnts / EEG.srate);
fprintf('Imported events: %d\n\n', numel(EEG.event));

%% Parse event types
nEvents = numel(EEG.event);
eventCodes = nan(nEvents, 1);
eventRaw = strings(nEvents, 1);
for k = 1:nEvents
    [eventCodes(k), eventRaw(k)] = parseEventCode(EEG.event(k).type);
end

fprintf('Imported trigger inventory:\n');
printTriggerInventoryToFile(1, eventCodes);

codesUsed = eventCodes;
decodeNote = 'Exact imported event codes were used.';
if ~any(codesUsed == cfg.onCode)
    lowByteCodes = nan(size(eventCodes));
    finiteMask = isfinite(eventCodes) & eventCodes >= 0;
    lowByteCodes(finiteMask) = double(bitand(uint32(round(eventCodes(finiteMask))), uint32(255)));
    if any(lowByteCodes == cfg.onCode)
        codesUsed = lowByteCodes;
        decodeNote = sprintf('No exact code %d events were found; lower 8 bits were used.', cfg.onCode);
        warning('%s', decodeNote);
    end
end

onEventIdx = find(codesUsed == cfg.onCode);
if isempty(onEventIdx)
    printUniqueEventTypes(eventCodes, eventRaw);
    error('No trigger %d events were found in EEG.event.', cfg.onCode);
end
nOnsets = numel(onEventIdx);
fprintf('\nTrigger %d onset events found: %d\n', cfg.onCode, nOnsets);
if ~isempty(cfg.expectedOnsets) && nOnsets ~= cfg.expectedOnsets
    warning('Expected %d onset events but found %d.', cfg.expectedOnsets, nOnsets);
end

%% Identify Ergo1 channel
labels = getChannelLabels(EEG);
pdChan = cfg.pdChan;
if isempty(pdChan)
    pdChan = findPhotodiodeChannel(labels, cfg.pdLabel);
    if isempty(pdChan)
        printChannelLabels(labels);
        error(['The Ergo/photodiode channel could not be identified automatically. ' ...
            'Rerun with ''pdChan'', <channel number>. No EXG fallback is used.']);
    end
    channelSelectionNote = sprintf('Auto-selected channel from label match "%s".', labels(pdChan));
else
    channelSelectionNote = 'Photodiode channel was supplied explicitly.';
end
if pdChan < 1 || pdChan > EEG.nbchan
    error('pdChan=%d is outside the imported channel range 1..%d.', pdChan, EEG.nbchan);
end
pdLabelUsed = char(labels(pdChan));
fprintf('Photodiode channel: %d (%s)\n', pdChan, pdLabelUsed);
fprintf('%s\n\n', channelSelectionNote);

%% Detect raw 10/50/90 crossings
sr = double(EEG.srate);
pd = double(EEG.data(pdChan, :));
nPnts = numel(pd);
fractions = cfg.riseFractions;

pulseIndex = (1:nOnsets)';
eventIndex = onEventIdx(:);
triggerSample = nan(nOnsets, 1);
triggerTimeSec = nan(nOnsets, 1);
excluded = ismember(pulseIndex, cfg.excludePulseIndices);
polarity = strings(nOnsets, 1);
baselineLevel = nan(nOnsets, 1);
plateauLevel = nan(nOnsets, 1);
signalDelta = nan(nOnsets, 1);
baselineNoiseMAD = nan(nOnsets, 1);
signalToNoise = nan(nOnsets, 1);

threshold10Level = nan(nOnsets, 1);
threshold50Level = nan(nOnsets, 1);
threshold90Level = nan(nOnsets, 1);
crossing10Sample = nan(nOnsets, 1);
crossing50Sample = nan(nOnsets, 1);
crossing90Sample = nan(nOnsets, 1);
latency10Ms = nan(nOnsets, 1);
latency50Ms = nan(nOnsets, 1);
latency90Ms = nan(nOnsets, 1);
riseTime10to90Ms = nan(nOnsets, 1);
detected10 = false(nOnsets, 1);
detected50 = false(nOnsets, 1);
detected90 = false(nOnsets, 1);
detectedAll = false(nOnsets, 1);
missReason = strings(nOnsets, 1);

for i = 1:nOnsets
    t0 = round(double(EEG.event(onEventIdx(i)).latency));
    triggerSample(i) = t0;
    triggerTimeSec(i) = (t0 - 1) / sr;

    b1 = t0 + round(cfg.baselineWinMs(1) / 1000 * sr);
    b2 = t0 + round(cfg.baselineWinMs(2) / 1000 * sr);
    s1 = t0 + round(cfg.searchWinMs(1) / 1000 * sr);
    s2 = t0 + round(cfg.searchWinMs(2) / 1000 * sr);
    p1 = t0 + round(cfg.plateauWinMs(1) / 1000 * sr);
    p2 = t0 + round(cfg.plateauWinMs(2) / 1000 * sr);

    if b1 < 1 || s1 < 1 || p1 < 1 || b2 > nPnts || s2 > nPnts || p2 > nPnts
        missReason(i) = "window_outside_recording";
        continue;
    end
    if b1 > b2 || s1 > s2 || p1 > p2
        missReason(i) = "invalid_window";
        continue;
    end

    baseSeg = pd(b1:b2);
    plateauSeg = pd(p1:p2);
    searchSeg = pd(s1:s2);  % RAW samples; no filtering or smoothing.

    base = median(baseSeg, 'omitnan');
    plateau = median(plateauSeg, 'omitnan');
    delta = plateau - base;
    noiseMAD = 1.4826 * median(abs(baseSeg - base), 'omitnan');
    snrValue = abs(delta) / max(noiseMAD, eps);

    baselineLevel(i) = base;
    plateauLevel(i) = plateau;
    signalDelta(i) = delta;
    baselineNoiseMAD(i) = noiseMAD;
    signalToNoise(i) = snrValue;

    if ~isfinite(delta) || abs(delta) <= eps
        missReason(i) = "no_black_white_difference";
        continue;
    end
    if ~isfinite(snrValue) || snrValue < cfg.minSignalToNoise
        missReason(i) = "signal_to_noise_below_minimum";
        continue;
    end

    if delta > 0
        polarity(i) = "positive";
    else
        polarity(i) = "negative";
    end

    crossingSamples = nan(1, 3);
    thresholdLevels = base + fractions * delta;

    for f = 1:3
        threshold = thresholdLevels(f);
        if delta > 0
            crossed = searchSeg(:) >= threshold;
        else
            crossed = searchSeg(:) <= threshold;
        end

        kCross = firstConsecutiveRun(crossed, cfg.minRunSamples);
        if isempty(kCross)
            continue;
        end

        onset = s1 + kCross - 1;
        if kCross > 1
            v1 = searchSeg(kCross - 1);
            v2 = searchSeg(kCross);
            if isfinite(v1) && isfinite(v2) && v2 ~= v1
                fracWithinSample = (threshold - v1) / (v2 - v1);
                fracWithinSample = max(0, min(1, fracWithinSample));
                onset = (s1 + kCross - 2) + fracWithinSample;
            end
        end
        crossingSamples(f) = onset;
    end

    threshold10Level(i) = thresholdLevels(1);
    threshold50Level(i) = thresholdLevels(2);
    threshold90Level(i) = thresholdLevels(3);
    crossing10Sample(i) = crossingSamples(1);
    crossing50Sample(i) = crossingSamples(2);
    crossing90Sample(i) = crossingSamples(3);

    detected10(i) = isfinite(crossingSamples(1));
    detected50(i) = isfinite(crossingSamples(2));
    detected90(i) = isfinite(crossingSamples(3));

    if detected10(i)
        latency10Ms(i) = (crossingSamples(1) - t0) / sr * 1000;
    end
    if detected50(i)
        latency50Ms(i) = (crossingSamples(2) - t0) / sr * 1000;
    end
    if detected90(i)
        latency90Ms(i) = (crossingSamples(3) - t0) / sr * 1000;
    end

    detectedAll(i) = detected10(i) && detected50(i) && detected90(i);
    if detectedAll(i)
        riseTime10to90Ms(i) = latency90Ms(i) - latency10Ms(i);
        if latency10Ms(i) <= latency50Ms(i) && latency50Ms(i) <= latency90Ms(i)
            missReason(i) = "ok";
        else
            detectedAll(i) = false;
            missReason(i) = "nonmonotonic_crossings";
        end
    else
        missingParts = strings(0, 1);
        if ~detected10(i), missingParts(end + 1) = "10"; end %#ok<AGROW>
        if ~detected50(i), missingParts(end + 1) = "50"; end %#ok<AGROW>
        if ~detected90(i), missingParts(end + 1) = "90"; end %#ok<AGROW>
        missReason(i) = "missing_" + strjoin(missingParts, "_") + "pct_crossing";
    end
end

useInSummary = detectedAll & ~excluded & isfinite(latency50Ms);
if ~any(useInSummary)
    error('No valid, non-excluded raw 10/50/90 transitions were detected.');
end

%% Summaries and flags
summary10 = calculateSummary(latency10Ms(useInSummary), cfg.frameMs);
summary50 = calculateSummary(latency50Ms(useInSummary), cfg.frameMs);
summary90 = calculateSummary(latency90Ms(useInSummary), cfg.frameMs);
summaryRise = calculateSummary(riseTime10to90Ms(useInSummary), cfg.frameMs);

robustZ50 = nan(nOnsets, 1);
isMADOutlier50 = false(nOnsets, 1);
if isfinite(summary50.robustMADMs) && summary50.robustMADMs > 0
    robustZ50(useInSummary) = ...
        (latency50Ms(useInSummary) - summary50.medianMs) / summary50.robustMADMs;
    isMADOutlier50(useInSummary) = abs(robustZ50(useInSummary)) > 3;
end
frameDeviation50Ms = latency50Ms - summary50.medianMs;
isBeyondHalfFrame50 = detected50 & abs(frameDeviation50Ms) > cfg.frameMs / 2;
isBeyondOneFrame50 = detected50 & abs(frameDeviation50Ms) > cfg.frameMs;

onsetCode = repmat(cfg.onCode, nOnsets, 1);
onsetLabel = repmat(string(cfg.onsetLabel), nOnsets, 1);
resultsTable = table( ...
    pulseIndex, onsetCode, onsetLabel, eventIndex, triggerSample, triggerTimeSec, ...
    crossing10Sample, crossing50Sample, crossing90Sample, ...
    latency10Ms, latency50Ms, latency90Ms, riseTime10to90Ms, ...
    detected10, detected50, detected90, detectedAll, excluded, useInSummary, ...
    polarity, baselineLevel, plateauLevel, signalDelta, ...
    threshold10Level, threshold50Level, threshold90Level, ...
    baselineNoiseMAD, signalToNoise, missReason, ...
    robustZ50, isMADOutlier50, frameDeviation50Ms, ...
    isBeyondHalfFrame50, isBeyondOneFrame50);

%% Print results
fprintf('\nRaw photodiode rise results\n');
fprintf('------------------------------------------------------------\n');
fprintf('Onset marker:               %s (code %d)\n', cfg.onsetLabel, cfg.onCode);
fprintf('Onset triggers found:       %d\n', nOnsets);
fprintf('Complete 10/50/90 rises:    %d\n', sum(detectedAll));
fprintf('Incomplete detections:      %d\n', sum(~detectedAll));
fprintf('Excluded pulse indices:     %s\n', numericListText(cfg.excludePulseIndices));
fprintf('Pulses used in summaries:   %d\n', sum(useInSummary));

printCompactSummary('10% rise latency', summary10);
printCompactSummary('50% rise latency (PRIMARY)', summary50);
printCompactSummary('90% rise latency', summary90);
printCompactSummary('10-90% rise time', summaryRise);

fprintf('\nPrimary 50%% QC:\n');
fprintf('MAD outliers:                %d\n', sum(isMADOutlier50 & useInSummary));
fprintf('> half-frame from median:    %d (half frame = %.3f ms)\n', ...
    sum(isBeyondHalfFrame50 & useInSummary), cfg.frameMs / 2);
fprintf('> one frame from median:     %d (one frame = %.3f ms)\n', ...
    sum(isBeyondOneFrame50 & useInSummary), cfg.frameMs);
if any(~detectedAll)
    fprintf('\nDetection miss reasons:\n');
    printReasonCounts(missReason(~detectedAll));
end

%% Output paths
prefix = fullfile(cfg.outputDir, analysisStem);
paths = struct();
paths.resultsCsv = [prefix '_rawrise_results.csv'];
paths.summaryTxt = [prefix '_rawrise_summary.txt'];
paths.resultsMat = [prefix '_rawrise_analysis.mat'];
paths.examplePng = [prefix '_rawrise_example_traces.png'];
paths.exampleFig = [prefix '_rawrise_example_traces.fig'];
paths.histogramPng = [prefix '_rawrise_50pct_histogram.png'];
paths.histogramFig = [prefix '_rawrise_50pct_histogram.fig'];
paths.stabilityPng = [prefix '_rawrise_latencies_by_pulse.png'];
paths.stabilityFig = [prefix '_rawrise_latencies_by_pulse.fig'];
paths.riseTimePng = [prefix '_rawrise_10to90_by_pulse.png'];
paths.riseTimeFig = [prefix '_rawrise_10to90_by_pulse.fig'];

writetable(resultsTable, paths.resultsCsv);
writeSummaryText(paths.summaryTxt, analysisVersion, cfg, EEG, pdChan, ...
    pdLabelUsed, channelSelectionNote, decodeNote, eventCodes, nOnsets, ...
    resultsTable, summary10, summary50, summary90, summaryRise);

out = struct();
out.analysisVersion = analysisVersion;
out.analysisProfile = cfg.analysisProfile;
out.onCode = cfg.onCode;
out.onsetLabel = cfg.onsetLabel;
out.bdfFile = cfg.bdfFile;
out.pdChan = pdChan;
out.pdLabel = pdLabelUsed;
out.resultsTable = resultsTable;
out.summary10 = summary10;
out.summary50 = summary50;
out.summary90 = summary90;
out.summaryRise10to90 = summaryRise;
out.config = cfg;
out.paths = paths;
out.triggerInventory = buildTriggerInventory(eventCodes);
save(paths.resultsMat, 'out', '-v7.3');

%% QC figures
visibility = 'on';
if ~cfg.showFigures
    visibility = 'off';
end
if cfg.nExampleTraces > 0
    fig1 = plotExampleTraces(pd, triggerSample, baselineLevel, signalDelta, ...
        latency10Ms, latency50Ms, latency90Ms, useInSummary, sr, cfg, visibility);
    saveFigurePair(fig1, paths.examplePng, paths.exampleFig, cfg.saveFigures);
end
fig2 = plotLatencyHistogram(latency50Ms(useInSummary), summary50, cfg, visibility);
saveFigurePair(fig2, paths.histogramPng, paths.histogramFig, cfg.saveFigures);
fig3 = plotLatenciesByPulse(pulseIndex, latency10Ms, latency50Ms, latency90Ms, ...
    useInSummary, excluded, summary50, cfg, visibility);
saveFigurePair(fig3, paths.stabilityPng, paths.stabilityFig, cfg.saveFigures);
fig4 = plotRiseTimeByPulse(pulseIndex, riseTime10to90Ms, useInSummary, ...
    excluded, summaryRise, cfg, visibility);
saveFigurePair(fig4, paths.riseTimePng, paths.riseTimeFig, cfg.saveFigures);

fprintf('\nSaved outputs:\n');
fprintf('  Per-pulse CSV: %s\n', paths.resultsCsv);
fprintf('  Summary text:  %s\n', paths.summaryTxt);
fprintf('  Results MAT:   %s\n', paths.resultsMat);
if cfg.saveFigures
    fprintf('  QC figures:    %s\n', cfg.outputDir);
end
fprintf('\nRaw-rise analysis complete.\n');
end

%% Local functions
function out = runTaskValidationPair(cfg, bdfDir, bdfBase)
% Analyse S1 and S2 independently so their distributions and files cannot mix.
if isempty(strtrim(cfg.outputDir))
    s1Dir = fullfile(bdfDir, [bdfBase '_S1_Code21_PhotodiodeAnalysis_RawRise']);
    s2Dir = fullfile(bdfDir, [bdfBase '_S2_Code23_PhotodiodeAnalysis_RawRise']);
else
    s1Dir = fullfile(cfg.outputDir, 'S1_Code21');
    s2Dir = fullfile(cfg.outputDir, 'S2_Code23');
end

commonArgs = { ...
    'bdfFile', cfg.bdfFile, ...
    'pdChan', cfg.pdChan, ...
    'pdLabel', cfg.pdLabel, ...
    'excludePulseIndices', cfg.excludePulseIndices, ...
    'monitorHz', cfg.monitorHz, ...
    'searchWinMs', cfg.searchWinMs, ...
    'baselineWinMs', cfg.baselineWinMs, ...
    'plateauWinMs', cfg.plateauWinMs, ...
    'riseFractions', cfg.riseFractions, ...
    'minRunSamples', cfg.minRunSamples, ...
    'minSignalToNoise', cfg.minSignalToNoise, ...
    'expectedOnsets', cfg.expectedOnsets, ...
    'saveFigures', cfg.saveFigures, ...
    'showFigures', cfg.showFigures, ...
    'nExampleTraces', cfg.nExampleTraces};

fprintf('\nRunning paired task-validation analysis: S1/code 21, then S2/code 23.\n');
out = struct();
out.analysisVersion = 'RawRise-v3.0';
out.analysisProfile = 'task-validation';
out.bdfFile = cfg.bdfFile;
out.S1 = CB_Photodiode_Ergo1_AnalyseBDF_RawRise(commonArgs{:}, ...
    'analysisProfile', 'task-s1', 'onCode', 21, 'onsetLabel', 'S1', ...
    'outputDir', s1Dir);
out.S2 = CB_Photodiode_Ergo1_AnalyseBDF_RawRise(commonArgs{:}, ...
    'analysisProfile', 'task-s2', 'onCode', 23, 'onsetLabel', 'S2', ...
    'outputDir', s2Dir);
out.comparison = struct( ...
    's1Median50Ms', out.S1.summary50.medianMs, ...
    's2Median50Ms', out.S2.summary50.medianMs, ...
    's2MinusS1Median50Ms', out.S2.summary50.medianMs - out.S1.summary50.medianMs, ...
    's1Sd50Ms', out.S1.summary50.sdMs, ...
    's2Sd50Ms', out.S2.summary50.sdMs);
fprintf('\nPaired task-validation analysis complete.\n');
fprintf('  S1 results: %s\n', out.S1.paths.summaryTxt);
fprintf('  S2 results: %s\n', out.S2.paths.summaryTxt);
fprintf('  S1/S2 median 50%% latency: %.3f / %.3f ms (S2-S1 = %.3f ms)\n', ...
    out.comparison.s1Median50Ms, out.comparison.s2Median50Ms, ...
    out.comparison.s2MinusS1Median50Ms);
end

function inventory = buildTriggerInventory(eventCodes)
finiteCodes = round(eventCodes(isfinite(eventCodes)));
codes = unique(finiteCodes);
counts = arrayfun(@(code) sum(finiteCodes == code), codes);
inventory = table(codes(:), counts(:), 'VariableNames', {'code', 'count'});
end

function printTriggerInventoryToFile(fid, eventCodes)
inventory = buildTriggerInventory(eventCodes);
if isempty(inventory)
    fprintf(fid, '  none\n');
    return;
end
for i = 1:height(inventory)
    fprintf(fid, '  %d: %d\n', inventory.code(i), inventory.count(i));
end
end

function label = sanitizeFileLabel(label)
label = regexprep(char(string(label)), '[^A-Za-z0-9]+', '_');
label = regexprep(label, '^_+|_+$', '');
if isempty(label)
    label = 'Onset';
end
end

function [code, raw] = parseEventCode(t)
raw = string(t);
code = NaN;
if isnumeric(t) && isscalar(t)
    code = double(t);
    return;
end
s = strtrim(char(raw));
codeDirect = str2double(s);
if isfinite(codeDirect)
    code = codeDirect;
    return;
end
tok = regexp(s, '(-?\d+(?:\.\d+)?)', 'tokens');
if ~isempty(tok)
    candidate = str2double(tok{end}{1});
    if isfinite(candidate)
        code = candidate;
    end
end
end

function labels = getChannelLabels(EEG)
labels = strings(EEG.nbchan, 1);
for c = 1:EEG.nbchan
    labels(c) = string(sprintf('ch%d', c));
    if isfield(EEG, 'chanlocs') && numel(EEG.chanlocs) >= c && ...
            isfield(EEG.chanlocs(c), 'labels') && ~isempty(EEG.chanlocs(c).labels)
        labels(c) = string(EEG.chanlocs(c).labels);
    end
end
end

function pdChan = findPhotodiodeChannel(labels, preferredPattern)
pdChan = [];
low = lower(strtrim(labels));
patterns = unique(lower(string({preferredPattern, 'Erg1', 'Ergo1', ...
    'photodiode', 'photo', 'diode'})), 'stable');
for p = 1:numel(patterns)
    if strlength(patterns(p)) == 0
        continue;
    end
    candidates = find(contains(low, patterns(p)));
    if numel(candidates) == 1
        pdChan = candidates;
        return;
    elseif numel(candidates) > 1
        exactCandidate = candidates(strcmpi(strtrim(labels(candidates)), patterns(p)));
        if numel(exactCandidate) == 1
            pdChan = exactCandidate;
            return;
        end
    end
end
end

function printChannelLabels(labels)
fprintf('\nImported channel labels:\n');
for c = 1:numel(labels)
    fprintf('  %3d  %s\n', c, char(labels(c)));
end
end

function printUniqueEventTypes(eventCodes, eventRaw)
fprintf('\nUnique imported event types:\n');
validCodes = unique(eventCodes(isfinite(eventCodes)));
for i = 1:numel(validCodes)
    fprintf('  numeric %g: %d\n', validCodes(i), sum(eventCodes == validCodes(i)));
end
nonNumeric = unique(eventRaw(~isfinite(eventCodes)));
for i = 1:min(numel(nonNumeric), 30)
    fprintf('  text "%s"\n', char(nonNumeric(i)));
end
end

function firstIdx = firstConsecutiveRun(mask, runLength)
mask = logical(mask(:));
firstIdx = [];
if runLength <= 1
    firstIdx = find(mask, 1, 'first');
    return;
end
if numel(mask) < runLength
    return;
end
runCount = conv(double(mask), ones(runLength, 1), 'valid');
firstIdx = find(runCount >= runLength, 1, 'first');
end

function s = calculateSummary(x, frameMs)
x = x(isfinite(x));
s = struct();
s.n = numel(x);
s.meanMs = mean(x);
s.medianMs = median(x);
s.sdMs = std(x);
s.minMs = min(x);
s.maxMs = max(x);
s.iqrMs = percentileLocal(x, 75) - percentileLocal(x, 25);
s.rawMADMs = median(abs(x - s.medianMs));
s.robustMADMs = 1.4826 * s.rawMADMs;
s.p05Ms = percentileLocal(x, 5);
s.p25Ms = percentileLocal(x, 25);
s.p75Ms = percentileLocal(x, 75);
s.p95Ms = percentileLocal(x, 95);
s.frameMs = frameMs;
end

function p = percentileLocal(x, q)
x = sort(x(isfinite(x)));
if isempty(x)
    p = NaN;
    return;
end
if numel(x) == 1
    p = x(1);
    return;
end
pos = 1 + (numel(x) - 1) * q / 100;
lo = floor(pos);
hi = ceil(pos);
if lo == hi
    p = x(lo);
else
    frac = pos - lo;
    p = x(lo) * (1 - frac) + x(hi) * frac;
end
end

function txt = numericListText(x)
if isempty(x)
    txt = 'none';
else
    txt = char(strjoin(string(x), ', '));
end
end

function printReasonCounts(reasons)
[u, ~, idx] = unique(reasons);
for i = 1:numel(u)
    fprintf('  %s: %d\n', char(u(i)), sum(idx == i));
end
end

function printCompactSummary(label, s)
fprintf('\n%s\n', label);
fprintf('  Mean / median:              %.3f / %.3f ms\n', s.meanMs, s.medianMs);
fprintf('  SD / IQR:                   %.3f / %.3f ms\n', s.sdMs, s.iqrMs);
fprintf('  Minimum / maximum:          %.3f / %.3f ms\n', s.minMs, s.maxMs);
fprintf('  5th / 95th percentile:      %.3f / %.3f ms\n', s.p05Ms, s.p95Ms);
end

function writeSummaryText(filename, analysisVersion, cfg, EEG, pdChan, ...
    pdLabel, channelNote, decodeNote, eventCodes, nOnsets, resultsTable, ...
    summary10, summary50, summary90, summaryRise)
fid = fopen(filename, 'w');
if fid < 0
    warning('Could not create summary file: %s', filename);
    return;
end
cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>

fprintf(fid, 'CB Photodiode Ergo1 Raw-Rise BDF Latency Analysis\n');
fprintf(fid, 'Analysis version: %s\n', analysisVersion);
fprintf(fid, 'Generated: %s\n\n', datestr(now, 31));
fprintf(fid, 'BDF: %s\n', cfg.bdfFile);
fprintf(fid, 'Analysis profile: %s\n', cfg.analysisProfile);
fprintf(fid, 'Onset marker: %s (code %d)\n', cfg.onsetLabel, cfg.onCode);
fprintf(fid, 'Analysis source: BDF only; Psychtoolbox timing CSV not used.\n');
fprintf(fid, 'Detector: raw 10%%, 50%%, and 90%% sustained crossings; no smoothing or filtering.\n');
fprintf(fid, 'Sampling rate: %.6f Hz\n', EEG.srate);
fprintf(fid, 'Sample duration: %.6f ms\n', 1000 / EEG.srate);
fprintf(fid, 'Monitor refresh: %.3f Hz (%.6f ms/frame)\n', cfg.monitorHz, cfg.frameMs);
fprintf(fid, 'Photodiode channel: %d (%s)\n', pdChan, pdLabel);
fprintf(fid, 'Channel selection: %s\n', channelNote);
fprintf(fid, 'Event decoding: %s\n\n', decodeNote);

fprintf(fid, 'Trigger inventory\n');
printTriggerInventoryToFile(fid, eventCodes);
fprintf(fid, '%s (code %d) onsets analysed: %d\n', ...
    cfg.onsetLabel, cfg.onCode, nOnsets);
fprintf(fid, 'Excluded pulse indices: %s\n', numericListText(cfg.excludePulseIndices));
fprintf(fid, 'Complete 10/50/90 rises: %d\n', sum(resultsTable.detectedAll));
fprintf(fid, 'Incomplete detections: %d\n', sum(~resultsTable.detectedAll));
fprintf(fid, 'Pulses used in summaries: %d\n\n', sum(resultsTable.useInSummary));

fprintf(fid, 'Detection settings\n');
fprintf(fid, '  Search window: [%.3f %.3f] ms\n', cfg.searchWinMs);
fprintf(fid, '  Baseline window: [%.3f %.3f] ms\n', cfg.baselineWinMs);
fprintf(fid, '  Plateau window: [%.3f %.3f] ms\n', cfg.plateauWinMs);
fprintf(fid, '  Rise fractions: %s\n', mat2str(cfg.riseFractions, 3));
fprintf(fid, '  Smoothing/filtering: none\n');
fprintf(fid, '  Consecutive crossing samples: %d\n', cfg.minRunSamples);
fprintf(fid, '  Minimum signal-to-noise ratio: %.3f\n\n', cfg.minSignalToNoise);

writeOneSummary(fid, '10% rise latency', summary10);
writeOneSummary(fid, '50% rise latency (PRIMARY)', summary50);
writeOneSummary(fid, '90% rise latency', summary90);
writeOneSummary(fid, '10-90% rise time', summaryRise);

fprintf(fid, 'Primary 50%% QC\n');
fprintf(fid, '  MAD outliers: %d\n', ...
    sum(resultsTable.isMADOutlier50 & resultsTable.useInSummary));
fprintf(fid, '  > half-frame from median: %d\n', ...
    sum(resultsTable.isBeyondHalfFrame50 & resultsTable.useInSummary));
fprintf(fid, '  > one frame from median: %d\n', ...
    sum(resultsTable.isBeyondOneFrame50 & resultsTable.useInSummary));
end

function writeOneSummary(fid, label, s)
fprintf(fid, '%s\n', label);
fprintf(fid, '  N: %d\n', s.n);
fprintf(fid, '  Mean: %.6f ms\n', s.meanMs);
fprintf(fid, '  Median: %.6f ms\n', s.medianMs);
fprintf(fid, '  SD: %.6f ms\n', s.sdMs);
fprintf(fid, '  Minimum: %.6f ms\n', s.minMs);
fprintf(fid, '  Maximum: %.6f ms\n', s.maxMs);
fprintf(fid, '  IQR: %.6f ms\n', s.iqrMs);
fprintf(fid, '  Robust MAD: %.6f ms\n', s.robustMADMs);
fprintf(fid, '  5th percentile: %.6f ms\n', s.p05Ms);
fprintf(fid, '  95th percentile: %.6f ms\n\n', s.p95Ms);
end

function fig = plotExampleTraces(pd, triggerSample, baselineLevel, signalDelta, ...
    latency10, latency50, latency90, useInSummary, sr, cfg, visibility)
validIdx = find(useInSummary);
nShow = min(cfg.nExampleTraces, numel(validIdx));
validIdx = validIdx(1:nShow);
fig = figure('Name', 'Raw normalized photodiode example traces', ...
    'Color', 'w', 'Visible', visibility);
hold on;
plotWinMs = [cfg.baselineWinMs(1), max(cfg.searchWinMs(2), 80)];
for j = 1:numel(validIdx)
    i = validIdx(j);
    t0 = triggerSample(i);
    a = max(1, t0 + round(plotWinMs(1) / 1000 * sr));
    b = min(numel(pd), t0 + round(plotWinMs(2) / 1000 * sr));
    normalized = (pd(a:b) - baselineLevel(i)) / signalDelta(i);
    tMs = ((a:b) - t0) / sr * 1000;
    plot(tMs, normalized, 'LineWidth', 0.9);
    xline(latency10(i), ':', 'HandleVisibility', 'off');
    xline(latency50(i), '--', 'HandleVisibility', 'off');
    xline(latency90(i), '-.', 'HandleVisibility', 'off');
end
xline(0, '--', sprintf('%s code %d', cfg.onsetLabel, cfg.onCode), 'LineWidth', 1.2);
yline(0.10, ':', '10%');
yline(0.50, '--', '50%');
yline(0.90, '-.', '90%');
xlabel(sprintf('Time relative to %s code %d (ms)', cfg.onsetLabel, cfg.onCode));
ylabel('Normalized raw photodiode signal (black = 0, white reference = 1)');
title(sprintf('%s raw normalized rises: first %d included onsets (no smoothing)', ...
    cfg.onsetLabel, nShow));
grid on;
hold off;
end

function fig = plotLatencyHistogram(latUse, summary, cfg, visibility)
fig = figure('Name', 'Raw 50% photodiode latency histogram', ...
    'Color', 'w', 'Visible', visibility);
histogram(latUse, max(10, round(sqrt(numel(latUse)))));
hold on;
xline(summary.medianMs, '--', 'Median', 'LineWidth', 1.2);
xline(summary.meanMs, ':', 'Mean', 'LineWidth', 1.2);
xline(summary.medianMs + cfg.frameMs, '-.', '+1 frame');
xline(summary.medianMs - cfg.frameMs, '-.', '-1 frame');
xlabel(sprintf('%s code %d to raw 50%% photodiode crossing (ms)', ...
    cfg.onsetLabel, cfg.onCode));
ylabel('Number of pulses');
title(sprintf('%s raw 50%% rise latency distribution, N = %d', ...
    cfg.onsetLabel, numel(latUse)));
grid on;
hold off;
end

function fig = plotLatenciesByPulse(pulseIndex, latency10, latency50, latency90, ...
    useInSummary, excluded, summary50, cfg, visibility)
fig = figure('Name', 'Raw rise latencies by pulse', 'Color', 'w', 'Visible', visibility);
hold on;
plot(pulseIndex(useInSummary), latency10(useInSummary), 'o-', ...
    'LineWidth', 0.8, 'MarkerSize', 3, 'DisplayName', '10%');
plot(pulseIndex(useInSummary), latency50(useInSummary), 'o-', ...
    'LineWidth', 1.1, 'MarkerSize', 4, 'DisplayName', '50% primary');
plot(pulseIndex(useInSummary), latency90(useInSummary), 'o-', ...
    'LineWidth', 0.8, 'MarkerSize', 3, 'DisplayName', '90%');
if any(excluded & isfinite(latency50))
    plot(pulseIndex(excluded & isfinite(latency50)), latency50(excluded & isfinite(latency50)), ...
        'x', 'LineWidth', 1.5, 'MarkerSize', 8, 'DisplayName', 'Excluded 50%');
end
yline(summary50.medianMs, '--', '50% median', 'HandleVisibility', 'off');
yline(summary50.medianMs + cfg.frameMs, '-.', '50% median + 1 frame', 'HandleVisibility', 'off');
yline(summary50.medianMs - cfg.frameMs, '-.', '50% median - 1 frame', 'HandleVisibility', 'off');
xlabel(sprintf('%s onset index', cfg.onsetLabel));
ylabel(sprintf('%s code %d to raw rise crossing (ms)', cfg.onsetLabel, cfg.onCode));
title(sprintf('Raw 10%%, 50%%, and 90%% %s latencies across the run', cfg.onsetLabel));
legend('Location', 'best');
grid on;
hold off;
end

function fig = plotRiseTimeByPulse(pulseIndex, riseTime, useInSummary, excluded, summaryRise, cfg, visibility)
fig = figure('Name', 'Raw 10-90% rise time by pulse', 'Color', 'w', 'Visible', visibility);
hold on;
plot(pulseIndex(useInSummary), riseTime(useInSummary), 'o-', ...
    'LineWidth', 1.0, 'MarkerSize', 4);
if any(excluded & isfinite(riseTime))
    plot(pulseIndex(excluded & isfinite(riseTime)), riseTime(excluded & isfinite(riseTime)), ...
        'x', 'LineWidth', 1.5, 'MarkerSize', 8);
end
yline(summaryRise.medianMs, '--', 'Median', 'LineWidth', 1.2);
xlabel(sprintf('%s onset index', cfg.onsetLabel));
ylabel('Raw 10-90% rise time (ms)');
title(sprintf('Photodiode 10-90%% rise time across the %s run', cfg.onsetLabel));
grid on;
hold off;
end

function saveFigurePair(fig, pngPath, figPath, saveFigures)
if ~saveFigures || isempty(fig) || ~ishandle(fig)
    return;
end
try
    if exist('exportgraphics', 'file') == 2
        exportgraphics(fig, pngPath, 'Resolution', 180);
    else
        saveas(fig, pngPath);
    end
catch ME
    warning('Could not save PNG %s: %s', pngPath, ME.message);
end
try
    savefig(fig, figPath);
catch ME
    warning('Could not save FIG %s: %s', figPath, ME.message);
end
end
