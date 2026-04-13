function CB_4xGratings_5Trial_TriggerSmokeTest
% CB_4xGratings_5Trial_TriggerSmokeTest
% Self-contained smoke test: instruction + trial-overview PNG + 5 calibration-style
% trials with serial (IOPort) and ViewPixx Pixel Mode on every Flip.
%
% Smoke-only behaviours (not in main CB_4xGratings_EEG.m):
% - Reserved bytes 80-85 on instruction/overview Flips (see cfg.eeg.codes.smoke).
% - After PAS / loc keypress: extra short Flip ("echo") so parallel path sees the
%   same code as serial (main task sends serial there without a Flip).
% - Pixel red channel uses minRNorm floor (default 19/255) so low codes (11,21,...)
%   stay visible on hardware; SERIAL still sends the exact byte.
%
% Requires: Psychtoolbox, optional Palamedes NOT required. Gratings_TrialOverview.png
% in pwd for overview screen (same as main task).

close all;
try ListenChar(0); catch, end
try KbQueueRelease(-1); catch, end
if exist('sca', 'file') == 2
    sca;
elseif exist('Screen', 'file') == 2
    Screen('CloseAll');
end

cfg = struct();
pid = input('Participant ID (Enter for SMOKE): ', 's');
if isempty(strtrim(pid)), cfg.participantID = 'SMOKE'; else, cfg.participantID = strtrim(pid); end

cfg.debugWindow      = false;
cfg.visualDebugLevel = 1;
cfg.skipSyncTests    = 1;
cfg.screenNumber     = 2;
cfg.kbDev            = -1;
cfg.displayProfile   = 'viewpixx';
cfg.display          = makeDisplayProfile(cfg.displayProfile);

cfg.stim.squareSizeDeg  = 6.9;
cfg.stim.spacingDeg     = 3.4;
cfg.stim.cyclesPerStim  = 10;
cfg.stim.contrast       = 0.8;
cfg.stim.backgroundGrey = 0.5;
cfg.stim.gaborSigmaFrac = 0.40;
cfg.stim.allowedOri     = 0:22.5:157.5;

cfg.fix.sizeDeg      = 0.37;
cfg.fix.lineWidthDeg = 0.08;

cfg.fixJitterRangeSec = [1.00 1.50];
cfg.postS2Gap_sec     = 0.20;
cfg.ITI_sec           = 1.00;
cfg.maxRespSec        = 30.00;
cfg.startDurFrames    = 30;

cfg.eeg.enable             = true;
cfg.eeg.serialPort         = 'COM3';
cfg.eeg.baudRate           = 115200;
cfg.eeg.pulseWidthSec      = 0.005;
cfg.eeg.sendResetAfterCode = true;
cfg.eeg.warnOnSendError    = true;

cfg.eeg.codes = struct();
cfg.eeg.codes.trialStart = 11;
cfg.eeg.codes.s1On       = 21;
cfg.eeg.codes.isiOn      = 22;
cfg.eeg.codes.s2On       = 23;
cfg.eeg.codes.q1On       = 31;
cfg.eeg.codes.pasBase    = 40;
cfg.eeg.codes.q2On       = 32;
cfg.eeg.codes.locBase    = 50;
cfg.eeg.codes.trialEnd   = 12;
cfg.eeg.codes.smoke = struct( ...
    'instrGrey', 80, ...
    'instrActive', 81, ...
    'overviewGrey', 82, ...
    'overviewActive', 83, ...
    'instrSpace', 84, ...
    'overviewSpace', 85);

cfg.trialOverviewPNG = fullfile(pwd, 'Gratings_TrialOverview.png');

cfg.viewpixx = struct( ...
    'pixelModeEnable', true, ...
    'pixelPos', [0 0], ...
    'pixelSize', 1, ...
    'minRNorm', 19/255, ...
    'datapixxOpen', false, ...
    'pixelModeEnabled', false);

KbName('UnifyKeyNames');
try
    PsychDefaultSetup(2);
catch
    error('Psychtoolbox not found.');
end

cfg.keys.escape = KbName('ESCAPE');
cfg.keys.space  = KbName('space');
cfg.keys.quad   = [KbName('1!') KbName('2@') KbName('3#') KbName('4$')];
cfg.keys.pas    = [KbName('1!') KbName('2@') KbName('3#') KbName('4$')];

