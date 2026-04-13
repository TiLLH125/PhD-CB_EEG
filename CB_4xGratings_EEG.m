%% One-Shot Change Blindness (4 gratings) + Dual Interleaved Palamedes (AMRF/QUEST-like) Calibration + PAS First in Q1
% - 2x2 grid of gratings
% - One-shot: Fix -> S1 -> ISI -> S2 -> Gap -> Q1(PAS) -> Q2(Localise) -> ITI
% - NEW QUESTION FLOW
% - Q1: PAS clarity (1-4) asked every trial
% - Detection defined as PAS > 1
% - Q2: 4AFC Localise (1-4) asked every trial (even if PAS = 1)
% - Two interleaved Palamedes running-fit staircases controlling stimulus duration (frames):
%       A targets ~50% "detection" rate on change trials (PAS > 1)
%       B targets ~70% "seeing" rate on change trials: (PAS > 1 | Q2 correct)



function CB_4xGratings_EEG

close all;

% ---- HARD RESET keyboard state BEFORE ANY PTB keyboard queues ----
% Prevents: "KbQueueCreate ... already in use by GetChar() et al."
try ListenChar(0); catch, end
try KbQueueRelease(-1); catch, end

% ---- Safer "close screens" (in case sca isn't on path temporarily)
if exist('sca','file') == 2
    sca;
elseif exist('Screen','file') == 2
    Screen('CloseAll');
end

%% ------------------------- USER CONFIG -------------------------
cfg = struct();

cfg.participantID = input('Enter Participant ID (e.g., S001): ', 's');
if isempty(cfg.participantID), cfg.participantID = 'UNKNOWN'; end

cfg.debugWindow      = false;     % smaller window
cfg.visualDebugLevel = 1;
cfg.skipSyncTests    = 1;         % 1 while debugging; use 0 for real data

% Screen selection (don't use 0 unless you WANT desktop-spanning)
% cfg.screenNumber = max(Screen('Screens'));
cfg.screenNumber = 2;

% Keyboard device: -1 = default keyboard
cfg.kbDev = -1;

% ---- Display profile ----
% Options: 'viewpixx' (lab monitor), 'default' (general monitor fallback)
cfg.displayProfile = 'viewpixx';
cfg.display = makeDisplayProfile(cfg.displayProfile);

% ---- Practice flow ----
cfg.practice.enable = true;

% Global practice settings
cfg.practice.feedbackWaitForSpace = true;   % lock feedback until SPACE
cfg.practice.maxRepeatsBlock1     = 2;      % for later (Phase D)
cfg.practice.logToCommandWindow   = true;

% ---------- Practice Block 1 (with feedback; wider range / anchoring) ----------
cfg.practice1.enable    = true;
cfg.practice1.name      = 'Practice Block 1';
cfg.practice1.feedback  = true;

% Trial composition (20 total; tweak as needed)
cfg.practice1.nSTD      = 10;   % standard change trials
cfg.practice1.nNCH      = 5;    % no-change trials (liberal catch)
cfg.practice1.nEASY     = 5;    % obvious change trials (conservative catch)
cfg.practice1.nTrials   = cfg.practice1.nSTD + cfg.practice1.nNCH + cfg.practice1.nEASY;

% Durations (frames) by trial type
cfg.practice1.durSTDFrames  = 20;   % standard / moderate
cfg.practice1.durEASYFrames = 30;   % obvious / easy anchor
cfg.practice1.durNCHFrames  = 20;   % no-change trial still has S1/S2 duration

% Optional: restrict "easy" changes to stronger/more obvious starts later if needed
cfg.practice1.easyUsesSameChangeRule = true;

% ---------- Practice Block 2 (reduced/no feedback; closer to calibration) ----------
cfg.practice2.enable    = true;
cfg.practice2.name      = 'Practice Block 2';
cfg.practice2.feedback  = false;

% Trial composition (placeholder for now)
cfg.practice2.nSTD      = 12;
cfg.practice2.nNCH      = 6;
cfg.practice2.nEASY     = 6;
cfg.practice2.nTrials   = cfg.practice2.nSTD + cfg.practice2.nNCH + cfg.practice2.nEASY;

% Base durations (used when tiered assignment is disabled)
cfg.practice2.durSTDFrames  = 20;
cfg.practice2.durEASYFrames = 30;
cfg.practice2.durNCHFrames  = 20;

% Tiered duration spread for Block 2 (balanced: 8 short / 8 medium / 8 long)
cfg.practice2.useTieredDurations = true;
cfg.practice2.durShortFrames     = 10;
cfg.practice2.durMediumFrames    = 20;
cfg.practice2.durLongFrames      = 30;
cfg.practice2.tierCounts.short   = 8;
cfg.practice2.tierCounts.medium  = 8;
cfg.practice2.tierCounts.long    = 8;

cfg.practice2.easyUsesSameChangeRule = true;

% ---------- Practice classification criteria ----------
cfg.practice1Criteria.maxFARateNCH   = 0.60;
cfg.practice1Criteria.minEasyDetect  = 0.60;
cfg.practice1Criteria.minEasySee     = 0.40;

% ---- Staircase convergence / freeze rules ----
cfg.calib.minUpdatesPerStair = 40;     % minimum change-trial updates per staircase
cfg.calib.stabilityWindow    = 12;     % how many recent xCurrent values to check
cfg.calib.stabilityTolFrames = 1.0;    % max range in that window (frames)
cfg.calib.maxTrials          = 600;    % full run total trials
cfg.calib.saveNRecentMedian  = 10;     % final estimate = median of last N xCurrents

% Trial counts
cfg.debug.trialLog = true;
cfg.nTotal = cfg.calib.maxTrials;
cfg.trialDial.pChange = 0.75; 
cfg.debug.trialLog   = true;
cfg.debug.logHeaderEachBlock = true;

% Apply the dial
cfg = applyTrialDial(cfg);
cfg.trialsPerBlock = 50;
cfg.nBlocks = ceil(cfg.nTotal / cfg.trialsPerBlock);
cfg.trialDial.applyPerBlock = true;
cfg.trialDial.nChangePerBlock = round(cfg.trialsPerBlock * cfg.trialDial.pChange);
assert(mod(cfg.nTotal, cfg.trialsPerBlock) == 0, 'nTotal must be divisible by trialsPerBlock');

% Staircase split (tether catch trials to either A or B)
cfg.nChangeA = cfg.nChange/2;  % 150
cfg.nChangeB = cfg.nChange/2;  % 150
cfg.nCatchA  = cfg.nCatch/2;   % 175
cfg.nCatchB  = cfg.nCatch/2;   % 175
assert(mod(cfg.nChangeA,1)==0 && mod(cfg.nCatchA,1)==0, 'Need even split for A/B');

% Targets
cfg.targetDetectHit = 0.50;   % staircase A: hit rate on change trials
cfg.targetSeeing    = 0.70;   % staircase B: (detect YES & localise correct) on change trials

% Timing (seconds)
cfg.fixJitterRangeSec = [1.00 1.50];  % fixation before S1
% cfg.ISI_sec           = 0.10;         % between S1 and S2 (fixation on grey)
cfg.postS2Gap_sec     = 0.20;         % gap between S2 and Q1
cfg.ITI_sec           = 1.00;         % after PAS response
cfg.maxRespSec        = 30.00;         % failsafe

% Duration staircase bounds (FRAMES; converted using ifi)
cfg.minDurFrames   = 1;
cfg.maxDurFrames   = 100;
cfg.startDurFrames = 30;

% Grating/mask appearance (visual-angle locked; converted to px at runtime)
cfg.stim.squareSizeDeg  = 6.9;
cfg.stim.spacingDeg     = 3.4;
cfg.stim.cyclesPerStim  = 10;
cfg.stim.contrast       = 0.8;
cfg.stim.backgroundGrey = 0.5;
cfg.stim.gaborSigmaFrac = 0.40;
cfg.stim.allowedOri = 0:22.5:157.5;

% Fixation (visual-angle locked; converted to px at runtime)
cfg.fix.sizeDeg      = 0.37;
cfg.fix.lineWidthDeg = 0.08;

% ---- EEG serial trigger settings ----
cfg.eeg.enable            = false;
cfg.eeg.serialPort        = 'COM3';
cfg.eeg.baudRate          = 115200;
cfg.eeg.pulseWidthSec     = 0.005;
cfg.eeg.sendResetAfterCode = true;
cfg.eeg.warnOnSendError   = true;

cfg.eeg.codes = struct();
cfg.eeg.codes.trialStart = 11;
cfg.eeg.codes.s1On       = 21;
cfg.eeg.codes.isiOn      = 22;
cfg.eeg.codes.s2On       = 23;
cfg.eeg.codes.q1On       = 31;
cfg.eeg.codes.pasBase    = 40; % sent as pasBase + PAS digit (1..4)
cfg.eeg.codes.q2On       = 32;
cfg.eeg.codes.locBase    = 50; % sent as locBase + localisation digit (1..4)
cfg.eeg.codes.trialEnd   = 12;
cfg.eeg.codes.aux = struct( ...
    'instrGrey', 80, ...
    'instrActive', 81, ...
    'instrSpace', 82, ...
    'overviewGrey', 83, ...
    'overviewActive', 84, ...
    'overviewSpace', 85, ...
    'practice1Grey', 86, ...
    'practice1Active', 87, ...
    'practice1Space', 88, ...
    'practice2Grey', 89, ...
    'practice2Active', 90, ...
    'practice2Space', 91, ...
    'calibIntroGrey', 92, ...
    'calibIntroActive', 93, ...
    'calibIntroSpace', 94);
cfg.eeg.codes.practice = struct( ...
    'trialStart', cfg.eeg.codes.trialStart, ...
    's1On', cfg.eeg.codes.s1On, ...
    'isiOn', cfg.eeg.codes.isiOn, ...
    's2On', cfg.eeg.codes.s2On, ...
    'q1On', cfg.eeg.codes.q1On, ...
    'pasBase', cfg.eeg.codes.pasBase, ...
    'q2On', cfg.eeg.codes.q2On, ...
    'locBase', cfg.eeg.codes.locBase, ...
    'trialEnd', cfg.eeg.codes.trialEnd);
cfg.eeg.markerPolicy = struct( ...
    'markAuxScreens', true, ...
    'markPracticeTrials', true, ...
    'echoPasLocPixel', true, ...
    'echoAuxSpacePixel', true, ...
    'alignTrialStartSerialToFixationFlip', true, ...
    'alignTrialEndToItiOnset', true, ...
    'echoPulseSec', 0.05);

% ---- ViewPixx Pixel Mode (optional; parallel trigger path via video pixel) ----
% Set cfg.viewpixx.pixelModeEnable = true on the ViewPixx stimulus PC to mirror
% marker bytes on the top-left pixel (R = code/255, PsychDefaultSetup(2) norm).
% Requires USB control to VPixx (Datapixx IsReady). If init fails, the run
% continues with serial triggers only. markerPolicy controls whether auxiliary
% screens and practice emit markers and whether PAS/localisation add short
% echo flips for pixel parity. minRNorm can floor pixel R for visibility;
% serial always sends the true byte value.
cfg.viewpixx = struct( ...
    'pixelModeEnable', true, ...
    'pixelPos', [0 0], ...
    'pixelSize', 1, ...
    'minRNorm', 19/255, ...
    'datapixxOpen', false, ...
    'pixelModeEnabled', false);

%% ------------------------- DEPENDENCY CHECKS -------------------------
KbName('UnifyKeyNames');

if exist('PAL_AMRF_setupRF','file') ~= 2 || exist('PAL_AMRF_updateRF','file') ~= 2
    error('Palamedes not found on path. Add Palamedes core folder to MATLAB path first.');
end

try
    PsychDefaultSetup(2);
catch
    error('Psychtoolbox not found. Install Psychtoolbox-3 first.');
end

% Keys
cfg.keys.escape = KbName('ESCAPE');
cfg.keys.space  = KbName('space');
cfg.keys.quad   = [KbName('1!') KbName('2@') KbName('3#') KbName('4$')]; 
cfg.keys.pas    = [KbName('1!') KbName('2@') KbName('3#') KbName('4$')];
            

%% ------------------------- SETUP PTB -------------------------
Screen('Preference','VisualDebugLevel', cfg.visualDebugLevel);
Screen('Preference','SkipSyncTests', cfg.skipSyncTests);

bg    = cfg.stim.backgroundGrey;   % <-- define BEFORE OpenWindow
black = 0;

window = [];

%% ------------ FAILSAFE LOGGING ------------ %%
outDir = fullfile(pwd, 'data');
if ~exist(outDir,'dir'), mkdir(outDir); end
timestamp = datestr(now,'yyyymmdd_HHMMSS');
outFile = fullfile(outDir, sprintf('CB_4xGratings_%s_FullRun_%s.csv', cfg.participantID, timestamp));

try
    cfg.trigger = initSerialTrigger(cfg.eeg);

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

    cfg = viewpixxInitPixelMode(cfg);

    ifi = Screen('GetFlipInterval', window);
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
    cfg.ISI_frames      = 9;                  % fixed globally for practice + main
    % cfg.ISI_sec         = cfg.ISI_frames*ifi; % keep cfg.ISI_sec consistent for logging
    cfg.gap_frames      = max(0, round(cfg.postS2Gap_sec / ifi));
    cfg.ITI_frames      = max(0, round(cfg.ITI_sec / ifi));
    cfg.fixJitterFrames = round(cfg.fixJitterRangeSec / ifi);

    Priority(0);
    HideCursor;

    ListenChar(0);

    try KbQueueRelease(cfg.kbDev); catch, end
    KbQueueCreate(cfg.kbDev);
    KbQueueStart(cfg.kbDev);
    KbQueueFlush(cfg.kbDev);

    %% ------------------------- BUILD STAIRCASES ----------------------------
    alphaRange = cfg.minDurFrames:1:cfg.maxDurFrames;
    
    % Fixed PF parameters (AMRF passes alpha only to PF)
    betaA   = 2;
    gammaA  = 0.0;
    lambdaA = 0.02;
    
    betaB   = 2;
    gammaB  = 0.0;   
    lambdaB = 0.02;
    
    RF_A = PAL_AMRF_setupRF();
    RF_A = PAL_AMRF_setupRF(RF_A, ...
        'priorAlphaRange', alphaRange, ...
        'beta', betaA, ...
        'gamma', gammaA, ...
        'lambda', lambdaA, ...
        'PF', @(params,x) PF_TargetLogisticAlpha(params, x, cfg.targetDetectHit, betaA, gammaA, lambdaA), ...
        'meanmode', 'mean', ...
        'xMin', cfg.minDurFrames, ...
        'xMax', cfg.maxDurFrames);
    
    RF_B = PAL_AMRF_setupRF();
    RF_B = PAL_AMRF_setupRF(RF_B, ...
        'priorAlphaRange', alphaRange, ...
        'beta', betaB, ...
        'gamma', gammaB, ...
        'lambda', lambdaB, ...
        'PF', @(params,x) PF_TargetLogisticAlpha(params, x, cfg.targetSeeing, betaB, gammaB, lambdaB), ...
        'meanmode', 'mean', ...
        'xMin', cfg.minDurFrames, ...
        'xMax', cfg.maxDurFrames);
    
    % Your Palamedes build ignores 'startValue', so set xCurrent manually:
    RF_A.xCurrent = cfg.startDurFrames;
    RF_B.xCurrent = cfg.startDurFrames;
    

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

    %% ------------------------- TRIAL LIST ----------------------------------
    trials = buildTrialList(cfg);

    for b = 1:cfg.nBlocks
        ii = (b-1)*cfg.trialsPerBlock + (1:cfg.trialsPerBlock);
        nC  = sum([trials(ii).isChange] == 1);
        nNC = sum([trials(ii).isChange] == 0);
        fprintf('Block %02d: C=%d  NC=%d\n', b, nC, nNC);
    end

    %% ------------------------- INSTRUCTIONS SCREEN -------------------------

    showInstructionScreen(window, windowRect, bg, black, cfg);

    %% ------------------------- TRIAL OVERVIEW SCREEN -----------------------

    cfg.trialOverviewPNG = fullfile(pwd,'Gratings_TrialOverview.png');

    showTrialOverviewScreen(window, windowRect, bg, black, cfg);

    %% ------------------------- PRACTICE ENTRY SCREEN -----------------------

    showPractice1Intro(window, windowRect, bg, black, cfg);

    %% ------------------------- PRACTICE FLOW (LINEAR) -----------------------------
    practiceFlow = struct();
    practiceFlow.block1 = struct('summary', struct(), 'result', 'not_run');
    practiceFlow.block2 = struct('summary', struct(), 'result', 'not_run');

    if isfield(cfg,'practice') && cfg.practice.enable
        if isfield(cfg,'practice1') && cfg.practice1.enable
            practice1Summary = runPracticeBlock(window, windowRect, gratingTex, allRects, fixationCoords, ...
                xCentre, yCentre, ifi, cfg, bg, black, cfg.practice1);
            printPracticeSummary(practice1Summary, 'Practice Block 1');
            practiceFlow.block1.summary = practice1Summary;
            practiceFlow.block1.result  = 'completed';
        end

        if isfield(cfg,'practice2') && cfg.practice2.enable
            showPractice2Intro(window, windowRect, bg, black, cfg);
            practice2Summary = runPracticeBlock(window, windowRect, gratingTex, allRects, fixationCoords, ...
                xCentre, yCentre, ifi, cfg, bg, black, cfg.practice2);
            printPracticeSummary(practice2Summary, 'Practice Block 2');
            practiceFlow.block2.summary = practice2Summary;
            practiceFlow.block2.result  = 'completed';
        end
    end

    practiceRow = struct();

    practiceRow.participantID = string(cfg.participantID);
    practiceRow.timestamp     = string(timestamp);
    
    % Block 1 summary
    practiceRow.b1_result            = string(practiceFlow.block1.result);
    practiceRow.b1_nTrials           = getFieldOrNaN(practiceFlow.block1.summary, 'nTrials');
    practiceRow.b1_faRateNCH         = getFieldOrNaN(practiceFlow.block1.summary, 'faRateNCH');
    practiceRow.b1_easyDetect        = getFieldOrNaN(practiceFlow.block1.summary, 'easyDetectRate');
    practiceRow.b1_easySee           = getFieldOrNaN(practiceFlow.block1.summary, 'easySeeRate');
    practiceRow.b1_changeDetect      = getFieldOrNaN(practiceFlow.block1.summary, 'changeDetectRate');
    practiceRow.b1_changeSee         = getFieldOrNaN(practiceFlow.block1.summary, 'changeSeeRate');
    
    % Block 2 summary
    practiceRow.b2_result            = string(practiceFlow.block2.result);
    practiceRow.b2_nTrials           = getFieldOrNaN(practiceFlow.block2.summary, 'nTrials');
    practiceRow.b2_faRateNCH         = getFieldOrNaN(practiceFlow.block2.summary, 'faRateNCH');
    practiceRow.b2_easyDetect        = getFieldOrNaN(practiceFlow.block2.summary, 'easyDetectRate');
    practiceRow.b2_easySee           = getFieldOrNaN(practiceFlow.block2.summary, 'easySeeRate');
    practiceRow.b2_changeDetect      = getFieldOrNaN(practiceFlow.block2.summary, 'changeDetectRate');
    practiceRow.b2_changeSee         = getFieldOrNaN(practiceFlow.block2.summary, 'changeSeeRate');
    
    practiceTable = struct2table(practiceRow);
    
    practiceFileCSV = fullfile(outDir, sprintf('CB_4xGratings_%s_PracticeFlow_%s.csv', cfg.participantID, timestamp));
    writetable(practiceTable, practiceFileCSV);
    fprintf('Saved practice flow CSV: %s\n', practiceFileCSV);
    practiceFileMAT = fullfile(outDir, sprintf('CB_4xGratings_%s_PracticeFlow_%s.mat', cfg.participantID, timestamp));
    save(practiceFileMAT, 'practiceFlow', 'practiceRow');
    fprintf('Saved practice flow MAT: %s\n', practiceFileMAT);

    %% ------------------------- CALIBRATION ENTRY SCREEN --------------------

    showCalibrationIntroScreen(window, windowRect, bg, black, cfg);

    %% ------------------------- RUN CALIBRATION -----------------------------
    results = repmat(emptyResultRow(), cfg.nTotal, 1);

    % --- calibration trackers ---
    nUpdA = 0; nUpdB = 0;
    histXA = []; histXB = [];
    convA = false; convB = false;
    freezeA = false; freezeB = false;
    freezeAFrames = NaN; freezeBFrames = NaN;


    for t = 1:cfg.nTotal
        checkAbort(cfg);

        % Block breaks
        if mod(t-1, cfg.trialsPerBlock) == 0
            blockNum = (t-1)/cfg.trialsPerBlock + 1;

            blockMsg = sprintf('Block %d of %d\n\nPress SPACEBAR to start.\n', blockNum, cfg.nBlocks);
            Screen('FillRect', window, bg);
            DrawFormattedText(window, blockMsg, 'center', 'center', black);
            drawViewPixxPixelIfNeeded(window, cfg, 0);
            Screen('Flip', window);

            waitForKeyQueue([cfg.keys.space], cfg.keys.escape, Inf, cfg);
        end

        trial = trials(t);
        if ~cfg.eeg.markerPolicy.alignTrialStartSerialToFixationFlip
            sendTrigger(cfg.trigger, cfg.eeg.codes.trialStart);
        end

        % Pick current duration from assigned staircase (tether catch trials too)
        if trial.staircase == 'A'
            if freezeA
                durFrames = freezeAFrames;
            else
                durFrames = clamp(round(RF_A.xCurrent), cfg.minDurFrames, cfg.maxDurFrames);
            end
        else
            if freezeB
                durFrames = freezeBFrames;
            else
                durFrames = clamp(round(RF_B.xCurrent), cfg.minDurFrames, cfg.maxDurFrames);
            end
        end

        % Build S1
        allowedOri = cfg.stim.allowedOri;
    
        if trial.isChange
            oriS1 = makeOriS1_noPostChangeDup(trial.changeQuad, trial.changeStartOri, allowedOri);
        else
            oriS1 = allowedOri(randperm(numel(allowedOri), 4))';
        end
        
        oriS2 = oriS1;
        if trial.isChange
            oriS2(trial.changeQuad) = mod(oriS1(trial.changeQuad) + 90, 180);
        end

        % ---------------- TIMELINE (ESC checked during each hold) ----------------
        % Fixation jitter
        jitterFrames = randi([cfg.fixJitterFrames(1), cfg.fixJitterFrames(2)], 1, 1);
        drawFixationOnly(window, bg, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
        drawViewPixxPixelIfNeeded(window, cfg, cfg.eeg.codes.trialStart);
        tFixOn = Screen('Flip', window);
        if cfg.eeg.markerPolicy.alignTrialStartSerialToFixationFlip
            sendTrigger(cfg.trigger, cfg.eeg.codes.trialStart);
        end
        tTrialStart = tFixOn;
        holdForSecondsWithAbort(tFixOn + jitterFrames*ifi, cfg);

        % S1
        drawGratings(window, gratingTex, allRects, oriS1, bg);
        drawFixation(window, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
        drawViewPixxPixelIfNeeded(window, cfg, cfg.eeg.codes.s1On);
        tS1 = Screen('Flip', window);
        sendTrigger(cfg.trigger, cfg.eeg.codes.s1On);
        holdForSecondsWithAbort(tS1 + durFrames*ifi, cfg);

        % ISI
        drawFixationOnly(window, bg, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
       %drawMaskFixationOnly(window, bg, maskRect, cfg.stim.maskGrey, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
        drawViewPixxPixelIfNeeded(window, cfg, cfg.eeg.codes.isiOn);
        tISI = Screen('Flip', window);
        sendTrigger(cfg.trigger, cfg.eeg.codes.isiOn);
        holdForSecondsWithAbort(tISI + cfg.ISI_frames*ifi, cfg);

        % S2
        drawGratings(window, gratingTex, allRects, oriS2, bg);
        drawFixation(window, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
        drawViewPixxPixelIfNeeded(window, cfg, cfg.eeg.codes.s2On);
        tS2 = Screen('Flip', window);
        sendTrigger(cfg.trigger, cfg.eeg.codes.s2On);
        holdForSecondsWithAbort(tS2 + durFrames*ifi, cfg);

        % Gap
        drawFixationOnly(window, bg, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
        drawViewPixxPixelIfNeeded(window, cfg, 0);
        tGap = Screen('Flip', window);
        holdForSecondsWithAbort(tGap + cfg.gap_frames*ifi, cfg);

        % ---------------- QUESTIONS ----------------
        % Q1 (PAS) — detection is defined as PAS > 1
        drawPAS(window, windowRect, black, bg, cfg);
        drawViewPixxPixelIfNeeded(window, cfg, cfg.eeg.codes.q1On);
        tQ1 = Screen('Flip', window);
        sendTrigger(cfg.trigger, cfg.eeg.codes.q1On);
        
        [pasKey, pasTime] = waitForKeyQueue(cfg.keys.pas, cfg.keys.escape, cfg.maxRespSec, cfg);
        pasRT = pasTime - tQ1;
        pas   = keyToDigit(pasKey);
        if ~isnan(pas) && pas >= 1 && pas <= 4
            sendTrigger(cfg.trigger, cfg.eeg.codes.pasBase + pas);
            if cfg.eeg.markerPolicy.echoPasLocPixel
                parallelEchoFlip(window, cfg, cfg.eeg.codes.pasBase + pas, ...
                    xCentre, yCentre, fixationCoords, cfg.fix.lineWidthPx, black, bg, cfg.eeg.markerPolicy.echoPulseSec);
            end
        end
        
        % Define "detection" from PAS
        hit = double(~isnan(pas) && pas > 1);

        % Decide Q2 prompt based on PAS
        if ~isnan(pas) && pas == 1
            q2Prompt = 'Select a quadrant, even if you experienced no change.';
        else
            q2Prompt = 'Where was the change?';
        end
                
        % Q2 (Localise) — ALWAYS ask (even if PAS == 1)
        drawQuadrantPrompt(window, windowRect, black, bg, q2Prompt, cfg);
        drawViewPixxPixelIfNeeded(window, cfg, cfg.eeg.codes.q2On);
        tQ2 = Screen('Flip', window);
        sendTrigger(cfg.trigger, cfg.eeg.codes.q2On);
        
        [resp2Key, resp2Time] = waitForKeyQueue(cfg.keys.quad, cfg.keys.escape, cfg.maxRespSec, cfg);
        resp2RT = resp2Time - tQ2;
        resp2   = keyToDigit(resp2Key);
        if ~isnan(resp2) && resp2 >= 1 && resp2 <= 4
            sendTrigger(cfg.trigger, cfg.eeg.codes.locBase + resp2);
            if cfg.eeg.markerPolicy.echoPasLocPixel
                parallelEchoFlip(window, cfg, cfg.eeg.codes.locBase + resp2, ...
                    xCentre, yCentre, fixationCoords, cfg.fix.lineWidthPx, black, bg, cfg.eeg.markerPolicy.echoPulseSec);
            end
        end
        
        % Localisation correctness (only meaningful on change trials)
        if trial.isChange
            if isnan(resp2)
                locCorrect = 0; % timeout/missing localisation = incorrect
            else
                locCorrect = double(resp2 == trial.changeQuad);
            end
        else
            locCorrect = NaN; % no-change trials: not defined
        end

        tTrialEnd = resp2Time;
        trialTotalSec = tTrialEnd - tTrialStart;

        % ITI
        % drawFixationOnly(window, bg, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
        Screen('FillRect', window, bg);
        if cfg.eeg.markerPolicy.alignTrialEndToItiOnset
            itiCode = cfg.eeg.codes.trialEnd;
        else
            itiCode = 0;
        end
        drawViewPixxPixelIfNeeded(window, cfg, itiCode);
        tITI = Screen('Flip', window);
        if cfg.eeg.markerPolicy.alignTrialEndToItiOnset
            sendTrigger(cfg.trigger, cfg.eeg.codes.trialEnd);
        end
        holdForSecondsWithAbort(tITI + cfg.ITI_frames*ifi, cfg);

        % ---------------- STAIRCASE UPDATES (CHANGE trials only) ----------------
        if trial.isChange
            if trial.staircase == 'A'
                if ~freezeA
                    RF_A = PAL_AMRF_updateRF(RF_A, durFrames, double(hit));
                    nUpdA = nUpdA + 1;
                    histXA(end+1) = RF_A.xCurrent;
            
                    % convergence check for A
                    if nUpdA >= cfg.calib.minUpdatesPerStair && numel(histXA) >= cfg.calib.stabilityWindow
                        w = histXA(end-cfg.calib.stabilityWindow+1:end);
                        convA = (max(w) - min(w)) <= cfg.calib.stabilityTolFrames;
                        if convA
                            freezeA = true;
                            freezeAFrames = clamp(round(RF_A.xCurrent), cfg.minDurFrames, cfg.maxDurFrames);
                            fprintf('Staircase A froze at trial %d: %d frames (%.3f s)\n', t, freezeAFrames, freezeAFrames * ifi);
                        end
                    end
                end
        
            else
                % B staircase: localisation accuracy conditional on hit (PAS > 1)
                if hit == 1 && ~freezeB
                    respB = double(locCorrect == 1);   % 1 = correct localisation, 0 = incorrect
                    RF_B  = PAL_AMRF_updateRF(RF_B, durFrames, respB);
            
                    nUpdB = nUpdB + 1;
                    histXB(end+1) = RF_B.xCurrent;
            
                    % convergence check for B
                    if nUpdB >= cfg.calib.minUpdatesPerStair && numel(histXB) >= cfg.calib.stabilityWindow
                        w = histXB(end-cfg.calib.stabilityWindow+1:end);
                        convB = (max(w) - min(w)) <= cfg.calib.stabilityTolFrames;
                        if convB
                            freezeB = true;
                            freezeBFrames = clamp(round(RF_B.xCurrent), cfg.minDurFrames, cfg.maxDurFrames);
                            fprintf('Staircase B froze at trial %d: %d frames (%.3f s)\n', t, freezeBFrames, freezeBFrames * ifi);
                        end
                    end
                end
            end

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

        results(t).oriS1 = sprintf('%.1f,%.1f,%.1f,%.1f', oriS1(1),oriS1(2),oriS1(3),oriS1(4));
        results(t).oriS2 = sprintf('%.1f,%.1f,%.1f,%.1f', oriS2(1),oriS2(2),oriS2(3),oriS2(4));

        results(t).tS1 = tS1;
        results(t).tISI = tISI;
        results(t).tS2 = tS2;
        results(t).tQ1 = tQ1;
        results(t).tQ2 = tQ2;

        results(t).resp2 = resp2;
        results(t).resp2RT = resp2RT;

        results(t).pas = pas;
        results(t).pasRT = pasRT;
        results(t).tTrialStart   = tTrialStart;
        results(t).tTrialEnd     = tTrialEnd;
        results(t).trialTotalSec = trialTotalSec;


        results(t).hit = double(hit);
        results(t).locCorrect = locCorrect;

        results(t).RF_A_xCurrent = RF_A.xCurrent;
        results(t).RF_B_xCurrent = RF_B.xCurrent;
        results(t).freezeA = freezeA;
        results(t).freezeB = freezeB;
        results(t).freezeAFrames = freezeAFrames;
        results(t).freezeBFrames = freezeBFrames;
        results(t).triggerEnabled = double(cfg.trigger.enabled);
        results(t).trigTrialStartCode = cfg.eeg.codes.trialStart;
        results(t).trigS1Code = cfg.eeg.codes.s1On;
        results(t).trigISICode = cfg.eeg.codes.isiOn;
        results(t).trigS2Code = cfg.eeg.codes.s2On;
        results(t).trigQ1Code = cfg.eeg.codes.q1On;
        results(t).trigPASCode = ternary(isnan(pas), NaN, cfg.eeg.codes.pasBase + pas);
        results(t).trigQ2Code = cfg.eeg.codes.q2On;
        results(t).trigLocCode = ternary(isnan(resp2), NaN, cfg.eeg.codes.locBase + resp2);
        results(t).trigTrialEndCode = cfg.eeg.codes.trialEnd;

        trialLogLine(t, cfg, trial, durFrames, resp2, hit, locCorrect, pas, RF_A, RF_B, nUpdA, nUpdB, convA, convB);
        if ~cfg.eeg.markerPolicy.alignTrialEndToItiOnset
            sendTrigger(cfg.trigger, cfg.eeg.codes.trialEnd);
        end

        % End-of-block
        if mod(t, cfg.trialsPerBlock) == 0

            checkpointSave(results, t, outFile);

            if t < cfg.nTotal
                Screen('FillRect', window, bg);
                DrawFormattedText(window, 'Take a break.\n\nPress SPACEBAR to continue.', 'center', 'center', black);
                drawViewPixxPixelIfNeeded(window, cfg, 0);
                Screen('Flip', window);
                waitForKeyQueue([cfg.keys.space], cfg.keys.escape, Inf, cfg);
            end
        end
    end

    %% ------------ FINAL THRESHOLD ESTIMATES -----------------
    if isempty(histXA)
        A_startFrames = cfg.startDurFrames;
    else
        NA = min(cfg.calib.saveNRecentMedian, numel(histXA));
        A_startFrames = round(median(histXA(end-NA+1:end)));
    end
    
    if isempty(histXB)
        B_startFrames = cfg.startDurFrames;
    else
        NB = min(cfg.calib.saveNRecentMedian, numel(histXB));
        B_startFrames = round(median(histXB(end-NB+1:end)));
    end
    
    A_startSec = A_startFrames * ifi;
    B_startSec = B_startFrames * ifi;

    
    fprintf('Run estimates: A=%d frames (%.3f s), B=%d frames (%.3f s)\n', ...
        A_startFrames, A_startSec, B_startFrames, B_startSec);


    %% ------------------------- SAVE -------------------------
    results = results(~cellfun(@isempty,{results.participantID}));

    T = struct2table(results);

    % --- Add final calibration summary values as columns (same value every row) ---
    T.calibTimestamp = repmat(string(timestamp), height(T), 1);
    
    T.A_startFrames  = repmat(A_startFrames, height(T), 1);
    T.B_startFrames  = repmat(B_startFrames, height(T), 1);
    T.A_startSec     = repmat(A_startSec,    height(T), 1);
    T.B_startSec     = repmat(B_startSec,    height(T), 1);
    
    T.nUpdA          = repmat(nUpdA, height(T), 1);
    T.nUpdB          = repmat(nUpdB, height(T), 1);
    T.convA          = repmat(convA, height(T), 1);
    T.convB          = repmat(convB, height(T), 1);
    T.freezeAFramesFinal = repmat(freezeAFrames, height(T), 1);
    T.freezeBFramesFinal = repmat(freezeBFrames, height(T), 1);

    T.viewpixxPixelModeEnabled = repmat(logical( ...
        isfield(cfg, 'viewpixx') && isfield(cfg.viewpixx, 'pixelModeEnabled') && cfg.viewpixx.pixelModeEnabled), height(T), 1);
    
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
    cal.participantID = cfg.participantID;
    cal.timestamp     = timestamp;
    cal.A_startFrames = A_startFrames;
    cal.B_startFrames = B_startFrames;
    cal.A_startSec    = A_startSec;
    cal.B_startSec    = B_startSec;
    cal.nUpdA         = nUpdA;
    cal.nUpdB         = nUpdB;
    cal.convA         = convA;
    cal.convB         = convB;
    cal.freezeAFrames = freezeAFrames;
    cal.freezeBFrames = freezeBFrames;
    
    calFile = fullfile(outDir, sprintf('CB_4xGratings_%s_FullRun_%s.mat', cfg.participantID, timestamp));
    save(calFile, 'cal');
    fprintf('Saved full-run MAT: %s\n', calFile);

    endText = sprintf('Done.\n\nSaved:\n%s\n\nPress any key to exit.', outFile);
    DrawFormattedText(window, endText, 'center', 'center', black, 90);
    Screen('Flip', window);
    KbStrokeWait;

catch ME
    try cleanup(window, cfg); catch, end

    rep = getReport(ME,'extended','hyperlinks','off');
    fprintf(2, '\n\n===== CB_Gratings ERROR =====\n%s\n', rep);

    fid = fopen(fullfile(pwd,'CB_last_error.txt'),'w');
    if fid > 0
        fprintf(fid, '%s\n', rep);
        fclose(fid);
    end

    if exist('results','var')
    last = find(~cellfun(@isempty,{results.participantID}), 1, 'last');
    if ~isempty(last)
        checkpointSave(results, last, outFile);
    end
    end

    rethrow(ME);
end
end

%% ========================= LOCAL FUNCTIONS =========================

function showInstructionScreen(window, windowRect, bg, black, cfg)

    % ---- Instruction text ----
    titleFirstInstructions = 'Change Blindness Task Instruction';
    FirstInstructions = [ ...
        'Welcome to this full experiment session.\n' ...
        'You will first complete practice, then continue into the main run.\n\n' ...
        'In the task you will see four circular gratings arranged in a 2 x 2 grid.\n' ...
        'Sometimes ONE grating will rotate from its original orientation.\n' ...
        'After each trial you will answer two questions about what you saw:\n\n' ...
        'Question 1 (PAS):\n' ...
        'How clearly did you experience a change?\n' ...
        '[1] = I didn''t experience a change,  [2] = I felt like there was a change,\n' ...
        '[3] = I saw something change,  [4] = I clearly saw the change\n\n' ...
        'Question 2:\n' ...
        'Where was the change?\n' ...
        '[1] = Top Left,  [2] = Top Right,\n' ...
        '[3] = Bottom Left,  [4] = Bottom Right\n\n' ...
        'Even if you choose ''[1] = I didn''t experience a change'' for Question 1, still pick a location for Question 2 to the best of your ability.\n\n' ...
    ];

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
    DrawFormattedText(window, FirstInstructions, 'center', bodyY, black, tcfg.bodyWrap, [], [], tcfg.bodyLineSpacing);
    Screen('TextSize', window, tcfg.promptSize);
    DrawFormattedText(window, 'Press SPACEBAR to continue.', 'center', promptY, greyText);

    tOn = emitAuxFlip(window, cfg, cfg.eeg.codes.aux.instrGrey);

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
    DrawFormattedText(window, FirstInstructions, 'center', bodyY, black, tcfg.bodyWrap, [], [], tcfg.bodyLineSpacing);
    Screen('TextSize', window, tcfg.promptSize);
    DrawFormattedText(window, 'Press SPACEBAR to continue.', 'center', promptY, black);

    emitAuxFlip(window, cfg, cfg.eeg.codes.aux.instrActive);

    KbQueueFlush(cfg.kbDev);
    waitForKeyQueue([cfg.keys.space], cfg.keys.escape, Inf, cfg);
    if cfg.eeg.markerPolicy.echoAuxSpacePixel
        emitAuxSpaceEcho(window, cfg, cfg.eeg.codes.aux.instrSpace, bg);
    end
end

function showTrialOverviewScreen(window, windowRect, bg, black, cfg)

    tcfg = cfg.display.text;
    lockSec  = tcfg.lockSec;
    greyText = tcfg.greyText;
    titleTrialOverview = 'Trial Overview';

    % --- Load PNG as texture ---
    pngPath = cfg.trialOverviewPNG;
    if ~exist(pngPath, 'file')
        error('Trial overview PNG not found: %s', pngPath);
    end

    [img, ~, alpha] = imread(pngPath);
    if ~isempty(alpha)
        img(:,:,4) = alpha;
    end
    tex = Screen('MakeTexture', window, img);

    KbQueueFlush(cfg.kbDev);

    % --- Text blocks (REMOVE the press-space line from bottomText) ---
    topText = [ ...
        'On each trial, the sequence will look like the example below.\n\n' ...
        'First, a fixation cross will appear in the centre.\n' ...
        'Next, you will see the four gratings, then a brief blank screen, then the four gratings again.\n' ...
        'Sometimes one grating will change orientation. Some trials will NOT contain a change.\n\n' ...
        'After the sequence, you will answer the same two questions described on the previous screen:\n' ...
        '1) PAS: clarity of change (1–4)\n' ...
        '2) Where was the change? (1–4) \n' ...
    ];

    bottomText = [ ...
        'We will begin with a short set of practice trials so you can get comfortable with the task.\n' ...
        'You will get feedback after each practice trial.\n\n' ...
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
    imgW = size(img,2);
    imgH = size(img,1);

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

    tOn = emitAuxFlip(window, cfg, cfg.eeg.codes.aux.overviewGrey);

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

    emitAuxFlip(window, cfg, cfg.eeg.codes.aux.overviewActive);

    KbQueueFlush(cfg.kbDev);
    waitForKeyQueue([cfg.keys.space], cfg.keys.escape, Inf, cfg);
    if cfg.eeg.markerPolicy.echoAuxSpacePixel
        emitAuxSpaceEcho(window, cfg, cfg.eeg.codes.aux.overviewSpace, bg);
    end

    % Cleanup texture
    Screen('Close', tex);
end

function showPractice1Intro(window, windowRect, bg, black, cfg)

    % --- Settings (match your other screens) ---
    tcfg = cfg.display.text;
    lockSec  = tcfg.lockSec;
    greyText = tcfg.greyText;
    promptY  = windowRect(4) * tcfg.promptYFrac;
    titlePractice1 = 'Practice Block #1\n\n';

    % --- Notice text (tight + readable) ---
    PracticeText1 = [ ...
        'Before we begin the practice trials, please keep this in mind:\n' ...
        'Some trials will contain a change, and some trials will NOT contain a change.\n\n' ...
        'Please use the full PAS scale when appropriate:\n' ...
        'Please use PAS 1 whenever you are guessing or unsure.\n' ...
        'Only choose PAS 2–4 when you genuinely experienced a change.\n\n' ...
        'This first practice block includes feedback after each trial.\n' ...
        'When you press SPACEBAR, the practice trials will begin.\n\n' ...
    ];

    % ---- PASS 1: greyed prompt (optional lockout) ----
    Screen('FillRect', window, bg);
    Screen('TextSize', window, tcfg.titleSize);
    Screen('TextStyle', window, 1);
    DrawFormattedText(window, titlePractice1, 'center', windowRect(4) * tcfg.practiceTitleY, black);
    Screen('TextStyle', window, 0);
    Screen('TextSize', window, tcfg.bodySize);
    DrawFormattedText(window, PracticeText1, 'center', windowRect(4) * tcfg.practiceBodyY, black, tcfg.bodyWrap, [], [], tcfg.bodyLineSpacing);
    Screen('TextSize', window, tcfg.promptSize);
    DrawFormattedText(window, 'Press SPACEBAR to begin practice.', 'center', promptY, greyText);

    tOn = emitAuxFlip(window, cfg, cfg.eeg.codes.aux.practice1Grey);

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
    DrawFormattedText(window, PracticeText1, 'center', windowRect(4) * tcfg.practiceBodyY, black, tcfg.bodyWrap, [], [], tcfg.bodyLineSpacing);
    Screen('TextSize', window, tcfg.promptSize);
    DrawFormattedText(window, 'Press SPACEBAR to begin practice.', 'center', promptY, black);
    emitAuxFlip(window, cfg, cfg.eeg.codes.aux.practice1Active);

    KbQueueFlush(cfg.kbDev);
    waitForKeyQueue([cfg.keys.space], cfg.keys.escape, Inf, cfg);
    if cfg.eeg.markerPolicy.echoAuxSpacePixel
        emitAuxSpaceEcho(window, cfg, cfg.eeg.codes.aux.practice1Space, bg);
    end
end

function checkAbort(cfg)
    [pressed, firstPress] = KbQueueCheck(cfg.kbDev);
    if pressed && firstPress(cfg.keys.escape) > 0
        error('Experiment terminated by user (ESC).');
    end
end

function showPractice2Intro(window, windowRect, bg, black, cfg)

    % --- Settings (match your other screens) ---
    tcfg = cfg.display.text;
    lockSec  = tcfg.lockSec;
    greyText = tcfg.greyText;
    promptY  = windowRect(4) * tcfg.promptYFrac;
    titlePractice2 = 'Practice Block #2';

    PracticeText2 = [ ...
        'Nice work!\n\n' ...
        'You will now complete a second lot of practice trials designed to feel more like the real task.\n\n' ...   
        'Remember that some trials will contain a change, and some trials will NOT contain a change.\n' ...
        'Use the full PAS scale when appropriate:\n' ...
        'Use PAS 1 whenever you are guessing or unsure.\n' ...
        'Only choose PAS 2 – 4 when you genuinely experienced a change.\n' ...
        'Feedback will be removed for this second block and there will be range of trial difficulties.\n' ...
        'When you press SPACEBAR, the practice trials will begin.' ...
    ];

    % ---- PASS 1: greyed prompt (optional lockout) ----
    Screen('FillRect', window, bg);
    Screen('TextSize', window, tcfg.titleSize);
    Screen('TextStyle', window, 1);
    DrawFormattedText(window, titlePractice2, 'center', windowRect(4) * tcfg.practiceTitleY, black);
    Screen('TextStyle', window, 0);
    Screen('TextSize', window, tcfg.bodySize);
    DrawFormattedText(window, PracticeText2, 'center', windowRect(4) * tcfg.practiceBodyY, black, tcfg.bodyWrap, [], [], tcfg.bodyLineSpacing);
    Screen('TextSize', window, tcfg.promptSize);
    DrawFormattedText(window, 'Press SPACEBAR to continue practice.', 'center', promptY, greyText);

    tOn = emitAuxFlip(window, cfg, cfg.eeg.codes.aux.practice2Grey);

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
    DrawFormattedText(window, PracticeText2, 'center', windowRect(4) * tcfg.practiceBodyY, black, tcfg.bodyWrap, [], [], tcfg.bodyLineSpacing);
    Screen('TextSize', window, tcfg.promptSize);
    DrawFormattedText(window, 'Press SPACEBAR to continue practice.', 'center', promptY, black);
    emitAuxFlip(window, cfg, cfg.eeg.codes.aux.practice2Active);

    KbQueueFlush(cfg.kbDev);
    waitForKeyQueue([cfg.keys.space], cfg.keys.escape, Inf, cfg);
    if cfg.eeg.markerPolicy.echoAuxSpacePixel
        emitAuxSpaceEcho(window, cfg, cfg.eeg.codes.aux.practice2Space, bg);
    end
end

function showCalibrationIntroScreen(window, windowRect, bg, black, cfg)

    % --- Settings (match your other screens) ---
    tcfg = cfg.display.text;
    lockSec  = tcfg.lockSec;
    greyText = tcfg.greyText;
    promptY  = windowRect(4) * tcfg.promptYFrac;
    titleMainExperiment = 'Main Experimental Trials';

    txt = [ ...
        'Well done! You''ve finished the practice trials.\n' ...
        'You will now begin the main experimental trial blocks.\n\n' ...
        'The task will continue throughout the full run with regular breaks for you to rest and refresh.\n' ...
        'You will NOT receive feedback during the main run.\n\n' ...
        'Remember that some trials will contain a change, and some trials will NOT contain a change.\n' ...
        'Use the full PAS scale when appropriate:\n' ...
        'Use PAS 1 whenever you are guessing or unsure.\n' ...
        'Only choose PAS 2 – 4 when you genuinely experienced a change.\n' ...
        'When you press SPACEBAR, the main run will begin.' ...
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
    DrawFormattedText(window, 'Press SPACEBAR to begin the main run.', 'center', promptY, greyText);

    tOn = emitAuxFlip(window, cfg, cfg.eeg.codes.aux.calibIntroGrey);

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
    DrawFormattedText(window, 'Press SPACEBAR to begin the main run.', 'center', promptY, black);
    emitAuxFlip(window, cfg, cfg.eeg.codes.aux.calibIntroActive);

    KbQueueFlush(cfg.kbDev);
    waitForKeyQueue([cfg.keys.space], cfg.keys.escape, Inf, cfg);
    if cfg.eeg.markerPolicy.echoAuxSpacePixel
        emitAuxSpaceEcho(window, cfg, cfg.eeg.codes.aux.calibIntroSpace, bg);
    end
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
    fprintf('FA(NCH)=%s | CR(NCH)=%s | EasyDetect=%s | EasySee=%s | ChangeDetect=%s | ChangeSee=%s\n', ...
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
                error('Experiment terminated by user (ESC).');
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

function y = PF_TargetLogisticAlpha(params, x, pTarget, beta, gamma, lambda)

    % Palamedes AMRF may pass params as a struct (often with field 'alpha')
    if isstruct(params)
        if isfield(params,'alpha')
            alpha = [params.alpha];          % works for scalar or struct-array
        elseif isfield(params,'threshold')
            alpha = [params.threshold];
        else
            error('PF_TargetLogisticAlpha: params struct has no alpha field.');
        end

        % If Palamedes also provides these in the struct, prefer them:
        if isfield(params,'beta'),   beta   = params(1).beta;   end
        if isfield(params,'gamma'),  gamma  = params(1).gamma;  end
        if isfield(params,'lambda'), lambda = params(1).lambda; end
    else
        % Fallback if params comes in numeric form
        alpha = params(1);
    end

    % Ensure numeric
    alpha  = double(alpha);
    x      = double(x);
    beta   = double(beta);
    gamma  = double(gamma);
    lambda = double(lambda);

    % Shift logistic so that y(alpha) == pTarget
    yScaled = (pTarget - gamma) / (1 - gamma - lambda);
    yScaled = min(max(yScaled, 1e-6), 1-1e-6);

    delta = -(1/beta) * log((1/yScaled) - 1);
    x0    = alpha - delta;

    y = gamma + (1 - gamma - lambda) ./ (1 + exp(-beta .* (x - x0)));
end

function pTrials = buildPracticeTrialList(pracCfg, allowedOri)

    % Trial template
    trialTemplate = struct( ...
        'trialType', '', ...          % 'STD' | 'NCH' | 'EASY'
        'isChange', false, ...
        'changeQuad', NaN, ...
        'changeStartOri', NaN, ...
        'staircase', 'P', ...
        'durFrames', NaN);

    nTotal = pracCfg.nTrials;
    pTrials = repmat(trialTemplate, nTotal, 1);

    k = 1;

    % ---------------- STD (standard change) ----------------
    nSTD = pracCfg.nSTD;
    stdQuads = makeBalancedQuads(nSTD);

    for i = 1:nSTD
        pTrials(k).trialType  = 'STD';
        pTrials(k).isChange   = true;
        pTrials(k).changeQuad = stdQuads(i);
        pTrials(k).durFrames  = pracCfg.durSTDFrames;
        k = k + 1;
    end

    % ---------------- NCH (no-change) ----------------
    nNCH = pracCfg.nNCH;
    for i = 1:nNCH
        pTrials(k).trialType  = 'NCH';
        pTrials(k).isChange   = false;
        pTrials(k).changeQuad = NaN;
        pTrials(k).durFrames  = pracCfg.durNCHFrames;
        k = k + 1;
    end

    % ---------------- EASY (obvious change) ----------------
    nEASY = pracCfg.nEASY;
    easyQuads = makeBalancedQuads(nEASY);

    for i = 1:nEASY
        pTrials(k).trialType  = 'EASY';
        pTrials(k).isChange   = true;
        pTrials(k).changeQuad = easyQuads(i);
        pTrials(k).durFrames  = pracCfg.durEASYFrames;
        k = k + 1;
    end

    % Optional block-specific tiered duration assignment (e.g., Practice Block 2)
    if isfield(pracCfg,'useTieredDurations') && pracCfg.useTieredDurations
        nShort  = pracCfg.tierCounts.short;
        nMedium = pracCfg.tierCounts.medium;
        nLong   = pracCfg.tierCounts.long;
        assert((nShort + nMedium + nLong) == nTotal, 'Tier counts must sum to nTrials.');

        durShort = pracCfg.durShortFrames;
        durMed   = pracCfg.durMediumFrames;
        durLong  = pracCfg.durLongFrames;

        assigned = nan(1, nTotal);
        trialTypes = {pTrials.trialType};
        idxEasy = find(strcmp(trialTypes, 'EASY'));

        % Keep EASY anchored to long durations where possible.
        nLongFromEasy = min(numel(idxEasy), nLong);
        if nLongFromEasy > 0
            ordEasy = idxEasy(randperm(numel(idxEasy)));
            assigned(ordEasy(1:nLongFromEasy)) = durLong;
        end

        nLongRemain = nLong - nLongFromEasy;
        idxAvail = find(isnan(assigned));
        if nLongRemain > 0
            assert(nLongRemain <= numel(idxAvail), 'Not enough trials for requested long-tier count.');
            ord = idxAvail(randperm(numel(idxAvail)));
            assigned(ord(1:nLongRemain)) = durLong;
        end

        idxAvail = find(isnan(assigned));
        assert(nMedium <= numel(idxAvail), 'Not enough trials for requested medium-tier count.');
        ord = idxAvail(randperm(numel(idxAvail)));
        assigned(ord(1:nMedium)) = durMed;

        idxAvail = find(isnan(assigned));
        assert(nShort == numel(idxAvail), 'Remaining trials must match short-tier count.');
        assigned(idxAvail) = durShort;

        for i = 1:nTotal
            pTrials(i).durFrames = assigned(i);
        end
    end

    % Sanity
    assert(k-1 == nTotal, 'buildPracticeTrialList: Trial count mismatch.');

    % ---------------- Assign change start orientations (for change trials) ----------------
    chgIdx = find([pTrials.isChange]);

    if ~isempty(chgIdx)
        v = repmat(allowedOri(:)', 1, ceil(numel(chgIdx) / numel(allowedOri)));
        v = v(1:numel(chgIdx));
        v = v(randperm(numel(v)));

        for ii = 1:numel(chgIdx)
            pTrials(chgIdx(ii)).changeStartOri = v(ii);
        end
    end

    % ---------------- Shuffle order ----------------
    pTrials = pTrials(randperm(numel(pTrials)));

    % (Optional later) de-streaking can be inserted here
end

function trials = buildTrialList(cfg)

    trialTemplate = struct('isChange',0,'staircase','A','changeQuad',0,'changeStartOri',NaN);
    trials = repmat(trialTemplate, cfg.nTotal, 1);

    idx0 = 1;

    for b = 1:cfg.nBlocks

        % --- Per-block counts (enforce 25/25 when pChange=0.5) ---
        if isfield(cfg,'trialDial') && isfield(cfg.trialDial,'applyPerBlock') && cfg.trialDial.applyPerBlock
            nChg  = cfg.trialDial.nChangePerBlock;
        else
            nChg  = round(cfg.trialsPerBlock * cfg.trialDial.pChange);
        end
        nCat = cfg.trialsPerBlock - nChg;

        % --- Split A/B inside the block (one staircase may get +1 when odd) ---
        if mod(b,2)==1
            nChgA = ceil(nChg/2);  nChgB = floor(nChg/2);
            nCatA = ceil(nCat/2);  nCatB = floor(nCat/2);
        else
            nChgA = floor(nChg/2); nChgB = ceil(nChg/2);
            nCatA = floor(nCat/2); nCatB = ceil(nCat/2);
        end

        % --- Build the block ---
        block = repmat(trialTemplate, cfg.trialsPerBlock, 1);
        k = 1;

        quadsA = makeBalancedQuads(nChgA);
        quadsB = makeBalancedQuads(nChgB);

        for i = 1:nChgA
            block(k).isChange = 1;
            block(k).staircase = 'A';
            block(k).changeQuad = quadsA(i);
            k = k + 1;
        end
        for i = 1:nChgB
            block(k).isChange = 1;
            block(k).staircase = 'B';
            block(k).changeQuad = quadsB(i);
            k = k + 1;
        end
        for i = 1:nCatA
            block(k).isChange = 0;
            block(k).staircase = 'A';
            k = k + 1;
        end
        for i = 1:nCatB
            block(k).isChange = 0;
            block(k).staircase = 'B';
            k = k + 1;
        end

        % --- Shuffle WITHIN the block (optional run constraint) ---
        order = randperm(numel(block));
        block = block(order);

        % write block into overall trials
        trials(idx0:idx0+cfg.trialsPerBlock-1) = block;
        idx0 = idx0 + cfg.trialsPerBlock;
    end

    % keep your orientation balancing after list is final
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


function drawPAS(window, windowRect, colour, bg, cfg)
    Screen('FillRect', window, bg);
    [~, yc] = RectCenter(windowRect);
    w = windowRect(3) - windowRect(1);
    h = windowRect(4) - windowRect(2);
    qcfg = cfg.display.text.questions;

    % Question
    Screen('TextSize', window, qcfg.pasQuestionSize);
    DrawFormattedText(window, 'How clearly did you see the change?', 'center', yc - round(h * qcfg.pasQuestionYOffsetFrac), colour, qcfg.pasQuestionWrap);

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

    numSize    = qcfg.pasNumberSize;
    textSize   = qcfg.pasDescSize;
    labelSize  = qcfg.pasLabelSize;
    lineStep   = round(h * qcfg.pasLineStepFrac);
    labelGap   = round(h * qcfg.pasLabelGapFrac);

    for i = 1:n
        % --- draw number (centred) ---
        Screen('TextSize', window, numSize);
        nb = Screen('TextBounds', window, nums{i});
        xNum = xs(i) - (nb(3) - nb(1))/2;
        DrawFormattedText(window, nums{i}, xNum, yNum, colour);

        % --- draw description (centred, can wrap if you add '\n') ---
        Screen('TextSize', window, textSize);
        lines = strsplit(desc{i}, '\n');

        yLine = yDescTop;
        for L = 1:numel(lines)
            lb = Screen('TextBounds', window, lines{L});
            xLine = xs(i) - (lb(3) - lb(1))/2;
            DrawFormattedText(window, lines{L}, xLine, yLine, colour);
            yLine = yLine + lineStep;
        end

        % --- draw bracketed label under description (centred) ---
        Screen('TextSize', window, labelSize);
        lab = labels{i};
        bb = Screen('TextBounds', window, lab);
        xLab = xs(i) - (bb(3) - bb(1))/2;
        yLab = yLine + labelGap;   % sits right under the description block
        DrawFormattedText(window, lab, xLab, yLab, colour);
    end
end

function d = keyToDigit(keyCode)
    if isnan(keyCode), d = NaN; return; end
    name = KbName(keyCode);
    if iscell(name), name = name{1}; end
    d = str2double(name(1));
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
            qCfg.quadGapFrac = 0.08;
            qCfg.quadBoxFrac = 0.42;
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
        'oriS1', '', ...
        'oriS2', '', ...
        'tS1', NaN, ...
        'tISI', NaN, ...
        'tS2', NaN, ...
        'tQ1', NaN, ...
        'tQ2', NaN, ...
        'resp2', NaN, ...
        'resp2RT', NaN, ...
        'pas', NaN, ...
        'pasRT', NaN, ...
        'hit', NaN, ...
        'locCorrect', NaN, ...
        'RF_A_xCurrent', NaN, ...
        'RF_B_xCurrent', NaN, ...
        'freezeA', NaN, ...
        'freezeB', NaN, ...
        'freezeAFrames', NaN, ...
        'freezeBFrames', NaN, ...
        'triggerEnabled', NaN, ...
        'trigTrialStartCode', NaN, ...
        'trigS1Code', NaN, ...
        'trigISICode', NaN, ...
        'trigS2Code', NaN, ...
        'trigQ1Code', NaN, ...
        'trigPASCode', NaN, ...
        'trigQ2Code', NaN, ...
        'trigLocCode', NaN, ...
        'trigTrialEndCode', NaN, ...
        'tTrialStart', NaN, ...
        'tTrialEnd',   NaN, ...
        'trialTotalSec', NaN ...
    );
end

function trigger = initSerialTrigger(eegCfg)
    trigger = struct( ...
        'enabled', false, ...
        'handle', [], ...
        'pulseWidthSec', 0, ...
        'sendResetAfterCode', false, ...
        'warnOnSendError', true);

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
        fprintf('EEG serial trigger enabled on %s @ %d baud.\n', eegCfg.serialPort, eegCfg.baudRate);
    catch ME
        trigger.enabled = false;
        trigger.handle = [];
        warning('EEG serial trigger disabled: %s', mExceptionText(ME));
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
            warning('EEG trigger send failed (%d): %s', code, mExceptionText(ME));
        end
    end
end

function emitSerialAndPixel(window, cfg, code)
    if nargin < 3 || isnan(code) || code < 0 || code > 255
        return;
    end
    sendTrigger(cfg.trigger, code);
    drawViewPixxPixelIfNeeded(window, cfg, code);
end

function tFlip = emitAuxFlip(window, cfg, code)
    if isfield(cfg, 'eeg') && isfield(cfg.eeg, 'markerPolicy') && cfg.eeg.markerPolicy.markAuxScreens
        emitSerialAndPixel(window, cfg, code);
    end
    tFlip = Screen('Flip', window);
end

function emitAuxSpaceEcho(window, cfg, code, bg)
    if ~(isfield(cfg, 'eeg') && isfield(cfg.eeg, 'markerPolicy') && cfg.eeg.markerPolicy.markAuxScreens)
        return;
    end
    Screen('FillRect', window, bg);
    emitSerialAndPixel(window, cfg, code);
    Screen('Flip', window);
    if isfield(cfg.eeg.markerPolicy, 'echoPulseSec')
        WaitSecs(cfg.eeg.markerPolicy.echoPulseSec);
    else
        WaitSecs(0.05);
    end
end

function parallelEchoFlip(window, cfg, code, xCentre, yCentre, fixationCoords, fixLWpx, black, bg, echoSec)
    if nargin < 10 || isempty(echoSec)
        echoSec = 0.05;
    end
    drawFixationOnly(window, bg, fixationCoords, fixLWpx, black, xCentre, yCentre);
    drawViewPixxPixelIfNeeded(window, cfg, code);
    sendTrigger(cfg.trigger, code);
    Screen('Flip', window);
    WaitSecs(echoSec);
end

function closeSerialTrigger(cfg)
    try
        if isfield(cfg,'trigger') && isfield(cfg.trigger,'enabled') && cfg.trigger.enabled && ...
                isfield(cfg.trigger,'handle') && ~isempty(cfg.trigger.handle)
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
        try viewpixxPixelModeShutdown(cfg); catch, end
        try closeSerialTrigger(cfg); catch, end
        try ShowCursor; catch, end

        if exist('sca','file') == 2
            sca;
        elseif exist('Screen','file') == 2
            Screen('CloseAll');
        end
    catch
        try Screen('CloseAll'); catch, end
    end
end

function cfg = viewpixxInitPixelMode(cfg)
% Initialise Datapixx Pixel Mode when cfg.viewpixx.pixelModeEnable is true.
    cfg.viewpixx.datapixxOpen = false;
    cfg.viewpixx.pixelModeEnabled = false;
    if ~isfield(cfg, 'viewpixx') || ~cfg.viewpixx.pixelModeEnable
        return;
    end
    try
        Datapixx('Open');
        if ~logical(Datapixx('IsReady'))
            warning(['ViewPixx: Datapixx IsReady==0 after Open. ' ...
                'Connect VPixx USB control; continuing without Pixel Mode.']);
            try Datapixx('Close'); catch, end
            return;
        end
        cfg.viewpixx.datapixxOpen = true;
        try
            Datapixx('EnablePixelMode');
        catch
            Datapixx('EnablePixelMode', 0);
        end
        Datapixx('RegWrRd');
        cfg.viewpixx.pixelModeEnabled = true;
        fprintf('ViewPixx Pixel Mode ENABLED (R = marker/255 on top-left pixel).\n');
    catch ME
        warning('ViewPixx Pixel Mode init failed: %s. Continuing without pixel markers.', mExceptionText(ME));
        try
            Datapixx('Close');
        catch
        end
        cfg.viewpixx.datapixxOpen = false;
        cfg.viewpixx.pixelModeEnabled = false;
    end
end

function drawViewPixxPixelIfNeeded(window, cfg, code)
% Draw Pixel Mode marker dot before Screen(''Flip'') when Pixel Mode is active.
    if ~isfield(cfg, 'viewpixx') || ~isfield(cfg.viewpixx, 'pixelModeEnabled') || ...
            ~cfg.viewpixx.pixelModeEnabled
        return;
    end
    if nargin < 3 || isnan(code) || code < 0 || code > 255
        return;
    end
    rVal = double(code) / 255;
    if isfield(cfg.viewpixx, 'minRNorm') && ~isempty(cfg.viewpixx.minRNorm)
        rVal = max(rVal, cfg.viewpixx.minRNorm);
    end
    rgb = [rVal, 0, 0];
    Screen('DrawDots', window, cfg.viewpixx.pixelPos, cfg.viewpixx.pixelSize, rgb, [], 1);
end

function viewpixxPixelModeShutdown(cfg)
    if ~isfield(cfg, 'viewpixx') || ~cfg.viewpixx.datapixxOpen
        return;
    end
    try
        if isfield(cfg.viewpixx, 'pixelModeEnabled') && cfg.viewpixx.pixelModeEnabled
            Datapixx('DisablePixelMode');
            Datapixx('RegWrRd');
        end
    catch
    end
    try
        Datapixx('Close');
    catch
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


function checkpointSave(results, t, outFile)
    try
        r = results(1:t);
        r = r(~cellfun(@isempty,{r.participantID}));
        if isempty(r), return; end

        T = struct2table(r);

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

function trialLogLine(t, cfg, trial, durFrames, resp2, hit, locCorrect, pas, RF_A, RF_B, nUpdA, nUpdB, convA, convB)

    if ~isfield(cfg,'debug') || ~isfield(cfg.debug,'trialLog') || ~cfg.debug.trialLog
        return;
    end

    blockNum = ceil(t / cfg.trialsPerBlock);

    % --- Persistent running PAS counters (reset each block) ---
    persistent lastBlock
    persistent pasCountBlock pasCountChangeBlock
    persistent pasCountBlind pasCountSensing pasCountSeeing
    persistent nBlind nSensing nSeeing
    
    if isempty(lastBlock) || blockNum ~= lastBlock
        lastBlock = blockNum;
    
        % PAS counts for ALL trials in block
        pasCountBlock       = zeros(1,4);
        % PAS counts for CHANGE trials in block
        pasCountChangeBlock = zeros(1,4);
    
        % PAS counts within each outcome bucket (CHANGE trials only)
        pasCountBlind   = zeros(1,4);
        pasCountSensing = zeros(1,4);
        pasCountSeeing  = zeros(1,4);
    
        % number of CHANGE trials in each bucket (regardless of PAS validity)
        nBlind = 0;
        nSensing = 0;
        nSeeing = 0;
    end

    % --- Update counters (ignore NaNs / out-of-range) ---
    if ~isnan(pas) && pas >= 1 && pas <= 4
        pasCountBlock(pas) = pasCountBlock(pas) + 1;
        if trial.isChange
            pasCountChangeBlock(pas) = pasCountChangeBlock(pas) + 1;
        end
    end

    % --- Outcome buckets (CHANGE trials only): Blind / Sensing / Seeing ---
    if trial.isChange
        if hit == 0
            nBlind = nBlind + 1;
            if ~isnan(pas) && pas >= 1 && pas <= 4
                pasCountBlind(pas) = pasCountBlind(pas) + 1;
            end
    
        elseif hit == 1 && locCorrect == 1
            nSeeing = nSeeing + 1;
            if ~isnan(pas) && pas >= 1 && pas <= 4
                pasCountSeeing(pas) = pasCountSeeing(pas) + 1;
            end
    
        else
            nSensing = nSensing + 1;
            if ~isnan(pas) && pas >= 1 && pas <= 4
                pasCountSensing(pas) = pasCountSensing(pas) + 1;
            end
        end
    end

    % --- Change vs No-change label ---
    if trial.isChange
        tc = 'CHG';
    else
        tc = 'NCH';
    end

    q1 = ternary(isnan(pas),'NaN',sprintf('%d',pas)); % Q1 is PAS
    if isnan(resp2), q2 = '-'; else, q2 = sprintf('%d', resp2); end

    % --- Score ---
    if trial.isChange
        if hit
            if ~isnan(locCorrect) && locCorrect == 1
                score = 1.0;      % detected + localised
            else
                score = 0.5;      % detected only
            end
        else
            score = 0.0;          % missed change
        end
    else
        score = double(~isnan(pas) && pas == 1); % No-change trials: PAS==1 is "correct rejection", PAS>1 is "false alarm"
    end

    % --- PAS distribution %s ---
    nAll = sum(pasCountBlock);
    if nAll > 0
        pAll = 100 * pasCountBlock / nAll;
    else
        pAll = [0 0 0 0];
    end

    nChg = sum(pasCountChangeBlock);
    if nChg > 0
        pChg = 100 * pasCountChangeBlock / nChg;
    else
        pChg = [0 0 0 0];
    end

    if trial.isChange
        locStr = sprintf('%d', locCorrect);   % 0/1
    else
        locStr = '-';
    end

    % --- Per-trial line ---
    fprintf(['blk=%02d trl=%03d %s st=%s q=%s dur=%02d | Q1=%s Q2=%s | hit=%d loc=%s | score=%.1f | ' ...
             'xA=%.1f xB=%.1f | PASblk[%d %d %d %d] CHG[%d %d %d %d] | updA=%d updB=%d convA=%d convB=%d\n'], ...
        blockNum, t, tc, trial.staircase, ...
        ternary(trial.isChange, sprintf('%d', trial.changeQuad), '-'), ...
        durFrames, q1, q2, ...
        hit, locStr, score, ...
        RF_A.xCurrent, RF_B.xCurrent, ...
        pasCountBlock(1), pasCountBlock(2), pasCountBlock(3), pasCountBlock(4), ...
        pasCountChangeBlock(1), pasCountChangeBlock(2), pasCountChangeBlock(3), pasCountChangeBlock(4), ...
        nUpdA, nUpdB, convA, convB);

    % --- End-of-block summaries ---
    if mod(t, cfg.trialsPerBlock) == 0

        fprintf('  PAS block dist (ALL):  1=%d (%.1f%%)  2=%d (%.1f%%)  3=%d (%.1f%%)  4=%d (%.1f%%)\n', ...
            pasCountBlock(1), pAll(1), pasCountBlock(2), pAll(2), pasCountBlock(3), pAll(3), pasCountBlock(4), pAll(4));

        fprintf('  PAS block dist (CHG):  1=%d (%.1f%%)  2=%d (%.1f%%)  3=%d (%.1f%%)  4=%d (%.1f%%)\n', ...
            pasCountChangeBlock(1), pChg(1), pasCountChangeBlock(2), pChg(2), pasCountChangeBlock(3), pChg(3), pasCountChangeBlock(4), pChg(4));

        % --- Blind/Sensing/Seeing counts + % ---
        nChgTotal = nBlind + nSensing + nSeeing;
        if nChgTotal > 0
            pBlindTot   = 100 * nBlind   / nChgTotal;
            pSensingTot = 100 * nSensing / nChgTotal;
            pSeeingTot  = 100 * nSeeing  / nChgTotal;
        else
            pBlindTot = 0; pSensingTot = 0; pSeeingTot = 0;
        end
        
        fprintf('  CHG outcomes: blind=%d (%.1f%%)  sensing=%d (%.1f%%)  seeing=%d (%.1f%%)\n', ...
            nBlind, pBlindTot, nSensing, pSensingTot, nSeeing, pSeeingTot);
        
        % --- PAS dist within outcome buckets ---
        nB = sum(pasCountBlind);
        if nB > 0, pB = 100 * pasCountBlind / nB; else, pB = [0 0 0 0]; end
        fprintf('  PAS dist (BLIND): 1=%d (%.1f%%)  2=%d (%.1f%%)  3=%d (%.1f%%)  4=%d (%.1f%%)\n', ...
            pasCountBlind(1), pB(1), pasCountBlind(2), pB(2), pasCountBlind(3), pB(3), pasCountBlind(4), pB(4));
        
        nS = sum(pasCountSensing);
        if nS > 0, pS = 100 * pasCountSensing / nS; else, pS = [0 0 0 0]; end
        fprintf('  PAS dist (SENS):  1=%d (%.1f%%)  2=%d (%.1f%%)  3=%d (%.1f%%)  4=%d (%.1f%%)\n', ...
            pasCountSensing(1), pS(1), pasCountSensing(2), pS(2), pasCountSensing(3), pS(3), pasCountSensing(4), pS(4));
        
        nV = sum(pasCountSeeing);
        if nV > 0, pV = 100 * pasCountSeeing / nV; else, pV = [0 0 0 0]; end
        fprintf('  PAS dist (SEE):   1=%d (%.1f%%)  2=%d (%.1f%%)  3=%d (%.1f%%)  4=%d (%.1f%%)\n', ...
            pasCountSeeing(1), pV(1), pasCountSeeing(2), pV(2), pasCountSeeing(3), pV(3), pasCountSeeing(4), pV(4));

    end
end

function summary = runPracticeBlock(window, windowRect, gratingTex, allRects, fixationCoords, xCentre, yCentre, ifi, cfg, bg, black, pracCfg)

    quadNames = {'TOP LEFT','TOP RIGHT','BOTTOM LEFT','BOTTOM RIGHT'};

    allowedOri = cfg.stim.allowedOri;

    % --- Build mixed practice trial list (STD / NCH / EASY) ---
    pTrials = buildPracticeTrialList(pracCfg, allowedOri);

    % --- Practice metrics counters (Phase C scaffold) ---
    m = struct();
    
    m.nTrials = numel(pTrials);
    
    m.nSTD = 0;  m.nSTD_detect = 0;  m.nSTD_see = 0;
    m.nNCH = 0;  m.nNCH_FA = 0;      m.nNCH_CR = 0;
    m.nEASY = 0; m.nEASY_detect = 0; m.nEASY_see = 0;
    
    m.nChange = 0; m.nChange_detect = 0; m.nChange_see = 0;

        for p = 1:numel(pTrials)
            trial = pTrials(p);
                checkAbort(cfg);
    
            durFrames = trial.durFrames;
    
            % Build S1 orientations using the same rules as main task
            if trial.isChange
                oriS1 = makeOriS1_noPostChangeDup(trial.changeQuad, trial.changeStartOri, allowedOri);
            else
                % No-change: still avoid "all same" and keep it non-trivial
                oriS1 = allowedOri(randperm(numel(allowedOri), 4))';
            end
            
            % Build S2
            oriS2 = oriS1;
            if trial.isChange
                % IMPORTANT: with allowedOri = [0 45 90 135], keep rotation consistent with your design.
                % If you still want a 90° rotation, use +90:
                oriS2(trial.changeQuad) = mod(oriS1(trial.changeQuad) + 90, 180);
            end
    
            % ---- Timeline (same as main) ----
            % Fixation jitter
            jitterFrames = randi([cfg.fixJitterFrames(1), cfg.fixJitterFrames(2)], 1, 1);
            drawFixationOnly(window, bg, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
            if cfg.eeg.markerPolicy.markPracticeTrials
                drawViewPixxPixelIfNeeded(window, cfg, cfg.eeg.codes.practice.trialStart);
            end
            tFixOn = Screen('Flip', window);
            if cfg.eeg.markerPolicy.markPracticeTrials
                sendTrigger(cfg.trigger, cfg.eeg.codes.practice.trialStart);
            end
            tTrialStart = tFixOn;
            holdForSecondsWithAbort(tFixOn + jitterFrames*ifi, cfg);
    
            % S1
            drawGratings(window, gratingTex, allRects, oriS1, bg);
            drawFixation(window, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
            if cfg.eeg.markerPolicy.markPracticeTrials
                drawViewPixxPixelIfNeeded(window, cfg, cfg.eeg.codes.practice.s1On);
            end
            tS1 = Screen('Flip', window);
            if cfg.eeg.markerPolicy.markPracticeTrials
                sendTrigger(cfg.trigger, cfg.eeg.codes.practice.s1On);
            end
            holdForSecondsWithAbort(tS1 + durFrames*ifi, cfg);
    
            % ISI (same as main)
            drawFixationOnly(window, bg, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
            if cfg.eeg.markerPolicy.markPracticeTrials
                drawViewPixxPixelIfNeeded(window, cfg, cfg.eeg.codes.practice.isiOn);
            end
            tISI = Screen('Flip', window);
            if cfg.eeg.markerPolicy.markPracticeTrials
                sendTrigger(cfg.trigger, cfg.eeg.codes.practice.isiOn);
            end
            holdForSecondsWithAbort(tISI + cfg.ISI_frames*ifi, cfg);
    
            % S2
            drawGratings(window, gratingTex, allRects, oriS2, bg);
            drawFixation(window, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
            if cfg.eeg.markerPolicy.markPracticeTrials
                drawViewPixxPixelIfNeeded(window, cfg, cfg.eeg.codes.practice.s2On);
            end
            tS2 = Screen('Flip', window);
            if cfg.eeg.markerPolicy.markPracticeTrials
                sendTrigger(cfg.trigger, cfg.eeg.codes.practice.s2On);
            end
            holdForSecondsWithAbort(tS2 + durFrames*ifi, cfg);
    
            % Gap
            drawFixationOnly(window, bg, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
            tGap = Screen('Flip', window);
            holdForSecondsWithAbort(tGap + cfg.gap_frames*ifi, cfg);
    
            % ---- Questions ----

            % Q1 (PAS)
            drawPAS(window, windowRect, black, bg, cfg);
            if cfg.eeg.markerPolicy.markPracticeTrials
                drawViewPixxPixelIfNeeded(window, cfg, cfg.eeg.codes.practice.q1On);
            end
            tQ1 = Screen('Flip', window);
            if cfg.eeg.markerPolicy.markPracticeTrials
                sendTrigger(cfg.trigger, cfg.eeg.codes.practice.q1On);
            end
            [pasKey, ~] = waitForKeyQueue(cfg.keys.pas, cfg.keys.escape, cfg.maxRespSec, cfg);
            pas = keyToDigit(pasKey);
            if cfg.eeg.markerPolicy.markPracticeTrials && ~isnan(pas) && pas >= 1 && pas <= 4
                sendTrigger(cfg.trigger, cfg.eeg.codes.practice.pasBase + pas);
                if cfg.eeg.markerPolicy.echoPasLocPixel
                    parallelEchoFlip(window, cfg, cfg.eeg.codes.practice.pasBase + pas, ...
                        xCentre, yCentre, fixationCoords, cfg.fix.lineWidthPx, black, bg, cfg.eeg.markerPolicy.echoPulseSec);
                end
            end
            
            detected = double(~isnan(pas) && pas > 1);
    
            if ~isnan(pas) && pas == 1
                q2Prompt = 'Select a quadrant, even if you experienced no change.';
            else
                q2Prompt = 'Where was the change?';
            end
            
            % Q2 (ALWAYS)
            drawQuadrantPrompt(window, windowRect, black, bg, q2Prompt, cfg);
            if cfg.eeg.markerPolicy.markPracticeTrials
                drawViewPixxPixelIfNeeded(window, cfg, cfg.eeg.codes.practice.q2On);
            end
            Screen('Flip', window);
            if cfg.eeg.markerPolicy.markPracticeTrials
                sendTrigger(cfg.trigger, cfg.eeg.codes.practice.q2On);
            end
            [resp2Key, ~] = waitForKeyQueue(cfg.keys.quad, cfg.keys.escape, cfg.maxRespSec, cfg);
            resp2 = keyToDigit(resp2Key);
            if cfg.eeg.markerPolicy.markPracticeTrials && ~isnan(resp2) && resp2 >= 1 && resp2 <= 4
                sendTrigger(cfg.trigger, cfg.eeg.codes.practice.locBase + resp2);
                if cfg.eeg.markerPolicy.echoPasLocPixel
                    parallelEchoFlip(window, cfg, cfg.eeg.codes.practice.locBase + resp2, ...
                        xCentre, yCentre, fixationCoords, cfg.fix.lineWidthPx, black, bg, cfg.eeg.markerPolicy.echoPulseSec);
                end
            end
            
            if trial.isChange
                if isnan(resp2)
                    locCorrect = 0;  % timeout/missing localisation = incorrect
                else
                    locCorrect = double(resp2 == trial.changeQuad);
                end
            else
                locCorrect = NaN;     % no-change trials: not defined
            end
    
            if isfield(cfg,'practice') && isfield(cfg.practice,'logToCommandWindow') && cfg.practice.logToCommandWindow
                if trial.isChange
                    if detected && locCorrect == 1
                        outcomeStr = 'SEE';
                    elseif detected && locCorrect == 0
                        outcomeStr = 'SENS';
                    else
                        outcomeStr = 'BLIND';
                    end
                    qStr = sprintf('%d', trial.changeQuad);
                    locStr = sprintf('%d', locCorrect);
                else
                    if detected
                        outcomeStr = 'FA';
                    else
                        outcomeStr = 'CR';
                    end
                    qStr = '-';
                    locStr = '-';
                end
            
                if isnan(pas)
                    pasStr = 'NaN';
                else
                    pasStr = sprintf('%d', pas);
                end
                
                if isnan(resp2)
                    resp2Str = 'NaN';
                else
                    resp2Str = sprintf('%d', resp2);
                end

                fprintf('PRACTICE %-14s trl=%02d/%02d type=%-4s q=%s dur=%02d | PAS=%s Q2=%s | det=%d loc=%s | %s\n', ...
                    pracCfg.name, p, numel(pTrials), trial.trialType, qStr, durFrames, pasStr, ...
                    resp2Str, detected, locStr, outcomeStr);
            end

            % --- Update practice metrics ---
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
                        m.nNCH_FA = m.nNCH_FA + 1;   % PAS > 1 on no-change
                    else
                        m.nNCH_CR = m.nNCH_CR + 1;   % PAS == 1 on no-change
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
                
                Screen('Flip', window);
        
        
                if cfg.practice.feedbackWaitForSpace
                    waitForKeyQueue([cfg.keys.space], cfg.keys.escape, Inf, cfg);
                else
                    WaitSecs(0.9);
                end
            end

            % ITI
            % drawFixationOnly(window, bg, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
            Screen('FillRect', window, bg);
            if cfg.eeg.markerPolicy.markPracticeTrials && cfg.eeg.markerPolicy.alignTrialEndToItiOnset
                drawViewPixxPixelIfNeeded(window, cfg, cfg.eeg.codes.practice.trialEnd);
            end
            tITI = Screen('Flip', window);
            if cfg.eeg.markerPolicy.markPracticeTrials
                sendTrigger(cfg.trigger, cfg.eeg.codes.practice.trialEnd);
            end
            holdForSecondsWithAbort(tITI + cfg.ITI_frames*ifi, cfg);
        end

        summary = struct();
        summary.name = pracCfg.name;
        summary.nTrials = m.nTrials;
        
        summary.nSTD = m.nSTD;
        summary.nNCH = m.nNCH;
        summary.nEASY = m.nEASY;
        
        summary.nChange = m.nChange;
        
        summary.nNCH_FA = m.nNCH_FA;
        summary.nNCH_CR = m.nNCH_CR;
        
        summary.nEASY_detect = m.nEASY_detect;
        summary.nEASY_see    = m.nEASY_see;
        
        summary.nChange_detect = m.nChange_detect;
        summary.nChange_see    = m.nChange_see;
        
        summary.faRateNCH      = safeRate(m.nNCH_FA, m.nNCH);
        summary.crRateNCH      = safeRate(m.nNCH_CR, m.nNCH);
        
        summary.easyDetectRate = safeRate(m.nEASY_detect, m.nEASY);
        summary.easySeeRate    = safeRate(m.nEASY_see, m.nEASY);
        
        summary.changeDetectRate = safeRate(m.nChange_detect, m.nChange);
        summary.changeSeeRate    = safeRate(m.nChange_see, m.nChange);
        
        summary.classification = 'unclassified';  % next phase

    end

function cfg = applyTrialDial(cfg)
    % Uses cfg.trialDial.pChange to set cfg.nChange/cfg.nCatch and A/B splits

    if ~isfield(cfg,'trialDial') || ~isfield(cfg.trialDial,'pChange')
        error('applyTrialDial: Missing cfg.trialDial.pChange');
    end

    p = cfg.trialDial.pChange;
    p = max(0, min(1, p)); % clamp

    % Compute counts from total
    nChange = round(cfg.nTotal * p);

    % Ensure even so we can split across A/B cleanly
    nChange = 2 * round(nChange/2);

    % Safety clamp
    nChange = max(0, min(cfg.nTotal, nChange));

    cfg.nChange = nChange;
    cfg.nCatch  = cfg.nTotal - cfg.nChange;

    % A/B splits (must be even)
    cfg.nChangeA = cfg.nChange/2;
    cfg.nChangeB = cfg.nChange/2;

    cfg.nCatchA  = cfg.nCatch/2;
    cfg.nCatchB  = cfg.nCatch/2;

    % Quick sanity checks
    if mod(cfg.nCatch,2) ~= 0
        error('applyTrialDial: nCatch ended up odd. Make cfg.nTotal even (it is) and pChange reasonable.');
    end
end

function trials = assignBalancedChangeStartOri(trials, allowedOri)
    isChg = [trials.isChange] == 1;

    for s = ['A','B']
        idxS = find(isChg & strcmp({trials.staircase}, s));

        for q = 1:4
            idx = idxS([trials(idxS).changeQuad] == q);
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

function oriS1 = makeOriS1_noPostChangeDup(changeQuad, startOri, allowedOri)

    allowedOri = allowedOri(:)';  % row vector

    % Pick/snap startOri safely
    if isempty(startOri) || ~isfinite(startOri)
        startOri = allowedOri(randi(numel(allowedOri)));
    else
        % Snap to nearest allowed value (helps with float weirdness)
        [~, idx] = min(abs(allowedOri - startOri));
        startOri = allowedOri(idx);
    end

    changedOri = mod(startOri + 90, 180);

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
