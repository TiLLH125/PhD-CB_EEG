function report = CB_EEG_RunFullPreprocessingPipeline_v3(participantID, dataPath, varargin)
% CB_EEG_RunFullPreprocessingPipeline_v3
%
% Full EEG preprocessing + S1/S2 ERP ROI plotting pipeline.
%
% Pipeline:
%   1. Import raw BioSemi BDF
%   2. Downsample to 512 Hz
%   3. QC-check scalp channels with EEGLAB Clean RawData (channel criteria only; flags only)
%   4. Create ICA-training copy, run filtered correlation QC, exclude
%      confirmed bad scalp channels, then apply the retained-channel average reference
%   5. Run Picard ICA on retained scalp channels with automatic PCA dimension
%   6. Run ICLabel
%   7. Automatically reject ICLabel Muscle/Eye components (threshold 0.90 default)
%   8. Create matched ERP-analysis copy: 0.1-20 Hz, same retained channels/reference
%   9. Transfer ICA weights, remove selected components, interpolate bad
%      scalp channels, and apply the final scalp average reference
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
%   - Synthetic codes:
%       S1: 201 Blind, 202 Sensing, 203 Seeing, 211 CR, 212 FA
%       S2: 301 Blind, 302 Sensing, 303 Seeing, 311 CR, 312 FA
%
% Example:
%   dataPath = 'C:\Users\hrl310\Documents\EEGData_HL';
%
%   report = CB_EEG_RunFullPreprocessingPipeline_v3( ...
%       'MAV01', ...
%       dataPath, ...
%       'BdfFile', 'MAV01.bdf', ...
%       'FullRunCsv', 'CB_4xGratings_MAV01_FullRun_20260616_160252.csv');
%
% Notes:
%   - Before ICA, scalp channels are QC-checked with EEGLAB Clean RawData
%     channel defaults: flatline > 5 s, line noise > 4 SD, correlation < 0.80.
%     Only scalp channels are screened on a temporary copy; ASR burst/window
%     rejection is disabled. Potentially bad channels are flagged to CSV for
%     review. In v3, flat channels and channels failing the filtered pre-ICA
%     correlation check are excluded from ICA and ERP preprocessing, then
%     spherically interpolated after ICA component removal. Raw-only line-
%     noise flags remain warnings. Verbose Clean RawData
%     progress is suppressed by default during diagnostic passes; use
%     'SuppressCleanRawDataConsole', false for full console output. Captured
%     verbose trace is saved when 'SaveCleanRawDataConsoleLog', true (default).
%   - Optional read-only 50 Hz line-noise QC runs on the downsampled data and
%     the final post-ICA/interpolated ERP continuous data. Results are saved
%     to CSV and optional plots. This does not apply notch filtering.
%   - Event matching is v3-aware (ascending within-trial trigger codes):
%     Main: 11->21->22->23->24->31->41-44->51->61-64->71; practice +100 (111->...->171).
%     Practice validated from +100 family (S1=121, S2=123, PAS=141-144, Q2=151, LOC=161-164,
%     trialEnd=171); main trials matched to FullRun CSV from base family only
%     (S1=21, S2=23, PAS=41-44, Q2=51, LOC=61-64, trialEnd=71). Practice trials are not
%     skipped positionally anymore.
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

if nargin < 2 || isempty(dataPath)
dataPath = 'C:\Users\hrl310\Documents\EEGData_HL';
end

if nargin < 1 || isempty(participantID)
    idInput = input('Enter participant ID(s), separated by commas or spaces: ', 's');
    participantIDs = localParseParticipantIDs(idInput);
else
    participantIDs = {char(participantID)};
end

if numel(participantIDs) > 1
    if localHasManualFileOverride(varargin)
        error(['Manual BdfFile, FullRunCsv, or FullRunPattern overrides are only supported ', ...
               'for single-participant runs. Remove those overrides or run one participant at a time.']);
    end

    fprintf('\nParticipants queued:\n');
    for qi = 1:numel(participantIDs)
        fprintf('  %d. %s\n', qi, participantIDs{qi});
    end
    fprintf('\n');

    successReports = cell(0, 1);
    batchRows = table(strings(0,1), strings(0,1), strings(0,1), strings(0,1), strings(0,1), ...
        'VariableNames', {'ParticipantID','Status','OutputDirectory','ErrorIdentifier','Message'});

    for i = 1:numel(participantIDs)
        fprintf('Starting participant %d of %d: %s\n', i, numel(participantIDs), participantIDs{i});

        try
            thisReport = CB_EEG_RunFullPreprocessingPipeline_v3(participantIDs{i}, dataPath, varargin{:});
            successReports{end+1,1} = thisReport; %#ok<AGROW>
            batchRows = [batchRows; table( ...
                string(participantIDs{i}), "OK", string(thisReport.outDir), "", "Completed", ...
                'VariableNames', batchRows.Properties.VariableNames)]; %#ok<AGROW>
        catch ME
            if strcmp(ME.identifier, 'CBPreproc:TooManyBadScalpChannels')
                warning('Participant %s failed channel QC and will be skipped: %s', ...
                    participantIDs{i}, ME.message);
                qcPathToken = regexp(ME.message, 'QC failure details:\s*(.+)$', 'tokens', 'once');
                if isempty(qcPathToken)
                    failedOutDir = "";
                else
                    failedOutDir = string(fileparts(qcPathToken{1}));
                end
                batchRows = [batchRows; table( ...
                    string(participantIDs{i}), "QC_FAILED", failedOutDir, ...
                    string(ME.identifier), string(ME.message), ...
                    'VariableNames', batchRows.Properties.VariableNames)]; %#ok<AGROW>
                continue;
            end
            rethrow(ME);
        end
    end

    batchOutputRoot = localGetNameValueText(varargin, 'OutputRoot', dataPath);
    if ~exist(batchOutputRoot, 'dir')
        mkdir(batchOutputRoot);
    end
    batchSummaryCsv = fullfile(batchOutputRoot, ...
        sprintf('CB_EEG_PreprocessingBatchSummary_%s.csv', datestr(now, 'yyyymmdd_HHMMSS')));
    writetable(batchRows, batchSummaryCsv);

    report = struct();
    report.isBatch = true;
    report.participantIDs = participantIDs;
    report.successfulReports = successReports;
    report.batchSummary = batchRows;
    report.batchSummaryCsv = batchSummaryCsv;
    return;
