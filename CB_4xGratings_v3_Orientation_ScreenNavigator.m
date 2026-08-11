function CB_4xGratings_v3_Orientation_ScreenNavigator(mode)
%% ORIENTATION PARTICIPANT-SCREEN NAVIGATOR
% IMPORTANT: This preview utility and its PNG assets are independent copies.
% Changes made here do not propagate to CB_4xGratings_v3_Orientation.m,
% and changes made in the experiment do not propagate back here.
%
% Usage:
%   CB_4xGratings_v3_Orientation_ScreenNavigator
%       Fullscreen ViewPixx preview on Psychtoolbox screen 2.
%
%   CB_4xGratings_v3_Orientation_ScreenNavigator('windowed')
%       1280 x 720 development preview.
%
% Controls:
%   Right / Left arrows  next / previous page
%   Up / Down arrows     next / previous variant
%   Home / End           first / last page
%   A                    active / grey SPACEBAR prompt
%   H                    show / hide operator overlay
%   S                    save a clean screenshot
%   Escape               close safely
%
% This file contains participant-screen previews only. It does not initialise
% experimental hardware, generate trials, or collect participant responses.

if nargin < 1 || isempty(mode)
    mode = 'fullscreen';
end

if isstring(mode)
    if ~isscalar(mode)
        error('CB_4xGratings_v3_Orientation_ScreenNavigator:InvalidMode', ...
            'Mode must be ''fullscreen'' or ''windowed''.');
    end
    mode = char(mode);
end
if ~ischar(mode)
    error('CB_4xGratings_v3_Orientation_ScreenNavigator:InvalidMode', ...
        'Mode must be ''fullscreen'' or ''windowed''.');
end

mode = lower(strtrim(mode));
if ~ismember(mode, {'fullscreen', 'windowed'})
    error('CB_4xGratings_v3_Orientation_ScreenNavigator:InvalidMode', ...
        'Unknown mode ''%s''. Use ''fullscreen'' or ''windowed''.', mode);
end

% Clear stale Psychtoolbox keyboard/display state before creating this preview.
try
    ListenChar(0);
catch
end
try
    KbQueueRelease(-1);
catch
end
if exist('Screen', 'file') == 2
    try
        Screen('CloseAll');
    catch
    end
end

try
    PsychDefaultSetup(2);
catch ME
    error('CB_4xGratings_v3_Orientation_ScreenNavigator:MissingPsychtoolbox', ...
        'Psychtoolbox could not be initialised: %s', ME.message);
end
KbName('UnifyKeyNames');

cfg = makeNavigatorConfig(mode);

oldPriority = 0;
try
    oldPriority = Priority;
catch
end
oldVisualDebugLevel = Screen('Preference', 'VisualDebugLevel');
oldSkipSyncTests = Screen('Preference', 'SkipSyncTests');
cleanupObj = onCleanup(@() cleanupNavigator( ...
    cfg.kbDev, oldPriority, oldVisualDebugLevel, oldSkipSyncTests));

availableScreens = Screen('Screens');
if strcmp(mode, 'fullscreen')
    if ~any(availableScreens == cfg.preview.fullscreenScreenNumber)
        error('CB_4xGratings_v3_Orientation_ScreenNavigator:ScreenUnavailable', ...
            ['Fullscreen preview requires Psychtoolbox screen %d, but the ' ...
             'available screens are %s. Connect/enable the ViewPixx or use ' ...
             'the ''windowed'' mode.'], ...
            cfg.preview.fullscreenScreenNumber, mat2str(availableScreens));
    end
    cfg.screenNumber = cfg.preview.fullscreenScreenNumber;
else
    cfg.screenNumber = min(availableScreens);
end

Screen('Preference', 'VisualDebugLevel', cfg.visualDebugLevel);
Screen('Preference', 'SkipSyncTests', cfg.skipSyncTests);

if strcmp(mode, 'windowed')
    [window, windowRect] = PsychImaging('OpenWindow', cfg.screenNumber, ...
        cfg.backgroundGrey, cfg.preview.windowRect);
else
    [window, windowRect] = PsychImaging('OpenWindow', cfg.screenNumber, ...
        cfg.backgroundGrey);
end

Screen('BlendFunction', window, 'GL_SRC_ALPHA', 'GL_ONE_MINUS_SRC_ALPHA');
Screen('TextFont', window, 'Arial');
Screen('TextStyle', window, 0);
HideCursor;
% Keep ListenChar disabled while the Psychtoolbox keyboard queue is active.
ListenChar(0);

if strcmp(mode, 'windowed')
    referenceWidth = cfg.preview.referenceResolution(1);
    referenceHeight = cfg.preview.referenceResolution(2);
    cfg.preview.layoutScale = min( ...
        RectWidth(windowRect) / referenceWidth, ...
        RectHeight(windowRect) / referenceHeight);
    cfg.display.text = scaleViewpixxTextConfig( ...
        cfg.display.text, cfg.preview.layoutScale);
else
    cfg.preview.layoutScale = 1;
end

resources = loadNavigatorResources(window, windowRect, cfg);
pages = makeScreenCatalogue(cfg);
keys = makeNavigatorKeys;
createNavigatorQueue(cfg.kbDev, keys);

state = struct();
state.pageIndex = 1;
state.variantIndices = ones(1, numel(pages));
state.promptActive = true;
state.overlayVisible = false;

fprintf('\nOrientation Screen Navigator (%s)\n', mode);
fprintf('Independent source: %s\n', mfilename('fullpath'));
fprintf('Initial instructions (active): %s\n', ...
    cfg.preview.initialInstructionsActivePath);
fprintf('Initial instructions (grey): %s\n', ...
    cfg.preview.initialInstructionsGreyPath);
fprintf('Trial overview (active): %s\n', ...
    cfg.preview.trialOverviewActivePath);
fprintf('Trial overview (grey): %s\n', ...
    cfg.preview.trialOverviewGreyPath);
fprintf('Practice Block 1 information (active): %s\n', ...
    cfg.preview.practice1InformationActivePath);
