function CB_4xGratings_PixelMode_TriggerTest
% CB_4xGratings_PixelMode_TriggerTest
% ViewPixx Pixel Mode trigger test (VPixx-style demo), using the same PTB startup
% style as CB_4xGratings_EEG (keyboard reset, screen choice, PsychDefaultSetup).
%
% Pixel Mode draws a 1-pixel marker (top-left) whose RGB encodes trigger lines.
% Example codes match VPixx docs: [19 0 0], [35 0 0], [67 0 0], clear [0 0 0].
%
% Controls:
%   1 / 2 / 3  -> set example trigger RGB
%   0          -> clear marker (0,0,0)
%   SPACE      -> exit
%
% BioSemi Actiview:
%   Actiview shows whatever enters the amplifier trigger port (parallel BDF bits,
%   etc.). It does NOT decode Pixel Mode from the monitor. You only see these
%   triggers in Actiview if hardware decodes pixel/TTL into your BioSemi trigger
%   input (e.g. VPixx digital out, a separate decoder, or your serial path).
%
% Requires: USB control link to VPixx so Datapixx('IsReady') is true after Open.

close all;

try ListenChar(0); catch, end
try KbQueueRelease(-1); catch, end

if exist('sca', 'file') == 2
    sca;
elseif exist('Screen', 'file') == 2
    Screen('CloseAll');
end

% Match CB_4xGratings_EEG defaults (edit if needed)
screenNumber   = 2;
skipSyncTests  = 1;

KbName('UnifyKeyNames');

try
    PsychDefaultSetup(2);
catch
    error('Psychtoolbox not found. Install Psychtoolbox-3 first.');
end

% Normalized colors (PsychDefaultSetup(2))
bgColor    = 0;
textColor  = [1 1 1];
pixelPos   = [0 0];
pixelSize  = 1;

% Example codes as 0..1 RGB (VPixx doc uses 8-bit 19/35/67 on R)
codeMap = containers.Map('KeyType', 'double', 'ValueType', 'any');
codeMap(0) = [0 0 0];
codeMap(1) = [19/255 0 0];
codeMap(2) = [35/255 0 0];
codeMap(3) = [67/255 0 0];

ctx = {[], false, false};  % {window, datapixxOpen, pixelModeEnabled}
cleanupObj = onCleanup(@() localPixelCleanup(ctx)); %#ok<NASGU>

try
    Screen('Preference', 'SkipSyncTests', skipSyncTests);
    Screen('Preference', 'VisualDebugLevel', 1);

    [window, ~] = PsychImaging('OpenWindow', screenNumber, bgColor);
    ctx{1} = window;

    Screen('TextFont', window, 'Arial');
    Screen('TextSize', window, 28);

    Datapixx('Open');
    if ~logical(Datapixx('IsReady'))
        error('CB_4xGratings_PixelMode_TriggerTest:DatapixxNotReady', ...
            'Datapixx IsReady==0. Connect VPixx USB control to this PC and retry.');
    end
    ctx{2} = true;

    % VPixx MEX: RGB Pixel Mode often uses one-arg form
    Datapixx('EnablePixelMode');
    datapixxRegWrRd();
    ctx{3} = true;

    currentCode = 1;
    running = true;

    while running
        curRGB = codeMap(currentCode);

        Screen('FillRect', window, bgColor);
        instr = sprintf([ ...
            'Pixel Mode trigger test (VPixx-style)\n\n' ...
            'Current key: %d  |  pixel RGB (norm): [%.4f %.4f %.4f]\n\n' ...
            '1 = [19 0 0]   2 = [35 0 0]   3 = [67 0 0]   0 = clear\n' ...
            'SPACE = exit\n'], ...
            currentCode, curRGB(1), curRGB(2), curRGB(3));
        DrawFormattedText(window, instr, 'center', 'center', textColor, 90);

        Screen('DrawDots', window, pixelPos, pixelSize, curRGB, [], 1);
        Screen('Flip', window);

        [keyDown, ~, keyCode] = KbCheck;
        if keyDown
            if keyCode(KbName('space'))
                running = false;
            elseif keyCode(KbName('0)'))
                currentCode = 0;
            elseif keyCode(KbName('1!'))
                currentCode = 1;
            elseif keyCode(KbName('2@'))
                currentCode = 2;
            elseif keyCode(KbName('3#'))
                currentCode = 3;
            end
            KbReleaseWait;
        end
    end

catch ME
    fprintf(2, '\nCB_4xGratings_PixelMode_TriggerTest ERROR:\n%s\n', ...
        getReport(ME, 'extended', 'hyperlinks', 'off'));
    rethrow(ME);
end

end

function datapixxRegWrRd()
Datapixx('RegWrRd');
end

function localPixelCleanup(ctx)
window = ctx{1};
datapixxOpen = ctx{2};
pixelModeEnabled = ctx{3};

try
    if datapixxOpen
        if pixelModeEnabled
            try
                Datapixx('DisablePixelMode');
                datapixxRegWrRd();
            catch
            end
        end
        try
            Datapixx('Close');
        catch
        end
    end
catch
end

try
    if ~isempty(window)
        sca;
    else
        try Screen('CloseAll'); catch, end
    end
catch
end
end