end

participantID = participantIDs{1};
participantID = char(participantID);
dataPath = char(dataPath);

if ~strcmp(dataPath(end), filesep)
dataPath = [dataPath filesep];
end

defaultBdfFile = sprintf('%s.bdf', participantID);
defaultFullRunPattern = sprintf('CB_4xGratings_%s_FullRun_*.csv', participantID);
defaultOutputRoot = dataPath;

isText = @(x) ischar(x) || isstring(x);

p = inputParser;
addParameter(p, 'BdfFile', defaultBdfFile, isText);
addParameter(p, 'FullRunCsv', '', isText);
addParameter(p, 'FullRunPattern', defaultFullRunPattern, isText);
addParameter(p, 'OutputRoot', defaultOutputRoot, isText);

% Core config
addParameter(p, 'NScalpChans', 64, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'ExternalChans', 65:72, @(x) isnumeric(x) && isvector(x));
addParameter(p, 'TargetSrate', 512, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'ICAFilterHz', [1 30], @(x) isnumeric(x) && numel(x)==2);
addParameter(p, 'ERPFilterHz', [0.1 20], @(x) isnumeric(x) && numel(x)==2);
addParameter(p, 'ICAType', 'picard', isText);
addParameter(p, 'ICAPcaDim', [], @(x) isempty(x) || ...
    (isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1 && mod(x,1) == 0));
addParameter(p, 'ICAMaxIter', 500, @(x) isnumeric(x) && isscalar(x));

% Bad scalp-channel QC checker using EEGLAB Clean RawData
addParameter(p, 'RunBadChannelChecker', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'BadChannelCheckerFlatlineCriterion', 5, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'BadChannelCheckerLineNoiseCriterion', 4, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'BadChannelCheckerCorrelationCriterion', 0.80, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 1);
addParameter(p, 'AdditionalBadScalpChannels', {}, @(x) iscellstr(x) || isstring(x) || ischar(x));
addParameter(p, 'MaxBadScalpChannels', 6, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0 && mod(x,1) == 0);

addParameter(p, 'SuppressCleanRawDataConsole', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'SaveCleanRawDataConsoleLog', true, @(x) islogical(x) || isnumeric(x));

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
if ischar(cfg.AdditionalBadScalpChannels)
    cfg.AdditionalBadScalpChannels = {cfg.AdditionalBadScalpChannels};
elseif isstring(cfg.AdditionalBadScalpChannels)
    cfg.AdditionalBadScalpChannels = cellstr(cfg.AdditionalBadScalpChannels);
else
    cfg.AdditionalBadScalpChannels = cellfun(@char, cfg.AdditionalBadScalpChannels, 'UniformOutput', false);
end
cfg.AdditionalBadScalpChannels = cfg.AdditionalBadScalpChannels(:);
cfg.MaxBadScalpChannels = double(cfg.MaxBadScalpChannels);

cfg.SuppressCleanRawDataConsole = logical(cfg.SuppressCleanRawDataConsole);
cfg.SaveCleanRawDataConsoleLog = logical(cfg.SaveCleanRawDataConsoleLog);

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

outDir = fullfile(cfg.OutputRoot, sprintf('%s_Preproc_%s', participantID, runStamp));
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
fprintf('CB EEG FULL PREPROCESSING PIPELINE\n');
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
originalAllLabels = string({originalAllChanlocs.labels});
originalAllLabels = originalAllLabels(:);
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

[flaggedFlatlineLabels, flaggedFlatlineIndices, ...
    flaggedLineNoiseLabels, flaggedLineNoiseIndices, ...
    initialChannelQcTableCsv, initialChannelQcSummaryCsv] = ...
    localRunInitialScalpChannelQC(EEG_ds, cfg, participantID, ...
    originalScalpLabels, originalScalpChanlocs, outDir);

if cfg.RunBadChannelChecker
    logStep('bad_channel_check', 'OK', ...
        'Initial flatline and line-noise channel QC completed', ...
        sprintf('%d flatline; %d line-noise warning(s)', ...
        numel(flaggedFlatlineLabels), numel(flaggedLineNoiseLabels)), initialChannelQcTableCsv);
else
    logStep('bad_channel_check', 'SKIP', ...
        'Initial bad-channel QC disabled', '', initialChannelQcSummaryCsv);
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

[flaggedCorrelationLabels, flaggedCorrelationIndices, preIcaCorrelationCsv] = ...
    localRunPreIcaCorrelationQC(EEG_ica, cfg, participantID, ...
    originalScalpLabels, originalScalpChanlocs, outDir);

[flaggedBadScalpLabels, flaggedBadScalpIndices, additionalBadScalpLabels, ...
    badChannelTable, badChannelCheckTableCsv, badChannelCheckSummaryCsv] = ...
    localFinalizeBadChannelDecision(participantID, originalScalpLabels, ...
    flaggedFlatlineLabels, flaggedLineNoiseLabels, flaggedCorrelationLabels, cfg, outDir);

if numel(flaggedBadScalpLabels) > cfg.MaxBadScalpChannels
    qcFailureCsv = fullfile(outDir, sprintf('%s_ChannelQCFailure.csv', participantID));
    failureTable = table(string(participantID), numel(flaggedBadScalpLabels), ...
        cfg.MaxBadScalpChannels, string(strjoin(flaggedBadScalpLabels, ', ')), ...
        string(badChannelCheckTableCsv), string(datestr(now)), ...
        'VariableNames', {'ParticipantID','NBadScalpChannels','MaxBadScalpChannels', ...
        'BadScalpChannels','DecisionTableCsv','DecisionTime'});
    writetable(failureTable, qcFailureCsv);
    logStep('bad_channel_decision', 'QC_FAIL', ...
        'Too many bad scalp channels for reliable interpolation', ...
        sprintf('%d bad; maximum %d', numel(flaggedBadScalpLabels), cfg.MaxBadScalpChannels), qcFailureCsv);
    error('CBPreproc:TooManyBadScalpChannels', ...
        ['Participant %s has %d bad scalp channels (maximum allowed: %d). ', ...
        'QC failure details: %s'], participantID, numel(flaggedBadScalpLabels), ...
        cfg.MaxBadScalpChannels, qcFailureCsv);
end

goodScalpLabels = setdiff(originalScalpLabels, flaggedBadScalpLabels, 'stable');
fprintf('\nFinal scalp channels excluded from ICA and ERP preprocessing (%d):\n', ...
    numel(flaggedBadScalpLabels));
