% rf_verse.m
% Jamie Near, McGill University 2020.
%
% USAGE:
% RF_out=rf_verse(RF_in,alpha);
% 
% DESCRIPTION:
% Turn a standard slice-selective RF pulse into a gradient modulated pulse 
% using variable-rate selective excitation (VERSE).  
% 
% INPUTS:
% RF_in     = Input RF pulse definition structure.  The input RF pulse must
%             already have a gradient waveform (in must be an Nx4 array).  
% alpha     = Alpha is the unitless modulation function by which the RF 
%             amplitude, time-step function, and gradient will all be 
%             scaled.
% 
% OUTPUTS:
% RF_out    = Output rf waveform following the addition of gradient 
%             waveform.

function RF_out=rf_verse(RF_in,alpha);

if ~isstruct(RF_in)
    error('ERROR:  the input RF pulse must be in structure format.  Try using rf_readwaveform to convert it!  Aborting.  ');
end

newWaveform=RF_in.waveform;

%Check if the input RF pulse already has a gradient. 
if size(newWaveform,2)<4
    error('ERROR:  Input waveform must already have a gradient waveform!');
end

%Check that the input alpha waveform has the correct dimensions:
if (alpha) ~= size(newWaveform,1)
    if size(alpha') ~= size(newWaveform,1);
        error('ERROR:  Gradient waveform does not match the length of the input RF pulse waveform!!  ABORTING!!');
    end
    alpha=alpha';
end

%Now apply the VERSE the modulation: 
newWaveform(:,2)=newWaveform(:,2).*alpha;
newWaveform(:,3)=newWaveform(:,3)./alpha;
newWaveform(:,4)=newWaveform(:,4).*alpha;

%Verify that the new time-step function has no negative values:
minduration=min(newWaveform(:,3));
if minduration<0
    error('ERROR:  Resulting duration cannot be negative');
end

%Now we're going to resample all of the waveforms back onto a linear time 
%waveform.
t_nonlin=cumsum(newWaveform(:,3));
t_lin=linspace(t_nonlin(1),t_nonlin(end),length(t_nonlin));
rf(:,1)=interp1(t_nonlin,newWaveform(:,1),t_lin);
rf(:,2)=interp1(t_nonlin,newWaveform(:,2),t_lin);
rf(:,3)=ones(length(newWaveform(:,1)),1);
rf(:,4)=interp1(t_nonlin,newWaveform(:,4),t_lin);

%Check if the pulse is phase modulated.  If it is not, then we can
%determine the time-w1 product of the pulse quite simply.  If it is phase
%modulated (adiabatic, etc) then the determination of the time-w1 product 
%will need to me more interactive.
a=(round(rf(:,1))==180)|(round(rf(:,1))==0);

if sum(a)<length(rf(:,1))
    isPhsMod=true;
else
    isPhsMod=false;
end

%If there are any phase discontinuities in the phase function that are
%equal to a 360 degree jump we can remove these.  This will make it easier
%for rf_resample to do it's job later on:
jumps=diff(rf(:,1));
jumpsAbs=(abs(jumps)>355 & abs(jumps)<365);  %Assume jumps within this range are exactly = 360 degrees.
jumpIndex=find(jumpsAbs);
for n=1:length(jumpIndex)
    rf(jumpIndex(n)+1:end,1)=rf(jumpIndex(n)+1:end,1)-(360*(jumps(jumpIndex(n))/abs(jumps(jumpIndex(n)))));
end

%Now re-calculate the time-b1 product:
%scale amplitude function so that maximum value is 1:
rf(:,2)=rf(:,2)./max(rf(:,2));

Tp=0.005;  %assume a 5 ms rf pulse;
if ~isPhsMod
    %The pulse is not phase modulated, so we can calculate the w1max:
    %find the B1 max of the pulse in [kHz]:
    if isstr(RF_in.type)
        if RF_in.type=='exc'
            flipCyc=0.25; %90 degrees is 0.25 cycles;
        elseif RF_in.type=='ref'
            flipCyc=0.5;  %180 degress is 0.5 cycles;
        elseif RF_in.type=='inv'
            flipCyc=0.5;  %180 degrees is 0.5 cycles;
        end
    elseif isnumeric(RF_in.type) %assume that a flip angle (in degrees) was given
        flipCyc=RF_in.type/360;
    end
    intRF=sum(rf(:,2).*((-2*(rf(:,1)>179))+1))/length(rf(:,2));
    if intRF~=0
        w1max=flipCyc/(intRF*Tp); %w1max is in [Hz]
    else
        w1max=0;
    end
    tw1=Tp*w1max;
else
    %The pulse is phase modulated, so we will need to run some test to find
    %out the w1max;  To do this, we can plot Mz as a function of w1 and
    %find the value of w1 that results in the desired flip angle.
    [mv,sc]=bes(rf,Tp*1000,'b',f0/1000,0,5,40000);
    plot(sc,mv(3,:));
    xlabel('w1 (kHz)');
    ylabel('mz');
    w1max=input('Input desired w1max in kHz (for 5.00 ms pulse):  ');
    w1max=w1max*1000; %convert w1max to [Hz]
    tw1=Tp*w1max;
end


%save the final result
RF_out=RF_in;
RF_out.waveform=rf;
RF_out.tw1=tw1;