bg    = cfg.stim.backgroundGrey;
black = 0;
window = [];

Screen('Preference', 'VisualDebugLevel', cfg.visualDebugLevel);
Screen('Preference', 'SkipSyncTests', cfg.skipSyncTests);

try
    cfg.trigger = initSerialTrigger(cfg.eeg);

    if cfg.debugWindow
        [window, windowRect] = PsychImaging('OpenWindow', cfg.screenNumber, bg, [100 100 900 700]);
    else
        [window, windowRect] = PsychImaging('OpenWindow', cfg.screenNumber, bg);
    end
    fprintf('Smoke test: OpenWindow OK\n');

    cleanupObj = onCleanup(@() cleanupSmokeTest(cfg)); %#ok<NASGU>

    Screen('BlendFunction', window, 'GL_SRC_ALPHA', 'GL_ONE_MINUS_SRC_ALPHA');
    Screen('TextFont', window, 'Arial');
    Screen('TextSize', window, 45);

    cfg = viewpixxInitPixelMode(cfg);

    ifi = Screen('GetFlipInterval', window);
    [xCentre, yCentre] = RectCenter(windowRect);

    geom = computeDisplayGeometry(cfg.display, windowRect);
    cfg.display.geom = geom;
    cfg.stim.squareSizePx = max(10, round(degToPx(cfg.stim.squareSizeDeg, geom)));
    cfg.stim.spacingPx    = max(5,  round(degToPx(cfg.stim.spacingDeg, geom)));
    cfg.fix.sizePx        = max(4,  round(degToPx(cfg.fix.sizeDeg, geom)));
    cfg.fix.lineWidthPx   = max(1,  round(degToPx(cfg.fix.lineWidthDeg, geom)));

    cfg.ISI_frames      = 9;
    cfg.gap_frames      = max(0, round(cfg.postS2Gap_sec / ifi));
    cfg.ITI_frames      = max(0, round(cfg.ITI_sec / ifi));
    cfg.fixJitterFrames = round(cfg.fixJitterRangeSec / ifi);

    ListenChar(0);
    try KbQueueRelease(cfg.kbDev); catch, end
    KbQueueCreate(cfg.kbDev);
    KbQueueStart(cfg.kbDev);
    KbQueueFlush(cfg.kbDev);

    baseRect = [0 0 cfg.stim.squareSizePx cfg.stim.squareSizePx];
    xPos = [xCentre - cfg.stim.spacingPx, xCentre + cfg.stim.spacingPx, ...
            xCentre - cfg.stim.spacingPx, xCentre + cfg.stim.spacingPx];
    yPos = [yCentre - cfg.stim.spacingPx, yCentre - cfg.stim.spacingPx, ...
            yCentre + cfg.stim.spacingPx, yCentre + cfg.stim.spacingPx];
    allRects = nan(4, 4);
    for i = 1:4
        allRects(i, :) = CenterRectOnPoint(baseRect, xPos(i), yPos(i));
    end

    gratingTex = makeGratingTexture(window, cfg.stim.squareSizePx, cfg.stim.cyclesPerStim, ...
        cfg.stim.contrast, bg, cfg.stim.gaborSigmaFrac);
    fixationCoords = [-cfg.fix.sizePx cfg.fix.sizePx 0 0; 0 0 -cfg.fix.sizePx cfg.fix.sizePx];

    showSmokeInstructionScreen(window, windowRect, bg, black, cfg, xCentre, yCentre, fixationCoords);
    showSmokeTrialOverviewScreen(window, windowRect, bg, black, cfg, xCentre, yCentre, fixationCoords);

    smokeTrials = buildSmokeFiveTrials();
    durFrames = cfg.startDurFrames;
    allowedOri = cfg.stim.allowedOri;

    fprintf('Smoke test: starting 5 trials (durFrames=%d).\n', durFrames);

    for t = 1:5
        trial = smokeTrials(t);
        checkAbort(cfg);

        sendTrigger(cfg.trigger, cfg.eeg.codes.trialStart);

        if trial.isChange
            oriS1 = makeOriS1_noPostChangeDup(trial.changeQuad, trial.changeStartOri, allowedOri);
        else
            oriS1 = allowedOri(randperm(numel(allowedOri), 4))';
        end
        oriS2 = oriS1;
        if trial.isChange
            oriS2(trial.changeQuad) = mod(oriS1(trial.changeQuad) + 90, 180);
        end

        jitterFrames = randi([cfg.fixJitterFrames(1), cfg.fixJitterFrames(2)], 1, 1);
        drawFixationOnly(window, bg, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
        drawViewPixxPixelIfNeeded(window, cfg, cfg.eeg.codes.trialStart);
        tFixOn = Screen('Flip', window);
        holdForSecondsWithAbort(tFixOn + jitterFrames * ifi, cfg);

        drawGratings(window, gratingTex, allRects, oriS1, bg);
        drawFixation(window, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
        drawViewPixxPixelIfNeeded(window, cfg, cfg.eeg.codes.s1On);
        tS1 = Screen('Flip', window);
        sendTrigger(cfg.trigger, cfg.eeg.codes.s1On);
        holdForSecondsWithAbort(tS1 + durFrames * ifi, cfg);

        drawFixationOnly(window, bg, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
        drawViewPixxPixelIfNeeded(window, cfg, cfg.eeg.codes.isiOn);
        tISI = Screen('Flip', window);
        sendTrigger(cfg.trigger, cfg.eeg.codes.isiOn);
        holdForSecondsWithAbort(tISI + cfg.ISI_frames * ifi, cfg);

        drawGratings(window, gratingTex, allRects, oriS2, bg);
        drawFixation(window, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
        drawViewPixxPixelIfNeeded(window, cfg, cfg.eeg.codes.s2On);
        tS2 = Screen('Flip', window);
        sendTrigger(cfg.trigger, cfg.eeg.codes.s2On);
        holdForSecondsWithAbort(tS2 + durFrames * ifi, cfg);

        drawFixationOnly(window, bg, fixationCoords, cfg.fix.lineWidthPx, black, xCentre, yCentre);
        drawViewPixxPixelIfNeeded(window, cfg, 0);
        tGap = Screen('Flip', window);
        holdForSecondsWithAbort(tGap + cfg.gap_frames * ifi, cfg);

        drawPAS(window, windowRect, black, bg, cfg);
        drawViewPixxPixelIfNeeded(window, cfg, cfg.eeg.codes.q1On);
        tQ1 = Screen('Flip', window);
        sendTrigger(cfg.trigger, cfg.eeg.codes.q1On);

        [pasKey, pasTime] = waitForKeyQueue(cfg.keys.pas, cfg.keys.escape, cfg.maxRespSec, cfg);
        pas = keyToDigit(pasKey);
        if ~isnan(pas) && pas >= 1 && pas <= 4
            cPas = cfg.eeg.codes.pasBase + pas;
            sendTrigger(cfg.trigger, cPas);
            parallelEchoFlip(window, cfg, cPas, xCentre, yCentre, fixationCoords, cfg.fix.lineWidthPx, black, bg);
        end

        hit = double(~isnan(pas) && pas > 1);
        if ~isnan(pas) && pas == 1
            q2Prompt = 'Select a quadrant, even if you experienced no change.';
        else
            q2Prompt = 'Where was the change?';
        end

        drawQuadrantPrompt(window, windowRect, black, bg, q2Prompt, cfg);
        drawViewPixxPixelIfNeeded(window, cfg, cfg.eeg.codes.q2On);
        tQ2 = Screen('Flip', window);
        sendTrigger(cfg.trigger, cfg.eeg.codes.q2On);

        [resp2Key, ~] = waitForKeyQueue(cfg.keys.quad, cfg.keys.escape, cfg.maxRespSec, cfg);
        resp2 = keyToDigit(resp2Key);
        if ~isnan(resp2) && resp2 >= 1 && resp2 <= 4
            cLoc = cfg.eeg.codes.locBase + resp2;
            sendTrigger(cfg.trigger, cLoc);
            parallelEchoFlip(window, cfg, cLoc, xCentre, yCentre, fixationCoords, cfg.fix.lineWidthPx, black, bg);
        end

        Screen('FillRect', window, bg);
        drawViewPixxPixelIfNeeded(window, cfg, 0);
        tITI = Screen('Flip', window);
        holdForSecondsWithAbort(tITI + cfg.ITI_frames * ifi, cfg);

        sendTrigger(cfg.trigger, cfg.eeg.codes.trialEnd);
        parallelEchoFlip(window, cfg, cfg.eeg.codes.trialEnd, xCentre, yCentre, fixationCoords, cfg.fix.lineWidthPx, black, bg);

        fprintf('Smoke test: finished trial %d/5 (change=%d).\n', t, trial.isChange);
    end

    Screen('Close', gratingTex);
    fprintf('Smoke test COMPLETE. Press SPACE to exit.\n');
    Screen('FillRect', window, bg);
    DrawFormattedText(window, 'Smoke test complete.\n\nPress SPACE.', 'center', 'center', black, 90);
    drawViewPixxPixelIfNeeded(window, cfg, 0);
    Screen('Flip', window);
    waitForKeyQueue([cfg.keys.space], cfg.keys.escape, Inf, cfg);

catch ME
    fprintf(2, 'Smoke test ERROR:\n%s\n', getReport(ME, 'extended', 'hyperlinks', 'off'));
    rethrow(ME);
end

end

%% ========================= LOCAL FUNCTIONS =========================

function trials = buildSmokeFiveTrials()
    trials = repmat(struct('isChange', false, 'changeQuad', NaN, 'changeStartOri', NaN), 5, 1);
    trials(1).isChange = true;  trials(1).changeQuad = 1; trials(1).changeStartOri = 0;
    trials(2).isChange = true;  trials(2).changeQuad = 2; trials(2).changeStartOri = 45;
    trials(3).isChange = false;
    trials(4).isChange = true;  trials(4).changeQuad = 3; trials(4).changeStartOri = 90;
    trials(5).isChange = false;
end

function parallelEchoFlip(window, cfg, code, xCentre, yCentre, fixationCoords, fixLWpx, black, bg)
    drawFixationOnly(window, bg, fixationCoords, fixLWpx, black, xCentre, yCentre);
    drawViewPixxPixelIfNeeded(window, cfg, code);
    Screen('Flip', window);
    WaitSecs(0.05);
end

function showSmokeInstructionScreen(window, windowRect, bg, black, cfg, xCentre, yCentre, fixationCoords)
    titleFirstInstructions = 'Change Blindness Task Instruction (SMOKE TEST)';
    FirstInstructions = [ ...
        'This is a SHORT smoke test for serial + ViewPixx Pixel Mode triggers.\n' ...
        'Same trial layout as the main task (fixation, gratings, PAS, quadrant).\n\n' ...
        'Triggers fire on instruction/overview Flips and on every trial phase.\n' ...
    ];

    tcfg = cfg.display.text;
    lockSec  = tcfg.lockSec;
    greyText = tcfg.greyText;
    promptY  = windowRect(4) * tcfg.promptYFrac;
    titleY   = windowRect(4) * tcfg.instructionTitleY;
    bodyY    = windowRect(4) * tcfg.instructionBodyY;

    Screen('FillRect', window, bg);
    Screen('TextSize', window, tcfg.titleSize);
    Screen('TextStyle', window, 1);
    DrawFormattedText(window, titleFirstInstructions, 'center', titleY, black);
    Screen('TextStyle', window, 0);
    Screen('TextSize', window, tcfg.bodySize);
    DrawFormattedText(window, FirstInstructions, 'center', bodyY, black, tcfg.bodyWrap, [], [], tcfg.bodyLineSpacing);
    Screen('TextSize', window, tcfg.promptSize);
    DrawFormattedText(window, 'Press SPACEBAR to continue.', 'center', promptY, greyText);

    sendTrigger(cfg.trigger, cfg.eeg.codes.smoke.instrGrey);
    drawViewPixxPixelIfNeeded(window, cfg, cfg.eeg.codes.smoke.instrGrey);
    tOn = Screen('Flip', window);

    KbQueueFlush(cfg.kbDev);
    holdForSecondsWithAbort(tOn + lockSec, cfg);
    KbQueueFlush(cfg.kbDev);

    Screen('FillRect', window, bg);
    Screen('TextSize', window, tcfg.titleSize);
    Screen('TextStyle', window, 1);
    DrawFormattedText(window, titleFirstInstructions, 'center', titleY, black);
    Screen('TextStyle', window, 0);
    Screen('TextSize', window, tcfg.bodySize);
    DrawFormattedText(window, FirstInstructions, 'center', bodyY, black, tcfg.bodyWrap, [], [], tcfg.bodyLineSpacing);
    Screen('TextSize', window, tcfg.promptSize);
    DrawFormattedText(window, 'Press SPACEBAR to continue.', 'center', promptY, black);

    sendTrigger(cfg.trigger, cfg.eeg.codes.smoke.instrActive);
    drawViewPixxPixelIfNeeded(window, cfg, cfg.eeg.codes.smoke.instrActive);
    Screen('Flip', window);

    KbQueueFlush(cfg.kbDev);
    waitForKeyQueue([cfg.keys.space], cfg.keys.escape, Inf, cfg);

    sendTrigger(cfg.trigger, cfg.eeg.codes.smoke.instrSpace);
    parallelEchoFlip(window, cfg, cfg.eeg.codes.smoke.instrSpace, xCentre, yCentre, ...
        fixationCoords, cfg.fix.lineWidthPx, black, bg);
end

function showSmokeTrialOverviewScreen(window, windowRect, bg, black, cfg, xCentre, yCentre, fixationCoords)
    tcfg = cfg.display.text;
    lockSec  = tcfg.lockSec;
    greyText = tcfg.greyText;
    titleTrialOverview = 'Trial Overview (SMOKE TEST)';

    pngPath = cfg.trialOverviewPNG;
    if ~exist(pngPath, 'file')
        error('Trial overview PNG not found: %s', pngPath);
    end

    [img, ~, alpha] = imread(pngPath);
    if ~isempty(alpha)
        img(:, :, 4) = alpha;
    end
    tex = Screen('MakeTexture', window, img);

    KbQueueFlush(cfg.kbDev);

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
        'This smoke test will run 5 trials at fixed duration (no staircases).\n' ...
    ];

    Screen('FillRect', window, bg);

    Screen('TextSize', window, tcfg.titleSize);
    Screen('TextStyle', window, 1);
    DrawFormattedText(window, titleTrialOverview, 'center', windowRect(4) * tcfg.trialOverviewTitleY, black);
    Screen('TextStyle', window, 0);
    Screen('TextSize', window, tcfg.bodySize);
    [~, ~, topBounds] = DrawFormattedText(window, topText, 'center', windowRect(4) * tcfg.trialOverviewTopY, black, tcfg.bodyWrap, [], [], tcfg.bodyLineSpacing);
    topBottomY = topBounds(4);

    [xc, ~] = RectCenter(windowRect);
    imgW = size(img, 2);
    imgH = size(img, 1);

    reserveBottomPx = tcfg.trialOverviewReserveBottomPx;
    maxW = windowRect(3) * 0.90;
    maxH = (windowRect(4) - topBottomY - reserveBottomPx) * 0.95;
    maxH = max(maxH, 50);
    pngScaleMult = 0.80;

    scale = min(maxW / imgW, maxH / imgH) * pngScaleMult;
    dstW = imgW * scale;
    dstH = imgH * scale;

    imgTopY = topBottomY + 20;
    dstRect = CenterRectOnPoint([0 0 dstW dstH], xc, imgTopY + dstH / 2);

    Screen('DrawTexture', window, tex, [], dstRect);

    Screen('TextSize', window, tcfg.bodySize);
    bottomY = dstRect(4) + 30;
    DrawFormattedText(window, bottomText, 'center', bottomY, black, tcfg.bodyWrap, [], [], tcfg.bodyLineSpacing);

    promptY = windowRect(4) * tcfg.promptYFrac;
    Screen('TextSize', window, tcfg.promptSize);
    DrawFormattedText(window, 'Press SPACEBAR to continue.', 'center', promptY, greyText);

    sendTrigger(cfg.trigger, cfg.eeg.codes.smoke.overviewGrey);
    drawViewPixxPixelIfNeeded(window, cfg, cfg.eeg.codes.smoke.overviewGrey);
    tOn = Screen('Flip', window);

    KbQueueFlush(cfg.kbDev);
    holdForSecondsWithAbort(tOn + lockSec, cfg);
    KbQueueFlush(cfg.kbDev);

    Screen('FillRect', window, bg);
    Screen('TextSize', window, tcfg.titleSize);
    Screen('TextStyle', window, 1);
    DrawFormattedText(window, titleTrialOverview, 'center', windowRect(4) * tcfg.trialOverviewTitleY, black);
    Screen('TextStyle', window, 0);
    Screen('TextSize', window, tcfg.bodySize);
    [~, ~, topBounds] = DrawFormattedText(window, topText, 'center', windowRect(4) * tcfg.trialOverviewTopY, black, tcfg.bodyWrap, [], [], tcfg.bodyLineSpacing);
    topBottomY = topBounds(4);

    imgTopY = topBottomY + 20;
    dstRect = CenterRectOnPoint([0 0 dstW dstH], xc, imgTopY + dstH / 2);
    Screen('DrawTexture', window, tex, [], dstRect);

    Screen('TextSize', window, tcfg.bodySize);
    bottomY = dstRect(4) + 30;
    DrawFormattedText(window, bottomText, 'center', bottomY, black, tcfg.bodyWrap, [], [], tcfg.bodyLineSpacing);

    Screen('TextSize', window, tcfg.promptSize);
    DrawFormattedText(window, 'Press SPACEBAR to continue.', 'center', promptY, black);

    sendTrigger(cfg.trigger, cfg.eeg.codes.smoke.overviewActive);
    drawViewPixxPixelIfNeeded(window, cfg, cfg.eeg.codes.smoke.overviewActive);
    Screen('Flip', window);

    KbQueueFlush(cfg.kbDev);
    waitForKeyQueue([cfg.keys.space], cfg.keys.escape, Inf, cfg);

    sendTrigger(cfg.trigger, cfg.eeg.codes.smoke.overviewSpace);
    parallelEchoFlip(window, cfg, cfg.eeg.codes.smoke.overviewSpace, xCentre, yCentre, ...
        fixationCoords, cfg.fix.lineWidthPx, black, bg);

    Screen('Close', tex);
end

function cleanupSmokeTest(cfg)
    try ListenChar(0); catch, end
    try Priority(0); catch, end
    try KbQueueRelease(cfg.kbDev); catch, end
    try viewpixxPixelModeShutdown(cfg); catch, end
    try closeSerialTrigger(cfg); catch, end
    try ShowCursor; catch, end
    if exist('sca', 'file') == 2
        sca;
    elseif exist('Screen', 'file') == 2
        Screen('CloseAll');
    end
end

function checkAbort(cfg)
    [pressed, firstPress] = KbQueueCheck(cfg.kbDev);
    if pressed && firstPress(cfg.keys.escape) > 0
        error('Experiment terminated by user (ESC).');
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

function trigger = initSerialTrigger(eegCfg)
    trigger = struct('enabled', false, 'handle', [], 'pulseWidthSec', 0, ...
        'sendResetAfterCode', false, 'warnOnSendError', true);

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

function closeSerialTrigger(cfg)
    try
        if isfield(cfg, 'trigger') && isfield(cfg.trigger, 'enabled') && cfg.trigger.enabled && ...
                isfield(cfg.trigger, 'handle') && ~isempty(cfg.trigger.handle)
            IOPort('Close', cfg.trigger.handle);
        end
    catch
    end
end

function txt = mExceptionText(ME)
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

function cfg = viewpixxInitPixelMode(cfg)
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
        fprintf('ViewPixx Pixel Mode ENABLED (smoke test; R uses minRNorm floor for pixel only).\n');
    catch ME
        warning('ViewPixx Pixel Mode init failed: %s. Continuing without pixel markers.', mExceptionText(ME));
        try Datapixx('Close'); catch, end
        cfg.viewpixx.datapixxOpen = false;
        cfg.viewpixx.pixelModeEnabled = false;
    end
end

function drawViewPixxPixelIfNeeded(window, cfg, code)
    if ~isfield(cfg, 'viewpixx') || ~isfield(cfg.viewpixx, 'pixelModeEnabled') || ...
            ~cfg.viewpixx.pixelModeEnabled
        return;
    end
    if nargin < 3 || isnan(code) || code < 0 || code > 255
        return;
    end
    r = double(code) / 255;
    if isfield(cfg.viewpixx, 'minRNorm') && ~isempty(cfg.viewpixx.minRNorm)
        r = max(r, cfg.viewpixx.minRNorm);
    end
    rgb = [r, 0, 0];
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

function geom = computeDisplayGeometry(displayCfg, windowRect)
    geom = struct();
    activeWidthPx = windowRect(3) - windowRect(1);
    if isfield(displayCfg, 'screenWidthPx') && displayCfg.screenWidthPx > 0
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

function d = keyToDigit(keyCode)
    if isnan(keyCode), d = NaN; return; end
    name = KbName(keyCode);
    if iscell(name), name = name{1}; end
    d = str2double(name(1));
end

function tex = makeGratingTexture(window, sz, cyclesPerStim, contrast, bg, gaborSigmaFrac)
    if nargin < 6 || isempty(gaborSigmaFrac)
        gaborSigmaFrac = 0.40;
    end
    [xRad, ~] = meshgrid(linspace(-pi, pi, sz), linspace(-pi, pi, sz));
    carrier = sin(cyclesPerStim * xRad);
    [xPix, yPix] = meshgrid(1:sz, 1:sz);
    xPix = xPix - (sz + 1) / 2;
    yPix = yPix - (sz + 1) / 2;
    radius = (sz / 2 - 1);
    sigma  = max(1, radius * gaborSigmaFrac);
    envelope = exp(-(xPix.^2 + yPix.^2) / (2 * sigma^2));
    img = bg + (contrast * 0.5) * (envelope .* carrier);
    img = min(max(img, 0), 1);
    alpha = min(max(envelope, 0), 1);
    rgb  = uint8(img * 255);
    a    = uint8(alpha * 255);
    rgba = cat(3, rgb, rgb, rgb, a);
    tex = Screen('MakeTexture', window, rgba);
end

function drawGratings(window, tex, allRects, orientations, bg)
    Screen('FillRect', window, bg);
    for i = 1:4
        Screen('DrawTexture', window, tex, [], allRects(i, :), orientations(i));
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
    [xc, yc] = RectCenter(windowRect);
    w = windowRect(3) - windowRect(1);
    h = windowRect(4) - windowRect(2);
    minDim = min(w, h);

    margin = round(minDim * qcfg.quadOuterMarginFrac);
    topReserve = round(h * qcfg.quadTopReserveFrac);
    bottomReserve = round(h * qcfg.quadBottomReserveFrac);

    gap = round(minDim * qcfg.quadGapFrac);
    boxDesired = round(minDim * qcfg.quadBoxFrac);

    maxBoxByWidth = floor((w - 2 * margin - gap) / 2);
    maxBoxByHeightTop = floor(yc - (windowRect(2) + topReserve) - gap / 2);
    maxBoxByHeightBottom = floor((windowRect(4) - bottomReserve) - yc - gap / 2);
    maxBoxByHeight = min(maxBoxByHeightTop, maxBoxByHeightBottom);
    box = max(60, min([boxDesired, maxBoxByWidth, maxBoxByHeight]));

    if box < 60
        box = 60;
        gap = max(30, min(gap, round(minDim * 0.06)));
    end

    half = box / 2;
    offset = half + gap / 2;

    quadRects = [ ...
        xc - offset - half, yc - offset - half, xc - gap / 2,         yc - gap / 2; ...
        xc + gap / 2,         yc - offset - half, xc + offset + half, yc - gap / 2; ...
        xc - offset - half, yc + gap / 2,         xc - gap / 2,         yc + offset + half; ...
        xc + gap / 2,         yc + gap / 2,         xc + offset + half, yc + offset + half ...
        ];

    for i = 1:4
        Screen('FrameRect', window, colour, quadRects(i, :), qcfg.quadFrameWidthPx);
        [cx, cy] = RectCenter(quadRects(i, :));
        Screen('TextSize', window, qcfg.quadNumberSize);
        nb = Screen('TextBounds', window, num2str(i));
        xNum = cx - (nb(3) - nb(1)) / 2;
        yNum = cy - (nb(4) - nb(2)) / 2;
        DrawFormattedText(window, num2str(i), xNum, yNum, colour);
    end

    Screen('TextSize', window, qcfg.quadPromptSize);
    quadTop = yc - (offset + half);
    promptY = max(windowRect(2) + round(h * 0.03), quadTop - round(h * qcfg.quadPromptYOffsetFrac));
    DrawFormattedText(window, promptText, 'center', promptY, colour, qcfg.quadPromptWrap);
end

function drawPAS(window, windowRect, colour, bg, cfg)
    Screen('FillRect', window, bg);
    [~, yc] = RectCenter(windowRect);
    w = windowRect(3) - windowRect(1);
    h = windowRect(4) - windowRect(2);
    qcfg = cfg.display.text.questions;

    Screen('TextSize', window, qcfg.pasQuestionSize);
    DrawFormattedText(window, 'How clearly did you see the change?', 'center', yc - round(h * qcfg.pasQuestionYOffsetFrac), colour, qcfg.pasQuestionWrap);

    nums = {'1', '2', '3', '4'};
    desc = { ...
        'I didn''t experience a change', ...
        'I felt like there was a change', ...
        'I saw something change', ...
        'I clearly saw the change' ...
        };
    labels = { ...
        '(No experience)', ...
        '(Brief experience)', ...
        '(Almost clear experience)', ...
        '(Clear experience)' ...
        };

    sideMargin = round(w * qcfg.pasSideMarginFrac);
    n  = numel(nums);
    xs = linspace(windowRect(1) + sideMargin, windowRect(3) - sideMargin, n);

    yNum      = yc + round(h * qcfg.pasNumYOffsetFrac);
    yDescTop  = yNum + round(h * qcfg.pasDescTopGapFrac);

    numSize    = qcfg.pasNumberSize;
    textSize   = qcfg.pasDescSize;
    labelSize  = qcfg.pasLabelSize;
    lineStep   = round(h * qcfg.pasLineStepFrac);
    labelGap   = round(h * qcfg.pasLabelGapFrac);

    for i = 1:n
        Screen('TextSize', window, numSize);
        nb = Screen('TextBounds', window, nums{i});
        xNum = xs(i) - (nb(3) - nb(1)) / 2;
        DrawFormattedText(window, nums{i}, xNum, yNum, colour);

        Screen('TextSize', window, textSize);
        lines = strsplit(desc{i}, '\n');

        yLine = yDescTop;
        for L = 1:numel(lines)
            lb = Screen('TextBounds', window, lines{L});
            xLine = xs(i) - (lb(3) - lb(1)) / 2;
            DrawFormattedText(window, lines{L}, xLine, yLine, colour);
            yLine = yLine + lineStep;
        end

        Screen('TextSize', window, labelSize);
        lab = labels{i};
        bb = Screen('TextBounds', window, lab);
        xLab = xs(i) - (bb(3) - bb(1)) / 2;
        yLab = yLine + labelGap;
        DrawFormattedText(window, lab, xLab, yLab, colour);
    end
end

function oriS1 = makeOriS1_noPostChangeDup(changeQuad, startOri, allowedOri)
    allowedOri = allowedOri(:)';
    if isempty(startOri) || ~isfinite(startOri)
        startOri = allowedOri(randi(numel(allowedOri)));
    else
        [~, idx] = min(abs(allowedOri - startOri));
        startOri = allowedOri(idx);
    end
    changedOri = mod(startOri + 90, 180);
    tol = 1e-6;
    keep = ~ismembertol(allowedOri, [startOri changedOri], tol);
    rem = allowedOri(keep);

    if numel(rem) < 3
        error('Need at least 5 allowed orientations to avoid duplicates after change.');
    end

    rem = rem(randperm(numel(rem), 3));

    oriS1 = nan(4, 1);
    oriS1(changeQuad) = startOri;
    otherIdx = setdiff(1:4, changeQuad);
    oriS1(otherIdx) = rem(:);
end

function displayCfg = makeDisplayProfile(profileName)
    name = lower(strtrim(profileName));

    switch name
        case 'viewpixx'
            displayCfg = struct();
            displayCfg.profile = 'viewpixx';
            displayCfg.viewDistanceCm = 60;
            displayCfg.screenWidthCm = 53.1;
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
