%% One-Shot Change Blindness (4 gratings) + Fixed Orientation Magnitudes + PAS First
% Stage 3 variant derived from CB_4xGratings_v3 with passive Tobii/Titta eye tracking
% and EEG triggers retained.
% - 2x2 grid of Gabors/gratings
% - Fixed timing: Fix -> S1(600 ms) -> ISI(200 ms) -> S2(600 ms) -> Gap(200 ms)
% - Questions: Q1 PAS clarity (1-4) -> Q2 Detection (Yes/No) -> Q3 Localisation (4AFC)
% - No QUEST+: orientation-change magnitude is fixed by trial.
% - Main run: 600 trials, 456 change trials balanced across 22.5, 45, 67.5, and 90 deg
%   (114 change trials per magnitude) plus 144 no-change catch trials.



function CB_4xGratings_v3_Orientation

close all;

% ---- HARD RESET keyboard state BEFORE ANY PTB keyboard queues ----
% Prevents: "KbQueueCreate ... already in use by GetChar() et al."
try ListenChar(0); catch, end
try KbQueueRelease(-1); catch, end
try IOPort('CloseAll'); catch, end

% ---- Safer "close screens" (in case sca isn't on path temporarily)
if exist('sca','file') == 2
    sca;
elseif exist('Screen','file') == 2
    Screen('CloseAll');
end

KbName('UnifyKeyNames');

%% ------------------------- USER CONFIG -------------------------
cfg = struct();
cfg.outputPrefix = 'CB_4xGratings_v3_Orientation';
cfg.questionOrder = 'PAS>Detection>Localisation';
cfg.detectionKeyMapping = 'green:a=yes;red:f=no';
cfg.eegQuestionTriggerScheme = 'Q1_PAS_30-34;Q2_Detection_40-42;Q3_Localisation_50-54';

cfg.participantID = input('Enter Participant ID (e.g., S001): ', 's');
if isempty(cfg.participantID), cfg.participantID = 'UNKNOWN'; end

cfg.debugWindow      = false;     % smaller window
cfg.visualDebugLevel = 1;
cfg.skipSyncTests    = 0;         % 1 while debugging; use 0 for real data

% Screen selection (don't use 0 unless you WANT desktop-spanning)
% cfg.screenNumber = max(Screen('Screens'));
  cfg.screenNumber = 2;

% Keyboard device: -1 = default keyboard
cfg.kbDev = -1;

% ---- EEG serial triggers: main trials use base codes; Practice Blocks 1 & 2 use base + practiceCodeOffset ----
% Behaviour-only testing: cfg.eeg.enable = false;
% Lab EEG/trigger testing (current): cfg.eeg.enable = true; COM7 @ 115200
cfg.eeg.enable            = true;
cfg.eeg.requirePort       = true;   % abort if the COM port cannot be opened
cfg.eeg.serialPort        = 'COM7';
cfg.eeg.baudRate          = 115200;
cfg.eeg.warnOnSendError   = true;

% resetMode: 'trialEndOnly' = zero reset only after trialEnd; set to 'blocking' for per-trigger A/B comparison
% emitTrigger reads cfg.eeg.resetMode (not cfg.trigger.resetMode)
cfg.eeg.resetMode         = 'trialEndOnly';  % options: 'none', 'blocking', 'trialEndOnly', 'deferred'
cfg.eeg.pulseWidthSec     = 0.002;         % used when resetMode = 'blocking' or 'trialEndOnly'

cfg.eeg.codes = struct();
cfg.eeg.codes.trialStart = 11;
cfg.eeg.codes.s1On       = 21;
cfg.eeg.codes.isiOn      = 22;
cfg.eeg.codes.s2On       = 23;
cfg.eeg.codes.gapOn      = 24;
cfg.eeg.codes.q1On       = 30; % Q1 PAS onset
cfg.eeg.codes.pasBase    = 30; % PAS response = 30 + PAS value (31-34)
cfg.eeg.codes.q2On       = 40; % Q2 detection onset
cfg.eeg.codes.detectNo   = 41; % Q2 detection response: no
cfg.eeg.codes.detectYes  = 42; % Q2 detection response: yes
cfg.eeg.codes.q3On       = 50; % Q3 localisation onset
cfg.eeg.codes.locBase    = 50; % LOC response = 50 + quadrant value (51-54)
cfg.eeg.codes.trialEnd   = 60;
% Ascending within-trial EEG trigger suite (main trials):
%   11 trial start/fixation, 21 S1, 22 ISI, 23 S2, 24 gap,
%   30 Q1 PAS, 31-34 PAS response, 40 Q2 detection, 41 no / 42 yes,
%   50 Q3 localisation, 51-54 LOC response, 60 trial end then reset to 0.
% Practice uses the same suite with practiceCodeOffset (+100 -> 111-160 family):
%   111 fix, 121 S1, 122 ISI, 123 S2, 124 gap, 130 Q1 PAS, 131-134 PAS,
%   140 Q2 detection, 141/142 detection, 150 Q3 LOC, 151-154 LOC, 160 trial end.
% Fixed timing, change magnitude, detection, localisation, PAS, and outcome metadata
% are saved to FullRun CSV, MAT, Tobii, and triggerLog but are NOT sent as EEG pulses.

cfg.eeg.practiceCodeOffset = 100;   % practice triggers = main code + 100 (111-160 family)

cfg.eeg.markerPolicy = struct();
cfg.eeg.markerPolicy.markPracticeTrials  = true;
cfg.eeg.markerPolicy.markPracticeBlock1  = true;
cfg.eeg.markerPolicy.markPracticeBlock2  = true;
cfg.eeg.markerPolicy.markAuxScreens      = false;
cfg.eeg.markerPolicy.markResponses       = true;
cfg.eeg.markerPolicy.markMainTrials      = true;

% ---- Tobii/Titta eye tracking (Stage 3: passive only) ----
% Passive recording only: no online fixation rejection, no gaze-contingent timing,
% no online fixation rejection and no gaze-contingent timing or stimulus selection.
cfg.tobii = struct();
cfg.tobii.enable                  = true;
cfg.tobii.requireTracker          = true;
cfg.tobii.trackerProfile          = 'IS4_Large_Peripheral';
cfg.tobii.tittaRoot               = 'C:\Users\hrl310\Documents\MATLAB\Titta-master\Titta-master';
cfg.tobii.debugMode               = true;
cfg.tobii.useAnimatedCalibration  = true;
cfg.tobii.saveMat                 = true;
cfg.tobii.saveGazeCSV             = true;
cfg.tobii.deleteIntermediateTSV   = true;
cfg.tobii.warnOnMessageError       = false;

% Because CB_4xGratings_v3 calls PsychDefaultSetup(2), the main CB task uses 0-1 PTB colours.
% Titta's setup/calibration/validation UI behaves correctly on this system with 0-255 colours.
cfg.tobii.ui.bgColor              = 127;
cfg.tobii.ui.textColor            = 0;
cfg.tobii.ui.fixBackColor         = 0;
cfg.tobii.ui.fixFrontColor        = 255;

% ---- Display profile ----
% Options: 'viewpixx' (lab monitor), 'default' (general monitor fallback)
cfg.displayProfile = 'viewpixx';
cfg.display = makeDisplayProfile(cfg.displayProfile);

% Trial overview PNG: same folder as this script (do not use pwd — depends on MATLAB current folder).
cfg.trialOverviewFilename = 'Gratings_TrialOverview.png';

% ---- Practice flow ----
cfg.practice.enable = true;

% Global practice settings
cfg.practice.feedbackWaitForSpace = true;   % lock feedback until SPACE
cfg.practice.logToCommandWindow   = true;

% ---------- Practice Block 1 (with feedback; wider range / anchoring) ----------
cfg.practice1.enable    = true;
cfg.practice1.name      = 'Practice Block 1';
cfg.practice1.feedback  = true;

% Trial composition (10 total: 4 STD, 3 EASY, 3 NCH)
cfg.practice1.nSTD      = 4;    % standard change trials
cfg.practice1.nNCH      = 3;    % no-change trials
cfg.practice1.nEASY     = 3;    % obvious/easy change trials
cfg.practice1.nTrials   = cfg.practice1.nSTD + cfg.practice1.nNCH + cfg.practice1.nEASY;

% Optional: restrict "easy" changes to stronger/more obvious starts later if needed
cfg.practice1.easyUsesSameChangeRule = true;

% Orientation-change magnitudes used in practice. Timing is fixed globally.
cfg.practice1.magnitudeSTDDeg  = 45;
cfg.practice1.magnitudeEASYDeg = 90;
cfg.practice1.magnitudeNCHDeg  = 0;

% ---------- Practice Block 2 (reduced/no feedback; closer to calibration) ----------
cfg.practice2.enable    = true;
cfg.practice2.name      = 'Practice Block 2';
cfg.practice2.feedback  = false;

% Trial composition (10 total: 4 STD, 3 EASY, 3 NCH)
cfg.practice2.nSTD      = 4;
cfg.practice2.nNCH      = 3;
cfg.practice2.nEASY     = 3;
cfg.practice2.nTrials   = cfg.practice2.nSTD + cfg.practice2.nNCH + cfg.practice2.nEASY;

cfg.practice2.easyUsesSameChangeRule = true;

% Orientation-change magnitudes used in practice. Timing is fixed globally.
cfg.practice2.magnitudeSTDDeg  = 45;
cfg.practice2.magnitudeEASYDeg = 90;
cfg.practice2.magnitudeNCHDeg  = 0;

% Both practice blocks use the global fixed S1/ISI/S2/gap timing. Trial type
% changes orientation magnitude only; practice-specific durations are not used.

% ---------- Practice classification criteria ----------
cfg.practice1Criteria.maxFARateNCH   = 0.60;
cfg.practice1Criteria.minEasyDetect  = 0.60;
cfg.practice1Criteria.minEasySee     = 0.40;

% ---- Fixed orientation-magnitude design ----
cfg.calib.maxTrials = 600;             % retained name for output compatibility
cfg.design = struct();
cfg.design.changeMagnitudesDeg = [22.5 45 67.5 90];
cfg.design.noChangeMagnitudeDeg = 0;
cfg.design.balanceChangeMagnitudes = true;

% Trial counts - 600-trial full lab run (12 blocks x 50 trials)
cfg.debug.trialLog = false;
cfg.debug.logHeaderEachBlock = true;
cfg.debug.quickRun = false;   % true = ultra-short formatting/test run; false = real/full run
cfg.debug.quickRunMagnitudesDeg  = [22.5 45 67.5 90];
cfg.debug.quickRunChangeCounts   = [4 4 4 4];  % totals across the complete quick run
cfg.debug.quickRunNoChangeTrials = 4;
cfg.debug.quickRunTrialsPerBlock = 10;

cfg.nTotal = cfg.calib.maxTrials;
cfg.trialsPerBlock = 50;
cfg.nBlocks = cfg.nTotal / cfg.trialsPerBlock;

cfg.trialDial.applyPerBlock = true;
cfg.trialDial.nChangePerBlock   = 38;
cfg.trialDial.nNoChangePerBlock = 12;

% ---- DEBUG QUICK RUN (overrides counts above when enabled) ----
if cfg.debug.quickRun
    fprintf('\n*** DEBUG QUICK RUN ENABLED: NOT FOR REAL DATA COLLECTION ***\n');

    cfg.practice1.nSTD = 1;  cfg.practice1.nEASY = 1;  cfg.practice1.nNCH = 1;
    cfg.practice1.nTrials = cfg.practice1.nSTD + cfg.practice1.nEASY + cfg.practice1.nNCH;

    cfg.practice2.nSTD = 1;  cfg.practice2.nEASY = 1;  cfg.practice2.nNCH = 1;
    cfg.practice2.nTrials = cfg.practice2.nSTD + cfg.practice2.nEASY + cfg.practice2.nNCH;

    [quickMags, quickCounts, quickNCH, quickTrialsPerBlock] = validateQuickRunProfile(cfg.debug);

    cfg.design.changeMagnitudesDeg = quickMags;
    cfg.design.changeCountsPerMagnitude = quickCounts;
    cfg.nChange = sum(quickCounts);
    cfg.nCatch = quickNCH;
    cfg.nTotal = cfg.nChange + cfg.nCatch;
    cfg.calib.maxTrials = cfg.nTotal;
    cfg.trialsPerBlock = quickTrialsPerBlock;
    cfg.nBlocks = cfg.nTotal / cfg.trialsPerBlock;
    cfg.trialDial.nChangePerBlock = cfg.nChange / cfg.nBlocks;
    cfg.trialDial.nNoChangePerBlock = cfg.nCatch / cfg.nBlocks;
else
    cfg.nChange = cfg.nBlocks * cfg.trialDial.nChangePerBlock;      % 456 in full run
    cfg.nCatch  = cfg.nBlocks * cfg.trialDial.nNoChangePerBlock;    % 144 in full run

    assert(mod(cfg.nChange, numel(cfg.design.changeMagnitudesDeg)) == 0, ...
        'Full-run change trials must be divisible by the number of orientation magnitudes.');
    cfg.design.changeCountsPerMagnitude = repmat( ...
        cfg.nChange / numel(cfg.design.changeMagnitudesDeg), ...
        1, numel(cfg.design.changeMagnitudesDeg));
end

cfg.trialDial.pChange = cfg.trialDial.nChangePerBlock / cfg.trialsPerBlock;

assert(mod(cfg.nTotal, cfg.trialsPerBlock) == 0, ...
    'nTotal must be divisible by trialsPerBlock');
assert(cfg.trialDial.nChangePerBlock + cfg.trialDial.nNoChangePerBlock == cfg.trialsPerBlock, ...
    'Per-block change + no-change counts must equal trialsPerBlock');
assert(numel(cfg.design.changeMagnitudesDeg) == numel(cfg.design.changeCountsPerMagnitude), ...
    'Magnitude and magnitude-count vectors must have the same length.');
assert(sum(cfg.design.changeCountsPerMagnitude) == cfg.nChange, ...
    'Magnitude-specific change counts must sum to nChange.');

if all(cfg.design.changeCountsPerMagnitude == cfg.design.changeCountsPerMagnitude(1))
    cfg.nChangePerMagnitude = cfg.design.changeCountsPerMagnitude(1);
else
    cfg.nChangePerMagnitude = NaN;  % legacy scalar is undefined for unequal magnitude counts
end

% Timing (seconds)
cfg.fixJitterRangeSec = [1.00 1.50];  % fixation before S1
cfg.S1_sec            = 0.600;
cfg.ISI_sec           = 0.200;
cfg.S2_sec            = 0.600;
cfg.postS2Gap_sec     = 0.200;         % gap between S2 and Q1
cfg.ITI_sec           = 1.00;          % after final PAS response
cfg.maxRespSec        = 30.00;         % failsafe

% Grating/mask appearance (visual-angle locked; converted to px at runtime)
cfg.stim.squareSizeDeg  = 3.5;
cfg.stim.spacingDeg     = 2.3;   % per-axis offset; gives 2.2 deg radial eccentricity
cfg.stim.cyclesPerStim  = 10;
cfg.stim.contrast       = 0.8;
cfg.stim.backgroundGrey = 0.5;
cfg.stim.gaborSigmaFrac = 0.40;
cfg.stim.allowedOri = 0:22.5:157.5;
cfg.stim.changeAngleDeg = NaN;    % per-trial value comes from cfg.design.changeMagnitudesDeg

% Fixation (visual-angle locked; converted to px at runtime)
cfg.fix.sizeDeg      = 0.37;
cfg.fix.lineWidthDeg = 0.08;

%% ------------------------- DEPENDENCY CHECKS -------------------------
try
    PsychDefaultSetup(2);
catch
    error('Psychtoolbox not found. Install Psychtoolbox-3 first.');
end

% Keys
cfg.keys.escape = KbName('ESCAPE');
cfg.keys.space  = KbName('space');

% Q1 PAS: left hand (q/w/e/r). Q2 detection: A=Yes/green, F=No/red.
% Q3 localisation: right hand (numpad 7/9/1/3).
% If numpad keys fail at runtime, run KbName interactively (e.g. KbName('KP_7'))
% to confirm correct names on this system - do not remap to top-row number keys.
cfg.keys.detectPhysical = {'a','f'};
cfg.keys.detectValues   = [1 0];

cfg.keys.quadPhysical = {'7','9','1','3'};
cfg.keys.quadValues   = [1 2 3 4];

cfg.keys.pasPhysical = {'q','w','e','r'};
cfg.keys.pasValues   = [1 2 3 4];

cfg.keys.detect = KbName(cfg.keys.detectPhysical);
cfg.keys.quad   = KbName(cfg.keys.quadPhysical);
cfg.keys.pas    = KbName(cfg.keys.pasPhysical);

fprintf('DETECTION key mapping: a=Yes (GREEN sticker), f=No (RED sticker)\n');
fprintf('LOC key mapping: numpad7=1, numpad9=2, numpad1=3, numpad3=4\n');
fprintf('PAS key mapping: q=1, w=2, e=3, r=4\n');
fprintf('DETECTION KbName codes: %s\n', mat2str(cfg.keys.detect));
fprintf('LOC KbName codes: %s\n', mat2str(cfg.keys.quad));
fprintf('PAS KbName codes: %s\n', mat2str(cfg.keys.pas));


%% ------------------------- SETUP PTB -------------------------
Screen('Preference','VisualDebugLevel', cfg.visualDebugLevel);
Screen('Preference','SkipSyncTests', cfg.skipSyncTests);

bg    = cfg.stim.backgroundGrey;   % <-- define BEFORE OpenWindow
black = 0;

window = [];
cleanupObj = []; %#ok<NASGU> % remains empty only if OpenWindow fails before onCleanup is created

%% ------------ FAILSAFE LOGGING ------------ %%
outDir = fullfile(pwd, 'data');
if ~exist(outDir,'dir'), mkdir(outDir); end
timestamp = datestr(now,'yyyymmdd_HHMMSS');
outFile = fullfile(outDir, sprintf('%s_%s_FullRun_%s.csv', cfg.outputPrefix, cfg.participantID, timestamp));

cfg.trigger = initSerialTrigger(cfg.eeg);

if cfg.eeg.enable && cfg.eeg.requirePort && ~cfg.trigger.enabled
    error(['EEG serial trigger port could not be opened. ' ...
           'Close any programme using %s, run IOPort(''CloseAll''), reconnect the trigger device if needed, then try again.'], ...
           cfg.eeg.serialPort);
end

% Tobii state is kept in the parent function so loggedFlip and response events can send messages.
tobii = makeEmptyTobiiState();

try
    if cfg.debugWindow
        [window, windowRect] = PsychImaging('OpenWindow', cfg.screenNumber, bg, [100 100 900 700]);
    else
        [window, windowRect] = PsychImaging('OpenWindow', cfg.screenNumber, bg);
    end
    fprintf('Reached: OpenWindow OK\n');

    cleanupObj = onCleanup(@() cleanup(window, cfg));

    Screen('BlendFunction', window, 'GL_SRC_ALPHA', 'GL_ONE_MINUS_SRC_ALPHA');
    Screen('TextFont', window, 'Arial');
    Screen('TextSize', window, 45);

    ifi = Screen('GetFlipInterval', window);

    flipLog = struct( ...
        'idx', {}, ...
        'label', {}, ...
        'context', {}, ...
        'trialNum', {}, ...
        'blockNum', {}, ...
        'scheduled', {}, ...
        'when', {}, ...
        'vbl', {}, ...
        'stimOnsetTime', {}, ...
        'flipTimestamp', {}, ...
        'missed', {}, ...
        'missedFlag', {} ...
    );
    flipN = 0;
    cfg.loggedFlip = @loggedFlip;
    cfg.emitTrigger = @emitTrigger;
    cfg.emitTobii = @emitTobiiMessage;

    triggerLog = struct( ...
        'idx', {}, ...
        'label', {}, ...
        'context', {}, ...
        'trialNum', {}, ...
        'blockNum', {}, ...
        'code', {}, ...
        'linkedFlipLabel', {}, ...
        'linkedFlipTime', {}, ...
        'rtFromLinkedFlipMs', {}, ...
        'sendStart', {}, ...
        'sendEnd', {}, ...
        'sendDurationMs', {}, ...
        'enabled', {}, ...
        'error', {} ...
    );
    triggerN = 0;

    [xCentre, yCentre] = RectCenter(windowRect);

    % ---- Display geometry conversion for visual-angle locked stimuli ----
    geom = computeDisplayGeometry(cfg.display, windowRect);
    cfg.display.geom = geom;

    cfg.stim.squareSizePx = max(10, round(degToPx(cfg.stim.squareSizeDeg, geom)));
    cfg.stim.spacingPx    = max(5,  round(degToPx(cfg.stim.spacingDeg, geom)));
    cfg.fix.sizePx        = max(4,  round(degToPx(cfg.fix.sizeDeg, geom)));
    cfg.fix.lineWidthPx   = max(1,  round(degToPx(cfg.fix.lineWidthDeg, geom)));

    fprintf(['Display geometry (%s): pxPerCm=%.3f | pxPerDeg=%.3f | ', ...
             'square=%.2fdeg->%dpx | spacing=%.2fdeg->%dpx | fix=%.2fdeg->%dpx | fixLW=%.2fdeg->%dpx\n'], ...
        cfg.display.profile, geom.pixelsPerCm, geom.pxPerDeg, ...
        cfg.stim.squareSizeDeg, cfg.stim.squareSizePx, ...
        cfg.stim.spacingDeg, cfg.stim.spacingPx, ...
        cfg.fix.sizeDeg, cfg.fix.sizePx, ...
        cfg.fix.lineWidthDeg, cfg.fix.lineWidthPx);

    % Convert timing to frames
    cfg.S1_frames       = max(1, round(cfg.S1_sec / ifi));
    cfg.ISI_frames      = max(1, round(cfg.ISI_sec / ifi));
    cfg.S2_frames       = max(1, round(cfg.S2_sec / ifi));
    cfg.gap_frames      = max(0, round(cfg.postS2Gap_sec / ifi));
    cfg.ITI_frames      = max(0, round(cfg.ITI_sec / ifi));
    cfg.fixJitterFrames = round(cfg.fixJitterRangeSec / ifi);

    fprintf('\nFixed orientation-magnitude run\n');
    if cfg.debug.quickRun
        fprintf('*** DEBUG QUICK RUN ENABLED: NOT FOR REAL DATA COLLECTION ***\n');
    end
    fprintf('Total trials: %d\n', cfg.nTotal);
    fprintf('Blocks: %d\n', cfg.nBlocks);
    fprintf('Trials/block: %d\n', cfg.trialsPerBlock);
    fprintf('Change/block: %d\n', cfg.trialDial.nChangePerBlock);
    fprintf('No-change/block: %d\n', cfg.trialDial.nNoChangePerBlock);
    fprintf('Total change: %d\n', cfg.nChange);
    fprintf('Total no-change: %d\n', cfg.nCatch);
    fprintf('Change magnitudes: %s deg\n', mat2str(cfg.design.changeMagnitudesDeg));
    fprintf('Change counts by magnitude: %s\n', mat2str(cfg.design.changeCountsPerMagnitude));
    fprintf('Question order: %s\n', cfg.questionOrder);
    fprintf('Detection buttons: %s\n', cfg.detectionKeyMapping);
    fprintf('Question trigger scheme: %s\n', cfg.eegQuestionTriggerScheme);
    fprintf('S1_frames: %d (~%.0f ms at %.1f Hz)\n', cfg.S1_frames, cfg.S1_frames * ifi * 1000, 1/ifi);
    fprintf('ISI_frames: %d (~%.0f ms at %.1f Hz)\n', cfg.ISI_frames, cfg.ISI_frames * ifi * 1000, 1/ifi);
    fprintf('S2_frames: %d (~%.0f ms at %.1f Hz)\n', cfg.S2_frames, cfg.S2_frames * ifi * 1000, 1/ifi);
    fprintf('Gap_frames: %d (~%.0f ms at %.1f Hz)\n', cfg.gap_frames, cfg.gap_frames * ifi * 1000, 1/ifi);
    if cfg.debug.trialLog
        fprintf('Trial logging: ON\n\n');
    else
        fprintf('Trial logging: OFF\n\n');
    end

    topPriorityLevel = MaxPriority(window);
    Priority(topPriorityLevel);
    HideCursor;

    %% ------------------------- TOBII CALIBRATION --------------------------
    tobii = initialiseAndCalibrateTobii(tobii, cfg, window);

    ListenChar(0);

    try KbQueueRelease(cfg.kbDev); catch, end
    KbQueueCreate(cfg.kbDev);
    KbQueueStart(cfg.kbDev);
    KbQueueFlush(cfg.kbDev);

    %% ------------------------- FIXED DESIGN SETUP -------------------------
    fprintf('Fixed design initialized: no QUEST+, no adaptive duration.\n');
    fprintf('Main change trial inventory:\n');
    for mm = 1:numel(cfg.design.changeMagnitudesDeg)
        fprintf('  %.12g deg: %d change trials\n', ...
            cfg.design.changeMagnitudesDeg(mm), cfg.design.changeCountsPerMagnitude(mm));
    end
    

    %% ------------------------- STIMULUS GEOMETRY ---------------------------
    baseRect = [0 0 cfg.stim.squareSizePx cfg.stim.squareSizePx];
    xPos = [xCentre - cfg.stim.spacingPx, xCentre + cfg.stim.spacingPx, ...
            xCentre - cfg.stim.spacingPx, xCentre + cfg.stim.spacingPx];
    yPos = [yCentre - cfg.stim.spacingPx, yCentre - cfg.stim.spacingPx, ...
            yCentre + cfg.stim.spacingPx, yCentre + cfg.stim.spacingPx];

    allRects = nan(4,4);          % 4 rects x 4 coords
    for i = 1:4
        allRects(i,:) = CenterRectOnPoint(baseRect, xPos(i), yPos(i));
    end

    gratingTex = makeGratingTexture(window, cfg.stim.squareSizePx, cfg.stim.cyclesPerStim, cfg.stim.contrast, bg, cfg.stim.gaborSigmaFrac);
    fixationCoords = [-cfg.fix.sizePx cfg.fix.sizePx 0 0; 0 0 -cfg.fix.sizePx cfg.fix.sizePx];

    qTex = cacheQuestionTextures(window, windowRect, black, bg, cfg);
    cfg.qTex = qTex;

    %% ------------------------- TRIAL LIST ----------------------------------
    trials = buildTrialList(cfg);

    for b = 1:cfg.nBlocks
        ii = (b-1)*cfg.trialsPerBlock + (1:cfg.trialsPerBlock);
        nC  = sum([trials(ii).isChange] == 1);
        nNC = sum([trials(ii).isChange] == 0);
        fprintf('Block %02d: C=%d  NC=%d\n', b, nC, nNC);
    end

    %% ------------------------- START TOBII RECORDING ----------------------
    % Record the full visible session: instructions, overview, practice, main trials, breaks, and end screen.
    tobii = startTobiiRecording(tobii, cfg, windowRect, ifi, timestamp);
    emitTobiiMessage('RUN_START', 'runStart', 'experiment', NaN, NaN, GetSecs, ...
        sprintf('participantID=%s timestamp=%s screen=%d res=%dx%d hz=%.3f nTotal=%d trialsPerBlock=%d eegEnabled=%d magnitudesDeg=%s magnitudeCounts=%s questionOrder=%s detectionKeyMapping=%s eegQuestionTriggerScheme=%s S1ms=%.0f ISIms=%.0f S2ms=%.0f gapMs=%.0f', ...
        cfg.participantID, timestamp, cfg.screenNumber, windowRect(3), windowRect(4), 1/ifi, cfg.nTotal, cfg.trialsPerBlock, double(cfg.eeg.enable), mat2str(cfg.design.changeMagnitudesDeg), mat2str(cfg.design.changeCountsPerMagnitude), cfg.questionOrder, cfg.detectionKeyMapping, cfg.eegQuestionTriggerScheme, cfg.S1_frames*ifi*1000, cfg.ISI_frames*ifi*1000, cfg.S2_frames*ifi*1000, cfg.gap_frames*ifi*1000));

    %% ------------------------- INSTRUCTIONS SCREEN -------------------------

    showInstructionScreen(window, windowRect, bg, black, cfg);

    %% ------------------------- TRIAL OVERVIEW SCREEN -----------------------

    exptDir = fileparts(mfilename('fullpath'));
    cfg.trialOverviewPNG = fullfile(exptDir, cfg.trialOverviewFilename);

    showTrialOverviewScreen(window, windowRect, bg, black, cfg);

    %% ------------------------- PRACTICE ENTRY SCREEN -----------------------

    showPractice1Intro(window, windowRect, bg, black, cfg);

    %% ------------------------- PRACTICE FLOW (LINEAR) -----------------------------
    practiceFlow = struct();
    practiceFlow.questionOrder = cfg.questionOrder;
    practiceFlow.detectionKeyMapping = cfg.detectionKeyMapping;
    practiceFlow.eegQuestionTriggerScheme = cfg.eegQuestionTriggerScheme;
    practiceFlow.block1 = struct('summary', struct(), 'result', 'not_run');
    practiceFlow.block2 = struct('summary', struct(), 'result', 'not_run');

    if isfield(cfg,'practice') && cfg.practice.enable
        if isfield(cfg,'practice1') && cfg.practice1.enable
            showPractice1BeginScreen(window, windowRect, bg, black, cfg);
            practice1Summary = runPracticeBlock(window, windowRect, gratingTex, allRects, fixationCoords, ...
                xCentre, yCentre, ifi, cfg, bg, black, cfg.practice1);
            practice1Summary.classification = classifyPractice1(practice1Summary, cfg);
            printPracticeSummary(practice1Summary, 'Practice Block 1');
            practiceFlow.block1.summary = practice1Summary;
            practiceFlow.block1.result  = 'completed';
        end

        if isfield(cfg,'practice2') && cfg.practice2.enable
            showPractice2Intro(window, windowRect, bg, black, cfg);
            showPractice2BeginScreen(window, windowRect, bg, black, cfg);
            practice2Summary = runPracticeBlock(window, windowRect, gratingTex, allRects, fixationCoords, ...
                xCentre, yCentre, ifi, cfg, bg, black, cfg.practice2);
            practice2Summary.classification = 'not_applicable';
            printPracticeSummary(practice2Summary, 'Practice Block 2');
            practiceFlow.block2.summary = practice2Summary;
            practiceFlow.block2.result  = 'completed';
        end
    end

    practiceRow = struct();

    practiceRow.participantID = string(cfg.participantID);
    practiceRow.timestamp     = string(timestamp);
    practiceRow.questionOrder = string(cfg.questionOrder);
    practiceRow.detectionKeyMapping = string(cfg.detectionKeyMapping);
    practiceRow.eegQuestionTriggerScheme = string(cfg.eegQuestionTriggerScheme);
    
    % Block 1 summary
    practiceRow.b1_result            = string(practiceFlow.block1.result);
    practiceRow.b1_classification    = getTextFieldOrDefault(practiceFlow.block1.summary, 'classification', 'not_run');
    practiceRow.b1_nTrials           = getFieldOrNaN(practiceFlow.block1.summary, 'nTrials');
    practiceRow.b1_nSTD              = getFieldOrNaN(practiceFlow.block1.summary, 'nSTD');
    practiceRow.b1_nSTD_detect       = getFieldOrNaN(practiceFlow.block1.summary, 'nSTD_detect');
    practiceRow.b1_nSTD_see          = getFieldOrNaN(practiceFlow.block1.summary, 'nSTD_see');
    practiceRow.b1_stdDetect         = getFieldOrNaN(practiceFlow.block1.summary, 'stdDetectRate');
    practiceRow.b1_stdSee            = getFieldOrNaN(practiceFlow.block1.summary, 'stdSeeRate');
    practiceRow.b1_nNCH              = getFieldOrNaN(practiceFlow.block1.summary, 'nNCH');
    practiceRow.b1_nNCH_FA           = getFieldOrNaN(practiceFlow.block1.summary, 'nNCH_FA');
    practiceRow.b1_nNCH_CR           = getFieldOrNaN(practiceFlow.block1.summary, 'nNCH_CR');
    practiceRow.b1_faRateNCH         = getFieldOrNaN(practiceFlow.block1.summary, 'faRateNCH');
    practiceRow.b1_crRateNCH         = getFieldOrNaN(practiceFlow.block1.summary, 'crRateNCH');
    practiceRow.b1_nEASY             = getFieldOrNaN(practiceFlow.block1.summary, 'nEASY');
    practiceRow.b1_nEASY_detect      = getFieldOrNaN(practiceFlow.block1.summary, 'nEASY_detect');
    practiceRow.b1_nEASY_see         = getFieldOrNaN(practiceFlow.block1.summary, 'nEASY_see');
    practiceRow.b1_easyDetect        = getFieldOrNaN(practiceFlow.block1.summary, 'easyDetectRate');
    practiceRow.b1_easySee           = getFieldOrNaN(practiceFlow.block1.summary, 'easySeeRate');
    practiceRow.b1_nChange           = getFieldOrNaN(practiceFlow.block1.summary, 'nChange');
    practiceRow.b1_nChange_detect    = getFieldOrNaN(practiceFlow.block1.summary, 'nChange_detect');
    practiceRow.b1_nChange_see       = getFieldOrNaN(practiceFlow.block1.summary, 'nChange_see');
    practiceRow.b1_changeDetect      = getFieldOrNaN(practiceFlow.block1.summary, 'changeDetectRate');
    practiceRow.b1_changeSee         = getFieldOrNaN(practiceFlow.block1.summary, 'changeSeeRate');
    
    % Block 2 summary
    practiceRow.b2_result            = string(practiceFlow.block2.result);
    practiceRow.b2_classification    = getTextFieldOrDefault(practiceFlow.block2.summary, 'classification', 'not_run');
    practiceRow.b2_nTrials           = getFieldOrNaN(practiceFlow.block2.summary, 'nTrials');
    practiceRow.b2_nSTD              = getFieldOrNaN(practiceFlow.block2.summary, 'nSTD');
    practiceRow.b2_nSTD_detect       = getFieldOrNaN(practiceFlow.block2.summary, 'nSTD_detect');
    practiceRow.b2_nSTD_see          = getFieldOrNaN(practiceFlow.block2.summary, 'nSTD_see');
    practiceRow.b2_stdDetect         = getFieldOrNaN(practiceFlow.block2.summary, 'stdDetectRate');
    practiceRow.b2_stdSee            = getFieldOrNaN(practiceFlow.block2.summary, 'stdSeeRate');
    practiceRow.b2_nNCH              = getFieldOrNaN(practiceFlow.block2.summary, 'nNCH');
    practiceRow.b2_nNCH_FA           = getFieldOrNaN(practiceFlow.block2.summary, 'nNCH_FA');
    practiceRow.b2_nNCH_CR           = getFieldOrNaN(practiceFlow.block2.summary, 'nNCH_CR');
    practiceRow.b2_faRateNCH         = getFieldOrNaN(practiceFlow.block2.summary, 'faRateNCH');
    practiceRow.b2_crRateNCH         = getFieldOrNaN(practiceFlow.block2.summary, 'crRateNCH');
    practiceRow.b2_nEASY             = getFieldOrNaN(practiceFlow.block2.summary, 'nEASY');
    practiceRow.b2_nEASY_detect      = getFieldOrNaN(practiceFlow.block2.summary, 'nEASY_detect');
    practiceRow.b2_nEASY_see         = getFieldOrNaN(practiceFlow.block2.summary, 'nEASY_see');
    practiceRow.b2_easyDetect        = getFieldOrNaN(practiceFlow.block2.summary, 'easyDetectRate');
    practiceRow.b2_easySee           = getFieldOrNaN(practiceFlow.block2.summary, 'easySeeRate');
    practiceRow.b2_nChange           = getFieldOrNaN(practiceFlow.block2.summary, 'nChange');
    practiceRow.b2_nChange_detect    = getFieldOrNaN(practiceFlow.block2.summary, 'nChange_detect');
    practiceRow.b2_nChange_see       = getFieldOrNaN(practiceFlow.block2.summary, 'nChange_see');
    practiceRow.b2_changeDetect      = getFieldOrNaN(practiceFlow.block2.summary, 'changeDetectRate');
    practiceRow.b2_changeSee         = getFieldOrNaN(practiceFlow.block2.summary, 'changeSeeRate');
    
    practiceTable = struct2table(practiceRow);
    
    practiceFileCSV = fullfile(outDir, sprintf('%s_%s_PracticeFlow_%s.csv', cfg.outputPrefix, cfg.participantID, timestamp));
    writetable(practiceTable, practiceFileCSV);
    fprintf('Saved practice flow CSV: %s\n', practiceFileCSV);
    practiceFileMAT = fullfile(outDir, sprintf('%s_%s_PracticeFlow_%s.mat', cfg.outputPrefix, cfg.participantID, timestamp));
    save(practiceFileMAT, 'practiceFlow', 'practiceRow');
    fprintf('Saved practice flow MAT: %s\n', practiceFileMAT);

    %% ------------------------- MAIN EXPERIMENT ENTRY SCREEN ----------------

    showMainExperimentIntroScreen(window, windowRect, bg, black, cfg);
    showMainTrialBeginScreen(window, windowRect, bg, black, cfg);

    %% ------------------------- RUN MAIN EXPERIMENT -------------------------
    results = repmat(emptyResultRow(), cfg.nTotal, 1);

    for t = 1:cfg.nTotal
        checkAbort(cfg);

        trial = trials(t);

        % Fixed timing. durFrames is retained as a legacy logging alias for S1 duration.
        durFrames = cfg.S1_frames;
        s1Frames = cfg.S1_frames;
        s2Frames = cfg.S2_frames;
        selectedPBlind = NaN;
        selectedPSensing = NaN;
        selectedPSeeing = NaN;
        selectedPAware = NaN;
        selectedPDetect = NaN;
        selectedPLocGivenAware = NaN;
        posteriorEntropyBits = NaN;
        trackName = char(string(trial.staircase));
        trackTargetOutcome = 'fixedMagnitude';
        trackTargetProb = NaN;

        % Build S1/S2 orientations.
        allowedOri = cfg.stim.allowedOri;
        if trial.isChange
            changeMagnitudeDeg = trial.changeMagnitudeDeg;
            oriS1 = makeOriS1_noPostChangeDup(trial.changeQuad, trial.changeStartOri, allowedOri, changeMagnitudeDeg);
        else
            changeMagnitudeDeg = cfg.design.noChangeMagnitudeDeg;
            oriS1 = allowedOri(randperm(numel(allowedOri), 4))';
        end
        
        oriS2 = oriS1;
        if trial.isChange
            oriS2(trial.changeQuad) = mod(oriS1(trial.changeQuad) + changeMagnitudeDeg, 180);
        end

        blockNum = ceil(t / cfg.trialsPerBlock);

        % ---------------- TIMELINE (scheduled VBL; ESC in ITI/questions/instructions) ----------------
        % Fixation jitter
        jitterFrames = randi([cfg.fixJitterFrames(1), cfg.fixJitterFrames(2)], 1, 1);
        drawFixationOnly(window, bg, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
        Screen('DrawingFinished', window);
        vblTargetFixOn = GetSecs + 0.5 * ifi;
        [tFixOn, ~, ~, missedFixOn] = cfg.loggedFlip('FixOn', 'main_trial', t, blockNum, vblTargetFixOn);
        if cfg.eeg.markerPolicy.markMainTrials
            emitTrigger('trialStart', 'main_trial', t, blockNum, cfg.eeg.codes.trialStart, 'FixOn', tFixOn);
        end
        tTrialStart = tFixOn;
        emitTobiiMessage('TRIAL_META', 'trialMeta', 'main_trial', t, blockNum, tTrialStart, ...
            sprintf('isChange=%d magnitudeDeg=%.1f label=%s changeQuad=%d S1Frames=%d ISIFrames=%d S2Frames=%d gapFrames=%d', ...
            trial.isChange, changeMagnitudeDeg, char(string(trial.staircase)), trial.changeQuad, cfg.S1_frames, cfg.ISI_frames, cfg.S2_frames, cfg.gap_frames));

        drawGratings(window, gratingTex, allRects, oriS1, bg);
        drawFixation(window, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
        vblTargetS1 = tFixOn + (jitterFrames - 0.5) * ifi;
        [tS1,  ~, ~, missedS1]  = cfg.loggedFlip('S1', 'main_trial', t, blockNum, vblTargetS1);
        if cfg.eeg.markerPolicy.markMainTrials
            emitTrigger('s1On', 'main_trial', t, blockNum, cfg.eeg.codes.s1On, 'S1', tS1);
        end

        drawFixationOnly(window, bg, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
       %drawMaskFixationOnly(window, bg, maskRect, cfg.stim.maskGrey, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
        vblTargetISI = tS1 + (cfg.S1_frames - 0.5) * ifi;
        [tISI, ~, ~, missedISI] = cfg.loggedFlip('ISI', 'main_trial', t, blockNum, vblTargetISI);
        if cfg.eeg.markerPolicy.markMainTrials
            emitTrigger('isiOn', 'main_trial', t, blockNum, cfg.eeg.codes.isiOn, 'ISI', tISI);
        end

        drawGratings(window, gratingTex, allRects, oriS2, bg);
        drawFixation(window, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
        vblTargetS2 = tISI + (cfg.ISI_frames - 0.5) * ifi;
        [tS2,  ~, ~, missedS2]  = cfg.loggedFlip('S2', 'main_trial', t, blockNum, vblTargetS2);
        if cfg.eeg.markerPolicy.markMainTrials
            emitTrigger('s2On', 'main_trial', t, blockNum, cfg.eeg.codes.s2On, 'S2', tS2);
        end

        drawFixationOnly(window, bg, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
        vblTargetGap = tS2 + (cfg.S2_frames - 0.5) * ifi;
        [tGap, ~, ~, missedGap] = cfg.loggedFlip('Gap', 'main_trial', t, blockNum, vblTargetGap);
        if cfg.eeg.markerPolicy.markMainTrials
            emitTrigger('gapOn', 'main_trial', t, blockNum, cfg.eeg.codes.gapOn, 'Gap', tGap);
        end

        % ---------------- QUESTIONS ----------------
        % Q1 (PAS clarity)
        Screen('DrawTexture', window, cfg.qTex.PAS);
        Screen('DrawingFinished', window);
        vblTargetQ1 = tGap + (cfg.gap_frames - 0.5) * ifi;
        [tQ1, ~, ~, missedQ1] = cfg.loggedFlip('Q1_PAS', 'main_trial', t, blockNum, vblTargetQ1);
        if cfg.eeg.markerPolicy.markMainTrials
            emitTrigger('q1On', 'main_trial', t, blockNum, cfg.eeg.codes.q1On, 'Q1_PAS', tQ1);
        end
        [pasKey, pasTime] = waitForKeyQueue(cfg.keys.pas, cfg.keys.escape, cfg.maxRespSec, cfg);
        pasRT = pasTime - tQ1;
        pas = keyToMappedValue(pasKey, cfg.keys.pas, cfg.keys.pasValues);
        emitTobiiMessage('PAS_RESP', 'Q1_PAS', 'main_trial', t, blockNum, pasTime, ...
            sprintf('pas=%s keyCode=%s rtMs=%.3f', numToStrOrNA(pas), numToStrOrNA(pasKey), pasRT * 1000));
        if cfg.eeg.markerPolicy.markMainTrials && cfg.eeg.markerPolicy.markResponses
            if ~isnan(pas) && pas >= 1 && pas <= 4
                emitTrigger('pasResponse', 'main_trial', t, blockNum, cfg.eeg.codes.pasBase + pas, 'Q1_PAS', tQ1);
            end
        end

        % Q2 (Detection Yes/No)
        drawDetection(window, windowRect, black, bg, cfg);
        Screen('DrawingFinished', window);
        vblTargetQ2 = GetSecs + 0.5 * ifi;
        [tQ2, ~, ~, missedQ2] = cfg.loggedFlip('Q2_Detect', 'main_trial', t, blockNum, vblTargetQ2);
        if cfg.eeg.markerPolicy.markMainTrials
            emitTrigger('q2On', 'main_trial', t, blockNum, cfg.eeg.codes.q2On, 'Q2_Detect', tQ2);
        end

        [detectKey, detectTime] = waitForKeyQueue(cfg.keys.detect, cfg.keys.escape, cfg.maxRespSec, cfg);
        detectRT = detectTime - tQ2;
        detectResp = keyToMappedValue(detectKey, cfg.keys.detect, cfg.keys.detectValues);
        emitTobiiMessage('DETECT_RESP', 'Q2_Detect', 'main_trial', t, blockNum, detectTime, ...
            sprintf('detect=%s keyCode=%s rtMs=%.3f', numToStrOrNA(detectResp), numToStrOrNA(detectKey), detectRT * 1000));
        if cfg.eeg.markerPolicy.markMainTrials && cfg.eeg.markerPolicy.markResponses
            if ~isnan(detectResp)
                if detectResp == 1
                    emitTrigger('detectYes', 'main_trial', t, blockNum, cfg.eeg.codes.detectYes, 'Q2_Detect', tQ2);
                elseif detectResp == 0
                    emitTrigger('detectNo', 'main_trial', t, blockNum, cfg.eeg.codes.detectNo, 'Q2_Detect', tQ2);
                end
            end
        end
        hit = double(~isnan(detectResp) && detectResp == 1);

        % Q3 (Localise) - ALWAYS ask, even after a no response.
        if hit == 0
            Screen('DrawTexture', window, cfg.qTex.Loc_detectNo);
        else
            Screen('DrawTexture', window, cfg.qTex.Loc_default);
        end
        Screen('DrawingFinished', window);
        vblTargetQ3 = GetSecs + 0.5 * ifi;
        [tQ3, ~, ~, missedQ3] = cfg.loggedFlip('Q3_Loc', 'main_trial', t, blockNum, vblTargetQ3);
        if cfg.eeg.markerPolicy.markMainTrials
            emitTrigger('q3On', 'main_trial', t, blockNum, cfg.eeg.codes.q3On, 'Q3_Loc', tQ3);
        end

        [resp2Key, resp2Time] = waitForKeyQueue(cfg.keys.quad, cfg.keys.escape, cfg.maxRespSec, cfg);
        locRT = resp2Time - tQ3;
        resp2 = keyToMappedValue(resp2Key, cfg.keys.quad, cfg.keys.quadValues);
        emitTobiiMessage('LOC_RESP', 'Q3_Loc', 'main_trial', t, blockNum, resp2Time, ...
            sprintf('loc=%s keyCode=%s rtMs=%.3f', numToStrOrNA(resp2), numToStrOrNA(resp2Key), locRT * 1000));
        if cfg.eeg.markerPolicy.markMainTrials && cfg.eeg.markerPolicy.markResponses
            if ~isnan(resp2) && resp2 >= 1 && resp2 <= 4
                emitTrigger('locResponse', 'main_trial', t, blockNum, cfg.eeg.codes.locBase + resp2, 'Q3_Loc', tQ3);
            end
        end

        % Localisation correctness (only meaningful on change trials)
        if trial.isChange
            if isnan(resp2)
                locCorrect = 0;
            else
                locCorrect = double(resp2 == trial.changeQuad);
            end
        else
            locCorrect = NaN;
        end

        tTrialEnd = resp2Time;
        trialTotalSec = tTrialEnd - tTrialStart;

        % ITI
        % drawFixationOnly(window, bg, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
        Screen('FillRect', window, bg);
        Screen('DrawingFinished', window);
        vblTargetITI = GetSecs + 0.5 * ifi;
        [tITI, ~, ~, missedITI] = cfg.loggedFlip('ITI', 'main_trial', t, blockNum, vblTargetITI);
        if cfg.eeg.markerPolicy.markMainTrials
            emitTrigger('trialEnd', 'main_trial', t, blockNum, cfg.eeg.codes.trialEnd, 'ITI', tITI);
        end
        holdForSecondsWithAbort(tITI + cfg.ITI_frames*ifi, cfg);

        % ---------------- OUTCOME CLASSIFICATION ----------------
        if trial.isChange
            if hit == 0
                outcomeBin = 1;   % Blind/objective miss
            elseif locCorrect == 1
                outcomeBin = 3;   % Seeing/detected and localised
            else
                outcomeBin = 2;   % Sensing/detected but not localised
            end
        else
            outcomeBin = NaN;   % no-change catch trial
        end

        % ---------------- LOG DATA ----------------
        results(t).participantID = cfg.participantID;
        results(t).trialNum = t;
        results(t).blockNum = ceil(t / cfg.trialsPerBlock);

        results(t).isChange = trial.isChange;
        results(t).staircase = trial.staircase;
        results(t).changeQuad = trial.changeQuad;

        results(t).durFrames = durFrames;
        results(t).durSec = durFrames * ifi;
        results(t).s1Frames = s1Frames;
        results(t).s1Sec = s1Frames * ifi;
        results(t).isiFrames = cfg.ISI_frames;
        results(t).isiSec = cfg.ISI_frames * ifi;
        results(t).s2Frames = s2Frames;
        results(t).s2Sec = s2Frames * ifi;
        results(t).gapFrames = cfg.gap_frames;
        results(t).gapSec = cfg.gap_frames * ifi;
        results(t).changeAngleDeg = changeMagnitudeDeg;
        results(t).changeMagnitudeDeg = changeMagnitudeDeg;

        results(t).trackName = trackName;
        results(t).trackTargetOutcome = trackTargetOutcome;
        results(t).trackTargetProb = trackTargetProb;
        results(t).selectedPBlind = selectedPBlind;
        results(t).selectedPSensing = selectedPSensing;
        results(t).selectedPSeeing = selectedPSeeing;
        results(t).selectedPAware = selectedPAware;
        results(t).selectedPDetect = selectedPDetect;
        results(t).selectedPLocGivenAware = selectedPLocGivenAware;
        results(t).posteriorEntropyBits = posteriorEntropyBits;

        results(t).oriS1 = sprintf('%.1f,%.1f,%.1f,%.1f', oriS1(1),oriS1(2),oriS1(3),oriS1(4));
        results(t).oriS2 = sprintf('%.1f,%.1f,%.1f,%.1f', oriS2(1),oriS2(2),oriS2(3),oriS2(4));

        results(t).tS1 = tS1;
        results(t).tISI = tISI;
        results(t).tS2 = tS2;
        results(t).tGap = tGap;
        results(t).actualS1Frames = (tISI - tS1) / ifi;
        results(t).actualISIFrames = (tS2 - tISI) / ifi;
        results(t).actualS2Frames = (tGap - tS2) / ifi;
        results(t).actualGapFrames = (tQ1 - tGap) / ifi;
        results(t).missedFixOn = missedFixOn;
        results(t).missedS1  = missedS1;
        results(t).missedISI = missedISI;
        results(t).missedS2  = missedS2;
        results(t).missedGap = missedGap;
        % Positional fields follow Q1 PAS, Q2 detection, Q3 localisation.
        results(t).missedQ1  = missedQ1;
        results(t).missedQ2  = missedQ2;
        results(t).missedQ3  = missedQ3;
        results(t).missedPAS = missedQ1;
        results(t).missedDetect = missedQ2;
        results(t).missedLoc = missedQ3;
        results(t).missedITI = missedITI;
        results(t).tQ1 = tQ1;
        results(t).tQ2 = tQ2;
        results(t).tQ3 = tQ3;
        results(t).tPAS = tQ1;
        results(t).tDetect = tQ2;
        results(t).tLoc = tQ3;

        results(t).detectResp = detectResp;
        results(t).detectRT = detectRT;
        % Legacy resp2 remains a localisation-response alias for compatibility.
        results(t).resp2 = resp2;
        results(t).locResp = resp2;
        results(t).locRT = locRT;

        results(t).pas = pas;
        results(t).pasRT = pasRT;
        results(t).tTrialStart   = tTrialStart;
        results(t).tTrialEnd     = tTrialEnd;
        results(t).trialTotalSec = trialTotalSec;


        results(t).hit = double(hit);
        results(t).locCorrect = locCorrect;

        if ~trial.isChange
            results(t).outcomeBin = 'NoChange';
        else
            switch outcomeBin
                case 1, results(t).outcomeBin = 'Blind';
                case 2, results(t).outcomeBin = 'Sensing';
                case 3, results(t).outcomeBin = 'Seeing';
                otherwise, results(t).outcomeBin = '';
            end
        end

        results(t).track1_xCurrent = NaN;
        results(t).track2_xCurrent = NaN;
        results(t).track3_xCurrent = NaN;
        results(t).track1_frozen   = NaN;
        results(t).track2_frozen   = NaN;
        results(t).track3_frozen   = NaN;
        results(t).track1_frozenFrames = NaN;
        results(t).track2_frozenFrames = NaN;
        results(t).track3_frozenFrames = NaN;

        trialLogLine(t, cfg, trial, durFrames, resp2, hit, locCorrect, pas, []);

        % End-of-block
        if mod(t, cfg.trialsPerBlock) == 0

            checkpointSave(results, t, outFile, cfg);

            if t < cfg.nTotal
                blockJustFinished = t / cfg.trialsPerBlock;
                showBlockBreakScreen(window, windowRect, bg, black, cfg, blockJustFinished, cfg.nBlocks);
                showBlockResumeScreen(window, windowRect, bg, black, cfg);
            end
        end
    end

    %% ------------ FINAL FIXED-DESIGN SUMMARY -----------------
    fprintf('Run complete: fixed S1=%d frames, ISI=%d frames, S2=%d frames, gap=%d frames.\n', ...
        cfg.S1_frames, cfg.ISI_frames, cfg.S2_frames, cfg.gap_frames);
    fprintf('Orientation magnitudes used: %s deg.\n', mat2str(cfg.design.changeMagnitudesDeg));
    fprintf('Change counts by magnitude: %s.\n', mat2str(cfg.design.changeCountsPerMagnitude));
    fprintf('Question order: %s.\n', cfg.questionOrder);


    %% ------------------------- SAVE -------------------------
    results = results(~cellfun(@isempty,{results.participantID}));

    T = struct2table(results);

    fprintf('\nMissed flip summary:\n');
    fprintf('S1:  %d\n', sum(T.missedS1 > 0));
    fprintf('ISI: %d\n', sum(T.missedISI > 0));
    fprintf('S2:  %d\n', sum(T.missedS2 > 0));
    fprintf('Gap: %d\n', sum(T.missedGap > 0));

    fprintf('\nActual main trial frame duration summary:\n');
    durFields = {'actualS1Frames', 'actualISIFrames', 'actualS2Frames', 'actualGapFrames'};
    expLabels = {sprintf('%d (S1)', cfg.S1_frames), ...
        sprintf('%d (ISI)', cfg.ISI_frames), ...
        sprintf('%d (S2)', cfg.S2_frames), ...
        sprintf('%d (gap)', cfg.gap_frames)};
    for ff = 1:numel(durFields)
        v = T.(durFields{ff});
        fprintf('  %s: mean=%.3f min=%.3f max=%.3f | expected ~ %s\n', ...
            durFields{ff}, mean(v), min(v), max(v), expLabels{ff});
    end

    % --- Add fixed-design summary values as columns (same value every row) ---
    T.calibTimestamp = repmat(string(timestamp), height(T), 1);
    T.fixedS1Frames  = repmat(cfg.S1_frames, height(T), 1);
    T.fixedISIFrames = repmat(cfg.ISI_frames, height(T), 1);
    T.fixedS2Frames  = repmat(cfg.S2_frames, height(T), 1);
    T.fixedGapFrames = repmat(cfg.gap_frames, height(T), 1);
    T.fixedS1Sec     = repmat(cfg.S1_frames * ifi, height(T), 1);
    T.fixedISISec    = repmat(cfg.ISI_frames * ifi, height(T), 1);
    T.fixedS2Sec     = repmat(cfg.S2_frames * ifi, height(T), 1);
    T.fixedGapSec    = repmat(cfg.gap_frames * ifi, height(T), 1);
    T.designMagnitudesDeg = repmat(string(mat2str(cfg.design.changeMagnitudesDeg)), height(T), 1);
    T.changeTrialsPerMagnitude = repmat(cfg.nChangePerMagnitude, height(T), 1);
    T.changeCountsPerMagnitude = repmat(string(mat2str(cfg.design.changeCountsPerMagnitude)), height(T), 1);
    T.noChangeTrials = repmat(cfg.nCatch, height(T), 1);
    T.debugQuickRun = repmat(double(cfg.debug.quickRun), height(T), 1);
    T.questTest100 = repmat(0, height(T), 1);
    T.questionOrder = repmat(string(cfg.questionOrder), height(T), 1);
    T.detectionKeyMapping = repmat(string(cfg.detectionKeyMapping), height(T), 1);
    T.eegQuestionTriggerScheme = repmat(string(cfg.eegQuestionTriggerScheme), height(T), 1);

    writetable(T, outFile);

    T2 = readtable(outFile);   % uses the file you just saved

    % --- PAS distribution across all trials (guarded) ---
    validPas = T2.pas;
    validPas = validPas(~isnan(validPas) & validPas >= 1 & validPas <= 4);
    
    pasCounts = accumarray(validPas, 1, [4 1])';
    if sum(pasCounts) > 0
        pasPct = 100 * pasCounts / sum(pasCounts);
    else
        pasPct = [0 0 0 0];
    end
    
    % --- Change-trial outcome distribution (blind/sensing/seeing) ---
    isChg   = (T2.isChange == 1);
    blind   = isChg & (T2.hit == 0);
    seeing  = isChg & (T2.hit == 1) & (T2.locCorrect == 1);
    sensing = isChg & (T2.hit == 1) & (T2.locCorrect == 0);

    outCounts = [sum(blind) sum(sensing) sum(seeing)];
    if sum(isChg) > 0
        outPct = 100 * outCounts / sum(isChg);
    else
        outPct = [0 0 0];
    end
    
    disp(table((1:4)', pasCounts', pasPct', 'VariableNames', {'PAS','Count','Percent'}));
    disp(table(["blind";"sensing";"seeing"], outCounts', outPct', 'VariableNames', {'Outcome','Count','Percent'}));

        
    cal = struct();
    cal.participantID  = cfg.participantID;
    cal.timestamp      = timestamp;
    cal.design         = cfg.design;
    cal.changeMagnitudesDeg = cfg.design.changeMagnitudesDeg;
    cal.nChangePerMagnitude = cfg.nChangePerMagnitude;
    cal.changeCountsPerMagnitude = cfg.design.changeCountsPerMagnitude;
    cal.nChange        = cfg.nChange;
    cal.nCatch         = cfg.nCatch;
    cal.trialDial      = cfg.trialDial;
    cal.S1_frames      = cfg.S1_frames;
    cal.ISI_frames     = cfg.ISI_frames;
    cal.S2_frames      = cfg.S2_frames;
    cal.gap_frames     = cfg.gap_frames;
    cal.S1_sec         = cfg.S1_frames * ifi;
    cal.ISI_sec        = cfg.ISI_frames * ifi;
    cal.S2_sec         = cfg.S2_frames * ifi;
    cal.gap_sec        = cfg.gap_frames * ifi;
    cal.debugQuickRun  = cfg.debug.quickRun;
    cal.questionOrder = cfg.questionOrder;
    cal.detectionKeyMapping = cfg.detectionKeyMapping;
    cal.eegQuestionTriggerScheme = cfg.eegQuestionTriggerScheme;

    calFile = fullfile(outDir, sprintf('%s_%s_FullRun_%s.mat', cfg.outputPrefix, cfg.participantID, timestamp));
    save(calFile, 'cal');
    fprintf('Saved full-run MAT: %s\n', calFile);

    endText = 'You have finished the experiment, well done!\n\nPress any key to exit.';
    DrawFormattedText(window, endText, 'center', 'center', black, 90);
    cfg.loggedFlip('experiment_end', 'experiment_end', NaN, NaN, NaN);

    if ~isempty(flipLog)
        flipLogT = struct2table(flipLog);

        flipLogT.missedMs = 1000 * flipLogT.missed;
        flipLogT.over1ms = flipLogT.missed > 0.001;
        flipLogT.overHalfFrame = flipLogT.missed > 0.5 * ifi;
        flipLogT.overOneFrame = flipLogT.missed > ifi;

        flipLogFile = fullfile(outDir, sprintf('%s_%s_FlipLog_%s.csv', cfg.outputPrefix, cfg.participantID, timestamp));
        writetable(flipLogT, flipLogFile);
        fprintf('Saved flip log CSV: %s\n', flipLogFile);

        fprintf('\nFull missed flip summary by context + label:\n');

        [G, ctxGroup, labelGroup] = findgroups(flipLogT.context, flipLogT.label);

        totalFlips = splitapply(@numel, flipLogT.missed, G);
        nPositive = splitapply(@(x) sum(x > 0), flipLogT.missed, G);
        maxMissedMs = splitapply(@(x) max(1000*x), flipLogT.missed, G);
        nOver1ms = splitapply(@(x) sum(x > 0.001), flipLogT.missed, G);
        nOverHalfFrame = splitapply(@(x) sum(x > 0.5 * ifi), flipLogT.missed, G);
        nOverOneFrame = splitapply(@(x) sum(x > ifi), flipLogT.missed, G);

        for ii = 1:numel(totalFlips)
            fprintf('  %-20s %-24s total=%4d missed=%3d maxMs=%8.3f >1ms=%3d >halfF=%3d >1F=%3d\n', ...
                char(ctxGroup(ii)), char(labelGroup(ii)), ...
                totalFlips(ii), nPositive(ii), maxMissedMs(ii), ...
                nOver1ms(ii), nOverHalfFrame(ii), nOverOneFrame(ii));
        end

        fprintf('\nMissed flips only:\n');
        missedOnly = flipLogT(flipLogT.missedFlag, ...
            {'idx','context','label','trialNum','blockNum','scheduled','when','vbl','missed','missedMs','over1ms','overHalfFrame','overOneFrame'});
        disp(missedOnly);
    end

    if exist('triggerLog', 'var') && ~isempty(triggerLog)
        triggerLogT = struct2table(triggerLog);

        fprintf('\nTrigger timing summary:\n');
        fprintf('Total trigger attempts: %d\n', height(triggerLogT));
        fprintf('Enabled sends: %d\n', sum(triggerLogT.enabled));
        fprintf('Mean send duration: %.3f ms\n', mean(triggerLogT.sendDurationMs));
        fprintf('Max send duration: %.3f ms\n', max(triggerLogT.sendDurationMs));
        fprintf('>1 ms: %d\n', sum(triggerLogT.sendDurationMs > 1));
        fprintf('>half frame: %d\n', sum(triggerLogT.sendDurationMs > 1000 * 0.5 * ifi));
        fprintf('>one frame: %d\n', sum(triggerLogT.sendDurationMs > 1000 * ifi));

        fprintf('\nTrigger count summary by context + label:\n');
        [G, ctxGroup, labelGroup] = findgroups(triggerLogT.context, triggerLogT.label);
        triggerCounts = splitapply(@numel, triggerLogT.code, G);
        for ii = 1:numel(triggerCounts)
            fprintf('  %-20s %-16s count=%4d\n', char(ctxGroup(ii)), char(labelGroup(ii)), triggerCounts(ii));
        end

        fprintf('\nTrigger count by code:\n');
        [Gc, codeGroup, labelGroupC] = findgroups(triggerLogT.code, triggerLogT.label);
        codeCounts = splitapply(@numel, triggerLogT.code, Gc);
        for ii = 1:numel(codeCounts)
            fprintf('  code=%3d  %-16s  count=%4d\n', codeGroup(ii), char(labelGroupC(ii)), codeCounts(ii));
        end

        triggerLogFile = fullfile(outDir, sprintf('%s_%s_TriggerLog_%s.csv', cfg.outputPrefix, cfg.participantID, timestamp));
        writetable(triggerLogT, triggerLogFile);
        fprintf('Saved trigger log CSV: %s\n', triggerLogFile);
    end

    emitTobiiMessage('RUN_END', 'runEnd', 'experiment_end', NaN, NaN, GetSecs, 'status=complete');
    KbStrokeWait;
    tobii = stopAndSaveTobii(tobii, cfg, outDir, cfg.participantID, timestamp, 'complete');

catch ME
    isUserAbort = strcmp(ME.identifier, 'CB_4xGratings_v3_Orientation:UserAbort');

    try
        if isUserAbort
            emitTobiiMessage('RUN_ABORT', 'runAbort', 'experiment_abort', NaN, NaN, GetSecs, 'status=user_abort');
            tobii = stopAndSaveTobii(tobii, cfg, outDir, cfg.participantID, timestamp, 'user_abort');
        else
            emitTobiiMessage('RUN_ERROR', 'runError', 'experiment_error', NaN, NaN, GetSecs, 'status=error');
            tobii = stopAndSaveTobii(tobii, cfg, outDir, cfg.participantID, timestamp, 'error');
        end
    catch
    end

    if ~isempty(cleanupObj)
        clear cleanupObj
    else
        try cleanup(window, cfg); catch, end
    end

    lastCompleted = 0;
    if exist('results','var')
        last = find(~cellfun(@isempty,{results.participantID}), 1, 'last');
        if ~isempty(last)
            checkpointSave(results, last, outFile, cfg);
            lastCompleted = last;
        end
    end

    if isUserAbort
        fprintf('\nExperiment stopped by user. Completed main trials checkpointed: %d.\n', lastCompleted);
        return;
    end

    rep = getReport(ME,'extended','hyperlinks','off');
    fprintf(2, '\n\n===== %s ERROR =====\n%s\n', cfg.outputPrefix, rep);

    fid = fopen(fullfile(pwd, sprintf('%s_last_error.txt', cfg.outputPrefix)), 'w');
    if fid > 0
        fprintf(fid, '%s\n', rep);
        fclose(fid);
    end

    rethrow(ME);
end

    function emitTrigger(label, context, trialNum, blockNum, code, linkedFlipLabel, linkedFlipTime)

        if nargin < 7
            linkedFlipTime = NaN;
        end
        if nargin < 6
            linkedFlipLabel = '';
        end

        if isnan(code) || code < 0 || code > 255
            return;
        end

        sendStart = GetSecs;
        errMsg = '';
        didEnable = false;

        try
            if isfield(cfg, 'trigger') && cfg.trigger.enabled && ~isempty(cfg.trigger.handle)
                IOPort('Write', cfg.trigger.handle, uint8(code), 0);
                didEnable = true;

                if code ~= 0 && isfield(cfg, 'eeg') && isfield(cfg.eeg, 'resetMode')
                    pulseWidth = 0.002;
                    if isfield(cfg.eeg, 'pulseWidthSec') && isnumeric(cfg.eeg.pulseWidthSec) && ...
                            isfinite(cfg.eeg.pulseWidthSec) && cfg.eeg.pulseWidthSec > 0
                        pulseWidth = cfg.eeg.pulseWidthSec;
                    end

                    doReset = strcmpi(cfg.eeg.resetMode, 'blocking') || ...
                        (strcmpi(cfg.eeg.resetMode, 'trialEndOnly') && strcmpi(label, 'trialEnd'));

                    if doReset
                        WaitSecs(pulseWidth);
                        IOPort('Write', cfg.trigger.handle, uint8(0), 0);
                    end
                end
            end
        catch ME
            errMsg = mExceptionText(ME);
            if isfield(cfg, 'eeg') && isfield(cfg.eeg, 'warnOnSendError') && cfg.eeg.warnOnSendError
                warning('EEG trigger send failed (%d): %s', code, errMsg);
            end
        end

        sendEnd = GetSecs;

        triggerN = triggerN + 1;
        triggerLog(triggerN).idx = triggerN;
        triggerLog(triggerN).label = string(label);
        triggerLog(triggerN).context = string(context);
        triggerLog(triggerN).trialNum = trialNum;
        triggerLog(triggerN).blockNum = blockNum;
        triggerLog(triggerN).code = code;
        triggerLog(triggerN).linkedFlipLabel = string(linkedFlipLabel);
        triggerLog(triggerN).linkedFlipTime = linkedFlipTime;
        if ~isnan(linkedFlipTime)
            triggerLog(triggerN).rtFromLinkedFlipMs = 1000 * (sendStart - linkedFlipTime);
        else
            triggerLog(triggerN).rtFromLinkedFlipMs = NaN;
        end
        triggerLog(triggerN).sendStart = sendStart;
        triggerLog(triggerN).sendEnd = sendEnd;
        triggerLog(triggerN).sendDurationMs = 1000 * (sendEnd - sendStart);
        triggerLog(triggerN).enabled = didEnable;
        triggerLog(triggerN).error = string(errMsg);
    end


    function emitTobiiMessage(eventName, label, context, trialNum, blockNum, eventTime, extraText)

        if nargin < 7 || isempty(extraText)
            extraText = '';
        end
        if nargin < 6 || isempty(eventTime)
            eventTime = GetSecs;
        end
        if nargin < 5 || isempty(blockNum)
            blockNum = NaN;
        end
        if nargin < 4 || isempty(trialNum)
            trialNum = NaN;
        end

        try
            if ~exist('tobii', 'var') || ~isstruct(tobii) || ~isfield(tobii, 'recording') || ~tobii.recording
                return;
            end
            if ~isfield(tobii, 'EThndl') || isempty(tobii.EThndl)
                return;
            end

            msg = sprintf('CBV3_%s label=%s context=%s trial=%s block=%s eventTime=%.6f %s', ...
                char(eventName), char(string(label)), char(string(context)), ...
                numToStrOrNA(trialNum), numToStrOrNA(blockNum), eventTime, char(string(extraText)));

            tobii.EThndl.sendMessage(msg, eventTime);
        catch ME_tobii
            if isfield(cfg, 'tobii') && isfield(cfg.tobii, 'warnOnMessageError') && cfg.tobii.warnOnMessageError
                warning('Tobii message failed: %s', mExceptionText(ME_tobii));
            end
        end
    end

    function [vbl, stimOnsetTime, flipTimestamp, missed] = loggedFlip(label, context, trialNum, blockNum, when)

        if nargin < 5 || isempty(when) || isnan(when)
            [vbl, stimOnsetTime, flipTimestamp, missed] = Screen('Flip', window);
            scheduled = false;
            whenVal = NaN;
        else
            [vbl, stimOnsetTime, flipTimestamp, missed] = Screen('Flip', window, when);
            scheduled = true;
            whenVal = when;
        end

        flipN = flipN + 1;
        flipLog(flipN).idx = flipN;
        flipLog(flipN).label = string(label);
        flipLog(flipN).context = string(context);
        flipLog(flipN).trialNum = trialNum;
        flipLog(flipN).blockNum = blockNum;
        flipLog(flipN).scheduled = scheduled;
        flipLog(flipN).when = whenVal;
        flipLog(flipN).vbl = vbl;
        flipLog(flipN).stimOnsetTime = stimOnsetTime;
        flipLog(flipN).flipTimestamp = flipTimestamp;
        flipLog(flipN).missed = missed;
        flipLog(flipN).missedFlag = missed > 0;

        emitTobiiMessage('FLIP', label, context, trialNum, blockNum, vbl, ...
            sprintf('scheduled=%d when=%s stimOnset=%.6f flipTimestamp=%.6f missed=%.6f', ...
            double(scheduled), numToStrOrNA(whenVal), stimOnsetTime, flipTimestamp, missed));
    end

end

%% ========================= LOCAL FUNCTIONS =========================

function showInstructionScreen(window, windowRect, bg, black, cfg)

    % ---- Instruction text (aligned with web task copy) ----
    titleFirstInstructions = 'Change Blindness Task Instruction';
    % Split body so each question heading can be drawn bold (TextStyle 1).
    instrBodyA = [ ...
        'In this task you will see four striped circles arranged in a 2 x 2 grid.\n' ...
        'Sometimes ONE of the circles will rotate and change orientation.\n' ...
        'Sometimes NO circles will rotate and change orientation.\n\n' ...
        'After each trial you will answer three questions:\n\n' ...
    ];
    instrQ1Bold = 'Question 1: How clearly did you experience the change?\n';
    instrBodyB = 'Use q/w/e/r for PAS ratings 1-4.\n\n';
    instrQ2Bold = 'Question 2: Did you detect a change?\n';
    instrBodyC = 'Press the GREEN button for Yes, or the RED button for No.\n\n';
    instrQ3Bold = 'Question 3: Where was the change?\n';
    instrBodyD = [ ...
        'Press the labelled quadrant button:\n\n' ...
        '[1] Top Left    [2] Top Right    [3] Bottom Left    [4] Bottom Right\n\n' ...
        'You will always be asked all three questions, even if you press the RED button for No in Question 2.\n\n' ...
    ];
    instrSegs = { instrBodyA, instrQ1Bold, instrBodyB, instrQ2Bold, instrBodyC, instrQ3Bold, instrBodyD };
    instrSegBold = [ false, true, false, true, false, true, false ];

    % ---- Lockout settings ----
    tcfg = cfg.display.text;
    lockSec  = tcfg.lockSec;
    greyText = tcfg.greyText;
    promptY  = windowRect(4) * tcfg.promptYFrac;
    titleY   = windowRect(4) * tcfg.instructionTitleY;
    bodyY    = windowRect(4) * tcfg.instructionBodyY;

    % ---- PASS 1: greyed-out prompt ----
    Screen('FillRect', window, bg);
    Screen('TextSize', window, tcfg.titleSize);
    Screen('TextStyle', window, 1);
    DrawFormattedText(window, titleFirstInstructions, 'center', titleY, black);
    Screen('TextStyle', window, 0);
    Screen('TextSize', window, tcfg.bodySize);
    % Body stays black; only the spacebar prompt is grey during the lockout interval.
    drawFirstInstrBody(window, bodyY, black, tcfg, instrSegs, instrSegBold);
    Screen('TextSize', window, tcfg.promptSize);
    DrawFormattedText(window, 'Press SPACEBAR to continue.', 'center', promptY, greyText);

    [tOn, ~, ~, ~] = cfg.loggedFlip('instruction_grey_prompt', 'instruction', NaN, NaN, NaN);

    KbQueueFlush(cfg.kbDev);
    holdForSecondsWithAbort(tOn + lockSec, cfg);
    KbQueueFlush(cfg.kbDev);

    % ---- PASS 2: active prompt (black) ----
    Screen('FillRect', window, bg);
    Screen('TextSize', window, tcfg.titleSize);
    Screen('TextStyle', window, 1);
    DrawFormattedText(window, titleFirstInstructions, 'center', titleY, black);
    Screen('TextStyle', window, 0);
    Screen('TextSize', window, tcfg.bodySize);
    drawFirstInstrBody(window, bodyY, black, tcfg, instrSegs, instrSegBold);
    Screen('TextSize', window, tcfg.promptSize);
    DrawFormattedText(window, 'Press SPACEBAR to continue.', 'center', promptY, black);

    cfg.loggedFlip('instruction_active', 'instruction', NaN, NaN, NaN);

    KbQueueFlush(cfg.kbDev);
    waitForKeyQueue([cfg.keys.space], cfg.keys.escape, Inf, cfg);
end

function drawFirstInstrBody(window, bodyY, fg, tcfg, segs, boldOn)
    % DrawFormattedText uses sy as the baseline of the first line (yPosIsBaseline=1).
    % Chain segments with the returned cursor ny — not textbounds(4), or baselines misalign and text overlaps.
    yCur = bodyY;
    for ii = 1:numel(segs)
        Screen('TextSize', window, tcfg.bodySize);
        if boldOn(ii)
            Screen('TextStyle', window, 1);
        else
            Screen('TextStyle', window, 0);
        end
        [~, ny] = DrawFormattedText(window, segs{ii}, 'center', yCur, fg, tcfg.bodyWrap, [], [], tcfg.bodyLineSpacing);
        Screen('TextStyle', window, 0);
        yCur = ny;
    end
end

function showTrialOverviewScreen(window, windowRect, bg, black, cfg)

    tcfg = cfg.display.text;
    lockSec  = tcfg.lockSec;
    greyText = tcfg.greyText;
    titleTrialOverview = 'Change Blindness Trial Overview';

    % --- Load PNG as texture ---
    pngPath = cfg.trialOverviewPNG;
    if ~exist(pngPath, 'file')
        error('Trial overview PNG not found: %s', pngPath);
    end

    [img, map, alpha] = imread(pngPath);
    if ~isempty(map)
        img = uint8(ind2rgb(img, map) * 255);
    end
    if size(img, 3) == 4
        rgba = img;
    else
        if ndims(img) == 2
            rgb = repmat(img, [1 1 3]);
        else
            rgb = img(:, :, 1:3);
        end
        if ~isempty(alpha)
            a = alpha;
            if ndims(a) == 3
                a = a(:, :, 1);
            end
            if ~isa(a, 'uint8')
                if islogical(a)
                    a = uint8(a) * 255;
                else
                    ad = double(a);
                    if max(ad(:)) <= 1 && min(ad(:)) >= 0
                        a = uint8(ad * 255);
                    else
                        a = uint8(max(0, min(255, ad)));
                    end
                end
            end
            rgba = cat(3, rgb, a);
        else
            rgba = cat(3, rgb, 255 * ones(size(rgb, 1), size(rgb, 2), 'uint8'));
        end
    end
    % RGBA + default blend (set after OpenWindow) lets transparent PNG areas show cfg background.
    tex = Screen('MakeTexture', window, rgba);
    imgH = size(rgba, 1);
    imgW = size(rgba, 2);

    KbQueueFlush(cfg.kbDev);

    % --- Text blocks (aligned with web task copy; spacebar = Continue) ---
    topText = [ ...
        '\n\nOn each trial, the sequence will look like the example below.\n\n' ...
        'First, a fixation cross will appear in the centre. Next, you will see four circles, a brief blank screen, then the four circles again.\n' ...
        'During each trial, please keep your eyes on the fixation cross in the centre of the screen, even when the circles appear.\nTry to avoid looking around at the individual circles during the brief sequence.\n\n' ...
        'After the sequence, you will answer all three questions in this order:\n' ...
        '1) PAS clarity, 2) detection using the GREEN/RED buttons, 3) localisation.\n' ...
        'The diagram shows examples of the stimulus, PAS, and localisation screens.\n\n' ...
    ];

    bottomText = [ ...
        '\nYou will always answer PAS, detection, and localisation, including after a RED/No response.\n' ...
        'We will begin with some practice trials so you can get comfortable with the task.\n' ...
    ];

    % ---- Draw with greyed prompt ----
    Screen('FillRect', window, bg);

    Screen('TextSize', window, tcfg.titleSize);
    Screen('TextStyle', window, 1);
    DrawFormattedText(window, titleTrialOverview, 'center', windowRect(4) * tcfg.trialOverviewTitleY, black);
    Screen('TextStyle', window, 0);
    Screen('TextSize', window, tcfg.bodySize);
    [~, ~, topBounds] = DrawFormattedText(window, topText, 'center', windowRect(4) * tcfg.trialOverviewTopY, black, tcfg.bodyWrap, [], [], tcfg.bodyLineSpacing);
    topBottomY = topBounds(4);

    % --- Fit + place image ---
    [xc, ~] = RectCenter(windowRect);

    reserveBottomPx = tcfg.trialOverviewReserveBottomPx; % room for bottomText + prompt
    maxW = windowRect(3) * 0.90;
    maxH = (windowRect(4) - topBottomY - reserveBottomPx) * 0.95;
    maxH = max(maxH, 50);
    pngScaleMult = 0.80;

    scale = min(maxW / imgW, maxH / imgH) * pngScaleMult;
    dstW = imgW * scale;
    dstH = imgH * scale;

    imgTopY = topBottomY + 20;
    dstRect = CenterRectOnPoint([0 0 dstW dstH], xc, imgTopY + dstH/2);

    Screen('DrawTexture', window, tex, [], dstRect);

    % --- Bottom explanatory text ---
    Screen('TextSize', window, tcfg.bodySize);
    bottomY = dstRect(4) + 30;
    DrawFormattedText(window, bottomText, 'center', bottomY, black, tcfg.bodyWrap, [], [], tcfg.bodyLineSpacing);

    % --- Greyed "Press SPACE…" line ---
    promptY = windowRect(4) * tcfg.promptYFrac;
    Screen('TextSize', window, tcfg.promptSize);
    DrawFormattedText(window, 'Press SPACEBAR to continue.', 'center', promptY, greyText);

    [tOn, ~, ~, ~] = cfg.loggedFlip('trial_overview_grey', 'trial_overview', NaN, NaN, NaN);

    % Lockout (ESC still works)
    KbQueueFlush(cfg.kbDev);
    holdForSecondsWithAbort(tOn + lockSec, cfg);
    KbQueueFlush(cfg.kbDev);

    % ---- Redraw identical screen but prompt in black ----
    Screen('FillRect', window, bg);

    Screen('TextSize', window, tcfg.titleSize);
    Screen('TextStyle', window, 1);
    DrawFormattedText(window, titleTrialOverview, 'center', windowRect(4) * tcfg.trialOverviewTitleY, black);
    Screen('TextStyle', window, 0);
    Screen('TextSize', window, tcfg.bodySize);
    [~, ~, topBounds] = DrawFormattedText(window, topText, 'center', windowRect(4) * tcfg.trialOverviewTopY, black, tcfg.bodyWrap, [], [], tcfg.bodyLineSpacing);
    topBottomY = topBounds(4);

    imgTopY = topBottomY + 20;
    dstRect = CenterRectOnPoint([0 0 dstW dstH], xc, imgTopY + dstH/2);
    Screen('DrawTexture', window, tex, [], dstRect);

    Screen('TextSize', window, tcfg.bodySize);
    bottomY = dstRect(4) + 30;
    DrawFormattedText(window, bottomText, 'center', bottomY, black, tcfg.bodyWrap, [], [], tcfg.bodyLineSpacing);

    Screen('TextSize', window, tcfg.promptSize);
    DrawFormattedText(window, 'Press SPACEBAR to continue.', 'center', promptY, black);

    cfg.loggedFlip('trial_overview_active', 'trial_overview', NaN, NaN, NaN);

    KbQueueFlush(cfg.kbDev);
    waitForKeyQueue([cfg.keys.space], cfg.keys.escape, Inf, cfg);

    % Cleanup texture
    Screen('Close', tex);
end

function showPractice1Intro(window, windowRect, bg, black, cfg)

    % --- Settings (match your other screens) ---
    tcfg = cfg.display.text;
    lockSec  = tcfg.lockSec;
    greyText = tcfg.greyText;
    promptY  = windowRect(4) * tcfg.promptYFrac;
    titlePractice1 = 'Practice Information\n\n\n\n';

    % --- Notice text (tight + readable) ---
    practice1BodyA = [ ...
        'Before we begin the practice trials, please remember:\n\n'
    ];
    practice1BoldOrder = 'Question order: PAS, detection, then localisation.\n\n';
    practice1BodyB = [ ...
        'Question 1 is the 1-4 PAS clarity rating using q/w/e/r.\n' ...
        'Question 2 is detection: GREEN means Yes and RED means No.\n' ...
        'Question 3 is localisation using the labelled quadrant buttons.\n' ...
        'Always answer all three questions, including after a RED/No response.\n\n\n' ...
    ];
    practice1BoldBlocks = 'You will be completing two practice blocks:\n\n';
    practice1BodyC = [ ...
        'In the first practice block the trials will include feedback.\n' ...
        'You can ask the researcher questions at any time during the practice trials.\n' ...
    ];
    practice1Segs = { practice1BodyA, practice1BoldOrder, practice1BodyB, practice1BoldBlocks, practice1BodyC };
    practice1SegBold = [ false, true, false, true, false ];
    practiceBodyY = windowRect(4) * tcfg.practiceBodyY;

    % ---- PASS 1: greyed prompt (optional lockout) ----
    Screen('FillRect', window, bg);
    Screen('TextSize', window, tcfg.titleSize);
    Screen('TextStyle', window, 1);
    DrawFormattedText(window, titlePractice1, 'center', windowRect(4) * tcfg.practiceTitleY, black);
    Screen('TextStyle', window, 0);
    Screen('TextSize', window, tcfg.bodySize);
    drawFirstInstrBody(window, practiceBodyY, black, tcfg, practice1Segs, practice1SegBold);
    Screen('TextSize', window, tcfg.promptSize);
    DrawFormattedText(window, 'Press SPACEBAR to continue.', 'center', promptY, greyText);

    [tOn, ~, ~, ~] = cfg.loggedFlip('practice1_intro_grey', 'practice1_intro', NaN, NaN, NaN);

    KbQueueFlush(cfg.kbDev);

    if lockSec > 0
        holdForSecondsWithAbort(tOn + lockSec, cfg);
        KbQueueFlush(cfg.kbDev);
    end

    % ---- PASS 2: active prompt ----
    Screen('FillRect', window, bg);
    Screen('TextSize', window, tcfg.titleSize);
    Screen('TextStyle', window, 1);
    DrawFormattedText(window, titlePractice1, 'center', windowRect(4) * tcfg.practiceTitleY, black);
    Screen('TextStyle', window, 0);
    Screen('TextSize', window, tcfg.bodySize);
    drawFirstInstrBody(window, practiceBodyY, black, tcfg, practice1Segs, practice1SegBold);
    Screen('TextSize', window, tcfg.promptSize);
    DrawFormattedText(window, 'Press SPACEBAR to continue.', 'center', promptY, black);
    cfg.loggedFlip('practice1_intro_active', 'practice1_intro', NaN, NaN, NaN);

    KbQueueFlush(cfg.kbDev);
    waitForKeyQueue([cfg.keys.space], cfg.keys.escape, Inf, cfg);
end

function showPressSpaceToBeginScreen(window, windowRect, bg, black, cfg, flipLabel)

    tcfg = cfg.display.text;
    titleTxt = 'When you are ready press SPACEBAR to begin';
    reminderTxt = 'Remember: please keep your eyes on the centre cross during each trial';

    [~, yc] = RectCenter(windowRect);
    Screen('FillRect', window, bg);
    Screen('TextSize', window, tcfg.titleSize);
    Screen('TextStyle', window, 1);
    [~, ny] = DrawFormattedText(window, titleTxt, 'center', yc - round(RectHeight(windowRect) * 0.06), black, tcfg.bodyWrap);
    Screen('TextStyle', window, 0);
    Screen('TextSize', window, tcfg.bodySize);
    DrawFormattedText(window, reminderTxt, 'center', ny + round(RectHeight(windowRect) * 0.06), black, tcfg.bodyWrap);
    cfg.loggedFlip(flipLabel, flipLabel, NaN, NaN, NaN);

    KbQueueFlush(cfg.kbDev);
    waitForKeyQueue([cfg.keys.space], cfg.keys.escape, Inf, cfg);
end

function showPractice1BeginScreen(window, windowRect, bg, black, cfg) %#ok<INUSD>

    showPressSpaceToBeginScreen(window, windowRect, bg, black, cfg, 'practice1_begin');
end

function checkAbort(cfg)
    [pressed, firstPress] = KbQueueCheck(cfg.kbDev);
    if pressed && firstPress(cfg.keys.escape) > 0
        error('CB_4xGratings_v3_Orientation:UserAbort', 'Experiment terminated by user (ESC).');
    end
end

function showPractice2Intro(window, windowRect, bg, black, cfg)

    % --- Settings (match your other screens) ---
    tcfg = cfg.display.text;
    lockSec  = tcfg.lockSec;
    greyText = tcfg.greyText;
    promptY  = windowRect(4) * tcfg.promptYFrac;
    titlePractice2 = 'Practice Information\n\n\n\n\n\n\n\n';

    PracticeText2a = [ ...
        '\nNice work!\n\n' ...
        'You will now complete a second block of practice trials designed to feel more like the real task.\n' ...
        'Remember that some trials will contain a change, and some trials will NOT contain a change.\n\n' ...
        'Question 1 is PAS clarity using q/w/e/r. Question 2 is detection using GREEN for Yes and RED for No.\n' ...
        'Question 3 is localisation using the labelled quadrant buttons. Always answer all three questions.\n\n' ...
    ];
    PracticeText2b = 'Feedback will be removed for this second block.\n';

    % ---- PASS 1: greyed prompt (optional lockout) ----
    Screen('FillRect', window, bg);
    Screen('TextSize', window, tcfg.titleSize);
    Screen('TextStyle', window, 1);
    DrawFormattedText(window, titlePractice2, 'center', windowRect(4) * tcfg.practiceTitleY, black);
    Screen('TextStyle', window, 0);
    Screen('TextSize', window, tcfg.bodySize);
    [~, ny] = DrawFormattedText(window, PracticeText2a, 'center', windowRect(4) * tcfg.practiceBodyY, black, tcfg.bodyWrap, [], [], tcfg.bodyLineSpacing);
    Screen('TextStyle', window, 1);
    DrawFormattedText(window, PracticeText2b, 'center', ny, black, tcfg.bodyWrap, [], [], tcfg.bodyLineSpacing);
    Screen('TextStyle', window, 0);
    Screen('TextSize', window, tcfg.promptSize);
    DrawFormattedText(window, 'Press SPACEBAR to continue.', 'center', promptY, greyText);

    [tOn, ~, ~, ~] = cfg.loggedFlip('practice2_intro_grey', 'practice2_intro', NaN, NaN, NaN);

    KbQueueFlush(cfg.kbDev);

    if lockSec > 0
        holdForSecondsWithAbort(tOn + lockSec, cfg);
        KbQueueFlush(cfg.kbDev);
    end

    % ---- PASS 2: active prompt ----
    Screen('FillRect', window, bg);
    Screen('TextSize', window, tcfg.titleSize);
    Screen('TextStyle', window, 1);
    DrawFormattedText(window, titlePractice2, 'center', windowRect(4) * tcfg.practiceTitleY, black);
    Screen('TextStyle', window, 0);
    Screen('TextSize', window, tcfg.bodySize);
    [~, ny] = DrawFormattedText(window, PracticeText2a, 'center', windowRect(4) * tcfg.practiceBodyY, black, tcfg.bodyWrap, [], [], tcfg.bodyLineSpacing);
    Screen('TextStyle', window, 1);
    DrawFormattedText(window, PracticeText2b, 'center', ny, black, tcfg.bodyWrap, [], [], tcfg.bodyLineSpacing);
    Screen('TextStyle', window, 0);
    Screen('TextSize', window, tcfg.promptSize);
    DrawFormattedText(window, 'Press SPACEBAR to continue.', 'center', promptY, black);
    cfg.loggedFlip('practice2_intro_active', 'practice2_intro', NaN, NaN, NaN);

    KbQueueFlush(cfg.kbDev);
    waitForKeyQueue([cfg.keys.space], cfg.keys.escape, Inf, cfg);
end

function showPractice2BeginScreen(window, windowRect, bg, black, cfg) %#ok<INUSD>

    showPressSpaceToBeginScreen(window, windowRect, bg, black, cfg, 'practice2_begin');
end

function showMainExperimentIntroScreen(window, windowRect, bg, black, cfg)

    % --- Settings (match your other screens) ---
    tcfg = cfg.display.text;
    lockSec  = tcfg.lockSec;
    greyText = tcfg.greyText;
    promptY  = windowRect(4) * tcfg.promptYFrac;
    titleMainExperiment = 'Experiment Information';

    txt = [ ...
        '\nWell done!\nYou''ve finished the practice trials.\n' ...
        'You will now begin the main experimental trial blocks.\n\n' ...
        'The task will continue throughout the full run with regular breaks for you to rest and refresh.\n' ...
        'You will NOT receive feedback during the main run.\n\n' ...
        'Remember that some trials will contain a change, and some trials will NOT contain a change.\n\n' ...
        'As before, please keep your eyes on the centre fixation cross during each trial, even when the circles appear.\n\n' ...
        'Question 1 is PAS clarity using q/w/e/r. Question 2 is detection using GREEN for Yes and RED for No.\n' ...
        'Question 3 is localisation using the labelled quadrant buttons. Always answer all three questions.\n' ...
    ];

    % ---- PASS 1: greyed prompt ----
    Screen('FillRect', window, bg);
    Screen('TextSize', window, tcfg.titleSize);
    Screen('TextStyle', window, 1);
    DrawFormattedText(window, titleMainExperiment, 'center', windowRect(4) * tcfg.mainTitleY, black);
    Screen('TextStyle', window, 0);
    Screen('TextSize', window, tcfg.bodySize);
    DrawFormattedText(window, txt, 'center', windowRect(4) * tcfg.mainBodyY, black, tcfg.bodyWrap, [], [], tcfg.bodyLineSpacing);
    Screen('TextSize', window, tcfg.promptSize);
    DrawFormattedText(window, 'Press SPACEBAR to continue.', 'center', promptY, greyText);

    [tOn, ~, ~, ~] = cfg.loggedFlip('main_intro_grey', 'main_intro', NaN, NaN, NaN);

    KbQueueFlush(cfg.kbDev);

    if lockSec > 0
        holdForSecondsWithAbort(tOn + lockSec, cfg);
        KbQueueFlush(cfg.kbDev);
    end

    % ---- PASS 2: active prompt ----
    Screen('FillRect', window, bg);
    Screen('TextSize', window, tcfg.titleSize);
    Screen('TextStyle', window, 1);
    DrawFormattedText(window, titleMainExperiment, 'center', windowRect(4) * tcfg.mainTitleY, black);
    Screen('TextStyle', window, 0);
    Screen('TextSize', window, tcfg.bodySize);
    DrawFormattedText(window, txt, 'center', windowRect(4) * tcfg.mainBodyY, black, tcfg.bodyWrap, [], [], tcfg.bodyLineSpacing);
    Screen('TextSize', window, tcfg.promptSize);
    DrawFormattedText(window, 'Press SPACEBAR to continue.', 'center', promptY, black);
    cfg.loggedFlip('main_intro_active', 'main_intro', NaN, NaN, NaN);

    KbQueueFlush(cfg.kbDev);
    waitForKeyQueue([cfg.keys.space], cfg.keys.escape, Inf, cfg);
end

function showMainTrialBeginScreen(window, windowRect, bg, black, cfg) 

    showPressSpaceToBeginScreen(window, windowRect, bg, black, cfg, 'main_begin');
end

function showBlockBreakScreen(window, windowRect, bg, black, cfg, blockJustFinished, totalBlocks)

    tcfg = cfg.display.text;
    lockSec  = tcfg.lockSec;
    greyText = tcfg.greyText;
    promptY  = windowRect(4) * tcfg.promptYFrac;

    titleTxt = sprintf('Block %d of %d complete', blockJustFinished, totalBlocks);
    bodyTxt = [ ...
        'Nice work!\n\n' ...
        'Please take a moment to rest your eyes and relax your hands and shoulders.\nThe next block will not begin until you press SPACEBAR.\n\n' ...
        'If you would like a longer break, a sip of water, or a seated stretch, please let the researcher know.' ...
    ];
    % mergedTxt = sprintf('%s\n\n%s', titleTxt, bodyTxt);

    % ---- PASS 1: greyed prompt ----
    Screen('FillRect', window, bg);
    [~, yc] = RectCenter(windowRect);
    titleY = yc - round(RectHeight(windowRect) * 0.18);
    bodyGap = round(RectHeight(windowRect) * 0.045);
    
    Screen('TextSize', window, tcfg.titleSize);
    Screen('TextStyle', window, 1);  % bold
    [~, titleBottom] = DrawFormattedText(window, titleTxt, 'center', titleY, black, tcfg.bodyWrap);
    
    Screen('TextSize', window, tcfg.bodySize);
    Screen('TextStyle', window, 0);  % normal
    DrawFormattedText(window, bodyTxt, 'center', titleBottom + bodyGap, black, tcfg.bodyWrap, [], [], tcfg.bodyLineSpacing);
    Screen('TextSize', window, tcfg.promptSize);
    DrawFormattedText(window, 'Press SPACEBAR to continue.', 'center', promptY, greyText);

    [tOn, ~, ~, ~] = cfg.loggedFlip('block_break_grey', 'block_break', NaN, blockJustFinished, NaN);
    KbQueueFlush(cfg.kbDev);
    if lockSec > 0
        holdForSecondsWithAbort(tOn + lockSec, cfg);
        KbQueueFlush(cfg.kbDev);
    end

    % ---- PASS 2: active prompt ----
    Screen('FillRect', window, bg);
    
    Screen('TextSize', window, tcfg.titleSize);
    Screen('TextStyle', window, 1);  % bold
    [~, titleBottom] = DrawFormattedText(window, titleTxt, 'center', titleY, black, tcfg.bodyWrap);
    
    Screen('TextSize', window, tcfg.bodySize);
    Screen('TextStyle', window, 0);  % normal
    DrawFormattedText(window, bodyTxt, 'center', titleBottom + bodyGap, black, tcfg.bodyWrap, [], [], tcfg.bodyLineSpacing);
    
    Screen('TextSize', window, tcfg.promptSize);
    DrawFormattedText(window, 'Press SPACEBAR to continue.', 'center', promptY, black);
    cfg.loggedFlip('block_break_active', 'block_break', NaN, blockJustFinished, NaN);

    KbQueueFlush(cfg.kbDev);
    waitForKeyQueue([cfg.keys.space], cfg.keys.escape, Inf, cfg);
end

function showBlockResumeScreen(window, windowRect, bg, black, cfg) 

    showPressSpaceToBeginScreen(window, windowRect, bg, black, cfg, 'block_resume');
end

function result = classifyPractice1(summary, cfg)

    crit = cfg.practice1Criteria;

    % Pull metrics (safe defaults)
    faRateNCH       = NaN;
    easyDetectRate  = NaN;
    easySeeRate     = NaN;
    changeDetectRate = NaN;

    if isfield(summary,'faRateNCH'),        faRateNCH = summary.faRateNCH; end
    if isfield(summary,'easyDetectRate'),   easyDetectRate = summary.easyDetectRate; end
    if isfield(summary,'easySeeRate'),      easySeeRate = summary.easySeeRate; end
    if isfield(summary,'changeDetectRate'), changeDetectRate = summary.changeDetectRate; end

    % ---- Safety rule: missing metrics => conservative fail ----
    requiredMissing = isnan(faRateNCH) || isnan(easyDetectRate) || isnan(easySeeRate);
    if requiredMissing
        warning('classifyPractice1: Missing required practice metrics. Treating as fail_conservative.');
        result = 'fail_conservative';
        return;
    end

    % Optional extra metric
    if isfield(crit,'useChangeDetect') && crit.useChangeDetect
        if isnan(changeDetectRate)
            warning('classifyPractice1: changeDetectRate missing. Treating as fail_conservative.');
            result = 'fail_conservative';
            return;
        end
    end

    % ---- Decision order: liberal first, then conservative ----
    if faRateNCH > crit.maxFARateNCH
        result = 'fail_liberal';
        return;
    end

    conservativeFail = (easyDetectRate < crit.minEasyDetect) || ...
                       (easySeeRate    < crit.minEasySee);

    if isfield(crit,'useChangeDetect') && crit.useChangeDetect
        conservativeFail = conservativeFail || (changeDetectRate < crit.minChangeDetect);
    end

    if conservativeFail
        result = 'fail_conservative';
    else
        result = 'pass';
    end
end

function printPracticeSummary(summary, label)

    if nargin < 2 || isempty(label)
        label = 'Practice';
    end

    fprintf('\n=== %s Summary ===\n', label);

    if isfield(summary,'nTrials')
        fprintf('nTrials=%d', summary.nTrials);
        if isfield(summary,'nSTD') && isfield(summary,'nNCH') && isfield(summary,'nEASY')
            fprintf('  (STD=%d, NCH=%d, EASY=%d)', summary.nSTD, summary.nNCH, summary.nEASY);
        end
        fprintf('\n');
    end

    % Helper for pretty printing NaN-safe values
    fprintf('StdDetect=%s | StdSee=%s | FA(NCH)=%s | CR(NCH)=%s | EasyDetect=%s | EasySee=%s | ChangeDetect=%s | ChangeSee=%s\n', ...
        fmtRate(getFieldOrNaN(summary,'stdDetectRate')), ...
        fmtRate(getFieldOrNaN(summary,'stdSeeRate')), ...
        fmtRate(getFieldOrNaN(summary,'faRateNCH')), ...
        fmtRate(getFieldOrNaN(summary,'crRateNCH')), ...
        fmtRate(getFieldOrNaN(summary,'easyDetectRate')), ...
        fmtRate(getFieldOrNaN(summary,'easySeeRate')), ...
        fmtRate(getFieldOrNaN(summary,'changeDetectRate')), ...
        fmtRate(getFieldOrNaN(summary,'changeSeeRate')));

    if isfield(summary,'classification')
        fprintf('classification=%s\n', string(summary.classification));
    end
end

function v = getFieldOrNaN(s, fieldName)
    if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
        v = s.(fieldName);
        if isempty(v)
            v = NaN;
        end
    else
        v = NaN;
    end
end

function v = getTextFieldOrDefault(s, fieldName, defaultValue)
    if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
        v = string(s.(fieldName));
    else
        v = string(defaultValue);
    end
end

function s = fmtRate(v)
    if isnan(v)
        s = 'NaN';
    else
        s = sprintf('%.2f', v);
    end
end

function holdForSecondsWithAbort(tEnd, cfg)
    while GetSecs < tEnd
        checkAbort(cfg);
        WaitSecs(0.001);
    end
end

function [key, secs] = waitForKeyQueue(validKeys, escapeKey, maxSecs, cfg)
    KbQueueFlush(cfg.kbDev);
    tStart = GetSecs;

    while true
        [pressed, firstPress] = KbQueueCheck(cfg.kbDev);

        if pressed
            if firstPress(escapeKey) > 0
                error('CB_4xGratings_v3_Orientation:UserAbort', 'Experiment terminated by user (ESC).');
            end

            vkPress = firstPress(validKeys);
            idx = find(vkPress > 0);

            if ~isempty(idx)
                % pick earliest of the valid keys
                [secs, minIdx] = min(vkPress(idx));
                key = validKeys(idx(minIdx));
                return;
            end
        end

        if (GetSecs - tStart) > maxSecs
            key = NaN;
            secs = GetSecs;
            return;
        end

        WaitSecs(0.001);
    end
end


function label = orientationMagnitudeLabel(mag)
    if isnan(mag)
        label = 'NCH';
    else
        if abs(10 * mag - round(10 * mag)) < 1e-9
            label = sprintf('M%.1f', mag);  % preserve existing labels for full-run magnitudes
        else
            label = sprintf('M%.12g', mag);
        end
        label = strrep(label, '.', 'p');
    end
end

function pTrials = buildPracticeTrialList(pracCfg, allowedOri)

    % Trial template
    trialTemplate = struct( ...
        'trialType', '', ...          % 'STD' | 'NCH' | 'EASY'
        'isChange', false, ...
        'changeQuad', NaN, ...
        'changeStartOri', NaN, ...
        'changeMagnitudeDeg', NaN, ...
        'staircase', 'P');

    nTotal = pracCfg.nTrials;
    pTrials = repmat(trialTemplate, nTotal, 1);

    magSTD = getPracticeMagnitude(pracCfg, 'magnitudeSTDDeg', 45);
    magEasy = getPracticeMagnitude(pracCfg, 'magnitudeEASYDeg', 90);

    k = 1;

    nSTD = pracCfg.nSTD;
    stdQuads = makeBalancedQuads(nSTD);
    for i = 1:nSTD
        pTrials(k).trialType  = 'STD';
        pTrials(k).isChange   = true;
        pTrials(k).changeQuad = stdQuads(i);
        pTrials(k).changeMagnitudeDeg = magSTD;
        pTrials(k).staircase = orientationMagnitudeLabel(magSTD);
        k = k + 1;
    end

    nNCH = pracCfg.nNCH;
    for i = 1:nNCH
        pTrials(k).trialType  = 'NCH';
        pTrials(k).isChange   = false;
        pTrials(k).changeQuad = NaN;
        pTrials(k).changeMagnitudeDeg = 0;
        pTrials(k).staircase = 'NCH';
        k = k + 1;
    end

    nEASY = pracCfg.nEASY;
    easyQuads = makeBalancedQuads(nEASY);
    for i = 1:nEASY
        pTrials(k).trialType  = 'EASY';
        pTrials(k).isChange   = true;
        pTrials(k).changeQuad = easyQuads(i);
        pTrials(k).changeMagnitudeDeg = magEasy;
        pTrials(k).staircase = orientationMagnitudeLabel(magEasy);
        k = k + 1;
    end

    assert(k-1 == nTotal, 'buildPracticeTrialList: Trial count mismatch.');

    chgIdx = find([pTrials.isChange]);
    if ~isempty(chgIdx)
        v = repmat(allowedOri(:)', 1, ceil(numel(chgIdx) / numel(allowedOri)));
        v = v(1:numel(chgIdx));
        v = v(randperm(numel(v)));
        for ii = 1:numel(chgIdx)
            pTrials(chgIdx(ii)).changeStartOri = v(ii);
        end
    end

    pTrials = pTrials(randperm(numel(pTrials)));
end

function mag = getPracticeMagnitude(pracCfg, fieldName, fallback)
    if isfield(pracCfg, fieldName) && isnumeric(pracCfg.(fieldName)) && isfinite(pracCfg.(fieldName))
        mag = pracCfg.(fieldName);
    else
        mag = fallback;
    end
end

function [mags, counts, nNoChange, trialsPerBlock] = validateQuickRunProfile(debugCfg)
    requiredFields = {'quickRunMagnitudesDeg', 'quickRunChangeCounts', ...
        'quickRunNoChangeTrials', 'quickRunTrialsPerBlock'};
    for ii = 1:numel(requiredFields)
        if ~isfield(debugCfg, requiredFields{ii})
            error('CB_4xGratings_v3_Orientation:InvalidQuickRunProfile', ...
                'Missing cfg.debug.%s.', requiredFields{ii});
        end
    end

    mags = debugCfg.quickRunMagnitudesDeg;
    counts = debugCfg.quickRunChangeCounts;
    nNoChange = debugCfg.quickRunNoChangeTrials;
    trialsPerBlock = debugCfg.quickRunTrialsPerBlock;

    if ~isnumeric(mags) || ~isreal(mags) || ~isvector(mags) || isempty(mags) || ...
            any(~isfinite(mags)) || any(mags <= 0) || any(mags > 90)
        error('CB_4xGratings_v3_Orientation:InvalidQuickRunProfile', ...
            'quickRunMagnitudesDeg must be a non-empty vector of finite values in (0, 90].');
    end
    mags = double(mags(:)');
    if any(diff(sort(mags)) < 1e-9)
        error('CB_4xGratings_v3_Orientation:InvalidQuickRunProfile', ...
            'quickRunMagnitudesDeg must contain unique values.');
    end

    if ~isnumeric(counts) || ~isreal(counts) || ~isvector(counts) || isempty(counts) || ...
            any(~isfinite(counts)) || any(counts <= 0) || any(abs(counts - round(counts)) > 1e-9)
        error('CB_4xGratings_v3_Orientation:InvalidQuickRunProfile', ...
            'quickRunChangeCounts must be a non-empty vector of positive integers.');
    end
    counts = double(round(counts(:)'));
    if numel(mags) ~= numel(counts)
        error('CB_4xGratings_v3_Orientation:InvalidQuickRunProfile', ...
            'quickRunMagnitudesDeg and quickRunChangeCounts must have the same length.');
    end

    if ~isnumeric(nNoChange) || ~isreal(nNoChange) || ~isscalar(nNoChange) || ...
            ~isfinite(nNoChange) || nNoChange < 0 || abs(nNoChange - round(nNoChange)) > 1e-9
        error('CB_4xGratings_v3_Orientation:InvalidQuickRunProfile', ...
            'quickRunNoChangeTrials must be a non-negative integer scalar.');
    end
    nNoChange = double(round(nNoChange));

    if ~isnumeric(trialsPerBlock) || ~isreal(trialsPerBlock) || ~isscalar(trialsPerBlock) || ...
            ~isfinite(trialsPerBlock) || trialsPerBlock <= 0 || ...
            abs(trialsPerBlock - round(trialsPerBlock)) > 1e-9
        error('CB_4xGratings_v3_Orientation:InvalidQuickRunProfile', ...
            'quickRunTrialsPerBlock must be a positive integer scalar.');
    end
    trialsPerBlock = double(round(trialsPerBlock));

    nChange = sum(counts);
    nTotal = nChange + nNoChange;
    if mod(nTotal, trialsPerBlock) ~= 0
        error('CB_4xGratings_v3_Orientation:InvalidQuickRunProfile', ...
            ['Quick-run total trials (%d) must be divisible by ' ...
             'quickRunTrialsPerBlock (%d).'], nTotal, trialsPerBlock);
    end

    nBlocks = nTotal / trialsPerBlock;
    if mod(nChange, nBlocks) ~= 0 || mod(nNoChange, nBlocks) ~= 0
        error('CB_4xGratings_v3_Orientation:InvalidQuickRunProfile', ...
            ['Quick-run change (%d) and no-change (%d) totals must each be ' ...
             'divisible by the derived number of blocks (%d).'], ...
            nChange, nNoChange, nBlocks);
    end
end

function trials = buildTrialList(cfg)

    trialTemplate = struct( ...
        'isChange', 0, ...
        'staircase', 'NCH', ...
        'changeQuad', 0, ...
        'changeStartOri', NaN, ...
        'changeMagnitudeDeg', NaN, ...
        'magnitudeIndex', NaN, ...
        'magnitudeLabel', '');
    trials = repmat(trialTemplate, cfg.nTotal, 1);

    mags = cfg.design.changeMagnitudesDeg(:)';
    magCounts = cfg.design.changeCountsPerMagnitude(:)';
    assert(numel(mags) == numel(magCounts), ...
        'buildTrialList: Magnitude and count vectors must have the same length.');
    assert(sum(magCounts) == cfg.nChange, ...
        'buildTrialList: Magnitude-specific counts must sum to nChange.');

    magPool = repelem(mags, magCounts);
    magPool = magPool(randperm(numel(magPool)));

    if mod(cfg.nChange, 4) == 0
        quadPool = repmat(1:4, 1, cfg.nChange / 4);
        quadPool = quadPool(randperm(numel(quadPool)));
    else
        quadPool = makeBalancedQuads(cfg.nChange);
    end

    idxChange = 0;
    idx0 = 1;

    for b = 1:cfg.nBlocks
        if isfield(cfg,'trialDial') && isfield(cfg.trialDial,'applyPerBlock') && cfg.trialDial.applyPerBlock
            nChg = cfg.trialDial.nChangePerBlock;
            nCat = cfg.trialDial.nNoChangePerBlock;
        else
            nChg = round(cfg.trialsPerBlock * cfg.trialDial.pChange);
            nCat = cfg.trialsPerBlock - nChg;
        end

        block = repmat(trialTemplate, cfg.trialsPerBlock, 1);
        k = 1;

        for i = 1:nChg
            idxChange = idxChange + 1;
            mag = magPool(idxChange);
            label = orientationMagnitudeLabel(mag);

            block(k).isChange = 1;
            block(k).staircase = label;
            block(k).magnitudeLabel = label;
            block(k).changeMagnitudeDeg = mag;
            block(k).magnitudeIndex = find(abs(mags - mag) < 1e-9, 1, 'first');
            block(k).changeQuad = quadPool(idxChange);
            k = k + 1;
        end

        for i = 1:nCat
            block(k).isChange = 0;
            block(k).staircase = 'NCH';
            block(k).magnitudeLabel = 'NCH';
            block(k).changeMagnitudeDeg = 0;
            block(k).magnitudeIndex = 0;
            block(k).changeQuad = 0;
            k = k + 1;
        end

        order = randperm(numel(block));
        block = block(order);
        trials(idx0:idx0+cfg.trialsPerBlock-1) = block;
        idx0 = idx0 + cfg.trialsPerBlock;
    end

    assert(idxChange == cfg.nChange, 'buildTrialList: change-trial count mismatch.');
    trials = assignBalancedChangeStartOri(trials, cfg.stim.allowedOri);
end

function q = makeBalancedQuads(n)
    base = repmat(1:4, 1, floor(n/4));
    rem = n - numel(base);
    if rem > 0
        base = [base randperm(4, rem)];
    end
    q = base(randperm(n));
end

function tex = makeGratingTexture(window, sz, cyclesPerStim, contrast, bg, gaborSigmaFrac)

    if nargin < 6 || isempty(gaborSigmaFrac)
        gaborSigmaFrac = 0.40; % default
    end

    % ----------------------------
    % 1) Carrier: sinusoidal grating
    % ----------------------------
    % Your original setup: cyclesPerStim cycles across the patch width
    [xRad, ~] = meshgrid(linspace(-pi, pi, sz), linspace(-pi, pi, sz));
    carrier = sin(cyclesPerStim * xRad);

    % ----------------------------
    % 2) Envelope: 2D Gaussian
    % ----------------------------
    [xPix, yPix] = meshgrid(1:sz, 1:sz);
    xPix = xPix - (sz+1)/2;
    yPix = yPix - (sz+1)/2;

    radius = (sz/2 - 1);
    sigma  = max(1, radius * gaborSigmaFrac);

    envelope = exp(-(xPix.^2 + yPix.^2) / (2*sigma^2));  % peaks at 1 in centre

    % Optional: clip tiny values for cleaner edges (not required)
    % envelope(envelope < 1/255) = 0;

    % ----------------------------
    % 3) Combine into a Gabor
    % ----------------------------
    % Contrast is strongest at centre, fades outwards
    img = bg + (contrast * 0.5) * (envelope .* carrier);
    img = min(max(img, 0), 1);

    % ----------------------------
    % 4) Alpha channel (use the Gaussian itself)
    % ----------------------------
    % This makes the patch blend perfectly into the background at the edges.
    alpha = min(max(envelope, 0), 1);

    % ----------------------------
    % 5) RGBA texture
    % ----------------------------
    rgb  = uint8(img * 255);
    a    = uint8(alpha * 255);
    rgba = cat(3, rgb, rgb, rgb, a);

    tex = Screen('MakeTexture', window, rgba);
end


function drawGratings(window, tex, allRects, orientations, bg)
    Screen('FillRect', window, bg);
    for i = 1:4
        Screen('DrawTexture', window, tex, [], allRects(i,:), orientations(i));
    end
end

function drawFixation(window, fixationCoords, lineWidthPx, colour, xCentre, yCentre)
    Screen('DrawLines', window, fixationCoords, lineWidthPx, colour, [xCentre yCentre], 2);
end

function drawFixationOnly(window, bg, fixationCoords, lineWidthPx, colour, xCentre, yCentre)
    Screen('FillRect', window, bg);
    drawFixation(window, fixationCoords, lineWidthPx, colour, xCentre, yCentre);
end

function drawQuadrantPrompt(window, windowRect, colour, bg, promptText, cfg)

    if nargin < 5 || isempty(promptText)
        promptText = 'Where was the change?';
    end
    qcfg = cfg.display.text.questions;

    Screen('FillRect', window, bg);
    [xc,yc] = RectCenter(windowRect);
    xLeft = windowRect(1);
    xRight = windowRect(3);
    yTop = windowRect(2);
    yBottom = windowRect(4);
    w = windowRect(3) - windowRect(1);
    h = windowRect(4) - windowRect(2);
    minDim = min(w, h);

    margin = round(minDim * qcfg.quadOuterMarginFrac);
    topReserve = round(h * qcfg.quadTopReserveFrac);
    bottomReserve = round(h * qcfg.quadBottomReserveFrac);

    gap = round(minDim * qcfg.quadGapFrac);
    boxDesired = round(minDim * qcfg.quadBoxFrac);

    % Fit quadrants to available area to avoid clipping on high-density displays.
    maxBoxByWidth = floor((w - 2 * margin - gap) / 2);
    maxBoxByHeightTop = floor(yc - (yTop + topReserve) - gap/2);
    maxBoxByHeightBottom = floor((yBottom - bottomReserve) - yc - gap/2);
    maxBoxByHeight = min(maxBoxByHeightTop, maxBoxByHeightBottom);
    box = max(60, min([boxDesired, maxBoxByWidth, maxBoxByHeight]));

    if box < 60
        box = 60;
        gap = max(30, min(gap, round(minDim * 0.06)));
    end

    half = box/2;
    offset = half + gap/2;

    quadRects = [
        xc - offset - half, yc - offset - half, xc - gap/2,         yc - gap/2;
        xc + gap/2,         yc - offset - half, xc + offset + half, yc - gap/2;
        xc - offset - half, yc + gap/2,         xc - gap/2,         yc + offset + half;
        xc + gap/2,         yc + gap/2,         xc + offset + half, yc + offset + half
    ];

    for i = 1:4
        Screen('FrameRect', window, colour, quadRects(i,:), qcfg.quadFrameWidthPx);
        [cx,cy] = RectCenter(quadRects(i,:));
        Screen('TextSize', window, qcfg.quadNumberSize);
        nb = Screen('TextBounds', window, num2str(i));
        xNum = cx - (nb(3) - nb(1))/2;
        yNum = cy - (nb(4) - nb(2))/2;
        DrawFormattedText(window, num2str(i), xNum, yNum, colour);
    end

    % prompt line (now customisable)
    Screen('TextSize', window, qcfg.quadPromptSize);
    quadTop = yc - (offset + half);
    promptY = max(yTop + round(h * 0.03), quadTop - round(h * qcfg.quadPromptYOffsetFrac));
    DrawFormattedText(window, promptText, 'center', promptY, colour, qcfg.quadPromptWrap);
end


function drawDetection(window, windowRect, colour, bg, cfg)
    Screen('TextFont', window, 'Arial');
    Screen('TextStyle', window, 0);
    Screen('FillRect', window, bg);
    [~, yc] = RectCenter(windowRect);
    h = windowRect(4) - windowRect(2);
    qcfg = cfg.display.text.questions;

    Screen('TextSize', window, qcfg.pasQuestionSize);
    DrawFormattedText(window, 'Did you detect a change?', 'center', yc - round(h * 0.12), colour, qcfg.pasQuestionWrap);

    Screen('TextSize', window, qcfg.pasNumberSize);
    DrawFormattedText(window, 'GREEN button = Yes        RED button = No', 'center', yc + round(h * 0.06), colour, qcfg.pasQuestionWrap);
end

function drawPAS(window, windowRect, colour, bg, cfg)
    Screen('TextFont', window, 'Arial');
    Screen('TextStyle', window, 0);
    Screen('FillRect', window, bg);
    [~, yc] = RectCenter(windowRect);
    w = windowRect(3) - windowRect(1);
    h = windowRect(4) - windowRect(2);
    qcfg = cfg.display.text.questions;

    % Question
    Screen('TextSize', window, qcfg.pasQuestionSize);
    DrawFormattedText(window, 'How clearly did you experience the change?', 'center', yc - round(h * qcfg.pasQuestionYOffsetFrac), colour, qcfg.pasQuestionWrap);

    % Numbers + your current descriptions
    nums = {'1', '2', '3', '4'};
    desc = { ...
        'I didn''t experience a change', ...
        'I felt like there was a change', ...
        'I saw something change', ...
        'I clearly saw the change' ...
    };

    % Bracketed original PAS labels (edit these to match the exact wording you want)
    labels = { ...
        '(No experience)', ...
        '(Brief experience)', ...
        '(Almost clear experience)', ...
        '(Clear experience)' ...
    };

    sideMargin = round(w * qcfg.pasSideMarginFrac);
    n  = numel(nums);
    xs = linspace(windowRect(1) + sideMargin, windowRect(3) - sideMargin, n);

    % Layout tuning
    yNum      = yc + round(h * qcfg.pasNumYOffsetFrac);
    yDescTop  = yNum + round(h * qcfg.pasDescTopGapFrac);
    yNum      = round(yNum);
    yDescTop  = round(yDescTop);

    numSize    = qcfg.pasNumberSize;
    textSize   = qcfg.pasDescSize;
    labelSize  = qcfg.pasLabelSize;
    lineStep   = round(h * qcfg.pasLineStepFrac);
    labelGap   = round(h * qcfg.pasLabelGapFrac);

    for i = 1:n
        % --- draw number (centred) ---
        Screen('TextSize', window, numSize);
        nb = Screen('TextBounds', window, nums{i});
        xNum = round(xs(i) - (nb(3) - nb(1))/2);
        DrawFormattedText(window, nums{i}, xNum, yNum, colour);

        % --- draw description (centred, can wrap if you add '\n') ---
        Screen('TextSize', window, textSize);
        lines = strsplit(desc{i}, '\n');

        yLine = yDescTop;
        for L = 1:numel(lines)
            lb = Screen('TextBounds', window, lines{L});
            xLine = round(xs(i) - (lb(3) - lb(1))/2);
            DrawFormattedText(window, lines{L}, xLine, yLine, colour);
            yLine = yLine + lineStep;
        end

        % --- draw bracketed label under description (centred) ---
        Screen('TextSize', window, labelSize);
        lab = labels{i};
        bb = Screen('TextBounds', window, lab);
        xLab = round(xs(i) - (bb(3) - bb(1))/2);
        yLab = yLine + labelGap;   % sits right under the description block
        DrawFormattedText(window, lab, xLab, yLab, colour);
    end
end

function val = keyToMappedValue(keyCode, keyList, valueList)
    val = NaN;
    if isempty(keyCode) || (isscalar(keyCode) && isnan(keyCode))
        return;
    end

    % Scalar key code from waitForKeyQueue; tolerate vector for safety
    if ~isscalar(keyCode)
        idxPress = find(keyCode > 0, 1, 'first');
        if isempty(idxPress)
            return;
        end
        keyCode = keyList(idxPress);
    end

    idx = find(keyList == keyCode, 1, 'first');
    if ~isempty(idx)
        val = valueList(idx);
    end
end

function v = clamp(v, lo, hi)
    v = max(lo, min(hi, v));
end

function displayCfg = makeDisplayProfile(profileName)
    name = lower(strtrim(profileName));

    switch name
        case 'viewpixx'
            displayCfg = struct();
            displayCfg.profile = 'viewpixx';
            displayCfg.viewDistanceCm = 60;
            displayCfg.screenWidthCm = 53.1;   % nominal 24" 16:9 active width
            displayCfg.screenWidthPx = 1920;

            textCfg = struct();
            textCfg.lockSec = 10;
            textCfg.greyText = 0.40;
            textCfg.promptYFrac = 0.92;
            textCfg.titleSize = 44;
            textCfg.bodySize = 30;
            textCfg.promptSize = 28;
            textCfg.bodyWrap = 140;
            textCfg.bodyLineSpacing = 1.25;

            textCfg.instructionTitleY = 0.08;
            textCfg.instructionBodyY = 0.18;
            textCfg.trialOverviewTitleY = 0.06;
            textCfg.trialOverviewTopY = 0.13;
            textCfg.trialOverviewReserveBottomPx = 240;
            textCfg.practiceTitleY = 0.10;
            textCfg.practiceBodyY = 0.18;
            textCfg.mainTitleY = 0.10;
            textCfg.mainBodyY = 0.18;

            qCfg = struct();
            qCfg.quadGapFrac = 0.05;
            qCfg.quadBoxFrac = 0.55;
            qCfg.quadFrameWidthPx = 3;
            qCfg.quadNumberSize = 34;
            qCfg.quadPromptSize = 28;
            qCfg.quadPromptWrap = 120;
            qCfg.quadPromptYOffsetFrac = 0.04;
            qCfg.quadOuterMarginFrac = 0.05;
            qCfg.quadTopReserveFrac = 0.20;
            qCfg.quadBottomReserveFrac = 0.06;

            qCfg.pasQuestionSize = 32;
            qCfg.pasQuestionWrap = 120;
            qCfg.pasQuestionYOffsetFrac = 0.18;
            qCfg.pasSideMarginFrac = 0.16;
            qCfg.pasNumYOffsetFrac = 0.06;
            qCfg.pasDescTopGapFrac = 0.05;
            qCfg.pasNumberSize = 32;
            qCfg.pasDescSize = 26;
            qCfg.pasLabelSize = 22;
            qCfg.pasLineStepFrac = 0.028;
            qCfg.pasLabelGapFrac = 0.010;
            textCfg.questions = qCfg;

            fbCfg = struct();
            fbCfg.promptYFrac = 0.92;
            fbCfg.textSize = 32;
            fbCfg.textWrap = 120;
            fbCfg.lineSpacing = 1.25;
            fbCfg.promptSize = 28;
            textCfg.feedback = fbCfg;
            displayCfg.text = textCfg;

        case 'default'
            displayCfg = struct();
            displayCfg.profile = 'default';
            displayCfg.viewDistanceCm = 60;
            displayCfg.screenWidthCm = 53.1;
            displayCfg.screenWidthPx = 1920;

            textCfg = struct();
            textCfg.lockSec = 10;
            textCfg.greyText = 0.40;
            textCfg.promptYFrac = 0.92;
            textCfg.titleSize = 38;
            textCfg.bodySize = 26;
            textCfg.promptSize = 24;
            textCfg.bodyWrap = 120;
            textCfg.bodyLineSpacing = 1.30;

            textCfg.instructionTitleY = 0.08;
            textCfg.instructionBodyY = 0.17;
            textCfg.trialOverviewTitleY = 0.06;
            textCfg.trialOverviewTopY = 0.12;
            textCfg.trialOverviewReserveBottomPx = 220;
            textCfg.practiceTitleY = 0.10;
            textCfg.practiceBodyY = 0.17;
            textCfg.mainTitleY = 0.10;
            textCfg.mainBodyY = 0.17;

            qCfg = struct();
            qCfg.quadGapFrac = 0.09;
            qCfg.quadBoxFrac = 0.40;
            qCfg.quadFrameWidthPx = 3;
            qCfg.quadNumberSize = 30;
            qCfg.quadPromptSize = 24;
            qCfg.quadPromptWrap = 100;
            qCfg.quadPromptYOffsetFrac = 0.04;
            qCfg.quadOuterMarginFrac = 0.05;
            qCfg.quadTopReserveFrac = 0.20;
            qCfg.quadBottomReserveFrac = 0.06;

            qCfg.pasQuestionSize = 28;
            qCfg.pasQuestionWrap = 110;
            qCfg.pasQuestionYOffsetFrac = 0.18;
            qCfg.pasSideMarginFrac = 0.18;
            qCfg.pasNumYOffsetFrac = 0.06;
            qCfg.pasDescTopGapFrac = 0.05;
            qCfg.pasNumberSize = 28;
            qCfg.pasDescSize = 22;
            qCfg.pasLabelSize = 20;
            qCfg.pasLineStepFrac = 0.030;
            qCfg.pasLabelGapFrac = 0.012;
            textCfg.questions = qCfg;

            fbCfg = struct();
            fbCfg.promptYFrac = 0.92;
            fbCfg.textSize = 28;
            fbCfg.textWrap = 100;
            fbCfg.lineSpacing = 1.25;
            fbCfg.promptSize = 24;
            textCfg.feedback = fbCfg;
            displayCfg.text = textCfg;

        otherwise
            error('Unknown display profile: %s. Use ''viewpixx'' or ''default''.', profileName);
    end
end

function geom = computeDisplayGeometry(displayCfg, windowRect)
    geom = struct();

    activeWidthPx = windowRect(3) - windowRect(1);
    if isfield(displayCfg,'screenWidthPx') && displayCfg.screenWidthPx > 0
        activeWidthPx = displayCfg.screenWidthPx;
    end

    geom.activeWidthPx = activeWidthPx;
    geom.screenWidthCm = displayCfg.screenWidthCm;
    geom.viewDistanceCm = displayCfg.viewDistanceCm;
    geom.pixelsPerCm = geom.activeWidthPx / geom.screenWidthCm;

    cmPerDeg = 2 * geom.viewDistanceCm * tan((1 * pi / 180) / 2);
    geom.pxPerDeg = geom.pixelsPerCm * cmPerDeg;
end

function px = degToPx(deg, geom)
    px = deg * geom.pxPerDeg;
end

function r = emptyResultRow()
    r = struct( ...
        'participantID', '', ...
        'trialNum', NaN, ...
        'blockNum', NaN, ...
        'isChange', NaN, ...
        'staircase', '', ...
        'changeQuad', NaN, ...
        'durFrames', NaN, ...
        'durSec', NaN, ...
        's1Frames', NaN, ...
        's1Sec', NaN, ...
        'isiFrames', NaN, ...
        'isiSec', NaN, ...
        's2Frames', NaN, ...
        's2Sec', NaN, ...
        'gapFrames', NaN, ...
        'gapSec', NaN, ...
        'changeAngleDeg', NaN, ...
        'changeMagnitudeDeg', NaN, ...
        'trackName', '', ...
        'trackTargetOutcome', '', ...
        'trackTargetProb', NaN, ...
        'selectedPBlind', NaN, ...
        'selectedPSensing', NaN, ...
        'selectedPSeeing', NaN, ...
        'selectedPAware', NaN, ...
        'selectedPDetect', NaN, ...
        'selectedPLocGivenAware', NaN, ...
        'posteriorEntropyBits', NaN, ...
        'oriS1', '', ...
        'oriS2', '', ...
        'tS1', NaN, ...
        'tISI', NaN, ...
        'tS2', NaN, ...
        'tGap', NaN, ...
        'actualS1Frames', NaN, ...
        'actualISIFrames', NaN, ...
        'actualS2Frames', NaN, ...
        'actualGapFrames', NaN, ...
        'missedFixOn', NaN, ...
        'missedS1', NaN, ...
        'missedISI', NaN, ...
        'missedS2', NaN, ...
        'missedGap', NaN, ...
        'missedQ1', NaN, ...
        'missedQ2', NaN, ...
        'missedQ3', NaN, ...
        'missedPAS', NaN, ...
        'missedDetect', NaN, ...
        'missedLoc', NaN, ...
        'missedITI', NaN, ...
        'tQ1', NaN, ...
        'tQ2', NaN, ...
        'tQ3', NaN, ...
        'tPAS', NaN, ...
        'tDetect', NaN, ...
        'tLoc', NaN, ...
        'detectResp', NaN, ...
        'detectRT', NaN, ...
        'resp2', NaN, ...
        'locResp', NaN, ...
        'locRT', NaN, ...
        'pas', NaN, ...
        'pasRT', NaN, ...
        'hit', NaN, ...
        'locCorrect', NaN, ...
        'outcomeBin', '', ...
        'track1_xCurrent', NaN, ...
        'track2_xCurrent', NaN, ...
        'track3_xCurrent', NaN, ...
        'track1_frozen', NaN, ...
        'track2_frozen', NaN, ...
        'track3_frozen', NaN, ...
        'track1_frozenFrames', NaN, ...
        'track2_frozenFrames', NaN, ...
        'track3_frozenFrames', NaN, ...
        'tTrialStart', NaN, ...
        'tTrialEnd',   NaN, ...
        'trialTotalSec', NaN ...
    );
end

function qTex = cacheQuestionTextures(window, windowRect, black, bg, cfg)

    w = RectWidth(windowRect);
    h = RectHeight(windowRect);
    offRect = [0 0 w h];

    off = Screen('OpenOffscreenWindow', window, bg, offRect);
    try
        Screen('TextFont', off, 'Arial');
        Screen('TextSize', off, 45);

        Screen('FillRect', off, bg);
        drawDetection(off, offRect, black, bg, cfg);
        img = Screen('GetImage', off);
        qTex.Detect = Screen('MakeTexture', window, img);

        Screen('FillRect', off, bg);
        drawQuadrantPrompt(off, offRect, black, bg, 'Where was the change?', cfg);
        img = Screen('GetImage', off);
        qTex.Loc_default = Screen('MakeTexture', window, img);

        Screen('FillRect', off, bg);
        drawQuadrantPrompt(off, offRect, black, bg, 'Select a quadrant, even if you said no change.', cfg);
        img = Screen('GetImage', off);
        qTex.Loc_detectNo = Screen('MakeTexture', window, img);

        Screen('FillRect', off, bg);
        drawPAS(off, offRect, black, bg, cfg);
        img = Screen('GetImage', off);
        qTex.PAS = Screen('MakeTexture', window, img);
    catch me
        Screen('Close', off);
        rethrow(me);
    end
    Screen('Close', off);

    Screen('FillRect', window, bg);
end

function s = numToStrOrNA(x)
    if isempty(x)
        s = 'NA';
        return;
    end

    if isstring(x) || ischar(x)
        if strlength(string(x)) == 0
            s = 'NA';
        else
            s = char(string(x));
        end
        return;
    end

    if isnumeric(x) || islogical(x)
        if isscalar(x) && isnan(double(x))
            s = 'NA';
        elseif isscalar(x)
            if abs(double(x) - round(double(x))) < eps
                s = sprintf('%d', round(double(x)));
            else
                s = sprintf('%.6f', double(x));
            end
        else
            s = mat2str(x);
        end
        return;
    end

    try
        s = char(string(x));
    catch
        s = 'NA';
    end
end

function tobii = makeEmptyTobiiState()
    tobii = struct();
    tobii.enabled = false;
    tobii.initialized = false;
    tobii.calibrated = false;
    tobii.recording = false;
    tobii.saved = false;
    tobii.EThndl = [];
    tobii.calVal = {};
    tobii.saveBase = '';
end

function ensureTittaOnPath(cfg)
    if ~isfield(cfg, 'tobii') || ~isfield(cfg.tobii, 'tittaRoot') || isempty(cfg.tobii.tittaRoot)
        return;
    end

    if exist(cfg.tobii.tittaRoot, 'dir') ~= 7
        error('Titta root folder not found: %s', cfg.tobii.tittaRoot);
    end

    oldDir = pwd;
    cleanupObj = onCleanup(@() cd(oldDir)); %#ok<NASGU>
    cd(cfg.tobii.tittaRoot);

    if exist('addTittaToPath.m', 'file') == 2
        addTittaToPath;
    else
        addpath(genpath(cfg.tobii.tittaRoot));
    end

    rehash toolboxcache;
end

function tobii = initialiseAndCalibrateTobii(tobii, cfg, window)

    if ~isfield(cfg, 'tobii') || ~cfg.tobii.enable
        fprintf('Tobii disabled: cfg.tobii.enable = false\n');
        return;
    end

    try
        ensureTittaOnPath(cfg);

        if exist('Titta', 'class') ~= 8 && exist('Titta', 'file') ~= 2
            error('Titta is not on the MATLAB path. Check cfg.tobii.tittaRoot.');
        end

        settings = Titta.getDefaults(cfg.tobii.trackerProfile);
        settings.debugMode = cfg.tobii.debugMode;

        ui = cfg.tobii.ui;

        settings.UI.setup.bgColor        = ui.bgColor;
        settings.UI.setup.instruct.color = ui.textColor;
        settings.UI.setup.fixBackColor   = ui.fixBackColor;
        settings.UI.setup.fixFrontColor  = ui.fixFrontColor;

        if cfg.tobii.useAnimatedCalibration
            calViz                    = AnimatedCalibrationDisplay();
            settings.cal.drawFunction = @calViz.doDraw;
            calViz.bgColor            = ui.bgColor;
            calViz.fixBackColor       = ui.fixBackColor;
            calViz.fixFrontColor      = ui.fixFrontColor;
        else
            settings.cal.bgColor       = ui.bgColor;
            settings.cal.fixBackColor  = ui.fixBackColor;
            settings.cal.fixFrontColor = ui.fixFrontColor;
        end

        % Avoid dependency on Titta demo helper functions.
        settings.cal.pointNotifyFunction = [];

        settings.UI.val.bgColor                  = ui.bgColor;
        settings.UI.val.avg.text.color           = ui.textColor;
        settings.UI.val.fixBackColor             = ui.fixBackColor;
        settings.UI.val.fixFrontColor            = ui.fixFrontColor;
        settings.UI.val.onlineGaze.fixBackColor  = ui.fixBackColor;
        settings.UI.val.onlineGaze.fixFrontColor = ui.fixFrontColor;

        tobii.EThndl = Titta(settings);
        tobii.EThndl.init();
        tobii.enabled = true;
        tobii.initialized = true;

        fprintf('\nTobii/Titta initialized with tracker profile: %s\n', cfg.tobii.trackerProfile);

        try
            ListenChar(-1);
        catch
            ListenChar(2);
        end

        tobii.calVal{1} = tobii.EThndl.calibrate(window);
        tobii.calibrated = true;

        ListenChar(0);
        fprintf('Tobii calibration completed.\n\n');

    catch ME
        try ListenChar(0); catch, end

        if isfield(cfg, 'tobii') && isfield(cfg.tobii, 'requireTracker') && cfg.tobii.requireTracker
            rethrow(ME);
        else
            warning('Tobii disabled after initialization/calibration failure: %s', mExceptionText(ME));
            tobii = makeEmptyTobiiState();
        end
    end
end

function tobii = startTobiiRecording(tobii, cfg, windowRect, ifi, timestamp)

    if ~isfield(cfg, 'tobii') || ~cfg.tobii.enable || ~isfield(tobii, 'initialized') || ~tobii.initialized
        return;
    end

    try
        tobii.EThndl.buffer.start('gaze');
        WaitSecs(0.8);

        tobii.recording = true;
        tobii.saved = false;

        fprintf('Tobii gaze recording started.\n');
        fprintf('  screen=%d res=%dx%d hz=%.3f timestamp=%s\n\n', ...
            cfg.screenNumber, windowRect(3), windowRect(4), 1/ifi, timestamp);

    catch ME
        if cfg.tobii.requireTracker
            rethrow(ME);
        else
            warning('Tobii recording could not start: %s', mExceptionText(ME));
            tobii.recording = false;
        end
    end
end

function tobii = stopAndSaveTobii(tobii, cfg, outDir, participantID, timestamp, statusLabel)

    if nargin < 6 || isempty(statusLabel)
        statusLabel = 'complete';
    end

    if ~isfield(cfg, 'tobii') || ~cfg.tobii.enable
        return;
    end
    if ~isfield(tobii, 'initialized') || ~tobii.initialized || isempty(tobii.EThndl)
        return;
    end
    if isfield(tobii, 'saved') && tobii.saved
        return;
    end

    try
        if isfield(tobii, 'recording') && tobii.recording
            try
                tobii.EThndl.buffer.stop('gaze');
            catch
            end
            tobii.recording = false;
        end

        dat = tobii.EThndl.collectSessionData();
        dat.expt.scriptName    = cfg.outputPrefix;
        dat.expt.stage         = 'Stage3_fixedOrientation_passiveTobii';
        dat.expt.statusLabel   = statusLabel;
        dat.expt.participantID = participantID;
        dat.expt.timestamp     = timestamp;
        dat.expt.calVal        = tobii.calVal;
        dat.expt.configSummary = makeTobiiConfigSummary(cfg);

        saveBase = fullfile(outDir, sprintf('%s_%s_Tobii_%s', cfg.outputPrefix, participantID, timestamp));
        tobii.saveBase = saveBase;

        if cfg.tobii.saveMat
            tobii.EThndl.saveData(dat, saveBase, true);
        end

        if cfg.tobii.saveGazeCSV
            tobii.EThndl.saveGazeDataToTSV(dat, saveBase, true);
            convertTittaTSVToCSV(saveBase, cfg.tobii.deleteIntermediateTSV);
        end

        tobii.saved = true;
        fprintf('Saved Tobii Stage 3 data to:\n%s\n', saveBase);

    catch ME
        warning('Tobii save failed: %s', mExceptionText(ME));
    end

    try
        tobii.EThndl.deInit();
    catch
    end

    tobii.initialized = false;
end

function cfgSummary = makeTobiiConfigSummary(cfg)
    cfgSummary = struct();
    cfgSummary.participantID = cfg.participantID;
    cfgSummary.screenNumber = cfg.screenNumber;
    cfgSummary.debugWindow = cfg.debugWindow;
    cfgSummary.debugQuickRun = cfg.debug.quickRun;
    cfgSummary.eegEnable = cfg.eeg.enable;
    cfgSummary.nTotal = cfg.nTotal;
    cfgSummary.trialsPerBlock = cfg.trialsPerBlock;
    cfgSummary.nBlocks = cfg.nBlocks;
    cfgSummary.changePerBlock = cfg.trialDial.nChangePerBlock;
    cfgSummary.noChangePerBlock = cfg.trialDial.nNoChangePerBlock;
    cfgSummary.changeMagnitudesDeg = cfg.design.changeMagnitudesDeg;
    cfgSummary.changeCountsPerMagnitude = cfg.design.changeCountsPerMagnitude;
    cfgSummary.questionOrder = cfg.questionOrder;
    cfgSummary.detectionKeyMapping = cfg.detectionKeyMapping;
    cfgSummary.eegQuestionTriggerScheme = cfg.eegQuestionTriggerScheme;
    cfgSummary.S1_frames = cfg.S1_frames;
    cfgSummary.ISI_frames = cfg.ISI_frames;
    cfgSummary.S2_frames = cfg.S2_frames;
    cfgSummary.gap_frames = cfg.gap_frames;
    cfgSummary.design = cfg.design;
    cfgSummary.postS2Gap_sec = cfg.postS2Gap_sec;
    cfgSummary.ITI_sec = cfg.ITI_sec;
    cfgSummary.stim = cfg.stim;
    cfgSummary.fix = cfg.fix;
    cfgSummary.tobii = cfg.tobii;
end

function convertTittaTSVToCSV(saveBase, deleteTSV)
    if nargin < 2
        deleteTSV = false;
    end

    tsvFiles = dir([saveBase '*.tsv']);

    for iFile = 1:numel(tsvFiles)
        tsvPath = fullfile(tsvFiles(iFile).folder, tsvFiles(iFile).name);

        T = readtable(tsvPath, ...
            'FileType', 'text', ...
            'Delimiter', '\t', ...
            'VariableNamingRule', 'preserve');

        [outFolder, outName] = fileparts(tsvPath);
        csvPath = fullfile(outFolder, [outName '.csv']);

        writetable(T, csvPath);

        if deleteTSV
            delete(tsvPath);
        end
    end
end

function trigger = initSerialTrigger(eegCfg)

    trigger = struct( ...
        'enabled', false, ...
        'handle', [], ...
        'resetMode', 'blocking', ...
        'warnOnSendError', true, ...
        'pulseWidthSec', 0.002);

    if ~isfield(eegCfg, 'enable') || ~eegCfg.enable
        return;
    end

    if isfield(eegCfg, 'resetMode')
        trigger.resetMode = eegCfg.resetMode;
    end
    if isfield(eegCfg, 'warnOnSendError')
        trigger.warnOnSendError = eegCfg.warnOnSendError;
    end
    if isfield(eegCfg, 'pulseWidthSec')
        trigger.pulseWidthSec = eegCfg.pulseWidthSec;
    end

    try
        cfgString = sprintf('BaudRate=%d DTR=1 RTS=1', eegCfg.baudRate);
        trigger.handle = IOPort('OpenSerialPort', eegCfg.serialPort, cfgString);
        trigger.enabled = true;
        fprintf('EEG serial trigger enabled on %s @ %d baud.\n', eegCfg.serialPort, eegCfg.baudRate);
    catch ME
        trigger.enabled = false;
        trigger.handle = [];
        warning('EEG serial trigger disabled: %s', mExceptionText(ME));
    end
end

function closeSerialTrigger(cfg)
    try
        if isfield(cfg, 'trigger') && isfield(cfg.trigger, 'enabled') && cfg.trigger.enabled && ...
                isfield(cfg.trigger, 'handle') && ~isempty(cfg.trigger.handle)
            IOPort('Close', cfg.trigger.handle);
        end
    catch
    end
end

function cleanup(~, cfg)
    try
        try ListenChar(0); catch, end
        try Priority(0); catch, end
        try KbQueueRelease(cfg.kbDev); catch, end
        try closeSerialTrigger(cfg); catch, end
        try IOPort('CloseAll'); catch, end
        try ShowCursor; catch, end

        if isfield(cfg, 'qTex')
            try
                texVals = struct2cell(cfg.qTex);
                Screen('Close', [texVals{:}]);
            catch
            end
        end

        if exist('sca','file') == 2
            sca;
        elseif exist('Screen','file') == 2
            Screen('CloseAll');
        end
    catch
        try Screen('CloseAll'); catch, end
    end
end

function txt = mExceptionText(ME)
% One-line text from a caught exception for warnings/logs (safe if message is empty).
    txt = 'unknown error';
    if isempty(ME)
        return;
    end
    if isa(ME, 'MException')
        if ~isempty(ME.message)
            txt = char(ME.message);
        else
            try
                txt = strtrim(getReport(ME, 'basic', 'hyperlinks', 'off'));
            catch
            end
        end
        return;
    end
    try
        txt = char(ME);
    catch
    end
end


function checkpointSave(results, t, outFile, cfg)
    try
        r = results(1:t);
        r = r(~cellfun(@isempty,{r.participantID}));
        if isempty(r), return; end

        T = struct2table(r);
        T.questionOrder = repmat(string(cfg.questionOrder), height(T), 1);
        T.detectionKeyMapping = repmat(string(cfg.detectionKeyMapping), height(T), 1);
        T.eegQuestionTriggerScheme = repmat(string(cfg.eegQuestionTriggerScheme), height(T), 1);

        % Write to temp CSV first, then replace
        [p,n,e] = fileparts(outFile);              % e should be '.csv'
        tmpFile = fullfile(p, [n '_tmp' e]);       % e.g. '..._tmp.csv'

        writetable(T, tmpFile);                    % extension is recognised
        movefile(tmpFile, outFile, 'f');

        fprintf('Checkpoint saved (%d trials): %s\n', height(T), outFile);

    catch saveME
        warning('%s', ['Checkpoint save failed: ' mExceptionText(saveME)]);
    end
end

function trialLogLine(t, cfg, trial, durFrames, resp2, hit, locCorrect, pas, ~)

    if ~isfield(cfg,'debug') || ~isfield(cfg.debug,'trialLog') || ~cfg.debug.trialLog
        return;
    end

    blockNum = ceil(t / cfg.trialsPerBlock);

    if trial.isChange
        tc = 'CHG';
        qStr = sprintf('%d', trial.changeQuad);
        locStr = sprintf('%d', locCorrect);
    else
        tc = 'NCH';
        qStr = '-';
        locStr = '-';
    end

    if isnan(resp2), locStrResp = '-'; else, locStrResp = sprintf('%d', resp2); end
    if isnan(pas), pasStr = 'NaN'; else, pasStr = sprintf('%d', pas); end

    if trial.isChange
        if hit && ~isnan(locCorrect) && locCorrect == 1
            outcomeStr = 'SEE';
        elseif hit
            outcomeStr = 'SENS';
        else
            outcomeStr = 'BLIND';
        end
    else
        if hit
            outcomeStr = 'FA';
        else
            outcomeStr = 'CR';
        end
    end

    fprintf('blk=%02d trl=%03d %s mag=%.1f q=%s dur=%02d | PAS=%s DET=%d LOC=%s | loc=%s | %s\n', ...
        blockNum, t, tc, trial.changeMagnitudeDeg, qStr, durFrames, pasStr, hit, locStrResp, locStr, outcomeStr);
end

function summary = runPracticeBlock(window, windowRect, gratingTex, allRects, fixationCoords, xCentre, yCentre, ifi, cfg, bg, black, pracCfg)

    quadNames = {'TOP LEFT','TOP RIGHT','BOTTOM LEFT','BOTTOM RIGHT'};

    allowedOri = cfg.stim.allowedOri;

    % --- Build mixed practice trial list (STD / NCH / EASY) ---
    pTrials = buildPracticeTrialList(pracCfg, allowedOri);

    isPractice1 = strcmp(pracCfg.name, 'Practice Block 1');
    isPractice2 = strcmp(pracCfg.name, 'Practice Block 2');

    doPracticeTriggers = ...
        (isPractice1 && isfield(cfg.eeg.markerPolicy, 'markPracticeBlock1') && cfg.eeg.markerPolicy.markPracticeBlock1) || ...
        (isPractice2 && isfield(cfg.eeg.markerPolicy, 'markPracticeBlock2') && cfg.eeg.markerPolicy.markPracticeBlock2);

    pracOff = cfg.eeg.practiceCodeOffset;

    % --- Practice metrics counters ---
    m = struct();
    
    m.nTrials = numel(pTrials);
    
    m.nSTD = 0;  m.nSTD_detect = 0;  m.nSTD_see = 0;
    m.nNCH = 0;  m.nNCH_FA = 0;      m.nNCH_CR = 0;
    m.nEASY = 0; m.nEASY_detect = 0; m.nEASY_see = 0;
    
    m.nChange = 0; m.nChange_detect = 0; m.nChange_see = 0;

        for p = 1:numel(pTrials)
            trial = pTrials(p);
            checkAbort(cfg);
    
            % Build S1 orientations using the same rules as main task
            if trial.isChange
                oriS1 = makeOriS1_noPostChangeDup(trial.changeQuad, trial.changeStartOri, allowedOri, trial.changeMagnitudeDeg);
            else
                % No-change: still avoid "all same" and keep it non-trivial
                oriS1 = allowedOri(randperm(numel(allowedOri), 4))';
            end
            
            % Build S2
            oriS2 = oriS1;
            if trial.isChange
                % Use the same configurable orientation-change magnitude as the main task.
                oriS2(trial.changeQuad) = mod(oriS1(trial.changeQuad) + trial.changeMagnitudeDeg, 180);
            end
    
            % ---- Timeline (same as main) ----
            % Fixation jitter
            jitterFrames = randi([cfg.fixJitterFrames(1), cfg.fixJitterFrames(2)], 1, 1);
            drawFixationOnly(window, bg, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
            Screen('DrawingFinished', window);
            vblTargetFixOn = GetSecs + 0.5 * ifi;
            [tFixOn, ~, ~, missedFixOn] = cfg.loggedFlip('FixOn', pracCfg.name, p, NaN, vblTargetFixOn);
            if doPracticeTriggers
                cfg.emitTrigger('trialStart', pracCfg.name, p, NaN, cfg.eeg.codes.trialStart + pracOff, 'FixOn', tFixOn);
            end
            tTrialStart = tFixOn;

            drawGratings(window, gratingTex, allRects, oriS1, bg);
            drawFixation(window, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
            vblTargetS1 = tFixOn + (jitterFrames - 0.5) * ifi;
            [tS1,  ~, ~, ~]  = cfg.loggedFlip('S1', pracCfg.name, p, NaN, vblTargetS1);
            if doPracticeTriggers
                cfg.emitTrigger('s1On', pracCfg.name, p, NaN, cfg.eeg.codes.s1On + pracOff, 'S1', tS1);
            end

            drawFixationOnly(window, bg, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
            vblTargetISI = tS1 + (cfg.S1_frames - 0.5) * ifi;
            [tISI, ~, ~, ~] = cfg.loggedFlip('ISI', pracCfg.name, p, NaN, vblTargetISI);
            if doPracticeTriggers
                cfg.emitTrigger('isiOn', pracCfg.name, p, NaN, cfg.eeg.codes.isiOn + pracOff, 'ISI', tISI);
            end

            drawGratings(window, gratingTex, allRects, oriS2, bg);
            drawFixation(window, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
            vblTargetS2 = tISI + (cfg.ISI_frames - 0.5) * ifi;
            [tS2,  ~, ~, ~]  = cfg.loggedFlip('S2', pracCfg.name, p, NaN, vblTargetS2);
            if doPracticeTriggers
                cfg.emitTrigger('s2On', pracCfg.name, p, NaN, cfg.eeg.codes.s2On + pracOff, 'S2', tS2);
            end

            drawFixationOnly(window, bg, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
            vblTargetGap = tS2 + (cfg.S2_frames - 0.5) * ifi;
            [tGap, ~, ~, ~] = cfg.loggedFlip('Gap', pracCfg.name, p, NaN, vblTargetGap);
            if doPracticeTriggers
                cfg.emitTrigger('gapOn', pracCfg.name, p, NaN, cfg.eeg.codes.gapOn + pracOff, 'Gap', tGap);
            end
    
            % ---- Questions ----

            % Q1 (PAS)
            Screen('DrawTexture', window, cfg.qTex.PAS);
            Screen('DrawingFinished', window);
            vblTargetQ1 = tGap + (cfg.gap_frames - 0.5) * ifi;
            [tQ1, ~, ~, ~] = cfg.loggedFlip('Q1_PAS', pracCfg.name, p, NaN, vblTargetQ1);
            if doPracticeTriggers
                cfg.emitTrigger('q1On', pracCfg.name, p, NaN, cfg.eeg.codes.q1On + pracOff, 'Q1_PAS', tQ1);
            end
            [pasKey, pasTime] = waitForKeyQueue(cfg.keys.pas, cfg.keys.escape, cfg.maxRespSec, cfg);
            pas = keyToMappedValue(pasKey, cfg.keys.pas, cfg.keys.pasValues);
            if isfield(cfg, 'emitTobii')
                cfg.emitTobii('PAS_RESP', 'Q1_PAS', pracCfg.name, p, NaN, pasTime, ...
                    sprintf('pas=%s keyCode=%s rtMs=%.3f trialType=%s', numToStrOrNA(pas), numToStrOrNA(pasKey), (pasTime - tQ1) * 1000, trial.trialType));
            end
            if doPracticeTriggers && cfg.eeg.markerPolicy.markResponses
                if ~isnan(pas) && pas >= 1 && pas <= 4
                    cfg.emitTrigger('pasResponse', pracCfg.name, p, NaN, cfg.eeg.codes.pasBase + pas + pracOff, 'Q1_PAS', tQ1);
                end
            end

            % Q2 (Detection Yes/No)
            drawDetection(window, windowRect, black, bg, cfg);
            Screen('DrawingFinished', window);
            vblTargetQ2 = GetSecs + 0.5 * ifi;
            [tQ2, ~, ~, ~] = cfg.loggedFlip('Q2_Detect', pracCfg.name, p, NaN, vblTargetQ2);
            if doPracticeTriggers
                cfg.emitTrigger('q2On', pracCfg.name, p, NaN, cfg.eeg.codes.q2On + pracOff, 'Q2_Detect', tQ2);
            end
            [detectKey, detectTime] = waitForKeyQueue(cfg.keys.detect, cfg.keys.escape, cfg.maxRespSec, cfg);
            detectResp = keyToMappedValue(detectKey, cfg.keys.detect, cfg.keys.detectValues);
            detectRT = detectTime - tQ2;
            if isfield(cfg, 'emitTobii')
                cfg.emitTobii('DETECT_RESP', 'Q2_Detect', pracCfg.name, p, NaN, detectTime, ...
                    sprintf('detect=%s keyCode=%s rtMs=%.3f trialType=%s', numToStrOrNA(detectResp), numToStrOrNA(detectKey), detectRT * 1000, trial.trialType));
            end
            if doPracticeTriggers && cfg.eeg.markerPolicy.markResponses
                if ~isnan(detectResp)
                    if detectResp == 1
                        cfg.emitTrigger('detectYes', pracCfg.name, p, NaN, cfg.eeg.codes.detectYes + pracOff, 'Q2_Detect', tQ2);
                    elseif detectResp == 0
                        cfg.emitTrigger('detectNo', pracCfg.name, p, NaN, cfg.eeg.codes.detectNo + pracOff, 'Q2_Detect', tQ2);
                    end
                end
            end
            detected = double(~isnan(detectResp) && detectResp == 1);

            % Q3 (localisation, always asked)
            if detected == 0
                Screen('DrawTexture', window, cfg.qTex.Loc_detectNo);
            else
                Screen('DrawTexture', window, cfg.qTex.Loc_default);
            end
            Screen('DrawingFinished', window);
            vblTargetQ3 = GetSecs + 0.5 * ifi;
            [tQ3, ~, ~, ~] = cfg.loggedFlip('Q3_Loc', pracCfg.name, p, NaN, vblTargetQ3);
            if doPracticeTriggers
                cfg.emitTrigger('q3On', pracCfg.name, p, NaN, cfg.eeg.codes.q3On + pracOff, 'Q3_Loc', tQ3);
            end
            [resp2Key, resp2Time] = waitForKeyQueue(cfg.keys.quad, cfg.keys.escape, cfg.maxRespSec, cfg);
            resp2 = keyToMappedValue(resp2Key, cfg.keys.quad, cfg.keys.quadValues);
            if isfield(cfg, 'emitTobii')
                cfg.emitTobii('LOC_RESP', 'Q3_Loc', pracCfg.name, p, NaN, resp2Time, ...
                    sprintf('loc=%s keyCode=%s rtMs=%.3f trialType=%s', numToStrOrNA(resp2), numToStrOrNA(resp2Key), (resp2Time - tQ3) * 1000, trial.trialType));
            end
            if doPracticeTriggers && cfg.eeg.markerPolicy.markResponses
                if ~isnan(resp2) && resp2 >= 1 && resp2 <= 4
                    cfg.emitTrigger('locResponse', pracCfg.name, p, NaN, cfg.eeg.codes.locBase + resp2 + pracOff, 'Q3_Loc', tQ3);
                end
            end

            if trial.isChange
                if isnan(resp2)
                    locCorrect = 0;
                else
                    locCorrect = double(resp2 == trial.changeQuad);
                end
            else
                locCorrect = NaN;
            end

            % ---- Practice metrics ----
            if trial.isChange
                m.nChange = m.nChange + 1;
                if detected
                    m.nChange_detect = m.nChange_detect + 1;
                end
                if detected && locCorrect == 1
                    m.nChange_see = m.nChange_see + 1;
                end
            end

            switch trial.trialType
                case 'STD'
                    m.nSTD = m.nSTD + 1;
                    if detected
                        m.nSTD_detect = m.nSTD_detect + 1;
                    end
                    if detected && locCorrect == 1
                        m.nSTD_see = m.nSTD_see + 1;
                    end

                case 'NCH'
                    m.nNCH = m.nNCH + 1;
                    if detected
                        m.nNCH_FA = m.nNCH_FA + 1;
                    else
                        m.nNCH_CR = m.nNCH_CR + 1;
                    end

                case 'EASY'
                    m.nEASY = m.nEASY + 1;
                    if detected
                        m.nEASY_detect = m.nEASY_detect + 1;
                    end
                    if detected && locCorrect == 1
                        m.nEASY_see = m.nEASY_see + 1;
                    end
            end

            if cfg.practice.logToCommandWindow
                if trial.isChange
                    qStr = numToStrOrNA(trial.changeQuad);
                    locStr = numToStrOrNA(locCorrect);
                    if detected && locCorrect == 1
                        outcomeStr = 'SEE';
                    elseif detected
                        outcomeStr = 'SENS';
                    else
                        outcomeStr = 'BLIND';
                    end
                else
                    qStr = '-';
                    locStr = '-';
                    if detected
                        outcomeStr = 'FA';
                    else
                        outcomeStr = 'CR';
                    end
                end

                fprintf(['PRACTICE %-16s trl=%02d/%02d type=%-4s mag=%5.1f q=%s | ' ...
                    'PAS=%s DET=%s LOC=%s | loc=%s | %s\n'], ...
                    pracCfg.name, p, numel(pTrials), trial.trialType, trial.changeMagnitudeDeg, qStr, ...
                    numToStrOrNA(pas), numToStrOrNA(detectResp), numToStrOrNA(resp2), locStr, outcomeStr);
            end
    
            % ---- Feedback ----
            if pracCfg.feedback
                if trial.isChange
                    correctQuadName = quadNames{trial.changeQuad};
                end
        
                 if trial.isChange
                    if detected && locCorrect == 1
                        fb = 'Nice.\n\nYou detected the change\nand localised it correctly.';
                    elseif detected && locCorrect == 0
                        fb = sprintf('Close.\n\nYou detected the change,\nbut localised it incorrectly.\n\nCorrect location: %s', correctQuadName);
                    else
                        fb = sprintf('Missed.\n\nYou did not detect the change.\n\nCorrect location: %s', correctQuadName);
                    end
                else
                    % No-change practice trials (if you're mixing them in)
                    if detected
                        fb = 'No change occurred.\n\nThat was a false alarm.';
                    else
                        fb = 'Correct.\n\nNo change occurred.';
                    end
                end
        
                fbcfg = cfg.display.text.feedback;
                promptY = windowRect(4) * fbcfg.promptYFrac;
        
                Screen('TextSize', window, fbcfg.textSize);
                Screen('FillRect', window, bg);
                DrawFormattedText(window, fb, 'center', 'center', black, fbcfg.textWrap, [], [], fbcfg.lineSpacing);
                
                if cfg.practice.feedbackWaitForSpace
                    Screen('TextSize', window, fbcfg.promptSize);
                    DrawFormattedText(window, 'Press SPACEBAR to continue.', 'center', promptY, black);
                end
                
                Screen('DrawingFinished', window);
                vblTargetFeedback = GetSecs + 0.5 * ifi;
                cfg.loggedFlip('practice_feedback', pracCfg.name, p, NaN, vblTargetFeedback);
        
        
                if cfg.practice.feedbackWaitForSpace
                    waitForKeyQueue([cfg.keys.space], cfg.keys.escape, Inf, cfg);
                else
                    WaitSecs(0.9);
                end
            end

            % ITI
            % drawFixationOnly(window, bg, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
            Screen('FillRect', window, bg);
            Screen('DrawingFinished', window);
            vblTargetITI = GetSecs + 0.5 * ifi;
            [tITI, ~, ~, missedITI] = cfg.loggedFlip('ITI', pracCfg.name, p, NaN, vblTargetITI);
            if doPracticeTriggers
                cfg.emitTrigger('trialEnd', pracCfg.name, p, NaN, cfg.eeg.codes.trialEnd + pracOff, 'ITI', tITI);
            end
            holdForSecondsWithAbort(tITI + cfg.ITI_frames*ifi, cfg);
        end

        summary = struct();
        summary.name = pracCfg.name;
        summary.nTrials = m.nTrials;
        
        summary.nSTD = m.nSTD;
        summary.nSTD_detect = m.nSTD_detect;
        summary.nSTD_see = m.nSTD_see;
        summary.nNCH = m.nNCH;
        summary.nEASY = m.nEASY;
        
        summary.nChange = m.nChange;
        
        summary.nNCH_FA = m.nNCH_FA;
        summary.nNCH_CR = m.nNCH_CR;
        
        summary.nEASY_detect = m.nEASY_detect;
        summary.nEASY_see    = m.nEASY_see;
        
        summary.nChange_detect = m.nChange_detect;
        summary.nChange_see    = m.nChange_see;

        summary.stdDetectRate  = safeRate(m.nSTD_detect, m.nSTD);
        summary.stdSeeRate     = safeRate(m.nSTD_see, m.nSTD);
        
        summary.faRateNCH      = safeRate(m.nNCH_FA, m.nNCH);
        summary.crRateNCH      = safeRate(m.nNCH_CR, m.nNCH);
        
        summary.easyDetectRate = safeRate(m.nEASY_detect, m.nEASY);
        summary.easySeeRate    = safeRate(m.nEASY_see, m.nEASY);
        
        summary.changeDetectRate = safeRate(m.nChange_detect, m.nChange);
        summary.changeSeeRate    = safeRate(m.nChange_see, m.nChange);

    end

function cfg = applyTrialDial(cfg)
    % Uses cfg.trialDial.pChange to set cfg.nChange/cfg.nCatch.
    % nChange/nCatch are forced to multiples of 3 so the Blind/Sensing/Seeing
    % tracks each receive an integer number of change AND catch trials.

    if ~isfield(cfg,'trialDial') || ~isfield(cfg.trialDial,'pChange')
        error('applyTrialDial: Missing cfg.trialDial.pChange');
    end

    p = cfg.trialDial.pChange;
    p = max(0, min(1, p));

    nChange = round(cfg.nTotal * p);
    nChange = 3 * round(nChange/3);
    nChange = max(0, min(cfg.nTotal, nChange));

    cfg.nChange = nChange;
    cfg.nCatch  = cfg.nTotal - cfg.nChange;

    if mod(cfg.nCatch,3) ~= 0
        error('applyTrialDial: nCatch is not divisible by 3. Make cfg.nTotal divisible by 3 and pChange reasonable.');
    end
end

function trials = assignBalancedChangeStartOri(trials, allowedOri)
    isChg = [trials.isChange] == 1;
    if ~any(isChg)
        return;
    end

    mags = unique([trials(isChg).changeMagnitudeDeg]);

    for mm = 1:numel(mags)
        mag = mags(mm);
        idxM = find(isChg & abs([trials.changeMagnitudeDeg] - mag) < 1e-9);
        for q = 1:4
            idx = idxM([trials(idxM).changeQuad] == q);
            n = numel(idx);
            if n == 0, continue; end

            reps = floor(n / numel(allowedOri));
            rem  = n - reps * numel(allowedOri);

            v = repmat(allowedOri, 1, reps);
            if rem > 0
                v = [v allowedOri(randperm(numel(allowedOri), rem))];
            end
            v = v(randperm(numel(v)));

            for k = 1:n
                trials(idx(k)).changeStartOri = v(k);
            end
        end
    end
end

function oriS1 = makeOriS1_noPostChangeDup(changeQuad, startOri, allowedOri, changeAngleDeg)

    if nargin < 4 || isempty(changeAngleDeg) || ~isfinite(changeAngleDeg)
        changeAngleDeg = 90;
    end

    allowedOri = allowedOri(:)';  % row vector

    % Pick/snap startOri safely
    if isempty(startOri) || ~isfinite(startOri)
        startOri = allowedOri(randi(numel(allowedOri)));
    else
        % Snap to nearest allowed value (helps with float weirdness)
        [~, idx] = min(abs(allowedOri - startOri));
        startOri = allowedOri(idx);
    end

    changedOri = mod(startOri + changeAngleDeg, 180);

    % Exclude BOTH the start orientation and the post-change orientation
    tol = 1e-6;
    keep = ~ismembertol(allowedOri, [startOri changedOri], tol);
    rem = allowedOri(keep);

    if numel(rem) < 3
        error('Need at least 5 allowed orientations to avoid duplicates after change.');
    end

    rem = rem(randperm(numel(rem), 3));

    oriS1 = nan(4,1);
    oriS1(changeQuad) = startOri;

    otherIdx = setdiff(1:4, changeQuad);
    oriS1(otherIdx) = rem(:);
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end

function r = safeRate(num, den)
    if den <= 0
        r = NaN;
    else
        r = num / den;
    end
end
