function report = CB_EEG_RunFullPreprocessingPipeline_ALEX01_v2(varargin)
% ALEX01-only recovery preprocessing pipeline.
% Reconstructs missing main S1 onset markers from recorded ISI-onset code 22
% and behavioural timing, preserving provenance with internal code 221.
% CB_EEG_RunFullPreprocessingPipeline
%
% Full EEG preprocessing + S1/S2 ERP ROI plotting pipeline.
%
% Pipeline:
%   1. Import raw BioSemi BDF
%   2. Downsample to 512 Hz
%   3. QC-check scalp channels with EEGLAB Clean RawData (channel criteria only; flags only)
%   4. Create ICA-training copy: 1-30 Hz + average reference (full scalp montage)
%   5. Run Picard ICA on all scalp channels
%   6. Run ICLabel
%   7. Automatically reject ICLabel Muscle/Eye components (threshold 0.90 default)
%   8. Create ERP-analysis copy: 0.1-20 Hz + average reference (full scalp montage)
%   8b. Optional channel QC persistence on downsampled / ICA / ERP datasets (read-only)
%   9. Transfer ICA weights to ERP-analysis copy and remove selected components
%  10. Match EEG triggers to behavioural FullRun CSV
%  11. Add synthetic S1/S2 outcome-specific event codes
%  12. Create S1-locked and S2-locked epochs
%  13. Apply S1 baseline to both S1 and S2 epochs
%  14. Run joint automated artefact rejection
%  15. Plot S1/S2 Blind/Sensing/Seeing ROI ERPs
%  16. Optional extra central ROI trial traces, B/S/S overlay, and S2 VAN/LP topomaps
%
% Main assumptions:
%   - BioSemi file has 72 channels total
%   - Channels 1:64 = scalp EEG
%   - Channels 65:72 = EXG channels
%   - ALEX01 recovery note: localisation triggers 51-54 were only partially
%     captured. They are audited where present, while behavioural CSV values
%     remain the source of localisation response/correctness for classification.
%   - Synthetic codes:
%       S1: 201 Blind, 202 Sensing, 203 Seeing, 211 CR, 212 FA
%       S2: 301 Blind, 302 Sensing, 303 Seeing, 311 CR, 312 FA
%
% Example:
%   report = CB_EEG_RunFullPreprocessingPipeline_ALEX01();
%
% Optional explicit filenames:
%   report = CB_EEG_RunFullPreprocessingPipeline_ALEX01( ...
%       'BdfFile', 'ALEX01.bdf', ...
%       'FullRunCsv', 'CB_4xGratings_ALEX01_FullRun_YYYYMMDD_HHMMSS.csv');
%
% Notes:
%   - Before ICA, scalp channels are QC-checked with EEGLAB Clean RawData
%     channel defaults: flatline > 5 s, line noise > 4 SD, correlation < 0.80.
%     Only scalp channels are screened on a temporary copy; ASR burst/window
%     rejection is disabled. Potentially bad channels are flagged to CSV for
%     manual review. No channels are removed or interpolated; ICA and ERP
%     preprocessing retain the full scalp montage. Verbose Clean RawData
%     progress is suppressed by default during diagnostic passes; use
%     'SuppressCleanRawDataConsole', false for full console output. Captured
%     verbose trace is saved when 'SaveCleanRawDataConsoleLog', true (default).
%   - Optional read-only 50 Hz line-noise QC runs on downsampled, ICA-training,
%     and ERP-analysis datasets. Results are saved to CSV and optional plots.
%     This does not apply notch filtering or channel removal.
%   - Optional read-only channel QC persistence reruns Clean RawData diagnostic
%     checks on temporary scalp copies after downsampling, ICA-training, and
%     ERP-analysis filtering. Compares against Stage 3b initial flags to show
%     which warnings persist. Complements line-noise PSD QC; no channels removed.
%   - ALEX01 recovery event handling uses the 600 surviving code-22 ISI
%     onset markers as trial anchors. Main S1 onset is reconstructed trial by
%     trial from behavioural timing and inserted with explicit provenance code
%     221. Recorded S2=23, gap=24, Q1=31, PAS=41-44, LOC=51-54.
%   - The original hardware event stream is retained. Reconstructed S1 timing
%     is clearly labelled in event metadata, audit CSVs, dataset names, and
%     the final recovery report.
% - Optional Stage 16 extra plots (central ROI trial traces, B/S/S overlay,
%     S2 VAN/LP topomaps) run on AR-clean S1/S2 datasets when plot functions
%     are on the MATLAB path. Figures are shown by default; use
%     'ExtraPlotVisible', false for silent/batch runs. Disable entirely with
%     'RunExtraFinalPlots', false.
%   - By default, automatically rejects ICLabel Muscle/Eye components with
%     probability >= 0.90. Enable manual review with 'ManualICAReject', true.
%     Change threshold with 'AutoICARejectThreshold', 0.90.
%   - Positive amplitudes are plotted above zero.
%   - The script writes both a text diary log and a structured CSV log.

% ========================================================================
% Parse inputs and config
% ========================================================================

participantID = 'ALEX01';
dataPath = 'C:\Users\hrl310\Documents\EEGData_HL\ALEX01';

if ~strcmp(dataPath(end), filesep)
    dataPath = [dataPath filesep];
end

defaultBdfFile = 'ALEX01.bdf';
defaultFullRunPattern = 'CB_4xGratings_ALEX01_FullRun_*.csv';
defaultOutputRoot = dataPath;

isText = @(x) ischar(x) || isstring(x);

p = inputParser;
addParameter(p, 'BdfFile', defaultBdfFile, isText);
addParameter(p, 'FullRunCsv', '', isText);
addParameter(p, 'FullRunPattern', defaultFullRunPattern, isText);
addParameter(p, 'OutputRoot', defaultOutputRoot, isText);

% ALEX01 recovery configuration
addParameter(p, 'RecordedISIAnchorCode', 22, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'RecordedS2Code', 23, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'RecordedGapCode', 24, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'RecordedQ1Code', 31, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'RecordedPASCodes', 41:44, @(x) isnumeric(x) && isvector(x));
addParameter(p, 'RecordedLocCodes', 51:54, @(x) isnumeric(x) && isvector(x));
addParameter(p, 'ReconstructedS1Code', 221, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'DisplayRefreshHz', 120, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'RecoveryTimingToleranceMs', 5, @(x) isnumeric(x) && isscalar(x) && x >= 0);

% Core config
addParameter(p, 'NScalpChans', 64, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'ExternalChans', 65:72, @(x) isnumeric(x) && isvector(x));
addParameter(p, 'TargetSrate', 512, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'ICAFilterHz', [1 30], @(x) isnumeric(x) && numel(x)==2);
addParameter(p, 'ERPFilterHz', [0.1 20], @(x) isnumeric(x) && numel(x)==2);
addParameter(p, 'ICAType', 'picard', isText);
addParameter(p, 'ICAPcaDim', 63, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'ICAMaxIter', 500, @(x) isnumeric(x) && isscalar(x));

% Bad scalp-channel QC checker using EEGLAB Clean RawData
addParameter(p, 'RunBadChannelChecker', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'BadChannelCheckerFlatlineCriterion', 5, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'BadChannelCheckerLineNoiseCriterion', 4, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'BadChannelCheckerCorrelationCriterion', 0.80, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 1);

addParameter(p, 'SuppressCleanRawDataConsole', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'SaveCleanRawDataConsoleLog', true, @(x) islogical(x) || isnumeric(x));

% Channel QC persistence (read-only; reruns Clean RawData diagnostics after filtering)
addParameter(p, 'RunChannelQCPersistence', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'ChannelQCPersistencePlot', true, @(x) islogical(x) || isnumeric(x));

% Line-noise QC (read-only measurement; no filtering)
addParameter(p, 'RunLineNoiseQC', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'LineNoiseFreqHz', 50, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'LineNoiseNeighbourHz', [45 55], @(x) isnumeric(x) && numel(x) == 2 && x(1) < x(2));
addParameter(p, 'LineNoiseExcludeHz', [49 51], @(x) isnumeric(x) && numel(x) == 2 && x(1) < x(2));
addParameter(p, 'LineNoiseQCPlot', true, @(x) islogical(x) || isnumeric(x));

% Trial/event config for CB_4xGratings_v3 (ascending within-trial trigger codes)
% Main: 11->21->22->23->24->31->41-44->51->61-64->71; practice + PracticeTriggerOffset.
% Behavioural metadata (block, track, duration, outcomeBin) comes from FullRun CSV only.
% NTriggeredPractice is kept as a legacy alias only; it is no longer used to
% positionally skip trials before behavioural matching.
addParameter(p, 'NTriggeredPractice', 20, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'ExpectedPracticeBlocks', 2, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'ExpectedPracticeTrialsPerBlock', 10, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'ExpectedPracticeTrials', 20, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'ExpectedMainBlocks', 12, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'ExpectedMainTrialsPerBlock', 50, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'ExpectedMainTrials', 600, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'PracticeTriggerOffset', 100, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'MainS1Code', 21, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'MainS2Code', 23, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'MainPASBase', 40, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'MainQ1Code', 31, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'MainQ2Code', 51, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'MainLocBase', 60, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'MainTrialEndCode', 71, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'ValidatePracticeTriggers', true, @(x) islogical(x) || isnumeric(x));

% Epoching/baseline
addParameter(p, 'S1EpochWinSec', [-0.200 1.400], @(x) isnumeric(x) && numel(x)==2);
addParameter(p, 'S2EpochWinSec', [-0.900 0.800], @(x) isnumeric(x) && numel(x)==2);
addParameter(p, 'S1BaselineMs', [-199 0], @(x) isnumeric(x) && numel(x)==2);

% Artefact rejection
addParameter(p, 'ArtifactAbsThresholdUv', 100, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'ArtifactPeakToPeakThresholdUv', 150, @(x) isnumeric(x) && isscalar(x));

% Manual / automatic ICA
addParameter(p, 'AutoICAReject', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'AutoICARejectThreshold', 0.90, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 1);
addParameter(p, 'AutoICARejectClasses', {'Muscle','Eye'}, @(x) iscellstr(x) || isstring(x) || ischar(x));
addParameter(p, 'ManualICAReject', false, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'ComponentsToRemove', [], @(x) isnumeric(x));

% Plotting
addParameter(p, 'VisiblePlots', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'NegativeUp', false, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'SaveFig', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'SavePng', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'SaveCsv', true, @(x) islogical(x) || isnumeric(x));

% Extra final ERP / topomap plotting (after ROI plots; optional)
addParameter(p, 'RunExtraFinalPlots', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'ExtraPlotVisible', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'ExtraPlotSavePng', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'ExtraPlotSaveFig', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'ExtraPlotSaveCsv', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'ExtraPlotCentralChannels', {'Cz','CPz','Pz'}, @(x) iscellstr(x) || isstring(x));
addParameter(p, 'ExtraPlotVANWindowMs', [150 250], @(x) isnumeric(x) && numel(x) == 2);
addParameter(p, 'ExtraPlotLPWindowMs', [400 600], @(x) isnumeric(x) && numel(x) == 2);

% Behaviour variable overrides
addParameter(p, 'PASVar', '', isText);
addParameter(p, 'LocCorrectVar', '', isText);
addParameter(p, 'LocRespVar', '', isText);
addParameter(p, 'IsChangeVar', '', isText);

% Safety/restart
addParameter(p, 'Overwrite', true, @(x) islogical(x) || isnumeric(x));

parse(p, varargin{:});
cfg = p.Results;

cfg.BdfFile = char(cfg.BdfFile);
cfg.FullRunCsv = char(cfg.FullRunCsv);
cfg.FullRunPattern = char(cfg.FullRunPattern);
cfg.OutputRoot = char(cfg.OutputRoot);
cfg.ICAType = char(cfg.ICAType);

cfg.ScalpChans = 1:cfg.NScalpChans;
cfg.NExternalChans = numel(cfg.ExternalChans);
cfg.TotalExpectedChans = cfg.NScalpChans + cfg.NExternalChans;

cfg.NTriggeredPractice = double(cfg.NTriggeredPractice);
cfg.ExpectedPracticeBlocks = double(cfg.ExpectedPracticeBlocks);
cfg.ExpectedPracticeTrialsPerBlock = double(cfg.ExpectedPracticeTrialsPerBlock);
cfg.ExpectedPracticeTrials = double(cfg.ExpectedPracticeTrials);
cfg.ExpectedMainBlocks = double(cfg.ExpectedMainBlocks);
cfg.ExpectedMainTrialsPerBlock = double(cfg.ExpectedMainTrialsPerBlock);
cfg.ExpectedMainTrials = double(cfg.ExpectedMainTrials);
cfg.PracticeTriggerOffset = double(cfg.PracticeTriggerOffset);
cfg.MainS1Code = double(cfg.MainS1Code);
cfg.MainS2Code = double(cfg.MainS2Code);
cfg.MainPASBase = double(cfg.MainPASBase);
cfg.MainQ1Code = double(cfg.MainQ1Code);
cfg.MainQ2Code = double(cfg.MainQ2Code);
cfg.MainLocBase = double(cfg.MainLocBase);
cfg.MainTrialEndCode = double(cfg.MainTrialEndCode);
cfg.ValidatePracticeTriggers = logical(cfg.ValidatePracticeTriggers);

expectedPracticeFromBlocks = cfg.ExpectedPracticeBlocks * cfg.ExpectedPracticeTrialsPerBlock;
if cfg.ExpectedPracticeTrials ~= expectedPracticeFromBlocks
    error('ExpectedPracticeTrials=%d does not match ExpectedPracticeBlocks x ExpectedPracticeTrialsPerBlock = %d.', ...
        cfg.ExpectedPracticeTrials, expectedPracticeFromBlocks);
end

expectedMainFromBlocks = cfg.ExpectedMainBlocks * cfg.ExpectedMainTrialsPerBlock;
if cfg.ExpectedMainTrials ~= expectedMainFromBlocks
    error('ExpectedMainTrials=%d does not match ExpectedMainBlocks x ExpectedMainTrialsPerBlock = %d.', ...
        cfg.ExpectedMainTrials, expectedMainFromBlocks);
end

if cfg.NTriggeredPractice ~= cfg.ExpectedPracticeTrials
    warning(['NTriggeredPractice is a legacy alias only and is no longer used for positional skipping. ', ...
        'Using ExpectedPracticeTrials=%d for +100-family practice-trigger validation.'], cfg.ExpectedPracticeTrials);
end

cfg.ManualICAReject = logical(cfg.ManualICAReject);
cfg.AutoICAReject = logical(cfg.AutoICAReject);
cfg.AutoICARejectThreshold = double(cfg.AutoICARejectThreshold);

if ischar(cfg.AutoICARejectClasses)
    cfg.AutoICARejectClasses = {cfg.AutoICARejectClasses};
elseif isstring(cfg.AutoICARejectClasses)
    cfg.AutoICARejectClasses = cellstr(cfg.AutoICARejectClasses);
else
    cfg.AutoICARejectClasses = cellfun(@char, cfg.AutoICARejectClasses, 'UniformOutput', false);
end

cfg.RunBadChannelChecker = logical(cfg.RunBadChannelChecker);
cfg.BadChannelCheckerFlatlineCriterion = double(cfg.BadChannelCheckerFlatlineCriterion);
cfg.BadChannelCheckerLineNoiseCriterion = double(cfg.BadChannelCheckerLineNoiseCriterion);
cfg.BadChannelCheckerCorrelationCriterion = double(cfg.BadChannelCheckerCorrelationCriterion);

cfg.SuppressCleanRawDataConsole = logical(cfg.SuppressCleanRawDataConsole);
cfg.SaveCleanRawDataConsoleLog = logical(cfg.SaveCleanRawDataConsoleLog);

cfg.RunChannelQCPersistence = logical(cfg.RunChannelQCPersistence);
cfg.ChannelQCPersistencePlot = logical(cfg.ChannelQCPersistencePlot);

cfg.RunLineNoiseQC = logical(cfg.RunLineNoiseQC);
cfg.LineNoiseFreqHz = double(cfg.LineNoiseFreqHz);
cfg.LineNoiseNeighbourHz = double(cfg.LineNoiseNeighbourHz);
cfg.LineNoiseExcludeHz = double(cfg.LineNoiseExcludeHz);
cfg.LineNoiseQCPlot = logical(cfg.LineNoiseQCPlot);

cfg.RunExtraFinalPlots = logical(cfg.RunExtraFinalPlots);
cfg.ExtraPlotVisible = logical(cfg.ExtraPlotVisible);
cfg.ExtraPlotSavePng = logical(cfg.ExtraPlotSavePng);
cfg.ExtraPlotSaveFig = logical(cfg.ExtraPlotSaveFig);
cfg.ExtraPlotSaveCsv = logical(cfg.ExtraPlotSaveCsv);
if isstring(cfg.ExtraPlotCentralChannels)
    cfg.ExtraPlotCentralChannels = cellstr(cfg.ExtraPlotCentralChannels);
elseif ischar(cfg.ExtraPlotCentralChannels)
    cfg.ExtraPlotCentralChannels = {cfg.ExtraPlotCentralChannels};
elseif iscell(cfg.ExtraPlotCentralChannels)
    cfg.ExtraPlotCentralChannels = cellfun(@char, cfg.ExtraPlotCentralChannels, 'UniformOutput', false);
end
cfg.ExtraPlotVANWindowMs = double(cfg.ExtraPlotVANWindowMs);
cfg.ExtraPlotLPWindowMs = double(cfg.ExtraPlotLPWindowMs);

cfg.VisiblePlots = logical(cfg.VisiblePlots);
cfg.NegativeUp = logical(cfg.NegativeUp);
cfg.SaveFig = logical(cfg.SaveFig);
cfg.SavePng = logical(cfg.SavePng);
cfg.SaveCsv = logical(cfg.SaveCsv);
cfg.Overwrite = logical(cfg.Overwrite);

if ~strcmp(cfg.OutputRoot(end), filesep)
cfg.OutputRoot = [cfg.OutputRoot filesep];
end

% ========================================================================
% Output folders and logging
% ========================================================================

runStamp = datestr(now, 'yyyymmdd_HHMMSS');

outDir = fullfile(cfg.OutputRoot, sprintf('%s_RecoveryPreproc_%s', participantID, runStamp));
if ~exist(outDir, 'dir')
mkdir(outDir);
end

plotDir = fullfile(outDir, sprintf('%s_ERP_ROI_Plots', participantID));
if ~exist(plotDir, 'dir')
mkdir(plotDir);
end

lineNoiseQCTables = {};
lineNoisePlotDir = '';
lineNoiseQCTableCsv = '';
lineNoiseQCSummaryCsv = '';
lineNoiseQCStatus = 'SKIPPED';
if cfg.RunLineNoiseQC
    lineNoiseQCTableCsv = fullfile(outDir, sprintf('%s_LineNoiseQC_Table.csv', participantID));
    lineNoiseQCSummaryCsv = fullfile(outDir, sprintf('%s_LineNoiseQC_Summary.csv', participantID));
end

channelQCPersistenceTableCsv = '';
channelQCPersistenceSummaryCsv = '';
channelQCPersistenceInterpretationCsv = '';
channelQCPlotDir = '';

cleanRawDataConsoleLogFile = '';
if cfg.SaveCleanRawDataConsoleLog
    cleanRawDataConsoleLogFile = fullfile(outDir, ...
        sprintf('%s_CleanRawDataDiagnosticConsoleLog.txt', participantID));
end
cfg.CleanRawDataConsoleLogFile = cleanRawDataConsoleLogFile;

logTxtFile = fullfile(outDir, sprintf('%s_PreprocessingLog_%s.txt', participantID, runStamp));
logCsvFile = fullfile(outDir, sprintf('%s_PreprocessingLog_%s.csv', participantID, runStamp));

logRows = table( ...
strings(0,1), strings(0,1), strings(0,1), strings(0,1), strings(0,1), strings(0,1), ...
'VariableNames', {'Timestamp','Stage','Status','Message','Value','File'});

diary(logTxtFile);
diary on;

fprintf('\n============================================================\n');
fprintf('CB EEG ALEX01 RECOVERY PREPROCESSING PIPELINE\n');
fprintf('Participant: %s\n', participantID);
fprintf('Started: %s\n', datestr(now));
fprintf('Output folder:\n%s\n', outDir);
fprintf('============================================================\n\n');

logStep('pipeline', 'START', 'Pipeline started', participantID, outDir);

try


% ====================================================================
% Stage 1: Resolve input files
% ====================================================================

bdfPath = cfg.BdfFile;
if exist(bdfPath, 'file') ~= 2
    bdfPath = fullfile(dataPath, cfg.BdfFile);