disp(flaggedBadScalpLabels');
logStep('bad_channel_decision', 'OK', ...
    'Final bad scalp-channel decision completed', ...
    sprintf('%d excluded; %d retained', numel(flaggedBadScalpLabels), numel(goodScalpLabels)), ...
    badChannelCheckTableCsv);

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
            'Line-noise QC failed for Downsampled_512Hz', ME.message, '');
    end
else
    logStep('line_noise_qc', 'SKIP', 'Line-noise QC disabled', '', '');
end

if ~isempty(flaggedBadScalpLabels)
    badIdxIca = localFindExistingChannelsByLabels(EEG_ica, flaggedBadScalpLabels);
    EEG_ica = pop_select(EEG_ica, 'nochannel', badIdxIca);
end

externalIdxIca = localFindExistingChannelsByLabels(EEG_ica, originalExternalLabels);
EEG_ica = pop_reref(EEG_ica, [], 'exclude', externalIdxIca);
EEG_ica.setname = sprintf('%s_ds%d_bp%dto%d_avgref_ICAtraining', ...
    participantID, cfg.TargetSrate, cfg.ICAFilterHz(1), cfg.ICAFilterHz(2));

EEG_ica = localFixChanlocsForICLabel(EEG_ica);
EEG_ica = eeg_checkset(EEG_ica);

icaScalpChanIdx = localFindExistingChannelsByLabels(EEG_ica, goodScalpLabels);
nIcaChansUsed = numel(icaScalpChanIdx);
icaPcaDimAutomatic = nIcaChansUsed - 1;
if isempty(cfg.ICAPcaDim)
    icaPcaDimUsed = icaPcaDimAutomatic;
else
    icaPcaDimUsed = double(cfg.ICAPcaDim);
end
if icaPcaDimUsed > icaPcaDimAutomatic
    error('ICAPcaDim=%d is too high for %d scalp channels after average reference.', ...
        icaPcaDimUsed, nIcaChansUsed);
end

icaTrainingSet = sprintf('%s_ds%d_bp%dto%d_avgref_ICAtraining.set', ...
    participantID, cfg.TargetSrate, cfg.ICAFilterHz(1), cfg.ICAFilterHz(2));

EEG_ica = pop_saveset(EEG_ica, 'filename', icaTrainingSet, 'filepath', outDir);

logStep('ica_training_dataset', 'OK', ...
    'Created 1-30 Hz average-referenced ICA-training dataset using retained scalp channels', ...
    sprintf('%d scalp channels; PCA %d', nIcaChansUsed, icaPcaDimUsed), icaTrainingSet);

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

if ~isempty(flaggedBadScalpLabels)
    badIdxErp = localFindExistingChannelsByLabels(EEG_erp, flaggedBadScalpLabels);
    EEG_erp = pop_select(EEG_erp, 'nochannel', badIdxErp);
end

externalIdxErp = localFindExistingChannelsByLabels(EEG_erp, originalExternalLabels);
EEG_erp = pop_reref(EEG_erp, [], 'exclude', externalIdxErp);
EEG_erp.setname = sprintf('%s_ds%d_bp0p1to20_avgref', participantID, cfg.TargetSrate);

EEG_erp = localFixChanlocsForICLabel(EEG_erp);
EEG_erp = eeg_checkset(EEG_erp);

erpSet = sprintf('%s_ds%d_bp0p1to20_avgref.set', participantID, cfg.TargetSrate);
EEG_erp = pop_saveset(EEG_erp, 'filename', erpSet, 'filepath', outDir);

logStep('erp_dataset', 'OK', ...
    'Created 0.1-20 Hz average-referenced ERP-analysis dataset using retained scalp channels', ...
    sprintf('%d scalp channels', numel(goodScalpLabels)), erpSet);

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

[EEG_clean, interpolationApplied] = localInterpolateAndRestoreMontage( ...
    EEG_clean, flaggedBadScalpLabels, originalAllChanlocs, originalAllLabels, ...
    originalExternalLabels, cfg);
logStep('channel_interpolation', 'OK', ...
    'Restored the original montage and applied the final scalp average reference', ...
    sprintf('%d scalp channel(s) interpolated; applied=%s', ...
    numel(flaggedBadScalpLabels), mat2str(interpolationApplied)), '');

compTag = localComponentTag(componentsToRemove);
cleanSet = sprintf('%s_ds%d_bp0p1to20_avgref_%sRemoved.set', ...
    participantID, cfg.TargetSrate, compTag);

EEG_clean.setname = erase(cleanSet, '.set');
EEG_clean = pop_saveset(EEG_clean, 'filename', cleanSet, 'filepath', outDir);

logStep('ica_transfer', 'OK', 'Transferred Picard ICA weights to ERP dataset', '', transferredSet);
logStep('component_removal', 'OK', 'Removed selected ICA components from ERP dataset', mat2str(componentsToRemove), cleanSet);

if cfg.RunLineNoiseQC
    try
        [tmpLineNoiseTable, lineNoisePlotDir, lineNoiseQCSummaryStr] = localComputeLineNoiseQC( ...
            EEG_clean, cfg, participantID, 'FinalERPclean_0p1to20Hz', ...
            originalScalpLabels, flaggedBadScalpLabels, flaggedLineNoiseLabels, ...
            outDir, lineNoisePlotDir);
        lineNoiseQCTables{end+1} = tmpLineNoiseTable;
        logStep('line_noise_qc', 'OK', ...
            'Line-noise QC completed for FinalERPclean_0p1to20Hz', ...
            lineNoiseQCSummaryStr, '');
    catch ME
        logStep('line_noise_qc', 'WARN', ...
            'Line-noise QC failed for FinalERPclean_0p1to20Hz', ME.message, '');
    end

    if ~isempty(lineNoiseQCTables)
        lineNoiseQCTable = vertcat(lineNoiseQCTables{:});
        writetable(lineNoiseQCTable, lineNoiseQCTableCsv);
        lineNoiseQCSummary = localSummarizeLineNoiseQC(lineNoiseQCTable, participantID, cfg);
        writetable(lineNoiseQCSummary, lineNoiseQCSummaryCsv);
        logStep('line_noise_qc', 'OK', ...
            'Saved line-noise QC table and summary', ...
            sprintf('%d stage table(s)', numel(lineNoiseQCTables)), lineNoiseQCTableCsv);
        if numel(lineNoiseQCTables) == 2
            lineNoiseQCStatus = 'OK';
        else
            lineNoiseQCStatus = 'PARTIAL';
        end
    else
        logStep('line_noise_qc', 'WARN', ...
            'No line-noise QC tables were produced', ...
            'Both line-noise QC stage calls failed', '');
        lineNoiseQCStatus = 'FAILED';
    end