fprintf('Practice Block 1 information (grey): %s\n', ...
    cfg.preview.practice1InformationGreyPath);
fprintf('Practice Block 2 information (active): %s\n', ...
    cfg.preview.practice2InformationActivePath);
fprintf('Practice Block 2 information (grey): %s\n', ...
    cfg.preview.practice2InformationGreyPath);
fprintf('Experiment information (active): %s\n', ...
    cfg.preview.experimentInformationActivePath);
fprintf('Experiment information (grey): %s\n', ...
    cfg.preview.experimentInformationGreyPath);
fprintf(['Controls: LEFT/RIGHT pages | UP/DOWN variants | HOME/END | ' ...
    'A prompt | H overlay | S screenshot | ESC exit\n\n']);

drawNavigatorFrame(window, windowRect, cfg, resources, pages, state);
printNavigatorState('Opened', pages, state);
KbQueueFlush(cfg.kbDev);

% Developer-only render audit used by automated verification. Normal use is
% unaffected because the environment variable is unset.
if strcmp(getenv('CB_ORIENTATION_NAVIGATOR_RENDER_AUDIT'), '1')
    renderedFrames = runAutomatedRenderAudit( ...
        window, windowRect, cfg, resources, pages, state);
    fprintf('RENDER_AUDIT_COMPLETE frames=%d pages=%d\n', ...
        renderedFrames, numel(pages));
    if strcmp(getenv('CB_ORIENTATION_NAVIGATOR_SCREENSHOT_AUDIT'), '1')
        auditScreenshotPath = saveCleanScreenshot( ...
            window, windowRect, cfg, resources, pages, state);
        fprintf('SCREENSHOT_AUDIT_COMPLETE path=%s\n', auditScreenshotPath);
    end
    clear cleanupObj;
    return;
end

running = true;
while running
    [pressed, firstPress] = KbQueueCheck(cfg.kbDev);
    if ~pressed
        WaitSecs(0.01);
        continue;
    end

    keyCode = earliestNavigatorKey(firstPress, keys.allCodes);
    if isnan(keyCode)
        KbQueueFlush(cfg.kbDev);
        continue;
    end

    redrawNeeded = false;
    actionText = '';

    if keyCode == keys.escape
        actionText = 'Escape';
        running = false;

    elseif keyCode == keys.right
        state.pageIndex = mod(state.pageIndex, numel(pages)) + 1;
        redrawNeeded = true;
        actionText = 'Next page';

    elseif keyCode == keys.left
        state.pageIndex = mod(state.pageIndex - 2, numel(pages)) + 1;
        redrawNeeded = true;
        actionText = 'Previous page';

    elseif keyCode == keys.home
        state.pageIndex = 1;
        redrawNeeded = true;
        actionText = 'First page';

    elseif keyCode == keys.endKey
        state.pageIndex = numel(pages);
        redrawNeeded = true;
        actionText = 'Last page';

    elseif keyCode == keys.up || keyCode == keys.down
        page = pages(state.pageIndex);
        nVariants = numel(page.variants);
        if nVariants > 1
            currentVariant = state.variantIndices(state.pageIndex);
            if keyCode == keys.up
                currentVariant = mod(currentVariant, nVariants) + 1;
                actionText = 'Next variant';
            else
                currentVariant = mod(currentVariant - 2, nVariants) + 1;
                actionText = 'Previous variant';
            end
            state.variantIndices(state.pageIndex) = currentVariant;
            redrawNeeded = true;
        else
            actionText = 'Variant change not applicable';
        end

    elseif keyCode == keys.togglePrompt
        if pages(state.pageIndex).supportsPromptToggle
            state.promptActive = ~state.promptActive;
            redrawNeeded = true;
            actionText = 'Prompt toggled';
        else
            actionText = 'Prompt toggle not applicable';
        end

    elseif keyCode == keys.toggleOverlay
        state.overlayVisible = ~state.overlayVisible;
        redrawNeeded = true;
        actionText = 'Overlay toggled';

    elseif keyCode == keys.screenshot
        screenshotPath = saveCleanScreenshot( ...
            window, windowRect, cfg, resources, pages, state);
        fprintf('Saved clean screenshot: %s\n', screenshotPath);
        actionText = 'Screenshot saved';
    end

    KbQueueFlush(cfg.kbDev);
    KbReleaseWait(cfg.kbDev);

    if redrawNeeded
        drawNavigatorFrame(window, windowRect, cfg, resources, pages, state);
    end

    printNavigatorState(actionText, pages, state);
end

clear cleanupObj;
fprintf('Orientation Screen Navigator closed safely.\n');
end

%% ======================== PREVIEW CONFIGURATION ========================

function cfg = makeNavigatorConfig(mode)
% Independent copy of the orientation task's ViewPixx participant-screen settings.

cfg = struct();
cfg.mode = mode;
cfg.kbDev = -1;
cfg.backgroundGrey = 0.5;
cfg.black = 0;
cfg.visualDebugLevel = 1;
cfg.skipSyncTests = double(strcmp(mode, 'windowed'));

cfg.preview = struct();
cfg.preview.fullscreenScreenNumber = 2;
cfg.preview.windowRect = [100 100 1380 820]; % 1280 x 720 client area
cfg.preview.referenceResolution = [1920 1080];
cfg.preview.layoutScale = 1;

% Edit this value to preview another run profile. Break examples are derived
% automatically and are 1, 3, and 5 when totalBlocks is 6.
cfg.preview.totalBlocks = 6;
if ~isscalar(cfg.preview.totalBlocks) || ...
        ~isfinite(cfg.preview.totalBlocks) || ...
        cfg.preview.totalBlocks < 2 || ...
        cfg.preview.totalBlocks ~= round(cfg.preview.totalBlocks)
    error('CB_4xGratings_v3_Orientation_ScreenNavigator:InvalidBlockTotal', ...
        'cfg.preview.totalBlocks must be an integer of at least 2.');
end
lastCompletedBlock = cfg.preview.totalBlocks - 1;
nBreakExamples = min(3, lastCompletedBlock);
cfg.preview.blockExamples = unique(round(linspace( ...
    1, lastCompletedBlock, nBreakExamples)), 'stable');

