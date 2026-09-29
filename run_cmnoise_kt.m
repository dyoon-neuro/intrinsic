function result = run_cmnoise_kt(varargin)
p = inputParser;
p.addParameter('rig',0);
p.addParameter('skipsynctests',1);
p.addParameter('animalid','fake');
p.addParameter('depth','000');
p.addParameter('repetitions',2);
p.addParameter('stimduration',16);
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
p.addParameter('oscbarwidth',10);
p.addParameter('contrast_period',9);
p.addParameter('rcontrast_window',120);
p.addParameter('stimFolderRemote', ...
    'Z:\YeerimKim\mesorig\VisStimData\');

%% -------------------- Camera parameters --------------------
p.addParameter('camera_device_id',1);
p.addParameter('camera_fps',10);
p.addParameter('camera_exposure_us',50000);
p.addParameter('camera_gain',18);
p.addParameter('camera_black_level',0);
p.addParameter('camera_preview',1);
p.addParameter('camera_preview_during_experiment',0);
p.addParameter('camera_save_folder','Chameleon3_TIFF_Trials');
p.addParameter('camera_tiff_chunk_frames',30);
p.addParameter('camera_final_drain_timeout_sec',120);

p.parse(varargin{:});
result = p.Results;

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
result.camera.preITI_sec = nan(nTrials,1);
result.camera.stimulus_sec = nan(nTrials,1);
result.camera.postITI_sec = nan(nTrials,1);
result.camera.tifFile = strings(nTrials,1);
result.camera.callbackError = strings(nTrials,1);

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

    % Do not use KbStrokeWait here. It can block MATLAB's event loop and
    % prevent the preview window from refreshing. Keep processing GUI
    % events while polling the keyboard instead.
    KbReleaseWait;
    previewKeyPressed = false;

    while ~previewKeyPressed
        drawnow;
        pause(0.01);

        [keyIsDown,~,keyCode] = KbCheck;

        if keyIsDown
            previewKeyPressed = true;

            if keyCode(KbName('q')) || keyCode(KbName('Q'))
                quitRequested = true;
            end
        end
    end

    KbReleaseWait;

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
    round(result.stimduration * wininfo.frameRate);

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
KbReleaseWait;
[~,startKeyCode] = KbStrokeWait;

if startKeyCode(KbName('q')) || startKeyCode(KbName('Q'))
    quitRequested = true;
    cleanup_resources();
    return;
end
KbReleaseWait;

topPriorityLevel = MaxPriority(wininfo.w);
Priority(topPriorityLevel);

Screen('DrawTexture',wininfo.w,wininfo.BG);
Screen('Flip',wininfo.w);

% Preserve the original randomized dirflag generation.
if result.movtype == 3.5
    dirflags = ones(result.repetitions,1);
    dirflags(1:floor(result.repetitions/2)) = 0;
    dirflags = dirflags(randperm(result.repetitions));
end

result.starttime = datestr(now);
t0 = GetSecs;
result.tr_num = 0;

%% -------------------- Non-triggered stimulus and camera loop --------------------
try
    for istimNT = 1:result.repetitions
        if check_for_quit()
            break;
        end

        result.tr_num = result.tr_num + 1;
        activeTrialIndex = result.tr_num;
        activeCallbackError = [];

        % Preserve the original movie-generation condition and dirflag use.
        if result.random_mov || result.tr_num > 1
            if result.movtype == 3.5
                result.dirflag = dirflags(istimNT);
            end
            result = get_movie_stim(result);
        end

        tifFile = fullfile(result.camera_save_folder, ...
            sprintf('trial%04d.tif',result.tr_num-1));

        if exist(tifFile,'file')
            delete(tifFile);
        end

        activeTiffFrameCount = 0;
        activeTiff = Tiff(tifFile,'w8');
        result.camera.tifFile(result.tr_num) = string(tifFile);

        flushdata(vid);

        fprintf('\nTrial %04d camera start: %s\n', ...
            result.tr_num-1,tifFile);

        start(vid);
        cameraStart = GetSecs;

        % Complete pre-ITI is recorded.
        WaitSecs(result.isipre);
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

            if ~isempty(activeTiff)
                close(activeTiff);
                activeTiff = [];
            end

            break;
        end

        result.timestamp(result.tr_num) = firstStimFlip - t0;
        result.camera.stimulus_sec(result.tr_num) = ...
            lastStimFlip - firstStimFlip;

        % Complete post-ITI is recorded.
        postStart = GetSecs;
        WaitSecs(result.isipost);
        postEnd = GetSecs;
        result.camera.postITI_sec(result.tr_num) = ...
            postEnd - postStart;

        if isrunning(vid)
            stop(vid);
        end

        cameraStop = GetSecs;
        result.camera.actualRecordTime_sec(result.tr_num) = ...
            cameraStop - cameraStart;
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

        if result.camera.actualRecordTime_sec(result.tr_num) > 0
            result.camera.actualFPS(result.tr_num) = ...
                result.camera.actualFrameCount(result.tr_num) / ...
                result.camera.actualRecordTime_sec(result.tr_num);
        end

        close(activeTiff);
        activeTiff = [];

        fprintf('Recorded %.3f sec, camera frames=%d, TIFF frames=%d\n', ...
            result.camera.actualRecordTime_sec(result.tr_num), ...
            result.camera.actualFrameCount(result.tr_num), ...
            result.camera.tiffFrameCount(result.tr_num));

        if result.camera.actualFrameCount(result.tr_num) ~= ...
                result.camera.tiffFrameCount(result.tr_num)
            warning('Camera and TIFF frame counts do not match.');
        end

        save(fnameLocal,'result','-v7.3');

        if result.save_remote
            save(fnameRemote,'result','-v7.3');
        end
    end

    if quitRequested
        fprintf('Experiment stopped by user.\n');
        cleanup_resources();
        return;
    end

    %% -------------------- Summary CSV --------------------
    Priority(0);

    summaryFile = fullfile(result.camera_save_folder, ...
        sprintf('%s_frame_count_summary.csv',sessionName));

    Trial = (0:nTrials-1)';
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

    T = table(Trial,PlannedRecordTime_sec,TargetFrameCount, ...
        ActualRecordTime_sec,ActualFrameCount,TIFFFrameCount, ...
        ActualFPS,PreITI_sec,Stimulus_sec,PostITI_sec, ...
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
        save(fnameLocal,'result','-v7.3');
    catch
    end

    cleanup_resources();
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
            frameBatch = getdata(cameraObject,nAvailable);

            append_frame_batch_to_tiff( ...
                frameBatch,cameraObject.NumberOfBands);
        end
    end

    function append_frame_batch_to_tiff(frameBatch,nBands)
        nFramesInBatch = ...
            get_batch_frame_count(frameBatch,nBands);

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
        end
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
            'MATLAB run_cmnoise_uday_notrigger_hs';
    end

    function [firstFlip,lastFlip] = ...
            display_grating(wininfoLocal,thisstim)

        firstFlip = NaN;
        lastFlip = NaN;

        if ~result.interleave || rem(result.tr_num,2) == 0
            for itex = 1:thisstim.movieDurationFrames
                if check_for_quit()
                    break;
                end

                Screen('DrawTexture',wininfoLocal.w, ...
                    thisstim.tex(itex), ...
                    [0 0 128 128], ...
                    [0 0 wininfoLocal.xRes wininfoLocal.xRes]);

                currentFlip = Screen('Flip',wininfoLocal.w);

                if itex == 1
                    firstFlip = currentFlip;
                end
                lastFlip = currentFlip;
            end
        else
            for itex = 1:thisstim.movieDurationFrames
                if check_for_quit()
                    break;
                end

                Screen('DrawTexture',wininfoLocal.w, ...
                    wininfoLocal.BG);

                currentFlip = Screen('Flip',wininfoLocal.w);

                if itex == 1
                    firstFlip = currentFlip;
                end
                lastFlip = currentFlip;
            end
        end

        if quitRequested
            if isfield(thisstim,'tex') && ~isempty(thisstim.tex)
                Screen('Close',thisstim.tex(:));
            end
            return;
        end

        Screen('DrawTexture',wininfoLocal.w,wininfoLocal.BG);
        Screen('Flip',wininfoLocal.w);

        Screen('Close',thisstim.tex(:));
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
        result.moviedata{result.tr_num} = generateNoise_xyt_uday(result.sFreqs, result.tFreqs, result.stimduration, wininfo, result, result.movtype);
%        toc
       result.contrasts_by_trial(result.tr_num) = result.contrast;
        
                   % result.contrast_used(end+1) = result.contrast;

        
        for f = 1:size(result.moviedata{result.tr_num},3)
            result.tex(f) = Screen('MakeTexture',wininfo.w, result.moviedata{result.tr_num}(:,:,f));
        end
    end


end