end

% ====================================================================
% Stage 10: Behavioural CSV and event matching
% ====================================================================

fprintf('\n\n================ STAGE 10: EVENT MATCHING ================\n');

T_beh = readtable(fullRunCsv);

fprintf('Behavioural FullRun rows: %d\n', height(T_beh));
if height(T_beh) ~= cfg.ExpectedMainTrials
    error('Expected %d behavioural rows but found %d.', cfg.ExpectedMainTrials, height(T_beh));
end

varMap = localInferBehaviourVars(T_beh, cfg);

fprintf('\nBehaviour variables:\n');

varMapTable = table( ...
    string(varMap.PASVar), ...
    string(varMap.LocCorrectVar), ...
    string(varMap.LocRespVar), ...
    string(varMap.IsChangeVar), ...
    'VariableNames', {'PASVar','LocCorrectVar','LocRespVar','IsChangeVar'});

disp(varMapTable);

varMapCsv = fullfile(outDir, sprintf('%s_BehaviourVariableMap.csv', participantID));
writetable(varMapTable, varMapCsv);

logStep('event_matching', 'OK', 'Behaviour variable map inferred', ...
    sprintf('PAS=%s; LocCorrect=%s; LocResp=%s; IsChange=%s', ...
    varMap.PASVar, varMap.LocCorrectVar, varMap.LocRespVar, varMap.IsChangeVar), ...
    varMapCsv);

mainPasCodes = (cfg.MainPASBase + 1):(cfg.MainPASBase + 4);
mainLocCodes = (cfg.MainLocBase + 1):(cfg.MainLocBase + 4);
practiceS1Code = cfg.MainS1Code + cfg.PracticeTriggerOffset;
practiceS2Code = cfg.MainS2Code + cfg.PracticeTriggerOffset;
practicePasCodes = mainPasCodes + cfg.PracticeTriggerOffset;
practiceLocCodes = mainLocCodes + cfg.PracticeTriggerOffset;
practiceQ1Code = cfg.MainQ1Code + cfg.PracticeTriggerOffset;
practiceQ2Code = cfg.MainQ2Code + cfg.PracticeTriggerOffset;
practiceTrialEndCode = cfg.MainTrialEndCode + cfg.PracticeTriggerOffset;

bdfEventNums = arrayfun(@(e) localEventTypeToNumber(e.type), EEG_clean.event);
bdfEventCodeInventoryCsv = fullfile(outDir, sprintf('%s_BdfEventCodeInventory.csv', participantID));
localWriteBdfEventCodeInventory(bdfEventNums, bdfEventCodeInventoryCsv);
localWarnLegacyTriggerCodes(bdfEventNums, cfg);

fprintf('\nAscending v3 trigger scheme reference:\n');
fprintf('  Main:    S1=%d S2=%d Q1=%d PAS=%s Q2=%d LOC=%s trialEnd=%d\n', ...
    cfg.MainS1Code, cfg.MainS2Code, cfg.MainQ1Code, mat2str(mainPasCodes), ...
    cfg.MainQ2Code, mat2str(mainLocCodes), cfg.MainTrialEndCode);
fprintf('  Practice (+100): S1=%d S2=%d Q1=%d PAS=%s Q2=%d LOC=%s trialEnd=%d\n', ...
    practiceS1Code, practiceS2Code, practiceQ1Code, mat2str(practicePasCodes), ...
    practiceQ2Code, mat2str(practiceLocCodes), practiceTrialEndCode);

% Practice trials are now identified by their own +100 trigger family.
% They are validated separately and are NOT positionally skipped when matching
% the FullRun CSV. Main trial matching uses only the base-code family.
trialsPractice = localExtractTriggeredTrials(EEG_clean, ...
    'FamilyName', 'practice+100', ...
    'S1Code', practiceS1Code, ...
    'S2Code', practiceS2Code, ...
    'PASCodes', practicePasCodes, ...
    'LocCodes', practiceLocCodes, ...
    'PASBase', cfg.MainPASBase + cfg.PracticeTriggerOffset, ...
    'LocBase', cfg.MainLocBase + cfg.PracticeTriggerOffset, ...
    'Q1Code', practiceQ1Code, ...
    'Q2Code', practiceQ2Code, ...
    'TrialEndCode', practiceTrialEndCode, ...
    'RequireResponses', false, ...
    'ValidateTrialMarkers', false);

trialsMain = localExtractTriggeredTrials(EEG_clean, ...
    'FamilyName', 'main', ...
    'S1Code', cfg.MainS1Code, ...
    'S2Code', cfg.MainS2Code, ...
    'PASCodes', mainPasCodes, ...
    'LocCodes', mainLocCodes, ...
    'PASBase', cfg.MainPASBase, ...
    'LocBase', cfg.MainLocBase, ...
    'Q1Code', cfg.MainQ1Code, ...
    'Q2Code', cfg.MainQ2Code, ...
    'TrialEndCode', cfg.MainTrialEndCode, ...
    'RequireResponses', true, ...
    'ValidateTrialMarkers', true);

nPracticeTriggered = numel(trialsPractice.s1EventIdx);
nMainTriggered = numel(trialsMain.s1EventIdx);

fprintf('Practice +100 S1-defined EEG trials: %d\n', nPracticeTriggered);
fprintf('Main base-code S1-defined EEG trials: %d\n', nMainTriggered);

if cfg.ValidatePracticeTriggers && nPracticeTriggered ~= cfg.ExpectedPracticeTrials
    error(['Practice trigger count mismatch. Expected %d practice S1-defined trials ', ...
           '(%d blocks x %d trials) using S1 code %d, found %d.'], ...
        cfg.ExpectedPracticeTrials, cfg.ExpectedPracticeBlocks, cfg.ExpectedPracticeTrialsPerBlock, ...
        practiceS1Code, nPracticeTriggered);
end

