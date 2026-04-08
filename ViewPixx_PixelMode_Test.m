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
% - Use PsychImaging AddTask UseDataPixx before OpenWindow so PsychDataPixx opens
%   the device and runs PerformPostWindowOpenSetup. Raw Datapixx('Open') after
%   OpenWindow still yields "Datapixx is not open" for EnablePixelMode on current
%   VPixx Datapixx.mex builds.
%
% TROUBLESHOOTING "Invalid MEX-file ... The specified module could not be found"
% ---------------------------------------------------------------------------
%   "which Datapixx" only proves MATLAB sees Datapixx.mexw64 on disk.
%   That error means WINDOWS could not load a DLL that the MEX depends on
%   (VPixx runtime libraries), not a MATLAB path problem.
%
%   After installing VPixx Software Tools: fully QUIT MATLAB and reopen it
%   (or reboot) so updated PATH / DLL search picks up the new install.
%
%   Typical fixes: install VPixx package with MATLAB + device drivers;
%   install the VC++ redistributable version VPixx documents; ensure the
%   VPixx install folder containing their .dll files is on the system PATH.

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

% Cell wrapper so onCleanup sees live flags (plain scalars are captured by value).
ctx = {[], false, false};  % {window, datapixxOpen, pixelModeEnabled}
cleanupObj = onCleanup(@() localCleanup(ctx));

try
    Screen('Preference', 'SkipSyncTests', 1);
    PsychImaging('PrepareConfiguration');
    PsychImaging('AddTask', 'General', 'UseDataPixx');
    [window, ~] = PsychImaging('OpenWindow', screenid, bgColor);
    ctx{1} = window;
    ctx{2} = true;   % PsychDataPixx refcount from OpenWindow — close with PsychDataPixx('Close')

    Screen('TextFont', window, 'Arial');
    Screen('TextSize', window, 28);

    % Newer VPixx Datapixx.mex: default RGB = no 2nd arg to EnablePixelMode.
    datapixxEnablePixelMode(pixelMode);
    datapixxRegApply();
    ctx{3} = true;

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
    if contains(ME.message, 'specified module could not be found', 'IgnoreCase', true) || ...
            contains(ME.message, 'Invalid MEX-file', 'IgnoreCase', true)
        printDatapixxLoadHelp(ME);
    end
    rethrow(ME);
end

end

function printDatapixxLoadHelp(~)
    mexPath = which('Datapixx');
    fprintf(2, '\n--- Datapixx MEX load help ---\n');
    fprintf(2, 'which Datapixx -> %s\n', mexPath);
    fprintf(2, ['That path is only the MEX file. "Module could not be found" means a ' ...
        'native DLL required by that MEX is missing or not on the Windows DLL search path.\n\n']);
    fprintf(2, 'Try:\n');
    fprintf(2, '  1) Install VPixx Software Tools (MATLAB + drivers) from vpixx.com/support.\n');
    fprintf(2, '  2) Fully quit MATLAB and reopen (or reboot) so PATH updates apply.\n');
    fprintf(2, '  3) Install the Microsoft VC++ Redistributable (x64) version VPixx specifies.\n');
    fprintf(2, '  4) Optional: use Dependencies (github lucasg/Dependencies) on Datapixx.mexw64 to see the missing DLL name.\n');
    fprintf(2, '---\n\n');
end

function datapixxEnablePixelMode(mode)
% VPixx-shipped MEX: mode 0 = one-arg form; do not fall back to EnablePixelMode(0) on errors
% (that masks "not open" with a generic Usage line).
mode = double(mode);
if mode == 0
    Datapixx('EnablePixelMode');
else
    Datapixx('EnablePixelMode', mode);
end
end

function datapixxRegApply()
% Commit register writes (write + readback). Current VPixx Datapixx.mex uses this; plain RegWr can error.
Datapixx('RegWrRd');
end

function localCleanup(ctx)
window = ctx{1};
datapixxOpen = ctx{2};
pixelModeEnabled = ctx{3};

% Tear down VPixx video mode before closing the GL window when possible.
try
    if datapixxOpen
        if pixelModeEnabled
            try
                Datapixx('DisablePixelMode');
                datapixxRegApply();
            catch
            end
        end
        try
            PsychDataPixx('Close');
        catch
            try
                Datapixx('Close');
            catch
            end
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
