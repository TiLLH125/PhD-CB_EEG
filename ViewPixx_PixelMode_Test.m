function ViewPixx_PixelMode_Test
% ViewPixx_PixelMode_Test
% Quick hardware/control-link preflight for VPixx + PTB.
%
% What this checks:
% 1) PTB can open a window (video path basic sanity)
% 2) Datapixx MEX loads
% 3) Datapixx control connection opens
% 4) Datapixx reports IsReady == true
% 5) Optional status query succeeds
%
% NOTE:
% - DB25 is NOT required for this preflight.
% - Pixel Mode needs Datapixx control link (usually USB), not just video.

close all;
KbName('UnifyKeyNames');

screenid = max(Screen('Screens'));
bgColor = 0;
win = [];

cleanupObj = onCleanup(@() localCleanup(win)); 

fprintf('\n=== VPixx Preflight Start ===\n');

try
    % 1) Video path basic sanity
    Screen('Preference', 'SkipSyncTests', 1);
    [win, ~] = PsychImaging('OpenWindow', screenid, bgColor);
    Screen('TextSize', win, 24);
    DrawFormattedText(win, ...
        'VPixx preflight running...\n(See MATLAB command window)', ...
        'center', 'center', [255 255 255]);
    Screen('Flip', win);
    fprintf('OK: PTB OpenWindow succeeded on screen %d.\n', screenid);

    % 2) Datapixx MEX load sanity
    mexPath = which('Datapixx');
    fprintf('Datapixx MEX path: %s\n', mexPath);

    % 3) Open control connection
    Datapixx('Open');
    fprintf('OK: Datapixx(''Open'') returned.\n');

    % 4) Check readiness
    isReady = Datapixx('IsReady');
    fprintf('Datapixx(''IsReady'') = %d\n', isReady);

    if ~isReady
        error(['Datapixx opened but IsReady==0. Control link is not working.\n' ...
               'Check USB/control cable, power, drivers, and ensure no other app has the device open.']);
    end

    % 5) Optional status/error checks
    try
        dErr = Datapixx('GetError');
        fprintf('Datapixx(''GetError'') = %d\n', dErr);
        if dErr ~= 0
            Datapixx('ClearError');
            fprintf('Info: Cleared Datapixx error flag.\n');
        end
    catch
        fprintf('Info: GetError/ClearError not available on this build.\n');
    end

    fprintf('\nPASS: Datapixx control link is ready.\n');
    fprintf('If Pixel Mode still fails after this, it is an API/syntax/config issue, not connectivity.\n');

    DrawFormattedText(win, ...
        'PASS: Datapixx control link ready.\nPress SPACE to exit.', ...
        'center', 'center', [0 255 0]);
    Screen('Flip', win);

    waitForSpace();

    % Optional: explicitly close datapixx now
    try
        Datapixx('Close');
    catch
    end

catch ME
    fprintf(2, '\n=== VPixx Preflight FAILED ===\n%s\n', ...
        getReport(ME, 'extended', 'hyperlinks', 'off'));

    fprintf(2, '\nChecklist:\n');
    fprintf(2, ' - Video cable connected to ViewPixx and correct display selected\n');
    fprintf(2, ' - USB/control cable from stimulus PC to VPixx hardware\n');
    fprintf(2, ' - Device powered on\n');
    fprintf(2, ' - VPixx drivers/software installed\n');
    fprintf(2, ' - No other app (e.g., LabMaestro) holding device open\n');
    fprintf(2, ' - Restart MATLAB after driver changes\n\n');

    rethrow(ME);
end

end

function waitForSpace()
while true
    [down, ~, keyCode] = KbCheck;
    if down
        if keyCode(KbName('space'))
            KbReleaseWait;
            break;
        end
        KbReleaseWait;
    end
end
end

function localCleanup(win)
try
    Datapixx('Close');
catch
end

try
    if ~isempty(win)
        sca;
    else
        try
            Screen('CloseAll');
        catch
        end
    end
catch
end
end