navigatorPath = mfilename('fullpath');
cfg.preview.navigatorDir = fileparts(navigatorPath);
cfg.preview.instructionAssetsDir = fullfile( ...
    cfg.preview.navigatorDir, 'Instruction Assets');
cfg.preview.initialInstructionsActiveFilename = ...
    'InitialInstructions_active.png';
cfg.preview.initialInstructionsGreyFilename = ...
    'InitialInstructions_grey.png';
cfg.preview.initialInstructionsActivePath = fullfile( ...
    cfg.preview.instructionAssetsDir, ...
    cfg.preview.initialInstructionsActiveFilename);
cfg.preview.initialInstructionsGreyPath = fullfile( ...
    cfg.preview.instructionAssetsDir, ...
    cfg.preview.initialInstructionsGreyFilename);
cfg.preview.trialOverviewActiveFilename = ...
    'TrialOverview_active.png';
cfg.preview.trialOverviewGreyFilename = ...
    'TrialOverview_grey.png';
cfg.preview.trialOverviewActivePath = fullfile( ...
    cfg.preview.instructionAssetsDir, ...
    cfg.preview.trialOverviewActiveFilename);
cfg.preview.trialOverviewGreyPath = fullfile( ...
    cfg.preview.instructionAssetsDir, ...
    cfg.preview.trialOverviewGreyFilename);
cfg.preview.practice1InformationActiveFilename = ...
    'Practice1Information_active.png';
cfg.preview.practice1InformationGreyFilename = ...
    'Practice1Information_grey.png';
cfg.preview.practice1InformationActivePath = fullfile( ...
    cfg.preview.instructionAssetsDir, ...
    cfg.preview.practice1InformationActiveFilename);
cfg.preview.practice1InformationGreyPath = fullfile( ...
    cfg.preview.instructionAssetsDir, ...
    cfg.preview.practice1InformationGreyFilename);
cfg.preview.practice2InformationActiveFilename = ...
    'Practice2Information_active.png';
cfg.preview.practice2InformationGreyFilename = ...
    'Practice2Information_grey.png';
cfg.preview.practice2InformationActivePath = fullfile( ...
    cfg.preview.instructionAssetsDir, ...
    cfg.preview.practice2InformationActiveFilename);
cfg.preview.practice2InformationGreyPath = fullfile( ...
    cfg.preview.instructionAssetsDir, ...
    cfg.preview.practice2InformationGreyFilename);
cfg.preview.experimentInformationActiveFilename = ...
    'ExperimentInformation_active.png';
cfg.preview.experimentInformationGreyFilename = ...
    'ExperimentInformation_grey.png';
cfg.preview.experimentInformationActivePath = fullfile( ...
    cfg.preview.instructionAssetsDir, ...
    cfg.preview.experimentInformationActiveFilename);
cfg.preview.experimentInformationGreyPath = fullfile( ...
    cfg.preview.instructionAssetsDir, ...
    cfg.preview.experimentInformationGreyFilename);
cfg.preview.screenshotDir = fullfile( ...
    cfg.preview.navigatorDir, 'ScreenPreview_Screenshots');

cfg.display = makeViewpixxPreviewProfile;
end

function displayCfg = makeViewpixxPreviewProfile
% Source counterpart: makeDisplayProfile('viewpixx').

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
end

function textCfg = scaleViewpixxTextConfig(textCfg, scale)
% Windowed preview only: scale ViewPixx pixel/font values proportionally.

textCfg.titleSize = scaledInteger(textCfg.titleSize, scale, 1);
textCfg.bodySize = scaledInteger(textCfg.bodySize, scale, 1);
textCfg.promptSize = scaledInteger(textCfg.promptSize, scale, 1);

qCfg = textCfg.questions;
qCfg.quadFrameWidthPx = scaledInteger(qCfg.quadFrameWidthPx, scale, 1);
qCfg.quadNumberSize = scaledInteger(qCfg.quadNumberSize, scale, 1);
qCfg.quadPromptSize = scaledInteger(qCfg.quadPromptSize, scale, 1);
qCfg.pasQuestionSize = scaledInteger(qCfg.pasQuestionSize, scale, 1);
qCfg.pasNumberSize = scaledInteger(qCfg.pasNumberSize, scale, 1);
qCfg.pasDescSize = scaledInteger(qCfg.pasDescSize, scale, 1);
qCfg.pasLabelSize = scaledInteger(qCfg.pasLabelSize, scale, 1);
textCfg.questions = qCfg;

fbCfg = textCfg.feedback;
fbCfg.textSize = scaledInteger(fbCfg.textSize, scale, 1);
fbCfg.promptSize = scaledInteger(fbCfg.promptSize, scale, 1);
textCfg.feedback = fbCfg;
end

function value = scaledInteger(referenceValue, scale, minimumValue)
value = max(minimumValue, round(referenceValue * scale));
end

%% =========================== SCREEN CATALOGUE ===========================

function pages = makeScreenCatalogue(cfg)
defaultVariant = makeVariant('default', 'Default', []);

feedbackVariants = [ ...
    makeVariant('nice', 'Nice / correct localisation', 'nice'), ...
    makeVariant('close', 'Close / incorrect localisation', 'close'), ...
    makeVariant('missed', 'Missed change', 'missed'), ...
    makeVariant('false_alarm', 'False alarm', 'false_alarm'), ...
    makeVariant('correct_rejection', 'Correct rejection', 'correct_rejection') ...
    ];

blockVariants = repmat(defaultVariant, 1, numel(cfg.preview.blockExamples));
for ii = 1:numel(cfg.preview.blockExamples)
    blockNumber = cfg.preview.blockExamples(ii);
    blockVariants(ii) = makeVariant( ...
        sprintf('block_%d_of_%d', blockNumber, cfg.preview.totalBlocks), ...
        sprintf('Block %d of %d', blockNumber, cfg.preview.totalBlocks), ...
        blockNumber);
end

