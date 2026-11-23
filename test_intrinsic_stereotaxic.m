function tests = test_intrinsic_stereotaxic
% Run: results = runtests('test_intrinsic_stereotaxic'); assertSuccess(results)
tests = functiontests(localfunctions);
end

function testOriginAxisAndScale(testCase)
b = [500 200]; l = [500 600];
points = [b;l;600 100;400 300];
[actual,cal] = intrinsic_stereotaxic_coordinates(points,b,l,[100 1100],5,1);
verifyEqual(testCase,actual,[0 0;-2 0;.5 .5;-.5 -.5],'AbsTol',1e-12);
verifyEqual(testCase,cal.mm_per_pixel,.005,'AbsTol',1e-12);
verifyEqual(testCase,cal.bregma_lambda_distance_mm,2,'AbsTol',1e-12);
end

function testRotationTranslationAndScaling(testCase)
% A known AP=+1.25, ML=-0.75 target retains its coordinates when the camera
% rotates, the image origin shifts, or every pixel distance is rescaled.
for theta = [0 pi/7 pi/2 pi 1.7*pi]
    rotation = [cos(theta) -sin(theta);sin(theta) cos(theta)];
    for magnification = [.5 1 3]
        b = [32 -71];
        l = b+([0 400]*rotation')*magnification;
        target = b+([-150 -250]*rotation')*magnification;
        actual = intrinsic_stereotaxic_coordinates(target,b,l, ...
            [20 20+1000*magnification],5,1);
        verifyEqual(testCase,actual,[1.25 -.75],'AbsTol',1e-12);
    end
end
end

function testReflectionAndBoundaryOrder(testCase)
normal = intrinsic_stereotaxic_coordinates([600 100],[500 200], ...
    [500 600],[100 1100],5,1);
mirrored = intrinsic_stereotaxic_coordinates([400 100],[500 200], ...
    [500 600],[1100 100],5,-1);
verifyEqual(testCase,mirrored,normal,'AbsTol',1e-12);
end

function testThreeMillimeterCoverslip(testCase)
points = [500 200;500 600;600 100];
[stereo,cal,rig] = intrinsic_stereotaxic_coordinates(points, ...
    [500 200],[500 600],[100 1100],3,1);
verifyEqual(testCase,rig,[0 0;-1.2 0;.3 .3],'AbsTol',1e-12);
verifyEqual(testCase,stereo,rig);
verifyEqual(testCase,cal.mm_per_pixel,.003,'AbsTol',1e-12);
end

function testWeightedAPCorrectionAndRigCoordinates(testCase)
% At 100 pixels/mm, B-L appears 4 mm vs 5 mm at surgery (factor 1.25).
% The coverslip AP diameter appears 2/3 of its true size (factor 1.5).
% The combined factor must be 1.375, independent of camera rotation or size.
for theta = [0 pi/7 pi/2 pi]
    rotation = [cos(theta) -sin(theta);sin(theta) cos(theta)];
    b = [200 100]; l = b+[0 400]*rotation';
    points = b+[0 0;0 400;-50 -100;50 200]*rotation';
    expectedRig = [0 0;-4 0;1 -.5;-2 .5];
    for diameter = [3 5]
        endpoints = b+[10 -200;70 -200+diameter*100/1.5]*rotation';
        references = {[],[];5,[];[],endpoints;5,endpoints};
        factors = [1 1.25 1.5 1.375];
        weights = [0 0;1 0;0 1;.5 .5];
        for k = 1:size(references,1)
            [stereo,cal,rig] = intrinsic_stereotaxic_coordinates(points,b,l, ...
                [0 diameter*100],diameter,1,'x',references{k,1},references{k,2});
            verifyEqual(testCase,rig,expectedRig,'AbsTol',1e-12);
            verifyEqual(testCase,stereo(:,1),expectedRig(:,1)*factors(k),'AbsTol',1e-12);
            verifyEqual(testCase,stereo(:,2),rig(:,2),'AbsTol',1e-12);
            verifyEqual(testCase,cal.ap_weights_bl_coverslip,weights(k,:));
            verifyEqual(testCase,cal.ap_correction_factor,factors(k),'AbsTol',1e-12);
        end
    end
end
end

function testEmptyAndInvalidCalibration(testCase)
[actual,cal] = intrinsic_stereotaxic_coordinates(zeros(0,2), ...
    [0 0],[0 100],[0 500]);
verifySize(testCase,actual,[0 2]);
verifyEqual(testCase,cal.mm_per_pixel,.01,'AbsTol',1e-12);
verifyError(testCase,@()intrinsic_stereotaxic_coordinates([0 0], ...
    [0 0],[0 100],[4 4]),'intrinsicStereo:InvalidScale');
verifyError(testCase,@()intrinsic_stereotaxic_coordinates([0 0], ...
    [0 0],[0 .1],[0 500]),'intrinsicStereo:InvalidLandmarks');
verifyError(testCase,@()intrinsic_stereotaxic_coordinates([0 0], ...
    [0 0],[0 100],[0 500],5,0),'intrinsicStereo:InvalidMLSign');
verifyError(testCase,@()intrinsic_stereotaxic_coordinates([0 0], ...
    [0 0],[0 100],[0 500],5,1,'x',[],[0 0;100 0]), ...
    'intrinsicStereo:InvalidCoverslipAP');
end

function testGuiImageAndControls(testCase)
folder = tempname; mkdir(folder);
cleanup = onCleanup(@()rmdir(folder,'s')); %#ok<NASGU>
path = fullfile(folder,'small_grayscale.png');
imwrite(uint8(repmat(0:255,120,1)),path);
fig = intrinsic_stereotaxic_gui(path);
cleanupFig = onCleanup(@()delete(fig)); %#ok<NASGU>
set(fig,'Visible','off');
drawnow;
ui = getappdata(fig,'IntrinsicStereoUI');
ax = getappdata(fig,'IntrinsicStereoAxes');
verifyEqual(testCase,get(ui.save,'Enable'),'off');
verifyEqual(testCase,get(ax,'YDir'),'reverse');
verifyEqual(testCase,size(get(findobj(ax,'Type','image'),'CData')),[120 256 3]);
set(ui.width,'Value',2);
callback = get(ui.width,'Callback'); callback(ui.width,[]);
callback = get(ui.flip,'Callback'); callback(ui.flip,[]);
set(ui.margin,'String','50');
callback = get(ui.margin,'Callback'); callback(ui.margin,[]);
state = getappdata(fig,'IntrinsicStereoState');
verifyEqual(testCase,state.widthMm,3);
verifyEqual(testCase,state.mlSign,-1);
verifyEqual(testCase,state.marginPercent,50);
verifyEqual(testCase,get(ax,'XLim'),[-127.5 384.5],'AbsTol',1e-12);
callback = get(ui.bregma,'Callback'); callback(ui.bregma,[]);
state = getappdata(fig,'IntrinsicStereoState');
verifyEqual(testCase,state.mode,'bregma');
end

function testPlacementMovementSaveAndReload(testCase)
exercisePlacementMovementSaveAndReload(testCase,'x');
end

function testHorizontalBoundariesSaveAndReload(testCase)
exercisePlacementMovementSaveAndReload(testCase,'y');
end

function testCorrectedCoordinatesSaveAndReload(testCase)
exercisePlacementMovementSaveAndReload(testCase,'x',true);
end

function exercisePlacementMovementSaveAndReload(testCase,scaleAxis,corrected)
if nargin < 3, corrected = false; end
% Exercise the actions underlying the mouse callbacks. Only file pickers
% are replaced; exports and session restoration use the production code.
folder = tempname; mkdir(folder);
cleanup = onCleanup(@()cleanupMocks(folder)); %#ok<NASGU>
writeMock(fullfile(folder,'uiputfile.m'),sprintf([ ...
    'function [file,folder] = uiputfile(varargin)\n' ...
    '[folder,name,ext] = fileparts(getappdata(0,''IntrinsicStereoTestFile''));\n' ...
    'file = [name ext];\nend\n']));
writeMock(fullfile(folder,'uigetfile.m'),sprintf([ ...
    'function [file,folder] = uigetfile(varargin)\n' ...
    '[folder,name,ext] = fileparts(getappdata(0,''IntrinsicStereoTestFile''));\n' ...
    'file = [name ext];\nend\n']));
addpath(folder,'-begin');
path = fullfile(folder,'overlay.png');
imwrite(uint8(100*ones(120,256,3)),path);
fig = intrinsic_stereotaxic_gui(path);
cleanupFig = onCleanup(@()delete(fig)); %#ok<NASGU>
set(fig,'Visible','off');
ui = getappdata(fig,'IntrinsicStereoUI');
actions = getappdata(fig,'IntrinsicStereoActions');
points = [20 60;220 60;120 40;120 100;160 20;80 80];
if strcmp(scaleAxis,'y')
    set(ui.orientation,'Value',2);
    callback = get(ui.orientation,'Callback'); callback(ui.orientation,[]);
    % Deliberately different x positions; only y separation sets the scale.
    points(1:2,:) = [50 -40;150 160];
end
for k = 1:size(points,1)
    actions.PlacePoint(points(k,:));
end
state = getappdata(fig,'IntrinsicStereoState');
verifyEqual(testCase,state.targets,[160 20;80 80]);
verifyEqual(testCase,get(ui.save,'Enable'),'on');
rows = get(ui.table,'Data');
verifyEqual(testCase,cell2mat(rows(:,2:3)),[.5 1;-1 -1],'AbsTol',1e-12);
verifyEqual(testCase,cell2mat(rows(:,4:5)),[.5 1;-1 -1],'AbsTol',1e-12);
if strcmp(scaleAxis,'y')
    actions.MoveMarker('scale',2,[999 360]);
    rows = get(ui.table,'Data');
    verifyEqual(testCase,cell2mat(rows(:,2:3)),[.25 .5;-.5 -.5],'AbsTol',1e-12);
    verifyEqual(testCase,cell2mat(rows(:,4:5)),[.25 .5;-.5 -.5],'AbsTol',1e-12);
    actions.MoveMarker('scale',2,[999 160]);
    ax = getappdata(fig,'IntrinsicStereoAxes');
    lines = findobj(ax,'Type','line');
    count = 0;
    for k = 1:numel(lines)
        if isappdata(lines(k),'StereoDrag')
            descriptor = getappdata(lines(k),'StereoDrag');
            if strcmp(descriptor.kind,'scale')
                count = count+1;
                verifyEqual(testCase,diff(get(lines(k),'YData')),0);
                verifyGreaterThan(testCase,abs(diff(get(lines(k),'XData'))),0);
            end
        end
    end
    verifyEqual(testCase,count,2);
end

% Move bregma by +20 pixels in y; AP increases by 0.5 mm for BOTH targets.
actions.MoveMarker('bregma',1,[120 60]);
rows = get(ui.table,'Data');
verifyEqual(testCase,cell2mat(rows(:,2:3)),[1 1;-.5 -1],'AbsTol',1e-12);
event = struct('Indices',[1 1],'NewData','Visual target');
callback = get(ui.table,'CellEditCallback'); callback(ui.table,event);
expectedRig = [1 1;-.5 -1]; expectedStereo = expectedRig;
if corrected
    set(ui.width,'Value',2);
    callback = get(ui.width,'Callback'); callback(ui.width,[]);
    expectedRig = [.6 .6;-.3 -.6];
    set(ui.surgeryBL,'String','2');
    callback = get(ui.surgeryBL,'Callback'); callback(ui.surgeryBL,[]);
    rows = get(ui.table,'Data');
    verifyEqual(testCase,cell2mat(rows(:,2:3)),expectedRig,'AbsTol',1e-12);
    verifyEqual(testCase,cell2mat(rows(:,4:5)),[2 .6;-1 -.6],'AbsTol',1e-12);
    callback = get(ui.coverslipAP,'Callback'); callback(ui.coverslipAP,[]);
    actions.PlacePoint([120 -20]); actions.PlacePoint([120 80]);
    expectedStereo = [1.6 .6;-.8 -.6];
    rows = get(ui.table,'Data');
    verifyEqual(testCase,cell2mat(rows(:,4:5)),expectedStereo,'AbsTol',1e-12);
    actions.MoveMarker('coverslipAP',2,[120 180]);
    rows = get(ui.table,'Data');
    verifyEqual(testCase,cell2mat(rows(:,2:3)),expectedRig,'AbsTol',1e-12);
    verifyEqual(testCase,cell2mat(rows(:,4:5)),[1.3 .6;-.65 -.6],'AbsTol',1e-12);
    % Clearing the surgery reference leaves the coverslip reference at 100%.
    set(ui.surgeryBL,'String','');
    callback = get(ui.surgeryBL,'Callback'); callback(ui.surgeryBL,[]);
    rows = get(ui.table,'Data');
    verifyEqual(testCase,cell2mat(rows(:,4:5)),expectedRig,'AbsTol',1e-12);
    set(ui.surgeryBL,'String','2'); callback(ui.surgeryBL,[]);
    actions.MoveMarker('coverslipAP',2,[120 80]);
    % 1-mm stereo AP arrow is 25 px; the unchanged ML arrow is 66.67 px.
    ax = getappdata(fig,'IntrinsicStereoAxes');
    arrows = findobj(ax,'Type','quiver');
    lengths = arrayfun(@(h)hypot(h.UData,h.VData),arrows);
    verifyEqual(testCase,sort(lengths(:)),[25;1000/15],'AbsTol',1e-12);
end
output = fullfile(folder,'roundtrip.mat');
setappdata(0,'IntrinsicStereoTestFile',output);
callback = get(ui.save,'Callback'); callback(ui.save,[]);
verifyTrue(testCase,isfile(output));
verifyTrue(testCase,isfile(fullfile(folder,'roundtrip.csv')));
verifyTrue(testCase,isfile(fullfile(folder,'roundtrip_annotated.png')));
saved = load(output,'session');
verifyEqual(testCase,saved.session.version,3);
verifyEqual(testCase,saved.session.calibration.scale_axis,scaleAxis);
verifyEqual(testCase,saved.session.targets.Rig_AP_mm,expectedRig(:,1),'AbsTol',1e-12);
verifyEqual(testCase,saved.session.targets.Rig_ML_mm,expectedRig(:,2),'AbsTol',1e-12);
verifyEqual(testCase,saved.session.targets.Stereotaxic_AP_mm,expectedStereo(:,1),'AbsTol',1e-12);
verifyEqual(testCase,saved.session.targets.Stereotaxic_ML_mm,expectedStereo(:,2),'AbsTol',1e-12);
verifyEqual(testCase,saved.session.targets.Name,{'Visual target';'T2'});
csv = readtable(fullfile(folder,'roundtrip.csv'));
verifyEqual(testCase,csv.Rig_AP_mm,expectedRig(:,1),'AbsTol',1e-12);
verifyEqual(testCase,csv.Stereotaxic_AP_mm,expectedStereo(:,1),'AbsTol',1e-12);
callback = get(ui.load,'Callback'); callback(ui.load,[]);
restored = getappdata(fig,'IntrinsicStereoState');
verifyEqual(testCase,restored.bregma,[120 60]);
verifyEqual(testCase,restored.targets,[160 20;80 80]);
verifyFalse(testCase,restored.dirty);
verifyEqual(testCase,restored.scaleAxis,scaleAxis);
verifyEqual(testCase,get(ui.orientation,'Value'),1+strcmp(scaleAxis,'y'));
verifyEqual(testCase,restored.scalePositions,points(1:2,1+strcmp(scaleAxis,'y'))');
if corrected
    verifyEqual(testCase,restored.surgeryBLMm,2);
    verifyEqual(testCase,restored.coverslipAP,[120 -20;120 80]);
    verifyEqual(testCase,restored.widthMm,3);
    verifyEqual(testCase,saved.session.calibration.ap_weights_bl_coverslip,[.5 .5]);
    verifyEqual(testCase,get(ui.width,'Value'),2);
end

if strcmp(scaleAxis,'x') && ~corrected
    % Both earlier file versions load with the optional correction disabled.
    for version = [1 2]
        session = saved.session; session.version = version;
        session.state = rmfield(session.state,{'surgeryBLMm','coverslipAP'});
        if version == 1
            session.state.scaleX = session.state.scalePositions;
            session.state = rmfield(session.state,{'scalePositions','scaleAxis'});
        end
        legacy = fullfile(folder,sprintf('legacy%d.mat',version));
        save(legacy,'session');
        setappdata(0,'IntrinsicStereoTestFile',legacy);
        callback = get(ui.load,'Callback'); callback(ui.load,[]);
        restored = getappdata(fig,'IntrinsicStereoState');
        verifyEqual(testCase,restored.scaleAxis,'x');
        verifyEqual(testCase,restored.scalePositions,[20 220]);
        verifyEmpty(testCase,restored.surgeryBLMm);
        verifyEmpty(testCase,restored.coverslipAP);
    end
end

% Switching the boundary direction invalidates only scale, not marked points.
set(ui.orientation,'Value',1+strcmp(scaleAxis,'x'));
callback = get(ui.orientation,'Callback'); callback(ui.orientation,[]);
switched = getappdata(fig,'IntrinsicStereoState');
verifyTrue(testCase,all(isnan(switched.scalePositions)));
verifyEqual(testCase,switched.targets,restored.targets);
verifyEqual(testCase,switched.bregma,restored.bregma);
verifyEqual(testCase,switched.lambda,restored.lambda);
verifyEqual(testCase,get(ui.save,'Enable'),'off');
if strcmp(scaleAxis,'x')
    actions.PlacePoint([50 -40]); actions.PlacePoint([150 160]);
else
    actions.PlacePoint([20 60]); actions.PlacePoint([220 60]);
end
switched = getappdata(fig,'IntrinsicStereoState');
verifyEqual(testCase,switched.mode,'target');
rows = get(ui.table,'Data');
verifyEqual(testCase,cell2mat(rows(:,2:3)),expectedRig,'AbsTol',1e-12);
verifyEqual(testCase,cell2mat(rows(:,4:5)),expectedStereo,'AbsTol',1e-12);
if corrected
    callback = get(ui.clearAP,'Callback'); callback(ui.clearAP,[]);
    state = getappdata(fig,'IntrinsicStereoState');
    verifyEmpty(testCase,state.coverslipAP);
    rows = get(ui.table,'Data');
    verifyEqual(testCase,cell2mat(rows(:,4:5)),[2 .6;-1 -.6],'AbsTol',1e-12);
end
end

function writeMock(path,contents)
fid = fopen(path,'w');
assert(fid >= 0,'Cannot write test mock.');
cleanup = onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',contents);
end

function cleanupMocks(folder)
if contains([path pathsep],[folder pathsep]), rmpath(folder); end
for key = {'IntrinsicStereoTestFile'}
    if isappdata(0,key{1}), rmappdata(0,key{1}); end
end
assert(startsWith(folder,tempdir),'Test cleanup must stay within tempdir.');
if isfolder(folder), rmdir(folder,'s'); end
end