end
if exist(bdfPath, 'file') ~= 2
    error('BDF file not found: %s', cfg.BdfFile);
end

fullRunCsv = cfg.FullRunCsv;
if isempty(fullRunCsv)
    csvFiles = dir(fullfile(dataPath, cfg.FullRunPattern));
    if isempty(csvFiles)
        error('No behavioural FullRun CSV found using pattern: %s', fullfile(dataPath, cfg.FullRunPattern));
    end
    [~, newestIdx] = max([csvFiles.datenum]);
    fullRunCsv = fullfile(csvFiles(newestIdx).folder, csvFiles(newestIdx).name);
else
    if exist(fullRunCsv, 'file') ~= 2
        fullRunCsv = fullfile(dataPath, fullRunCsv);
    end
    if exist(fullRunCsv, 'file') ~= 2
        error('Behavioural FullRun CSV not found: %s', cfg.FullRunCsv);
    end
end

logStep('input', 'OK', 'Resolved BDF file', '', bdfPath);
logStep('input', 'OK', 'Resolved FullRun CSV', '', fullRunCsv);

% ====================================================================
% Stage 2: Import raw BDF
% ====================================================================

fprintf('\n\n================ STAGE 2: RAW BDF IMPORT ================\n');

EEG_raw = pop_biosig(bdfPath);
EEG_raw.setname = sprintf('%s_raw', participantID);
EEG_raw = eeg_checkset(EEG_raw);

fprintf('Raw channels: %d\n', EEG_raw.nbchan);
fprintf('Raw points:   %d\n', EEG_raw.pnts);
fprintf('Raw srate:    %.1f Hz\n', EEG_raw.srate);

if EEG_raw.nbchan ~= cfg.TotalExpectedChans
    error('Expected %d channels but loaded %d channels.', cfg.TotalExpectedChans, EEG_raw.nbchan);
end

rawSet = sprintf('%s_raw.set', participantID);
EEG_raw = pop_saveset(EEG_raw, 'filename', rawSet, 'filepath', outDir);

logStep('raw_import', 'OK', 'Imported raw BDF', sprintf('%d channels', EEG_raw.nbchan), rawSet);

% ====================================================================
% Stage 3: Downsample
% ====================================================================

fprintf('\n\n================ STAGE 3: DOWNSAMPLE ================\n');

EEG_ds = pop_resample(EEG_raw, cfg.TargetSrate);
EEG_ds.setname = sprintf('%s_ds%d', participantID, cfg.TargetSrate);
EEG_ds = eeg_checkset(EEG_ds);

dsSet = sprintf('%s_ds%d.set', participantID, cfg.TargetSrate);
EEG_ds = pop_saveset(EEG_ds, 'filename', dsSet, 'filepath', outDir);

fprintf('Downsampled to %.1f Hz\n', EEG_ds.srate);
logStep('downsample', 'OK', 'Downsampled continuous data', sprintf('%.1f Hz', EEG_ds.srate), dsSet);

EEG_ds = localFixChanlocsForICLabel(EEG_ds);
EEG_ds = eeg_checkset(EEG_ds);

originalAllChanlocs = EEG_ds.chanlocs;
originalScalpChanlocs = EEG_ds.chanlocs(1:cfg.NScalpChans);
originalScalpLabels = string({originalScalpChanlocs.labels});
originalScalpLabels = originalScalpLabels(:);
originalExternalChanlocs = EEG_ds.chanlocs(cfg.ExternalChans);
originalExternalLabels = string({originalExternalChanlocs.labels});
originalExternalLabels = originalExternalLabels(:);

% ====================================================================
% Stage 3b: Bad scalp-channel QC check with Clean RawData
% ====================================================================

fprintf('\n\n================ STAGE 3b: BAD SCALP-CHANNEL QC CHECK ================\n');

[flaggedBadScalpLabels, flaggedBadScalpIndices, ...
    flaggedFlatlineLabels, flaggedFlatlineIndices, ...
    flaggedLineNoiseLabels, flaggedLineNoiseIndices, ...
    flaggedCorrelationLabels, flaggedCorrelationIndices, ...
    badChannelCheckTableCsv, badChannelCheckSummaryCsv, badChannelTable] = ...
    localCheckBadScalpChannelsCleanRawData(EEG_ds, cfg, participantID, originalScalpLabels, originalScalpChanlocs, outDir);

if cfg.RunBadChannelChecker
    logStep('bad_channel_check', 'OK', ...
        'Bad scalp-channel QC check completed; no channels removed', ...
        strjoin(flaggedBadScalpLabels, ', '), badChannelCheckTableCsv);
else
    logStep('bad_channel_check', 'SKIP', ...
        'Bad scalp-channel QC check disabled; no channels removed', '', badChannelCheckSummaryCsv);
end

if cfg.RunLineNoiseQC
    try
        [tmpLineNoiseTable, lineNoisePlotDir, lineNoiseQCSummaryStr] = localComputeLineNoiseQC( ...
            EEG_ds, cfg, participantID, 'Downsampled_512Hz', ...
            originalScalpLabels, flaggedBadScalpLabels, flaggedLineNoiseLabels, ...
            outDir, lineNoisePlotDir);
        lineNoiseQCTables{end+1} = tmpLineNoiseTable;
        logStep('line_noise_qc', 'OK', ...
            'Line-noise QC completed for Downsampled_512Hz', ...
            lineNoiseQCSummaryStr, '');
    catch ME
        logStep('line_noise_qc', 'WARN', ...
            'Line-noise QC failed for Downsampled_512Hz', ...
            ME.message, '');
    end
else
    logStep('line_noise_qc', 'SKIP', 'Line-noise QC disabled', '', '');
end

% ====================================================================
% Stage 4: Create ICA-training dataset
% ====================================================================

fprintf('\n\n================ STAGE 4: ICA-TRAINING DATASET ================\n');

EEG_ica = EEG_ds;

EEG_ica = pop_eegfiltnew(EEG_ica, ...
    'locutoff', cfg.ICAFilterHz(1), ...
    'hicutoff', cfg.ICAFilterHz(2), ...
    'plotfreqz', 0);

EEG_ica.setname = sprintf('%s_ds%d_bp%dto%d', ...
    participantID, cfg.TargetSrate, cfg.ICAFilterHz(1), cfg.ICAFilterHz(2));

externalIdxIca = localFindExistingChannelsByLabels(EEG_ica, originalExternalLabels);
EEG_ica = pop_reref(EEG_ica, [], 'exclude', externalIdxIca);
EEG_ica.setname = sprintf('%s_ds%d_bp%dto%d_avgref_ICAtraining', ...
    participantID, cfg.TargetSrate, cfg.ICAFilterHz(1), cfg.ICAFilterHz(2));

EEG_ica = localFixChanlocsForICLabel(EEG_ica);
EEG_ica = eeg_checkset(EEG_ica);

icaScalpChanIdx = cfg.ScalpChans;
nIcaChansUsed = numel(icaScalpChanIdx);
icaPcaDimUsed = cfg.ICAPcaDim;
if icaPcaDimUsed > nIcaChansUsed - 1
    error('ICAPcaDim=%d is too high for %d scalp channels after average reference.', ...
        icaPcaDimUsed, nIcaChansUsed);
end

icaTrainingSet = sprintf('%s_ds%d_bp%dto%d_avgref_ICAtraining.set', ...
    participantID, cfg.TargetSrate, cfg.ICAFilterHz(1), cfg.ICAFilterHz(2));

EEG_ica = pop_saveset(EEG_ica, 'filename', icaTrainingSet, 'filepath', outDir);

logStep('ica_training_dataset', 'OK', 'Created 1-30 Hz average-referenced ICA-training dataset', '', icaTrainingSet);

if cfg.RunLineNoiseQC
    try
        [tmpLineNoiseTable, lineNoisePlotDir, lineNoiseQCSummaryStr] = localComputeLineNoiseQC( ...
            EEG_ica, cfg, participantID, 'ICAtraining_1to30Hz', ...
            originalScalpLabels, flaggedBadScalpLabels, flaggedLineNoiseLabels, ...
            outDir, lineNoisePlotDir);
        lineNoiseQCTables{end+1} = tmpLineNoiseTable;
        logStep('line_noise_qc', 'OK', ...
            'Line-noise QC completed for ICAtraining_1to30Hz', ...
            lineNoiseQCSummaryStr, '');
    catch ME
        logStep('line_noise_qc', 'WARN', ...
            'Line-noise QC failed for ICAtraining_1to30Hz', ...
            ME.message, '');
    end
end

% ====================================================================
% Stage 5: Picard ICA
% ====================================================================

fprintf('\n\n================ STAGE 5: PICARD ICA ================\n');

EEG_ica.icaact = [];
EEG_ica.icawinv = [];
EEG_ica.icasphere = [];
EEG_ica.icaweights = [];
EEG_ica.icachansind = [];

fprintf('Running %s ICA on %d scalp channels with PCA %d...\n', ...
    cfg.ICAType, nIcaChansUsed, icaPcaDimUsed);

tic;
EEG_ica = pop_runica(EEG_ica, ...
    'icatype', cfg.ICAType, ...
    'chanind', icaScalpChanIdx, ...
    'pca', icaPcaDimUsed, ...
    'maxiter', cfg.ICAMaxIter, ...
    'mode', 'standard');
icaElapsedSec = toc;

EEG_ica = eeg_checkset(EEG_ica);

fprintf('\nICA finished in %.2f minutes.\n', icaElapsedSec/60);
fprintf('icaweights size: [%d x %d]\n', size(EEG_ica.icaweights,1), size(EEG_ica.icaweights,2));
fprintf('icawinv size:    [%d x %d]\n', size(EEG_ica.icawinv,1), size(EEG_ica.icawinv,2));
fprintf('icachansind:     %d channels\n', numel(EEG_ica.icachansind));

if size(EEG_ica.icaweights,1) ~= icaPcaDimUsed || ...
        size(EEG_ica.icaweights,2) ~= nIcaChansUsed || ...
        size(EEG_ica.icawinv,1) ~= nIcaChansUsed || ...
        size(EEG_ica.icawinv,2) ~= icaPcaDimUsed
    error('ICA dimensions are not as expected. Expected weights [%d x %d] and icawinv [%d x %d].', ...
        icaPcaDimUsed, nIcaChansUsed, nIcaChansUsed, icaPcaDimUsed);
end

picardSet = sprintf('%s_ds%d_bp%dto%d_avgref_PicardICA_pca%d.set', ...
    participantID, cfg.TargetSrate, cfg.ICAFilterHz(1), cfg.ICAFilterHz(2), icaPcaDimUsed);

EEG_ica.setname = erase(picardSet, '.set');
EEG_ica = pop_saveset(EEG_ica, 'filename', picardSet, 'filepath', outDir);

logStep('picard_ica', 'OK', 'Picard ICA completed', sprintf('%.2f min', icaElapsedSec/60), picardSet);
logStep('picard_ica', 'OK', 'ICA dimensions', sprintf('weights %dx%d; icawinv %dx%d', ...
    size(EEG_ica.icaweights,1), size(EEG_ica.icaweights,2), size(EEG_ica.icawinv,1), size(EEG_ica.icawinv,2)), picardSet);

% ====================================================================
% Stage 6: ICLabel
% ====================================================================

fprintf('\n\n================ STAGE 6: ICLABEL ================\n');

EEG_ica = localFixChanlocsForICLabel(EEG_ica);
EEG_ica = eeg_checkset(EEG_ica);

EEG_ica = pop_iclabel(EEG_ica, 'default');
EEG_ica = eeg_checkset(EEG_ica);

iclabelSet = sprintf('%s_ds%d_bp%dto%d_avgref_PicardICA_pca%d_ICLabel.set', ...
    participantID, cfg.TargetSrate, cfg.ICAFilterHz(1), cfg.ICAFilterHz(2), icaPcaDimUsed);

EEG_ica.setname = erase(iclabelSet, '.set');
EEG_ica = pop_saveset(EEG_ica, 'filename', iclabelSet, 'filepath', outDir);

T_ic = localMakeICLabelTable(EEG_ica);
iclabelCsv = fullfile(outDir, sprintf('%s_ICLabel_Table.csv', participantID));
writetable(T_ic, iclabelCsv);

fprintf('\nFirst 25 ICLabel classifications:\n');
disp(T_ic(1:min(25,height(T_ic)),:));

logStep('iclabel', 'OK', 'ICLabel completed', sprintf('%d ICs', height(T_ic)), iclabelSet);
logStep('iclabel', 'OK', 'Saved ICLabel table', '', iclabelCsv);

% ====================================================================
% Stage 7: ICA component selection
% ====================================================================

fprintf('\n\n================ STAGE 7: ICA COMPONENT SELECTION ================\n');

autoComponents = [];
autoSelectionTable = table();
autoSelectionCsv = '';

if cfg.AutoICAReject
    [autoComponents, autoSelectionTable] = localGetICLabelAutoRejectComponents( ...
        EEG_ica, cfg.AutoICARejectClasses, cfg.AutoICARejectThreshold);
    autoSelectionCsv = fullfile(outDir, sprintf('%s_AutoICASelectionTable.csv', participantID));
    writetable(autoSelectionTable, autoSelectionCsv);
    logStep('ica_component_selection', 'OK', 'Auto ICA selection table saved', mat2str(autoComponents), autoSelectionCsv);
end

providedComponents = cfg.ComponentsToRemove(:)';
manualComponents = [];

if cfg.ManualICAReject
    fprintf('\nOpening component viewer for ICs 1:%d.\n', min(35, size(EEG_ica.icaweights,1)));
    fprintf('Inspect maps, time courses, and ICLabel classifications.\n\n');

    try
        pop_selectcomps(EEG_ica, 1:min(35, size(EEG_ica.icaweights,1)));
    catch ME
        warning('Could not open pop_selectcomps: %s', ME.message);
    end

    fprintf('\nAutomatically selected ICs:\n');
    disp(autoComponents);

    additionalManualComponents = input('Enter any additional ICs to remove, e.g. [1 2 3], or [] for none: ');
    manualComponents = additionalManualComponents(:)';
end

componentsToRemove = unique([autoComponents(:); providedComponents(:); manualComponents(:)])';

if any(componentsToRemove < 1) || any(componentsToRemove > size(EEG_ica.icaweights,1))
    error('ComponentsToRemove contains invalid component indices.');
end

componentDecisionTable = table( ...
    string(participantID), ...
    logical(cfg.AutoICAReject), ...
    cfg.AutoICARejectThreshold, ...
    string(strjoin(string(cfg.AutoICARejectClasses), ', ')), ...
    string(mat2str(autoComponents)), ...
    string(mat2str(providedComponents)), ...
    string(mat2str(manualComponents)), ...
    string(mat2str(componentsToRemove)), ...
    string(datestr(now)), ...
    'VariableNames', { ...
        'ParticipantID', ...
        'AutoICAReject', ...
        'AutoICARejectThreshold', ...
        'AutoICARejectClasses', ...
        'AutoComponents', ...
        'ProvidedComponentsToRemove', ...
        'ManualComponents', ...
        'FinalComponentsToRemove', ...
        'DecisionTime'});

componentDecisionCsv = fullfile(outDir, sprintf('%s_ICAComponentsToRemove.csv', participantID));
writetable(componentDecisionTable, componentDecisionCsv);

fprintf('\nAutomatic ICLabel rejection enabled: %s\n', mat2str(cfg.AutoICAReject));
fprintf('Classes: %s\n', strjoin(cfg.AutoICARejectClasses, ', '));
fprintf('Threshold: %.2f\n', cfg.AutoICARejectThreshold);
fprintf('\nAutomatically selected ICs:\n');
disp(autoComponents);
fprintf('\nProvided ComponentsToRemove:\n');
disp(providedComponents);
fprintf('\nAdditional manual ICs:\n');
disp(manualComponents);
fprintf('\nFinal components selected for removal:\n');
disp(componentsToRemove);

logStep('ica_component_selection', 'OK', 'ICA components selected for removal', mat2str(componentsToRemove), componentDecisionCsv);

% ====================================================================
% Stage 8: Create ERP-analysis dataset
% ====================================================================

fprintf('\n\n================ STAGE 8: ERP-ANALYSIS DATASET ================\n');

EEG_erp = EEG_ds;

EEG_erp = pop_eegfiltnew(EEG_erp, ...
    'locutoff', cfg.ERPFilterHz(1), ...
    'hicutoff', cfg.ERPFilterHz(2), ...
    'plotfreqz', 0);

EEG_erp.setname = sprintf('%s_ds%d_bp0p1to20', participantID, cfg.TargetSrate);

externalIdxErp = localFindExistingChannelsByLabels(EEG_erp, originalExternalLabels);
EEG_erp = pop_reref(EEG_erp, [], 'exclude', externalIdxErp);
EEG_erp.setname = sprintf('%s_ds%d_bp0p1to20_avgref', participantID, cfg.TargetSrate);

EEG_erp = localFixChanlocsForICLabel(EEG_erp);
EEG_erp = eeg_checkset(EEG_erp);

erpSet = sprintf('%s_ds%d_bp0p1to20_avgref.set', participantID, cfg.TargetSrate);
EEG_erp = pop_saveset(EEG_erp, 'filename', erpSet, 'filepath', outDir);

logStep('erp_dataset', 'OK', 'Created 0.1-20 Hz average-referenced ERP-analysis dataset', '', erpSet);

if cfg.RunLineNoiseQC
    try
        [tmpLineNoiseTable, lineNoisePlotDir, lineNoiseQCSummaryStr] = localComputeLineNoiseQC( ...
            EEG_erp, cfg, participantID, 'ERPanalysis_0p1to20Hz', ...
            originalScalpLabels, flaggedBadScalpLabels, flaggedLineNoiseLabels, ...
            outDir, lineNoisePlotDir);
        lineNoiseQCTables{end+1} = tmpLineNoiseTable;
        logStep('line_noise_qc', 'OK', ...
            'Line-noise QC completed for ERPanalysis_0p1to20Hz', ...
            lineNoiseQCSummaryStr, '');
    catch ME
        logStep('line_noise_qc', 'WARN', ...
            'Line-noise QC failed for ERPanalysis_0p1to20Hz', ...
            ME.message, '');
    end

    if ~isempty(lineNoiseQCTables)
        lineNoiseQCTable = vertcat(lineNoiseQCTables{:});
        writetable(lineNoiseQCTable, lineNoiseQCTableCsv);
        lineNoiseQCSummary = localSummarizeLineNoiseQC(lineNoiseQCTable, participantID, cfg);
        writetable(lineNoiseQCSummary, lineNoiseQCSummaryCsv);
        logStep('line_noise_qc', 'OK', ...
            'Saved line-noise QC table and summary', ...
            sprintf('%d stage table(s)', numel(lineNoiseQCTables)), ...
            lineNoiseQCTableCsv);
        if numel(lineNoiseQCTables) == 3
            lineNoiseQCStatus = 'OK';
        else
            lineNoiseQCStatus = 'PARTIAL';
        end
    else
        logStep('line_noise_qc', 'WARN', ...
            'No line-noise QC tables were produced', ...
            'All line-noise QC stage calls failed or were skipped', '');
        lineNoiseQCStatus = 'FAILED';
    end
end

% ====================================================================
% Stage 8b: Channel QC persistence
% ====================================================================

fprintf('\n\n================ STAGE 8b: CHANNEL QC PERSISTENCE ================\n');

if ~cfg.RunChannelQCPersistence
    logStep('channel_qc_persistence', 'SKIP', ...
        'Channel QC persistence check disabled', '', '');
else
    try
        [channelQCPersistenceTableCsv, channelQCPersistenceSummaryCsv, ...
            channelQCPersistenceInterpretationCsv, channelQCPlotDir, chQcSummaryStr] = ...
            localRunChannelQCPersistence(cfg, participantID, outDir, badChannelTable, ...
            originalScalpLabels, EEG_ds, EEG_ica, EEG_erp);
        logStep('channel_qc_persistence', 'OK', ...
            'Channel QC persistence check completed', chQcSummaryStr, channelQCPersistenceSummaryCsv);
    catch ME
        logStep('channel_qc_persistence', 'WARN', ...
            'Channel QC persistence check failed', ME.message, '');
    end
end

% ====================================================================
% Stage 9: Transfer ICA and remove selected components
% ====================================================================

fprintf('\n\n================ STAGE 9: ICA TRANSFER AND COMPONENT REMOVAL ================\n');

localCheckIcaTransferCompatibility(EEG_ica, EEG_erp);