pages = [ ...
    makePage('initial_instructions', 'Initial instructions', ...
        'initial_instructions', true, defaultVariant), ...
    makePage('trial_overview', 'Trial overview', ...
        'trial_overview', true, defaultVariant), ...
    makePage('practice_1_introduction', 'Practice Block 1 introduction', ...
        'practice_1_introduction', true, defaultVariant), ...
    makePage('practice_1_begin', 'Practice Block 1 begin', ...
        'ready_to_begin', false, defaultVariant), ...
    makePage('pas_question', 'PAS question', ...
        'pas_question', false, defaultVariant), ...
    makePage('localisation_aware', 'Localisation after PAS 2-4', ...
        'localisation_aware', false, defaultVariant), ...
    makePage('localisation_best_guess', 'Best-guess localisation after PAS 1', ...
        'localisation_best_guess', false, defaultVariant), ...
    makePage('practice_feedback', 'Practice feedback', ...
        'practice_feedback', false, feedbackVariants), ...
    makePage('practice_2_introduction', 'Practice Block 2 introduction', ...
        'practice_2_introduction', true, defaultVariant), ...
    makePage('practice_2_begin', 'Practice Block 2 begin', ...
        'ready_to_begin', false, defaultVariant), ...
    makePage('main_run_introduction', 'Main-run introduction', ...
        'main_run_introduction', true, defaultVariant), ...
    makePage('main_run_begin', 'Main-run begin', ...
        'ready_to_begin', false, defaultVariant), ...
    makePage('block_break', 'Block break', ...
        'block_break', true, blockVariants), ...
    makePage('block_resume', 'Block-resume screen', ...
        'ready_to_begin', false, defaultVariant), ...
    makePage('completion', 'Completion screen', ...
        'completion', false, defaultVariant) ...
    ];
end

function page = makePage(id, name, renderer, supportsPromptToggle, variants)
page = struct( ...
    'id', id, ...
    'name', name, ...
    'renderer', renderer, ...
    'supportsPromptToggle', supportsPromptToggle, ...
    'variants', variants);
end

function variant = makeVariant(id, label, value)
variant = struct('id', id, 'label', label, 'value', value);
end

%% ====================== PARTICIPANT-SCREEN RENDERING ======================

function drawNavigatorFrame(window, windowRect, cfg, resources, pages, state)
page = pages(state.pageIndex);
variantIndex = state.variantIndices(state.pageIndex);
variant = page.variants(variantIndex);

renderParticipantPage( ...
    window, windowRect, cfg, resources, page, variant, state.promptActive);

if state.overlayVisible
    drawOperatorOverlay(window, windowRect, cfg, pages, state);
end

Screen('DrawingFinished', window);
Screen('Flip', window);
end

function renderParticipantPage( ...
        window, windowRect, cfg, resources, page, variant, promptActive)

Screen('FillRect', window, cfg.backgroundGrey);
Screen('TextFont', window, 'Arial');
Screen('TextStyle', window, 0);

switch page.renderer
    case 'initial_instructions'
        if promptActive
            instructionTexture = ...
                resources.initialInstructionsTextures.active;
        else
            instructionTexture = ...
                resources.initialInstructionsTextures.grey;
        end
        Screen('DrawTexture', window, instructionTexture, [], windowRect);

    case 'trial_overview'
        if promptActive
            trialOverviewTexture = ...
                resources.trialOverviewTextures.active;
        else
            trialOverviewTexture = ...
                resources.trialOverviewTextures.grey;
        end
        Screen('DrawTexture', window, trialOverviewTexture, [], windowRect);

    case 'practice_1_introduction'
        if promptActive
            practice1InformationTexture = ...
                resources.practice1InformationTextures.active;
        else
            practice1InformationTexture = ...
                resources.practice1InformationTextures.grey;
        end
        Screen('DrawTexture', window, ...
            practice1InformationTexture, [], windowRect);

    case 'ready_to_begin'
        renderReadyToBegin(window, windowRect, cfg);

    case 'pas_question'
        Screen('DrawTexture', window, resources.questionTextures.PAS);

    case 'localisation_aware'
        Screen('DrawTexture', window, resources.questionTextures.Loc_default);

    case 'localisation_best_guess'
        Screen('DrawTexture', window, resources.questionTextures.Loc_pas1);

    case 'practice_feedback'
        renderPracticeFeedback(window, windowRect, cfg, variant.value);

    case 'practice_2_introduction'
        if promptActive
            practice2InformationTexture = ...
                resources.practice2InformationTextures.active;
        else
            practice2InformationTexture = ...
                resources.practice2InformationTextures.grey;
        end
        Screen('DrawTexture', window, ...
            practice2InformationTexture, [], windowRect);

    case 'main_run_introduction'
        if promptActive
            experimentInformationTexture = ...
                resources.experimentInformationTextures.active;
        else
            experimentInformationTexture = ...
                resources.experimentInformationTextures.grey;
        end
        Screen('DrawTexture', window, ...
            experimentInformationTexture, [], windowRect);

    case 'block_break'
        renderBlockBreak( ...
            window, windowRect, cfg, variant.value, promptActive);

    case 'completion'
        renderCompletion(window, cfg);

    otherwise
        error('CB_4xGratings_v3_Orientation_ScreenNavigator:UnknownRenderer', ...
            'Unknown participant-screen renderer ''%s''.', page.renderer);
end
end

function renderReadyToBegin(window, windowRect, cfg)
% Source counterpart: showPressSpaceToBeginScreen. The catalogue deliberately
% keeps each experiment occurrence as a separate page.

tcfg = cfg.display.text;
titleText = 'When you are ready press SPACEBAR to begin';
reminderText = ...
    'Remember: please keep your eyes on the centre cross during each trial';
[~, yCentre] = RectCenter(windowRect);

Screen('TextSize', window, tcfg.titleSize);
Screen('TextStyle', window, 1);
[~, nextY] = DrawFormattedText(window, titleText, 'center', ...
    yCentre - round(RectHeight(windowRect) * 0.06), ...
    cfg.black, tcfg.bodyWrap);
Screen('TextStyle', window, 0);
Screen('TextSize', window, tcfg.bodySize);
DrawFormattedText(window, reminderText, 'center', ...
    nextY + round(RectHeight(windowRect) * 0.06), ...
    cfg.black, tcfg.bodyWrap);