if nMainTriggered ~= cfg.ExpectedMainTrials
    error(['Main trigger count mismatch. Expected %d main S1-defined trials ', ...
           '(%d blocks x %d trials) using S1 code %d, found %d.'], ...
        cfg.ExpectedMainTrials, cfg.ExpectedMainBlocks, cfg.ExpectedMainTrialsPerBlock, ...
        cfg.MainS1Code, nMainTriggered);
end

practiceTriggerAuditCsv = fullfile(outDir, sprintf('%s_PracticePlus100TriggerAudit.csv', participantID));
mainTriggerAuditCsv = fullfile(outDir, sprintf('%s_MainTriggerAudit.csv', participantID));
writetable(localMakeTriggeredTrialAuditTable(trialsPractice, 'practice+100'), practiceTriggerAuditCsv);
writetable(localMakeTriggeredTrialAuditTable(trialsMain, 'main'), mainTriggerAuditCsv);

pasBeh = double(T_beh.(varMap.PASVar));
locRespBeh = [];
if ~isempty(varMap.LocRespVar)
    locRespBeh = double(T_beh.(varMap.LocRespVar));
end

locCorrect = localColumnToLogicalCorrect(T_beh.(varMap.LocCorrectVar));
isChange = localColumnToLogicalChange(T_beh.(varMap.IsChangeVar));

pasMismatch = sum(trialsMain.pasResp(:) ~= pasBeh(:), 'omitnan');

if ~isempty(locRespBeh)
    locMismatch = sum(trialsMain.locResp(:) ~= locRespBeh(:), 'omitnan');
else
    locMismatch = NaN;
end

fprintf('\nPAS mismatches EEG main triggers vs CSV: %d\n', pasMismatch);
if isnan(locMismatch)
    fprintf('LOC response mismatch check skipped: no loc response column identified.\n');
else
    fprintf('LOC mismatches EEG main triggers vs CSV: %d\n', locMismatch);
end

if pasMismatch ~= 0
    error('PAS mismatch detected between main EEG triggers and behavioural CSV.');
end

if ~isnan(locMismatch) && locMismatch ~= 0
    error('Localisation response mismatch detected between main EEG triggers and behavioural CSV.');
end

logStep('event_matching', 'OK', 'Practice +100 trigger family validated', ...
    sprintf('%d trials; expected %d = %d x %d', nPracticeTriggered, cfg.ExpectedPracticeTrials, ...
    cfg.ExpectedPracticeBlocks, cfg.ExpectedPracticeTrialsPerBlock), practiceTriggerAuditCsv);
logStep('event_matching', 'OK', 'Main base-code trigger family matched to FullRun CSV', ...
    sprintf('%d trials; expected %d = %d x %d', nMainTriggered, cfg.ExpectedMainTrials, ...
    cfg.ExpectedMainBlocks, cfg.ExpectedMainTrialsPerBlock), mainTriggerAuditCsv);
logStep('event_matching', 'OK', 'PAS mismatches EEG main triggers vs CSV', num2str(pasMismatch), '');
logStep('event_matching', 'OK', 'LOC mismatches EEG main triggers vs CSV', num2str(locMismatch), '');

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

