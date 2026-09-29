function result = run_cmnoise_green_red(varargin)

%RUN_CMNOISE_GREEN_RED Run green-light and red-light imaging sessions.
%   This version does not draw a Frame2TTL patch and does not initialize,
%   control, or read a Bpod state machine. Camera acquisition is started
%   directly from MATLAB and display timing is measured with Psychtoolbox.

p = inputParser;
p.addParameter('rig',0);
p.addParameter('skipsynctests',1);
p.addParameter('animalid','c03');
p.addParameter('depth','000');
p.addParameter('repetitions',5);
p.addParameter('stimduration',180);
p.addParameter('isipre',5); % Per-block gray baseline used by analysis.
p.addParameter('isipost',3);
p.addParameter('DScreen',8);
p.addParameter('VertScreenSize',15);
p.addParameter('HorzScreenSize',20);
p.addParameter('fullscreen',1);
p.addParameter('screenNumber',2); % Psychtoolbox display index for stimulus output.
p.addParameter('sFreqs',0.04);
p.addParameter('tFreqs',1);
p.addParameter('contrast_list',[1]);
p.addParameter('position',[0,0]);
p.addParameter('save_remote',0);
p.addParameter('interleave',0);
p.addParameter('random_mov',1);
p.addParameter('movtype',3.5);
p.addParameter('aperture_width_deg',12);
p.addParameter('contrast_period',18);
p.addParameter('match_elevation_speed',true);
p.addParameter('counterbalance_block_order',true);
p.addParameter('sweeps_per_block',10);
p.addParameter('green_repetitions',1);
p.addParameter('green_sweeps_per_block',5);
p.addParameter('rcontrast_window',120);
p.addParameter('stimFolderRemote', ...
    'Z:\YeerimKim\mesorig\VisStimData\');

%% -------------------- Camera parameters --------------------
p.addParameter('camera_device_id',1);
p.addParameter('camera_video_format','Mono16');
p.addParameter('camera_fps',10);
p.addParameter('camera_exposure_us',100000);
p.addParameter('camera_gain',18);
p.addParameter('camera_red_exposure_us',[]);
p.addParameter('camera_red_gain',[]);
p.addParameter('camera_black_level',0);
p.addParameter('camera_preview',1);
p.addParameter('camera_preview_during_experiment',0);
p.addParameter('red_setup_preview',1);
p.addParameter('camera_save_folder','D:\intrinsic');
p.addParameter('camera_tiff_chunk_frames',30);
p.addParameter('camera_final_drain_timeout_sec',120);

p.parse(varargin{:});
result = p.Results;

% Retinotopy block design. Screen-coordinate convention:
%   nasal -> temporal     = left -> right
%   temporal -> nasal     = right -> left
%   inferior -> superior  = bottom -> top
%   superior -> inferior  = top -> bottom
baseBlockNames = [ ...
    "nasal_to_temporal"; ...
    "temporal_to_nasal"; ...
    "inferior_to_superior"; ...
    "superior_to_inferior"];
baseBlockAxis = [0; 0; 1; 1];       % 0: horizontal, 1: vertical
baseBlockReverse = [0; 1; 1; 0];    % Reverse increasing screen coordinates

blockRepetitions = result.repetitions;
validateattributes(blockRepetitions,{'numeric'}, ...
    {'scalar','integer','positive'});

blockNames = strings(numel(baseBlockNames)*blockRepetitions,1);
blockAxis = zeros(size(blockNames));
blockReverse = zeros(size(blockNames));

for repetitionIndex = 1:blockRepetitions
    if logical(result.counterbalance_block_order) && ...
            mod(repetitionIndex,2) == 0
        directionOrder = numel(baseBlockNames):-1:1;
    else
        directionOrder = 1:numel(baseBlockNames);
    end

    destinationIndices = (repetitionIndex-1)*numel(baseBlockNames) + ...
        (1:numel(baseBlockNames));
    blockNames(destinationIndices) = ...
        baseBlockNames(directionOrder) + "_" + string(repetitionIndex);
    blockAxis(destinationIndices) = baseBlockAxis(directionOrder);
    blockReverse(destinationIndices) = baseBlockReverse(directionOrder);
end
greenBlockRepetitions = result.green_repetitions;
validateattributes(greenBlockRepetitions,{'numeric'}, ...
    {'scalar','integer','positive'});

greenBlockNames = strings( ...
    numel(baseBlockNames)*greenBlockRepetitions,1);
greenBlockAxis = zeros(size(greenBlockNames));
greenBlockReverse = zeros(size(greenBlockNames));

for repetitionIndex = 1:greenBlockRepetitions
    if logical(result.counterbalance_block_order) && ...
            mod(repetitionIndex,2) == 0
        directionOrder = numel(baseBlockNames):-1:1;
    else
        directionOrder = 1:numel(baseBlockNames);
    end

    destinationIndices = ...
        (repetitionIndex-1)*numel(baseBlockNames) + ...
        (1:numel(baseBlockNames));
    greenBlockNames(destinationIndices) = ...
        baseBlockNames(directionOrder) + "_" + string(repetitionIndex);
    greenBlockAxis(destinationIndices) = baseBlockAxis(directionOrder);
    greenBlockReverse(destinationIndices) = ...
        baseBlockReverse(directionOrder);
end
greenSweepsPerBlock = result.green_sweeps_per_block;

result.repetitions = numel(blockNames);
result.stimduration = ...
    result.contrast_period * result.sweeps_per_block;
result.interleave = 0;
result.block.names = blockNames;
result.block.axis = blockAxis;
result.block.reverse = logical(blockReverse);
result.block.period_sec = repmat(result.contrast_period, ...
    numel(blockNames),1);
result.block.repetitions = blockRepetitions;
result.green.repetitions_per_session = greenBlockRepetitions;
result.green.sweeps_per_block = greenSweepsPerBlock;
result.green.block.names = greenBlockNames;
result.green.block.axis = greenBlockAxis;
result.green.block.reverse = logical(greenBlockReverse);
result.green.block.period_sec = repmat(result.contrast_period, ...
    numel(greenBlockNames),1);
result.green.sessionCount = 0;
result.green.sessions = struct([]);

fprintf('Running file: %s\n',mfilename('fullpath'));
fprintf(['Design: %d blocks x %d sweeps x %.3f sec = ' ...
    '%.3f min stimulus (%.3f min including pre/post ITI).\n'], ...
    result.repetitions,result.sweeps_per_block, ...
    result.contrast_period, ...
    result.repetitions*result.stimduration/60, ...
    result.repetitions*(result.isipre+result.stimduration+ ...
    result.isipost)/60);

validateattributes(result.repetitions,{'numeric'}, ...
    {'scalar','integer','positive'});
validateattributes(result.stimduration,{'numeric'}, ...
    {'scalar','nonnegative'});
validateattributes(result.isipre,{'numeric'}, ...
    {'scalar','nonnegative'});
validateattributes(result.isipost,{'numeric'}, ...
    {'scalar','nonnegative'});
validateattributes(result.camera_fps,{'numeric'}, ...
    {'scalar','positive'});
validateattributes(result.camera_tiff_chunk_frames,{'numeric'}, ...
    {'scalar','integer','positive'});
validateattributes(result.camera_final_drain_timeout_sec,{'numeric'}, ...
    {'scalar','positive'});
validateattributes(result.counterbalance_block_order, ...
    {'numeric','logical'},{'scalar'});
result.counterbalance_block_order = ...
    logical(result.counterbalance_block_order);
validateattributes(result.red_setup_preview, ...
    {'numeric','logical'},{'scalar'});
result.red_setup_preview = logical(result.red_setup_preview);

if ~isempty(result.camera_red_exposure_us)
    validateattributes(result.camera_red_exposure_us,{'numeric'}, ...
        {'scalar','positive'});
end

if ~isempty(result.camera_red_gain)
    validateattributes(result.camera_red_gain,{'numeric'}, ...
        {'scalar','finite'});
end
validateattributes(result.aperture_width_deg,{'numeric'}, ...
    {'scalar','positive'});
validateattributes(result.contrast_period,{'numeric'}, ...
    {'scalar','positive'});
validateattributes(result.match_elevation_speed,{'numeric','logical'}, ...
    {'scalar'});
result.match_elevation_speed = logical(result.match_elevation_speed);
validateattributes(result.camera_video_format,{'char','string'}, ...
    {'scalartext'});
validateattributes(result.sweeps_per_block,{'numeric'}, ...
    {'scalar','integer','positive'});
validateattributes(result.green_sweeps_per_block,{'numeric'}, ...
    {'scalar','integer','positive'});
if result.repetitions < numel(result.contrast_list)
    warning(['The trial number (repetitions) is less than the number ' ...
        'of requested contrasts.']);
    warn = input('Press q to quit or any other key to continue...','s');

    if strcmpi(warn,'q')
        return;
    end
end

%% -------------------- Experiment paths --------------------
result.do_msock = 0;
result.stimFolderLocal = 'D:\Users\USER\VisStimData\';
result.exptid = '101_camera';

cameraRootFolder = result.camera_save_folder;

% Store each experiment in a subject-specific folder inside today's folder.
% Folder creation is deferred until the camera preview is accepted so that
% quitting after preview does not leave an empty experiment folder.
% Examples:
%   D:\intrinsic\20260720\c03_1
%   D:\intrinsic\20260720\c03_2
dateFolderName = datestr(now,'yyyymmdd');
cameraDateFolder = fullfile(cameraRootFolder,dateFolderName);

subjectName = char(string(result.animalid));
sessionSequence = 1;
sessionName = sprintf('%s_%d',subjectName,sessionSequence);

while exist(fullfile(cameraDateFolder,sessionName),'dir')
    sessionSequence = sessionSequence + 1;
    sessionName = sprintf('%s_%d',subjectName,sessionSequence);
end

cameraSessionFolder = fullfile(cameraDateFolder,sessionName);

result.camera_root_folder = cameraRootFolder;
result.camera_date_folder = cameraDateFolder;
result.camera_session_name = sessionName;
result.camera_save_folder = cameraSessionFolder;

if result.do_msock
    sock = msPrep();
end

%% -------------------- Cross-clock calibration --------------------
% Repeated PC-wall-clock <-> PTB GetSecs anchor pairs make it possible to
% estimate both clock offset and drift. Wall-clock sampling is deliberately
% kept outside the stimulus frame loop.
result.clock.anchorLabel = strings(0,1);
result.clock.anchorBlock = zeros(0,1);
result.clock.pcWallTime = strings(0,1);
result.clock.pcWallTimeZone = "UTC";
result.clock.pcWallPosix_sec = zeros(0,1);
result.clock.ptbGetSecs_sec = zeros(0,1);
result.clock.anchorUncertainty_sec = zeros(0,1);
result.clock.ptbT0GetSecs_sec = NaN;

%% -------------------- Camera result arrays --------------------
nTrials = result.repetitions;
plannedTrialDuration = ...
    result.isipre + result.stimduration + result.isipost;
plannedFrameCount = ...
    round(plannedTrialDuration * result.camera_fps);

result.camera.rootFolder = string(cameraRootFolder);
result.camera.sessionFolder = string(result.camera_save_folder);
result.camera.sessionName = string(sessionName);
result.camera.plannedTrialDuration_sec = ...
    repmat(plannedTrialDuration,nTrials,1);
result.camera.targetFrameCount = ...
    repmat(plannedFrameCount,nTrials,1);
result.camera.actualRecordTime_sec = nan(nTrials,1);
result.camera.actualFrameCount = zeros(nTrials,1);
result.camera.tiffFrameCount = zeros(nTrials,1);
result.camera.actualFPS = nan(nTrials,1);
result.camera.stopLatency_sec = nan(nTrials,1);
result.camera.preITI_sec = nan(nTrials,1);
result.camera.stimulus_sec = nan(nTrials,1);
result.camera.postITI_sec = nan(nTrials,1);
result.camera.tifFile = strings(nTrials,1);
result.camera.callbackError = strings(nTrials,1);
result.camera.frameTime_sec = cell(nTrials,1);
result.camera.frameNumber = cell(nTrials,1);
result.camera.frameAbsTime = cell(nTrials,1);
result.camera.frameMetadata = cell(nTrials,1);
result.camera.chunkTimestamp = cell(nTrials,1);
result.camera.frameTimestampCount = zeros(nTrials,1);
result.camera.timestampDerivedFPS = nan(nTrials,1);
result.camera.startGetSecs_sec = nan(nTrials,1);
result.camera.stopRequestGetSecs_sec = nan(nTrials,1);
result.camera.stopCompleteGetSecs_sec = nan(nTrials,1);

%% -------------------- Camera initialization --------------------
vid = [];
src = [];
wininfo = [];
cameraPreviewStarted = false;

activeTiff = [];
activeTiffFrameCount = 0;
activeTrialIndex = 0;
activeSessionType = "none";
activeGreenSessionIndex = 0;
activeCallbackError = [];
callbackIsWriting = false;
activeCameraFrameTime = zeros(0,1);
activeCameraFrameNumber = zeros(0,1);
activeCameraFrameAbsTime = zeros(0,6);
activeCameraFrameMetadata = struct([]);
activeCameraChunkTimestamp = cell(0,1);

% Shared quit state.
quitRequested = false;

% Cleanup is called explicitly on normal completion, q-abort, and errors.
% Do not use a nested-function onCleanup callback here because MATLAB can
% destroy the parent workspace before the callback reads captured variables.

imaqreset;

if strlength(string(result.camera_video_format)) == 0
    vid = videoinput('gentl',result.camera_device_id);
else
    vid = videoinput('gentl',result.camera_device_id, ...
        char(string(result.camera_video_format)));
end

src = getselectedsource(vid);
result.camera.videoFormat = string(vid.VideoFormat);
fprintf('Camera video format: %s\n',char(result.camera.videoFormat));

if contains(lower(result.camera.videoFormat),"mono8")
    warning(['Camera is acquiring Mono8. Low-amplitude red intrinsic ' ...
        'responses can be below one digital count per frame; use ' ...
        'camera_video_format to select an unpacked 12/16-bit ' ...
        'monochrome mode if supported.']);
end

triggerconfig(vid,'immediate');

vid.FramesPerTrigger = Inf;
vid.TriggerRepeat = 0;
vid.LoggingMode = 'memory';
vid.Timeout = max(10,ceil(plannedTrialDuration)+10);
vid.FramesAcquiredFcnCount = result.camera_tiff_chunk_frames;
vid.FramesAcquiredFcn = @realtime_tiff_callback;

try
    src.TriggerMode = 'Off';
catch ME
    warning('TriggerMode setting failed: %s',ME.message);
end

try
    src.AcquisitionFrameRateEnabled = 'True';
    src.AcquisitionFrameRate = result.camera_fps;
catch
    try
        src.AcquisitionFrameRateEnabled = 'On';
        src.AcquisitionFrameRate = result.camera_fps;
    catch ME
        warning('Frame-rate setting failed: %s',ME.message);
    end
end

try
    src.BalanceWhiteAuto = 'Off';
catch
end

result.camera.requestedFrameRate = result.camera_fps;
result.camera.requestedExposure_us = result.camera_exposure_us;
result.camera.requestedGain = result.camera_gain;
result.camera.requestedBlackLevel = result.camera_black_level;
result.camera.appliedSettingsBeforePreview = apply_camera_settings( ...
    result.camera_fps,result.camera_exposure_us,result.camera_gain, ...
    result.camera_black_level,"initialization");
result.camera.appliedSettingsDuringPreview = struct();

% Keep the preview in the camera's native bit depth. This avoids the
% Image Acquisition Toolbox converting a Mono12/Mono16 preview to 8-bit.
try
    vid.PreviewFullBitDepth = 'on';
catch ME
    warning('Full-bit-depth preview setting failed: %s',ME.message);
end

if result.camera_preview
    fprintf('\nOpening camera preview.\n');

    try
        preview(vid);
        cameraPreviewStarted = true;

        % Reapply settings after streaming starts. Some GenICam cameras do
        % not expose the new value in their first queued preview frames
        % even though the pre-preview property write succeeded.
        result.camera.appliedSettingsDuringPreview = ...
            apply_camera_settings(result.camera_fps, ...
            result.camera_exposure_us, ...
            result.camera_gain,result.camera_black_level, ...
            "initial preview");
    catch ME
        warning('Camera preview failed: %s',ME.message);
        cameraPreviewStarted = false;
    end

    if ~cameraPreviewStarted
        error(['Camera preview could not be started. Check the selected ' ...
            'device ID, adaptor support, and whether another program is ' ...
            'using the camera.']);
    end

    % Allow at least two newly configured frames to reach the preview.
    pause(max(0.5,2/result.camera_fps));
    drawnow;

    disp('Adjust camera, then press any key / q to abort.');

    % Ignore keys that are already held and wait for a new key press.
    % This keeps the preview responsive and avoids KbReleaseWait hanging
    % indefinitely on a device that reports a stuck key.
    previewKeyCode = wait_for_new_key(true);

    if previewKeyCode(KbName('q')) || ...
            previewKeyCode(KbName('Q'))
        quitRequested = true;
    end

    if quitRequested
        cleanup_resources();
        return;
    end

    if ~result.camera_preview_during_experiment
        closepreview(vid);
        cameraPreviewStarted = false;
        drawnow;
    end
end

% Create the output folders only after preview has been accepted. When
% camera_preview is disabled, create them immediately before display setup.
if ~exist(cameraRootFolder,'dir')
    mkdir(cameraRootFolder);
end

if ~exist(cameraDateFolder,'dir')
    mkdir(cameraDateFolder);
end

mkdir(cameraSessionFolder);

[result,fnameLocal,fnameRemote] = saveFilePrep(result);

fprintf('Camera files will be saved in: %s\n', ...
    result.camera_save_folder);

%% -------------------- Psychtoolbox initialization --------------------
try
    wininfo = gen_wininfo_uday(result);
catch ME
    cleanup_resources();
    rethrow(ME);
end

assignin('base','wininfo',wininfo);

result.image_mag = 10;
result.dispInfo.xRes = wininfo.xRes;
result.dispInfo.yRes = wininfo.yRes;
result.dispInfo.DScreen = result.DScreen;
result.dispInfo.VertScreenSize = result.VertScreenSize;
result.dispInfo.XDeg = wininfo.XDeg;
result.dispInfo.YDeg = wininfo.YDeg;

% The stimulus texture fills the logical framebuffer.  The earlier square
% destination rectangle used xRes for both axes; in this setup that drew a
% 640-by-640 texture into a 640-by-400 framebuffer and clipped 37.5% of the
% vertical trajectory.  Store the corrected geometry so the analysis can
% convert phase using the trajectory actually shown.
result.stimulus.destinationRect_pix = ...
    [0 0 wininfo.xRes wininfo.yRes];
result.stimulus.azimuthSpan_deg = wininfo.XDeg;
result.stimulus.elevationSpan_deg = wininfo.YDeg;
result.stimulus.matchElevationSpeed = result.match_elevation_speed;
result.stimulus.azimuthTrajectorySpan_deg = ...
    wininfo.XDeg + result.aperture_width_deg;
result.stimulus.elevationTrajectorySpan_deg = ...
    wininfo.YDeg + result.aperture_width_deg;
result.stimulus.azimuthPeriod_sec = result.contrast_period;

if result.match_elevation_speed
    % Match angular speed by shortening the elevation period. Extending the
    % vertical trajectory instead leaves the aperture completely off-screen
    % for part of every cycle on a landscape display.
    result.stimulus.elevationPeriod_sec = ...
        result.stimulus.elevationTrajectorySpan_deg / ...
        (result.stimulus.azimuthTrajectorySpan_deg / ...
        result.stimulus.azimuthPeriod_sec);
else
    result.stimulus.elevationPeriod_sec = result.contrast_period;
end

% The frequency-domain noise generator requires an even number of temporal
% samples. Quantize both periods to an even number of display frames and
% store the actual period that will be presented and analyzed.
result.stimulus.azimuthFramesPerSweep = max(2,2*round( ...
    result.stimulus.azimuthPeriod_sec*wininfo.frameRate/2));
result.stimulus.elevationFramesPerSweep = max(2,2*round( ...
    result.stimulus.elevationPeriod_sec*wininfo.frameRate/2));
result.stimulus.azimuthPeriod_sec = ...
    result.stimulus.azimuthFramesPerSweep/wininfo.frameRate;
result.stimulus.elevationPeriod_sec = ...
    result.stimulus.elevationFramesPerSweep/wininfo.frameRate;

result.block.period_sec = result.stimulus.azimuthPeriod_sec + ...
    blockAxis .* (result.stimulus.elevationPeriod_sec - ...
    result.stimulus.azimuthPeriod_sec);
result.green.block.period_sec = ...
    result.stimulus.azimuthPeriod_sec + greenBlockAxis .* ...
    (result.stimulus.elevationPeriod_sec - ...
    result.stimulus.azimuthPeriod_sec);

result.stimulus.azimuthSweepSpeed_deg_per_sec = ...
    result.stimulus.azimuthTrajectorySpan_deg / ...
    result.stimulus.azimuthPeriod_sec;
result.stimulus.elevationSweepSpeed_deg_per_sec = ...
    result.stimulus.elevationTrajectorySpan_deg / ...
    result.stimulus.elevationPeriod_sec;

fprintf(['Stimulus geometry: %.2f x %.2f deg, %.2f-deg aperture; ' ...
    'azimuth %.3f deg/s (%.3f sec), ' ...
    'elevation %.3f deg/s (%.3f sec).\n'], ...
    wininfo.XDeg,wininfo.YDeg,result.aperture_width_deg, ...
    result.stimulus.azimuthSweepSpeed_deg_per_sec, ...
    result.stimulus.azimuthPeriod_sec, ...
    result.stimulus.elevationSweepSpeed_deg_per_sec, ...
    result.stimulus.elevationPeriod_sec);

result.movieDurationFrames = ...
    round(max(result.block.period_sec) * wininfo.frameRate);
result.blockDurationFrames = ...
    result.movieDurationFrames * result.sweeps_per_block;

blockStimulusDuration_sec = ...
    result.block.period_sec * result.sweeps_per_block;
result.camera.plannedTrialDuration_sec = result.isipre + ...
    blockStimulusDuration_sec + result.isipost;
result.camera.targetFrameCount = round( ...
    result.camera.plannedTrialDuration_sec * result.camera_fps);

result.displayTiming.ptbFlipTime_sec = ...
    nan(nTrials,result.blockDurationFrames);
result.displayTiming.ptbMissedDeadline_sec = ...
    nan(nTrials,result.blockDurationFrames);

Screen('FillRect',wininfo.w,[128,128,128]);
Screen('TextFont',wininfo.w,'Courier New');
Screen('TextSize',wininfo.w,14);
Screen('TextStyle',wininfo.w,1+2);

topPriorityLevel = MaxPriority(wininfo.w);
Priority(topPriorityLevel);

%% -------------------- Green-light imaging --------------------
try
    repeatGreenSession = true;

    while repeatGreenSession
        Screen('FillRect',wininfo.w,[128,128,128]);
        Screen('DrawText',wininfo.w,'GREEN-LIGHT IMAGING', ...
            60,50,[0 255 0]);
        Screen('DrawText',wininfo.w, ...
            'Is the GREEN light ON? Press G to start / Q to abort.', ...
            60,75,[0 255 0]);
        Screen('Flip',wininfo.w);

        disp(['Is the GREEN light ON? Press G to start green-light ' ...
            'imaging / Q to abort.']);
        greenStartChoice = wait_for_choice({'g','q'},false);

        if strcmp(greenStartChoice,'q')
            quitRequested = true;
            break;
        end

        greenSessionIndex = result.green.sessionCount + 1;
        activeGreenSessionIndex = greenSessionIndex;
        run_green_imaging_session(greenSessionIndex);

        if quitRequested
            break;
        end

        Screen('FillRect',wininfo.w,[128,128,128]);
        Screen('DrawText',wininfo.w, ...
            'Green-light imaging completed.', ...
            60,50,[0 255 0]);
        Screen('DrawText',wininfo.w, ...
            ['Press R to repeat green-light imaging / ' ...
            'C to continue to the RED-light main experiment / ' ...
            'Q to abort.'], ...
            60,75,[0 255 0]);
        Screen('Flip',wininfo.w);

        disp(['Green-light imaging completed. Press R to repeat / ' ...
            'C to continue to the red-light main experiment / ' ...
            'Q to abort.']);
        greenEndChoice = wait_for_choice({'r','c','q'},false);

        if strcmp(greenEndChoice,'r')
            repeatGreenSession = true;
        elseif strcmp(greenEndChoice,'c')
            repeatGreenSession = false;
        else
            quitRequested = true;
            break;
        end
    end
catch ME
    cleanup_resources();

    try
        save(fnameLocal,'result','-v7.3');
    catch
    end

    rethrow(ME);
end

if quitRequested
    cleanup_resources();

    try
        save(fnameLocal,'result','-v7.3');
    catch ME
        warning('Partial result save failed: %s',ME.message);
    end

    return;
end

%% -------------------- Red-light main experiment --------------------
redExposure_us = result.camera_exposure_us;

if ~isempty(result.camera_red_exposure_us)
    redExposure_us = result.camera_red_exposure_us;
end

redGain = result.camera_gain;

if ~isempty(result.camera_red_gain)
    redGain = result.camera_red_gain;
end

result.redSetup.requestedExposure_us = result.camera_red_exposure_us;
result.redSetup.requestedGain = result.camera_red_gain;
result.redSetup.effectiveExposure_us = redExposure_us;
result.redSetup.effectiveGain = redGain;
result.redSetup.appliedSettingsBeforePreview = ...
    apply_camera_settings(result.camera_fps,redExposure_us,redGain, ...
    result.camera_black_level,"red setup");
result.redSetup.appliedSettingsDuringPreview = struct();
result.redSetup.previewIntensity = struct();

Screen('FillRect',wininfo.w,[128,128,128]);
Screen('DrawText',wininfo.w,strcat( ...
    num2str(result.block.repetitions),' direction-set repeats__', ...
    num2str(sum(result.camera.plannedTrialDuration_sec) / 60), ...
    ' min estimated Duration.'), ...
    60,50,[255 128 0]);

Screen('DrawText',wininfo.w,strcat( ...
    'RED >610 nm + correct filter; refocus 100-500 um below vessels. ', ...
    'Filename:',fnameLocal), ...
    60,70,[255 128 0]);

Screen('DrawText',wininfo.w, ...
    'Adjust red intensity in preview, then hit any key / q to abort.', ...
    60,90,[255 128 0]);

Screen('Flip',wininfo.w);

FlushEvents;
disp(['Turn RED illumination (>610 nm) and the matching optical ' ...
    'filter ON. Refocus 100-500 um below the surface vasculature, ' ...
    'adjust intensity without saturation, then hit any key / q to abort.']);

if result.red_setup_preview
    try
        preview(vid);
        cameraPreviewStarted = true;
        result.redSetup.appliedSettingsDuringPreview = ...
            apply_camera_settings(result.camera_fps, ...
            redExposure_us,redGain, ...
            result.camera_black_level,"red preview");
        pause(max(0.5,2/result.camera_fps));
        drawnow;
    catch ME
        warning('Red setup preview failed: %s',ME.message);
        cameraPreviewStarted = false;
    end
end

startKeyCode = wait_for_new_key(false);

if cameraPreviewStarted
    try
        previewFrameRaw = getsnapshot(vid);

        if isinteger(previewFrameRaw)
            previewMaximum = double(intmax(class(previewFrameRaw)));
            formatBitDepth = regexpi( ...
                char(result.camera.videoFormat),'Mono(\d+)', ...
                'tokens','once');

            if ~isempty(formatBitDepth)
                previewMaximum = min(previewMaximum, ...
                    2^str2double(formatBitDepth{1})-1);
            end
        else
            previewMaximum = double(max(previewFrameRaw(:)));
        end

        if ndims(previewFrameRaw) == 3
            previewFrame = mean(double(previewFrameRaw),3);
        else
            previewFrame = double(previewFrameRaw);
        end

        previewValues = previewFrame(isfinite(previewFrame));

        result.redSetup.previewIntensity.p01 = ...
            prctile(previewValues,1);
        result.redSetup.previewIntensity.median = ...
            median(previewValues);
        result.redSetup.previewIntensity.p99 = ...
            prctile(previewValues,99);
        result.redSetup.previewIntensity.maximumPossible = ...
            previewMaximum;
        result.redSetup.previewIntensity.saturatedFraction = ...
            mean(previewValues >= previewMaximum);

        fprintf(['Red preview intensity: p1=%.1f, median=%.1f, ' ...
            'p99=%.1f / %.1f, saturated=%.4f%%.\n'], ...
            result.redSetup.previewIntensity.p01, ...
            result.redSetup.previewIntensity.median, ...
            result.redSetup.previewIntensity.p99,previewMaximum, ...
            100*result.redSetup.previewIntensity.saturatedFraction);

        if result.redSetup.previewIntensity.p99 < 0.55*previewMaximum
            warning(['Red preview uses less than 55%% of the camera ' ...
                'range. Increase red illumination/exposure if safe.']);
        elseif result.redSetup.previewIntensity.saturatedFraction > 0.001
            warning(['More than 0.1%% of red-preview pixels are ' ...
                'saturated. Reduce illumination/exposure.']);
        end
    catch ME
        warning('Red preview intensity QC failed: %s',ME.message);
    end

    closepreview(vid);
    cameraPreviewStarted = false;
    drawnow;
end

if startKeyCode(KbName('q')) || startKeyCode(KbName('Q'))
    quitRequested = true;
    cleanup_resources();
    return;
end

Screen('DrawTexture',wininfo.w,wininfo.BG);
Screen('Flip',wininfo.w);

result.starttime = datestr(now);
t0 = GetSecs;
result.clock.ptbT0GetSecs_sec = t0;
capture_clock_anchor("session_start",0);
result.tr_num = 0;
result.block.firstStimFlip_sec = nan(nTrials,1);
result.block.lastStimFlip_sec = nan(nTrials,1);
result.block.sweepFirstFlip_sec = ...
    nan(nTrials,result.sweeps_per_block);
result.block.sweepLastFlip_sec = ...
    nan(nTrials,result.sweeps_per_block);

%% -------------------- Non-triggered stimulus and camera loop --------------------
try
    for istimNT = 1:result.repetitions
        if check_for_quit()
            break;
        end

        result.tr_num = result.tr_num + 1;
        result.block.currentName = blockNames(istimNT);
        result.dirflag = blockAxis(istimNT);
        result.reverseflag = logical(blockReverse(istimNT));
        result.current_period_sec = result.block.period_sec(istimNT);
        result.movieDurationFrames = round( ...
            result.current_period_sec * wininfo.frameRate);
        result.blockDurationFrames = ...
            result.movieDurationFrames * result.sweeps_per_block;
        result.stimduration = ...
            result.current_period_sec * result.sweeps_per_block;
        result = get_movie_stim(result);

        activeTrialIndex = result.tr_num;
        activeSessionType = "red";
        activeGreenSessionIndex = 0;
        activeCallbackError = [];
        capture_clock_anchor( ...
            sprintf('block_%d_start',result.tr_num), ...
            result.tr_num);

        fprintf('\nBlock %d/%d: %s, %d sweeps x %.3f sec\n', ...
            istimNT,nTrials,char(blockNames(istimNT)), ...
            result.sweeps_per_block,result.current_period_sec);

        tifFile = fullfile(result.camera_save_folder, ...
            sprintf('red_block%02d_%s.tif',result.tr_num, ...
            char(blockNames(istimNT))));

        if exist(tifFile,'file')
            delete(tifFile);
        end

        activeTiffFrameCount = 0;
        activeCameraFrameTime = zeros(0,1);
        activeCameraFrameNumber = zeros(0,1);
        activeCameraFrameAbsTime = zeros(0,6);
        activeCameraFrameMetadata = struct([]);
        activeCameraChunkTimestamp = cell(0,1);
        activeTiff = Tiff(tifFile,'w8');
        result.camera.tifFile(result.tr_num) = string(tifFile);

        flushdata(vid);

        fprintf('\nTrial %04d camera start: %s\n', ...
            result.tr_num-1,tifFile);

        start(vid);
        cameraStart = GetSecs;
        result.camera.startGetSecs_sec(result.tr_num) = cameraStart;

        % Complete pre-ITI is recorded.
        WaitSecs(result.isipre);
        capture_clock_anchor( ...
            sprintf('block_%d_pre_stimulus',result.tr_num), ...
            result.tr_num);
        preEnd = GetSecs;
        result.camera.preITI_sec(result.tr_num) = ...
            preEnd - cameraStart;

        % Complete stimulus is recorded.
        [firstStimFlip,lastStimFlip] = ...
            display_grating(wininfo,result);

        if quitRequested
            if isrunning(vid)
                stop(vid);
            end

            while vid.FramesAvailable > 0
                drain_camera_buffer_to_tiff(vid);
            end

            store_camera_frame_timestamps(result.tr_num);

            if ~isempty(activeTiff)
                close(activeTiff);
                activeTiff = [];
            end

            capture_clock_anchor( ...
                sprintf('block_%d_aborted',result.tr_num), ...
                result.tr_num);
            break;
        end

        capture_clock_anchor( ...
            sprintf('block_%d_post_stimulus',result.tr_num), ...
            result.tr_num);

        result.timestamp(result.tr_num) = firstStimFlip - t0;
        result.block.firstStimFlip_sec(result.tr_num) = ...
            firstStimFlip - t0;
        result.block.lastStimFlip_sec(result.tr_num) = ...
            lastStimFlip - t0;
        result.camera.stimulus_sec(result.tr_num) = ...
            lastStimFlip - firstStimFlip;

        % Complete post-ITI is recorded.
        postStart = GetSecs;
        WaitSecs(result.isipost);
        postEnd = GetSecs;
        result.camera.postITI_sec(result.tr_num) = ...
            postEnd - postStart;

        % Timestamp the requested acquisition end before stop(). Some
        % adaptors block inside stop() while finalizing the acquisition;
        % that latency is not part of the camera recording duration.
        cameraStopRequest = GetSecs;
        result.camera.stopRequestGetSecs_sec(result.tr_num) = ...
            cameraStopRequest;

        if isrunning(vid)
            stop(vid);
        end

        cameraStopComplete = GetSecs;
        result.camera.stopCompleteGetSecs_sec(result.tr_num) = ...
            cameraStopComplete;
        result.camera.actualRecordTime_sec(result.tr_num) = ...
            cameraStopRequest - cameraStart;
        result.camera.stopLatency_sec(result.tr_num) = ...
            cameraStopComplete - cameraStopRequest;
        result.camera.actualFrameCount(result.tr_num) = ...
            vid.FramesAcquired;

        % Write every frame still left in the acquisition buffer.
        drainTimer = tic;
        while vid.FramesAvailable > 0
            drain_camera_buffer_to_tiff(vid);

            if toc(drainTimer) > ...
                    result.camera_final_drain_timeout_sec
                error('Final TIFF drain timed out.');
            end
        end

        if ~isempty(activeCallbackError)
            result.camera.callbackError(result.tr_num) = ...
                string(activeCallbackError.message);
            rethrow(activeCallbackError);
        end

        result.camera.tiffFrameCount(result.tr_num) = ...
            activeTiffFrameCount;
        store_camera_frame_timestamps(result.tr_num);

        if result.camera.actualRecordTime_sec(result.tr_num) > 0
            result.camera.actualFPS(result.tr_num) = ...
                result.camera.actualFrameCount(result.tr_num) / ...
                result.camera.actualRecordTime_sec(result.tr_num);
        end

        close(activeTiff);
        activeTiff = [];

        capture_clock_anchor( ...
            sprintf('block_%d_end',result.tr_num), ...
            result.tr_num);

        fprintf('Recorded %.3f sec, camera frames=%d, TIFF frames=%d\n', ...
            result.camera.actualRecordTime_sec(result.tr_num), ...
            result.camera.actualFrameCount(result.tr_num), ...
            result.camera.tiffFrameCount(result.tr_num));

        if result.camera.actualFrameCount(result.tr_num) ~= ...
                result.camera.tiffFrameCount(result.tr_num)
            warning('Camera and TIFF frame counts do not match.');
        end

        if result.camera.frameTimestampCount(result.tr_num) ~= ...
                result.camera.tiffFrameCount(result.tr_num)
            warning(['Camera timestamp and TIFF frame counts do not ' ...
                'match in block %d.'],result.tr_num);
        end

        save(fnameLocal,'result','-v7.3');

        if result.save_remote
            save(fnameRemote,'result','-v7.3');
        end
    end

    if quitRequested
        fprintf('Experiment stopped by user.\n');
        capture_clock_anchor("session_end",activeTrialIndex);
        cleanup_resources();

        try
            save(fnameLocal,'result','-v7.3');

            if result.save_remote
                save(fnameRemote,'result','-v7.3');
            end
        catch ME
            warning('Partial result save failed: %s',ME.message);
        end

        return;
    end

    capture_clock_anchor("session_end",0);

    %% -------------------- Summary CSV --------------------
    Priority(0);

    summaryFile = fullfile(result.camera_save_folder, ...
        sprintf('%s_frame_count_summary.csv',sessionName));

    Trial = (1:nTrials)';
    BlockCondition = result.block.names;
    PlannedRecordTime_sec = ...
        result.camera.plannedTrialDuration_sec;
    TargetFrameCount = ...
        result.camera.targetFrameCount;
    ActualRecordTime_sec = ...
        result.camera.actualRecordTime_sec;
    ActualFrameCount = ...
        result.camera.actualFrameCount;
    TIFFFrameCount = ...
        result.camera.tiffFrameCount;
    ActualFPS = ...
        result.camera.actualFPS;
    CameraStopLatency_sec = ...
        result.camera.stopLatency_sec;
    CameraTimestampCount = ...
        result.camera.frameTimestampCount;
    TimestampDerivedFPS = ...
        result.camera.timestampDerivedFPS;
    PreITI_sec = ...
        result.camera.preITI_sec;
    Stimulus_sec = ...
        result.camera.stimulus_sec;
    PostITI_sec = ...
        result.camera.postITI_sec;
    TIFF_File = ...
        result.camera.tifFile;
    CallbackError = ...
        result.camera.callbackError;
    PTBMissedDisplayFrames = sum( ...
        result.displayTiming.ptbMissedDeadline_sec > 0,2);

    T = table(Trial,BlockCondition, ...
        PlannedRecordTime_sec,TargetFrameCount, ...
        ActualRecordTime_sec,ActualFrameCount,TIFFFrameCount, ...
        ActualFPS,CameraStopLatency_sec, ...
        CameraTimestampCount,TimestampDerivedFPS, ...
        PreITI_sec,Stimulus_sec,PostITI_sec, ...
        PTBMissedDisplayFrames, ...
        TIFF_File,CallbackError);

    writetable(T,summaryFile);
    result.camera.summaryFile = summaryFile;

    disp(T);

    save(fnameLocal,'result','-v7.3');

    if result.save_remote
        save(fnameRemote,'result','-v7.3');
    end

    cleanup_resources();

catch ME
    try
        capture_clock_anchor("session_error",activeTrialIndex);
    catch
    end

    cleanup_resources();

    try
        save(fnameLocal,'result','-v7.3');
    catch
    end

    rethrow(ME);
end

if ~quitRequested
    disp('Experiment and camera recording completed.');
end

%%%%% ALL THE INNER FXNS %%%%%

    function appliedSettings = apply_camera_settings( ...
            requestedFPS,requestedExposure_us,requestedGain, ...
            requestedBlackLevel,settingContext)
        % Write dependent GenICam settings in controller-first order and
        % read them back. Repeating a write handles devices that expose a
        % stale value briefly while their acquisition state is changing.
        appliedSettings = struct();
        appliedSettings.context = string(settingContext);

        [appliedSettings.frameRate, ...
            appliedSettings.frameRateVerified, ...
            appliedSettings.frameRateCommanded, ...
            appliedSettings.frameRateLimits] = ...
            set_camera_property_verified( ...
            'AcquisitionFrameRate',requestedFPS,settingContext);

        [appliedSettings.exposureAuto, ...
            appliedSettings.exposureAutoVerified] = ...
            set_camera_property_verified( ...
            'ExposureAuto','Off',settingContext);
        [appliedSettings.exposureTime_us, ...
            appliedSettings.exposureTimeVerified, ...
            appliedSettings.exposureTimeCommanded_us, ...
            appliedSettings.exposureTimeLimits_us] = ...
            set_camera_property_verified( ...
            'ExposureTime',requestedExposure_us,settingContext);

        [appliedSettings.gainAuto, ...
            appliedSettings.gainAutoVerified] = ...
            set_camera_property_verified( ...
            'GainAuto','Off',settingContext);
        [appliedSettings.gain,appliedSettings.gainVerified, ...
            appliedSettings.gainCommanded, ...
            appliedSettings.gainLimits] = ...
            set_camera_property_verified( ...
            'Gain',requestedGain,settingContext);

        [appliedSettings.blackLevel, ...
            appliedSettings.blackLevelVerified, ...
            appliedSettings.blackLevelCommanded, ...
            appliedSettings.blackLevelLimits] = ...
            set_camera_property_verified( ...
            'BlackLevel',requestedBlackLevel,settingContext);

        fprintf(['Camera settings [%s], requested -> applied: ' ...
            'FPS %s -> %s, exposure %s -> %s us, ' ...
            'gain %s -> %s, black level %s -> %s.\n'], ...
            char(string(settingContext)), ...
            camera_value_to_text(requestedFPS), ...
            camera_value_to_text(appliedSettings.frameRate), ...
            camera_value_to_text(requestedExposure_us), ...
            camera_value_to_text(appliedSettings.exposureTime_us), ...
            camera_value_to_text(requestedGain), ...
            camera_value_to_text(appliedSettings.gain), ...
            camera_value_to_text(requestedBlackLevel), ...
            camera_value_to_text(appliedSettings.blackLevel));
    end

    function [appliedValue,isVerified,commandedValue, ...
            constraintLimits] = ...
            set_camera_property_verified( ...
            propertyName,requestedValue,settingContext)
        propertyName = char(string(propertyName));
        appliedValue = [];
        isVerified = false;
        commandedValue = requestedValue;
        constraintLimits = [];
        lastErrorMessage = "";
        maxAttempts = 3;

        if isnumeric(requestedValue) && isscalar(requestedValue)
            try
                propertyInfo = propinfo(src,propertyName);

                if strcmpi(propertyInfo.Constraint,'bounded') && ...
                        isnumeric(propertyInfo.ConstraintValue) && ...
                        numel(propertyInfo.ConstraintValue) >= 2
                    constraintLimits = double( ...
                        propertyInfo.ConstraintValue([1,end]));
                    commandedValue = min(max(double(requestedValue), ...
                        constraintLimits(1)),constraintLimits(2));

                    if commandedValue ~= double(requestedValue)
                        warning( ...
                            ['run_cmnoise_green_red:' ...
                            'CameraSettingAdjusted'], ...
                            ['Camera setting %s [%s] requested %s, ' ...
                            'but the current allowed range is ' ...
                            '[%s, %s]. Applying %s instead.'], ...
                            propertyName,char(string(settingContext)), ...
                            camera_value_to_text(requestedValue), ...
                            camera_value_to_text(constraintLimits(1)), ...
                            camera_value_to_text(constraintLimits(2)), ...
                            camera_value_to_text(commandedValue));
                    end
                end
            catch ME
                % A missing constraint must not prevent the normal property
                % write. Preserve the diagnostic in case that write fails.
                lastErrorMessage = string(ME.message);
            end
        end

        for settingAttempt = 1:maxAttempts
            try
                src.(propertyName) = commandedValue;
                pause(0.05);
                appliedValue = src.(propertyName);

                if camera_property_values_match( ...
                        commandedValue,appliedValue)
                    isVerified = true;
                    return;
                end
            catch ME
                lastErrorMessage = string(ME.message);
            end

            pause(0.05*settingAttempt);
        end

        if strlength(lastErrorMessage) > 0
            warning('run_cmnoise_green_red:CameraSettingNotApplied', ...
                ['Camera setting %s [%s] could not be applied. ' ...
                'Requested %s, commanded %s. Last error: %s'], ...
                propertyName,char(string(settingContext)), ...
                camera_value_to_text(requestedValue), ...
                camera_value_to_text(commandedValue), ...
                char(lastErrorMessage));
        else
            warning('run_cmnoise_green_red:CameraSettingNotVerified', ...
                ['Camera setting %s [%s] did not match after %d ' ...
                'attempts. Commanded %s, read back %s.'], ...
                propertyName,char(string(settingContext)),maxAttempts, ...
                camera_value_to_text(commandedValue), ...
                camera_value_to_text(appliedValue));
        end
    end

    function valuesMatch = camera_property_values_match( ...
            requestedValue,appliedValue)
        if (isnumeric(requestedValue) || islogical(requestedValue)) && ...
                (isnumeric(appliedValue) || islogical(appliedValue)) && ...
                isscalar(requestedValue) && isscalar(appliedValue)
            requestedNumeric = double(requestedValue);
            appliedNumeric = double(appliedValue);
            numericTolerance = max(1e-6, ...
                1e-3*max(1,abs(requestedNumeric)));
            valuesMatch = isfinite(appliedNumeric) && ...
                abs(appliedNumeric-requestedNumeric) <= numericTolerance;
        else
            valuesMatch = strcmpi(strtrim(string(appliedValue)), ...
                strtrim(string(requestedValue)));
        end
    end

    function valueText = camera_value_to_text(value)
        if isempty(value)
            valueText = '<unavailable>';
        elseif isnumeric(value) || islogical(value)
            valueText = sprintf('%.9g',double(value));
        else
            valueText = char(string(value));
        end
    end

    function run_green_imaging_session(sessionIndex)
        validateattributes(sessionIndex,{'numeric'}, ...
            {'scalar','integer','positive'});
        nGreenBlocks = numel(greenBlockNames);
        greenBlockPeriods_sec = result.green.block.period_sec(:);
        greenStimDuration_sec = ...
            greenBlockPeriods_sec * greenSweepsPerBlock;
        greenPlannedTrialDuration_sec = result.isipre + ...
            greenStimDuration_sec + result.isipost;
        greenPlannedFrameCount = round( ...
            greenPlannedTrialDuration_sec * result.camera_fps);
        greenMovieDurationFrames = round( ...
            greenBlockPeriods_sec * wininfo.frameRate);
        maxGreenBlockDurationFrames = ...
            max(greenMovieDurationFrames) * greenSweepsPerBlock;

        result.green.sessionCount = sessionIndex;
        result.green.sessions(sessionIndex).sessionIndex = sessionIndex;
        result.green.sessions(sessionIndex).starttime = datestr(now);
        result.green.sessions(sessionIndex).endtime = '';
        result.green.sessions(sessionIndex).completed = false;
        result.green.sessions(sessionIndex).block.names = ...
            greenBlockNames;
        result.green.sessions(sessionIndex).block.axis = ...
            greenBlockAxis;
        result.green.sessions(sessionIndex).block.reverse = ...
            logical(greenBlockReverse);
        result.green.sessions(sessionIndex).block.period_sec = ...
            greenBlockPeriods_sec;
        result.green.sessions(sessionIndex).block.firstStimFlip_sec = ...
            nan(nGreenBlocks,1);
        result.green.sessions(sessionIndex).block.lastStimFlip_sec = ...
            nan(nGreenBlocks,1);
        result.green.sessions(sessionIndex).block.sweepFirstFlip_sec = ...
            nan(nGreenBlocks,greenSweepsPerBlock);
        result.green.sessions(sessionIndex).block.sweepLastFlip_sec = ...
            nan(nGreenBlocks,greenSweepsPerBlock);
        result.green.sessions(sessionIndex).contrast = ...
            nan(nGreenBlocks,1);
        result.green.sessions(sessionIndex).timestamp = ...
            nan(nGreenBlocks,1);
        result.green.sessions(sessionIndex).displayTiming.ptbFlipTime_sec = ...
            nan(nGreenBlocks,maxGreenBlockDurationFrames);
        result.green.sessions( ...
            sessionIndex).displayTiming.ptbMissedDeadline_sec = ...
            nan(nGreenBlocks,maxGreenBlockDurationFrames);

        result.green.sessions( ...
            sessionIndex).camera.plannedTrialDuration_sec = ...
            greenPlannedTrialDuration_sec;
        result.green.sessions(sessionIndex).camera.targetFrameCount = ...
            greenPlannedFrameCount;
        result.green.sessions(sessionIndex).camera.actualRecordTime_sec = ...
            nan(nGreenBlocks,1);
        result.green.sessions(sessionIndex).camera.actualFrameCount = ...
            zeros(nGreenBlocks,1);
        result.green.sessions(sessionIndex).camera.tiffFrameCount = ...
            zeros(nGreenBlocks,1);
        result.green.sessions(sessionIndex).camera.actualFPS = ...
            nan(nGreenBlocks,1);
        result.green.sessions(sessionIndex).camera.stopLatency_sec = ...
            nan(nGreenBlocks,1);
        result.green.sessions(sessionIndex).camera.preITI_sec = ...
            nan(nGreenBlocks,1);
        result.green.sessions(sessionIndex).camera.stimulus_sec = ...
            nan(nGreenBlocks,1);
        result.green.sessions(sessionIndex).camera.postITI_sec = ...
            nan(nGreenBlocks,1);
        result.green.sessions(sessionIndex).camera.tifFile = ...
            strings(nGreenBlocks,1);
        result.green.sessions(sessionIndex).camera.callbackError = ...
            strings(nGreenBlocks,1);
        result.green.sessions(sessionIndex).camera.frameTime_sec = ...
            cell(nGreenBlocks,1);
        result.green.sessions(sessionIndex).camera.frameNumber = ...
            cell(nGreenBlocks,1);
        result.green.sessions(sessionIndex).camera.frameAbsTime = ...
            cell(nGreenBlocks,1);
        result.green.sessions(sessionIndex).camera.frameMetadata = ...
            cell(nGreenBlocks,1);
        result.green.sessions(sessionIndex).camera.chunkTimestamp = ...
            cell(nGreenBlocks,1);
        result.green.sessions( ...
            sessionIndex).camera.frameTimestampCount = ...
            zeros(nGreenBlocks,1);
        result.green.sessions( ...
            sessionIndex).camera.timestampDerivedFPS = ...
            nan(nGreenBlocks,1);
        result.green.sessions(sessionIndex).camera.startGetSecs_sec = ...
            nan(nGreenBlocks,1);
        result.green.sessions( ...
            sessionIndex).camera.stopRequestGetSecs_sec = ...
            nan(nGreenBlocks,1);
        result.green.sessions( ...
            sessionIndex).camera.stopCompleteGetSecs_sec = ...
            nan(nGreenBlocks,1);

        greenSessionT0 = GetSecs;
        result.green.sessions(sessionIndex).ptbT0GetSecs_sec = ...
            greenSessionT0;
        capture_clock_anchor( ...
            sprintf('green_session_%d_start',sessionIndex),0);

        fprintf(['\nGreen-light imaging session %d: %d blocks x ' ...
            '%d sweeps; azimuth %.3f sec/sweep, elevation %.3f ' ...
            'sec/sweep\n'],sessionIndex,nGreenBlocks, ...
            greenSweepsPerBlock,result.stimulus.azimuthPeriod_sec, ...
            result.stimulus.elevationPeriod_sec);

        for greenBlockIdx = 1:nGreenBlocks
            if check_for_quit()
                break;
            end

            activeSessionType = "green";
            activeGreenSessionIndex = sessionIndex;
            activeTrialIndex = greenBlockIdx;
            activeCallbackError = [];
            capture_clock_anchor(sprintf( ...
                'green_session_%d_block_%d_start', ...
                sessionIndex,greenBlockIdx),greenBlockIdx);

            greenStim = result;
            greenStim.tr_num = greenBlockIdx;
            greenStim.sweeps_per_block = greenSweepsPerBlock;
            greenStim.current_period_sec = ...
                greenBlockPeriods_sec(greenBlockIdx);
            greenStim.movieDurationFrames = ...
                greenMovieDurationFrames(greenBlockIdx);
            greenStim.stimduration = ...
                greenStimDuration_sec(greenBlockIdx);
            greenStim.blockDurationFrames = ...
                greenStim.movieDurationFrames * greenSweepsPerBlock;
            greenStim.dirflag = greenBlockAxis(greenBlockIdx);
            greenStim.reverseflag = ...
                logical(greenBlockReverse(greenBlockIdx));
            greenStim.moviedata = cell(nGreenBlocks,1);
            greenStim.tex = [];
            greenStim.contrasts_by_trial = nan(nGreenBlocks,1);
            greenStim = get_movie_stim(greenStim);
            result.green.sessions(sessionIndex).contrast( ...
                greenBlockIdx) = greenStim.contrast;

            fprintf(['\nGreen session %d, block %d/%d: %s, ' ...
                '%d sweeps x %.3f sec\n'], ...
                sessionIndex,greenBlockIdx,nGreenBlocks, ...
                char(greenBlockNames(greenBlockIdx)), ...
                greenSweepsPerBlock,greenStim.current_period_sec);

            tifFile = fullfile(result.camera_save_folder, ...
                sprintf('green_session%02d_block%02d_%s.tif', ...
                sessionIndex,greenBlockIdx, ...
                char(greenBlockNames(greenBlockIdx))));

            if exist(tifFile,'file')
                delete(tifFile);
            end

            activeTiffFrameCount = 0;
            activeCameraFrameTime = zeros(0,1);
            activeCameraFrameNumber = zeros(0,1);
            activeCameraFrameAbsTime = zeros(0,6);
            activeCameraFrameMetadata = struct([]);
            activeCameraChunkTimestamp = cell(0,1);
            activeTiff = Tiff(tifFile,'w8');
            result.green.sessions(sessionIndex).camera.tifFile( ...
                greenBlockIdx) = string(tifFile);

            flushdata(vid);
            fprintf('\nGreen block %02d camera start: %s\n', ...
                greenBlockIdx,tifFile);

            start(vid);
            cameraStart = GetSecs;
            result.green.sessions( ...
                sessionIndex).camera.startGetSecs_sec( ...
                greenBlockIdx) = cameraStart;

            WaitSecs(result.isipre);
            capture_clock_anchor(sprintf( ...
                'green_session_%d_block_%d_pre_stimulus', ...
                sessionIndex,greenBlockIdx),greenBlockIdx);
            preEnd = GetSecs;
            result.green.sessions(sessionIndex).camera.preITI_sec( ...
                greenBlockIdx) = preEnd - cameraStart;

            [firstStimFlip,lastStimFlip,flipTimes,missedDeadlines, ...
                sweepFirstFlips,sweepLastFlips] = ...
                display_green_grating(wininfo,greenStim);

            if quitRequested
                if isrunning(vid)
                    stop(vid);
                end

                while vid.FramesAvailable > 0
                    drain_camera_buffer_to_tiff(vid);
                end

                store_camera_frame_timestamps(greenBlockIdx);

                if ~isempty(activeTiff)
                    close(activeTiff);
                    activeTiff = [];
                end

                capture_clock_anchor(sprintf( ...
                    'green_session_%d_block_%d_aborted', ...
                    sessionIndex,greenBlockIdx),greenBlockIdx);
                save(fnameLocal,'result','-v7.3');
                return;
            end

            capture_clock_anchor(sprintf( ...
                'green_session_%d_block_%d_post_stimulus', ...
                sessionIndex,greenBlockIdx),greenBlockIdx);

            result.green.sessions(sessionIndex).timestamp( ...
                greenBlockIdx) = firstStimFlip - greenSessionT0;
            result.green.sessions( ...
                sessionIndex).block.firstStimFlip_sec( ...
                greenBlockIdx) = firstStimFlip - greenSessionT0;
            result.green.sessions( ...
                sessionIndex).block.lastStimFlip_sec( ...
                greenBlockIdx) = lastStimFlip - greenSessionT0;
            result.green.sessions( ...
                sessionIndex).block.sweepFirstFlip_sec( ...
                greenBlockIdx,:) = sweepFirstFlips - greenSessionT0;
            result.green.sessions( ...
                sessionIndex).block.sweepLastFlip_sec( ...
                greenBlockIdx,:) = sweepLastFlips - greenSessionT0;
            result.green.sessions( ...
                sessionIndex).displayTiming.ptbFlipTime_sec( ...
                greenBlockIdx,1:numel(flipTimes)) = ...
                flipTimes - greenSessionT0;
            result.green.sessions( ...
                sessionIndex).displayTiming.ptbMissedDeadline_sec( ...
                greenBlockIdx,1:numel(missedDeadlines)) = ...
                missedDeadlines;
            result.green.sessions(sessionIndex).camera.stimulus_sec( ...
                greenBlockIdx) = lastStimFlip - firstStimFlip;

            postStart = GetSecs;
            WaitSecs(result.isipost);
            postEnd = GetSecs;
            result.green.sessions(sessionIndex).camera.postITI_sec( ...
                greenBlockIdx) = postEnd - postStart;

            cameraStopRequest = GetSecs;
            result.green.sessions( ...
                sessionIndex).camera.stopRequestGetSecs_sec( ...
                greenBlockIdx) = cameraStopRequest;

            if isrunning(vid)
                stop(vid);
            end

            cameraStopComplete = GetSecs;
            result.green.sessions( ...
                sessionIndex).camera.stopCompleteGetSecs_sec( ...
                greenBlockIdx) = cameraStopComplete;
            result.green.sessions( ...
                sessionIndex).camera.actualRecordTime_sec( ...
                greenBlockIdx) = cameraStopRequest - cameraStart;
            result.green.sessions(sessionIndex).camera.stopLatency_sec( ...
                greenBlockIdx) = cameraStopComplete - cameraStopRequest;
            result.green.sessions( ...
                sessionIndex).camera.actualFrameCount( ...
                greenBlockIdx) = vid.FramesAcquired;

            drainTimer = tic;
            while vid.FramesAvailable > 0
                drain_camera_buffer_to_tiff(vid);

                if toc(drainTimer) > ...
                        result.camera_final_drain_timeout_sec
                    error('Final green-session TIFF drain timed out.');
                end
            end

            if ~isempty(activeCallbackError)
                result.green.sessions( ...
                    sessionIndex).camera.callbackError( ...
                    greenBlockIdx) = ...
                    string(activeCallbackError.message);
                rethrow(activeCallbackError);
            end

            result.green.sessions( ...
                sessionIndex).camera.tiffFrameCount( ...
                greenBlockIdx) = activeTiffFrameCount;
            store_camera_frame_timestamps(greenBlockIdx);

            if result.green.sessions( ...
                    sessionIndex).camera.actualRecordTime_sec( ...
                    greenBlockIdx) > 0
                result.green.sessions(sessionIndex).camera.actualFPS( ...
                    greenBlockIdx) = ...
                    result.green.sessions( ...
                    sessionIndex).camera.actualFrameCount( ...
                    greenBlockIdx) / ...
                    result.green.sessions( ...
                    sessionIndex).camera.actualRecordTime_sec( ...
                    greenBlockIdx);
            end

            close(activeTiff);
            activeTiff = [];

            capture_clock_anchor(sprintf( ...
                'green_session_%d_block_%d_end', ...
                sessionIndex,greenBlockIdx),greenBlockIdx);

            fprintf(['Green block recorded %.3f sec, camera ' ...
                'frames=%d, TIFF frames=%d\n'], ...
                result.green.sessions( ...
                sessionIndex).camera.actualRecordTime_sec( ...
                greenBlockIdx), ...
                result.green.sessions( ...
                sessionIndex).camera.actualFrameCount( ...
                greenBlockIdx), ...
                result.green.sessions( ...
                sessionIndex).camera.tiffFrameCount( ...
                greenBlockIdx));

            if result.green.sessions( ...
                    sessionIndex).camera.actualFrameCount( ...
                    greenBlockIdx) ~= ...
                    result.green.sessions( ...
                    sessionIndex).camera.tiffFrameCount( ...
                    greenBlockIdx)
                warning(['Green session camera and TIFF frame ' ...
                    'counts do not match.']);
            end

            if result.green.sessions( ...
                    sessionIndex).camera.frameTimestampCount( ...
                    greenBlockIdx) ~= ...
                    result.green.sessions( ...
                    sessionIndex).camera.tiffFrameCount( ...
                    greenBlockIdx)
                warning(['Green session timestamp and TIFF frame ' ...
                    'counts do not match in block %d.'],greenBlockIdx);
            end

            save(fnameLocal,'result','-v7.3');

            if result.save_remote
                save(fnameRemote,'result','-v7.3');
            end
        end

        if ~quitRequested
            result.green.sessions(sessionIndex).completed = true;
            result.green.sessions(sessionIndex).endtime = datestr(now);
            capture_clock_anchor(sprintf( ...
                'green_session_%d_end',sessionIndex),0);
            save(fnameLocal,'result','-v7.3');

            if result.save_remote
                save(fnameRemote,'result','-v7.3');
            end
        end

        activeSessionType = "none";
        activeGreenSessionIndex = 0;
        activeTrialIndex = 0;
    end

    function [firstFlip,lastFlip,flipTimes,missedDeadlines, ...
            sweepFirstFlips,sweepLastFlips] = ...
            display_green_grating(wininfoLocal,thisstim)

        nSweeps = thisstim.sweeps_per_block;
        nBlockFrames = thisstim.movieDurationFrames * nSweeps;
        firstFlip = NaN;
        lastFlip = NaN;
        flipTimes = nan(1,nBlockFrames);
        missedDeadlines = nan(1,nBlockFrames);
        sweepFirstFlips = nan(1,nSweeps);
        sweepLastFlips = nan(1,nSweeps);

        for sweepIdx = 1:nSweeps
            for itex = 1:thisstim.movieDurationFrames
                if check_for_quit()
                    break;
                end

                Screen('DrawTexture',wininfoLocal.w, ...
                    thisstim.tex(itex),[], ...
                    thisstim.stimulus.destinationRect_pix);

                blockFrameIdx = ...
                    (sweepIdx-1)*thisstim.movieDurationFrames + itex;

                if isnan(lastFlip)
                    [currentFlip,~,~,~] = ...
                        Screen('Flip',wininfoLocal.w);
                    missedDeadline = NaN;
                else
                    nextFlipDeadline = ...
                        lastFlip + 0.5*wininfoLocal.ifi;
                    [currentFlip,~,~,missedDeadline] = ...
                        Screen('Flip',wininfoLocal.w, ...
                        nextFlipDeadline);
                end

                flipTimes(blockFrameIdx) = currentFlip;
                missedDeadlines(blockFrameIdx) = missedDeadline;

                if itex == 1
                    sweepFirstFlips(sweepIdx) = currentFlip;

                    if isnan(firstFlip)
                        firstFlip = currentFlip;
                    end
                end

                sweepLastFlips(sweepIdx) = currentFlip;
                lastFlip = currentFlip;
            end

            if quitRequested
                break;
            end
        end

        if quitRequested
            if isfield(thisstim,'tex') && ~isempty(thisstim.tex)
                Screen('Close',thisstim.tex(:));
            end
            return;
        end

        Screen('DrawTexture',wininfoLocal.w,wininfoLocal.BG);
        Screen('Flip',wininfoLocal.w, ...
            lastFlip + 0.5*wininfoLocal.ifi);
        Screen('Close',thisstim.tex(:));
    end

    function realtime_tiff_callback(callbackVid,~)
        if callbackIsWriting || isempty(activeTiff)
            return;
        end

        callbackIsWriting = true;

        try
            drain_camera_buffer_to_tiff(callbackVid);
        catch callbackME
            activeCallbackError = callbackME;

            if activeSessionType == "green" && ...
                    activeGreenSessionIndex >= 1 && ...
                    activeGreenSessionIndex <= ...
                    numel(result.green.sessions) && ...
                    activeTrialIndex >= 1 && ...
                    activeTrialIndex <= numel(greenBlockNames)
                result.green.sessions( ...
                    activeGreenSessionIndex).camera.callbackError( ...
                    activeTrialIndex) = string(callbackME.message);
            elseif activeSessionType == "red" && ...
                    activeTrialIndex >= 1 && activeTrialIndex <= nTrials
                result.camera.callbackError(activeTrialIndex) = ...
                    string(callbackME.message);
            end

            try
                if isrunning(callbackVid)
                    stop(callbackVid);
                end
            catch
            end
        end

        callbackIsWriting = false;
    end

    function drain_camera_buffer_to_tiff(cameraObject)
        if isempty(activeTiff)
            return;
        end

        while cameraObject.FramesAvailable > 0
            nAvailable = cameraObject.FramesAvailable;
            [frameBatch,frameTimes,frameMetadata] = ...
                getdata(cameraObject,nAvailable);

            append_frame_batch_to_tiff( ...
                frameBatch,cameraObject.NumberOfBands, ...
                frameTimes,frameMetadata);
        end
    end

    function append_frame_batch_to_tiff( ...
            frameBatch,nBands,frameTimes,frameMetadata)
        nFramesInBatch = ...
            get_batch_frame_count(frameBatch,nBands);

        if numel(frameTimes) ~= nFramesInBatch || ...
                numel(frameMetadata) ~= nFramesInBatch
            error(['Camera frame, timestamp, and metadata counts do ' ...
                'not match within an acquisition batch.']);
        end

        frameTimes = frameTimes(:);
        frameMetadata = frameMetadata(:);

        for frameIdx = 1:nFramesInBatch
            oneFrame = get_frame_from_batch( ...
                frameBatch,frameIdx,nFramesInBatch,nBands);

            if activeTiffFrameCount > 0
                writeDirectory(activeTiff);
            end

            setTag(activeTiff,make_tiff_tags(oneFrame));
            write(activeTiff,oneFrame);

            activeTiffFrameCount = ...
                activeTiffFrameCount + 1;

            metadataItem = frameMetadata(frameIdx);
            activeCameraFrameTime(end+1,1) = ...
                frameTimes(frameIdx);

            if isfield(metadataItem,'FrameNumber')
                activeCameraFrameNumber(end+1,1) = ...
                    double(metadataItem.FrameNumber);
            else
                activeCameraFrameNumber(end+1,1) = NaN;
            end

            if isfield(metadataItem,'AbsTime') && ...
                    numel(metadataItem.AbsTime) == 6
                activeCameraFrameAbsTime(end+1,:) = ...
                    double(metadataItem.AbsTime(:)');
            else
                activeCameraFrameAbsTime(end+1,:) = nan(1,6);
            end

            if isempty(activeCameraFrameMetadata)
                activeCameraFrameMetadata = metadataItem;
            else
                activeCameraFrameMetadata(end+1,1) = metadataItem;
            end

            activeCameraChunkTimestamp{end+1,1} = ...
                extract_chunk_timestamp(metadataItem);
        end
    end

    function store_camera_frame_timestamps(trialIndex)
        if activeSessionType == "green"
            if activeGreenSessionIndex < 1 || ...
                    activeGreenSessionIndex > ...
                    numel(result.green.sessions) || ...
                    trialIndex < 1 || ...
                    trialIndex > numel(greenBlockNames)
                return;
            end

            result.green.sessions( ...
                activeGreenSessionIndex).camera.frameTime_sec{ ...
                trialIndex} = activeCameraFrameTime;
            result.green.sessions( ...
                activeGreenSessionIndex).camera.frameNumber{ ...
                trialIndex} = activeCameraFrameNumber;
            result.green.sessions( ...
                activeGreenSessionIndex).camera.frameAbsTime{ ...
                trialIndex} = activeCameraFrameAbsTime;
            result.green.sessions( ...
                activeGreenSessionIndex).camera.frameMetadata{ ...
                trialIndex} = activeCameraFrameMetadata;
            result.green.sessions( ...
                activeGreenSessionIndex).camera.chunkTimestamp{ ...
                trialIndex} = activeCameraChunkTimestamp;
            result.green.sessions( ...
                activeGreenSessionIndex).camera.frameTimestampCount( ...
                trialIndex) = numel(activeCameraFrameTime);

            if numel(activeCameraFrameTime) >= 2
                result.green.sessions( ...
                    activeGreenSessionIndex).camera.timestampDerivedFPS( ...
                    trialIndex) = ...
                    1/median(diff(activeCameraFrameTime));
            end
        else
            if trialIndex < 1 || trialIndex > nTrials
                return;
            end

            result.camera.frameTime_sec{trialIndex} = ...
                activeCameraFrameTime;
            result.camera.frameNumber{trialIndex} = ...
                activeCameraFrameNumber;
            result.camera.frameAbsTime{trialIndex} = ...
                activeCameraFrameAbsTime;
            result.camera.frameMetadata{trialIndex} = ...
                activeCameraFrameMetadata;
            result.camera.chunkTimestamp{trialIndex} = ...
                activeCameraChunkTimestamp;
            result.camera.frameTimestampCount(trialIndex) = ...
                numel(activeCameraFrameTime);

            if numel(activeCameraFrameTime) >= 2
                result.camera.timestampDerivedFPS(trialIndex) = ...
                    1/median(diff(activeCameraFrameTime));
            end
        end
    end

    function chunkTimestamp = extract_chunk_timestamp(metadataItem)
        % ChunkData contents and timestamp field names are adaptor/device
        % specific. Preserve the raw metadata separately and extract the
        % first scalar field containing "timestamp" without converting its
        % numeric class (often uint64 camera clock ticks).
        chunkTimestamp = [];

        if ~isfield(metadataItem,'ChunkData') || ...
                isempty(metadataItem.ChunkData) || ...
                ~isstruct(metadataItem.ChunkData)
            return;
        end

        chunkData = metadataItem.ChunkData;
        chunkFields = fieldnames(chunkData);
        timestampField = find(contains( ...
            lower(string(chunkFields)),'timestamp'),1);

        if isempty(timestampField)
            return;
        end

        timestampValue = chunkData.(chunkFields{timestampField});

        if isnumeric(timestampValue) && isscalar(timestampValue)
            chunkTimestamp = timestampValue;
        end
    end

    function capture_clock_anchor(anchorLabel,blockIndex)
        % Bracket the wall-clock query with the monotonic PTB clock. The
        % midpoint is the best estimate of the GetSecs value corresponding
        % to the wall timestamp; half the bracket width is its uncertainty.
        ptbBefore = GetSecs;
        wallTime = datetime('now','TimeZone','UTC');
        ptbAfter = GetSecs;

        anchorIndex = numel(result.clock.ptbGetSecs_sec) + 1;
        result.clock.anchorLabel(anchorIndex,1) = ...
            string(anchorLabel);
        result.clock.anchorBlock(anchorIndex,1) = blockIndex;
        result.clock.pcWallTime(anchorIndex,1) = string(wallTime);
        result.clock.pcWallPosix_sec(anchorIndex,1) = ...
            posixtime(wallTime);
        result.clock.ptbGetSecs_sec(anchorIndex,1) = ...
            (ptbBefore+ptbAfter)/2;
        result.clock.anchorUncertainty_sec(anchorIndex,1) = ...
            (ptbAfter-ptbBefore)/2;
    end

    function nFramesInBatch = ...
            get_batch_frame_count(frameBatch,nBands)

        if nBands == 1
            if ismatrix(frameBatch)
                nFramesInBatch = 1;
            elseif ndims(frameBatch) == 3
                nFramesInBatch = size(frameBatch,3);
            else
                nFramesInBatch = size(frameBatch,4);
            end
        else
            if ndims(frameBatch) == 3
                nFramesInBatch = 1;
            else
                nFramesInBatch = size(frameBatch,4);
            end
        end
    end

    function oneFrame = get_frame_from_batch( ...
            frameBatch,frameIdx,nFramesInBatch,nBands)

        if nBands == 1
            if ismatrix(frameBatch)
                oneFrame = frameBatch;
            elseif ndims(frameBatch) == 3
                oneFrame = frameBatch(:,:,frameIdx);
            else
                oneFrame = frameBatch(:,:,1,frameIdx);
            end
        else
            if nFramesInBatch == 1 && ndims(frameBatch) == 3
                oneFrame = frameBatch;
            else
                oneFrame = frameBatch(:,:,:,frameIdx);
            end
        end
    end

    function tagStruct = make_tiff_tags(oneFrame)
        if ndims(oneFrame) == 2
            nSamples = 1;
        else
            nSamples = size(oneFrame,3);
        end

        switch class(oneFrame)
            case 'uint8'
                bitsPerSample = 8;
                sampleFormat = Tiff.SampleFormat.UInt;
            case 'uint16'
                bitsPerSample = 16;
                sampleFormat = Tiff.SampleFormat.UInt;
            case 'int8'
                bitsPerSample = 8;
                sampleFormat = Tiff.SampleFormat.Int;
            case 'int16'
                bitsPerSample = 16;
                sampleFormat = Tiff.SampleFormat.Int;
            otherwise
                error('Unsupported TIFF frame class: %s', ...
                    class(oneFrame));
        end

        if nSamples == 1
            photometric = Tiff.Photometric.MinIsBlack;
        elseif nSamples == 3
            photometric = Tiff.Photometric.RGB;
        else
            error('Unsupported channel count: %d',nSamples);
        end

        tagStruct.ImageLength = size(oneFrame,1);
        tagStruct.ImageWidth = size(oneFrame,2);
        tagStruct.Photometric = photometric;
        tagStruct.BitsPerSample = bitsPerSample;
        tagStruct.SamplesPerPixel = nSamples;
        tagStruct.SampleFormat = sampleFormat;
        tagStruct.Compression = Tiff.Compression.None;
        tagStruct.PlanarConfiguration = ...
            Tiff.PlanarConfiguration.Chunky;
        tagStruct.RowsPerStrip = min(64,size(oneFrame,1));
        tagStruct.Orientation = Tiff.Orientation.TopLeft;
        tagStruct.Software = ...
            'MATLAB run_cmnoise_green_red';
    end

    function [firstFlip,lastFlip] = ...
            display_grating(wininfoLocal,thisstim)

        firstFlip = NaN;
        lastFlip = NaN;

        for sweepIdx = 1:result.sweeps_per_block
            sweepFirstFlip = NaN;
            sweepLastFlip = NaN;

            for itex = 1:thisstim.movieDurationFrames
                if check_for_quit()
                    break;
                end

                Screen('DrawTexture',wininfoLocal.w, ...
                    thisstim.tex(itex), ...
                    [], ...
                    thisstim.stimulus.destinationRect_pix);

                blockFrameIdx = ...
                    (sweepIdx-1)*thisstim.movieDurationFrames + itex;

                if isnan(lastFlip)
                    % The first frame has no preceding stimulus VBL from
                    % which to define a requested deadline. Its immediate
                    % Flip "missed" output is therefore not a dropped-frame
                    % measurement.
                    [currentFlip,~,~,~] = ...
                        Screen('Flip',wininfoLocal.w);
                    missedDeadline = NaN;
                else
                    % Request the next VBL explicitly. The returned missed
                    % value is now a meaningful deadline diagnostic.
                    nextFlipDeadline = ...
                        lastFlip + 0.5*wininfoLocal.ifi;
                    [currentFlip,~,~,missedDeadline] = ...
                        Screen('Flip',wininfoLocal.w, ...
                        nextFlipDeadline);
                end
                result.displayTiming.ptbFlipTime_sec( ...
                    result.tr_num,blockFrameIdx) = currentFlip - t0;
                result.displayTiming.ptbMissedDeadline_sec( ...
                    result.tr_num,blockFrameIdx) = missedDeadline;

                if itex == 1
                    sweepFirstFlip = currentFlip;

                    if isnan(firstFlip)
                        firstFlip = currentFlip;
                    end
                end

                sweepLastFlip = currentFlip;
                lastFlip = currentFlip;
            end

            if ~isnan(sweepFirstFlip)
                result.block.sweepFirstFlip_sec( ...
                    result.tr_num,sweepIdx) = sweepFirstFlip - t0;
            end

            if ~isnan(sweepLastFlip)
                result.block.sweepLastFlip_sec( ...
                    result.tr_num,sweepIdx) = sweepLastFlip - t0;
            end

            if quitRequested
                break;
            end
        end

        if quitRequested
            if isfield(thisstim,'tex') && ~isempty(thisstim.tex)
                Screen('Close',thisstim.tex(:));
            end
            return;
        end

        Screen('DrawTexture',wininfoLocal.w,wininfoLocal.BG);
        Screen('Flip',wininfoLocal.w, ...
            lastFlip + 0.5*wininfoLocal.ifi);

        Screen('Close',thisstim.tex(:));
    end

    function choice = wait_for_choice(validKeyNames,processGuiEvents)
        choice = '';

        while isempty(choice)
            keyCode = wait_for_new_key(processGuiEvents);

            for keyIdx = 1:numel(validKeyNames)
                keyName = validKeyNames{keyIdx};

                if keyCode(KbName(keyName))
                    choice = keyName;
                    return;
                end
            end
        end
    end

    function keyCode = wait_for_new_key(processGuiEvents)
        [~,~,ignoredKeys] = KbCheck;
        keyCode = false(size(ignoredKeys));

        while true
            if processGuiEvents
                drawnow;
            end

            [keyIsDown,~,currentKeys] = KbCheck;
            newlyPressedKeys = currentKeys & ~ignoredKeys;

            if keyIsDown && any(newlyPressedKeys)
                keyCode = newlyPressedKeys;
                return;
            end

            % A key that was held when this function started becomes
            % detectable again after it has first been released.
            ignoredKeys = ignoredKeys & currentKeys;
            pause(0.01);
        end
    end

    function userQuit = check_for_quit()
        userQuit = quitRequested;

        if userQuit
            return;
        end

        [keyIsDown,~,keyCode] = KbCheck;

        if keyIsDown && ...
                (keyCode(KbName('q')) || keyCode(KbName('Q')))
            quitRequested = true;
            userQuit = true;

            try
                if ~isempty(vid) && isrunning(vid)
                    stop(vid);
                end
            catch
            end
        end
    end

    function cleanup_resources()
        try
            Priority(0);
        catch
        end

        try
            ShowCursor;
        catch
        end

        try
            Screen('CloseAll');
        catch
            try
                sca;
            catch
            end
        end

        try
            ListenChar(0);
        catch
        end

        if ~isempty(vid)
            try
                if isrunning(vid)
                    stop(vid);
                end
            catch
            end

            try
                if ~isempty(activeTiff)
                    drain_camera_buffer_to_tiff(vid);
                end
            catch
            end

            if activeTrialIndex >= 1
                store_camera_frame_timestamps(activeTrialIndex);
            end

            if cameraPreviewStarted
                try
                    closepreview(vid);
                catch
                end
            end
        end

        if ~isempty(activeTiff)
            try
                close(activeTiff);
            catch
            end
            activeTiff = [];
        end

        if ~isempty(vid)
            try
                delete(vid);
            catch
            end
            vid = [];
        end

        if result.do_msock
            try
                msclose(sock);
            catch
            end
        end

        try
            assignin('base','noiseResult',result);

            if ~isempty(wininfo)
                assignin('base','wininfo',wininfo);
            end
        catch
        end
    end

    function result = get_movie_stim(result)
%         tic
        result.contrast = result.contrast_list(randperm(numel(result.contrast_list),1));
        result.contrast_idx = find(result.contrast_list == result.contrast,1);
       % disp(['contrast requested: ', num2str(result.contrast)])
        moviePeriod_sec = result.contrast_period;

        if isfield(result,'current_period_sec') && ...
                isfinite(result.current_period_sec) && ...
                result.current_period_sec > 0
            moviePeriod_sec = result.current_period_sec;
        end

        result.moviedata{result.tr_num} = generateNoise_xyt_uday( ...
            result.sFreqs,result.tFreqs,moviePeriod_sec, ...
            wininfo,result,result.movtype);
        result.movieDurationFrames = size( ...
            result.moviedata{result.tr_num},3);
        result.blockDurationFrames = ...
            result.movieDurationFrames * result.sweeps_per_block;
%        toc
       result.contrasts_by_trial(result.tr_num) = result.contrast;
        
                   % result.contrast_used(end+1) = result.contrast;

        
        for f = 1:size(result.moviedata{result.tr_num},3)
            result.tex(f) = Screen('MakeTexture',wininfo.w, result.moviedata{result.tr_num}(:,:,f));
        end
    end


end