end

function renderBlockBreak( ...
        window, windowRect, cfg, blockJustFinished, promptActive)
% Source counterpart: showBlockBreakScreen.

tcfg = cfg.display.text;
titleText = sprintf('Block %d of %d complete', ...
    blockJustFinished, cfg.preview.totalBlocks);
bodyText = [ ...
    'Nice work!\n\n' ...
    'Please take a moment to rest your eyes and relax your hands and shoulders.\nThe next block will not begin until you press SPACEBAR.\n\n' ...
    'If you would like a longer break, a sip of water, or a seated stretch, please let the researcher know.' ...
    ];

[~, yCentre] = RectCenter(windowRect);
titleY = yCentre - round(RectHeight(windowRect) * 0.18);
bodyGap = round(RectHeight(windowRect) * 0.045);

Screen('TextSize', window, tcfg.titleSize);
Screen('TextStyle', window, 1);
[~, titleBottom] = DrawFormattedText(window, titleText, ...
    'center', titleY, cfg.black, tcfg.bodyWrap);
Screen('TextSize', window, tcfg.bodySize);
Screen('TextStyle', window, 0);
DrawFormattedText(window, bodyText, 'center', titleBottom + bodyGap, ...
    cfg.black, tcfg.bodyWrap, [], [], tcfg.bodyLineSpacing);
drawContinuePrompt(window, windowRect, cfg, promptActive);
end

function renderPracticeFeedback(window, windowRect, cfg, feedbackVariant)
% Source counterpart: practice-feedback construction and drawing section.

switch feedbackVariant
    case 'nice'
        feedbackText = ...
            'Nice.\n\nYou detected the change\nand localised it correctly.';
    case 'close'
        feedbackText = [ ...
            'Close.\n\nYou detected the change,\nbut localised it incorrectly.' ...
            '\n\nCorrect location: TOP LEFT' ...
            ];
    case 'missed'
        feedbackText = [ ...
            'Missed.\n\nYou did not detect the change.' ...
            '\n\nCorrect location: TOP LEFT' ...
            ];
    case 'false_alarm'
        feedbackText = ...
            'No change occurred.\n\nThat was a false alarm.';
    case 'correct_rejection'
        feedbackText = 'Correct.\n\nNo change occurred.';
    otherwise
        error('CB_4xGratings_v3_Orientation_ScreenNavigator:UnknownFeedback', ...
            'Unknown feedback variant ''%s''.', feedbackVariant);
end

feedbackCfg = cfg.display.text.feedback;
Screen('TextSize', window, feedbackCfg.textSize);
DrawFormattedText(window, feedbackText, 'center', 'center', ...
    cfg.black, feedbackCfg.textWrap, [], [], feedbackCfg.lineSpacing);
Screen('TextSize', window, feedbackCfg.promptSize);
DrawFormattedText(window, 'Press SPACEBAR to continue.', 'center', ...
    windowRect(4) * feedbackCfg.promptYFrac, cfg.black);
end

function renderCompletion(window, cfg)
% Source counterpart: experiment completion screen.

Screen('TextSize', window, cfg.display.text.bodySize);
endText = ...
    'You have finished the experiment, well done!\n\nPress any key to exit.';
DrawFormattedText(window, endText, 'center', 'center', cfg.black, 90);
end

function drawContinuePrompt(window, windowRect, cfg, promptActive)
tcfg = cfg.display.text;
if promptActive
    colour = cfg.black;
else
    colour = tcfg.greyText;
end
Screen('TextStyle', window, 0);
Screen('TextSize', window, tcfg.promptSize);
DrawFormattedText(window, 'Press SPACEBAR to continue.', 'center', ...
    windowRect(4) * tcfg.promptYFrac, colour);
end

%% ======================= CACHED QUESTION RENDERING =======================

function questionTextures = cacheQuestionTextures( ...
        window, windowRect, cfg)
% Source counterpart: cacheQuestionTextures.

width = RectWidth(windowRect);
height = RectHeight(windowRect);
offscreenRect = [0 0 width height];
offscreen = Screen('OpenOffscreenWindow', ...
    window, cfg.backgroundGrey, offscreenRect);

try
    Screen('TextFont', offscreen, 'Arial');
    Screen('TextSize', offscreen, scaledInteger(45, ...
        cfg.preview.layoutScale, 1));

    drawPASPreview(offscreen, offscreenRect, cfg.black, ...
        cfg.backgroundGrey, cfg);
    image = Screen('GetImage', offscreen);
    questionTextures.PAS = Screen('MakeTexture', window, image);

    drawQuadrantPreview(offscreen, offscreenRect, cfg.black, ...
        cfg.backgroundGrey, 'Where was the change?', cfg);
    image = Screen('GetImage', offscreen);
    questionTextures.Loc_default = Screen('MakeTexture', window, image);

    drawQuadrantPreview(offscreen, offscreenRect, cfg.black, ...
        cfg.backgroundGrey, ...
        'Select a quadrant, even if you experienced no change.', cfg);
    image = Screen('GetImage', offscreen);
    questionTextures.Loc_pas1 = Screen('MakeTexture', window, image);
catch ME
    Screen('Close', offscreen);
    rethrow(ME);
end

Screen('Close', offscreen);
end

function drawQuadrantPreview( ...
        window, windowRect, colour, background, promptText, cfg)
% Source counterpart: drawQuadrantPrompt.

qcfg = cfg.display.text.questions;
Screen('FillRect', window, background);
[xCentre, yCentre] = RectCenter(windowRect);
yTop = windowRect(2);
yBottom = windowRect(4);
width = RectWidth(windowRect);
height = RectHeight(windowRect);
minimumDimension = min(width, height);

margin = round(minimumDimension * qcfg.quadOuterMarginFrac);
topReserve = round(height * qcfg.quadTopReserveFrac);
bottomReserve = round(height * qcfg.quadBottomReserveFrac);
gap = round(minimumDimension * qcfg.quadGapFrac);
boxDesired = round(minimumDimension * qcfg.quadBoxFrac);