EEG_erp.icaweights = EEG_ica.icaweights;
EEG_erp.icasphere  = EEG_ica.icasphere;
EEG_erp.icawinv    = EEG_ica.icawinv;
EEG_erp.icachansind = EEG_ica.icachansind;
EEG_erp.icaact = [];

if isfield(EEG_ica, 'etc') && isfield(EEG_ica.etc, 'ic_classification')
    EEG_erp.etc.ic_classification = EEG_ica.etc.ic_classification;
end

EEG_erp = eeg_checkset(EEG_erp);

transferredSet = sprintf('%s_ds%d_bp0p1to20_avgref_PicardICAtransferred.set', participantID, cfg.TargetSrate);
EEG_erp.setname = erase(transferredSet, '.set');
EEG_erp = pop_saveset(EEG_erp, 'filename', transferredSet, 'filepath', outDir);

if ~isempty(componentsToRemove)
    EEG_clean = pop_subcomp(EEG_erp, componentsToRemove, 0);
else
    EEG_clean = EEG_erp;
end

EEG_clean = localClearIcaFields(EEG_clean);
logStep('clear_ica_fields', 'OK', ...
    'Cleared ICA fields from final cleaned continuous dataset after component removal', '', '');

compTag = localComponentTag(componentsToRemove);
cleanSet = sprintf('%s_ds%d_bp0p1to20_avgref_%sRemoved.set', ...
    participantID, cfg.TargetSrate, compTag);

EEG_clean.setname = erase(cleanSet, '.set');
EEG_clean = pop_saveset(EEG_clean, 'filename', cleanSet, 'filepath', outDir);

logStep('ica_transfer', 'OK', 'Transferred Picard ICA weights to ERP dataset', '', transferredSet);
logStep('component_removal', 'OK', 'Removed selected ICA components from ERP dataset', mat2str(componentsToRemove), cleanSet);

% ====================================================================
% Stage 10: ALEX01 behavioural matching and S1 reconstruction
% ====================================================================

fprintf('\n\n================ STAGE 10: ALEX01 S1 RECOVERY ================\n');

T_beh = readtable(fullRunCsv);
fprintf('Behavioural FullRun rows: %d\n', height(T_beh));
if height(T_beh) ~= cfg.ExpectedMainTrials
    error('Expected %d behavioural rows but found %d.', cfg.ExpectedMainTrials, height(T_beh));
end

varMap = localInferBehaviourVars(T_beh, cfg);
varMapTable = table(string(varMap.PASVar), string(varMap.LocCorrectVar), ...
    string(varMap.LocRespVar), string(varMap.IsChangeVar), ...
    'VariableNames', {'PASVar','LocCorrectVar','LocRespVar','IsChangeVar'});
varMapCsv = fullfile(outDir, sprintf('%s_BehaviourVariableMap.csv', participantID));
writetable(varMapTable, varMapCsv);

bdfEventNums = arrayfun(@(e) localEventTypeToNumber(e.type), EEG_clean.event);
bdfEventCodeInventoryCsv = fullfile(outDir, sprintf('%s_BdfEventCodeInventory.csv', participantID));
localWriteBdfEventCodeInventory(bdfEventNums, bdfEventCodeInventoryCsv);

if any(bdfEventNums == 21)
    warning('ALEX01 BDF unexpectedly contains code 21. Recovery still uses code 22 plus CSV timing.');
end

fprintf('ALEX01 recorded scheme used for recovery:\n');
fprintf('  ISI anchor=%d, S2=%d, gap=%d, Q1=%d, PAS=%s, LOC=%s\n', ...
    cfg.RecordedISIAnchorCode, cfg.RecordedS2Code, cfg.RecordedGapCode, ...
    cfg.RecordedQ1Code, mat2str(cfg.RecordedPASCodes), mat2str(cfg.RecordedLocCodes));
fprintf('  Reconstructed S1 internal code=%d (not a recorded hardware trigger)\n', cfg.ReconstructedS1Code);

[trialsMain, recoveryAudit] = localReconstructALEX01Trials(EEG_clean, T_beh, cfg);
nMainTriggered = numel(trialsMain.s1Latency);
nPracticeTriggered = 0;
practiceTriggerAuditCsv = '';
mainTriggerAuditCsv = fullfile(outDir, sprintf('%s_ALEX01_RecoveryTrialAudit.csv', participantID));
writetable(recoveryAudit, mainTriggerAuditCsv);
syntheticS1AuditCsv = mainTriggerAuditCsv;

if nMainTriggered ~= cfg.ExpectedMainTrials
    error('ALEX01 recovery produced %d trials; expected %d.', nMainTriggered, cfg.ExpectedMainTrials);
end

pasBeh = double(T_beh.(varMap.PASVar));
locRespBeh = [];
if ~isempty(varMap.LocRespVar)
    locRespBeh = double(T_beh.(varMap.LocRespVar));
end
locCorrect = localColumnToLogicalCorrect(T_beh.(varMap.LocCorrectVar));
isChange = localColumnToLogicalChange(T_beh.(varMap.IsChangeVar));

pasMismatch = sum(trialsMain.pasResp(:) ~= pasBeh(:), 'omitnan');
if ~isempty(locRespBeh)
    locTriggerPresent = isfinite(trialsMain.locResp(:));
    nLocTriggersPresent = sum(locTriggerPresent);
    locMismatch = sum(trialsMain.locResp(locTriggerPresent) ~= locRespBeh(locTriggerPresent));
else
    locTriggerPresent = false(nMainTriggered,1);
    nLocTriggersPresent = 0;
    locMismatch = NaN;
end

fprintf('Reconstructed S1 trials: %d\n', nMainTriggered);
fprintf('PAS mismatches EEG vs CSV: %d\n', pasMismatch);
if isnan(locMismatch)
    fprintf('LOC response audit skipped: no loc response column identified.\n');
else
    fprintf('Recorded LOC triggers available: %d / %d trials\n', nLocTriggersPresent, nMainTriggered);
    fprintf('LOC mismatches among recorded LOC triggers vs CSV: %d\n', locMismatch);
end

if pasMismatch ~= 0
    error('PAS mismatch detected between ALEX01 EEG triggers and behavioural CSV.');
end
if ~isnan(locMismatch) && locMismatch ~= 0
    error(['Localisation mismatch detected among the subset of ALEX01 trials with a surviving ', ...
        '51-54 trigger. This suggests trial-order misalignment.']);
end

logStep('alex01_s1_recovery', 'OK', ...
    'Reconstructed S1 onsets from code 22 and behavioural timing', ...
    sprintf('%d trials; internal code %d', nMainTriggered, cfg.ReconstructedS1Code), mainTriggerAuditCsv);
logStep('event_matching', 'OK', 'PAS mismatches EEG vs CSV', num2str(pasMismatch), '');
logStep('event_matching', 'OK', 'LOC trigger audit (surviving subset only)', ...
    sprintf('%d present; %s mismatches', nLocTriggersPresent, num2str(locMismatch)), '');

% ====================================================================
% Stage 11: Add synthetic S1/S2 outcome codes
% ====================================================================

fprintf('\n\n================ STAGE 11: ADD S1/S2 OUTCOME CODES ================\n');

[outcome, s1Codes, s2Codes] = localMakeOutcomeCodes(pasBeh, locCorrect, isChange);

outcomeCounts = groupsummary(table(string(outcome(:)), s1Codes(:), s2Codes(:), ...
    'VariableNames', {'Outcome','S1Code','S2Code'}), 'Outcome');

fprintf('\nBehavioural outcome counts before artefact rejection:\n');
disp(outcomeCounts);

EEG_coded = localAddSyntheticS1S2Events(EEG_clean, trialsMain, s1Codes, s2Codes, outcome);
EEG_coded = eeg_checkset(EEG_coded, 'eventconsistency');

codedSet = sprintf('%s_ds%d_bp0p1to20_avgref_%sRemoved_RECOVERED_S1S2coded.set', ...
    participantID, cfg.TargetSrate, compTag);

EEG_coded.setname = erase(codedSet, '.set');
EEG_coded = pop_saveset(EEG_coded, 'filename', codedSet, 'filepath', outDir);

logStep('s1s2_coding', 'OK', 'Added synthetic S1/S2 outcome codes', sprintf('%d S1 + %d S2', numel(s1Codes), numel(s2Codes)), codedSet);

% ====================================================================
% Stage 12: Epoch S1 and S2 with S1 baseline logic
% ====================================================================

fprintf('\n\n================ STAGE 12: EPOCH S1/S2 ================\n');

currentScalpLabels = string({EEG_coded.chanlocs(1:cfg.NScalpChans).labels});
currentScalpLabels = currentScalpLabels(:);
if ~isequal(currentScalpLabels, originalScalpLabels)
    error('Expected original scalp channel labels/order to be restored before epoching.');
end

s1EventCodes = {'201','202','203','211','212'};
s2EventCodes = {'301','302','303','311','312'};

baselineMeans = localComputePreS1BaselineMeans(EEG_coded, trialsMain.s1Latency, cfg.S1BaselineMs);

EEG_S1 = pop_epoch(EEG_coded, s1EventCodes, cfg.S1EpochWinSec, 'epochinfo', 'yes');
EEG_S1 = eeg_checkset(EEG_S1);
EEG_S1 = pop_rmbase(EEG_S1, cfg.S1BaselineMs);
EEG_S1.icaact = [];
EEG_S1.etc.cb_epoching.baseline = 'pre-S1 baseline';
EEG_S1.etc.cb_epoching.baselineMs = cfg.S1BaselineMs;
EEG_S1.etc.cb_epoching.lock = 'S1';
EEG_S1.etc.cb_epoching.s1TimingProvenance = 'Reconstructed from recorded code 22 and behavioural timing';
EEG_S1.etc.cb_epoching.reconstructedS1Code = cfg.ReconstructedS1Code;
EEG_S1.etc.cb_epoching.fullRunRows = (1:cfg.ExpectedMainTrials)';
EEG_S1 = eeg_checkset(EEG_S1);

EEG_S2 = pop_epoch(EEG_coded, s2EventCodes, cfg.S2EpochWinSec, 'epochinfo', 'yes');
EEG_S2 = eeg_checkset(EEG_S2);

if EEG_S2.trials ~= cfg.ExpectedMainTrials
    error('S2 epoch count mismatch. Expected %d, got %d.', cfg.ExpectedMainTrials, EEG_S2.trials);
end

for tr = 1:EEG_S2.trials
    EEG_S2.data(:,:,tr) = double(EEG_S2.data(:,:,tr)) - baselineMeans(:,tr);
end

EEG_S2.icaact = [];
EEG_S2.etc.cb_epoching.baseline = 'trial-wise pre-S1 baseline';
EEG_S2.etc.cb_epoching.baselineMs = cfg.S1BaselineMs;
EEG_S2.etc.cb_epoching.lock = 'S2';
EEG_S2.etc.cb_epoching.s1BaselineTimingProvenance = 'S1 baseline anchored to reconstructed S1 onset';
EEG_S2.etc.cb_epoching.fullRunRows = (1:cfg.ExpectedMainTrials)';
EEG_S2 = eeg_checkset(EEG_S2);

s1EpochSet = sprintf('%s_ERP_S1locked_RECONSTRUCTED_m200to1400_S1base.set', participantID);
s2EpochSet = sprintf('%s_ERP_S2locked_m900to800_RECONSTRUCTED_S1base.set', participantID);

EEG_S1.setname = erase(s1EpochSet, '.set');
EEG_S2.setname = erase(s2EpochSet, '.set');

EEG_S1 = pop_saveset(EEG_S1, 'filename', s1EpochSet, 'filepath', outDir);
EEG_S2 = pop_saveset(EEG_S2, 'filename', s2EpochSet, 'filepath', outDir);

fprintf('S1 epochs: %d | %.1f to %.1f ms\n', EEG_S1.trials, EEG_S1.xmin*1000, EEG_S1.xmax*1000);
fprintf('S2 epochs: %d | %.1f to %.1f ms\n', EEG_S2.trials, EEG_S2.xmin*1000, EEG_S2.xmax*1000);

logStep('epoching', 'OK', 'Created S1 epochs with S1 baseline', sprintf('%d epochs', EEG_S1.trials), s1EpochSet);
logStep('epoching', 'OK', 'Created S2 epochs with trial-wise S1 baseline', sprintf('%d epochs', EEG_S2.trials), s2EpochSet);

% ====================================================================
% Stage 13: Joint artefact rejection
% ====================================================================

fprintf('\n\n================ STAGE 13: JOINT ARTEFACT REJECTION ================\n');

badS1 = localFindBadEpochs(EEG_S1, cfg.ScalpChans, cfg.ArtifactAbsThresholdUv, cfg.ArtifactPeakToPeakThresholdUv);
badS2 = localFindBadEpochs(EEG_S2, cfg.ScalpChans, cfg.ArtifactAbsThresholdUv, cfg.ArtifactPeakToPeakThresholdUv);

badUnion = badS1.anyBad | badS2.anyBad;
rejectIdx = find(badUnion);
keepIdx = find(~badUnion);

fprintf('S1 bad epochs:    %d / %d\n', sum(badS1.anyBad), EEG_S1.trials);
fprintf('S2 bad epochs:    %d / %d\n', sum(badS2.anyBad), EEG_S2.trials);
fprintf('Union rejected:   %d / %d\n', numel(rejectIdx), EEG_S1.trials);
fprintf('Remaining epochs: %d / %d\n', numel(keepIdx), EEG_S1.trials);

EEG_S1_clean = pop_select(EEG_S1, 'trial', keepIdx);
EEG_S2_clean = pop_select(EEG_S2, 'trial', keepIdx);

EEG_S1_clean.etc.cb_artifactReject.keptOriginalTrialIdx = keepIdx(:);
EEG_S2_clean.etc.cb_artifactReject.keptOriginalTrialIdx = keepIdx(:);
EEG_S1_clean.etc.cb_artifactReject.rejectedOriginalTrialIdx = rejectIdx(:);
EEG_S2_clean.etc.cb_artifactReject.rejectedOriginalTrialIdx = rejectIdx(:);
EEG_S1_clean.etc.cb_artifactReject.thresholdAbsUv = cfg.ArtifactAbsThresholdUv;
EEG_S2_clean.etc.cb_artifactReject.thresholdAbsUv = cfg.ArtifactAbsThresholdUv;
EEG_S1_clean.etc.cb_artifactReject.thresholdPeakToPeakUv = cfg.ArtifactPeakToPeakThresholdUv;
EEG_S2_clean.etc.cb_artifactReject.thresholdPeakToPeakUv = cfg.ArtifactPeakToPeakThresholdUv;

s1CleanSet = sprintf('%s_ERP_S1locked_RECONSTRUCTED_m200to1400_S1base_ARclean.set', participantID);
s2CleanSet = sprintf('%s_ERP_S2locked_m900to800_RECONSTRUCTED_S1base_ARclean.set', participantID);

EEG_S1_clean.setname = erase(s1CleanSet, '.set');
EEG_S2_clean.setname = erase(s2CleanSet, '.set');

EEG_S1_clean = pop_saveset(EEG_S1_clean, 'filename', s1CleanSet, 'filepath', outDir);
EEG_S2_clean = pop_saveset(EEG_S2_clean, 'filename', s2CleanSet, 'filepath', outDir);

arReport = localMakeArtifactReport(EEG_S1, EEG_S2, badS1, badS2, badUnion, keepIdx, rejectIdx);
arCsv = fullfile(outDir, sprintf('%s_EpochArtifactRejectionReport.csv', participantID));
writetable(arReport, arCsv);

countsBefore = localConditionCountsFromEpochs(EEG_S1, [201 202 203 211 212]);
countsAfter  = localConditionCountsFromEpochs(EEG_S1_clean, [201 202 203 211 212]);

countsBeforeCsv = fullfile(outDir, sprintf('%s_ConditionCountsBeforeAR.csv', participantID));
countsAfterCsv = fullfile(outDir, sprintf('%s_ConditionCountsAfterAR.csv', participantID));
writetable(countsBefore, countsBeforeCsv);
writetable(countsAfter, countsAfterCsv);

fprintf('\nCondition counts before artefact rejection:\n');
disp(countsBefore);

fprintf('\nCondition counts after artefact rejection:\n');
disp(countsAfter);

logStep('artifact_rejection', 'OK', 'Joint S1/S2 artefact rejection complete', sprintf('%d rejected; %d kept', numel(rejectIdx), numel(keepIdx)), arCsv);
logStep('artifact_rejection', 'OK', 'Saved AR-clean S1 dataset', '', s1CleanSet);
logStep('artifact_rejection', 'OK', 'Saved AR-clean S2 dataset', '', s2CleanSet);

% ====================================================================
% Stage 14: ROI plotting
% ====================================================================

fprintf('\n\n================ STAGE 14: ROI PLOTTING ================\n');

plotReport = localPlotAllRois(EEG_S1_clean, EEG_S2_clean, participantID, plotDir, cfg);

plotReportCsv = fullfile(plotDir, sprintf('%s_ROIPlotFiles.csv', participantID));
writetable(plotReport.plotFiles, plotReportCsv);

logStep('roi_plotting', 'OK', 'Generated S1/S2 ROI plots', sprintf('%d plot rows', height(plotReport.plotFiles)), plotReportCsv);

% ====================================================================
% Stage 15: Extra final ERP and topography plots
% ====================================================================

fprintf('\n\n================ STAGE 15: EXTRA FINAL ERP AND TOPOGRAPHY PLOTS ================\n');

extraPlotOutputs = struct();

if ~cfg.RunExtraFinalPlots
    logStep('extra_final_plots', 'SKIP', 'Extra final plotting disabled', '', '');
elseif exist(fullfile(outDir, s1CleanSet), 'file') ~= 2 || exist(fullfile(outDir, s2CleanSet), 'file') ~= 2
    warning('AR-clean S1/S2 datasets not found in %s; skipping extra final plots.', outDir);
    logStep('extra_final_plots', 'SKIP', 'AR-clean S1/S2 datasets missing for extra final plots', '', '');
else
    extraPlotCommonArgs = { ...
        'Visible', cfg.ExtraPlotVisible, ...
        'SavePng', cfg.ExtraPlotSavePng, ...
        'SaveFig', cfg.ExtraPlotSaveFig, ...
        'SaveCsv', cfg.ExtraPlotSaveCsv};

    if exist('CB_EEG_PlotCentralROI_TrialTraces_S1S2', 'file') == 2
        try
            extraPlotOutputs.centralTrialTraces = CB_EEG_PlotCentralROI_TrialTraces_S1S2( ...
                participantID, outDir, ...
                'S1SetName', s1CleanSet, ...
                'S2SetName', s2CleanSet, ...
                'CentralChannels', cfg.ExtraPlotCentralChannels, ...
                extraPlotCommonArgs{:});
            logStep('extra_final_plots', 'OK', 'Generated central ROI trial-trace plots', '', ...
                localExtractPlotOutputPath(extraPlotOutputs.centralTrialTraces));
        catch ME
            extraPlotOutputs.centralTrialTraces = struct('status', 'failed', 'message', ME.message);
            logStep('extra_final_plots', 'WARN', 'Central ROI trial-trace plotting failed', ME.message, '');
        end
    else
        warning('CB_EEG_PlotCentralROI_TrialTraces_S1S2 was not found on the MATLAB path.');
        logStep('extra_final_plots', 'WARN', 'Central ROI trial-trace function not found', '', '');
    end

    if exist('CB_EEG_PlotCentralROI_BSS_Overlay_S1S2', 'file') == 2
        try
            extraPlotOutputs.centralBSSOverlay = CB_EEG_PlotCentralROI_BSS_Overlay_S1S2( ...
                participantID, outDir, ...
                'S1SetName', s1CleanSet, ...
                'S2SetName', s2CleanSet, ...
                'CentralChannels', cfg.ExtraPlotCentralChannels, ...
                extraPlotCommonArgs{:});
            logStep('extra_final_plots', 'OK', 'Generated central ROI B/S/S overlay trial-trace plot', '', ...
                localExtractPlotOutputPath(extraPlotOutputs.centralBSSOverlay));
        catch ME
            extraPlotOutputs.centralBSSOverlay = struct('status', 'failed', 'message', ME.message);
            logStep('extra_final_plots', 'WARN', 'Central ROI B/S/S overlay plotting failed', ME.message, '');
        end
    else
        warning('CB_EEG_PlotCentralROI_BSS_Overlay_S1S2 was not found on the MATLAB path.');
        logStep('extra_final_plots', 'WARN', 'Central ROI B/S/S overlay function not found', '', '');
    end

    if exist('CB_EEG_PlotS2_VAN_LP_Topomaps', 'file') == 2
        try
            extraPlotOutputs.s2VanLpTopomaps = CB_EEG_PlotS2_VAN_LP_Topomaps( ...
                participantID, outDir, ...
                'S2SetName', s2CleanSet, ...
                'ScalpChans', cfg.ScalpChans, ...
                'VANWindowMs', cfg.ExtraPlotVANWindowMs, ...
                'LPWindowMs', cfg.ExtraPlotLPWindowMs, ...
                extraPlotCommonArgs{:}, ...
                'Electrodes', 'on');
            logStep('extra_final_plots', 'OK', 'Generated S2 VAN/LP topomaps', '', ...
                localExtractPlotOutputPath(extraPlotOutputs.s2VanLpTopomaps));
        catch ME
            extraPlotOutputs.s2VanLpTopomaps = struct('status', 'failed', 'message', ME.message);
            logStep('extra_final_plots', 'WARN', 'S2 VAN/LP topomap plotting failed', ME.message, '');
        end
    else
        warning('CB_EEG_PlotS2_VAN_LP_Topomaps was not found on the MATLAB path.');
        logStep('extra_final_plots', 'WARN', 'S2 VAN/LP topomap function not found', '', '');
    end
