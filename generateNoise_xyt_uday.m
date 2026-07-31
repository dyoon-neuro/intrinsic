function moviedata=generateNoise_xyt_uday(maxSpatFreq,maxTempFreq,duration,wininfo,result,movtype,binarize)
%%% generates white noise movies with limited spatial and temporal
%%% frequency, via inverse fourier transform
%%% now with more options ...
%%% binarize (0/1)  = convert grayscale to binary, for higher contrast
%%% movie type = allows noise patches, moving noise bars, etc.
%%% movietype 1 = standard contrast modulated noise
%%% movietype 1.5 = random contrast modulated noise
%%% movietype 2 = full-field step function of white noise
%%% movietype 3 = moving bar of white noise
%%% movietype 4 = alternating patches of white noise along x-axis
%%% movietype 5 = alternating patches of white noise along y-axis

% Some legacy stimulus/Bpod code may previously have called
% rand('state',...), which puts MATLAB into legacy RNG mode. Switch back to
% the modern default generator before applying a time-dependent seed.
rng('default');
rng('shuffle');

%%% stimulus/display parameters

if ~exist('binarize','var') |  isempty(binarize)
    binarize=0;
end
if ~exist('movtype','var') | isempty(movtype)
    movtype=0;
end

cmod=1; cmodrnd = 1.5; step=2; bar = 3; oscbar = 3.5; Xpatches=4; Ypatches=5; %%%% movietypes

imsize = 102;                %% size in pixels
ximsize = wininfo.xRes;
yimsize = wininfo.yRes;
framerate = wininfo.frameRate;             %% Hz
imageMag = result.image_mag;                 %% magnification that movie will be played at
%%%contrastSigma =0.5;   %0.5      %% one-sigma value for contrast
contrastSigma = result.contrast;
%disp(['contrast used: ', num2str(result.contrast)])
%% derived parameters

degperpix = (1/wininfo.PixperDeg)*imageMag;
nframes = round(framerate*duration);

%% frequency intervals for FFT
nyq_pix = 0.5;
nyq_deg=nyq_pix/degperpix;
freqInt_deg = nyq_deg / (0.5*imsize);
freqInt_pix = nyq_pix / (0.5*imsize);
nyq = framerate/2;
tempFreq_int = nyq/(0.5*nframes);


%% cutoffs in terms of frequency intervals

tempCutoff = round(maxTempFreq/tempFreq_int);
maxFreq_pix = maxSpatFreq*degperpix;
spatCutoff = round(maxFreq_pix / freqInt_pix);


%%% generate frequency spectrum (invFFT)
alpha=-1;
offset=3;
range_mult =1;
%for noise that extends past cutoff parameter (i.e. if cutoff = 1sigma)
%range_mult=2;
spaceRange = (imsize/2 - range_mult*spatCutoff : imsize/2 + range_mult*spatCutoff)+1;
tempRange =   (nframes /2 - range_mult*tempCutoff : nframes/2 + range_mult*tempCutoff)+1;
[x y z] = meshgrid(-range_mult*spatCutoff:range_mult*spatCutoff,-range_mult*spatCutoff:range_mult*spatCutoff,-range_mult*tempCutoff:range_mult*tempCutoff);
%% can put any other function to describe frequency spectrum in here,
%% e.g. gaussian spectrum
% use = exp(-1*((0.5*x.^2/spatCutoff^2) + (0.5*y.^2/spatCutoff^2) + (0.5*z.^2/tempCutoff^2)));
%  use =single(((x.^2 + y.^2)<=(spatCutoff^2))& ((z.^2)<(tempCutoff^2)) );
use =single(((x.^2 + y.^2)<=(spatCutoff^2))& ((z.^2)<(tempCutoff^2)) ).*(sqrt(x.^2 + y.^2 +offset).^alpha);
clear x y z;


%%%
invFFT = zeros(imsize,imsize,nframes,'single');
mu = zeros(size(spaceRange,2), size(spaceRange,2), size(tempRange,2));
sig = ones(size(spaceRange,2), size(spaceRange,2), size(tempRange,2));
invFFT(spaceRange, spaceRange, tempRange) = single(use .* normrnd(mu,sig).*exp(2*pi*i*rand(size(spaceRange,2), size(spaceRange,2), size(tempRange,2))));
clear use;

%% in order to get real values for image, need to make spectrum
%% symmetric
fullspace = -range_mult*spatCutoff:range_mult*spatCutoff; halftemp = 1:range_mult*tempCutoff;
halfspace = 1:range_mult*spatCutoff;
invFFT(imsize/2 + fullspace+1, imsize/2+fullspace+1, nframes/2 + halftemp+1) = ...
    conj(invFFT(imsize/2 - fullspace+1, imsize/2-fullspace+1, nframes/2 - halftemp+1));
invFFT(imsize/2+fullspace+1, imsize/2 + halfspace+1,nframes/2+1) = ...
    conj( invFFT(imsize/2-fullspace+1, imsize/2 - halfspace+1,nframes/2+1));
invFFT(imsize/2+halfspace+1, imsize/2 +1,nframes/2+1) = ...
    conj( invFFT(imsize/2-halfspace+1, imsize/2+1,nframes/2+1));

shiftinvFFT = ifftshift(invFFT);
clear invFFT;

%%% invert FFT and scale it to 0 -255