maxBoxByWidth = floor((width - 2 * margin - gap) / 2);
maxBoxByHeightTop = floor( ...
    yCentre - (yTop + topReserve) - gap / 2);
maxBoxByHeightBottom = floor( ...
    (yBottom - bottomReserve) - yCentre - gap / 2);
maxBoxByHeight = min(maxBoxByHeightTop, maxBoxByHeightBottom);

minimumBox = scaledInteger(60, cfg.preview.layoutScale, 1);
minimumGap = scaledInteger(30, cfg.preview.layoutScale, 1);
box = max(minimumBox, ...
    min([boxDesired, maxBoxByWidth, maxBoxByHeight]));
if box < minimumBox
    box = minimumBox;
    gap = max(minimumGap, ...
        min(gap, round(minimumDimension * 0.06)));
end

halfBox = box / 2;
offset = halfBox + gap / 2;
quadrantRects = [ ...
    xCentre - offset - halfBox, yCentre - offset - halfBox, xCentre - gap/2, yCentre - gap/2; ...
    xCentre + gap/2, yCentre - offset - halfBox, xCentre + offset + halfBox, yCentre - gap/2; ...
    xCentre - offset - halfBox, yCentre + gap/2, xCentre - gap/2, yCentre + offset + halfBox; ...
    xCentre + gap/2, yCentre + gap/2, xCentre + offset + halfBox, yCentre + offset + halfBox ...
    ];

for ii = 1:4
    Screen('FrameRect', window, colour, quadrantRects(ii, :), ...
        qcfg.quadFrameWidthPx);
    [quadrantX, quadrantY] = RectCenter(quadrantRects(ii, :));
    Screen('TextSize', window, qcfg.quadNumberSize);
    numberBounds = Screen('TextBounds', window, num2str(ii));
    numberX = quadrantX - (numberBounds(3) - numberBounds(1)) / 2;
    numberY = quadrantY - (numberBounds(4) - numberBounds(2)) / 2;
    DrawFormattedText(window, num2str(ii), numberX, numberY, colour);
end

Screen('TextSize', window, qcfg.quadPromptSize);
quadrantTop = yCentre - (offset + halfBox);
promptY = max(yTop + round(height * 0.03), ...
    quadrantTop - round(height * qcfg.quadPromptYOffsetFrac));
DrawFormattedText(window, promptText, 'center', promptY, ...
    colour, qcfg.quadPromptWrap);
end

function drawPASPreview(window, windowRect, colour, background, cfg)
% Source counterpart: drawPAS.

Screen('TextFont', window, 'Arial');
Screen('TextStyle', window, 0);
Screen('FillRect', window, background);
[~, yCentre] = RectCenter(windowRect);
width = RectWidth(windowRect);
height = RectHeight(windowRect);
qcfg = cfg.display.text.questions;

Screen('TextSize', window, qcfg.pasQuestionSize);
DrawFormattedText(window, 'How clearly did you see the change?', ...
    'center', yCentre - round(height * qcfg.pasQuestionYOffsetFrac), ...
    colour, qcfg.pasQuestionWrap);