end

% ====================================================================
% Final report
% ====================================================================

report = struct();
report.participantID = participantID;
report.dataPath = dataPath;
report.outDir = outDir;
report.plotDir = plotDir;
report.logTxtFile = logTxtFile;
report.logCsvFile = logCsvFile;
report.bdfPath = bdfPath;
report.fullRunCsv = fullRunCsv;
report.nPracticeTriggered = nPracticeTriggered;
report.nMainTriggered = nMainTriggered;
report.practiceTriggerAuditCsv = practiceTriggerAuditCsv;
report.mainTriggerAuditCsv = mainTriggerAuditCsv;
report.bdfEventCodeInventoryCsv = bdfEventCodeInventoryCsv;
report.recoveryMode = 'ALEX01_missing_S1';
report.reconstructedS1Code = cfg.ReconstructedS1Code;
report.syntheticS1AuditCsv = syntheticS1AuditCsv;
report.cfg = cfg;
report.componentsToRemove = componentsToRemove;
report.autoICAComponentsToRemove = autoComponents;
report.providedICAComponentsToRemove = providedComponents;
report.manualICAComponentsToRemove = manualComponents;
report.autoICASelectionTableCsv = autoSelectionCsv;
report.icaComponentDecisionCsv = componentDecisionCsv;
report.flaggedBadScalpChannels = cellstr(flaggedBadScalpLabels);
report.flaggedBadScalpChannelIndices = flaggedBadScalpIndices;
report.nFlaggedBadScalpChannels = numel(flaggedBadScalpLabels);
report.flatlineFlaggedBadScalpChannels = cellstr(flaggedFlatlineLabels);
report.flatlineFlaggedBadScalpChannelIndices = flaggedFlatlineIndices;
report.nFlatlineFlaggedBadScalpChannels = numel(flaggedFlatlineLabels);
report.lineNoiseFlaggedBadScalpChannels = cellstr(flaggedLineNoiseLabels);
report.lineNoiseFlaggedBadScalpChannelIndices = flaggedLineNoiseIndices;
report.nLineNoiseFlaggedBadScalpChannels = numel(flaggedLineNoiseLabels);
report.correlationFlaggedBadScalpChannels = cellstr(flaggedCorrelationLabels);
report.correlationFlaggedBadScalpChannelIndices = flaggedCorrelationIndices;
report.nCorrelationFlaggedBadScalpChannels = numel(flaggedCorrelationLabels);
report.badChannelCheckTableCsv = badChannelCheckTableCsv;
report.badChannelCheckSummaryCsv = badChannelCheckSummaryCsv;
report.badChannelsRemoved = false;
report.lineNoiseQCTableCsv = lineNoiseQCTableCsv;
report.lineNoiseQCSummaryCsv = lineNoiseQCSummaryCsv;
report.lineNoiseQCPlotDir = lineNoisePlotDir;
report.runLineNoiseQC = cfg.RunLineNoiseQC;
report.lineNoiseQCStatus = lineNoiseQCStatus;
report.runChannelQCPersistence = cfg.RunChannelQCPersistence;
report.channelQCPersistenceTableCsv = channelQCPersistenceTableCsv;
report.channelQCPersistenceSummaryCsv = channelQCPersistenceSummaryCsv;
report.channelQCPersistenceInterpretationCsv = channelQCPersistenceInterpretationCsv;
report.channelQCPersistencePlotDir = channelQCPlotDir;
report.cleanRawDataConsoleLogFile = cleanRawDataConsoleLogFile;
report.nGoodScalpChannelsForICA = cfg.NScalpChans;
report.icaPcaDimRequested = cfg.ICAPcaDim;
report.icaPcaDimUsed = icaPcaDimUsed;
report.nIcaChannelsUsed = nIcaChansUsed;
report.icaElapsedSec = icaElapsedSec;
report.icaElapsedMin = icaElapsedSec/60;
report.cleanContinuousSet = cleanSet;
report.codedContinuousSet = codedSet;
report.s1EpochSet = s1EpochSet;
report.s2EpochSet = s2EpochSet;
report.s1CleanSet = s1CleanSet;
report.s2CleanSet = s2CleanSet;
report.countsBeforeAR = countsBefore;
report.countsAfterAR = countsAfter;
report.plotReport = plotReport;
report.runExtraFinalPlots = cfg.RunExtraFinalPlots;
report.extraFinalPlotOutputs = extraPlotOutputs;

finalReportMat = fullfile(outDir, sprintf('%s_FinalRecoveryPipelineReport.mat', participantID));
save(finalReportMat, 'report');

logStep('pipeline', 'DONE', 'Pipeline completed successfully', '', finalReportMat);

writeLogCsv();

fprintf('\n============================================================\n');
fprintf('PIPELINE COMPLETE\n');
fprintf('Finished: %s\n', datestr(now));
fprintf('Output folder:\n%s\n', outDir);
fprintf('Text log:\n%s\n', logTxtFile);
fprintf('CSV log:\n%s\n', logCsvFile);
fprintf('============================================================\n\n');

diary off;


catch ME
fprintf('\n============================================================\n');
fprintf('PIPELINE ERROR\n');
fprintf('%s\n', ME.message);
fprintf('============================================================\n\n');


logStep('pipeline', 'ERROR', ME.message, '', '');

try
    writeLogCsv();
catch
end

diary off;
rethrow(ME);


end

% ========================================================================
% Nested logging functions
% ========================================================================


function logStep(stage, status, message, value, file)
    if nargin < 4 || isempty(value)
        value = "";
    end
    if nargin < 5 || isempty(file)
        file = "";
    end

    ts = string(datestr(now, 'yyyy-mm-dd HH:MM:SS'));

    fprintf('[%s] %-24s %-8s %s', ts, char(stage), char(status), char(message));
    if strlength(string(value)) > 0
        fprintf(' | %s', char(string(value)));
    end
    if strlength(string(file)) > 0
        fprintf(' | %s', char(string(file)));
    end
    fprintf('\n');

    newRow = table( ...
        ts, string(stage), string(status), string(message), string(value), string(file), ...
        'VariableNames', {'Timestamp','Stage','Status','Message','Value','File'});

    logRows = [logRows; newRow];
end

function writeLogCsv()
    writetable(logRows, logCsvFile);
end


end

% ========================================================================
% Helper functions
% ========================================================================


function [flaggedBadScalpLabels, flaggedBadScalpIndices, ...
    flaggedFlatlineLabels, flaggedFlatlineIndices, ...
    flaggedLineNoiseLabels, flaggedLineNoiseIndices, ...
    flaggedCorrelationLabels, flaggedCorrelationIndices, ...
    badChannelCheckTableCsv, badChannelCheckSummaryCsv, badChannelTable] = ...
    localCheckBadScalpChannelsCleanRawData(EEG_ds, cfg, participantID, originalScalpLabels, originalScalpChanlocs, outDir)

originalScalpLabels = string(originalScalpLabels(:));
nScalp = numel(originalScalpLabels);

flaggedBadScalpLabels = strings(0, 1);
flaggedBadScalpIndices = [];
flaggedFlatlineLabels = strings(0, 1);
flaggedFlatlineIndices = [];
flaggedLineNoiseLabels = strings(0, 1);
flaggedLineNoiseIndices = [];
flaggedCorrelationLabels = strings(0, 1);
flaggedCorrelationIndices = [];

if cfg.RunBadChannelChecker
    localValidateScalpChanlocs(originalScalpChanlocs);

    if exist('pop_clean_rawdata', 'file') ~= 2
        error('Clean RawData plugin function pop_clean_rawdata was not found. Install/enable EEGLAB Clean RawData before using RunBadChannelChecker.');
    end

    EEG_badcheck = pop_select(EEG_ds, 'channel', 1:cfg.NScalpChans);
    EEG_badcheck = localFixChanlocsForICLabel(EEG_badcheck);
    EEG_badcheck = eeg_checkset(EEG_badcheck);

    labelsBefore = string({EEG_badcheck.chanlocs.labels});
    labelsBefore = labelsBefore(:);

    diag = localRunScalpChannelDiagnosticPasses(EEG_badcheck, cfg, labelsBefore, false, '');

    flaggedBadScalpLabels = diag.combinedLabels;
    flaggedBadScalpIndices = diag.combinedIndices;
    flaggedFlatlineLabels = diag.flatlineLabels;
    flaggedFlatlineIndices = diag.flatlineIndices;
    flaggedLineNoiseLabels = diag.lineNoiseLabels;
    flaggedLineNoiseIndices = diag.lineNoiseIndices;
    flaggedCorrelationLabels = diag.correlationLabels;
    flaggedCorrelationIndices = diag.correlationIndices;

    combinedMask = diag.combinedMask;
    flatlineMask = diag.flatlineMask;
    lineNoiseMask = diag.lineNoiseMask;
    correlationMask = diag.correlationMask;
else
    fprintf('Bad scalp-channel QC checker disabled.\n');
end

decisionTime = string(datestr(now));

if cfg.RunBadChannelChecker
    combinedMask = ismember(originalScalpLabels, flaggedBadScalpLabels);
    flatlineMask = ismember(originalScalpLabels, flaggedFlatlineLabels);
    lineNoiseMask = ismember(originalScalpLabels, flaggedLineNoiseLabels);
    correlationMask = ismember(originalScalpLabels, flaggedCorrelationLabels);
else
    combinedMask = false(nScalp, 1);
    flatlineMask = false(nScalp, 1);
    lineNoiseMask = false(nScalp, 1);
    correlationMask = false(nScalp, 1);
end

flagReasonCol = strings(nScalp, 1);
for i = 1:nScalp
    flagReasonCol(i) = localBuildBadChannelFlagReason( ...
        combinedMask(i), flatlineMask(i), lineNoiseMask(i), correlationMask(i), cfg.RunBadChannelChecker);
end

badChannelTable = table( ...
    repmat(string(participantID), nScalp, 1), ...
    (1:nScalp)', ...
    originalScalpLabels, ...
    repmat(logical(cfg.RunBadChannelChecker), nScalp, 1), ...
    combinedMask, ...
    flatlineMask, ...
    lineNoiseMask, ...
    correlationMask, ...
    flagReasonCol, ...
    repmat(cfg.BadChannelCheckerFlatlineCriterion, nScalp, 1), ...
    repmat(cfg.BadChannelCheckerLineNoiseCriterion, nScalp, 1), ...
    repmat(cfg.BadChannelCheckerCorrelationCriterion, nScalp, 1), ...
    repmat(decisionTime, nScalp, 1), ...
    'VariableNames', { ...
        'ParticipantID', ...
        'OriginalScalpIndex', ...
        'Label', ...
        'RunBadChannelChecker', ...
        'FlaggedByCleanRawData', ...
        'FlaggedByFlatlineCriterion', ...
        'FlaggedByLineNoiseCriterion', ...
        'FlaggedByCorrelationCriterion', ...
        'FlagReason', ...
        'BadChannelCheckerFlatlineCriterion', ...
        'BadChannelCheckerLineNoiseCriterion', ...
        'BadChannelCheckerCorrelationCriterion', ...
        'DecisionTime'});

badChannelCheckTableCsv = fullfile(outDir, sprintf('%s_BadChannelCheckTable.csv', participantID));
writetable(badChannelTable, badChannelCheckTableCsv);

summaryTable = table( ...
    string(participantID), ...
    string(strjoin(flaggedBadScalpLabels, ', ')), ...
    string(mat2str(flaggedBadScalpIndices)), ...
    numel(flaggedBadScalpLabels), ...
    string(strjoin(flaggedFlatlineLabels, ', ')), ...
    string(mat2str(flaggedFlatlineIndices)), ...
    numel(flaggedFlatlineLabels), ...
    string(strjoin(flaggedLineNoiseLabels, ', ')), ...
    string(mat2str(flaggedLineNoiseIndices)), ...
    numel(flaggedLineNoiseLabels), ...
    string(strjoin(flaggedCorrelationLabels, ', ')), ...
    string(mat2str(flaggedCorrelationIndices)), ...
    numel(flaggedCorrelationLabels), ...
    logical(cfg.RunBadChannelChecker), ...
    cfg.BadChannelCheckerFlatlineCriterion, ...
    cfg.BadChannelCheckerLineNoiseCriterion, ...
    cfg.BadChannelCheckerCorrelationCriterion, ...
    decisionTime, ...
    'VariableNames', { ...
        'ParticipantID', ...
        'FlaggedBadScalpLabels', ...
        'FlaggedBadScalpIndices', ...
        'NFlaggedBadScalpChannels', ...
        'FlatlineFlaggedLabels', ...
        'FlatlineFlaggedIndices', ...
        'NFlatlineFlaggedChannels', ...
        'LineNoiseFlaggedLabels', ...
        'LineNoiseFlaggedIndices', ...
        'NLineNoiseFlaggedChannels', ...
        'CorrelationFlaggedLabels', ...
        'CorrelationFlaggedIndices', ...
        'NCorrelationFlaggedChannels', ...
        'RunBadChannelChecker', ...
        'BadChannelCheckerFlatlineCriterion', ...
        'BadChannelCheckerLineNoiseCriterion', ...
        'BadChannelCheckerCorrelationCriterion', ...
        'DecisionTime'});

badChannelCheckSummaryCsv = fullfile(outDir, sprintf('%s_BadChannelCheckSummary.csv', participantID));
writetable(summaryTable, badChannelCheckSummaryCsv);

fprintf('\nBad scalp-channel checker enabled: %s\n', mat2str(cfg.RunBadChannelChecker));
if cfg.RunBadChannelChecker
    fprintf('Clean RawData checker criteria:\n');
    fprintf('  FlatlineCriterion: %.1f s\n', cfg.BadChannelCheckerFlatlineCriterion);
    fprintf('  LineNoiseCriterion: %.1f SD\n', cfg.BadChannelCheckerLineNoiseCriterion);
    fprintf('  ChannelCriterion: %.2f\n', cfg.BadChannelCheckerCorrelationCriterion);
    if isempty(flaggedBadScalpLabels)
        fprintf('\nNo potentially bad scalp channels were flagged by the QC checker.\n');
    else
        fprintf('\nPotentially bad scalp channels flagged for review:\n');
        for i = 1:numel(flaggedBadScalpLabels)
            lab = flaggedBadScalpLabels(i);
            hit = find(strcmpi(originalScalpLabels, lab), 1, 'first');
            fprintf('  %-8s %s\n', lab, flagReasonCol(hit));
        end
        fprintf('\nReason-specific counts:\n');
        fprintf('  Flatline: %d\n', numel(flaggedFlatlineLabels));
        fprintf('  Line noise: %d\n', numel(flaggedLineNoiseLabels));
        fprintf('  Low channel correlation: %d\n', numel(flaggedCorrelationLabels));
    end
else
    fprintf('Clean RawData checker was not run.\n');
end
fprintf('\nNo channels were removed by this stage.\n');
fprintf('ICA will run on all %d scalp channels.\n', nScalp);

end


function [flaggedLabels, flaggedIndices] = localRunCleanRawDataChannelCheck( ...
    EEG_badcheck, labelsBefore, cfg, passLabel, varargin)

labelsBefore = string(labelsBefore(:));
cleanArgs = localNormaliseCleanRawDataArgs(varargin{:});

EEG_work = pop_select(EEG_badcheck, 'channel', 1:EEG_badcheck.nbchan);
EEG_work = eeg_checkset(EEG_work);

fprintf('Running Clean RawData diagnostic pass: %s on temporary copy ... ', passLabel);

if cfg.SuppressCleanRawDataConsole
    cleanConsoleText = evalc('EEG_checked = pop_clean_rawdata(EEG_work, cleanArgs{:});');
else
    EEG_checked = pop_clean_rawdata(EEG_work, cleanArgs{:});
    cleanConsoleText = '';
end

EEG_checked = eeg_checkset(EEG_checked);

labelsAfter = string({EEG_checked.chanlocs.labels});
labelsAfter = labelsAfter(:);

flaggedLabels = setdiff(labelsBefore, labelsAfter, 'stable');
flaggedIndices = find(ismember(labelsBefore, flaggedLabels))';

summarySuffix = sprintf('Flagged %d channel(s)', numel(flaggedLabels));
if numel(flaggedLabels) > 0 && numel(flaggedLabels) <= 10
    summarySuffix = sprintf('%s (%s)', summarySuffix, strjoin(flaggedLabels, ', '));
end
fprintf('done. %s.\n', summarySuffix);

if cfg.SaveCleanRawDataConsoleLog && cfg.SuppressCleanRawDataConsole && ...
        ~isempty(cfg.CleanRawDataConsoleLogFile)
    localAppendCleanRawDataConsoleLog(cfg.CleanRawDataConsoleLogFile, passLabel, cleanConsoleText);
end

end


function localAppendCleanRawDataConsoleLog(logFile, passLabel, capturedText)

fid = fopen(logFile, 'a');
if fid < 0
    warning('Could not open Clean RawData console log for writing: %s', logFile);
    return;
end

cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>

fprintf(fid, '============================================================\n');
fprintf(fid, 'Clean RawData diagnostic pass: %s\n', passLabel);
fprintf(fid, 'Time: %s\n', datestr(now));
fprintf(fid, '============================================================\n');
fprintf(fid, '%s', capturedText);
if ~isempty(capturedText) && capturedText(end) ~= newline
    fprintf(fid, '\n');
end
fprintf(fid, '\n');

end


function passLabel = localCleanRawDataPassLabel(stageName, checkType)

if nargin < 1 || isempty(stageName)
    passLabel = checkType;
else
    passLabel = sprintf('%s %s', char(stageName), checkType);
end

end


function argsOut = localNormaliseCleanRawDataArgs(varargin)

argsOut = varargin;
for i = 1:2:numel(argsOut)
    if ischar(argsOut{i}) || isstring(argsOut{i})
        paramName = char(argsOut{i});
        paramValue = argsOut{i+1};
        if ischar(paramValue) && strcmpi(paramValue, 'off')
            argsOut{i+1} = localCleanRawDataCriterionDisabledValue(paramName);
        elseif isstring(paramValue) && isscalar(paramValue) && strcmpi(paramValue, "off")
            argsOut{i+1} = localCleanRawDataCriterionDisabledValue(paramName);
        end
    end
end

end


function disabledValue = localCleanRawDataCriterionDisabledValue(paramName)

switch paramName
    case 'FlatlineCriterion'
        disabledValue = Inf;
    case 'LineNoiseCriterion'
        disabledValue = Inf;
    case 'ChannelCriterion'
        disabledValue = 0;
    otherwise
        disabledValue = 'off';
end

end


function reason = localBuildBadChannelFlagReason(flaggedCombined, flaggedFlatline, flaggedLineNoise, flaggedCorrelation, checkerRan)

if ~checkerRan
    reason = "Not run";
    return;
end

reasonParts = strings(0, 1);
if flaggedFlatline
    reasonParts(end+1) = "Flatline";
end
if flaggedLineNoise
    reasonParts(end+1) = "Line noise";
end
if flaggedCorrelation
    reasonParts(end+1) = "Low channel correlation";
end

if flaggedCombined && isempty(reasonParts)
    reason = "Flagged by combined Clean RawData pass only";
elseif isempty(reasonParts)
    reason = "Not flagged";
else
    reason = strjoin(reasonParts, "; ");
end

end


function diag = localRunScalpChannelDiagnosticPasses(EEG_continuous, cfg, labelsBefore, printConsoleNote, stageName)

if nargin < 5
    stageName = '';
end

