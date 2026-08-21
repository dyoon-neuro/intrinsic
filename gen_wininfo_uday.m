function wininfo = gen_wininfo_uday(result)
% xRes = 1024; 
% yRes = 768;
% xRes = 1280; % Dell 170S monitors
% yRes = 1024;
Bcol = 128;
availableScreens = Screen('Screens');
if isfield(result,'screenNumber')
    screenNumber = result.screenNumber;
    validateattributes(screenNumber,{'numeric'}, {'scalar','integer'});
    if ~ismember(screenNumber,availableScreens)
        error(['Requested Psychtoolbox screenNumber %d is not available. ' ...
            'Available screen numbers: %s.'],screenNumber, ...
            mat2str(availableScreens));
    end
else
    screenNumber = max(availableScreens);
end
blI = BlackIndex(screenNumber);
whI = WhiteIndex(screenNumber);

blI = BlackIndex(screenNumber);
whI = WhiteIndex(screenNumber);

if isfield(result, 'background') 
    switch result.background
        case 'w'
            Bcol = whI;
        case 'g'
            Bcol = (blI+whI)/2;
        case 'k'
            Bcol = blI;
        otherwise
            error('background color was misspecified')
    end
else
    Bcol = (blI+whI)/2;
end

if isfield(result, 'backgroundcontrast') 
    Bcol = blI + (whI-blI)*result.backgroundcontrast;
end

scaleby = 0.5;
xRes = RectWidth(Screen('Rect', screenNumber))*scaleby;
yRes = RectHeight(Screen('Rect', screenNumber))*scaleby;
fitSize = [xRes,yRes];
%
AssertOpenGL; % Psychtoolbox function

Screen('Preference', 'VBLTimestampingMode', -1);

if isfield(result,'skipsynctests')
    validateattributes(result.skipsynctests,{'numeric','logical'}, ...
        {'scalar'});
    wininfo.skipSync = double(logical(result.skipsynctests));
else
    wininfo.skipSync = 0;
end

if wininfo.skipSync
    warning(['Psychtoolbox synchronization tests are disabled. ' ...
        'Stimulus timing must be independently verified before ' ...
        'using these data for timing-critical conclusions.']);
end

Screen('Preference','SkipSyncTests',wininfo.skipSync);

PsychImaging('PrepareConfiguration');

PsychImaging('AddTask', 'General', 'UsePanelFitter', fitSize, 'Aspect');

% Center small framebuffer inside big framebuffer. Scale it up to
% maximum size while preserving aspect ration of the original
% framebuffer:

[w,windowRect] = PsychImaging('OpenWindow',screenNumber,Bcol); %Screen('OpenWindow',screenNumber);
% HideCursor()

[sw,sh] = Screen('DisplaySize',screenNumber);
if ~(sw==197 && sh==148)
    disp('check monitor size rig 2')
end
screenWidth = sw/10;
screenHeight = sh/10;

% VertScreenDimDeg = atand(result.VertScreenSize/result.DScreen); % in visual degrees
% PixperDeg = yRes/VertScreenDimDeg;
DiagPix = sqrt(xRes^2+yRes^2);
Diagcm = sqrt(screenWidth^2+screenHeight^2);
DiagDeg = 2*atand((Diagcm/2)/result.DScreen); % viewing angle: 116.2 degrees in rig computer (on 200106)
DPixperDeg = DiagPix / DiagDeg;
XDeg = 2*atand((screenWidth/2)/result.DScreen); % viewing angle: 102.8 degrees in rig computer (on 200106)
XPixperDeg = xRes / XDeg;
YDeg = 2*atand((screenHeight/2)/result.DScreen); % viewing angle: 90.2 degrees in rig computer (on 200106)
YPixperDeg = yRes / YDeg;
try
    xposStim = result.position(:,1);
    yposStim = result.position(:,2);
catch
    xposStim = NaN;
    yposStim = NaN;
end
frameRate = Screen('FrameRate',screenNumber);
ifi = Screen('GetFlipInterval',w);


wininfo.xRes = xRes;
wininfo.yRes = yRes;
wininfo.w = w;
wininfo.windowRect = windowRect;
wininfo.screenWidthcm = screenWidth;
wininfo.screenHeightcm = screenHeight;
wininfo.DiagPix = DiagPix;
wininfo.Diagcm = Diagcm;
wininfo.DiagDeg = DiagDeg;
wininfo.DPixperDeg = DPixperDeg;
wininfo.XDeg = XDeg;
wininfo.XPixperDeg = XPixperDeg;
wininfo.YDeg = YDeg;
wininfo.YPixperDeg = YPixperDeg;
wininfo.PixperDeg = YPixperDeg;
wininfo.xposStim = xposStim;
wininfo.yposStim = yposStim;
wininfo.frameRate = frameRate;
wininfo.ifi = ifi;
wininfo.Bcol = Bcol;
wininfo.blI = blI;
wininfo.whI = whI;
wininfo.grI = (blI + whI)/2;
wininfo.screenNumber = screenNumber;

wininfo.scaleby= scaleby;
bg = ones(yRes,xRes)*Bcol;
wininfo.BG = Screen('MakeTexture', wininfo.w, bg);
end
