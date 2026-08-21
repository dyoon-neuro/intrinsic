function analysis = analyze_cmnoise_retinotopy(sessionFolder,varargin)
%ANALYZE_CMNOISE_RETINOTOPY Analyze green or red intrinsic imaging data.
%   ANALYZE_CMNOISE_RETINOTOPY opens a Windows folder-selection dialog and
%   analyzes the selected acquisition session folder.
%
%   ANALYSIS = ANALYZE_CMNOISE_RETINOTOPY(SESSIONFOLDER) interactively
%   selects a green-light or red-light recording from SESSIONFOLDER.
%
%   The pipeline implements the processing described in Nsiangani et al.
%   (Scientific Reports, 2022; doi:10.1038/s41598-022-05932-2):
%     1. Delta absorbance = log10(Ia/I0), where I0 defaults to each
%        block's gray pre-ITI; no separately recorded baseline is required.
%     2. Per-sweep DFT at the aperture sweep frequency using all sweep frames.
%     3. Phase-coherence and response-amplitude quality diagnostics.
%     4. Absolute phase = (forward - reverse)/2.
%     5. VFS = sin(elevation-gradient angle - azimuth-gradient angle).
%
%   Example interactive use:
%       analyze_cmnoise_retinotopy
%       analyze_cmnoise_retinotopy('D:\intrinsic\20260811')
%
%   Example noninteractive use:
%       analyze_cmnoise_retinotopy(folder,'session_type','red')
%       analyze_cmnoise_retinotopy(folder,'session_type','green', ...
%           'green_session_index',1)
%
%   Block-level parallel processing (Parallel Computing Toolbox):
%       analyze_cmnoise_retinotopy(folder,'session_type','red', ...
%           'use_parallel',true,'num_workers',4)

if nargin < 1 || isempty(sessionFolder) || ...
        strlength(string(sessionFolder)) == 0
    selectedFolder = uigetdir(pwd, ...
        'Select the intrinsic-imaging session folder');

    if isequal(selectedFolder,0)
        fprintf('Folder selection canceled. Analysis was not started.\n');
        analysis = [];
        return;
    end

    sessionFolder = selectedFolder;
end

p = inputParser;
p.addRequired('sessionFolder',@(x)ischar(x) || isstring(x));
p.addParameter('session_type','ask', ...
    @(x)ischar(x) || isstring(x));
p.addParameter('green_session_index',[], ...
    @(x)isempty(x) || (isnumeric(x) && isscalar(x) && ...
    isfinite(x) && x >= 1 && mod(x,1) == 0));