labelsBefore = string(labelsBefore(:));
nScalp = numel(labelsBefore);

diag = localEmptyChannelDiagnosticResult(nScalp, labelsBefore);

commonOffArgs = { ...
    'Highpass', 'off', ...
    'BurstCriterion', 'off', ...
    'WindowCriterion', 'off', ...
    'BurstRejection', 'off'};

if printConsoleNote
    fprintf('\nRunning channel-quality persistence QC on temporary copies only.\n');
    fprintf('Any "Removing channel(s)" messages below refer to temporary diagnostic copies, not the analysis dataset.\n');
    fprintf('No channels will be removed or interpolated from the real EEG data.\n\n');
end

EEG_scalp = pop_select(EEG_continuous, 'channel', 1:cfg.NScalpChans);
EEG_scalp = localFixChanlocsForICLabel(EEG_scalp);
EEG_scalp = eeg_checkset(EEG_scalp);

try
    passLabel = localCleanRawDataPassLabel(stageName, 'flatline check');
    [diag.flatlineLabels, diag.flatlineIndices] = localRunCleanRawDataChannelCheck( ...
        EEG_scalp, labelsBefore, cfg, passLabel, ...
        'FlatlineCriterion', cfg.BadChannelCheckerFlatlineCriterion, ...
        'LineNoiseCriterion', 'off', ...
        'ChannelCriterion', 'off', ...
        commonOffArgs{:});
    diag.flatlineMask = ismember(labelsBefore, diag.flatlineLabels);
catch ME
    warning('Flatline diagnostic pass failed: %s', ME.message);
end

try
    passLabel = localCleanRawDataPassLabel(stageName, 'line-noise check');
    [diag.lineNoiseLabels, diag.lineNoiseIndices] = localRunCleanRawDataChannelCheck( ...
        EEG_scalp, labelsBefore, cfg, passLabel, ...
        'FlatlineCriterion', 'off', ...
        'LineNoiseCriterion', cfg.BadChannelCheckerLineNoiseCriterion, ...
        'ChannelCriterion', 'off', ...
        commonOffArgs{:});
    diag.lineNoiseMask = ismember(labelsBefore, diag.lineNoiseLabels);
catch ME
    warning('Line-noise diagnostic pass failed: %s', ME.message);
end

try
    passLabel = localCleanRawDataPassLabel(stageName, 'correlation check');
    [diag.correlationLabels, diag.correlationIndices] = localRunCleanRawDataChannelCheck( ...
        EEG_scalp, labelsBefore, cfg, passLabel, ...
        'FlatlineCriterion', 'off', ...
        'LineNoiseCriterion', 'off', ...
        'ChannelCriterion', cfg.BadChannelCheckerCorrelationCriterion, ...
        commonOffArgs{:});
    diag.correlationMask = ismember(labelsBefore, diag.correlationLabels);
catch ME
    warning('Correlation diagnostic pass failed: %s', ME.message);
end

try
    passLabel = localCleanRawDataPassLabel(stageName, 'combined channel check');
    [diag.combinedLabels, diag.combinedIndices] = localRunCleanRawDataChannelCheck( ...
        EEG_scalp, labelsBefore, cfg, passLabel, ...
        'FlatlineCriterion', cfg.BadChannelCheckerFlatlineCriterion, ...
        'LineNoiseCriterion', cfg.BadChannelCheckerLineNoiseCriterion, ...
        'ChannelCriterion', cfg.BadChannelCheckerCorrelationCriterion, ...
        commonOffArgs{:});
    diag.combinedMask = ismember(labelsBefore, diag.combinedLabels);
catch ME
    warning('Combined Clean RawData diagnostic pass failed: %s', ME.message);
end

end


function diag = localEmptyChannelDiagnosticResult(nScalp, labelsBefore) %#ok<INUSD>

diag = struct();
diag.flatlineMask = false(nScalp, 1);
diag.lineNoiseMask = false(nScalp, 1);
diag.correlationMask = false(nScalp, 1);
diag.combinedMask = false(nScalp, 1);
diag.flatlineLabels = strings(0, 1);
diag.flatlineIndices = [];
diag.lineNoiseLabels = strings(0, 1);
diag.lineNoiseIndices = [];
diag.correlationLabels = strings(0, 1);
diag.correlationIndices = [];
diag.combinedLabels = strings(0, 1);
diag.combinedIndices = [];

end


function [tableCsv, summaryCsv, interpretationCsv, plotDir, summaryString] = ...
    localRunChannelQCPersistence(cfg, participantID, outDir, badChannelTable, ...
    originalScalpLabels, EEG_ds, EEG_ica, EEG_erp)

originalScalpLabels = string(originalScalpLabels(:));
nScalp = numel(originalScalpLabels);
participantID = char(participantID);

nbchanDs = EEG_ds.nbchan;
nbchanIca = EEG_ica.nbchan;
nbchanErp = EEG_erp.nbchan;

if exist('pop_clean_rawdata', 'file') ~= 2
    error(['Clean RawData plugin function pop_clean_rawdata was not found. ', ...
        'Install/enable EEGLAB Clean RawData before using RunChannelQCPersistence.']);
end

stageNames = ["Downsampled_512Hz", "ICAtraining_1to30Hz", "ERPanalysis_0p1to20Hz"];
stageEEGs = {EEG_ds, EEG_ica, EEG_erp};

initCombined = logical(badChannelTable.FlaggedByCleanRawData);
initFlatline = logical(badChannelTable.FlaggedByFlatlineCriterion);
initLineNoise = logical(badChannelTable.FlaggedByLineNoiseCriterion);
initCorrelation = logical(badChannelTable.FlaggedByCorrelationCriterion);
initFlagReason = string(badChannelTable.FlagReason);

decisionTime = string(datestr(now));
allRows = table();
summaryRows = table();
summaryParts = strings(0, 1);
stageReasons = strings(nScalp, numel(stageNames));

for s = 1:numel(stageNames)

stageName = stageNames(s);
EEG_stage = stageEEGs{s};

try
    diag = localRunScalpChannelDiagnosticPasses(EEG_stage, cfg, originalScalpLabels, s == 1, char(stageName));
catch ME
    warning('Channel QC persistence diagnostic passes failed for %s: %s', stageName, ME.message);
    diag = localEmptyChannelDiagnosticResult(nScalp, originalScalpLabels);
end

flagReasonCol = strings(nScalp, 1);
for i = 1:nScalp
    flagReasonCol(i) = localBuildBadChannelFlagReason( ...
        diag.combinedMask(i), diag.flatlineMask(i), ...
        diag.lineNoiseMask(i), diag.correlationMask(i), true);
end
stageReasons(:, s) = flagReasonCol;

anyCriterionMask = diag.flatlineMask | diag.lineNoiseMask | diag.correlationMask | diag.combinedMask;
persistedAny = initCombined & anyCriterionMask;
flatlinePersisted = initFlatline & diag.flatlineMask;
lineNoisePersisted = initLineNoise & diag.lineNoiseMask;
correlationPersisted = initCorrelation & diag.correlationMask;

stageTable = table( ...
    repmat(string(participantID), nScalp, 1), ...
    repmat(stageName, nScalp, 1), ...
    (1:nScalp)', ...
    originalScalpLabels, ...
    initCombined, ...
    initFlatline, ...
    initLineNoise, ...
    initCorrelation, ...
    initFlagReason, ...
    diag.flatlineMask, ...
    diag.lineNoiseMask, ...
    diag.correlationMask, ...
    diag.combinedMask, ...
    flagReasonCol, ...
    persistedAny, ...
    flatlinePersisted, ...
    lineNoisePersisted, ...
    correlationPersisted, ...
    repmat(decisionTime, nScalp, 1), ...
    'VariableNames', { ...
        'ParticipantID', ...
        'Stage', ...
        'OriginalScalpIndex', ...
        'Label', ...
        'InitiallyFlaggedByBadChannelChecker', ...
        'InitiallyFlaggedByFlatlineCriterion', ...
        'InitiallyFlaggedByLineNoiseCriterion', ...
        'InitiallyFlaggedByCorrelationCriterion', ...
        'InitialFlagReason', ...
        'FlaggedByFlatlineCriterion', ...
        'FlaggedByLineNoiseCriterion', ...
        'FlaggedByCorrelationCriterion', ...
        'FlaggedByCombinedCleanRawData', ...
        'FlagReason', ...
        'PersistedFromInitialChecker', ...
        'FlatlinePersistedFromInitial', ...
        'LineNoisePersistedFromInitial', ...
        'CorrelationPersistedFromInitial', ...
        'DecisionTime'});

allRows = [allRows; stageTable]; %#ok<AGROW>

summaryRows = [summaryRows; table( ...
    string(participantID), ...
    stageName, ...
    nScalp, ...
    sum(initCombined), ...
    sum(initFlatline), ...
    sum(initLineNoise), ...
    sum(initCorrelation), ...
    sum(diag.flatlineMask), ...
    sum(diag.lineNoiseMask), ...
    sum(diag.correlationMask), ...
    sum(diag.combinedMask), ...
    sum(persistedAny), ...
    sum(flatlinePersisted), ...
    sum(lineNoisePersisted), ...
    sum(correlationPersisted), ...
    string(localLabelsFromMask(originalScalpLabels, diag.flatlineMask)), ...
    string(localLabelsFromMask(originalScalpLabels, diag.lineNoiseMask)), ...
    string(localLabelsFromMask(originalScalpLabels, diag.correlationMask)), ...
    string(localLabelsFromMask(originalScalpLabels, diag.combinedMask)), ...
    string(localLabelsFromMask(originalScalpLabels, persistedAny)), ...
    string(localLabelsFromMask(originalScalpLabels, flatlinePersisted)), ...
    string(localLabelsFromMask(originalScalpLabels, lineNoisePersisted)), ...
    string(localLabelsFromMask(originalScalpLabels, correlationPersisted)), ...
    decisionTime, ...
    'VariableNames', { ...
        'ParticipantID', ...
        'Stage', ...
        'NScalpChannelsAnalysed', ...
        'NInitiallyFlaggedByBadChannelChecker', ...
        'NInitiallyFlatlineFlagged', ...
        'NInitiallyLineNoiseFlagged', ...
        'NInitiallyCorrelationFlagged', ...
        'NFlaggedByFlatlineCriterion', ...
        'NFlaggedByLineNoiseCriterion', ...
        'NFlaggedByCorrelationCriterion', ...
        'NFlaggedByCombinedCleanRawData', ...
        'NInitialFlagsPersisted', ...
        'NFlatlineFlagsPersisted', ...
        'NLineNoiseFlagsPersisted', ...
        'NCorrelationFlagsPersisted', ...
        'FlaggedLabels_Flatline', ...
        'FlaggedLabels_LineNoise', ...
        'FlaggedLabels_Correlation', ...
        'FlaggedLabels_Combined', ...
        'PersistentLabels_Any', ...
        'PersistentLabels_Flatline', ...
        'PersistentLabels_LineNoise', ...
        'PersistentLabels_Correlation', ...
        'DecisionTime'})]; %#ok<AGROW>

summaryParts(end+1) = sprintf('%s: %d flatline, %d line-noise, %d correlation, %d persist', ...
    stageName, sum(diag.flatlineMask), sum(diag.lineNoiseMask), ...
    sum(diag.correlationMask), sum(persistedAny)); %#ok<AGROW>

end

if EEG_ds.nbchan ~= nbchanDs || EEG_ica.nbchan ~= nbchanIca || EEG_erp.nbchan ~= nbchanErp
    error('Channel QC persistence modified source dataset channel counts.');
end

tableCsv = fullfile(outDir, sprintf('%s_ChannelQCPersistence_Table.csv', participantID));
summaryCsv = fullfile(outDir, sprintf('%s_ChannelQCPersistence_Summary.csv', participantID));
interpretationCsv = fullfile(outDir, sprintf('%s_ChannelQCPersistence_Interpretation.csv', participantID));
plotDir = '';

writetable(allRows, tableCsv);
writetable(summaryRows, summaryCsv);

interpretationTable = localBuildChannelQCPersistenceInterpretation( ...
    participantID, badChannelTable, allRows, stageNames, stageReasons);
writetable(interpretationTable, interpretationCsv);

if cfg.ChannelQCPersistencePlot
    plotDir = fullfile(outDir, [participantID '_ChannelQCPersistence_Plots']);
    try
        localPlotChannelQCPersistenceHeatmap(allRows, badChannelTable, ...
            originalScalpLabels, stageNames, participantID, plotDir);
    catch ME
        warning('Channel QC persistence heatmap failed: %s', ME.message);
        plotDir = '';
    end
end

summaryString = strjoin(summaryParts, '; ');

localPrintChannelQCPersistenceSummary(summaryRows, tableCsv, summaryCsv, interpretationCsv);

end


function localPrintChannelQCPersistenceSummary(summaryRows, tableCsv, summaryCsv, interpretationCsv)

stageOrder = ["Downsampled_512Hz", "ICAtraining_1to30Hz", "ERPanalysis_0p1to20Hz"];

fprintf('\n================ CHANNEL QC PERSISTENCE SUMMARY ================\n\n');

for s = 1:numel(stageOrder)
    stageName = stageOrder(s);
    rowIdx = find(strcmp(summaryRows.Stage, stageName), 1, 'first');

    if isempty(rowIdx)
        nFlatline = 0;
        nLineNoise = 0;
        nCorrelation = 0;
    else
        nFlatline = summaryRows.NFlaggedByFlatlineCriterion(rowIdx);
        nLineNoise = summaryRows.NFlaggedByLineNoiseCriterion(rowIdx);
        nCorrelation = summaryRows.NFlaggedByCorrelationCriterion(rowIdx);
    end

    fprintf('%s:\n', char(stageName));
    fprintf('  %d flatline\n', nFlatline);
    fprintf('  %d line-noise\n', nLineNoise);
    fprintf('  %d correlation\n', nCorrelation);

    if s < numel(stageOrder)
        fprintf('\n');
    end
end

erpRowIdx = find(strcmp(summaryRows.Stage, "ERPanalysis_0p1to20Hz"), 1, 'first');
if isempty(erpRowIdx)
    nFlatlinePersisted = 0;
    nLineNoisePersisted = 0;
    nCorrelationPersisted = 0;
else
    nFlatlinePersisted = summaryRows.NFlatlineFlagsPersisted(erpRowIdx);
    nLineNoisePersisted = summaryRows.NLineNoiseFlagsPersisted(erpRowIdx);
    nCorrelationPersisted = summaryRows.NCorrelationFlagsPersisted(erpRowIdx);
end

fprintf('\nPersistent original flags into final ERP-analysis stage:\n');
fprintf('  Flatline: %d\n', nFlatlinePersisted);
fprintf('  Line-noise: %d\n', nLineNoisePersisted);
fprintf('  Correlation: %d\n', nCorrelationPersisted);

fprintf('\nFull persistence details saved to:\n');
fprintf('  %s\n', tableCsv);
fprintf('  %s\n', summaryCsv);
fprintf('  %s\n', interpretationCsv);
fprintf('===============================================================\n');

end


function labelStr = localLabelsFromMask(labels, mask)

labels = string(labels(:));
mask = logical(mask(:));
if ~any(mask)
    labelStr = '';
else
    labelStr = char(strjoin(labels(mask), ', '));
end

end


function interpretationTable = localBuildChannelQCPersistenceInterpretation( ...
    participantID, badChannelTable, allRows, stageNames, stageReasons)

originalScalpLabels = string(badChannelTable.Label);
nScalp = numel(originalScalpLabels);

initCombined = logical(badChannelTable.FlaggedByCleanRawData);
initFlatline = logical(badChannelTable.FlaggedByFlatlineCriterion);
initLineNoise = logical(badChannelTable.FlaggedByLineNoiseCriterion);
initCorrelation = logical(badChannelTable.FlaggedByCorrelationCriterion);
initFlagReason = string(badChannelTable.FlagReason);

everFlagged = initCombined | initFlatline | initLineNoise | initCorrelation;
for s = 1:numel(stageNames)
    stageRows = allRows(strcmp(allRows.Stage, stageNames(s)), :);
    everFlagged = everFlagged | stageRows.FlaggedByFlatlineCriterion | ...
        stageRows.FlaggedByLineNoiseCriterion | stageRows.FlaggedByCorrelationCriterion | ...
        stageRows.FlaggedByCombinedCleanRawData;
end

chanIdx = find(everFlagged);
if isempty(chanIdx)
    interpretationTable = table();
    return;
end

interpParticipant = strings(numel(chanIdx), 1);
interpIndex = zeros(numel(chanIdx), 1);
interpLabel = strings(numel(chanIdx), 1);
interpInitialReason = strings(numel(chanIdx), 1);
interpDownsampledReason = strings(numel(chanIdx), 1);
interpIcaReason = strings(numel(chanIdx), 1);
interpErpReason = strings(numel(chanIdx), 1);
interpFinal = strings(numel(chanIdx), 1);

erpRows = allRows(strcmp(allRows.Stage, "ERPanalysis_0p1to20Hz"), :);
dsRows = allRows(strcmp(allRows.Stage, "Downsampled_512Hz"), :);
icaRows = allRows(strcmp(allRows.Stage, "ICAtraining_1to30Hz"), :);

for k = 1:numel(chanIdx)
    i = chanIdx(k);
    interpParticipant(k) = string(participantID);
    interpIndex(k) = i;
    interpLabel(k) = originalScalpLabels(i);
    interpInitialReason(k) = initFlagReason(i);
    interpDownsampledReason(k) = stageReasons(i, 1);
    interpIcaReason(k) = stageReasons(i, 2);
    interpErpReason(k) = stageReasons(i, 3);

    interpFinal(k) = localBuildChannelQCInterpretationLabel( ...
        initCombined(i), initFlatline(i), initLineNoise(i), initCorrelation(i), ...
        dsRows.FlaggedByLineNoiseCriterion(i), ...
        icaRows.FlaggedByLineNoiseCriterion(i), ...
        erpRows.FlaggedByLineNoiseCriterion(i), ...
        erpRows.FlaggedByFlatlineCriterion(i), ...
        erpRows.FlaggedByLineNoiseCriterion(i), ...
        erpRows.FlaggedByCorrelationCriterion(i), ...
        erpRows.FlaggedByCombinedCleanRawData(i), ...
        erpRows.FlatlinePersistedFromInitial(i), ...
        erpRows.LineNoisePersistedFromInitial(i), ...
        erpRows.CorrelationPersistedFromInitial(i), ...
        dsRows.FlaggedByFlatlineCriterion(i) | dsRows.FlaggedByLineNoiseCriterion(i) | ...
            dsRows.FlaggedByCorrelationCriterion(i) | dsRows.FlaggedByCombinedCleanRawData(i), ...
        icaRows.FlaggedByFlatlineCriterion(i) | icaRows.FlaggedByLineNoiseCriterion(i) | ...
            icaRows.FlaggedByCorrelationCriterion(i) | icaRows.FlaggedByCombinedCleanRawData(i), ...
        erpRows.FlaggedByFlatlineCriterion(i) | erpRows.FlaggedByLineNoiseCriterion(i) | ...
            erpRows.FlaggedByCorrelationCriterion(i) | erpRows.FlaggedByCombinedCleanRawData(i));
end

interpretationTable = table( ...
    interpParticipant, ...
    interpIndex, ...
    interpLabel, ...
    interpInitialReason, ...
    interpDownsampledReason, ...
    interpIcaReason, ...
    interpErpReason, ...
    interpFinal, ...
    'VariableNames', { ...
        'ParticipantID', ...
        'OriginalScalpIndex', ...
        'Label', ...
        'InitialFlagReason', ...
        'DownsampledFlagReason', ...
        'ICAtrainingFlagReason', ...
        'ERPanalysisFlagReason', ...
        'FinalQCInterpretation'});

end


function label = localBuildChannelQCInterpretationLabel( ...
    initCombined, initFlatline, initLineNoise, initCorrelation, ...
    dsLineNoise, icaLineNoise, erpLineNoise, ...
    erpFlatline, erpLineNoiseFlag, erpCorrelation, erpCombined, ...
    erpFlatlinePersisted, erpLineNoisePersisted, erpCorrelationPersisted, ...
    dsAnyFlag, icaAnyFlag, erpAnyFlag)

erpAnyCriterion = erpFlatline || erpLineNoiseFlag || erpCorrelation || erpCombined;
nPersistTypes = double(erpFlatlinePersisted) + double(erpLineNoisePersisted) + double(erpCorrelationPersisted);
initiallyFlaggedAny = initCombined || initFlatline || initLineNoise || initCorrelation;
lineNoiseOnlyBeforeFiltering = dsLineNoise && ~icaLineNoise && ~erpLineNoise;

