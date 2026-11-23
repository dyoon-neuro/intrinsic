function fig = intrinsic_stereotaxic_gui(imagePath)
%INTRINSIC_STEREOTAXIC_GUI Mark an intrinsic overlay and read AP/ML in mm.
%   INTRINSIC_STEREOTAXIC_GUI opens an image picker.
%   INTRINSIC_STEREOTAXIC_GUI('E:\intrinsic\session\overlay.png') opens a file.
%   FIG = INTRINSIC_STEREOTAXIC_GUI(...) returns the nonblocking GUI figure.
%
%   1. Choose left/right (vertical lines) or top/bottom (horizontal lines),
%      then click both boundaries spanning the FULL coverslip diameter.
%      Select the coverslip diameter: 5 mm (default) or 3 mm.
%   2. Click bregma, then lambda. Bregma is (AP,ML)=(0,0).
%   3. Check the ML+ arrow points to the animal's RIGHT; flip if necessary.
%   4. Click targets. Drag any marker or boundary to adjust it. Rename targets
%      in the table. Changing landmarks/scale recalculates every target.
%   5. Optionally enter the B-L distance (mm) measured with the skull level
%      during surgery. AP alone is rescaled to match it; blank disables this.
%      Optionally mark both ends of the coverslip AP diameter. When both
%      references exist, their AP factors are averaged (50% B-L, 50% cover).
%      With one reference, use it at 100%; with neither, apply no correction.
%   6. Save CSV + MAT + PNG. Load the MAT to resume editing later.
%   Rig and stereotaxic coordinates are both displayed and saved, in mm.
%   Rig = before AP correction; stereotaxic = after AP correction, assuming
%   a level skull. Both share the bregma origin and B-L-based AP/ML axes.
%
%   AP+ is lambda -> bregma (anterior), AP- posterior; ML+ animal right,
%   ML- animal left after verifying image handedness. Coordinates use original
%   pixels, independent of display resizing, zoom, and pan. Use the toolbar
%   for zoom/pan; choose a placement button again to leave navigation mode.
%   View margin permits estimated boundaries/landmarks outside a cropped image.
%
%   The optional B-L correction assumes uniform AP foreshortening and a
%   reliable coverslip-derived ML scale. Use the full coverslip diameter.
%   Perspective, ML tilt, and lens distortion are not corrected. No DV is
%   inferred; a single B-L distance cannot recover full 3-D skull orientation.
%   Tested with MATLAB R2025b; no Image Processing Toolbox is required.

fig = gobjects(0);
if nargin < 1 || isempty(imagePath)
    [file,folder] = uigetfile(imageFilter(),'Select intrinsic overlay image');
    if isequal(file,0), return; end
    imagePath = fullfile(folder,file);
end
[imageData,imageAlpha] = readImage(imagePath);
s = blankState(char(imagePath));
selectedRow = [];
drag = [];
overlays = gobjects(0);

fig = figure('Name','Intrinsic overlay -> stereotaxic AP / ML', ...
    'NumberTitle','off','Color',[0.12 0.14 0.17], ...
    'Units','normalized','Position',[0.06 0.06 0.88 0.86], ...
    'MenuBar','none','ToolBar','figure', ...
    'WindowButtonDownFcn',@mouseDown,'WindowButtonMotionFcn',@mouseMove, ...
    'WindowButtonUpFcn',@mouseUp,'WindowKeyPressFcn',@keyPress, ...
    'CloseRequestFcn',@closeApp);
ax = axes('Parent',fig,'Units','normalized','Position',[0.045 0.07 0.61 0.86], ...
    'Color',[0.22 0.24 0.27],'XColor',[0.85 0.85 0.85], ...
    'YColor',[0.85 0.85 0.85],'YDir','reverse','DataAspectRatio',[1 1 1]);
im = image(ax,'CData',imageData,'XData',[1 size(imageData,2)], ...
    'YData',[1 size(imageData,1)],'HitTest','off');
if ~isempty(imageAlpha), set(im,'AlphaData',imageAlpha); end
hold(ax,'on');
xlabel(ax,'Original image x (pixels)');
ylabel(ax,'Original image y (pixels)');
panel = uipanel('Parent',fig,'Units','normalized', ...
    'Position',[0.68 0.025 0.31 0.95],'Title','Calibration and targets', ...
    'FontSize',11,'BackgroundColor',[0.96 0.96 0.96]);
