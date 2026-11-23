function [coordinates,calibration,rigCoordinates] = intrinsic_stereotaxic_coordinates( ...
    points,bregma,lambda,scalePositions,coverslipWidthMm,mlSign,scaleAxis, ...
    surgeryBLMm,coverslipAP)
%INTRINSIC_STEREOTAXIC_COORDINATES Convert image pixels to AP/ML in mm.
%   [AP_ML,CAL] = INTRINSIC_STEREOTAXIC_COORDINATES(POINTS,B,L,BOUNDS,5,1,'x')
%   POINTS is N-by-2 [x y] in original image pixels (x right, y down).
%   SCALEPOSITIONS contains two boundary positions in original image pixels.
%   SCALEAXIS='x' (default): x positions of left/right vertical boundaries.
%   SCALEAXIS='y': y positions of top/bottom horizontal boundaries.
%   Their separation represents the full COVERSLIPWIDTHMM (default 5).
%   Bregma is the origin. AP+ points from lambda to bregma. With MLSIGN=1,
%   ML+ is 90 degrees clockwise from AP+ on the displayed image; MLSIGN=-1
%   reverses it. Choose the sign so that ML+ points to the animal's right.
%   Optional eighth argument SURGERYBLMM is the bregma-lambda distance (mm)
%   measured during surgery with the skull level. Empty (default) disables
%   correction. When supplied, only AP is multiplied by surgery/image B-L;
%   ML retains the coverslip scale. This assumes uniform AP foreshortening
%   with a reliable ML scale; it does not recover a 3-D skull orientation.
%   Optional ninth argument COVERSLIPAP is 2-by-2 [x y] AP diameter endpoints.
%   Their separation projected onto the B-L axis gives a second AP factor:
%   true coverslip diameter / apparent AP diameter. If both references are
%   supplied, their factors are averaged with weights 0.5 / 0.5. One reference
%   alone has weight 1; neither gives factor 1.
%   First output is the corrected stereotaxic [AP ML] (level skull assumed).
%   Third output is the uncorrected rig [AP ML]. Both use bregma as origin and
%   the same B-L axes; rig here is not a manipulator's hardware coordinate.

if nargin < 5, coverslipWidthMm = 5; end
if nargin < 6, mlSign = 1; end
if nargin < 7, scaleAxis = 'x'; end
if nargin < 8, surgeryBLMm = []; end
if nargin < 9 || isempty(coverslipAP), coverslipAP = zeros(0,2); end
scaleAxis = validatestring(scaleAxis,{'x','y'},mfilename,'scaleAxis');
validateattributes(points,{'numeric'},{'real','finite','2d','ncols',2}, ...
    mfilename,'points');
validateattributes(bregma,{'numeric'},{'real','finite','vector','numel',2}, ...
    mfilename,'bregma');
validateattributes(lambda,{'numeric'},{'real','finite','vector','numel',2}, ...
    mfilename,'lambda');
validateattributes(scalePositions,{'numeric'},{'real','finite','vector','numel',2}, ...
    mfilename,'scalePositions');
validateattributes(coverslipWidthMm,{'numeric'}, ...
    {'real','finite','scalar','positive'},mfilename,'coverslipWidthMm');
validateattributes(mlSign,{'numeric'},{'real','finite','scalar'}, ...
    mfilename,'mlSign');
if ~ismember(mlSign,[-1 1])
    error('intrinsicStereo:InvalidMLSign','mlSign must be +1 or -1.');
end
if ~isempty(surgeryBLMm)
    validateattributes(surgeryBLMm,{'numeric'}, ...
        {'real','finite','scalar','positive'},mfilename,'surgeryBLMm');
end
if ~isempty(coverslipAP)
    validateattributes(coverslipAP,{'numeric'}, ...
        {'real','finite','size',[2 2]},mfilename,'coverslipAP');
end

bregma = double(bregma(:)');
lambda = double(lambda(:)');
widthPx = abs(diff(double(scalePositions(:))));
axisLengthPx = norm(bregma-lambda);
if widthPx < 1
    error('intrinsicStereo:InvalidScale', ...
        'The coverslip boundaries must be at least one pixel apart.');
end
if axisLengthPx < 1
    error('intrinsicStereo:InvalidLandmarks', ...
        'Bregma and lambda must be at least one pixel apart.');
end

apUnit = (bregma-lambda)/axisLengthPx;
mlUnit = double(mlSign)*[-apUnit(2) apUnit(1)];
mmPerPixel = double(coverslipWidthMm)/widthPx;
imageBLMm = axisLengthPx*mmPerPixel;
factors = [1 1]; % B-L reference, coverslip AP reference.
if ~isempty(surgeryBLMm)
    factors(1) = double(surgeryBLMm)/imageBLMm;
end
coverAPPx = [];
if ~isempty(coverslipAP)
    coverAPPx = abs(diff(double(coverslipAP),1,1)*apUnit(:));
    if coverAPPx < 1
        error('intrinsicStereo:InvalidCoverslipAP', ...
            'Coverslip AP endpoints must span at least one pixel along the AP axis.');
    end
    factors(2) = double(coverslipWidthMm)/(coverAPPx*mmPerPixel);
end
weights = double([~isempty(surgeryBLMm) ~isempty(coverslipAP)]);
apCorrectionFactor = 1;
if any(weights)
    weights = weights/sum(weights);
    apCorrectionFactor = sum(factors.*weights);
end
rigCoordinates = (double(points)-bregma)*[apUnit(:) mlUnit(:)]*mmPerPixel;
coordinates = rigCoordinates;
coordinates(:,1) = coordinates(:,1)*apCorrectionFactor;
calibration = struct('mm_per_pixel',mmPerPixel, ...
    'pixels_per_mm',1/mmPerPixel,'coverslip_width_px',widthPx, ...
    'coverslip_width_mm',double(coverslipWidthMm), ...
    'scale_axis',scaleAxis,'scale_positions_px',double(scalePositions(:)'), ...
    'bregma_lambda_distance_mm',imageBLMm, ...
    'surgery_bregma_lambda_mm',double(surgeryBLMm), ...
    'coverslip_ap_xy_px',double(coverslipAP), ...
    'coverslip_ap_distance_px',coverAPPx, ...
    'coverslip_ap_distance_mm',coverAPPx*mmPerPixel, ...
    'bregma_lambda_ap_factor',factors(1),'coverslip_ap_factor',factors(2), ...
    'ap_weights_bl_coverslip',weights, ...
    'corrected_bregma_lambda_distance_mm',imageBLMm*apCorrectionFactor, ...
    'ap_correction_factor',apCorrectionFactor, ...
    'ap_mm_per_pixel',mmPerPixel*apCorrectionFactor,'ml_mm_per_pixel',mmPerPixel, ...
    'bregma_xy_px',bregma,'lambda_xy_px',lambda, ...
    'ap_unit_xy',apUnit,'ml_unit_xy',mlUnit,'ml_sign',double(mlSign), ...
    'convention','AP+ anterior; ML+ animal right (verify image handedness)', ...
    'pixel_convention','Original image pixels: x right, y down, first center (1,1)');
end