codedSet = sprintf('%s_ds%d_bp0p1to20_avgref_%sRemoved_S1S2coded.set', ...
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
EEG_S2.etc.cb_epoching.fullRunRows = (1:cfg.ExpectedMainTrials)';
EEG_S2 = eeg_checkset(EEG_S2);

s1EpochSet = sprintf('%s_ERP_S1locked_m200to1400_S1base.set', participantID);
s2EpochSet = sprintf('%s_ERP_S2locked_m900to800_S1base.set', participantID);

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

s1CleanSet = sprintf('%s_ERP_S1locked_m200to1400_S1base_ARclean.set', participantID);
s2CleanSet = sprintf('%s_ERP_S2locked_m900to800_S1base_ARclean.set', participantID);

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

finalQcSummary = table( ...
    string(participantID), ...
    numel(flaggedFlatlineLabels), ...
    numel(flaggedLineNoiseLabels), ...
    numel(flaggedCorrelationLabels), ...
    numel(additionalBadScalpLabels), ...
    numel(flaggedBadScalpLabels), ...
    cfg.MaxBadScalpChannels, ...
    nIcaChansUsed, ...
    icaPcaDimUsed, ...
    numel(componentsToRemove), ...
    string(lineNoiseQCStatus), ...
    EEG_S1.trials, ...
    numel(rejectIdx), ...
    numel(keepIdx), ...
    100 * numel(rejectIdx) / EEG_S1.trials, ...
    localConditionCountForCode(countsAfter, 201), ...
    localConditionCountForCode(countsAfter, 202), ...
    localConditionCountForCode(countsAfter, 203), ...
    localConditionCountForCode(countsAfter, 211), ...
    localConditionCountForCode(countsAfter, 212), ...
    cfg.NScalpChans, ...
    EEG_clean.nbchan, ...
    string(datestr(now)), ...
    'VariableNames', { ...
        'ParticipantID', ...
        'NInitialFlatlineFlags', ...
        'NInitialLineNoiseWarnings', ...
        'NPreIcaCorrelationFlags', ...
        'NAdditionalBadScalpChannels', ...
        'NExcludedAndInterpolatedScalpChannels', ...
        'MaxBadScalpChannels', ...
        'NScalpChannelsUsedForICA', ...
        'ICAPcaDimUsed', ...
        'NICAComponentsRemoved', ...
        'LineNoiseQCStatus', ...
        'NEpochsBeforeArtifactRejection', ...
        'NEpochsRejected', ...
        'NEpochsKept', ...
        'PercentEpochsRejected', ...
        'NBlindAfterArtifactRejection', ...
        'NSensingAfterArtifactRejection', ...
        'NSeeingAfterArtifactRejection', ...
        'NNoChangeCRAfterArtifactRejection', ...
        'NNoChangeFAAfterArtifactRejection', ...
        'NFinalScalpChannels', ...
        'NFinalContinuousChannels', ...
        'DecisionTime'});
finalQcSummaryCsv = fullfile(outDir, sprintf('%s_FinalQCSummary.csv', participantID));
writetable(finalQcSummary, finalQcSummaryCsv);
logStep('final_qc', 'OK', 'Saved final participant QC summary', ...
    sprintf('%d channels interpolated; %.1f%% epochs rejected', ...
    numel(flaggedBadScalpLabels), 100 * numel(rejectIdx) / EEG_S1.trials), finalQcSummaryCsv);

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
report.badChannelDecisionTable = badChannelTable;
report.initialChannelQcTableCsv = initialChannelQcTableCsv;
report.initialChannelQcSummaryCsv = initialChannelQcSummaryCsv;
report.preIcaCorrelationQcCsv = preIcaCorrelationCsv;
report.additionalBadScalpChannels = cellstr(additionalBadScalpLabels);
report.maxBadScalpChannels = cfg.MaxBadScalpChannels;
report.badChannelsRemoved = ~isempty(flaggedBadScalpLabels);
report.badChannelsInterpolated = ~isempty(flaggedBadScalpLabels);
report.interpolationMethod = 'spherical';
report.finalMontageRestored = true;
report.lineNoiseQCTableCsv = lineNoiseQCTableCsv;
report.lineNoiseQCSummaryCsv = lineNoiseQCSummaryCsv;
report.lineNoiseQCPlotDir = lineNoisePlotDir;
report.runLineNoiseQC = cfg.RunLineNoiseQC;
report.lineNoiseQCStatus = lineNoiseQCStatus;
report.cleanRawDataConsoleLogFile = cleanRawDataConsoleLogFile;
report.nGoodScalpChannelsForICA = nIcaChansUsed;
report.goodScalpChannelsForICA = cellstr(goodScalpLabels);
report.icaPcaDimRequested = cfg.ICAPcaDim;
report.icaPcaDimAutomatic = icaPcaDimAutomatic;
report.icaPcaDimUsed = icaPcaDimUsed;
report.nIcaChannelsUsed = nIcaChansUsed;
report.icaElapsedSec = icaElapsedSec;
report.icaElapsedMin = icaElapsedSec/60;
report.cleanContinuousSet = cleanSet;
report.finalContinuousChannelLabels = cellstr(string({EEG_clean.chanlocs.labels})');
report.codedContinuousSet = codedSet;
report.s1EpochSet = s1EpochSet;
report.s2EpochSet = s2EpochSet;
report.s1CleanSet = s1CleanSet;
report.s2CleanSet = s2CleanSet;
report.countsBeforeAR = countsBefore;
report.countsAfterAR = countsAfter;
report.finalQcSummary = finalQcSummary;
report.finalQcSummaryCsv = finalQcSummaryCsv;
report.plotReport = plotReport;
report.runExtraFinalPlots = cfg.RunExtraFinalPlots;
report.extraFinalPlotOutputs = extraPlotOutputs;

finalReportMat = fullfile(outDir, sprintf('%s_FinalPipelineReport.mat', participantID));
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


function [flaggedLabels, flaggedIndices] = localRunCleanRawDataChannelCheck( ...
    EEG_badcheck, labelsBefore, cfg, passLabel, varargin)

labelsBefore = string(labelsBefore(:));
% Clean RawData requires the literal value 'off' to disable individual
% criteria. Pass the arguments through unchanged: replacing 'off' with
% Inf/0 still runs clean_channels and contaminates isolated QC passes.
cleanArgs = varargin;

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
excludedFromIcaCol = ismember(originalScalpLabels, flaggedBadScalpLabels);
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
    participantCol, stageCol, origIdxCol, labelCol, excludedFromIcaCol, lineNoiseFlagCol, ...
    lineFreqCol, powerAtLineCol, neighbourBandCol, neighbourMedCol, ratioCol, ratioDbCol, ...
    stageNoteCol, decisionCol, ...
    'VariableNames', { ...
        'ParticipantID', ...
        'Stage', ...
        'OriginalScalpIndex', ...
        'Label', ...
        'IsExcludedFromICAAndERP', ...
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
        sum(stageRows.IsExcludedFromICAAndERP), ...
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
            'NChannelsExcludedFromICAAndERP', ...
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
    case 'FinalERPclean_0p1to20Hz'
        stageNote = sprintf('%g Hz expected to be strongly attenuated by the %.0f Hz low-pass; final data are post-ICA and interpolated', ...
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
legacyMetadata = [65:69, 70:82, 90:109];

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


s2Ev = EEG.event(trialsMain.s2EventIdx(i));
s2Ev.type = num2str(s2Codes(i));
s2Ev.latency = trialsMain.s2Latency(i);
s2Ev.cb_mainTrial = i;
s2Ev.cb_fullRunRow = i;
s2Ev.cb_outcome = char(outcome(i));
s2Ev.cb_synthetic = 1;
s2Ev.cb_lock = 'S2';

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


function [flatlineLabels, flatlineIndices, lineNoiseLabels, lineNoiseIndices, ...
    tableCsv, summaryCsv] = localRunInitialScalpChannelQC( ...
    EEG_ds, cfg, participantID, originalScalpLabels, originalScalpChanlocs, outDir)

originalScalpLabels = string(originalScalpLabels(:));
nScalp = numel(originalScalpLabels);
flatlineLabels = strings(0, 1);
flatlineIndices = [];
lineNoiseLabels = strings(0, 1);
lineNoiseIndices = [];

if cfg.RunBadChannelChecker
    localValidateScalpChanlocs(originalScalpChanlocs);
    if exist('pop_clean_rawdata', 'file') ~= 2
        error(['Clean RawData plugin function pop_clean_rawdata was not found. ', ...
            'Install/enable EEGLAB Clean RawData before using RunBadChannelChecker.']);
    end

    EEG_scalp = pop_select(EEG_ds, 'channel', 1:cfg.NScalpChans);
    EEG_scalp = localFixChanlocsForICLabel(EEG_scalp);
    EEG_scalp = eeg_checkset(EEG_scalp);
    labelsBefore = string({EEG_scalp.chanlocs.labels});
    labelsBefore = labelsBefore(:);
    commonOffArgs = { ...
        'Highpass', 'off', ...
        'BurstCriterion', 'off', ...
        'WindowCriterion', 'off', ...
        'BurstRejection', 'off'};

    [flatlineLabels, flatlineIndices] = localRunCleanRawDataChannelCheck( ...
        EEG_scalp, labelsBefore, cfg, 'Downsampled flatline check', ...
        'FlatlineCriterion', cfg.BadChannelCheckerFlatlineCriterion, ...
        'LineNoiseCriterion', 'off', ...
        'ChannelCriterion', 'off', ...
        commonOffArgs{:});

    [lineNoiseLabels, lineNoiseIndices] = localRunCleanRawDataChannelCheck( ...
        EEG_scalp, labelsBefore, cfg, 'Downsampled line-noise warning check', ...
        'FlatlineCriterion', 'off', ...
        'LineNoiseCriterion', cfg.BadChannelCheckerLineNoiseCriterion, ...
        'ChannelCriterion', 'off', ...
        commonOffArgs{:});
end

flatlineMask = ismember(originalScalpLabels, flatlineLabels);
lineNoiseMask = ismember(originalScalpLabels, lineNoiseLabels);
decisionTime = string(datestr(now));

initialTable = table( ...
    repmat(string(participantID), nScalp, 1), ...
    (1:nScalp)', ...
    originalScalpLabels, ...
    repmat(logical(cfg.RunBadChannelChecker), nScalp, 1), ...
    flatlineMask, ...
    lineNoiseMask, ...
    flatlineMask, ...
    repmat(cfg.BadChannelCheckerFlatlineCriterion, nScalp, 1), ...
    repmat(cfg.BadChannelCheckerLineNoiseCriterion, nScalp, 1), ...
    repmat(decisionTime, nScalp, 1), ...
    'VariableNames', { ...
        'ParticipantID','OriginalScalpIndex','Label','CheckerRan', ...
        'InitialFlatlineFlag','InitialLineNoiseWarning', ...
        'AutomaticallyExcludedAtInitialStage','FlatlineCriterionSec', ...
        'LineNoiseCriterionSD','DecisionTime'});

summaryTable = table( ...
    string(participantID), ...
    logical(cfg.RunBadChannelChecker), ...
    numel(flatlineLabels), ...
    string(strjoin(flatlineLabels, ', ')), ...
    numel(lineNoiseLabels), ...
    string(strjoin(lineNoiseLabels, ', ')), ...
    decisionTime, ...
    'VariableNames', { ...
        'ParticipantID','CheckerRan','NInitialFlatlineFlags', ...
        'InitialFlatlineLabels','NInitialLineNoiseWarnings', ...
        'InitialLineNoiseWarningLabels','DecisionTime'});

tableCsv = fullfile(outDir, sprintf('%s_InitialChannelQC_Table.csv', participantID));
summaryCsv = fullfile(outDir, sprintf('%s_InitialChannelQC_Summary.csv', participantID));
writetable(initialTable, tableCsv);
writetable(summaryTable, summaryCsv);

end


function [correlationLabels, correlationIndices, tableCsv] = ...
    localRunPreIcaCorrelationQC(EEG_icaFiltered, cfg, participantID, ...
    originalScalpLabels, originalScalpChanlocs, outDir)

originalScalpLabels = string(originalScalpLabels(:));
nScalp = numel(originalScalpLabels);
correlationLabels = strings(0, 1);
correlationIndices = [];

if cfg.RunBadChannelChecker
    localValidateScalpChanlocs(originalScalpChanlocs);
    if exist('pop_clean_rawdata', 'file') ~= 2
        error(['Clean RawData plugin function pop_clean_rawdata was not found. ', ...
            'Install/enable EEGLAB Clean RawData before using RunBadChannelChecker.']);
    end

    EEG_scalp = pop_select(EEG_icaFiltered, 'channel', 1:cfg.NScalpChans);
    EEG_scalp = localFixChanlocsForICLabel(EEG_scalp);
    EEG_scalp = eeg_checkset(EEG_scalp);
    labelsBefore = string({EEG_scalp.chanlocs.labels});
    labelsBefore = labelsBefore(:);

    [correlationLabels, correlationIndices] = localRunCleanRawDataChannelCheck( ...
        EEG_scalp, labelsBefore, cfg, 'Filtered pre-ICA correlation check', ...
        'FlatlineCriterion', 'off', ...
        'LineNoiseCriterion', 'off', ...
        'ChannelCriterion', cfg.BadChannelCheckerCorrelationCriterion, ...
        'Highpass', 'off', ...
        'BurstCriterion', 'off', ...
        'WindowCriterion', 'off', ...
        'BurstRejection', 'off');
end

correlationMask = ismember(originalScalpLabels, correlationLabels);
correlationTable = table( ...
    repmat(string(participantID), nScalp, 1), ...
    (1:nScalp)', ...
    originalScalpLabels, ...
    repmat(logical(cfg.RunBadChannelChecker), nScalp, 1), ...
    correlationMask, ...
    repmat(cfg.BadChannelCheckerCorrelationCriterion, nScalp, 1), ...
    repmat(string(datestr(now)), nScalp, 1), ...
    'VariableNames', { ...
        'ParticipantID','OriginalScalpIndex','Label','CheckerRan', ...
        'PreIcaCorrelationFlag','CorrelationCriterion','DecisionTime'});

tableCsv = fullfile(outDir, sprintf('%s_PreIcaCorrelationQC_Table.csv', participantID));
writetable(correlationTable, tableCsv);

end


function [finalBadLabels, finalBadIndices, additionalBadLabels, decisionTable, ...
    tableCsv, summaryCsv] = localFinalizeBadChannelDecision( ...
    participantID, originalScalpLabels, flatlineLabels, lineNoiseLabels, ...
    correlationLabels, cfg, outDir)

originalScalpLabels = string(originalScalpLabels(:));
flatlineLabels = string(flatlineLabels(:));
lineNoiseLabels = string(lineNoiseLabels(:));
correlationLabels = string(correlationLabels(:));
additionalBadLabels = localCanonicaliseScalpLabels( ...
    cfg.AdditionalBadScalpChannels, originalScalpLabels, 'AdditionalBadScalpChannels');

excludeMask = ismember(originalScalpLabels, flatlineLabels) | ...
    ismember(originalScalpLabels, correlationLabels) | ...
    ismember(originalScalpLabels, additionalBadLabels);
finalBadLabels = originalScalpLabels(excludeMask);
finalBadIndices = find(excludeMask)';

nScalp = numel(originalScalpLabels);
flatlineMask = ismember(originalScalpLabels, flatlineLabels);
lineNoiseMask = ismember(originalScalpLabels, lineNoiseLabels);
correlationMask = ismember(originalScalpLabels, correlationLabels);
additionalMask = ismember(originalScalpLabels, additionalBadLabels);
reason = strings(nScalp, 1);

for i = 1:nScalp
    parts = strings(0, 1);
    if flatlineMask(i)
        parts(end+1) = "Initial flatline (excluded)"; %#ok<AGROW>
    end
    if lineNoiseMask(i)
        parts(end+1) = "Initial line-noise warning only"; %#ok<AGROW>
    end
    if correlationMask(i)
        parts(end+1) = "Filtered pre-ICA low correlation (excluded)"; %#ok<AGROW>
    end
    if additionalMask(i)
        parts(end+1) = "Explicit additional bad channel (excluded)"; %#ok<AGROW>
    end
    if isempty(parts)
        reason(i) = "Retained";
    else
        reason(i) = strjoin(parts, "; ");
    end
end

decisionTime = string(datestr(now));
decisionTable = table( ...
    repmat(string(participantID), nScalp, 1), ...
    (1:nScalp)', ...
    originalScalpLabels, ...
    flatlineMask, ...
    lineNoiseMask, ...
    correlationMask, ...
    additionalMask, ...
    excludeMask, ...
    reason, ...
    repmat(cfg.MaxBadScalpChannels, nScalp, 1), ...
    repmat(decisionTime, nScalp, 1), ...
    'VariableNames', { ...
        'ParticipantID','OriginalScalpIndex','Label','InitialFlatlineFlag', ...
        'InitialLineNoiseWarning','PreIcaCorrelationFlag', ...
        'AdditionalBadScalpChannel','ExcludedFromICAAndERP','DecisionReason', ...
        'MaxBadScalpChannels','DecisionTime'});

summaryTable = table( ...
    string(participantID), ...
    numel(flatlineLabels), ...
    string(strjoin(flatlineLabels, ', ')), ...
    numel(lineNoiseLabels), ...
    string(strjoin(lineNoiseLabels, ', ')), ...
    numel(correlationLabels), ...
    string(strjoin(correlationLabels, ', ')), ...
    numel(additionalBadLabels), ...
    string(strjoin(additionalBadLabels, ', ')), ...
    numel(finalBadLabels), ...
    string(strjoin(finalBadLabels, ', ')), ...
    cfg.MaxBadScalpChannels, ...
    string(datestr(now)), ...
    'VariableNames', { ...
        'ParticipantID','NInitialFlatlineFlags','InitialFlatlineLabels', ...
        'NInitialLineNoiseWarnings','InitialLineNoiseWarningLabels', ...
        'NPreIcaCorrelationFlags','PreIcaCorrelationLabels', ...
        'NAdditionalBadScalpChannels','AdditionalBadScalpChannelLabels', ...
        'NFinalBadScalpChannels','FinalBadScalpChannelLabels', ...
        'MaxBadScalpChannels','DecisionTime'});

tableCsv = fullfile(outDir, sprintf('%s_BadChannelDecisionTable.csv', participantID));
summaryCsv = fullfile(outDir, sprintf('%s_BadChannelDecisionSummary.csv', participantID));
writetable(decisionTable, tableCsv);
writetable(summaryTable, summaryCsv);

end


function canonicalLabels = localCanonicaliseScalpLabels(labelsIn, originalScalpLabels, parameterName)

labelsIn = string(labelsIn(:));
labelsIn = strtrim(labelsIn);
labelsIn = labelsIn(strlength(labelsIn) > 0);
originalScalpLabels = string(originalScalpLabels(:));
canonicalLabels = strings(0, 1);

for i = 1:numel(labelsIn)
    hit = find(strcmpi(originalScalpLabels, labelsIn(i)), 1, 'first');
    if isempty(hit)
        error('%s contains an unknown scalp-channel label: %s', parameterName, labelsIn(i));
    end
    canonicalLabels(end+1,1) = originalScalpLabels(hit); %#ok<AGROW>
end
canonicalLabels = unique(canonicalLabels, 'stable');

end


function [EEG, interpolationApplied] = localInterpolateAndRestoreMontage( ...
    EEG, badScalpLabels, originalAllChanlocs, originalAllLabels, ...
    originalExternalLabels, cfg)

badScalpLabels = string(badScalpLabels(:));
originalAllLabels = string(originalAllLabels(:));
interpolationApplied = ~isempty(badScalpLabels);
pointsBefore = EEG.pnts;
samplingRateBefore = EEG.srate;
trialsBefore = EEG.trials;
eventLatenciesBefore = [EEG.event.latency];

if interpolationApplied
    EEG = pop_interp(EEG, originalAllChanlocs, 'spherical');
    EEG = eeg_checkset(EEG);
end

currentLabels = string({EEG.chanlocs.labels});
currentLabels = currentLabels(:);
if numel(currentLabels) ~= numel(originalAllLabels) || ...
        ~all(ismember(lower(originalAllLabels), lower(currentLabels)))
    error('Could not restore the complete original channel montage after interpolation.');
end

restoreOrder = localFindExistingChannelsByLabels(EEG, originalAllLabels);
if ~isequal(restoreOrder, 1:numel(originalAllLabels))
    EEG = pop_select(EEG, 'channel', restoreOrder);
end

externalIdx = localFindExistingChannelsByLabels(EEG, originalExternalLabels);
EEG = pop_reref(EEG, [], 'exclude', externalIdx);
EEG = localFixChanlocsForICLabel(EEG);
EEG = eeg_checkset(EEG);

restoredLabels = string({EEG.chanlocs.labels});
restoredLabels = restoredLabels(:);
if EEG.nbchan ~= cfg.TotalExpectedChans || ~isequal(restoredLabels, originalAllLabels)
    error('Final channel montage does not match the original %d-channel label order.', ...
        cfg.TotalExpectedChans);
end
if EEG.pnts ~= pointsBefore || EEG.srate ~= samplingRateBefore || EEG.trials ~= trialsBefore || ...
        ~isequal([EEG.event.latency], eventLatenciesBefore)
    error('Interpolation or final rereferencing changed data dimensions or event latencies.');
end

end


function n = localConditionCountForCode(countTable, code)

idx = find(countTable.Code == code, 1, 'first');
if isempty(idx)
    n = 0;
else
    n = countTable.N(idx);
end

end


function value = localGetNameValueText(args, parameterName, defaultValue)

value = char(defaultValue);
for k = 1:2:numel(args)
    if k+1 <= numel(args) && (ischar(args{k}) || isstring(args{k})) && ...
            strcmpi(char(args{k}), parameterName)
        value = char(args{k+1});
        return;
    end
end

end