ui.open = button('Open image...',[.03 .945 .45 .037],@openImage);
ui.load = button('Load session MAT...',[.51 .945 .46 .037],@loadSession);
ui.path = label('',[.03 .902 .94 .037]);
set(ui.path,'FontSize',8);
label('Coverslip diameter (mm)',[.03 .861 .65 .027]);
ui.width = uicontrol(panel,'Style','popupmenu','Units','normalized', ...
    'Position',[.73 .861 .24 .033],'FontSize',10,'BackgroundColor','white', ...
    'String',{'5 mm','3 mm'},'UserData',[5 3],'Callback',@widthChanged);
label('Surgery B-L (mm; blank = off)',[.03 .819 .70 .027]);
ui.surgeryBL = editBox('',[.75 .819 .22 .033],@surgeryBLChanged);
set(ui.surgeryBL,'TooltipString', ...
    'Bregma-lambda distance measured with the skull level. Corrects AP only.');
ui.orientation = uicontrol(panel,'Style','popupmenu','Units','normalized', ...
    'Position',[.03 .777 .94 .033],'FontSize',10,'BackgroundColor','white', ...
    'String',{'Left / right: vertical lines','Top / bottom: horizontal lines'}, ...
    'TooltipString','Choose which pair spans the full coverslip diameter.', ...
    'Callback',@orientationChanged);
ui.scale = button('1. Set two boundaries',[.03 .732 .94 .039], ...
    @(~,~)setMode('scale1'));
ui.bregma = button('2. Mark bregma',[.03 .687 .45 .039], ...
    @(~,~)setMode('bregma'));
ui.lambda = button('3. Mark lambda',[.51 .687 .46 .039], ...
    @(~,~)setMode('lambda'));
ui.coverslipAP = button('Set coverslip AP ends (optional)',[.03 .642 .73 .039], ...
    @(~,~)setMode('coverslipAP1'));
ui.clearAP = button('Clear AP',[.78 .642 .19 .039],@clearCoverslipAP);
ui.target = button('4. Add targets',[.03 .597 .45 .039], ...
    @(~,~)setMode('target'));
ui.flip = button('Flip ML (+/-)',[.51 .597 .46 .039],@flipML);
ui.info = label('',[.03 .454 .94 .135]);
set(ui.info,'FontSize',9);
label('View margin (%)',[.03 .413 .54 .027]);
ui.margin = editBox('15',[.59 .413 .16 .033],@marginChanged);
ui.fit = button('Fit',[.78 .413 .19 .033],@(~,~)fitView());
ui.status = label('',[.03 .351 .94 .055]);
set(ui.status,'ForegroundColor',[.05 .25 .55],'FontWeight','bold');
label('Target AP / ML coordinates (mm)',[.03 .319 .94 .026]);
ui.table = uitable('Parent',panel,'Units','normalized', ...
    'Position',[.03 .185 .94 .129], ...
    'ColumnName',{'Name','Rig AP','Rig ML','Stereo AP','Stereo ML'}, ...
    'ColumnEditable',[true false false false false], ...
    'ColumnFormat',{'char','numeric','numeric','numeric','numeric'}, ...
    'ColumnWidth',{75 68 68 80 80},'RowName',[],'FontSize',9, ...
    'CellSelectionCallback',@tableSelected,'CellEditCallback',@renameTarget);
ui.delete = button('Delete selected',[.03 .140 .45 .036],@deleteSelected);
ui.undo = button('Remove last',[.51 .140 .46 .036],@removeLast);
ui.save = button('Save CSV + MAT + PNG...',[.03 .091 .94 .041],@saveSession);
ui.help = label(sprintf(['Rig: uncorrected AP. Stereo: AP corrected; ML same.\n' ...
    'For AP correction, use the ML diameter for base scale.\n' ...
    'Drag markers / lines. Verify ML+ points to animal RIGHT.']),[.03 .008 .94 .075]);
set(ui.help,'FontSize',8);
setappdata(fig,'IntrinsicStereoUI',ui);
setappdata(fig,'IntrinsicStereoAxes',ax);
% The same actions are used by mouse callbacks and programmatic callers.
setappdata(fig,'IntrinsicStereoActions', ...
    struct('PlacePoint',@placePoint,'MoveMarker',@moveMarker));