numbers = {'1', '2', '3', '4'};
descriptions = { ...
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

sideMargin = round(width * qcfg.pasSideMarginFrac);
xPositions = linspace( ...
    windowRect(1) + sideMargin, windowRect(3) - sideMargin, 4);
yNumber = round(yCentre + round(height * qcfg.pasNumYOffsetFrac));
yDescriptionTop = round( ...
    yNumber + round(height * qcfg.pasDescTopGapFrac));
lineStep = round(height * qcfg.pasLineStepFrac);
labelGap = round(height * qcfg.pasLabelGapFrac);

for ii = 1:4
    Screen('TextSize', window, qcfg.pasNumberSize);
    numberBounds = Screen('TextBounds', window, numbers{ii});
    numberX = round(xPositions(ii) - ...
        (numberBounds(3) - numberBounds(1)) / 2);
    DrawFormattedText(window, numbers{ii}, numberX, yNumber, colour);

    Screen('TextSize', window, qcfg.pasDescSize);
    descriptionLines = strsplit(descriptions{ii}, '\n');
    lineY = yDescriptionTop;
    for lineIndex = 1:numel(descriptionLines)
        lineBounds = Screen('TextBounds', ...
            window, descriptionLines{lineIndex});
        lineX = round(xPositions(ii) - ...
            (lineBounds(3) - lineBounds(1)) / 2);
        DrawFormattedText(window, descriptionLines{lineIndex}, ...
            lineX, lineY, colour);
        lineY = lineY + lineStep;
    end

    Screen('TextSize', window, qcfg.pasLabelSize);
    labelBounds = Screen('TextBounds', window, labels{ii});
    labelX = round(xPositions(ii) - ...
        (labelBounds(3) - labelBounds(1)) / 2);
    DrawFormattedText(window, labels{ii}, ...
        labelX, lineY + labelGap, colour);
end
end

%% ============================= ASSET LOADING =============================

function resources = loadNavigatorResources(window, windowRect, cfg)
% Load independent full-screen instruction assets and cached question screens.

resources = struct();
[resources.initialInstructionsTextures.active, activeSize] = ...
    loadFullScreenPngTexture( ...
    window, cfg.preview.initialInstructionsActivePath, ...
    cfg.preview.referenceResolution, 'active initial instructions');
[resources.initialInstructionsTextures.grey, greySize] = ...
    loadFullScreenPngTexture( ...
    window, cfg.preview.initialInstructionsGreyPath, ...
    cfg.preview.referenceResolution, 'grey initial instructions');
resources.initialInstructionsSize = activeSize;
if ~isequal(activeSize, greySize)
    error('CB_4xGratings_v3_Orientation_ScreenNavigator:InstructionAssetMismatch', ...
        ['Initial-instruction PNG sizes do not match: active=%s, ' ...
         'grey=%s.'], mat2str(activeSize), mat2str(greySize));
end

[resources.trialOverviewTextures.active, activeOverviewSize] = ...
    loadFullScreenPngTexture( ...
    window, cfg.preview.trialOverviewActivePath, ...
    cfg.preview.referenceResolution, 'active trial overview');
[resources.trialOverviewTextures.grey, greyOverviewSize] = ...
    loadFullScreenPngTexture( ...
    window, cfg.preview.trialOverviewGreyPath, ...
    cfg.preview.referenceResolution, 'grey trial overview');
resources.trialOverviewSize = activeOverviewSize;
if ~isequal(activeOverviewSize, greyOverviewSize)
    error('CB_4xGratings_v3_Orientation_ScreenNavigator:InstructionAssetMismatch', ...
        ['Trial-overview PNG sizes do not match: active=%s, ' ...
         'grey=%s.'], ...
        mat2str(activeOverviewSize), mat2str(greyOverviewSize));
end

[resources.practice1InformationTextures.active, activePractice1Size] = ...
    loadFullScreenPngTexture( ...
    window, cfg.preview.practice1InformationActivePath, ...
    cfg.preview.referenceResolution, ...
    'active Practice Block 1 information');
[resources.practice1InformationTextures.grey, greyPractice1Size] = ...
    loadFullScreenPngTexture( ...
    window, cfg.preview.practice1InformationGreyPath, ...
    cfg.preview.referenceResolution, ...
    'grey Practice Block 1 information');
resources.practice1InformationSize = activePractice1Size;
if ~isequal(activePractice1Size, greyPractice1Size)
    error('CB_4xGratings_v3_Orientation_ScreenNavigator:InstructionAssetMismatch', ...
        ['Practice Block 1 information PNG sizes do not match: ' ...
         'active=%s, grey=%s.'], ...
        mat2str(activePractice1Size), mat2str(greyPractice1Size));
end

[resources.practice2InformationTextures.active, activePractice2Size] = ...
    loadFullScreenPngTexture( ...
    window, cfg.preview.practice2InformationActivePath, ...
    cfg.preview.referenceResolution, ...
    'active Practice Block 2 information');
[resources.practice2InformationTextures.grey, greyPractice2Size] = ...
    loadFullScreenPngTexture( ...
    window, cfg.preview.practice2InformationGreyPath, ...
    cfg.preview.referenceResolution, ...
    'grey Practice Block 2 information');
resources.practice2InformationSize = activePractice2Size;
if ~isequal(activePractice2Size, greyPractice2Size)
    error('CB_4xGratings_v3_Orientation_ScreenNavigator:InstructionAssetMismatch', ...
        ['Practice Block 2 information PNG sizes do not match: ' ...
         'active=%s, grey=%s.'], ...
        mat2str(activePractice2Size), mat2str(greyPractice2Size));
end

[resources.experimentInformationTextures.active, activeExperimentSize] = ...
    loadFullScreenPngTexture( ...
    window, cfg.preview.experimentInformationActivePath, ...
    cfg.preview.referenceResolution, ...
    'active Experiment information');
[resources.experimentInformationTextures.grey, greyExperimentSize] = ...
    loadFullScreenPngTexture( ...
    window, cfg.preview.experimentInformationGreyPath, ...
    cfg.preview.referenceResolution, ...
    'grey Experiment information');
resources.experimentInformationSize = activeExperimentSize;
if ~isequal(activeExperimentSize, greyExperimentSize)
    error('CB_4xGratings_v3_Orientation_ScreenNavigator:InstructionAssetMismatch', ...
        ['Experiment information PNG sizes do not match: ' ...
         'active=%s, grey=%s.'], ...
        mat2str(activeExperimentSize), mat2str(greyExperimentSize));
end

resources.questionTextures = cacheQuestionTextures( ...
    window, windowRect, cfg);
end

function [texture, sizePx] = loadFullScreenPngTexture( ...
        window, imagePath, expectedSizePx, assetLabel)
% Load an opaque or alpha PNG intended to cover the complete ViewPixx frame.

if ~exist(imagePath, 'file')
    error('CB_4xGratings_v3_Orientation_ScreenNavigator:MissingInstructionAsset', ...
        'Missing %s PNG:\n%s', assetLabel, imagePath);
end

[image, map, alpha] = imread(imagePath);
if ~isempty(map)
    image = uint8(ind2rgb(image, map) * 255);
end
if ismatrix(image)
    image = repmat(image, [1 1 3]);
elseif size(image, 3) > 4
    image = image(:, :, 1:4);
end

sizePx = [size(image, 2), size(image, 1)];
if ~isequal(sizePx, expectedSizePx)
    error('CB_4xGratings_v3_Orientation_ScreenNavigator:InvalidInstructionAssetSize', ...
        '%s PNG must be %d x %d pixels, but is %d x %d:\n%s', ...
        assetLabel, expectedSizePx(1), expectedSizePx(2), ...
        sizePx(1), sizePx(2), imagePath);
end

if ~isempty(alpha) && size(image, 3) < 4
    if ~isa(alpha, 'uint8')
        alphaDouble = double(alpha);
        if max(alphaDouble(:)) <= 1 && min(alphaDouble(:)) >= 0
            alpha = uint8(alphaDouble * 255);
        else
            alpha = uint8(max(0, min(255, alphaDouble)));
        end
    end
    image = cat(3, image(:, :, 1:3), alpha(:, :, 1));
end

texture = Screen('MakeTexture', window, image);
end

%% ====================== NAVIGATION / OPERATOR LAYER ======================

function keys = makeNavigatorKeys
keys = struct();
keys.escape = KbName('ESCAPE');
keys.right = KbName('RightArrow');
keys.left = KbName('LeftArrow');
keys.up = KbName('UpArrow');
keys.down = KbName('DownArrow');
keys.home = KbName('Home');
keys.endKey = KbName('End');
keys.togglePrompt = KbName('a');
keys.toggleOverlay = KbName('h');
keys.screenshot = KbName('s');
keys.allCodes = unique([ ...
    keys.escape, keys.right, keys.left, keys.up, keys.down, ...
    keys.home, keys.endKey, keys.togglePrompt, ...
    keys.toggleOverlay, keys.screenshot ...
    ]);
end

function renderedFrames = runAutomatedRenderAudit( ...
        window, windowRect, cfg, resources, pages, state)
% Exercise every page, variant, and applicable prompt state without input.

renderedFrames = 0;
state.overlayVisible = false;
for pageIndex = 1:numel(pages)
    state.pageIndex = pageIndex;
    for variantIndex = 1:numel(pages(pageIndex).variants)
        state.variantIndices(pageIndex) = variantIndex;
        if pages(pageIndex).supportsPromptToggle
            promptStates = [true false];
        else
            promptStates = true;
        end
        for promptActive = promptStates
            state.promptActive = promptActive;
            drawNavigatorFrame( ...
                window, windowRect, cfg, resources, pages, state);
            renderedFrames = renderedFrames + 1;
        end
    end
end

% Exercise the operator overlay separately from participant rendering.
state.overlayVisible = true;
drawNavigatorFrame(window, windowRect, cfg, resources, pages, state);
renderedFrames = renderedFrames + 1;
end

function createNavigatorQueue(kbDev, keys)
if any(keys.allCodes < 1) || any(keys.allCodes > 256)
    error('CB_4xGratings_v3_Orientation_ScreenNavigator:InvalidKeyCode', ...
        'A navigator key did not resolve to a valid Psychtoolbox key code.');
end
keyMask = zeros(1, 256);
keyMask(keys.allCodes) = 1;
KbQueueCreate(kbDev, keyMask);
KbQueueStart(kbDev);
KbQueueFlush(kbDev);
end

function keyCode = earliestNavigatorKey(firstPress, allowedCodes)
keyCode = NaN;
times = firstPress(allowedCodes);
valid = times > 0;
if ~any(valid)
    return;
end
validCodes = allowedCodes(valid);
validTimes = times(valid);
[~, earliestIndex] = min(validTimes);
keyCode = validCodes(earliestIndex);
end

function drawOperatorOverlay(window, windowRect, cfg, pages, state)
page = pages(state.pageIndex);
variant = page.variants(state.variantIndices(state.pageIndex));
promptState = currentPromptState(page, state.promptActive);

overlayText = sprintf([ ...
    'ORIENTATION SCREEN NAVIGATOR\n' ...
    'Page %d/%d: %s\n' ...
    'ID: %s\n' ...
    'Variant: %s\n' ...
    'SPACEBAR prompt: %s\n\n' ...
    'LEFT/RIGHT page   UP/DOWN variant   HOME/END first/last\n' ...
    'A prompt   H overlay   S clean screenshot   ESC exit'], ...
    state.pageIndex, numel(pages), page.name, page.id, ...
    variant.label, promptState);

scale = cfg.preview.layoutScale;
margin = scaledInteger(20, scale, 8);
overlayWidth = min(RectWidth(windowRect) - 2 * margin, ...
    scaledInteger(900, scale, 400));
overlayHeight = scaledInteger(245, scale, 160);
overlayRect = [margin, margin, ...
    margin + overlayWidth, margin + overlayHeight];

Screen('FillRect', window, [0 0 0 0.82], overlayRect);
Screen('TextFont', window, 'Arial');
Screen('TextStyle', window, 0);
Screen('TextSize', window, scaledInteger(18, scale, 13));
textInset = scaledInteger(16, scale, 8);
DrawFormattedText(window, overlayText, ...
    overlayRect(1) + textInset, overlayRect(2) + textInset, ...
    1, 95, [], [], 1.15);
end

function printNavigatorState(actionText, pages, state)
page = pages(state.pageIndex);
variant = page.variants(state.variantIndices(state.pageIndex));
promptState = currentPromptState(page, state.promptActive);
if state.overlayVisible
    overlayState = 'shown';
else
    overlayState = 'hidden';
end

fprintf(['NAV | %-31s | page=%02d/%02d | id=%-27s | ' ...
    'variant=%-31s | prompt=%-14s | overlay=%s\n'], ...
    actionText, state.pageIndex, numel(pages), page.id, ...
    variant.label, promptState, overlayState);
end

function promptState = currentPromptState(page, promptActive)
if ~page.supportsPromptToggle
    promptState = 'not_applicable';
elseif promptActive
    promptState = 'active';
else
    promptState = 'grey';
end
end

function screenshotPath = saveCleanScreenshot( ...
        window, windowRect, cfg, resources, pages, state)

cleanState = state;
cleanState.overlayVisible = false;
drawNavigatorFrame( ...
    window, windowRect, cfg, resources, pages, cleanState);
image = Screen('GetImage', window, [], 'frontBuffer');

if ~exist(cfg.preview.screenshotDir, 'dir')
    mkdir(cfg.preview.screenshotDir);
end

page = pages(state.pageIndex);
variant = page.variants(state.variantIndices(state.pageIndex));
promptState = currentPromptState(page, state.promptActive);
timestamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss_SSS'));
safePageId = regexprep(page.id, '[^A-Za-z0-9_-]', '_');
safeVariantId = regexprep(variant.id, '[^A-Za-z0-9_-]', '_');
safePromptState = regexprep(promptState, '[^A-Za-z0-9_-]', '_');
filename = sprintf('%s_%s_%s_%s.png', ...
    timestamp, safePageId, safeVariantId, safePromptState);
screenshotPath = fullfile(cfg.preview.screenshotDir, filename);
imwrite(image, screenshotPath);

% Restore the current operator-overlay state after the clean capture.
drawNavigatorFrame(window, windowRect, cfg, resources, pages, state);
end

%% ================================ CLEANUP ================================

function cleanupNavigator( ...
        kbDev, oldPriority, oldVisualDebugLevel, oldSkipSyncTests)

try
    KbQueueRelease(kbDev);
catch
end
try
    ListenChar(0);
catch
end
try
    Priority(oldPriority);
catch
end
try
    ShowCursor;
catch
end
try
    Screen('CloseAll');
catch
end
try
    Screen('Preference', 'VisualDebugLevel', oldVisualDebugLevel);
catch
end
try
    Screen('Preference', 'SkipSyncTests', oldSkipSyncTests);
catch
end
end