if nPersistTypes >= 2
    label = "Persistent multi-criterion warning";
elseif erpFlatlinePersisted
    label = "Persistent flatline warning";
elseif erpCorrelationPersisted
    label = "Persistent low-correlation warning";
elseif erpAnyCriterion
    label = "Still flagged in ERP-analysis data";
elseif lineNoiseOnlyBeforeFiltering
    label = "Line-noise only before filtering";
elseif initiallyFlaggedAny && ~dsAnyFlag && ~icaAnyFlag && ~erpAnyFlag
    label = "Initial-only warning";
else
    label = "Not flagged at any stage";
end

end


function localPlotChannelQCPersistenceHeatmap(allRows, badChannelTable, originalScalpLabels, stageNames, participantID, plotDir)

if ~exist(plotDir, 'dir')
    mkdir(plotDir);
end

originalScalpLabels = string(originalScalpLabels(:));
nScalp = numel(originalScalpLabels);

initAny = logical(badChannelTable.FlaggedByCleanRawData) | ...
    logical(badChannelTable.FlaggedByFlatlineCriterion) | ...
    logical(badChannelTable.FlaggedByLineNoiseCriterion) | ...
    logical(badChannelTable.FlaggedByCorrelationCriterion);

stageAny = false(nScalp, 1);
for s = 1:numel(stageNames)
    stageRows = allRows(strcmp(allRows.Stage, stageNames(s)), :);
    stageAny = stageAny | stageRows.FlaggedByFlatlineCriterion | ...
        stageRows.FlaggedByLineNoiseCriterion | stageRows.FlaggedByCorrelationCriterion;
end

chanIdx = find(initAny | stageAny);
if isempty(chanIdx)
    return;
end

colLabels = strings(0, 1);
for s = 1:numel(stageNames)
    shortStage = localChannelQCStageShortName(stageNames(s));
    colLabels = [colLabels, ...
        shortStage + " Flatline", ...
        shortStage + " LineNoise", ...
        shortStage + " Correlation"]; %#ok<AGROW>
end

heatMat = zeros(numel(chanIdx), numel(colLabels));
rowLabels = strings(numel(chanIdx), 1);

for r = 1:numel(chanIdx)
    i = chanIdx(r);
    rowLabels(r) = originalScalpLabels(i);
    col = 1;
    for s = 1:numel(stageNames)
        stageRows = allRows(strcmp(allRows.Stage, stageNames(s)), :);
        heatMat(r, col) = double(stageRows.FlaggedByFlatlineCriterion(i));
        heatMat(r, col + 1) = double(stageRows.FlaggedByLineNoiseCriterion(i));
        heatMat(r, col + 2) = double(stageRows.FlaggedByCorrelationCriterion(i));
        col = col + 3;
    end
end

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1200 max(400, 28 * numel(chanIdx))]);
imagesc(heatMat);
colormap(fig, [1 1 1; 0.85 0.33 0.10]);
caxis([0 1]);
set(gca, 'XTick', 1:numel(colLabels), 'XTickLabel', colLabels, ...
    'XTickLabelRotation', 45, 'YTick', 1:numel(chanIdx), 'YTickLabel', rowLabels);
title(sprintf('%s | Channel QC persistence heatmap', participantID), 'Interpreter', 'none');
xlabel('Stage / criterion');
ylabel('Channel');

pngFile = fullfile(plotDir, sprintf('%s_ChannelQCPersistence_Heatmap.png', participantID));
exportgraphics(fig, pngFile, 'Resolution', 150);
close(fig);

end


function shortName = localChannelQCStageShortName(stageName)

switch char(stageName)
    case 'Downsampled_512Hz'
        shortName = "Downsampled";
    case 'ICAtraining_1to30Hz'
        shortName = "ICA";
    case 'ERPanalysis_0p1to20Hz'
        shortName = "ERP";
    otherwise
        shortName = string(stageName);
end

end


function [stageTable, lineNoisePlotDir, summaryString] = localComputeLineNoiseQC( ...
    EEG, cfg, participantID, stageName, originalScalpLabels, ...
    flaggedBadScalpLabels, flaggedLineNoiseLabels, outDir, lineNoisePlotDir)

originalScalpLabels = string(originalScalpLabels(:));
flaggedBadScalpLabels = string(flaggedBadScalpLabels(:));
flaggedLineNoiseLabels = string(flaggedLineNoiseLabels(:));

nScalp = numel(originalScalpLabels);
scalpIdx = localFindExistingChannelsByLabels(EEG, originalScalpLabels);
stageNote = localGetLineNoiseStageNote(stageName, cfg);
decisionTime = string(datestr(now));

neighLo = cfg.LineNoiseNeighbourHz(1);
neighHi = cfg.LineNoiseNeighbourHz(2);
exclLo = cfg.LineNoiseExcludeHz(1);
exclHi = cfg.LineNoiseExcludeHz(2);
neighbourBandStr = sprintf('%.0f-%.0f; %.0f-%.0f', neighLo, exclLo, exclHi, neighHi);

participantCol = repmat(string(participantID), nScalp, 1);
stageCol = repmat(string(stageName), nScalp, 1);
origIdxCol = (1:nScalp)';
labelCol = originalScalpLabels;
badCheckerCol = ismember(originalScalpLabels, flaggedBadScalpLabels);
lineNoiseFlagCol = ismember(originalScalpLabels, flaggedLineNoiseLabels);
lineFreqCol = repmat(cfg.LineNoiseFreqHz, nScalp, 1);
powerAtLineCol = nan(nScalp, 1);
neighbourBandCol = repmat(string(neighbourBandStr), nScalp, 1);
neighbourMedCol = nan(nScalp, 1);
ratioCol = nan(nScalp, 1);
ratioDbCol = nan(nScalp, 1);
stageNoteCol = repmat(string(stageNote), nScalp, 1);
decisionCol = repmat(decisionTime, nScalp, 1);

psdMatrix = [];
freqs = [];

for i = 1:nScalp
    chIdx = scalpIdx(i);
    x = double(EEG.data(chIdx, :));
    x = x(:);
    [psd, f] = pwelch(x, [], [], [], EEG.srate);
    psd = psd(:);
    f = f(:);

    if isempty(freqs)
        freqs = f;
        psdMatrix = nan(numel(f), nScalp);
    end

    psdMatrix(:, i) = psd;

    [~, idxLine] = min(abs(f - cfg.LineNoiseFreqHz));
    neighbourIdx = (f >= neighLo & f < exclLo) | (f > exclHi & f <= neighHi);

    powerAtLineCol(i) = psd(idxLine);
    if any(neighbourIdx)
        neighbourMedCol(i) = median(psd(neighbourIdx), 'omitnan');
    else
        neighbourMedCol(i) = NaN;
    end

    if neighbourMedCol(i) > 0 && isfinite(neighbourMedCol(i))
        ratioCol(i) = powerAtLineCol(i) / neighbourMedCol(i);
        if ratioCol(i) > 0
            ratioDbCol(i) = 10 * log10(ratioCol(i));
        end
    end
end

stageTable = table( ...
    participantCol, stageCol, origIdxCol, labelCol, badCheckerCol, lineNoiseFlagCol, ...
    lineFreqCol, powerAtLineCol, neighbourBandCol, neighbourMedCol, ratioCol, ratioDbCol, ...
    stageNoteCol, decisionCol, ...
    'VariableNames', { ...
        'ParticipantID', ...
        'Stage', ...
        'OriginalScalpIndex', ...
        'Label', ...
        'IsFlaggedByBadChannelChecker', ...
        'IsFlaggedByLineNoiseCriterion', ...
        'LineNoiseFreqHz', ...
        'PowerAtLineNoiseHz', ...
        'NeighbourBandHz', ...
        'NeighbourMedianPower', ...
        'LineNoiseRatio', ...
        'LineNoiseRatioDb', ...
        'StageNote', ...
        'DecisionTime'});

summaryString = localLineNoiseQCStageSummaryString(stageTable);

fprintf('\nLine-noise QC: %s\n', stageName);
fprintf('  Median %g Hz ratio, all scalp channels: %.2f dB\n', ...
    cfg.LineNoiseFreqHz, median(stageTable.LineNoiseRatioDb, 'omitnan'));
if any(isfinite(stageTable.LineNoiseRatioDb))
    [maxDbAll, maxIdxAll] = max(stageTable.LineNoiseRatioDb, [], 'omitnan');
    fprintf('  Worst scalp channel: %s, %.2f dB\n', stageTable.Label(maxIdxAll), maxDbAll);
else
    fprintf('  Worst scalp channel: (none)\n');
end

flaggedRows = stageTable(stageTable.IsFlaggedByLineNoiseCriterion, :);
if isempty(flaggedRows)
    fprintf('  Worst flagged line-noise channel: (none)\n');
else
    [maxDbFlag, maxIdxFlag] = max(flaggedRows.LineNoiseRatioDb, [], 'omitnan');
    fprintf('  Worst flagged line-noise channel: %s, %.2f dB\n', ...
        flaggedRows.Label(maxIdxFlag), maxDbFlag);
end
fprintf('  Note: %s\n', stageNote);

if cfg.LineNoiseQCPlot
    try
        if isempty(lineNoisePlotDir)
            lineNoisePlotDir = fullfile(outDir, sprintf('%s_LineNoiseQC_Plots', participantID));
        end
        if ~exist(lineNoisePlotDir, 'dir')
            mkdir(lineNoisePlotDir);
        end
        localPlotLineNoiseQCStage(freqs, psdMatrix, stageTable, cfg, participantID, stageName, lineNoisePlotDir);
    catch ME
        warning('Line-noise QC plot failed for stage %s: %s', stageName, ME.message);
    end
end

end


function summaryString = localLineNoiseQCStageSummaryString(stageTable)

medianDb = median(stageTable.LineNoiseRatioDb, 'omitnan');
if any(isfinite(stageTable.LineNoiseRatioDb))
    [maxDb, maxIdx] = max(stageTable.LineNoiseRatioDb, [], 'omitnan');
    worstLabel = stageTable.Label(maxIdx);
    summaryString = sprintf('median=%.2f dB; worst=%s %.2f dB', medianDb, worstLabel, maxDb);
else
    summaryString = 'no valid line-noise ratios';
end

end


function summaryTable = localSummarizeLineNoiseQC(lineNoiseQCTable, participantID, cfg)

stages = unique(lineNoiseQCTable.Stage, 'stable');
nStages = numel(stages);
summaryTable = table();

for s = 1:nStages
    stageName = stages(s);
    stageRows = lineNoiseQCTable(lineNoiseQCTable.Stage == stageName, :);
    flaggedLineRows = stageRows(stageRows.IsFlaggedByLineNoiseCriterion, :);

    row = table( ...
        string(participantID), ...
        stageName, ...
        cfg.LineNoiseFreqHz, ...
        height(stageRows), ...
        sum(stageRows.IsFlaggedByBadChannelChecker), ...
        sum(stageRows.IsFlaggedByLineNoiseCriterion), ...
        median(stageRows.LineNoiseRatioDb, 'omitnan'), ...
        max(stageRows.LineNoiseRatioDb, [], 'omitnan'), ...
        string(localWorstLineNoiseChannelLabel(stageRows)), ...
        localWorstLineNoiseChannelDb(stageRows), ...
        localFlaggedLineNoiseMedianDb(flaggedLineRows), ...
        localFlaggedLineNoiseMaxDb(flaggedLineRows), ...
        string(localWorstLineNoiseChannelLabel(flaggedLineRows)), ...
        localWorstLineNoiseChannelDb(flaggedLineRows), ...
        string(datestr(now)), ...
        'VariableNames', { ...
            'ParticipantID', ...
            'Stage', ...
            'LineNoiseFreqHz', ...
            'NScalpChannelsAnalysed', ...
            'NChannelsFlaggedByBadChannelChecker', ...
            'NChannelsFlaggedByLineNoiseCriterion', ...
            'MedianLineNoiseRatioDb_AllScalp', ...
            'MaxLineNoiseRatioDb_AllScalp', ...
            'WorstChannel_AllScalp', ...
            'WorstChannelLineNoiseRatioDb_AllScalp', ...
            'MedianLineNoiseRatioDb_FlaggedLineNoiseChannels', ...
            'MaxLineNoiseRatioDb_FlaggedLineNoiseChannels', ...
            'WorstFlaggedLineNoiseChannel', ...
            'WorstFlaggedLineNoiseRatioDb', ...
            'DecisionTime'});

    summaryTable = [summaryTable; row]; %#ok<AGROW>
end

end


function worstLabel = localWorstLineNoiseChannelLabel(stageRows)

if isempty(stageRows) || ~any(isfinite(stageRows.LineNoiseRatioDb))
    worstLabel = '';
    return;
end
[~, idx] = max(stageRows.LineNoiseRatioDb, [], 'omitnan');
worstLabel = char(stageRows.Label(idx));

end


function worstDb = localWorstLineNoiseChannelDb(stageRows)

if isempty(stageRows) || ~any(isfinite(stageRows.LineNoiseRatioDb))
    worstDb = NaN;
    return;
end
worstDb = max(stageRows.LineNoiseRatioDb, [], 'omitnan');

end


function medDb = localFlaggedLineNoiseMedianDb(flaggedLineRows)

if isempty(flaggedLineRows) || ~any(isfinite(flaggedLineRows.LineNoiseRatioDb))
    medDb = NaN;
else
    medDb = median(flaggedLineRows.LineNoiseRatioDb, 'omitnan');
end

end


function maxDb = localFlaggedLineNoiseMaxDb(flaggedLineRows)

if isempty(flaggedLineRows) || ~any(isfinite(flaggedLineRows.LineNoiseRatioDb))
    maxDb = NaN;
else
    maxDb = max(flaggedLineRows.LineNoiseRatioDb, [], 'omitnan');
end

end


function stageNote = localGetLineNoiseStageNote(stageName, cfg)

switch stageName
    case 'Downsampled_512Hz'
        stageNote = sprintf('Broadband/downsampled data at %.0f Hz before stage-specific low-pass', cfg.TargetSrate);
    case 'ICAtraining_1to30Hz'
        stageNote = sprintf('%g Hz expected to be attenuated by the %.0f Hz low-pass', ...
            cfg.LineNoiseFreqHz, cfg.ICAFilterHz(2));
    case 'ERPanalysis_0p1to20Hz'
        stageNote = sprintf('%g Hz expected to be strongly attenuated by the %.0f Hz low-pass', ...
            cfg.LineNoiseFreqHz, cfg.ERPFilterHz(2));
    otherwise
        stageNote = 'Line-noise QC stage';
end

end


function localPlotLineNoiseQCStage(freqs, psdMatrix, stageTable, cfg, participantID, stageName, lineNoisePlotDir)

medianAll = median(psdMatrix, 2, 'omitnan');
flagMask = stageTable.IsFlaggedByLineNoiseCriterion;
if any(flagMask)
    medianFlagged = median(psdMatrix(:, flagMask), 2, 'omitnan');
else
    medianFlagged = [];
end

fig = figure('Visible', 'off');
plot(freqs, 10 * log10(medianAll), 'LineWidth', 1.5);
hold on;
if ~isempty(medianFlagged)
    plot(freqs, 10 * log10(medianFlagged), 'LineWidth', 1.2, 'LineStyle', '--');
    legend({'Median all scalp', 'Median flagged line-noise'}, 'Location', 'best');
else
    legend({'Median all scalp'}, 'Location', 'best');
end
xline(cfg.LineNoiseFreqHz, 'r--', sprintf('%g Hz', cfg.LineNoiseFreqHz));
xlim([1 60]);
xlabel('Frequency (Hz)');
ylabel('Power (dB)');
title(sprintf('%s Line-noise QC: %s', participantID, stageName));
grid on;
hold off;

pngFile = fullfile(lineNoisePlotDir, sprintf('%s_LineNoiseQC_%s.png', participantID, stageName));
exportgraphics(fig, pngFile, 'Resolution', 150);
close(fig);

end


function idx = localFindExistingChannelsByLabels(EEG, labels)

labels = string(labels(:));
allLabels = string({EEG.chanlocs.labels});
idx = zeros(1, numel(labels));

for i = 1:numel(labels)
    hit = find(strcmpi(allLabels, labels(i)), 1, 'first');
    if isempty(hit)
        error('Could not find channel label in dataset: %s', labels(i));
    end
    idx(i) = hit;
end

end


function localValidateScalpChanlocs(scalpChanlocs, minFractionValid)

if nargin < 2
    minFractionValid = 0.80;
end

nScalp = numel(scalpChanlocs);
if nScalp < 1
    error('No scalp channel locations available for validation.');
end

nValid = 0;
for i = 1:nScalp
  loc = scalpChanlocs(i);
  hasXYZ = isfield(loc, 'X') && isfield(loc, 'Y') && isfield(loc, 'Z') && ...
      localChanlocFieldUsable(loc.X) && localChanlocFieldUsable(loc.Y) && localChanlocFieldUsable(loc.Z);
  hasTheta = isfield(loc, 'theta') && isfield(loc, 'radius') && ...
      localChanlocFieldUsable(loc.theta) && localChanlocFieldUsable(loc.radius);
  if hasXYZ || hasTheta
      nValid = nValid + 1;
  end
end

fracValid = nValid / nScalp;
if fracValid < minFractionValid
    error(['Scalp channel locations appear missing or unusable (%d/%d channels with coordinates). ', ...
        'Clean RawData correlation-based channel checking requires ', ...
        'valid scalp channel locations (X/Y/Z or theta/radius).'], nValid, nScalp);
end

end


function usable = localChanlocFieldUsable(value)

if isempty(value)
    usable = false;
elseif isnumeric(value) && isscalar(value) && isnan(value)
    usable = false;
else
    usable = true;
end

end


function EEG = localClearIcaFields(EEG)

EEG.icaact = [];
EEG.icaweights = [];
EEG.icasphere = [];
EEG.icawinv = [];
EEG.icachansind = [];
EEG = eeg_checkset(EEG);

end


function EEG = localFixChanlocsForICLabel(EEG)

if isfield(EEG, 'chaninfo')
if isfield(EEG.chaninfo, 'plotrad')
EEG.chaninfo = rmfield(EEG.chaninfo, 'plotrad');
end
if isfield(EEG.chaninfo, 'shrink')
EEG.chaninfo = rmfield(EEG.chaninfo, 'shrink');
end
end

try
EEG = pop_chanedit(EEG, 'lookup', 'standard-10-5-cap385.elp');
catch ME
warning('Could not load standard channel locations: %s', ME.message);
end

end

function T_ic = localMakeICLabelTable(EEG)

if ~isfield(EEG.etc, 'ic_classification') || ...
        ~isfield(EEG.etc.ic_classification, 'ICLabel') || ...
        ~isfield(EEG.etc.ic_classification.ICLabel, 'classifications') || ...
        ~isfield(EEG.etc.ic_classification.ICLabel, 'classes')
    error('ICLabel classifications not found in EEG.etc.');
end

classMat = EEG.etc.ic_classification.ICLabel.classifications;
classNames = string(EEG.etc.ic_classification.ICLabel.classes);
classNames = classNames(:);

[bestProb, bestClassIdx] = max(classMat, [], 2);

nIC = size(classMat, 1);

IC = (1:nIC)';
BestClass = string(classNames(bestClassIdx));
BestClass = BestClass(:);
BestPct = bestProb(:) * 100;

BrainPct = localICLabelClassPct(classMat, classNames, 'Brain');
MusclePct = localICLabelClassPct(classMat, classNames, 'Muscle');
EyePct = localICLabelClassPct(classMat, classNames, 'Eye');
HeartPct = localICLabelClassPct(classMat, classNames, 'Heart');
LineNoisePct = localICLabelClassPct(classMat, classNames, 'Line Noise');
ChannelNoisePct = localICLabelClassPct(classMat, classNames, 'Channel Noise');
OtherPct = localICLabelClassPct(classMat, classNames, 'Other');

T_ic = table( ...
    IC, ...
    BestClass, ...
    BestPct, ...
    BrainPct, ...
    MusclePct, ...
    EyePct, ...
    HeartPct, ...
    LineNoisePct, ...
    ChannelNoisePct, ...
    OtherPct, ...
    'VariableNames', {'IC','BestClass','BestPct','BrainPct','MusclePct','EyePct','HeartPct','LineNoisePct','ChannelNoisePct','OtherPct'});

end


function pctCol = localICLabelClassPct(classMat, classNames, classLabel)

colIdx = find(strcmpi(classNames, classLabel), 1, 'first');
if isempty(colIdx)
    error('ICLabel class not found: %s', classLabel);