fitView();
refresh();

    function h = button(caption,position,callback)
        h = uicontrol(panel,'Style','pushbutton','String',caption, ...
            'Units','normalized','Position',position,'FontSize',10, ...
            'Callback',callback);
    end

    function h = label(caption,position)
        h = uicontrol(panel,'Style','text','String',caption, ...
            'Units','normalized','Position',position,'FontSize',10, ...
            'HorizontalAlignment','left','BackgroundColor',[.96 .96 .96]);
    end

    function h = editBox(value,position,callback)
        h = uicontrol(panel,'Style','edit','String',value, ...
            'Units','normalized','Position',position,'FontSize',10, ...
            'BackgroundColor','white','Callback',callback);
    end

    function setMode(mode)
        zoom(fig,'off'); pan(fig,'off'); rotate3d(fig,'off');
        s.mode = mode;
        drag = [];
        refresh();
    end

    function orientationChanged(~,~)
        axesNames = 'xy';
        newAxis = axesNames(get(ui.orientation,'Value'));
        if strcmp(newAxis,s.scaleAxis), return; end
        s.scaleAxis = newAxis;
        % Re-mark only the scale; preserve all landmarks and target pixels.
        s.scalePositions = [NaN NaN];
        s.dirty = true;
        setMode('scale1');
    end

    function fitView()
        margin = s.marginPercent/100*max(size(imageData,1),size(imageData,2));
        set(ax,'XLim',[.5-margin size(imageData,2)+.5+margin], ...
            'YLim',[.5-margin size(imageData,1)+.5+margin], ...
            'YDir','reverse','DataAspectRatio',[1 1 1]);
    end

    function [xy,inside] = pointerXY()
        cp = get(ax,'CurrentPoint');
        xy = cp(1,1:2);
        xl = xlim(ax); yl = ylim(ax);
        inside = all(isfinite(xy)) && xy(1) >= xl(1) && xy(1) <= xl(2) ...
            && xy(2) >= yl(1) && xy(2) <= yl(2);
        hit = hittest(fig);
        inside = inside && (isequal(hit,ax) || isequal(ancestor(hit,'axes'),ax));
    end

    function mouseDown(~,~)
        z = zoom(fig); p = pan(fig); r = rotate3d(fig);
        if strcmp(z.Enable,'on') || strcmp(p.Enable,'on') || strcmp(r.Enable,'on')
            return;
        end
        if ~strcmp(get(fig,'SelectionType'),'normal'), return; end
        [xy,inside] = pointerXY();
        if ~inside, return; end
        hit = hittest(fig);
        if isgraphics(hit) && isappdata(hit,'StereoDrag')
            drag = getappdata(hit,'StereoDrag');
            if strcmp(drag.kind,'target'), selectedRow = drag.index; end
            return;
        end
        placePoint(xy);
    end

    function placePoint(xy)
        validateattributes(xy,{'numeric'},{'real','finite','size',[1 2]});
        switch s.mode
            case 'scale1'
                s.scalePositions(1) = xy(1+strcmp(s.scaleAxis,'y'));
                s.mode = 'scale2';
            case 'scale2'
                s.scalePositions(2) = xy(1+strcmp(s.scaleAxis,'y'));
                if abs(diff(s.scalePositions)) < 1
                    s.scalePositions(2) = NaN;
                else
                    resumeMarking();
                end
            case 'coverslipAP1'
                s.coverslipAP = xy;
                s.mode = 'coverslipAP2';
            case 'coverslipAP2'
                s.coverslipAP(2,:) = xy;
                resumeMarking();
            case 'bregma'
                s.bregma = xy;
                s.mode = 'lambda';
            case 'lambda'
                s.lambda = xy;
                if norm(s.bregma-s.lambda) >= 1, s.mode = 'target'; end
            case 'target'
                if ~isCalibrated(), return; end
                s.targets(end+1,:) = xy;
                s.names{end+1,1} = sprintf('T%d',s.nextTargetId);
                s.nextTargetId = s.nextTargetId+1;
                selectedRow = size(s.targets,1);
            otherwise
                return;
        end
        s.dirty = true;
        refresh();
    end

    function resumeMarking()
        if ~all(isfinite(s.scalePositions))
            s.mode = 'scale1';
        elseif ~all(isfinite(s.bregma))
            s.mode = 'bregma';
        elseif ~all(isfinite(s.lambda))
            s.mode = 'lambda';
        else
            s.mode = 'target';
        end
    end

    function clearCoverslipAP(~,~)
        s.coverslipAP = zeros(0,2); s.dirty = true;
        resumeMarking(); setMode(s.mode);
    end

    function mouseMove(~,~)
        if isempty(drag), return; end
        cp = get(ax,'CurrentPoint'); xy = cp(1,1:2);
        if any(~isfinite(xy)), return; end
        moveMarker(drag.kind,drag.index,xy);
        drawnow limitrate;
    end

    function moveMarker(kind,index,xy)
        validateattributes(xy,{'numeric'},{'real','finite','size',[1 2]});
        switch kind
            case 'scale', s.scalePositions(index) = xy(1+strcmp(s.scaleAxis,'y'));
            case 'bregma', s.bregma = xy;
            case 'lambda', s.lambda = xy;
            case 'target', s.targets(index,:) = xy;
            case 'coverslipAP', s.coverslipAP(index,:) = xy;
            otherwise, error('Unknown marker type: %s',kind);
        end
        s.dirty = true;
        refresh();
    end

    function mouseUp(~,~)
        drag = [];
    end

    function keyPress(~,event)
        if strcmp(event.Key,'escape')
            drag = [];
            s.mode = 'idle';
            refresh();
        end
    end

    function widthChanged(~,~)
        sizes = get(ui.width,'UserData');
        s.widthMm = sizes(get(ui.width,'Value'));
        s.dirty = true; refresh();
    end

    function surgeryBLChanged(~,~)
        entry = strtrim(get(ui.surgeryBL,'String'));
        if isempty(entry)
            value = [];
        else
            value = str2double(entry);
        end
        if ~isempty(value) && (~isfinite(value) || value <= 0)
            set(ui.surgeryBL,'String',num2str(s.surgeryBLMm));
            errordlg('Enter a positive B-L distance in mm, or leave blank.', ...
                'Invalid surgery B-L distance');
            return;
        end
        s.surgeryBLMm = value; s.dirty = true; refresh();
    end

    function marginChanged(~,~)
        value = str2double(get(ui.margin,'String'));
        if ~isfinite(value) || value < 0 || value > 300
            set(ui.margin,'String',num2str(s.marginPercent));
            errordlg('Enter a view margin from 0 to 300 percent.','Invalid margin');
            return;
        end
        s.marginPercent = value; fitView(); refresh();
    end

    function flipML(~,~)
        s.mlSign = -s.mlSign; s.dirty = true; refresh();
    end

    function tableSelected(~,event)
        if isempty(event.Indices), return; end
        selectedRow = event.Indices(1,1);
        % Do not rebuild the table here: that would interrupt cell editing.
    end

    function renameTarget(~,event)
        row = event.Indices(1);
        name = strtrim(char(string(event.NewData)));
        if isempty(name)
            errordlg('Target name must not be empty.','Invalid target name');
        else
            s.names{row} = name; s.dirty = true;
        end
        refresh();
    end

    function deleteSelected(~,~)
        if isempty(selectedRow) || selectedRow > size(s.targets,1), return; end
        s.targets(selectedRow,:) = []; s.names(selectedRow) = [];
        selectedRow = []; s.dirty = true; refresh();
    end

    function removeLast(~,~)
        if isempty(s.targets), return; end
        selectedRow = size(s.targets,1); deleteSelected();
    end

    function tf = isCalibrated()
        tf = all(isfinite([s.scalePositions s.bregma s.lambda])) ...
            && abs(diff(s.scalePositions)) >= 1 && norm(s.bregma-s.lambda) >= 1;
        if tf && ~isempty(s.coverslipAP)
            apUnit = (s.bregma-s.lambda)/norm(s.bregma-s.lambda);
            tf = size(s.coverslipAP,1) == 2 ...
                && abs(diff(s.coverslipAP,1,1)*apUnit(:)) >= 1;
        end
    end

    function [coords,cal,rig] = convertPoints(points)
        [coords,cal,rig] = intrinsic_stereotaxic_coordinates(points, ...
            s.bregma,s.lambda,s.scalePositions,s.widthMm,s.mlSign, ...
            s.scaleAxis,s.surgeryBLMm,s.coverslipAP);
    end

    function vectors = axisVectors(cal)
        vectors = [cal.ap_unit_xy/cal.ap_mm_per_pixel; ...
            cal.ml_unit_xy/cal.ml_mm_per_pixel];
    end

    function mark = draggable(mark,kind,index)
        set(mark,'HitTest','on','PickableParts','all');
        setappdata(mark,'StereoDrag',struct('kind',kind,'index',index));
        overlays(end+1) = mark;
    end

    function mark = decoration(mark)
        set(mark,'HitTest','off','PickableParts','none');
        overlays(end+1) = mark;
    end

    function refresh()
        delete(overlays(isgraphics(overlays))); overlays = gobjects(0);
        [~,name,ext] = fileparts(s.imagePath);
        set(ui.path,'String',[name ext],'TooltipString',s.imagePath);
        % Keep an older session's custom diameter visible when resuming it.
        sizes = unique([5 3 s.widthMm],'stable');
        set(ui.width,'String',compose('%g mm',sizes),'UserData',sizes, ...
            'Value',find(sizes == s.widthMm,1));
        set(ui.surgeryBL,'String',num2str(s.surgeryBLMm));
        set(ui.margin,'String',num2str(s.marginPercent));
        set(ui.orientation,'Value',1+strcmp(s.scaleAxis,'y'));
        title(ax,[name ext],'Interpreter','none','Color',[.95 .95 .95]);
        % Span a generous range so the boundaries remain draggable when panning.
        span = 100*max(size(imageData,1),size(imageData,2));
        for k = 1:2
            if isfinite(s.scalePositions(k))
                if strcmp(s.scaleAxis,'x')
                    lineX = [s.scalePositions(k) s.scalePositions(k)];
                    lineY = [-span span];
                else
                    lineX = [-span span];
                    lineY = [s.scalePositions(k) s.scalePositions(k)];
                end
                draggable(line(ax,lineX,lineY, ...
                    'Color',[1 .8 .05],'LineWidth',1.8,'LineStyle','--'),'scale',k);
            end
        end
        if all(isfinite(s.scalePositions))
            if strcmp(s.scaleAxis,'x')
                lineX = s.scalePositions; lineY = [1 1]; rotation = 0;
            else
                lineX = [1 1]; lineY = s.scalePositions; rotation = 90;
            end
            decoration(line(ax,lineX,lineY,'Color',[1 .8 .05],'LineWidth',1.5));
            decoration(text(ax,mean(lineX),mean(lineY),sprintf('  %.3g mm  ',s.widthMm), ...
                'Color','k','BackgroundColor',[1 .8 .05],'HorizontalAlignment','center', ...
                'VerticalAlignment','bottom','FontWeight','bold','Clipping','on', ...
                'Rotation',rotation));
        end
        drawLandmark(s.bregma,'Bregma (0,0)',[.2 1 .4],'bregma');
        drawLandmark(s.lambda,'Lambda',[1 .4 1],'lambda');
        for k = 1:size(s.coverslipAP,1)
            xy = s.coverslipAP(k,:);
            draggable(line(ax,xy(1),xy(2),'LineStyle','none','Marker','s', ...
                'MarkerSize',9,'Color',[.4 .85 1],'LineWidth',2),'coverslipAP',k);
            decoration(text(ax,xy(1),xy(2),sprintf('  Cover AP %d',k), ...
                'Color',[.4 .85 1],'FontWeight','bold','Clipping','on'));
        end
        if size(s.coverslipAP,1) == 2
            decoration(line(ax,s.coverslipAP(:,1),s.coverslipAP(:,2), ...
                'Color',[.4 .85 1],'LineStyle','--'));
        end
        coords = nan(size(s.targets));
        rig = coords;
        if isCalibrated()
            [coords,cal,rig] = convertPoints(s.targets);
            decoration(line(ax,[s.bregma(1) s.lambda(1)], ...
                [s.bregma(2) s.lambda(2)],'LineStyle',':','Color',[.7 1 .7]));
            % Each arrow represents 1 mm, including the optional AP correction.
            vectors = axisVectors(cal);
            colors = {[.2 1 .4],[0 .9 1]}; labels = {'Stereo AP+ 1 mm','ML+ 1 mm (R)'};
            for j = 1:2
                decoration(quiver(ax,s.bregma(1),s.bregma(2), ...
                    vectors(j,1),vectors(j,2),0,'Color',colors{j}, ...
                    'LineWidth',1.7,'MaxHeadSize',.35));
                tip = s.bregma+vectors(j,:);
                decoration(text(ax,tip(1),tip(2),['  ' labels{j}], ...
                    'Color',colors{j},'FontWeight','bold','Clipping','on'));
            end
            set(ui.info,'String',sprintf([ ...
                'Base scale: %.6f mm/px\n' ...
                'B-L factor: %.4f (image %.3f mm)\n' ...
                'Coverslip AP factor: %.4f\n' ...
                'Weights B-L / cover: %.0f%% / %.0f%%\n' ...
                'Final AP factor: %.4f (ML unchanged)\n' ...
                'AP+ anterior; ML+ arrow = animal RIGHT'], ...
                cal.mm_per_pixel,cal.bregma_lambda_ap_factor, ...
                cal.bregma_lambda_distance_mm,cal.coverslip_ap_factor, ...
                100*cal.ap_weights_bl_coverslip(1), ...
                100*cal.ap_weights_bl_coverslip(2),cal.ap_correction_factor));
        else
            set(ui.info,'String',sprintf(['Mark boundaries, bregma and lambda.\n' ...
                'Optional cover AP: mark both ends or Clear AP.\n' ...
                'Scale, B-L and projected AP spans must be >= 1 px.\n' ...
                'Use the full coverslip diameter.']));
        end
        for k = 1:size(s.targets,1)
            xy = s.targets(k,:);
            draggable(line(ax,xy(1),xy(2),'LineStyle','none','Marker','o', ...
                'MarkerSize',8,'Color',[1 .65 .1],'MarkerFaceColor',[1 .35 .05], ...
                'LineWidth',1.3),'target',k);
            caption = sprintf(['  %s  Rig AP %+.3f / ML %+.3f\n' ...
                '  Stereo AP %+.3f / ML %+.3f'], ...
                s.names{k},rig(k,1),rig(k,2),coords(k,1),coords(k,2));
            decoration(text(ax,xy(1),xy(2),caption,'Color',[1 .9 .3], ...
                'FontWeight','bold','Interpreter','none','Clipping','on'));
        end
        rows = [s.names num2cell(rig) num2cell(coords)];
        set(ui.table,'Data',rows);
        set(ui.save,'Enable',onOff(isCalibrated()));
        switch s.mode
            case 'scale1'
                if strcmp(s.scaleAxis,'x')
                    message = 'Click a left/right coverslip boundary (vertical line).';
                else
                    message = 'Click a top/bottom coverslip boundary (horizontal line).';
                end
            case 'scale2', message = 'Click the opposite boundary of the full diameter.';
            case 'coverslipAP1', message = 'Click the anterior end of the FULL coverslip AP diameter.';
            case 'coverslipAP2', message = 'Click the posterior end of the FULL coverslip AP diameter.';
            case 'bregma', message = 'Click bregma. This is AP = 0, ML = 0.';
            case 'lambda', message = 'Click lambda (posterior to bregma).';
            case 'target'
                if isCalibrated()
                    message = 'Click targets; drag markers to refine. Check ML+ arrow.';
                else
                    message = 'Complete scale, landmarks and optional AP ends, or Clear AP.';
                end
            otherwise, message = 'Placement paused. Select a marking button to resume.';
        end
        set(ui.status,'String',message);
        % Metadata is available for scripts and reproducible inspection.
        setappdata(fig,'IntrinsicStereoState',s);
    end

    function drawLandmark(xy,caption,color,kind)
        if ~all(isfinite(xy)), return; end
        draggable(line(ax,xy(1),xy(2),'LineStyle','none','Marker','+', ...
            'MarkerSize',14,'Color',color,'LineWidth',2.4),kind,1);
        decoration(text(ax,xy(1),xy(2),['  ' caption],'Color',color, ...
            'FontWeight','bold','VerticalAlignment','bottom','Clipping','on'));
    end

    function okay = canDiscard()
        okay = true;
        if s.dirty
            answer = questdlg('There are unsaved edits. Continue without saving?', ...
                'Unsaved calibration','Discard edits','Cancel','Cancel');
            okay = strcmp(answer,'Discard edits');
        end
    end

    function openImage(~,~)
        [file,folder] = uigetfile(imageFilter(),'Select intrinsic overlay',s.imagePath);
        if isequal(file,0), return; end
        if ~canDiscard(), return; end
        newPath = fullfile(folder,file);
        try
            [data,alpha] = readImage(newPath);
        catch ME
            errordlg(ME.message,'Cannot open image'); return;
        end
        s = blankState(newPath); selectedRow = []; drag = [];
        replaceImage(data,alpha); setMode('scale1');
    end

    function replaceImage(data,alpha)
        imageData = data; imageAlpha = alpha;
        set(im,'CData',data,'XData',[1 size(data,2)],'YData',[1 size(data,1)]);
        if isempty(alpha), set(im,'AlphaData',1); else, set(im,'AlphaData',alpha); end
        fitView();
    end

    function saveSession(~,~)
        if ~isCalibrated(), return; end
        [folder,name] = fileparts(s.imagePath);
        [file,folder] = uiputfile('*.mat','Save calibration and targets', ...
            fullfile(folder,[name '_stereotaxic.mat']));
        if isequal(file,0), return; end
        [~,base] = fileparts(file);
        paths = {fullfile(folder,[base '.mat']),fullfile(folder,[base '.csv']), ...
            fullfile(folder,[base '_annotated.png'])};
        if any(cellfun(@(p)exist(p,'file') == 2,paths))
            answer = questdlg('Replace the existing output files with this name?', ...
                'Existing output','Replace','Cancel','Cancel');
            if ~strcmp(answer,'Replace'), return; end
        end
        [coords,calibration,rig] = convertPoints(s.targets);
        targets = table(s.names,s.targets(:,1),s.targets(:,2), ...
            rig(:,1),rig(:,2),coords(:,1),coords(:,2), ...
            'VariableNames',{'Name','X_px','Y_px','Rig_AP_mm','Rig_ML_mm', ...
            'Stereotaxic_AP_mm','Stereotaxic_ML_mm'});
        session = struct('format','intrinsic_stereotaxic','version',3, ...
            'saved_at',char(datetime('now','Format','yyyy-MM-dd''T''HH:mm:ss')), ...
            'image_path',s.imagePath, ...
            'image_size',[size(imageData,1) size(imageData,2)], ...
            'state',s,'calibration',calibration,'targets',targets);
        session.state.dirty = false;
        try
            save(paths{1},'session');
            writetable(targets,paths{2});
            exportAnnotation(paths{3});
        catch ME
            errordlg(sprintf('Save incomplete; some files may exist.\n%s',ME.message), ...
                'Save failed'); return;
        end
        s.dirty = false; refresh();
        set(ui.status,'String',sprintf('Saved %d targets: %s',height(targets),base));
        fprintf('Saved calibration: %s\nTargets: %s\nAnnotation: %s\n', ...
            paths{1},paths{2},paths{3});
    end

    function exportAnnotation(path)
        % Export a full-image view including all annotations, even after zoom.
        out = figure('Visible','off','Color',[.15 .15 .15], ...
            'Position',[50 50 1100 1000],'InvertHardcopy','off');
        cleanup = onCleanup(@()delete(out));
        copy = copyobj(ax,out);
        set(copy,'Units','normalized','Position',[.08 .09 .86 .83]);
        x = [.5 size(imageData,2)+.5 s.bregma(1) s.lambda(1) ...
            s.targets(:,1)' s.coverslipAP(:,1)'];
        y = [.5 size(imageData,1)+.5 s.bregma(2) s.lambda(2) ...
            s.targets(:,2)' s.coverslipAP(:,2)'];
        if strcmp(s.scaleAxis,'x')
            x = [x s.scalePositions];
        else
            y = [y s.scalePositions];
        end
        [~,cal] = convertPoints(zeros(0,2));
        tips = s.bregma+axisVectors(cal);
        x = [x tips(:,1)']; y = [y tips(:,2)'];
        pad = .08*max(max(x)-min(x),max(y)-min(y));
        set(copy,'XLim',[min(x)-pad max(x)+pad],'YLim',[min(y)-pad max(y)+pad]);
        title(copy,sprintf(['%s\nAP+ anterior | ML+ animal right (user-verified)\n' ...
            'Rig: before AP correction | Stereo: AP x %.4f | B-L / cover weights %.0f%% / %.0f%%'], ...
            get(get(ax,'Title'),'String'),cal.ap_correction_factor, ...
            100*cal.ap_weights_bl_coverslip(1),100*cal.ap_weights_bl_coverslip(2)), ...
            'Interpreter','none');
        print(out,path,'-dpng','-r150');
    end

    function loadSession(~,~)
        [file,folder] = uigetfile('*.mat','Load a saved stereotaxic session');
        if isequal(file,0), return; end
        if ~canDiscard(), return; end
        try
            loaded = load(fullfile(folder,file),'session');
            if ~isfield(loaded,'session') || ~isstruct(loaded.session) ...
                    || ~isscalar(loaded.session) ...
                    || ~isfield(loaded.session,'format') ...
                    || ~strcmp(loaded.session.format,'intrinsic_stereotaxic') ...
                    || ~isfield(loaded.session,'version') ...
                    || ~isscalar(loaded.session.version) ...
                    || ~ismember(loaded.session.version,[1 2 3])
                error('This is not a supported intrinsic stereotaxic session.');
            end
            saved = loaded.session;
            candidate = saved.state;
            if saved.version == 1
                candidate.scalePositions = candidate.scaleX;
                candidate.scaleAxis = 'x';
                candidate = rmfield(candidate,'scaleX');
            end
            if saved.version < 3
                candidate.surgeryBLMm = []; candidate.coverslipAP = zeros(0,2);
            end
            validateState(candidate);
            newPath = saved.image_path;
            if ~isfile(newPath)
                [~,stem,ext] = fileparts(newPath);
                newPath = fullfile(folder,[stem ext]);
            end
            if ~isfile(newPath)
                [imgFile,imgFolder] = uigetfile(imageFilter(), ...
                    'Original image moved: select the SAME original image');
                if isequal(imgFile,0), return; end
                newPath = fullfile(imgFolder,imgFile);
            end
            [data,alpha] = readImage(newPath);
            if ~isequal([size(data,1) size(data,2)],saved.image_size)
                error('Image dimensions differ from the saved calibration.');
            end
            candidate.imagePath = char(newPath); candidate.dirty = false;
            candidate.mode = 'target';
        catch ME
            errordlg(ME.message,'Cannot load session'); return;
        end
        s = candidate; selectedRow = []; drag = [];
        replaceImage(data,alpha); setMode('target');
    end

    function closeApp(~,~)
        if canDiscard(), delete(fig); end
    end
