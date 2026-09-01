function analysis = analyze_cmnoise_retinotopy_parallel(sessionFolder,varargin)
%ANALYZE_CMNOISE_RETINOTOPY_PARALLEL Analyze BigTIFF blocks in parallel.
%   ANALYSIS = ANALYZE_CMNOISE_RETINOTOPY_PARALLEL(SESSIONFOLDER) runs the
%   retinotopy analysis with block-level parallel processing enabled. Each
%   worker opens one block BigTIFF once and processes its sweeps
%   sequentially.
%
%   Name-value options are passed to ANALYZE_CMNOISE_RETINOTOPY. Useful
%   parallel options include:
%       'num_workers'               requested process-worker count
%       'parallel_block_batch_size' maximum in-memory block results
%   Green-light analysis automatically groups all recorded direction-set
%   repetitions in the selected green session using the block-name suffix.
%
%   Examples:
%       analyze_cmnoise_retinotopy_parallel(folder, ...
%           'session_type','red','num_workers',8)
%       analyze_cmnoise_retinotopy_parallel(folder, ...
%           'session_type','green','green_session_index',1)

if nargin < 1
    sessionFolder = [];
end

if has_name_value_option(varargin,'use_parallel')
    error(['Do not pass use_parallel to this function. Use ' ...
        'analyze_cmnoise_retinotopy with use_parallel=false for ' ...
        'sequential processing.']);
end

analysis = analyze_cmnoise_retinotopy( ...
    sessionFolder,'use_parallel',true,varargin{:});
end


function tf = has_name_value_option(arguments,optionName)
tf = false;

for argumentIndex = 1:2:numel(arguments)
    candidate = arguments{argumentIndex};

    if (ischar(candidate) || isstring(candidate)) && ...
            strcmpi(string(candidate),string(optionName))
        tf = true;
        return;
    end
end
end