end
pctCol = classMat(:, colIdx) * 100;

end


function [autoComponents, autoSelectionTable] = localGetICLabelAutoRejectComponents(EEG, classesToReject, threshold)

if ~isfield(EEG.etc, 'ic_classification') || ...
        ~isfield(EEG.etc.ic_classification, 'ICLabel') || ...
        ~isfield(EEG.etc.ic_classification.ICLabel, 'classifications') || ...
        ~isfield(EEG.etc.ic_classification.ICLabel, 'classes')
    error('ICLabel classifications not found in EEG.etc.');
end

classMat = EEG.etc.ic_classification.ICLabel.classifications;
classNames = string(EEG.etc.ic_classification.ICLabel.classes);
nIC = size(classMat, 1);

rejectCols = zeros(1, numel(classesToReject));
for c = 1:numel(classesToReject)
    hit = find(strcmpi(classNames, classesToReject{c}), 1, 'first');
    if isempty(hit)
        error('ICLabel class not found: %s', classesToReject{c});
    end
    rejectCols(c) = hit;
end

rejectMask = false(nIC, 1);
reasons = strings(nIC, 1);
thrPct = threshold * 100;

for i = 1:nIC
    reasonParts = strings(0, 1);
    for c = 1:numel(classesToReject)
        prob = classMat(i, rejectCols(c));
        if prob >= threshold
            rejectMask(i) = true;
            reasonParts(end+1) = sprintf('%s >= %.0f%%', classesToReject{c}, thrPct); %#ok<AGROW>
        end
    end
    if rejectMask(i)
        reasons(i) = strjoin(reasonParts, '; ');
    else
        reasons(i) = "";
    end
end

autoComponents = find(rejectMask)';
autoSelectionTable = localMakeICLabelTable(EEG);
autoSelectionTable.AutoReject = rejectMask;
autoSelectionTable.AutoRejectReason = reasons;

end

function localCheckIcaTransferCompatibility(EEG_source, EEG_target)

if EEG_source.nbchan ~= EEG_target.nbchan
error('ICA source/target channel counts do not match.');
end

if EEG_source.pnts ~= EEG_target.pnts
error('ICA source/target point counts do not match.');
end

if EEG_source.srate ~= EEG_target.srate
error('ICA source/target sampling rates do not match.');
end

labelsSource = string({EEG_source.chanlocs.labels});
labelsTarget = string({EEG_target.chanlocs.labels});

if ~isequal(labelsSource(:), labelsTarget(:))
error('ICA source/target channel labels do not match.');
end

end

function compTag = localComponentTag(componentsToRemove)

if isempty(componentsToRemove)
compTag = 'NoICs';
else
compTag = sprintf('ICs%s', strjoin(string(componentsToRemove), 'to'));
end

end

function varMap = localInferBehaviourVars(T, cfg)

vars = string(T.Properties.VariableNames);

varMap = struct();

if ~isempty(char(cfg.PASVar))
varMap.PASVar = char(cfg.PASVar);
else
varMap.PASVar = localFindVar(vars, ["PAS","pas","pasResp","pasResponse","PASresponse","q1","Q1","q1Resp","q1Response","q1PAS"], true, 'PAS response');
end

if ~isempty(char(cfg.LocCorrectVar))
varMap.LocCorrectVar = char(cfg.LocCorrectVar);
else
varMap.LocCorrectVar = localFindVar(vars, ["locCorrect","localisationCorrect","localizationCorrect","isLocCorrect","locAcc","localisationAcc","localizationAcc","q2Correct"], true, 'localisation correctness');
end

if ~isempty(char(cfg.LocRespVar))
varMap.LocRespVar = char(cfg.LocRespVar);
else
varMap.LocRespVar = localFindVar(vars, ["locResp","locResponse","localisationResp","localizationResp","locChoice","q2","Q2","q2Resp","q2Response"], false, 'localisation response');
end

if ~isempty(char(cfg.IsChangeVar))
varMap.IsChangeVar = char(cfg.IsChangeVar);
else
varMap.IsChangeVar = localFindVar(vars, ["isChange","isChangeTrial","changeTrial","changePresent","changed","isChanged","trialType","trialCondition","condition"], true, 'change/no-change trial type');
end

end

function varName = localFindVar(vars, candidates, required, purpose)

varName = '';

normVars = lower(regexprep(vars, '[^a-zA-Z0-9]', ''));
normCandidates = lower(regexprep(candidates, '[^a-zA-Z0-9]', ''));

for c = 1:numel(normCandidates)
hit = find(normVars == normCandidates(c), 1, 'first');
if ~isempty(hit)
varName = char(vars(hit));
return;
end
end