end

function state = blankState(imagePath)
state = struct('imagePath',imagePath,'scalePositions',[NaN NaN],'scaleAxis','x', ...
    'bregma',[NaN NaN],'lambda',[NaN NaN], ...
    'targets',zeros(0,2),'names',{cell(0,1)},'nextTargetId',1, ...
    'widthMm',5,'surgeryBLMm',[],'coverslipAP',zeros(0,2), ...
    'mlSign',1,'marginPercent',15, ...
    'mode','scale1','dirty',false);
end

function filters = imageFilter()
filters = {'*.png;*.tif;*.tiff;*.jpg;*.jpeg;*.bmp','Image files';'*.*','All files'};
end

function [data,alpha] = readImage(path)
[data,map,alpha] = imread(path);
if ~isempty(map), data = ind2rgb(data,map); end
if ismatrix(data), data = repmat(data,1,1,3); end
if ndims(data) ~= 3 || size(data,3) ~= 3
    error('Expected a grayscale, indexed, or RGB image.');
end
if ~isempty(alpha)
    if isinteger(alpha), alpha = double(alpha)/double(intmax(class(alpha))); end
    alpha = double(alpha);
end
end

function value = onOff(tf)
if tf, value = 'on'; else, value = 'off'; end
end

function validateState(s)
required = fieldnames(blankState(''));
if ~isstruct(s) || ~isscalar(s) || ~all(isfield(s,required))
    error('Saved session is missing required fields.');
end
intrinsic_stereotaxic_coordinates(s.targets,s.bregma,s.lambda, ...
    s.scalePositions,s.widthMm,s.mlSign,s.scaleAxis,s.surgeryBLMm,s.coverslipAP);
if ~isequal(size(s.bregma),[1 2]) || ~isequal(size(s.lambda),[1 2]) ...
        || ~isequal(size(s.scalePositions),[1 2]) ...
        || ~ischar(s.scaleAxis) || ~any(strcmp(s.scaleAxis,{'x','y'})) ...
        || ~iscellstr(s.names) || ~isequal(size(s.names),[size(s.targets,1) 1]) ...
        || any(cellfun(@isempty,s.names))
    error('Saved session has invalid landmark or target fields.');
end
validateattributes(s.marginPercent,{'numeric'},{'scalar','finite','>=',0,'<=',300});
validateattributes(s.nextTargetId,{'numeric'},{'scalar','integer','positive','finite'});
end
