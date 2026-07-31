function [result, fnameLocal, fnameRemote] = saveFilePrep(result)
%SAVEFILEPREP Prepare a local result filename for run_cmnoise_kt.

saveFolder = result.camera_save_folder;

if ~exist(saveFolder, 'dir')
    mkdir(saveFolder);
end

timestamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
fileName = sprintf('%s_%s_depth%s_%s.mat', ...
    result.animalid, result.exptid, result.depth, timestamp);

fnameLocal = fullfile(saveFolder, fileName);
fnameRemote = '';

% Remote saving is intentionally disabled.
result.save_remote = false;
result.result_file = fnameLocal;
end