p.addParameter('result_file','',@(x)ischar(x) || isstring(x));
p.addParameter('output_folder','',@(x)ischar(x) || isstring(x));
p.addParameter('map_smoothing_sigma',3, ...
    @(x)isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
p.addParameter('vfs_smoothing_sigma',3.5, ...
    @(x)isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
p.addParameter('register_blocks',true, ...
    @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter('registration_sample_frames',40, ...
    @(x)isnumeric(x) && isscalar(x) && isfinite(x) && ...
    x >= 1 && mod(x,1) == 0);
p.addParameter('registration_sample_frames_per_sweep',5, ...
    @(x)isnumeric(x) && isscalar(x) && isfinite(x) && ...
    x >= 1 && mod(x,1) == 0);
p.addParameter('register_sweeps',true, ...
    @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter('temporal_stride',1, ...
    @(x)isnumeric(x) && isscalar(x) && isfinite(x) && ...
    x >= 1 && mod(x,1) == 0);
p.addParameter('minimum_phase_coherence',0.25, ...
    @(x)isnumeric(x) && isscalar(x) && isfinite(x) && ...
    x >= 0 && x <= 1);
p.addParameter('crop_rect',[], ...
    @(x)isempty(x) || (isnumeric(x) && numel(x) == 4 && ...
    all(isfinite(x))));
p.addParameter('spatial_bin',1, ...
    @(x)isnumeric(x) && isscalar(x) && isfinite(x) && ...
    x >= 1 && mod(x,1) == 0);
p.addParameter('azimuth_range_deg',[], ...
    @(x)isempty(x) || (isnumeric(x) && numel(x) == 2 && ...
    all(isfinite(x)) && x(2) > x(1)));
p.addParameter('elevation_range_deg',[], ...
    @(x)isempty(x) || (isnumeric(x) && numel(x) == 2 && ...
    all(isfinite(x)) && x(2) > x(1)));
p.addParameter('azimuth_phase_sign',1, ...
    @(x)isnumeric(x) && isscalar(x) && ismember(x,[-1 1]));
p.addParameter('elevation_phase_sign',1, ...
    @(x)isnumeric(x) && isscalar(x) && ismember(x,[-1 1]));
p.addParameter('overlay_alpha',0.65, ...
    @(x)isnumeric(x) && isscalar(x) && isfinite(x) && ...
    x >= 0 && x <= 1);
p.addParameter('show_figures',false, ...
    @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter('use_parallel',true, ...
    @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter('num_workers',4, ...
    @(x)isempty(x) || (isnumeric(x) && isscalar(x) && ...
    isfinite(x) && x >= 1 && mod(x,1) == 0));
p.addParameter('parallel_block_batch_size',[], ...
    @(x)isempty(x) || (isnumeric(x) && isscalar(x) && ...
    isfinite(x) && x >= 1 && mod(x,1) == 0));
p.parse(sessionFolder,varargin{:});
opts = p.Results;
opts.register_blocks = logical(opts.register_blocks);
opts.register_sweeps = logical(opts.register_sweeps);
opts.show_figures = logical(opts.show_figures);
opts.use_parallel = logical(opts.use_parallel);

sessionFolder = char(string(sessionFolder));

if ~isfolder(sessionFolder)
    error('Session folder does not exist: %s',sessionFolder);
end

resultFile = resolve_result_file(sessionFolder,opts.result_file);
loaded = load(resultFile,'result');

if ~isfield(loaded,'result')
    error('The selected MAT file does not contain a result variable.');
end

acquisitionResult = loaded.result;
sessionType = select_session_type(opts.session_type);
[cfg,opts] = build_analysis_config( ...
    acquisitionResult,sessionFolder,resultFile,sessionType,opts);
opts = configure_parallel_processing(opts);

if strlength(string(opts.output_folder)) == 0
    if strcmp(cfg.sessionType,'green')
        outputFolder = fullfile(sessionFolder,sprintf( ...
            'analysis_green_session%02d',cfg.greenSessionIndex));
    else
        outputFolder = fullfile(sessionFolder,'analysis_red');
    end
else
    outputFolder = char(string(opts.output_folder));
end

if ~isfolder(outputFolder)
    mkdir(outputFolder);
end

fprintf('\nAnalyzing %s-light imaging from: %s\n', ...
    upper(cfg.sessionType),sessionFolder);
fprintf('Output folder: %s\n',outputFolder);
if opts.parallel_enabled
    fprintf(['BigTIFF processing: block-level parallel, %d workers, ' ...
        'batch size %d.\n'],opts.parallel_workers_actual, ...
        resolve_parallel_batch_size(opts,cfg.nBlocks));
else
    fprintf('BigTIFF processing: sequential blocks.\n');
end
fprintf(['Baseline correction: log10(Ia/I0), block pre-ITI; ' ...
    'full-sweep DFT at stimulus frequency.\n']);

[baselineMeans,referenceFirstFrame,referenceMean,baselineInfo] = ...
    prepare_baselines(cfg,opts);
mapSize = size(baselineMeans{1});

repetitionAggregates = repmat( ...
    new_direction_aggregate(mapSize),cfg.nRepetitions,1);
qcTables = cell(cfg.nBlocks,1);
analysisBlocks = repmat(struct( ...
    'name',"",'repetition',NaN,'directionIndex',NaN, ...
    'tifFile',"",'registrationShiftXY_pix',[0 0], ...
    'sweepRegistrationShiftXY_pix',[], ...
    'timingSource',"",'baselineSource',"", ...
    'baselineFrameCount',0, ...
    'responseAmplitudeMedian',[],'responseAmplitude95',[], ...
    'retainedSweeps',[],'framesPerSweep',[], ...
    'retainedSweepCount',0),cfg.nBlocks,1);

blockConfigs = cell(cfg.nBlocks,1);
blockBaselines = cell(cfg.nBlocks,1);

for blockIndex = 1:cfg.nBlocks
    blockConfigs{blockIndex} = make_direction_block_config(cfg,blockIndex);
    blockBaselines{blockIndex} = ...
        baselineMeans{cfg.blockRepetition(blockIndex)};
end

batchSize = resolve_parallel_batch_size(opts,cfg.nBlocks);

for batchStart = 1:batchSize:cfg.nBlocks
    batchEnd = min(cfg.nBlocks,batchStart+batchSize-1);
    batchBlockIndices = batchStart:batchEnd;
    batchConfigs = blockConfigs(batchBlockIndices);
    batchBaselines = blockBaselines(batchBlockIndices);
    batchResults = cell(numel(batchBlockIndices),1);

    if opts.parallel_enabled && numel(batchBlockIndices) > 1
        parfor batchIndex = 1:numel(batchBlockIndices)
            batchResults{batchIndex} = analyze_direction_block( ...
                batchConfigs{batchIndex},batchBaselines{batchIndex}, ...
                referenceMean,opts);
        end
    else
        for batchIndex = 1:numel(batchBlockIndices)
            batchResults{batchIndex} = analyze_direction_block( ...
                batchConfigs{batchIndex},batchBaselines{batchIndex}, ...
                referenceMean,opts);
        end
    end

    for batchIndex = 1:numel(batchBlockIndices)
        blockIndex = batchBlockIndices(batchIndex);
        blockResult = batchResults{batchIndex};
        repetitionIndex = cfg.blockRepetition(blockIndex);
        directionIndex = direction_name_to_index( ...
            cfg.blockNames(blockIndex));
        print_block_progress( ...
            cfg,blockIndex,repetitionIndex,blockResult);

        repetitionAggregates(repetitionIndex) = ...
            add_block_to_aggregate( ...
            repetitionAggregates(repetitionIndex),blockResult, ...
            directionIndex);

        analysisBlocks(blockIndex).name = cfg.blockNames(blockIndex);
        analysisBlocks(blockIndex).repetition = repetitionIndex;
        analysisBlocks(blockIndex).directionIndex = directionIndex;
        analysisBlocks(blockIndex).tifFile = ...
            string(cfg.blockFiles{blockIndex});
        analysisBlocks(blockIndex).registrationShiftXY_pix = ...
            blockResult.registrationShiftXY_pix;
        analysisBlocks(blockIndex).sweepRegistrationShiftXY_pix = ...
            blockResult.sweepRegistrationShiftXY_pix;
        analysisBlocks(blockIndex).timingSource = ...
            string(blockResult.timingSource);
        analysisBlocks(blockIndex).baselineSource = ...
            string(blockResult.baselineSource);
        analysisBlocks(blockIndex).baselineFrameCount = ...
            blockResult.baselineFrameCount;
        analysisBlocks(blockIndex).responseAmplitudeMedian = ...
            blockResult.responseAmplitudeMedian;
        analysisBlocks(blockIndex).responseAmplitude95 = ...
            blockResult.responseAmplitude95;
        analysisBlocks(blockIndex).retainedSweeps = ...
            blockResult.retainedSweeps;
        analysisBlocks(blockIndex).framesPerSweep = ...
            blockResult.framesPerSweep;
        analysisBlocks(blockIndex).retainedSweepCount = ...
            blockResult.retainedSweepCount;

        qcTables{blockIndex} = make_qc_table( ...
            cfg,blockIndex,blockResult);
    end
end

qcTable = vertcat(qcTables{:});
qcFile = fullfile(outputFolder,'sweep_quality_control.csv');
writetable(qcTable,qcFile);

repetitionMaps = cell(cfg.nRepetitions,1);

for repetitionIndex = 1:cfg.nRepetitions
    repetitionMap = make_retinotopy_maps( ...
        repetitionAggregates(repetitionIndex),cfg,opts);
    repetitionMap.repetition = repetitionIndex;
    repetitionMaps{repetitionIndex} = repetitionMap;

    repetitionFile = fullfile(outputFolder,sprintf( ...
        'repetition_%02d_maps.mat',repetitionIndex));
    save(repetitionFile,'repetitionMap','-v7.3');

    plot_maps(repetitionMap,cfg,opts, ...
        fullfile(outputFolder,sprintf( ...
        'repetition_%02d_maps.png',repetitionIndex)), ...
        sprintf('%s repetition %d',upper(cfg.sessionType), ...
        repetitionIndex));
end

repetitionMaps = vertcat(repetitionMaps{:});

% Combine the already quality-controlled coordinate estimates rather than
% summing raw complex responses across repetitions. Repetition-to-
% repetition phase offsets otherwise cancel in the complex sum and make a
% valid field disappear under the phase-coherence threshold. A pixelwise
% median is robust to both phase-wrap branches and an outlying repetition.
overallMaps = make_repetition_consensus_maps( ...
    repetitionMaps,cfg,opts);
quality = summarize_quality(overallMaps,repetitionMaps);
plot_maps(overallMaps,cfg,opts, ...
    fullfile(outputFolder,'overall_maps.png'), ...
    sprintf('%s all repetitions',upper(cfg.sessionType)));

firstBaselineFile = fullfile(outputFolder, ...
    'first_baseline_frame.png');
write_reference_image(referenceFirstFrame,firstBaselineFile);

overlayFile = fullfile(outputFolder, ...
    'overall_vfs_overlay_first_baseline.png');
write_vfs_overlay(referenceFirstFrame,overallMaps.vfs, ...
    overlayFile,opts);

analysis = struct();
analysis.created = string(datetime('now','TimeZone','local'));
analysis.method = [ ...
    "Nsiangani et al., Scientific Reports 2022"; ...
    "Modified Beer-Lambert log10(Ia/I0)"; ...
    "Per-sweep full-duration DFT at stimulus frequency"; ...
    "Phase coherence and response-amplitude QC"; ...
    "Overall map = robust median of repetition coordinate maps"; ...
    "Absolute phase = (forward - reverse)/2"; ...
    "VFS gradient-angle sine"];
analysis.sessionFolder = string(sessionFolder);
analysis.resultFile = string(resultFile);
analysis.outputFolder = string(outputFolder);
analysis.sessionType = string(cfg.sessionType);
analysis.greenSessionIndex = cfg.greenSessionIndex;
analysis.config = cfg;
analysis.options = opts;
analysis.baseline = baselineInfo;
analysis.reference.firstBaselineFrame = referenceFirstFrame;
analysis.reference.firstBaselineFrameFile = string(firstBaselineFile);
analysis.blocks = analysisBlocks;
analysis.repetitions = repetitionMaps;
analysis.overall = overallMaps;
analysis.quality = quality;
analysis.qcTableFile = string(qcFile);
analysis.overlayFile = string(overlayFile);

analysisFile = fullfile(outputFolder,'retinotopy_analysis.mat');
analysis.analysisFile = string(analysisFile);
save(analysisFile,'analysis','-v7.3');

fprintf('\nAnalysis completed.\n');
fprintf('Overall maps: %s\n', ...
    fullfile(outputFolder,'overall_maps.png'));
fprintf('VFS overlay: %s\n',overlayFile);
fprintf('First baseline frame: %s\n',firstBaselineFile);
fprintf('MAT result: %s\n',analysisFile);
fprintf(['Median pair coherence: azimuth %.3f, elevation %.3f; ' ...
    'mean repetition correlation: azimuth %.3f, elevation %.3f.\n'], ...
    quality.medianAzimuthCoherence, ...
    quality.medianElevationCoherence, ...
    quality.meanRepetitionAzimuthCorrelation, ...
    quality.meanRepetitionElevationCorrelation);
end


function opts = configure_parallel_processing(opts)
opts.parallel_enabled = false;
opts.parallel_workers_actual = 0;

if ~opts.use_parallel
    return;
end

hasParallelToolbox = license('test','Distrib_Computing_Toolbox') && ...
    ~isempty(ver('parallel')) && exist('parpool','file') == 2;

if ~hasParallelToolbox
    warning(['Parallel Computing Toolbox is unavailable; BigTIFF blocks ' ...
        'will be processed sequentially.']);
    return;
end

try
    parallelPool = gcp('nocreate');

    if isempty(parallelPool)
        if isempty(opts.num_workers)
            parallelPool = parpool('local');
        else
            parallelPool = parpool('local',opts.num_workers);
        end
    elseif ~isempty(opts.num_workers) && ...
            parallelPool.NumWorkers ~= opts.num_workers
        warning(['An existing parallel pool has %d workers; requested ' ...
            'num_workers=%d is ignored.'],parallelPool.NumWorkers, ...
            opts.num_workers);
    end

    opts.parallel_enabled = true;
    opts.parallel_workers_actual = parallelPool.NumWorkers;
catch ME
    warning('intrinsic:ParallelPoolUnavailable', ...
        ['Could not start or use a parallel pool; BigTIFF blocks ' ...
        'will be processed sequentially: %s'],ME.message);
end
end


function batchSize = resolve_parallel_batch_size(opts,nBlocks)
if ~opts.parallel_enabled
    batchSize = 1;
    return;
end

if isempty(opts.parallel_block_batch_size)
    requestedBatchSize = opts.parallel_workers_actual;
else
    requestedBatchSize = opts.parallel_block_batch_size;
end

batchSize = max(1,min([requestedBatchSize, ...
    opts.parallel_workers_actual,max(1,nBlocks)]));
end


function quality = summarize_quality(overallMaps,repetitionMaps)
quality = struct();
quality.medianAzimuthCoherence = median( ...
    overallMaps.azimuthCoherence(:),'omitnan');
quality.medianElevationCoherence = median( ...
    overallMaps.elevationCoherence(:),'omitnan');
nRepetitions = numel(repetitionMaps);
quality.repetitionAzimuthCorrelation = nan(nRepetitions);
quality.repetitionElevationCorrelation = nan(nRepetitions);

for firstIndex = 1:nRepetitions
    for secondIndex = firstIndex+1:nRepetitions
        firstMap = repetitionMaps(firstIndex).azimuth_deg;
        secondMap = repetitionMaps(secondIndex).azimuth_deg;
        valid = isfinite(firstMap) & isfinite(secondMap);

        if nnz(valid) >= 3
            quality.repetitionAzimuthCorrelation( ...
                firstIndex,secondIndex) = corr( ...
                firstMap(valid),secondMap(valid));
        end

        firstMap = repetitionMaps(firstIndex).elevation_deg;
        secondMap = repetitionMaps(secondIndex).elevation_deg;
        valid = isfinite(firstMap) & isfinite(secondMap);

        if nnz(valid) >= 3
            quality.repetitionElevationCorrelation( ...
                firstIndex,secondIndex) = corr( ...
                firstMap(valid),secondMap(valid));
        end
    end
end

quality.meanRepetitionAzimuthCorrelation = mean( ...
    quality.repetitionAzimuthCorrelation(:),'omitnan');
quality.meanRepetitionElevationCorrelation = mean( ...
    quality.repetitionElevationCorrelation(:),'omitnan');
end


function resultFile = resolve_result_file(sessionFolder,requestedFile)
if strlength(string(requestedFile)) > 0
    resultFile = char(string(requestedFile));

    if ~isfile(resultFile)
        error('Requested result file does not exist: %s',resultFile);
    end

    return;
end

candidates = dir(fullfile(sessionFolder,'*.mat'));
valid = false(numel(candidates),1);

for fileIndex = 1:numel(candidates)
    candidate = fullfile(candidates(fileIndex).folder, ...
        candidates(fileIndex).name);

    try
        variables = whos('-file',candidate);
        valid(fileIndex) = any(strcmp({variables.name},'result'));
    catch
        valid(fileIndex) = false;
    end
end

candidates = candidates(valid);

if isempty(candidates)
    error('No MAT file containing result was found in %s.',sessionFolder);
end

[~,newestIndex] = max([candidates.datenum]);
resultFile = fullfile(candidates(newestIndex).folder, ...
    candidates(newestIndex).name);

if numel(candidates) > 1
    warning('Multiple result MAT files found; using newest: %s', ...
        resultFile);
end
end


function sessionType = select_session_type(requestedType)
sessionType = lower(strtrim(char(string(requestedType))));

if strcmp(sessionType,'ask') || isempty(sessionType)
    while true
        answer = lower(strtrim(input( ...
            'Analyze green or red imaging? [g/r]: ','s')));

        if ismember(answer,{'g','green'})
            sessionType = 'green';
            break;
        elseif ismember(answer,{'r','red'})
            sessionType = 'red';
            break;
        end
    end
end

if ~ismember(sessionType,{'green','red'})
    error('session_type must be ask, green, or red.');
end
end


function [cfg,opts] = build_analysis_config( ...
        result,sessionFolder,resultFile,sessionType,opts)
cfg = struct();
cfg.sessionType = sessionType;
cfg.sessionFolder = string(sessionFolder);
cfg.resultFile = string(resultFile);
cfg.cameraFPS = double(result.camera_fps);
cfg.preITI_sec = double(result.isipre);
cfg.greenSessionIndex = NaN;

if isempty(opts.azimuth_range_deg)
    horizontalDeg = 2*atand((double(result.HorzScreenSize)/2) / ...
        double(result.DScreen));

    if isfield(result,'dispInfo') && ...
            isfield(result.dispInfo,'XDeg') && ...
            isfinite(double(result.dispInfo.XDeg))
        horizontalDeg = double(result.dispInfo.XDeg);
    end

    azimuthCenter = 0;

    if isfield(result,'position') && ~isempty(result.position)
        azimuthCenter = double(result.position(1));
    end

    cfg.azimuthRange_deg = azimuthCenter + ...
        [-horizontalDeg/2 horizontalDeg/2];
else
    cfg.azimuthRange_deg = double(opts.azimuth_range_deg(:)');
end

if isempty(opts.elevation_range_deg)
    verticalDeg = 2*atand((double(result.VertScreenSize)/2) / ...
        double(result.DScreen));

    if isfield(result,'dispInfo') && ...
            isfield(result.dispInfo,'YDeg') && ...
            isfinite(double(result.dispInfo.YDeg))
        verticalDeg = double(result.dispInfo.YDeg);
    end

    elevationCenter = 0;

    if isfield(result,'position') && numel(result.position) >= 2
        elevationCenter = double(result.position(2));
    end

    cfg.elevationRange_deg = elevationCenter + ...
        [-verticalDeg/2 verticalDeg/2];
else
    cfg.elevationRange_deg = double(opts.elevation_range_deg(:)');
end

if strcmp(sessionType,'green')
    if ~isfield(result,'green') || ...
            ~isfield(result.green,'sessions') || ...
            isempty(result.green.sessions)
        error('No green-light session exists in the result file.');
    end

    nGreenSessions = numel(result.green.sessions);
    greenSessionIndex = opts.green_session_index;

    if isempty(greenSessionIndex)
        if nGreenSessions == 1
            greenSessionIndex = 1;
        else
            fprintf('Available green sessions: 1-%d\n',nGreenSessions);
            greenSessionIndex = input('Green session index to analyze: ');
        end
    end

    if greenSessionIndex < 1 || greenSessionIndex > nGreenSessions
        error('green_session_index must be between 1 and %d.', ...
            nGreenSessions);
    end

    greenSession = result.green.sessions(greenSessionIndex);

    cfg.greenSessionIndex = greenSessionIndex;
    cfg.nBlocks = numel(greenSession.block.names);
    cfg.sweepsPerBlock = double(result.green.sweeps_per_block);
    cfg.blockNames = string(greenSession.block.names(:));
    cfg.blockRepetition = nan(cfg.nBlocks,1);

    for blockIndex = 1:cfg.nBlocks
        suffix = regexp(char(cfg.blockNames(blockIndex)), ...
            '_(\d+)$','tokens','once');

        if isempty(suffix)
            % Backward compatibility for older green recordings whose
            % block names did not include a repetition suffix.
            cfg.blockRepetition(blockIndex) = ceil(blockIndex/4);
        else
            cfg.blockRepetition(blockIndex) = str2double(suffix{1});
        end
    end

    cfg.nRepetitions = max(cfg.blockRepetition);

    if isfield(result.green,'repetitions_per_session')
        recordedGreenRepetitions = double( ...
            result.green.repetitions_per_session);

        if isscalar(recordedGreenRepetitions) && ...
                isfinite(recordedGreenRepetitions) && ...
                recordedGreenRepetitions >= 1 && ...
                mod(recordedGreenRepetitions,1) == 0 && ...
                recordedGreenRepetitions ~= cfg.nRepetitions
            warning(['Green repetition metadata reports %d sets, but ' ...
                'the recorded block names contain %d. Block names will ' ...
                'be used for analysis.'],recordedGreenRepetitions, ...
                cfg.nRepetitions);
        end
    end

    cfg.blockFiles = resolve_recorded_paths( ...
        greenSession.camera.tifFile,sessionFolder);
    cfg.blockFrameTimes = greenSession.camera.frameTime_sec;
    cfg.blockStartGetSecs = double( ...
        greenSession.camera.startGetSecs_sec(:));
    cfg.blockFirstStimFlip_sec = double( ...
        greenSession.block.firstStimFlip_sec(:));
    cfg.ptbT0GetSecs_sec = double(greenSession.ptbT0GetSecs_sec);
else
    cfg.nRepetitions = double(result.block.repetitions);
    cfg.nBlocks = numel(result.block.names);
    cfg.sweepsPerBlock = double(result.sweeps_per_block);
    cfg.blockNames = string(result.block.names(:));
    cfg.blockRepetition = nan(cfg.nBlocks,1);

    for blockIndex = 1:cfg.nBlocks
        suffix = regexp(char(cfg.blockNames(blockIndex)), ...
            '_(\d+)$','tokens','once');

        if isempty(suffix)
            cfg.blockRepetition(blockIndex) = ...
                ceil(blockIndex/4);
        else
            cfg.blockRepetition(blockIndex) = str2double(suffix{1});
        end
    end

    cfg.blockFiles = resolve_recorded_paths( ...
        result.camera.tifFile,sessionFolder);
    cfg.blockFrameTimes = result.camera.frameTime_sec;
    cfg.blockStartGetSecs = double( ...
        result.camera.startGetSecs_sec(:));
    cfg.blockFirstStimFlip_sec = double( ...
        result.block.firstStimFlip_sec(:));
    cfg.ptbT0GetSecs_sec = double(result.clock.ptbT0GetSecs_sec);
end

if cfg.preITI_sec <= 0
    error('Analysis requires a positive pre-stimulus ITI.');
end

cfg.baselineFiles = cell(cfg.nRepetitions,1);
cfg.baselineFrameTimes = cell(cfg.nRepetitions,1);
cfg.baselineReferenceBlockIndex = nan(cfg.nRepetitions,1);

for repetitionIndex = 1:cfg.nRepetitions
    referenceBlockIndex = find( ...
        cfg.blockRepetition == repetitionIndex,1,'first');

    if isempty(referenceBlockIndex)
        error('No block exists for repetition %d.',repetitionIndex);
    end

    cfg.baselineReferenceBlockIndex(repetitionIndex) = ...
        referenceBlockIndex;
    cfg.baselineFiles{repetitionIndex} = ...
        cfg.blockFiles{referenceBlockIndex};
    cfg.baselineFrameTimes{repetitionIndex} = ...
        cfg.blockFrameTimes{referenceBlockIndex};
end

cfg.baselineDuration_sec = cfg.preITI_sec;
cfg.baselineReferenceSource = "first_block_preiti";

cfg.period_sec = repmat(double(result.contrast_period),cfg.nBlocks,1);

if strcmp(sessionType,'green') && ...
        isfield(greenSession,'block') && ...
        isfield(greenSession.block,'period_sec') && ...
        numel(greenSession.block.period_sec) == cfg.nBlocks
    cfg.period_sec = double(greenSession.block.period_sec(:));
elseif strcmp(sessionType,'red') && ...
        isfield(result.block,'period_sec') && ...
        numel(result.block.period_sec) == cfg.nBlocks
    cfg.period_sec = double(result.block.period_sec(:));
end

cfg.azimuthTrajectorySpan_deg = diff(cfg.azimuthRange_deg);
cfg.elevationTrajectorySpan_deg = diff(cfg.elevationRange_deg);

if isfield(result,'stimulus')
    if isfield(result.stimulus,'azimuthTrajectorySpan_deg')
        cfg.azimuthTrajectorySpan_deg = double( ...
            result.stimulus.azimuthTrajectorySpan_deg);
    end

    if isfield(result.stimulus,'elevationTrajectorySpan_deg')
        cfg.elevationTrajectorySpan_deg = double( ...
            result.stimulus.elevationTrajectorySpan_deg);
    end

    if isfield(result,'aperture_width_deg') && ...
            isfield(result.stimulus,'elevationSpan_deg')
        visibleElevationTravel_deg = double( ...
            result.stimulus.elevationSpan_deg) + ...
            double(result.aperture_width_deg);

        if cfg.elevationTrajectorySpan_deg > ...
                visibleElevationTravel_deg + 0.5
            warning(['Elevation trajectory exceeds visible edge-to-edge ' ...
                'travel by %.2f deg. The aperture is fully off-screen ' ...
                'during part of each sweep in this acquisition.'], ...
                cfg.elevationTrajectorySpan_deg - ...
                visibleElevationTravel_deg);
        end
    end
end

if cfg.nBlocks ~= numel(cfg.blockFiles)
    error('Block metadata and TIFF file counts do not match.');
end

cfg.blockStimulusOffset_sec = nan(cfg.nBlocks,1);

for blockIndex = 1:cfg.nBlocks
    absoluteStimulusStart = cfg.ptbT0GetSecs_sec + ...
        cfg.blockFirstStimFlip_sec(blockIndex);
    cfg.blockStimulusOffset_sec(blockIndex) = ...
        absoluteStimulusStart - cfg.blockStartGetSecs(blockIndex);

    if ~isfinite(cfg.blockStimulusOffset_sec(blockIndex)) || ...
            cfg.blockStimulusOffset_sec(blockIndex) < 0
        cfg.blockStimulusOffset_sec(blockIndex) = cfg.preITI_sec;
    end
end

cfg.directionNames = [ ...
    "nasal_to_temporal"; ...
    "temporal_to_nasal"; ...
    "inferior_to_superior"; ...
    "superior_to_inferior"];
cfg.analysisVersion = "2.0";
opts.azimuth_range_deg = cfg.azimuthRange_deg;
opts.elevation_range_deg = cfg.elevationRange_deg;
end


function paths = resolve_recorded_paths(recordedPaths,sessionFolder)
recordedPaths = string(recordedPaths(:));
paths = cell(numel(recordedPaths),1);

for pathIndex = 1:numel(recordedPaths)
    paths{pathIndex} = resolve_recorded_path( ...
        recordedPaths(pathIndex),sessionFolder);
end
end


function path = resolve_recorded_path(recordedPath,sessionFolder)
recordedPath = char(string(recordedPath));

if isfile(recordedPath)
    path = recordedPath;
    return;
end

[~,name,extension] = fileparts(recordedPath);
path = fullfile(sessionFolder,[name extension]);

if ~isfile(path)
    error('Recorded TIFF file was not found: %s',recordedPath);
end
end


function [baselineMeans,referenceFirstFrame,referenceMean,infoOut] = ...
        prepare_baselines(cfg,opts)
baselineMeans = cell(cfg.nRepetitions,1);
infoOut = repmat(struct( ...
    'tifFile',"",'frameCountUsed',0, ...
    'registrationShiftXY_pix',[0 0]),cfg.nRepetitions,1);

[referenceMean,referenceFirstRaw,firstFrameCount] = ...
    read_baseline_mean(cfg.baselineFiles{1}, ...
    cfg.baselineFrameTimes{1},cfg.baselineDuration_sec,cfg.cameraFPS);
referenceFirstFrame = process_frame( ...
    referenceFirstRaw,[0 0],opts);
baselineMeans{1} = process_frame(referenceMean,[0 0],opts);
infoOut(1).tifFile = string(cfg.baselineFiles{1});
infoOut(1).frameCountUsed = firstFrameCount;

for repetitionIndex = 2:cfg.nRepetitions
    [baselineMean,~,frameCount] = read_baseline_mean( ...
        cfg.baselineFiles{repetitionIndex}, ...
        cfg.baselineFrameTimes{repetitionIndex}, ...
        cfg.baselineDuration_sec,cfg.cameraFPS);
    shiftXY = estimate_integer_translation( ...
        baselineMean,referenceMean,opts);
    baselineMeans{repetitionIndex} = process_frame( ...
        baselineMean,shiftXY,opts);
    infoOut(repetitionIndex).tifFile = ...
        string(cfg.baselineFiles{repetitionIndex});
    infoOut(repetitionIndex).frameCountUsed = frameCount;
    infoOut(repetitionIndex).registrationShiftXY_pix = shiftXY;
end

for repetitionIndex = 1:cfg.nRepetitions
    if ~isequal(size(baselineMeans{repetitionIndex}), ...
            size(baselineMeans{1}))
        error('Processed baseline image sizes do not match.');
    end
end
end


function [meanFrame,firstFrame,nFramesUsed] = read_baseline_mean( ...
        tifFile,frameTimes,duration_sec,cameraFPS)
info = imfinfo(tifFile);
nFrames = numel(info);

if nFrames < 1
    error('Baseline TIFF contains no frames: %s',tifFile);
end

frameTimes = normalize_frame_times(frameTimes,nFrames,cameraFPS);
relativeTimes = frameTimes - frameTimes(1);
frameIndices = find(relativeTimes < duration_sec);

if isempty(frameIndices)
    frameIndices = 1:min(nFrames,max(1,round(duration_sec*cameraFPS)));
end

firstFrame = read_tiff_frame(tifFile,frameIndices(1),info);
meanFrame = zeros(size(firstFrame),'double');

for frameIndex = frameIndices(:)'
    meanFrame = meanFrame + ...
        read_tiff_frame(tifFile,frameIndex,info);
end

nFramesUsed = numel(frameIndices);
meanFrame = meanFrame/nFramesUsed;
end


function blockConfig = make_direction_block_config(cfg,blockIndex)
blockConfig = struct();
blockConfig.blockIndex = blockIndex;
blockConfig.blockName = cfg.blockNames(blockIndex);
blockConfig.tifFile = cfg.blockFiles{blockIndex};
blockConfig.frameTimes = cfg.blockFrameTimes{blockIndex};
blockConfig.cameraFPS = cfg.cameraFPS;
blockConfig.stimulusStart_sec = ...
    cfg.blockStimulusOffset_sec(blockIndex);
blockConfig.period_sec = cfg.period_sec(blockIndex);
blockConfig.sweepsPerBlock = cfg.sweepsPerBlock;
blockConfig.preITI_sec = cfg.preITI_sec;
blockConfig.baselineReferenceSource = cfg.baselineReferenceSource;
blockConfig.baselineDuration_sec = cfg.baselineDuration_sec;
end


function print_block_progress(cfg,blockIndex,repetitionIndex,blockResult)
fprintf('\nBlock %d/%d (%s), repetition %d\n', ...
    blockIndex,cfg.nBlocks,char(cfg.blockNames(blockIndex)), ...
    repetitionIndex);

for sweepIndex = 1:numel(blockResult.framesPerSweep)
    fprintf(['  sweep %02d: amplitude p95 %.3g, analyzed=%d, ' ...
        'frames=%d, shift=[%g %g]\n'], ...
        sweepIndex, ...
        blockResult.responseAmplitude95(sweepIndex), ...
        blockResult.retainedSweeps(sweepIndex), ...
        blockResult.framesPerSweep(sweepIndex), ...
        blockResult.sweepRegistrationShiftXY_pix(sweepIndex,1), ...
        blockResult.sweepRegistrationShiftXY_pix(sweepIndex,2));
end
end


function blockResult = analyze_direction_block( ...
        blockConfig,baselineMean,referenceMean,opts)
blockIndex = blockConfig.blockIndex;
tifFile = blockConfig.tifFile;
info = imfinfo(tifFile);
nFrames = numel(info);
clear info;

if nFrames < 1
    error('Block TIFF contains no frames: %s',tifFile);
end

tiffReader = Tiff(tifFile,'r');
readerCleanup = onCleanup(@() tiffReader.close());
rawFrameTimes = blockConfig.frameTimes;
[frameTimes,timingSource] = normalize_frame_times( ...
    rawFrameTimes,nFrames,blockConfig.cameraFPS);
stimulusStart = blockConfig.stimulusStart_sec;
period_sec = blockConfig.period_sec;
stimulusEnd = stimulusStart + ...
    blockConfig.sweepsPerBlock*period_sec;
stimulusFrameIndices = find( ...
    frameTimes >= stimulusStart & frameTimes < stimulusEnd);

if isempty(stimulusFrameIndices)
    warning(['No frames matched stimulus timestamps in block %d; ' ...
        'falling back to pre-ITI and nominal FPS.'],blockIndex);
    frameTimes = (0:nFrames-1)'/blockConfig.cameraFPS;
    timingSource = 'nominal_fps_fallback';
    stimulusStart = blockConfig.preITI_sec;
    stimulusEnd = stimulusStart + ...
        blockConfig.sweepsPerBlock*period_sec;
    stimulusFrameIndices = find( ...
        frameTimes >= stimulusStart & frameTimes < stimulusEnd);
end

baselineSource = char(blockConfig.baselineReferenceSource);
baselineFrameCount = 0;
blockShiftXY = [0 0];
baselineForBlock = baselineMean;
usedBlockPreITI = false;

baselineStart = max(frameTimes(1), ...
    stimulusStart-blockConfig.baselineDuration_sec);
baselineIndices = find(frameTimes >= baselineStart & ...
    frameTimes < stimulusStart);

if numel(baselineIndices) >= 3
    blockBaselineRaw = mean_selected_tiff_frames_reader( ...
        tiffReader,baselineIndices);
    blockShiftXY = estimate_integer_translation( ...
        blockBaselineRaw,referenceMean,opts);
    baselineForBlock = process_frame( ...
        blockBaselineRaw,blockShiftXY,opts);
    baselineSource = 'block_preiti';
    baselineFrameCount = numel(baselineIndices);
    usedBlockPreITI = true;
else
    warning(['Block %d has fewer than 3 pre-stimulus frames; ' ...
        'using the repetition reference image.'],blockIndex);
end

if ~usedBlockPreITI
    sampleIndices = evenly_spaced_indices( ...
        stimulusFrameIndices,opts.registration_sample_frames);
    blockMean = mean_selected_tiff_frames_reader( ...
        tiffReader,sampleIndices);
    blockShiftXY = estimate_integer_translation( ...
        blockMean,referenceMean,opts);
end

mapSize = size(baselineForBlock);
retainedComplexSum = complex(zeros(mapSize));
retainedValidCount = zeros(mapSize);
retainedAmplitudeSum = zeros(mapSize);
responseAmplitudeMedian = nan(blockConfig.sweepsPerBlock,1);
responseAmplitude95 = nan(blockConfig.sweepsPerBlock,1);
retainedSweeps = false(blockConfig.sweepsPerBlock,1);
framesPerSweep = zeros(blockConfig.sweepsPerBlock,1);
sweepShiftXY = nan(blockConfig.sweepsPerBlock,2);

for sweepIndex = 1:blockConfig.sweepsPerBlock
    sweepStart = stimulusStart + (sweepIndex-1)*period_sec;
    sweepEnd = sweepStart + period_sec;
    frameIndices = find( ...
        frameTimes >= sweepStart & frameTimes < sweepEnd);
    frameIndices = frameIndices(1:opts.temporal_stride:end);
    framesPerSweep(sweepIndex) = numel(frameIndices);

    if numel(frameIndices) < 4
        warning('Block %d sweep %d has fewer than 4 frames.', ...
            blockIndex,sweepIndex);
        continue;
    end
    sampleTimes = frameTimes(frameIndices);
    phaseRadians = 2*pi*(sampleTimes-sweepStart)/period_sec;
    complexWeights = (2/numel(frameIndices))* ...
        exp(-1i*phaseRadians(:)');
    sweepResult = analyze_single_sweep( ...
        tiffReader,tifFile,frameIndices,complexWeights, ...
        baselineForBlock,referenceMean,blockShiftXY,opts);
    sweepShiftXY(sweepIndex,:) = sweepResult.shiftXY;
    responseAmplitudeMedian(sweepIndex) = ...
        sweepResult.responseAmplitudeMedian;
    responseAmplitude95(sweepIndex) = ...
        sweepResult.responseAmplitude95;
    retainedSweeps(sweepIndex) = true;
    validCoefficient = sweepResult.validCoefficient;
    coefficient = sweepResult.coefficient;
    retainedComplexSum(validCoefficient) = ...
        retainedComplexSum(validCoefficient) + ...
        coefficient(validCoefficient);
    retainedValidCount(validCoefficient) = ...
        retainedValidCount(validCoefficient) + 1;
    retainedAmplitudeSum(validCoefficient) = ...
        retainedAmplitudeSum(validCoefficient) + ...
        abs(coefficient(validCoefficient));
end

blockResult = struct();
blockResult.retainedComplexSum = retainedComplexSum;
blockResult.retainedValidCount = retainedValidCount;
blockResult.retainedAmplitudeSum = retainedAmplitudeSum;
blockResult.retainedSweepCount = sum(retainedSweeps);
blockResult.responseAmplitudeMedian = responseAmplitudeMedian;
blockResult.responseAmplitude95 = responseAmplitude95;
blockResult.retainedSweeps = retainedSweeps;
blockResult.framesPerSweep = framesPerSweep;
blockResult.registrationShiftXY_pix = blockShiftXY;
blockResult.sweepRegistrationShiftXY_pix = sweepShiftXY;
blockResult.timingSource = timingSource;
blockResult.baselineSource = baselineSource;
blockResult.baselineFrameCount = baselineFrameCount;

if blockResult.retainedSweepCount == 0
    warning('No sweep could be analyzed for block %d (%s).', ...
        blockIndex, ...
        char(blockConfig.blockName));
end
end


function sweepResult = analyze_single_sweep( ...
        tiffReader,tifFile,frameIndices,complexWeights, ...
        baselineForBlock,referenceMean,blockShiftXY,opts)
thisShiftXY = blockShiftXY;

if opts.register_blocks && opts.register_sweeps
    registrationIndices = evenly_spaced_indices(frameIndices, ...
        opts.registration_sample_frames_per_sweep);
    sweepMean = mean_selected_tiff_frames_reader( ...
        tiffReader,registrationIndices);
    thisShiftXY = estimate_integer_translation( ...
        sweepMean,referenceMean,opts);
end

mapSize = size(baselineForBlock);
baselineValid = isfinite(baselineForBlock) & baselineForBlock > 0;
baselineDenominator = max(baselineForBlock,eps);
coefficient = complex(zeros(mapSize));
validCoefficient = baselineValid;

for localFrameIndex = 1:numel(frameIndices)
    frame = read_tiff_frame_reader( ...
        tiffReader,frameIndices(localFrameIndex));
    frame = process_frame(frame,thisShiftXY,opts);

    if ~isequal(size(frame),mapSize)
        error(['Processed TIFF frame size does not match the baseline ' ...
            'size for file %s.'],tifFile);
    end

    deltaAbsorbance = log10(max(frame,eps)./baselineDenominator);
    validPixel = isfinite(deltaAbsorbance) & baselineValid;
    coefficient(validPixel) = coefficient(validPixel) + ...
        deltaAbsorbance(validPixel)*complexWeights(localFrameIndex);
    validCoefficient = validCoefficient & validPixel;
end

coefficient(~validCoefficient) = complex(NaN,NaN);
finiteAmplitude = abs(coefficient(validCoefficient));
responseAmplitudeMedian = NaN;
responseAmplitude95 = NaN;

if ~isempty(finiteAmplitude)
    responseAmplitudeMedian = percentile_local(finiteAmplitude,50);
    responseAmplitude95 = percentile_local(finiteAmplitude,95);
end

sweepResult = struct();
sweepResult.shiftXY = thisShiftXY;
sweepResult.responseAmplitudeMedian = responseAmplitudeMedian;
sweepResult.responseAmplitude95 = responseAmplitude95;
sweepResult.coefficient = coefficient;
sweepResult.validCoefficient = validCoefficient;
end


function frame = read_tiff_frame_reader(tiffReader,frameIndex)
tiffReader.setDirectory(frameIndex);
frame = double(tiffReader.read());

if ndims(frame) == 3
    frame = mean(frame,3);
end
end


function meanFrame = mean_selected_tiff_frames_reader( ...
        tiffReader,indices)
if isempty(indices)
    error('No TIFF frames were selected for sweep registration.');
end

firstFrame = read_tiff_frame_reader(tiffReader,indices(1));
meanFrame = zeros(size(firstFrame));

for frameIndex = indices(:)'
    meanFrame = meanFrame + ...
        read_tiff_frame_reader(tiffReader,frameIndex);
end

meanFrame = meanFrame/numel(indices);
end


function aggregate = new_direction_aggregate(mapSize)
aggregate = struct();
aggregate.complexSum = complex(zeros([mapSize 4]));
aggregate.validCount = zeros([mapSize 4]);
aggregate.amplitudeSum = zeros([mapSize 4]);
aggregate.retainedSweepCount = zeros(4,1);
end


function aggregate = add_block_to_aggregate( ...
        aggregate,blockResult,directionIndex)
aggregate.complexSum(:,:,directionIndex) = ...
    aggregate.complexSum(:,:,directionIndex) + ...
    blockResult.retainedComplexSum;
aggregate.validCount(:,:,directionIndex) = ...
    aggregate.validCount(:,:,directionIndex) + ...
    blockResult.retainedValidCount;
aggregate.amplitudeSum(:,:,directionIndex) = ...
    aggregate.amplitudeSum(:,:,directionIndex) + ...
    blockResult.retainedAmplitudeSum;
aggregate.retainedSweepCount(directionIndex) = ...
    aggregate.retainedSweepCount(directionIndex) + ...
    blockResult.retainedSweepCount;
end


function directionIndex = direction_name_to_index(blockName)
blockName = string(blockName);

if startsWith(blockName,"nasal_to_temporal")
    directionIndex = 1;
elseif startsWith(blockName,"temporal_to_nasal")
    directionIndex = 2;
elseif startsWith(blockName,"inferior_to_superior")
    directionIndex = 3;
elseif startsWith(blockName,"superior_to_inferior")
    directionIndex = 4;
else
    error('Unknown retinotopy block name: %s',blockName);
end
end


function qcTable = make_qc_table(cfg,blockIndex,blockResult)
nSweeps = numel(blockResult.framesPerSweep);
SessionType = repmat(string(cfg.sessionType),nSweeps,1);
GreenSession = repmat(cfg.greenSessionIndex,nSweeps,1);
Repetition = repmat(cfg.blockRepetition(blockIndex),nSweeps,1);
BlockIndex = repmat(blockIndex,nSweeps,1);
BlockName = repmat(cfg.blockNames(blockIndex),nSweeps,1);
SweepIndex = (1:nSweeps)';
ResponseAmplitudeMedian = blockResult.responseAmplitudeMedian(:);
ResponseAmplitude95 = blockResult.responseAmplitude95(:);
Retained = blockResult.retainedSweeps(:);
FrameCount = blockResult.framesPerSweep(:);
RegistrationShiftX_pix = ...
    blockResult.sweepRegistrationShiftXY_pix(:,1);
RegistrationShiftY_pix = ...
    blockResult.sweepRegistrationShiftXY_pix(:,2);
TIFF_File = repmat(string(cfg.blockFiles{blockIndex}),nSweeps,1);
qcTable = table(SessionType,GreenSession,Repetition,BlockIndex, ...
    BlockName,SweepIndex,ResponseAmplitudeMedian, ...
    ResponseAmplitude95,Retained,FrameCount,RegistrationShiftX_pix, ...
    RegistrationShiftY_pix,TIFF_File);
end


function maps = make_retinotopy_maps(aggregate,cfg,opts)
mapSize = size(aggregate.complexSum(:,:,1));
directionPhase = nan([mapSize 4]);
directionAmplitude = nan([mapSize 4]);
directionCoherence = nan([mapSize 4]);

for directionIndex = 1:4
    sumSlice = aggregate.complexSum(:,:,directionIndex);
    countSlice = aggregate.validCount(:,:,directionIndex);
    amplitudeSumSlice = aggregate.amplitudeSum(:,:,directionIndex);
    valid = countSlice > 0;
    directionMean = complex(nan(mapSize));
    directionMean(valid) = sumSlice(valid)./countSlice(valid);
    directionMean = nan_gaussian_complex_filter( ...
        directionMean,opts.map_smoothing_sigma);
    directionPhase(:,:,directionIndex) = angle(directionMean);
    directionAmplitude(:,:,directionIndex) = abs(directionMean);
    coherenceValid = amplitudeSumSlice > 0;
    coherenceSlice = nan(mapSize);
    coherenceSlice(coherenceValid) = ...
        abs(sumSlice(coherenceValid))./ ...
        amplitudeSumSlice(coherenceValid);
    directionCoherence(:,:,directionIndex) = ...
        nan_gaussian_filter(coherenceSlice,opts.map_smoothing_sigma);
end

azimuthCoherence = nan(mapSize);
elevationCoherence = nan(mapSize);
azimuthForwardCoherence = directionCoherence(:,:,1);
azimuthReverseCoherence = directionCoherence(:,:,2);
elevationForwardCoherence = directionCoherence(:,:,3);
elevationReverseCoherence = directionCoherence(:,:,4);
azimuthPairValid = isfinite(azimuthForwardCoherence) & ...
    isfinite(azimuthReverseCoherence);
elevationPairValid = isfinite(elevationForwardCoherence) & ...
    isfinite(elevationReverseCoherence);
azimuthCoherence(azimuthPairValid) = min( ...
    azimuthForwardCoherence(azimuthPairValid), ...
    azimuthReverseCoherence(azimuthPairValid));
elevationCoherence(elevationPairValid) = min( ...
    elevationForwardCoherence(elevationPairValid), ...
    elevationReverseCoherence(elevationPairValid));

azimuthAmplitude = sqrt( ...
    directionAmplitude(:,:,1).*directionAmplitude(:,:,2));
elevationAmplitude = sqrt( ...
    directionAmplitude(:,:,3).*directionAmplitude(:,:,4));
azimuthAbsolutePhase = opts.azimuth_phase_sign* ...
    (directionPhase(:,:,1)-directionPhase(:,:,2))/2;
elevationAbsolutePhase = opts.elevation_phase_sign* ...
    (directionPhase(:,:,3)-directionPhase(:,:,4))/2;
azimuthSpan = cfg.azimuthTrajectorySpan_deg;
elevationSpan = cfg.elevationTrajectorySpan_deg;
azimuthCenter = mean(cfg.azimuthRange_deg);
elevationCenter = mean(cfg.elevationRange_deg);
azimuth_deg = azimuthCenter + ...
    azimuthAbsolutePhase/(2*pi)*azimuthSpan;
elevation_deg = elevationCenter + ...
    elevationAbsolutePhase/(2*pi)*elevationSpan;
azimuth_deg(azimuthCoherence < opts.minimum_phase_coherence) = NaN;
elevation_deg(elevationCoherence < opts.minimum_phase_coherence) = NaN;

[azimuthDx,azimuthDy] = gradient(azimuth_deg);
[elevationDx,elevationDy] = gradient(elevation_deg);
azimuthGradientAngle = atan2(azimuthDy,azimuthDx);
elevationGradientAngle = atan2(elevationDy,elevationDx);
vfs = sin(elevationGradientAngle-azimuthGradientAngle);
vfs = nan_gaussian_filter(vfs,opts.vfs_smoothing_sigma);
vfs = max(-1,min(1,vfs));

maps = struct();
maps.azimuth_deg = azimuth_deg;
maps.elevation_deg = elevation_deg;
maps.vfs = vfs;
maps.azimuthAbsolutePhase_rad = azimuthAbsolutePhase;
maps.elevationAbsolutePhase_rad = elevationAbsolutePhase;
maps.directionPhase_rad = directionPhase;
maps.directionAmplitude = directionAmplitude;
maps.directionCoherence = directionCoherence;
maps.azimuthCoherence = azimuthCoherence;
maps.elevationCoherence = elevationCoherence;
maps.azimuthAmplitude = azimuthAmplitude;
maps.elevationAmplitude = elevationAmplitude;
maps.directionNames = cfg.directionNames;
maps.retainedSweepCount = aggregate.retainedSweepCount;
maps.azimuthRange_deg = cfg.azimuthRange_deg;
maps.elevationRange_deg = cfg.elevationRange_deg;
end


function maps = make_repetition_consensus_maps( ...
        repetitionMaps,cfg,opts)
nRepetitions = numel(repetitionMaps);

if nRepetitions < 1
    error('At least one repetition map is required.');
end

maps = repetitionMaps(1);
maps.repetition = 0;
maps.repetitionCount = nRepetitions;
maps.combinationMethod = ...
    "pixelwise_median_of_repetition_coordinate_maps";
maps.minimumRepetitionSupport = floor(nRepetitions/2) + 1;

[maps.azimuth_deg,maps.azimuthRepetitionSupportCount] = ...
    median_repetition_field(repetitionMaps,'azimuth_deg');
[maps.elevation_deg,maps.elevationRepetitionSupportCount] = ...
    median_repetition_field(repetitionMaps,'elevation_deg');
[maps.azimuthCoherence,~] = ...
    median_repetition_field(repetitionMaps,'azimuthCoherence');
[maps.elevationCoherence,~] = ...
    median_repetition_field(repetitionMaps,'elevationCoherence');
[maps.azimuthAmplitude,~] = ...
    median_repetition_field(repetitionMaps,'azimuthAmplitude');
[maps.elevationAmplitude,~] = ...
    median_repetition_field(repetitionMaps,'elevationAmplitude');

azimuthSupported = maps.azimuthRepetitionSupportCount >= ...
    maps.minimumRepetitionSupport;
elevationSupported = maps.elevationRepetitionSupportCount >= ...
    maps.minimumRepetitionSupport;
maps.azimuth_deg(~azimuthSupported) = NaN;
maps.elevation_deg(~elevationSupported) = NaN;
maps.azimuthCoherence(~azimuthSupported) = NaN;
maps.elevationCoherence(~elevationSupported) = NaN;

mapSize = size(maps.azimuth_deg);
nDirections = size(repetitionMaps(1).directionPhase_rad,3);
maps.directionPhase_rad = nan([mapSize nDirections]);
maps.directionAmplitude = nan([mapSize nDirections]);
maps.directionCoherence = nan([mapSize nDirections]);

for directionIndex = 1:nDirections
    weightedPhaseSum = complex(zeros(mapSize));
    phaseWeightSum = zeros(mapSize);
    coherenceSum = zeros(mapSize);
    coherenceCount = zeros(mapSize);
    amplitudeSum = zeros(mapSize);
    amplitudeCount = zeros(mapSize);

    for repetitionIndex = 1:nRepetitions
        phase = repetitionMaps( ...
            repetitionIndex).directionPhase_rad(:,:,directionIndex);
        coherence = repetitionMaps( ...
            repetitionIndex).directionCoherence(:,:,directionIndex);
        amplitude = repetitionMaps( ...
            repetitionIndex).directionAmplitude(:,:,directionIndex);
        validPhase = isfinite(phase) & isfinite(coherence) & ...
            coherence > 0;
        phaseWeight = zeros(mapSize);
        phaseWeight(validPhase) = coherence(validPhase);
        weightedPhaseContribution = complex(zeros(mapSize));
        weightedPhaseContribution(validPhase) = ...
            phaseWeight(validPhase).*exp(1i*phase(validPhase));
        weightedPhaseSum = weightedPhaseSum + ...
            weightedPhaseContribution;
        phaseWeightSum = phaseWeightSum + phaseWeight;

        validCoherence = isfinite(coherence);
        coherenceSum(validCoherence) = ...
            coherenceSum(validCoherence) + coherence(validCoherence);
        coherenceCount(validCoherence) = ...
            coherenceCount(validCoherence) + 1;

        validAmplitude = isfinite(amplitude);
        amplitudeSum(validAmplitude) = ...
            amplitudeSum(validAmplitude) + amplitude(validAmplitude);
        amplitudeCount(validAmplitude) = ...
            amplitudeCount(validAmplitude) + 1;
    end

    validPhaseAverage = phaseWeightSum > 0;
    thisDirectionPhase = nan(mapSize);
    thisDirectionPhase(validPhaseAverage) = angle( ...
        weightedPhaseSum(validPhaseAverage));
    maps.directionPhase_rad(:,:,directionIndex) = ...
        thisDirectionPhase;

    validCoherenceAverage = coherenceCount > 0;
    thisDirectionCoherence = nan(mapSize);
    thisDirectionCoherence(validCoherenceAverage) = ...
        coherenceSum(validCoherenceAverage)./ ...
        coherenceCount(validCoherenceAverage);
    maps.directionCoherence(:,:,directionIndex) = ...
        thisDirectionCoherence;

    validAmplitudeAverage = amplitudeCount > 0;
    thisDirectionAmplitude = nan(mapSize);
    thisDirectionAmplitude(validAmplitudeAverage) = ...
        amplitudeSum(validAmplitudeAverage)./ ...
        amplitudeCount(validAmplitudeAverage);
    maps.directionAmplitude(:,:,directionIndex) = ...
        thisDirectionAmplitude;
end

azimuthCenter = mean(cfg.azimuthRange_deg);
elevationCenter = mean(cfg.elevationRange_deg);
maps.azimuthAbsolutePhase_rad = 2*pi * ...
    (maps.azimuth_deg-azimuthCenter) / ...
    cfg.azimuthTrajectorySpan_deg;
maps.elevationAbsolutePhase_rad = 2*pi * ...
    (maps.elevation_deg-elevationCenter) / ...
    cfg.elevationTrajectorySpan_deg;

[azimuthDx,azimuthDy] = gradient(maps.azimuth_deg);
[elevationDx,elevationDy] = gradient(maps.elevation_deg);
azimuthGradientAngle = atan2(azimuthDy,azimuthDx);
elevationGradientAngle = atan2(elevationDy,elevationDx);
maps.vfs = sin(elevationGradientAngle-azimuthGradientAngle);
maps.vfs = nan_gaussian_filter( ...
    maps.vfs,opts.vfs_smoothing_sigma);
maps.vfs = max(-1,min(1,maps.vfs));

maps.retainedSweepCount = zeros( ...
    size(repetitionMaps(1).retainedSweepCount));

for repetitionIndex = 1:nRepetitions
    maps.retainedSweepCount = maps.retainedSweepCount + ...
        repetitionMaps(repetitionIndex).retainedSweepCount;
end
end


function [medianMap,supportCount] = ...
        median_repetition_field(repetitionMaps,fieldName)
referenceMap = repetitionMaps(1).(fieldName);
nRepetitions = numel(repetitionMaps);
mapStack = nan(size(referenceMap,1),size(referenceMap,2), ...
    nRepetitions);

for repetitionIndex = 1:nRepetitions
    thisMap = repetitionMaps(repetitionIndex).(fieldName);

    if ~isequal(size(thisMap),size(referenceMap))
        error('Repetition field sizes do not match for %s.',fieldName);
    end

    mapStack(:,:,repetitionIndex) = thisMap;
end

supportCount = uint16(sum(isfinite(mapStack),3));
medianMap = median(mapStack,3,'omitnan');
end


function filtered = nan_gaussian_complex_filter(imageData,sigma)
filtered = complex( ...
    nan_gaussian_filter(real(imageData),sigma), ...
    nan_gaussian_filter(imag(imageData),sigma));
end


function filtered = nan_gaussian_filter(imageData,sigma)
if sigma <= 0
    filtered = imageData;
    return;
end

valid = isfinite(imageData);
values = imageData;
values(~valid) = 0;
numerator = imgaussfilt(values,sigma,'Padding','replicate');
denominator = imgaussfilt(double(valid),sigma,'Padding','replicate');
filtered = numerator./max(denominator,eps);
filtered(denominator < 1e-6) = NaN;
end


function plot_maps(maps,cfg,opts,outputFile,figureTitle)
if opts.show_figures
    visibility = 'on';
else
    visibility = 'off';
end

fig = figure('Visible',visibility,'Color','w', ...
    'Position',[100 100 1500 900]);
layout = tiledlayout(fig,2,3,'TileSpacing','compact', ...
    'Padding','compact');
title(layout,figureTitle,'Interpreter','none');

ax1 = nexttile(layout);
imagesc(ax1,maps.azimuth_deg);
axis(ax1,'image','off');
title(ax1,'Azimuth (deg)');
clim(ax1,cfg.azimuthRange_deg);
colormap(ax1,turbo(256));
colorbar(ax1);

ax2 = nexttile(layout);
imagesc(ax2,maps.elevation_deg);
axis(ax2,'image','off');
title(ax2,'Elevation (deg)');
clim(ax2,cfg.elevationRange_deg);
colormap(ax2,turbo(256));
colorbar(ax2);

ax3 = nexttile(layout);
imagesc(ax3,maps.vfs);
axis(ax3,'image','off');
title(ax3,'Visual field sign');
clim(ax3,[-1 1]);
colormap(ax3,blue_white_red(256));
colorbar(ax3);

ax4 = nexttile(layout);
imagesc(ax4,maps.azimuthCoherence);
axis(ax4,'image','off');
title(ax4,'Azimuth phase coherence');
clim(ax4,[0 1]);
colormap(ax4,parula(256));
colorbar(ax4);

ax5 = nexttile(layout);
imagesc(ax5,maps.elevationCoherence);
axis(ax5,'image','off');
title(ax5,'Elevation phase coherence');
clim(ax5,[0 1]);
colormap(ax5,parula(256));
colorbar(ax5);

ax6 = nexttile(layout);
pairAmplitude = sqrt(maps.azimuthAmplitude.*maps.elevationAmplitude);
imagesc(ax6,log10(max(pairAmplitude,eps)));
axis(ax6,'image','off');
title(ax6,'log10 paired response amplitude');
colormap(ax6,parula(256));
colorbar(ax6);

exportgraphics(fig,outputFile,'Resolution',200);

if ~opts.show_figures
    close(fig);
end
end


function write_vfs_overlay(background,vfs,outputFile,opts)
background = normalize_image(background);
backgroundRGB = repmat(background,1,1,3);
colorMap = blue_white_red(256);
vfsClipped = max(-1,min(1,vfs));
colorIndex = round((vfsClipped+1)/2*255)+1;
colorIndex(~isfinite(colorIndex)) = 128;
vfsRGB = reshape(colorMap(colorIndex(:),:), ...
    [size(vfs,1),size(vfs,2),3]);
alpha = opts.overlay_alpha*min(1,abs(vfsClipped));
alpha(~isfinite(alpha)) = 0;
alpha = repmat(alpha,1,1,3);
overlay = backgroundRGB.*(1-alpha) + vfsRGB.*alpha;
overlay = max(0,min(1,overlay));
imwrite(uint8(round(overlay*255)),outputFile);

if opts.show_figures
    figure('Color','w');
    imshow(overlay);
    title('Overall VFS on first baseline frame');
end
end


function write_reference_image(imageData,outputFile)
normalized = normalize_image(imageData);
imwrite(uint16(round(normalized*double(intmax('uint16')))), ...
    outputFile);
end


function colorMap = blue_white_red(nColors)
half = ceil(nColors/2);
blueToWhite = [linspace(0,1,half)' linspace(0,1,half)' ...
    ones(half,1)];
redCount = nColors-half;
whiteToRed = [ones(redCount,1) linspace(1,0,redCount)' ...
    linspace(1,0,redCount)'];
colorMap = [blueToWhite;whiteToRed];
end


function normalized = normalize_image(imageData)
finiteValues = imageData(isfinite(imageData));

if isempty(finiteValues)
    normalized = zeros(size(imageData));
    return;
end

lowerLimit = percentile_local(finiteValues,1);
upperLimit = percentile_local(finiteValues,99);

if upperLimit <= lowerLimit
    lowerLimit = min(finiteValues);
    upperLimit = max(finiteValues);
end

if upperLimit <= lowerLimit
    normalized = zeros(size(imageData));
else
    normalized = (imageData-lowerLimit)/(upperLimit-lowerLimit);
    normalized = max(0,min(1,normalized));
    normalized(~isfinite(normalized)) = 0;
end
end


function value = percentile_local(values,percent)
values = sort(values(:));

if isempty(values)
    value = NaN;
    return;
end

position = 1 + (numel(values)-1)*percent/100;
lowerIndex = floor(position);
upperIndex = ceil(position);
fraction = position-lowerIndex;
value = values(lowerIndex)*(1-fraction) + ...
    values(upperIndex)*fraction;
end


function [frameTimes,timingSource] = normalize_frame_times( ...
        recordedTimes,nFrames,cameraFPS)
recordedTimes = double(recordedTimes(:));

if numel(recordedTimes) == nFrames && ...
        all(isfinite(recordedTimes)) && ...
        all(diff(recordedTimes) > 0)
    frameTimes = recordedTimes;
    timingSource = 'camera_metadata';
else
    frameTimes = (0:nFrames-1)'/cameraFPS;
    timingSource = 'nominal_fps';
end
end


function frame = read_tiff_frame(tifFile,frameIndex,info)
frame = imread(tifFile,frameIndex,'Info',info);
frame = double(frame);

if ndims(frame) == 3
    frame = mean(frame,3);
end
end


function indices = evenly_spaced_indices(indices,maxCount)
indices = indices(:);

if isempty(indices)
    return;
end

if numel(indices) <= maxCount
    return;
end

selection = unique(round(linspace(1,numel(indices),maxCount)));
indices = indices(selection);
end


function shiftXY = estimate_integer_translation(moving,fixed,opts)
shiftXY = [0 0];

if ~opts.register_blocks
    return;
end

if ~isequal(size(moving),size(fixed))
    error('Registration images have different sizes.');
end

try
    maximumDimension = max(size(fixed));
    registrationScale = min(1,512/maximumDimension);

    if registrationScale < 1
        movingForRegistration = imresize( ...
            moving,registrationScale,'bilinear');
        fixedForRegistration = imresize( ...
            fixed,registrationScale,'bilinear');
    else
        movingForRegistration = moving;
        fixedForRegistration = fixed;
    end

    movingForRegistration = normalize_image(movingForRegistration);
    fixedForRegistration = normalize_image(fixedForRegistration);
    transform = imregcorr(movingForRegistration, ...
        fixedForRegistration,'translation');

    if isprop(transform,'A')
        transformMatrix = transform.A;
    else
        transformMatrix = transform.T;
    end

    shiftXY = round(transformMatrix(3,1:2)/registrationScale);

    if any(abs(shiftXY) > max(size(fixed))/4)
        warning(['Estimated registration shift [%d %d] is too large; ' ...
            'using [0 0].'],shiftXY(1),shiftXY(2));
        shiftXY = [0 0];
    end
catch ME
    warning('intrinsic:RegistrationFailed', ...
        'Block registration failed; using [0 0]: %s',ME.message);
    shiftXY = [0 0];
end
end


function processed = process_frame(frame,shiftXY,opts)
processed = translate_integer(frame,shiftXY);

if ~isempty(opts.crop_rect)
    rect = round(double(opts.crop_rect(:)'));
    xStart = max(1,rect(1));
    yStart = max(1,rect(2));
    width = max(1,rect(3));
    height = max(1,rect(4));
    xEnd = min(size(processed,2),xStart+width-1);
    yEnd = min(size(processed,1),yStart+height-1);

    if xEnd < xStart || yEnd < yStart
        error('crop_rect does not overlap the image.');
    end

    processed = processed(yStart:yEnd,xStart:xEnd);
end

if opts.spatial_bin > 1
    targetSize = max(1,floor(size(processed)/opts.spatial_bin));
    processed = imresize(processed,targetSize,'bilinear');
end
end


function shifted = translate_integer(frame,shiftXY)
dx = round(shiftXY(1));
dy = round(shiftXY(2));
shifted = nan(size(frame));
height = size(frame,1);
width = size(frame,2);

sourceXStart = max(1,1-dx);
sourceXEnd = min(width,width-dx);
sourceYStart = max(1,1-dy);
sourceYEnd = min(height,height-dy);

if sourceXEnd < sourceXStart || sourceYEnd < sourceYStart
    return;
end

destinationXStart = sourceXStart+dx;
destinationXEnd = sourceXEnd+dx;
destinationYStart = sourceYStart+dy;
destinationYEnd = sourceYEnd+dy;
shifted(destinationYStart:destinationYEnd, ...
    destinationXStart:destinationXEnd) = ...
    frame(sourceYStart:sourceYEnd,sourceXStart:sourceXEnd);
end