if required
fprintf('\nCould not identify behavioural variable for: %s\n', purpose);
fprintf('Available variables:\n');
disp(vars');
error('Please pass the correct variable name as an input parameter.');
end

end

function isCorrect = localColumnToLogicalCorrect(x)

if islogical(x)
isCorrect = x(:);
elseif isnumeric(x)
isCorrect = x(:) ~= 0;
else
s = upper(strtrim(string(x(:))));
isCorrect = s == "1" | s == "TRUE" | s == "CORRECT" | s == "YES" | s == "Y";
end

end

function isChange = localColumnToLogicalChange(x)

if islogical(x)
isChange = x(:);
elseif isnumeric(x)
isChange = x(:) ~= 0;
else
s = upper(strtrim(string(x(:))));
isChange = s == "1" | s == "TRUE" | s == "CHANGE" | s == "CHG" | s == "C" | ...
(contains(s, "CHANGE") & ~contains(s, "NO"));
end

end

function [trials, audit] = localReconstructALEX01Trials(EEG, T_beh, cfg)
% Reconstruct ALEX01 S1 onset from each recorded ISI-onset marker (22).
% Preferred duration source is actual PTB timing tISI-tS1. Falls back to
% durSec, then durFrames/DisplayRefreshHz.

eventNums = arrayfun(@(e) localEventTypeToNumber(e.type), EEG.event);
isiIdx = find(eventNums == cfg.RecordedISIAnchorCode);

n = numel(isiIdx);
if n ~= cfg.ExpectedMainTrials
    error('Expected %d code-%d ISI anchors but found %d.', ...
        cfg.ExpectedMainTrials, cfg.RecordedISIAnchorCode, n);
end
if height(T_beh) ~= n
    error('Behavioural rows (%d) do not match ISI anchors (%d).', height(T_beh), n);
end

vars = string(T_beh.Properties.VariableNames);
[timingSource, s1DurationSec] = localGetALEX01S1Durations(T_beh, vars, cfg);

trials = struct();
trials.family = repmat("ALEX01_recovery", n, 1);
trials.s1Code = repmat(cfg.ReconstructedS1Code, n, 1);
trials.s2CodeExpected = repmat(cfg.RecordedS2Code, n, 1);
trials.pasCodesExpected = repmat(string(mat2str(cfg.RecordedPASCodes)), n, 1);
trials.locCodesExpected = repmat(string(mat2str(cfg.RecordedLocCodes)), n, 1);
trials.s1EventIdx = isiIdx(:); % source event used only as a struct template
trials.s2EventIdx = nan(n,1);
trials.s1Latency = nan(n,1);
trials.s2Latency = nan(n,1);
trials.pasCode = nan(n,1);
trials.pasResp = nan(n,1);
trials.locCode = nan(n,1);
trials.locResp = nan(n,1);
trials.q2Code = nan(n,1);
trials.q2EventIdx = nan(n,1);
trials.q2Latency = nan(n,1);
trials.trialEndCode = nan(n,1);
trials.trialEndEventIdx = nan(n,1);
trials.trialEndLatency = nan(n,1);

isiLatency = nan(n,1); gapLatency = nan(n,1); q1Latency = nan(n,1);
eegIsiToS2Ms = nan(n,1); csvIsiToS2Ms = nan(n,1); isiToS2DiffMs = nan(n,1);
eegS2ToGapMs = nan(n,1); csvS2ToGapMs = nan(n,1); s2ToGapDiffMs = nan(n,1);

for t = 1:n
    startIdx = isiIdx(t);
    if t < n, stopIdx = isiIdx(t+1)-1; else, stopIdx = numel(EEG.event); end
    segIdx = startIdx:stopIdx;
    segNums = eventNums(segIdx);

    s2Rel = find(segNums == cfg.RecordedS2Code, 1, 'first');
    gapRel = find(segNums == cfg.RecordedGapCode, 1, 'first');
    q1Rel = find(segNums == cfg.RecordedQ1Code, 1, 'first');
    pasRel = find(ismember(segNums, cfg.RecordedPASCodes), 1, 'first');
    locRel = find(ismember(segNums, cfg.RecordedLocCodes), 1, 'first');
    % The core timing/PAS chain survived for all 600 trials. Localisation
    % response triggers (51-54) were only partially captured in ALEX01, so
    % they are optional audit markers rather than required anchors.
    if isempty(s2Rel) || isempty(gapRel) || isempty(q1Rel) || isempty(pasRel)
        missingParts = strings(0,1);
        if isempty(s2Rel), missingParts(end+1) = "S2(23)"; end
        if isempty(gapRel), missingParts(end+1) = "Gap(24)"; end
        if isempty(q1Rel), missingParts(end+1) = "Q1(31)"; end
        if isempty(pasRel), missingParts(end+1) = "PAS(41-44)"; end
        error('ALEX01 trial %d is missing required surviving marker(s): %s.', ...
            t, strjoin(missingParts, ', '));
    end
    if ~(s2Rel < gapRel && gapRel < q1Rel && q1Rel < pasRel)
        error('ALEX01 trial %d core surviving trigger order is invalid.', t);
    end
    if ~isempty(locRel) && locRel <= pasRel
        warning('ALEX01 trial %d has a LOC marker before/at PAS; ignoring that LOC marker.', t);
        locRel = [];
    end

    isiLatency(t) = EEG.event(startIdx).latency;
    trials.s1Latency(t) = isiLatency(t) - s1DurationSec(t) * EEG.srate;
    if trials.s1Latency(t) < 1
        error('Trial %d reconstructed S1 latency falls before dataset start.', t);
    end
    trials.s2EventIdx(t) = segIdx(s2Rel);
    trials.s2Latency(t) = EEG.event(segIdx(s2Rel)).latency;
    gapLatency(t) = EEG.event(segIdx(gapRel)).latency;
    q1Latency(t) = EEG.event(segIdx(q1Rel)).latency;
    trials.pasCode(t) = segNums(pasRel);
    trials.pasResp(t) = segNums(pasRel) - 40;
    if ~isempty(locRel)
        trials.locCode(t) = segNums(locRel);
        trials.locResp(t) = segNums(locRel) - 50;
    end

    eegIsiToS2Ms(t) = (trials.s2Latency(t)-isiLatency(t))/EEG.srate*1000;
    eegS2ToGapMs(t) = (gapLatency(t)-trials.s2Latency(t))/EEG.srate*1000;
end

% Optional PTB interval validation when timing columns exist.
[tS1, okS1] = localNumericColumn(T_beh, vars, ["tS1","s1OnsetTime"]);
[tISI, okISI] = localNumericColumn(T_beh, vars, ["tISI","isiOnsetTime"]);
[tS2, okS2] = localNumericColumn(T_beh, vars, ["tS2","s2OnsetTime"]);
[tGap, okGap] = localNumericColumn(T_beh, vars, ["tGap","gapOnsetTime"]);
if okISI && okS2
    csvIsiToS2Ms = (tS2-tISI)*1000;
    isiToS2DiffMs = eegIsiToS2Ms-csvIsiToS2Ms;
end
if okS2 && okGap
    csvS2ToGapMs = (tGap-tS2)*1000;
    s2ToGapDiffMs = eegS2ToGapMs-csvS2ToGapMs;
end

if any(isfinite(isiToS2DiffMs)) && max(abs(isiToS2DiffMs),[],'omitnan') > cfg.RecoveryTimingToleranceMs
    warning('ALEX01 maximum EEG-vs-CSV ISI-to-S2 discrepancy is %.3f ms (tolerance %.3f ms).', ...
        max(abs(isiToS2DiffMs),[],'omitnan'), cfg.RecoveryTimingToleranceMs);
end
if any(isfinite(s2ToGapDiffMs)) && max(abs(s2ToGapDiffMs),[],'omitnan') > cfg.RecoveryTimingToleranceMs
    warning('ALEX01 maximum EEG-vs-CSV S2-to-gap discrepancy is %.3f ms (tolerance %.3f ms).', ...
        max(abs(s2ToGapDiffMs),[],'omitnan'), cfg.RecoveryTimingToleranceMs);
end

trial = (1:n)';
locTriggerPresent = isfinite(trials.locCode);
audit = table(trial, repmat(string(timingSource),n,1), s1DurationSec, ...
    isiIdx(:), isiLatency, trials.s1Latency, repmat(cfg.ReconstructedS1Code,n,1), ...
    trials.s2EventIdx, trials.s2Latency, gapLatency, q1Latency, ...
    trials.pasCode, trials.pasResp, locTriggerPresent, trials.locCode, trials.locResp, ...
    eegIsiToS2Ms, csvIsiToS2Ms, isiToS2DiffMs, ...
    eegS2ToGapMs, csvS2ToGapMs, s2ToGapDiffMs, ...
    'VariableNames', {'Trial','S1DurationSource','S1DurationSec','ISIEventIdx','ISILatency', ...
    'ReconstructedS1Latency','ReconstructedS1Code','S2EventIdx','S2Latency','GapLatency','Q1Latency', ...
    'PASCode','PASResp','LocTriggerPresent','LocCode','LocResp','EEG_ISI_to_S2_ms','CSV_ISI_to_S2_ms', ...
    'ISI_to_S2_Difference_ms','EEG_S2_to_Gap_ms','CSV_S2_to_Gap_ms','S2_to_Gap_Difference_ms'});
end

function [source, durSec] = localGetALEX01S1Durations(T, vars, cfg)
[tS1, okS1] = localNumericColumn(T, vars, ["tS1","s1OnsetTime"]);
[tISI, okISI] = localNumericColumn(T, vars, ["tISI","isiOnsetTime"]);
if okS1 && okISI && all(isfinite(tS1)) && all(isfinite(tISI)) && all(tISI > tS1)
    durSec = tISI-tS1; source = 'tISI_minus_tS1'; return;
end
[durSec, okDurSec] = localNumericColumn(T, vars, ["durSec","durationSec","s1DurationSec"]);
if okDurSec && all(isfinite(durSec)) && all(durSec > 0)
    source = 'durSec'; return;
end
[durFrames, okFrames] = localNumericColumn(T, vars, ["actualS1Frames","durFrames","durationFrames"]);
if okFrames && all(isfinite(durFrames)) && all(durFrames > 0)
    durSec = durFrames/cfg.DisplayRefreshHz; source = 'frames_over_refresh'; return;
end
error('Could not reconstruct S1 duration: need valid tS1/tISI, durSec, or durFrames/actualS1Frames columns.');
end

function [x, found] = localNumericColumn(T, vars, candidates)
x = []; found = false;
normVars = lower(regexprep(vars, '[^a-zA-Z0-9]', ''));
normCandidates = lower(regexprep(candidates, '[^a-zA-Z0-9]', ''));
for i = 1:numel(normCandidates)
    hit = find(normVars == normCandidates(i),1,'first');
    if ~isempty(hit)
        try
            x = double(T.(char(vars(hit))));
            x = x(:); found = true; return;
        catch
        end
    end
end
end

function trials = localExtractTriggeredTrials(EEG, varargin)

p = inputParser;
addParameter(p, 'FamilyName', 'main', @(x) ischar(x) || isstring(x));
addParameter(p, 'S1Code', 21, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'S2Code', 23, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'PASCodes', 41:44, @(x) isnumeric(x) && isvector(x));
addParameter(p, 'LocCodes', 61:64, @(x) isnumeric(x) && isvector(x));
addParameter(p, 'PASBase', 40, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'LocBase', 60, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'Q1Code', NaN, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'Q2Code', NaN, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'TrialEndCode', NaN, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'RequireResponses', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'ValidateTrialMarkers', false, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
opt = p.Results;

familyName = char(opt.FamilyName);
s1Code = double(opt.S1Code);
s2Code = double(opt.S2Code);
pasCodes = double(opt.PASCodes(:)');
locCodes = double(opt.LocCodes(:)');
pasBase = double(opt.PASBase);
locBase = double(opt.LocBase);
q1Code = double(opt.Q1Code);
q2Code = double(opt.Q2Code);
trialEndCode = double(opt.TrialEndCode);
requireResponses = logical(opt.RequireResponses);
validateTrialMarkers = logical(opt.ValidateTrialMarkers);

eventNums = arrayfun(@(e) localEventTypeToNumber(e.type), EEG.event);
s1Idx = find(eventNums == s1Code);

n = numel(s1Idx);

trials = struct();
trials.family = repmat(string(familyName), n, 1);
trials.s1Code = repmat(s1Code, n, 1);
trials.s2CodeExpected = repmat(s2Code, n, 1);
trials.pasCodesExpected = repmat(string(mat2str(pasCodes)), n, 1);
trials.locCodesExpected = repmat(string(mat2str(locCodes)), n, 1);
trials.s1EventIdx = nan(n,1);
trials.s2EventIdx = nan(n,1);
trials.s1Latency = nan(n,1);
trials.s2Latency = nan(n,1);
trials.pasCode = nan(n,1);
trials.pasResp = nan(n,1);
trials.locCode = nan(n,1);
trials.locResp = nan(n,1);
trials.q2Code = nan(n,1);
trials.q2EventIdx = nan(n,1);
trials.q2Latency = nan(n,1);
trials.trialEndCode = nan(n,1);
trials.trialEndEventIdx = nan(n,1);
trials.trialEndLatency = nan(n,1);

for t = 1:n
    startIdx = s1Idx(t);

    if t < n
        stopIdx = s1Idx(t+1) - 1;
    else
        stopIdx = numel(EEG.event);
    end

    segIdx = startIdx:stopIdx;
    segNums = eventNums(segIdx);

    s2Rel = find(segNums == s2Code, 1, 'first');
    pasRel = find(ismember(segNums, pasCodes), 1, 'first');
    locRel = find(ismember(segNums, locCodes), 1, 'first');
    q2Rel = [];
    trialEndRel = [];

    if isfinite(q2Code)
        q2Rel = find(segNums == q2Code, 1, 'first');
    end
    if isfinite(trialEndCode)
        trialEndRel = find(segNums == trialEndCode, 1, 'first');
    end

    trials.s1EventIdx(t) = startIdx;
    trials.s1Latency(t) = EEG.event(startIdx).latency;

    if ~isempty(s2Rel)
        trials.s2EventIdx(t) = segIdx(s2Rel);
        trials.s2Latency(t) = EEG.event(segIdx(s2Rel)).latency;
    end

    if ~isempty(pasRel)
        trials.pasCode(t) = segNums(pasRel);
        trials.pasResp(t) = segNums(pasRel) - pasBase;
    end

    if ~isempty(locRel)
        trials.locCode(t) = segNums(locRel);
        trials.locResp(t) = segNums(locRel) - locBase;
    end

    if ~isempty(q2Rel)
        trials.q2Code(t) = segNums(q2Rel);
        trials.q2EventIdx(t) = segIdx(q2Rel);
        trials.q2Latency(t) = EEG.event(segIdx(q2Rel)).latency;
    end

    if ~isempty(trialEndRel)
        trials.trialEndCode(t) = segNums(trialEndRel);
        trials.trialEndEventIdx(t) = segIdx(trialEndRel);
        trials.trialEndLatency(t) = EEG.event(segIdx(trialEndRel)).latency;
    end

    if validateTrialMarkers && ~isempty(locRel) && ~isempty(trialEndRel) && trialEndRel <= locRel
        error('%s trial %d: trialEnd code %d occurs before localisation response in ascending sequence.', ...
            familyName, t, trialEndCode);
    end
end

missingS2 = find(isnan(trials.s2EventIdx));
if ~isempty(missingS2)
    error('Some %s S1-defined trials are missing S2 trigger %d. Missing trial rows: %s', ...
        familyName, s2Code, mat2str(missingS2(:)'));
end

missingPAS = find(isnan(trials.pasResp));
missingLoc = find(isnan(trials.locResp));

if requireResponses
    if ~isempty(missingPAS)
        error('Some %s S1-defined trials are missing PAS response trigger(s) %s. Missing trial rows: %s', ...
            familyName, mat2str(pasCodes), mat2str(missingPAS(:)'));
    end

    if ~isempty(missingLoc)
        error('Some %s S1-defined trials are missing localisation response trigger(s) %s. Missing trial rows: %s', ...
            familyName, mat2str(locCodes), mat2str(missingLoc(:)'));
    end
else
    if ~isempty(missingPAS)
        warning('Some %s S1-defined trials are missing PAS response trigger(s) %s. Missing trial rows: %s', ...
            familyName, mat2str(pasCodes), mat2str(missingPAS(:)'));
    end

    if ~isempty(missingLoc)
        warning('Some %s S1-defined trials are missing localisation response trigger(s) %s. Missing trial rows: %s', ...
            familyName, mat2str(locCodes), mat2str(missingLoc(:)'));
    end
end

if validateTrialMarkers && isfinite(q2Code)
    missingQ2 = find(isnan(trials.q2EventIdx));
    if ~isempty(missingQ2)
        error('Some %s S1-defined trials are missing Q2 onset trigger %d. Missing trial rows: %s', ...
            familyName, q2Code, mat2str(missingQ2(:)'));
    end
end

if validateTrialMarkers && isfinite(trialEndCode)
    missingTrialEnd = find(isnan(trials.trialEndEventIdx));
    if ~isempty(missingTrialEnd)
        error('Some %s S1-defined trials are missing trialEnd trigger %d. Missing trial rows: %s', ...
            familyName, trialEndCode, mat2str(missingTrialEnd(:)'));
    end
end

end

function T = localMakeTriggeredTrialAuditTable(trials, familyName)

n = numel(trials.s1EventIdx);
trialNum = (1:n)';

if n == 0
    T = table( ...
        zeros(0,1), strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
        zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
        zeros(0,1), zeros(0,1), ...
        'VariableNames', {'Trial','Family','S1EventIdx','S2EventIdx','S1Latency','S2Latency', ...
        'PASCode','PASResp','LocCode','LocResp','Q2Code','Q2Latency','TrialEndCode','TrialEndLatency'});
    return;
end

T = table( ...
    trialNum, ...
    repmat(string(familyName), n, 1), ...
    trials.s1EventIdx(:), ...
    trials.s2EventIdx(:), ...
    trials.s1Latency(:), ...
    trials.s2Latency(:), ...
    trials.pasCode(:), ...
    trials.pasResp(:), ...
    trials.locCode(:), ...
    trials.locResp(:), ...
    trials.q2Code(:), ...
    trials.q2Latency(:), ...
    trials.trialEndCode(:), ...
    trials.trialEndLatency(:), ...
    'VariableNames', {'Trial','Family','S1EventIdx','S2EventIdx','S1Latency','S2Latency', ...
    'PASCode','PASResp','LocCode','LocResp','Q2Code','Q2Latency','TrialEndCode','TrialEndLatency'});

end

function localWriteBdfEventCodeInventory(eventNums, csvPath)

eventNums = eventNums(isfinite(eventNums));
[uCodes, ~, ic] = unique(eventNums);
counts = accumarray(ic, 1);

T = table(uCodes(:), counts(:), 'VariableNames', {'EventCode','Count'});
T = sortrows(T, 'EventCode');
writetable(T, csvPath);
fprintf('Saved BDF event code inventory: %s\n', csvPath);

end

function localWarnLegacyTriggerCodes(eventNums, cfg)

offset = cfg.PracticeTriggerOffset;
legacyMain = [12, 32, 52:54];
legacyPractice = [12, 32, 52:54] + offset;
legacyMetadata = setdiff([65:69, 70:82, 90:109], ...
    [cfg.MainQ1Code, cfg.MainQ2Code, ...
     (cfg.MainLocBase + 1):(cfg.MainLocBase + 4), ...
     cfg.MainTrialEndCode]);

present = unique(eventNums(isfinite(eventNums)));
foundMain = intersect(present, legacyMain);
foundPractice = intersect(present, legacyPractice);
foundMetadata = intersect(present, legacyMetadata);

if ~isempty(foundMain)
    warning('BDF contains deprecated main-family trigger code(s) %s (old trialEnd/Q2/LOC mapping).', ...
        mat2str(foundMain));
end
if ~isempty(foundPractice)
    warning('BDF contains deprecated practice-family trigger code(s) %s (old trialEnd/Q2/LOC mapping).', ...
        mat2str(foundPractice));
end
if ~isempty(foundMetadata)
    warning('BDF contains legacy metadata trigger code(s) %s; these are not used in ascending v3.', ...
        mat2str(foundMetadata));
end

end

function trialsOut = localSubsetTrialStruct(trialsIn, idx)

fields = fieldnames(trialsIn);
trialsOut = struct();

for f = 1:numel(fields)
trialsOut.(fields{f}) = trialsIn.(fields{f})(idx);
end

end

function x = localEventTypeToNumber(eventType)

if isnumeric(eventType)
x = double(eventType);
else
x = str2double(string(eventType));
end

end

function [outcome, s1Codes, s2Codes] = localMakeOutcomeCodes(pas, locCorrect, isChange)

n = numel(pas);

outcome = strings(n,1);
s1Codes = nan(n,1);
s2Codes = nan(n,1);

for i = 1:n
if isChange(i)
if pas(i) == 1
outcome(i) = "Blind";
s1Codes(i) = 201;
s2Codes(i) = 301;
elseif pas(i) > 1 && ~locCorrect(i)
outcome(i) = "Sensing";
s1Codes(i) = 202;
s2Codes(i) = 302;
elseif pas(i) > 1 && locCorrect(i)
outcome(i) = "Seeing";
s1Codes(i) = 203;
s2Codes(i) = 303;
else
outcome(i) = "UnknownChange";
s1Codes(i) = 299;
s2Codes(i) = 399;
end
else
if pas(i) == 1
outcome(i) = "NoChange_CR";
s1Codes(i) = 211;
s2Codes(i) = 311;
else
outcome(i) = "NoChange_FA";
s1Codes(i) = 212;
s2Codes(i) = 312;
end
end
end

end

function EEG = localAddSyntheticS1S2Events(EEG, trialsMain, s1Codes, s2Codes, outcome)

if ~isfield(EEG.event, 'cb_mainTrial')
[EEG.event.cb_mainTrial] = deal([]);
end
if ~isfield(EEG.event, 'cb_fullRunRow')
[EEG.event.cb_fullRunRow] = deal([]);
end
if ~isfield(EEG.event, 'cb_outcome')
[EEG.event.cb_outcome] = deal([]);
end
if ~isfield(EEG.event, 'cb_synthetic')
[EEG.event.cb_synthetic] = deal([]);
end
if ~isfield(EEG.event, 'cb_lock')
[EEG.event.cb_lock] = deal([]);
end
if ~isfield(EEG.event, 'cb_reconstructedS1')
[EEG.event.cb_reconstructedS1] = deal([]);
end
if ~isfield(EEG.event, 'cb_sourceAnchorCode')
[EEG.event.cb_sourceAnchorCode] = deal([]);
end
if ~isfield(EEG.event, 'cb_reconstructedMarkerCode')
[EEG.event.cb_reconstructedMarkerCode] = deal([]);
end

n = numel(s1Codes);

for i = 1:n
s1Ev = EEG.event(trialsMain.s1EventIdx(i));
s1Ev.type = num2str(s1Codes(i));
s1Ev.latency = trialsMain.s1Latency(i);
s1Ev.cb_mainTrial = i;
s1Ev.cb_fullRunRow = i;
s1Ev.cb_outcome = char(outcome(i));
s1Ev.cb_synthetic = 1;
s1Ev.cb_lock = 'S1';
s1Ev.cb_reconstructedS1 = 1;
s1Ev.cb_sourceAnchorCode = 22;
s1Ev.cb_reconstructedMarkerCode = 221;

% Add a distinct provenance marker at the same reconstructed latency.
% Code 221 is never treated as a recorded hardware trigger.
reconEv = s1Ev;
reconEv.type = '221';
reconEv.cb_synthetic = 1;
reconEv.cb_lock = 'S1_RECON';
reconEv.cb_outcome = '';

s2Ev = EEG.event(trialsMain.s2EventIdx(i));
s2Ev.type = num2str(s2Codes(i));
s2Ev.latency = trialsMain.s2Latency(i);
s2Ev.cb_mainTrial = i;
s2Ev.cb_fullRunRow = i;
s2Ev.cb_outcome = char(outcome(i));
s2Ev.cb_synthetic = 1;
s2Ev.cb_lock = 'S2';

EEG.event(end+1) = reconEv;
EEG.event(end+1) = s1Ev; 
EEG.event(end+1) = s2Ev;


end

[~, sortIdx] = sort([EEG.event.latency]);
EEG.event = EEG.event(sortIdx);

end

function baselineMeans = localComputePreS1BaselineMeans(EEG, s1Latencies, baselineMs)

nTrials = numel(s1Latencies);
baselineMeans = nan(EEG.nbchan, nTrials);

srate = EEG.srate;

for tr = 1:nTrials
s1Lat = s1Latencies(tr);


startSample = round(s1Lat + (baselineMs(1)/1000)*srate);
endSample   = round(s1Lat + (baselineMs(2)/1000)*srate) - 1;

startSample = max(1, startSample);
endSample = min(EEG.pnts, endSample);

if endSample <= startSample
    error('Invalid baseline sample range for trial %d.', tr);
end

baselineMeans(:,tr) = mean(double(EEG.data(:,startSample:endSample)), 2, 'omitnan');


end

end

function bad = localFindBadEpochs(EEG, chans, absThr, ptpThr)

nTrials = EEG.trials;

badAbs = false(nTrials,1);
badPtp = false(nTrials,1);

for tr = 1:nTrials
d = double(EEG.data(chans,:,tr));


badAbs(tr) = any(abs(d(:)) > absThr);

ptp = max(d, [], 2) - min(d, [], 2);
badPtp(tr) = any(ptp > ptpThr);


end

bad = struct();
bad.badAbs = badAbs;
bad.badPtp = badPtp;
bad.anyBad = badAbs | badPtp;

end

function T = localMakeArtifactReport(EEG_S1, EEG_S2, badS1, badS2, badUnion, keepIdx, rejectIdx)

n = EEG_S1.trials;

T = table();
T.Epoch = (1:n)';
T.S1_badAbs = badS1.badAbs;
T.S1_badPtp = badS1.badPtp;
T.S1_anyBad = badS1.anyBad;
T.S2_badAbs = badS2.badAbs;
T.S2_badPtp = badS2.badPtp;
T.S2_anyBad = badS2.anyBad;
T.RejectedUnion = badUnion(:);
T.Kept = ~badUnion(:);

T.KeptIndexAfterRejection = nan(n,1);
T.KeptIndexAfterRejection(keepIdx) = (1:numel(keepIdx))';

T.RejectionOrder = nan(n,1);
T.RejectionOrder(rejectIdx) = (1:numel(rejectIdx))';

end

function counts = localConditionCountsFromEpochs(EEG, lockCodes)

epochCodes = localEpochLockCodes(EEG, lockCodes);

names = strings(numel(lockCodes),1);
for i = 1:numel(lockCodes)
switch lockCodes(i)
case {201,301}
names(i) = "Blind";
case {202,302}
names(i) = "Sensing";
case {203,303}
names(i) = "Seeing";
case {211,311}
names(i) = "NoChange_CR";
case {212,312}
names(i) = "NoChange_FA";
otherwise
names(i) = "Unknown";
end
end

n = zeros(numel(lockCodes),1);
for i = 1:numel(lockCodes)
n(i) = sum(epochCodes == lockCodes(i));
end

counts = table(names(:), lockCodes(:), n(:), ...
'VariableNames', {'Condition','Code','N'});

end

function epochCodes = localEpochLockCodes(EEG_epoched, lockCodes)

epochCodes = nan(EEG_epoched.trials,1);

for e = 1:EEG_epoched.trials
evTypes = EEG_epoched.epoch(e).eventtype;


if ~iscell(evTypes)
    evTypes = {evTypes};
end

evNums = nan(numel(evTypes),1);

for k = 1:numel(evTypes)
    thisType = evTypes{k};

    if isnumeric(thisType)
        evNums(k) = double(thisType);
    else
        evNums(k) = str2double(string(thisType));
    end
end

matchIdx = find(ismember(evNums, lockCodes));

if isempty(matchIdx)
    error('No lock code found for epoch %d.', e);
end

epochCodes(e) = evNums(matchIdx(1));


end

end

function plotReport = localPlotAllRois(EEG_S1, EEG_S2, participantID, plotDir, cfg)

roiDefs = struct();
roiDefs(1).name = "OccipitalROI";
roiDefs(1).labels = ["O1","Oz","O2"];

roiDefs(2).name = "PosteriorROI";
roiDefs(2).labels = ["PO7","PO8","PO3","PO4","POz"];

roiDefs(3).name = "ParietalROI";
roiDefs(3).labels = ["P3","Pz","P4"];

roiDefs(4).name = "CentralROI";
roiDefs(4).labels = ["Cz","CPz","Pz"];

roiDefs(5).name = "PO7PO8";
roiDefs(5).labels = ["PO7","PO8"];

% Codes to recognise in the epoched datasets
allS1LockCodes = [201 202 203 211 212];
allS2LockCodes = [301 302 303 311 312];

% Codes to actually plot
plotS1CondCodes = [201 202 203];
plotS2CondCodes = [301 302 303];

plotRows = table();

for r = 1:numel(roiDefs)


rowS1 = localPlotOneRoiLock( ...
    EEG_S1, ...
    participantID, ...
    plotDir, ...
    "S1", ...
    roiDefs(r), ...
    plotS1CondCodes, ...
    allS1LockCodes, ...
    cfg);

rowS2 = localPlotOneRoiLock( ...
    EEG_S2, ...
    participantID, ...
    plotDir, ...
    "S2", ...
    roiDefs(r), ...
    plotS2CondCodes, ...
    allS2LockCodes, ...
    cfg);

plotRows = [plotRows; rowS1; rowS2]; %#ok<AGROW>


end

plotReport = struct();
plotReport.plotFiles = plotRows;

end

function row = localPlotOneRoiLock(EEG, participantID, plotDir, lockName, roiDef, plotCondCodes, allLockCodes, cfg)

condNames = ["Blind","Sensing","Seeing"];

colors.Blind   = [0.000 0.447 0.741];
colors.Sensing = [0.929 0.694 0.125];
colors.Seeing  = [0.850 0.325 0.098];

roiChanIdx = localFindChannels(EEG, roiDef.labels);

% Important:
% Use all lock codes to identify every epoch, including no-change trials.
% Then only plot the three change-awareness conditions.
epochCodes = localEpochLockCodes(EEG, allLockCodes);

times = EEG.times(:);

roiData = squeeze(mean(double(EEG.data(roiChanIdx,:,:)), 1, 'omitnan'));

% Make sure orientation is time x trial
if size(roiData,1) ~= EEG.pnts && size(roiData,2) == EEG.pnts
roiData = roiData';
end

isBlind   = epochCodes == plotCondCodes(1);
isSensing = epochCodes == plotCondCodes(2);
isSeeing  = epochCodes == plotCondCodes(3);

waveBlind   = mean(roiData(:, isBlind),   2, 'omitnan');
waveSensing = mean(roiData(:, isSensing), 2, 'omitnan');
waveSeeing  = mean(roiData(:, isSeeing),  2, 'omitnan');

nBlind   = sum(isBlind);
nSensing = sum(isSensing);
nSeeing  = sum(isSeeing);

nIgnored = EEG.trials - (nBlind + nSensing + nSeeing);

fprintf('\n%s %s\n', char(lockName), char(roiDef.name));
fprintf('  Blind:   %d\n', nBlind);
fprintf('  Sensing: %d\n', nSensing);
fprintf('  Seeing:  %d\n', nSeeing);
fprintf('  Ignored no-change/other epochs: %d\n', nIgnored);

waveTable = table( ...
times, ...
waveBlind, ...
waveSensing, ...
waveSeeing, ...
'VariableNames', {'TimeMs','Blind_uV','Sensing_uV','Seeing_uV'});

roiNameChar = char(roiDef.name);
chanText = char(strjoin(roiDef.labels, ', '));
chanFileText = char(strjoin(roiDef.labels, '_'));

baseName = sprintf('%s_%slocked_ERP_%s_%s', ...
participantID, char(lockName), roiNameChar, chanFileText);

csvFile = fullfile(plotDir, [baseName '.csv']);
pngFile = fullfile(plotDir, [baseName '.png']);
figFile = fullfile(plotDir, [baseName '.fig']);

if cfg.SaveCsv
writetable(waveTable, csvFile);
end

if cfg.VisiblePlots
figVis = 'on';
else
figVis = 'off';
end

h = figure('Color', 'w', 'Visible', figVis);
hold on;

p1 = plot(times, waveBlind, ...
'Color', colors.Blind, ...
'LineWidth', 2.5);

p2 = plot(times, waveSensing, ...
'Color', colors.Sensing, ...
'LineWidth', 2.5);

p3 = plot(times, waveSeeing, ...
'Color', colors.Seeing, ...
'LineWidth', 2.5);

xline(0, 'k-', 'LineWidth', 1.2, 'HandleVisibility', 'off');
yline(0, 'k-', 'LineWidth', 0.8, 'HandleVisibility', 'off');

grid on;
box off;

xlabel(sprintf('Time from %s onset (ms)', char(lockName)));
ylabel('Amplitude (\muV)');

title({ ...
sprintf('%s-locked ERP | %s | %s', char(lockName), roiNameChar, participantID), ...
sprintf('Channels: %s', chanText)}, ...
'Interpreter', 'none');

legend([p1 p2 p3], ...
sprintf('Blind (n=%d)', nBlind), ...
sprintf('Sensing (n=%d)', nSensing), ...
sprintf('Seeing (n=%d)', nSeeing), ...
'Location', 'best');

set(gca, 'FontSize', 12);

% Positive-up orientation by default
if cfg.NegativeUp
set(gca, 'YDir', 'reverse');
else
set(gca, 'YDir', 'normal');
end

if strcmpi(char(lockName), 'S1')
xlim([cfg.S1EpochWinSec(1)*1000 cfg.S1EpochWinSec(2)*1000]);
else
xlim([cfg.S2EpochWinSec(1)*1000 cfg.S2EpochWinSec(2)*1000]);
end

drawnow;

if cfg.SavePng
print(h, pngFile, '-dpng', '-r300');
end

if cfg.SaveFig
savefig(h, figFile);
end

if ~cfg.VisiblePlots
close(h);
end

row = table( ...
string(lockName), ...
string(roiDef.name), ...
string(chanText), ...
nBlind, ...
nSensing, ...
nSeeing, ...
nIgnored, ...
string(csvFile), ...
string(pngFile), ...
string(figFile), ...
'VariableNames', {'Lock','ROI','Channels','NBlind','NSensing','NSeeing','NIgnored','CsvFile','PngFile','FigFile'});

end


function chanIdx = localFindChannels(EEG, labels)

labels = string(labels);
allLabels = string({EEG.chanlocs.labels});

chanIdx = nan(numel(labels),1);

for i = 1:numel(labels)
hit = find(strcmpi(allLabels, labels(i)), 1, 'first');


if isempty(hit)
    error('Could not find channel label: %s', labels(i));
end

chanIdx(i) = hit;


end

end


function participantIDs = localParseParticipantIDs(idInput)

idInput = strtrim(char(idInput));
if isempty(idInput)
    error('No valid participant ID entered.');
end

idInput = strrep(idInput, ',', ' ');
tokens = strsplit(strtrim(idInput));
tokens = tokens(~cellfun(@isempty, strtrim(tokens)));

if isempty(tokens)
    error('No valid participant ID entered.');
end

participantIDs = cellfun(@(s) char(strtrim(s)), tokens, 'UniformOutput', false);

end


function pathOut = localExtractPlotOutputPath(plotOutput)

pathOut = '';
if ~isstruct(plotOutput)
    return;
end
if isfield(plotOutput, 'figurePng') && ~isempty(plotOutput.figurePng)
    pathOut = char(string(plotOutput.figurePng));
elseif isfield(plotOutput, 'pngFile') && ~isempty(plotOutput.pngFile)
    pathOut = char(string(plotOutput.pngFile));
elseif isfield(plotOutput, 'plotDir') && ~isempty(plotOutput.plotDir)
    pathOut = char(string(plotOutput.plotDir));
end

end


function tf = localHasManualFileOverride(args)

tf = false;

for k = 1:2:numel(args)
    if k+1 <= numel(args) && (ischar(args{k}) || isstring(args{k}))
        name = lower(char(args{k}));
        if strcmp(name, 'bdffile') || strcmp(name, 'fullruncsv') || strcmp(name, 'fullrunpattern')
            tf = true;
            return;
        end
    end
end

end