function ViewPixx_PixelMode_Test
% ViewPixx_PixelMode_Test
% Quick standalone Pixel Mode verification script for VPixx displays.
%
% Controls:
%   1 -> Trigger code 19 (example from VPixx docs)
%   2 -> Trigger code 35
%   3 -> Trigger code 67
%   0 -> Trigger code 0 (clear)
%   SPACE -> Exit
%
% Notes:
% - Pixel Mode trigger is drawn as a single pixel at top-left.
% - This script enables Pixel Mode on start and disables it on exit.

close all;
KbName('UnifyKeyNames');

% ---- User settings ----
pixelMode = 0;                  % 0 = Pixel Mode RGB, 1 = Pixel Mode GB
screenid = max(Screen('Screens'));
bgColor = 0;
textColor = [255 255 255];
pixelPos = [0, 0];              % top-left pixel
pixelSize = 1;

% Example trigger color triplets.
% Adjust these to your lab codebook as needed.
codeMap = containers.Map('KeyType','double','ValueType','any');
codeMap(0) = [0 0 0];
codeMap(1) = [19 0 0];
codeMap(2) = [35 0 0];
codeMap(3) = [67 0 0];

window = [];
datapixxOpen = false;
pixelModeEnabled = false;

cleanupObj = onCleanup(@() localCleanup(window, datapixxOpen, pixelModeEnabled)); %#ok<NASGU>

try
    Screen('Preference', 'SkipSyncTests', 1);
    [window, windowRect] = PsychImaging('OpenWindow', screenid, bgColor);
    Screen('TextFont', window, 'Arial');
    Screen('TextSize', window, 28);

    % ---- Enable ViewPixx Pixel Mode ----
    Datapixx('Open');
    datapixxOpen = true;
    Datapixx('EnablePixelMode', pixelMode);
    Datapixx('RegWr');
    pixelModeEnabled = true;

    currentCode = 0;
    running = true;

    while running
        curRGB = codeMap(currentCode);

        % Draw instruction panel
        Screen('FillRect', window, bgColor);
        panelText = sprintf([ ...
            'ViewPixx Pixel Mode Test\n\n' ...
            'Pixel Mode: %d\n' ...
            'Current code key: %d\n' ...
            'Current pixel RGB: [%d %d %d]\n\n' ...
            'Press 1, 2, or 3 to set trigger pixel code.\n' ...
            'Press 0 to clear (RGB = [0 0 0]).\n' ...
            'Press SPACE to exit.\n'], ...
            pixelMode, currentCode, ...
            curRGB(1), curRGB(2), curRGB(3));

        DrawFormattedText(window, panelText, 'center', 'center', textColor, 90);

        % Draw trigger pixel
        pixelCol = curRGB;
        Screen('DrawDots', window, pixelPos, pixelSize, pixelCol, [], 1);

        Screen('Flip', window);

        % Poll keyboard
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

            % Debounce
            KbReleaseWait;
        end
    end

catch ME
    fprintf(2, '\nViewPixx_PixelMode_Test ERROR:\n%s\n', getReport(ME, 'extended', 'hyperlinks', 'off'));
    rethrow(ME);
end

end

function localCleanup(window, datapixxOpen, pixelModeEnabled)
try
    if ~isempty(window)
        sca;
    else
        try Screen('CloseAll'); catch, end
    end
catch
end

try
    if datapixxOpen
        if pixelModeEnabled
            Datapixx('DisablePixelMode');
            Datapixx('RegWr');
        end
        Datapixx('Close');
    end
catch
end
end
