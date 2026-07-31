function result = run_cmnoise_no_frame2ttl_bpod(varargin)

%RUN_CMNOISE_NO_FRAME2TTL_BPOD Run the stimulus and camera standalone.
%   This version does not draw a Frame2TTL patch and does not initialize,
%   control, or read a Bpod state machine. Camera acquisition is started
%   directly from MATLAB and display timing is measured with Psychtoolbox.

p = inputParser;
p.addParameter('rig',0);
p.addParameter('skipsynctests',1);
p.addParameter('animalid','fake');
p.addParameter('depth','000');
p.addParameter('repetitions',4);
p.addParameter('stimduration',180);
p.addParameter('isipre',3);
p.addParameter('isipost',3);
p.addParameter('DScreen',8);
p.addParameter('VertScreenSize',15);
p.addParameter('HorzScreenSize',20);
p.addParameter('fullscreen',1);
p.addParameter('sFreqs',0.04);
p.addParameter('tFreqs',1);
p.addParameter('contrast_list',[1]);
p.addParameter('position',[0,0]);
p.addParameter('save_remote',0);
p.addParameter('interleave',0);
p.addParameter('random_mov',1);
p.addParameter('movtype',3.5);
p.addParameter('aperture_width_deg',20);
p.addParameter('contrast_period',18);
p.addParameter('sweeps_per_block',10);
p.addParameter('rcontrast_window',120);
p.addParameter('stimFolderRemote', ...
    'Z:\YeerimKim\mesorig\VisStimData\');

%% -------------------- Camera parameters --------------------
p.addParameter('camera_device_id',1);
p.addParameter('camera_fps',10);
p.addParameter('camera_exposure_us',30000);
p.addParameter('camera_gain',18);
p.addParameter('camera_black_level',0);
p.addParameter('camera_preview',1);
p.addParameter('camera_preview_during_experiment',0);
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
blockNames = [ ...
    "nasal_to_temporal"; ...
    "temporal_to_nasal"; ...
    "inferior_to_superior"; ...
    "superior_to_inferior"];
blockAxis = [0; 0; 1; 1];       % 0: horizontal, 1: vertical
blockReverse = [0; 1; 1; 0];    % Reverse increasing screen coordinates

result.repetitions = numel(blockNames);
result.stimduration = ...
    result.contrast_period * result.sweeps_per_block;
result.interleave = 0;
result.block.names = blockNames;
result.block.axis = blockAxis;
result.block.reverse = logical(blockReverse);

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
validateattributes(result.aperture_width_deg,{'numeric'}, ...
    {'scalar','positive'});
validateattributes(result.contrast_period,{'numeric'}, ...
    {'scalar','positive'});
validateattributes(result.sweeps_per_block,{'numeric'}, ...
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

if ~exist(result.camera_save_folder,'dir')
    mkdir(result.camera_save_folder);
end

% Create a unique date-based folder for this experiment.
% Examples:
%   Chameleon3_TIFF_Trials\20260720
%   Chameleon3_TIFF_Trials\20260720_1
%   Chameleon3_TIFF_Trials\20260720_2
dateBaseName = datestr(now,'yyyymmdd');
sessionName = dateBaseName;
sessionIndex = 0;

while exist(fullfile(result.camera_save_folder,sessionName),'dir')
    sessionIndex = sessionIndex + 1;
    sessionName = sprintf('%s_%d',dateBaseName,sessionIndex);
end

cameraRootFolder = result.camera_save_folder;
cameraSessionFolder = fullfile(cameraRootFolder,sessionName);
mkdir(cameraSessionFolder);

result.camera_root_folder = cameraRootFolder;
result.camera_session_name = sessionName;
result.camera_save_folder = cameraSessionFolder;

fprintf('Camera files will be saved in: %s\n', ...
    result.camera_save_folder);

if result.do_msock
    sock = msPrep();
end

[result,fnameLocal,fnameRemote] = saveFilePrep(result);

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

vid = videoinput('gentl',result.camera_device_id);
src = getselectedsource(vid);

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
    src.ExposureAuto = 'Off';
    src.ExposureTime = result.camera_exposure_us;
catch ME
    warning('Exposure setting failed: %s',ME.message);
end

try
    src.GainAuto = 'Off';
    src.Gain = result.camera_gain;
catch ME
    warning('Gain setting failed: %s',ME.message);
end

try
    src.BalanceWhiteAuto = 'Off';
catch
end

try
    src.BlackLevel = result.camera_black_level;
catch ME
    warning('Black-level setting failed: %s',ME.message);
end

if result.camera_preview
    fprintf('\nOpening camera preview.\n');

    try
        preview(vid);
        cameraPreviewStarted = true;
    catch ME
        warning('Camera preview failed: %s',ME.message);
        cameraPreviewStarted = false;
    end

    if ~cameraPreviewStarted
        error(['Camera preview could not be started. Check the selected ' ...
            'device ID, adaptor support, and whether another program is ' ...
            'using the camera.']);
    end

    % Allow the preview figure and camera stream to initialize.
    pause(0.5);
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

%% -------------------- Psychtoolbox initialization --------------------
wininfo = gen_wininfo_uday(result);
assignin('base','wininfo',wininfo);

result.image_mag = 10;
result.dispInfo.xRes = wininfo.xRes;
result.dispInfo.yRes = wininfo.yRes;
result.dispInfo.DScreen = result.DScreen;
result.dispInfo.VertScreenSize = result.VertScreenSize;

result.movieDurationFrames = ...
    round(result.contrast_period * wininfo.frameRate);
result.blockDurationFrames = ...
    result.movieDurationFrames * result.sweeps_per_block;

result.displayTiming.ptbFlipTime_sec = ...
    nan(nTrials,result.blockDurationFrames);
result.displayTiming.ptbMissedDeadline_sec = ...
    nan(nTrials,result.blockDurationFrames);

Screen('FillRect',wininfo.w,[128,128,128]);
Screen('TextFont',wininfo.w,'Courier New');
Screen('TextSize',wininfo.w,14);
Screen('TextStyle',wininfo.w,1+2);

Screen('DrawText',wininfo.w,strcat( ...
    num2str(result.repetitions),' Repeats__', ...
    num2str(result.repetitions * ...
    (result.isipre + result.stimduration + result.isipost) / 60), ...
    ' min estimated Duration.'), ...
    60,50,[255 128 0]);

Screen('DrawText',wininfo.w,strcat( ...
    'Filename:',fnameLocal, ...
    '    Hit any key to continue / q to abort.'), ...
    60,70,[255 128 0]);

Screen('Flip',wininfo.w);

FlushEvents;
disp('Hit any key to continue / q to abort.');
startKeyCode = wait_for_new_key(false);

if startKeyCode(KbName('q')) || startKeyCode(KbName('Q'))
    quitRequested = true;
    cleanup_resources();
    return;
end

topPriorityLevel = MaxPriority(wininfo.w);
Priority(topPriorityLevel);

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
        activeTrialIndex = result.tr_num;
        activeCallbackError = [];
        capture_clock_anchor( ...
            sprintf('block_%d_start',result.tr_num), ...
            result.tr_num);

        result.block.currentName = blockNames(istimNT);
        result.dirflag = blockAxis(istimNT);
        result.reverseflag = logical(blockReverse(istimNT));
        result = get_movie_stim(result);

        fprintf('\nBlock %d/%d: %s, %d sweeps x %.3f sec\n', ...
            istimNT,nTrials,char(blockNames(istimNT)), ...
            result.sweeps_per_block,result.contrast_period);

        tifFile = fullfile(result.camera_save_folder, ...
            sprintf('block%02d_%s.tif',result.tr_num, ...
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

    function realtime_tiff_callback(callbackVid,~)
        if callbackIsWriting || isempty(activeTiff)
            return;
        end

        callbackIsWriting = true;

        try
            drain_camera_buffer_to_tiff(callbackVid);
        catch callbackME
            activeCallbackError = callbackME;

            if activeTrialIndex >= 1 && activeTrialIndex <= nTrials
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
            'MATLAB run_cmnoise_no_frame2ttl_bpod';
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
                    [0 0 wininfoLocal.xRes wininfoLocal.xRes]);

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

            if activeTrialIndex >= 1 && activeTrialIndex <= nTrials
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
        result.moviedata{result.tr_num} = generateNoise_xyt_uday( ...
            result.sFreqs,result.tFreqs,result.contrast_period, ...
            wininfo,result,result.movtype);
%        toc
       result.contrasts_by_trial(result.tr_num) = result.contrast;
        
                   % result.contrast_used(end+1) = result.contrast;

        
        for f = 1:size(result.moviedata{result.tr_num},3)
            result.tex(f) = Screen('MakeTexture',wininfo.w, result.moviedata{result.tr_num}(:,:,f));
        end
    end


end