imraw = real(ifftn(shiftinvFFT));
clear shiftinvFFT;
immean = mean(imraw(:));
immax = std(imraw(:))/contrastSigma;
immin = -1*immax;
imscaled = (imraw - immin-immean) / (immax - immin);
clear imfiltered;
contrast_period =result.contrast_period;
rcontrwin = result.rcontrast_window;


%%% modify movie for different patterns (patches, bars, etc)
if binarize
    imscaled(imscaled<0.5)=0;
    imscaled(imscaled>0.5)=1;
end

if movtype==bar
    barPix=20;
    center = linspace(0-barPix/2,imsize+barPix/2,contrast_period*framerate);
    center=fliplr(center);
    loweredge = center-barPix/2; upperedge=center+barPix/2;
    loweredge(loweredge<1)=1; loweredge(loweredge>imsize)=imsize;
    upperedge(upperedge<1)=1; upperedge(upperedge>imsize)=imsize;
    loweredge = round(loweredge); upperedge=round(upperedge);
end

if movtype==oscbar
    sweepFrames = round(contrast_period*framerate);
    dirflag = result.dirflag;

    if ~dirflag
        % Vertical aperture moving horizontally.
        pixelsPerDeg = wininfo.XPixperDeg/imageMag;
        oscbarPix = max(1,round( ...
            result.aperture_width_deg*pixelsPerDeg));
        center = linspace(0-oscbarPix/2, ...
            imsize+oscbarPix/2,sweepFrames);
    else
        % Horizontal aperture moving vertically.
        pixelsPerDeg = wininfo.YPixperDeg/imageMag;
        oscbarPix = max(1,round( ...
            result.aperture_width_deg*pixelsPerDeg));
        scalef = wininfo.screenHeightcm/wininfo.screenWidthcm;
        center = linspace(0-oscbarPix/2, ...
            scalef*imsize+oscbarPix/2,sweepFrames);
    end

    if result.reverseflag
        center = fliplr(center);
    end

    loweredge = round(center-oscbarPix/2);
    upperedge = round(center+oscbarPix/2);
    loweredge = max(1,min(imsize,loweredge));
    upperedge = max(1,min(imsize,upperedge));
end

for f = 1:nframes
    if movtype == cmod
        imscaled(:,:,f) = 0.5*(imscaled(:,:,f)-0.5).*(1-cos(2*pi*f/(contrast_period*framerate)));

    elseif movtype ==step
        %imscaled(:,:,f) = (imscaled(:,:,f)-.5).*(sin(pi+2*pi*f/(contrast_period*framerate))>0); 
        imscaled(:,:,f) = 0.5*sign(sin(pi+2*pi*f/(contrast_period*framerate))); 

    elseif movtype ==bar        
        le = loweredge(mod(f-1,contrast_period*framerate)+1);
        ue = upperedge(mod(f-1,contrast_period*framerate)+1);

        imscaled(1:le,:,f)=0.5; imscaled(ue:imsize,:,f)=0.5;

    elseif movtype ==oscbar
        sweepIndex = mod(f-1,sweepFrames)+1;
        le = loweredge(sweepIndex);
        ue = upperedge(sweepIndex);
        
        if(dirflag)
            imscaled(1:le,:,f)=0.5; imscaled(ue:imsize,:,f)=0.5;
        else
            imscaled(:,1:le,f)=0.5; imscaled(:,ue:imsize,f)=0.5;
        end
    elseif movtype==Xpatches | movtype==Ypatches
        if movtype==Xpatches
       % wx = 0.25;  xpos = 0.25; ypos = 0.5;   
       wx = 0.2; xpos = 0.4; ypos=0.5;
        widthpix = 2*round(wx*imsize/2);  yposPix = ypos*imsize;
        if mod((f-1)/(contrast_period*framerate),1)<0.5
            xposPix = xpos*imsize;
        else 
            xposPix=(1-xpos)*imsize
        end
        elseif movtype==Ypatches
          % wx = 0.25;  xpos = 0.5; ypos = 0.35;  
           wx = 0.2;  xpos = 0.5; ypos = 0.4;   
        widthpix = 2*round(wx*imsize/2);  xposPix = xpos*imsize;
        if mod((f-1)/(contrast_period*framerate),1)<0.5
            yposPix = ypos*imsize;
        else 
            yposPix=(1-ypos)*imsize
        end
        
        end
        xposPix=round(xposPix); yposPix=round(yposPix);
        imscaled(1:(xposPix-widthpix/2),:,f)=0.5; imscaled(xposPix+widthpix/2:imsize,:,f)=0.5; 
        imscaled(:,1:(yposPix-widthpix/2),f)=0.5; imscaled(:,(yposPix+widthpix/2):imsize,f)=0.5;
    end
        
    %imscaled(:,:,f) = (imscaled(:,:,f)-.5).*(contrast(mod(f-1,1800)+1));
end
%%% Added below on 10/4/19 for step-like random contrast modulation
if movtype == cmodrnd
    tempframe = zeros(size(imscaled));
    temp = repmat(rand(1,ceil(nframes/rcontrwin)),[rcontrwin,1]);
    temp = temp(:);
    for f=1:nframes
        tempframe(:,:,f) = temp(f)*ones(size(imscaled,1),size(imscaled,2));
    end
    imscaled = 0.5*(imscaled-0.5).*tempframe;
end
%%%

if movtype ==cmod | movtype == cmodrnd | movtype==step
imscaled = imscaled+0.5;
end


moviedata = uint8(floor(imscaled(1:imsize,1:imsize,:)*255)+1);

