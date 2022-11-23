function [spkts,spkwv,lfp,lfpts,lfpfq,meth]=processWB(wb,ts,Fs,spkfq,lfpfq,spkbuff,n_std,rawspk,resamp,saveupsamp,poswav,lowFilt) 
%PROCESSWB - Extract LFP and spikes from wideband data
%
%Input:
%wb - Nx1 wideband data
%ts - Nx1 timestamps corresponding to wideband data. **Must be in seconds!!
%Fs - scalar. Sampling frequency
%spkfq - Spike Fq filter. Scalar defines high pass; 2x1 defines bandpass
%spkbuff - 2x1. Buffer before/after each spike in # samples
%n_std - scalar. Standard deviation of negative threshold
%lfpfq - resample freq for lfp
%rawspk - bool. True exports unfiltered spike waveforms
%resamp - bool. True resamples the waveforms with splines
%saveupsamp - bool. True saves the upsampled spike waveforms
%poswav - bool. True detects positive spikes in addition to negative spikes
%lowFilt - Filter object from 'designfilt'. Anti-aliasing low-pass filter 
%   used before downsampling data for LFP.
%   Default: 10th-order Butterworth with Half Frequency of transition band 
%       at Nyquist of 'lfpfq'
%
%Output:
%spkts - Sx1 array. Spike timestamps
%spkwv - SxW matrix. Spike waveforms; W=sum(spkbuff)
%lfp - Nx1 array. Low-pass filtered and downsampled local field potential
%lfpts - Nx1 array.  LFP timestamps
%lfpfq - scalar. Frequency of resampled LFP
%meth - struct. Contains information about filters and data processing used
%   by 'processWB'
%
%Jon Rueckemann and Yoni Browning 2018

vers='2.0';

if nargin<12
    lowFilt=[]; 
end

%Default parameters
mingap=10; %Minimum gap in seconds between separate LFP epochs

if isempty(spkfq)||isempty(spkbuff)
    spkts=[];
    spkwv=[];
    sfilter=[];
else
    spktot=sum(spkbuff); %spike window is sum of look behind and look ahead
    spkwind=spktot+spkbuff(1)+1; %expanded waveform for looking for minimum
    
    %Filter wideband signal to extract spikes
    if numel(spkfq)==1
        [b,a]=butter(4,spkfq/(Fs/2),'high');
    else
        [b,a]=butter(4,spkfq/(Fs/2));
    end
    spkfilt=filtfilt(b,a,wb);
    sfilter=struct('Style','Butterworth','Order',4,...
        'Numerator',b,'Denominator',a);
    
    %Identify candidate spikes
    spkidx=find([0; diff(spkfilt<-n_std*std(spkfilt))>0]); %Threshold 
    if poswav %Detect positive spike waveforms
        posspkidx=find([0; diff(spkfilt>n_std*std(spkfilt))>0]); %Threshold
        %posidx=[ones(size(spkidx)); -ones(size(posspkidx))];
        posidx=[false(size(spkidx)); true(size(posspkidx))];
        spkidx=[spkidx; posspkidx];
    else
        posidx=false(size(spkidx));
    end
    
    spkidx(spkidx<spkwind|spkidx>numel(wb)-spkwind)=[]; %Drop start/end 
    spkwv=repmat(-spkbuff(1):spktot,numel(spkidx),1); %Indices span spkwind
    spkwv=repmat(spkidx,1,spkwind)+spkwv; %Indices for each waveform
    if rawspk %Index into continuous data
        spkwv=wb(spkwv);
        spkwv=spkwv-repmat(mean(spkwv,2),1,spkwind); %Zero-mean wb waveform
    else
        spkwv=spkfilt(spkwv);
    end
    
    spkwv(posidx,:)=-spkwv(posidx,:);%Temporarily flip negative waveforms
    %spkwv=diag(posidx)*spkwv; %Temporarily flip negative waveforms
    
    
    %Find minima in (upsampled) waveforms
    if resamp
        [Ts,T]=ndgrid(linspace(1,spkwind,spkwind*4),1:spkwind);%4X upsample
        upsampleBasis=sinc(Ts-T); %sinc function basis for upsampling
        upspkwv=(upsampleBasis*spkwv')'; %upsample waveforms
        [~,I]=min(upspkwv(:,spkbuff(1)*4+1:end-spkbuff(2)*4),[],2);%valley
        wvidx=repmat(-spkbuff(1)*4:spkbuff(2)*4,numel(I),1);
        wvidx=repmat(I+spkbuff(1)*4,1,spktot*4+1)+wvidx; %column indices
        wvidx=sub2ind(size(upspkwv),cumsum(ones(size(wvidx)),1),wvidx);%idx
        spkwv=upspkwv(wvidx); %select waveforms from matrix
        if ~saveupsamp %Downsample spikes
            spkwv=spkwv(:,1:4:end);
        end
        spkts=ts(round(spkidx+0.25*I-1));
    else
        [~,I]=min(spkwv(:,spkbuff(1)+1:end-spkbuff(2)),[],2); %valley
        wvidx=repmat(-spkbuff(1):spkbuff(2),numel(I),1);
        wvidx=repmat(I+spkbuff(1),1,spktot+1)+wvidx; %column indices
        wvidx=sub2ind(size(spkwv),cumsum(ones(size(wvidx)),1),wvidx); %idx
        spkwv=spkwv(wvidx); %select waveforms from matrix
        spkts=ts(spkidx+I-1);
    end
    
    spkwv(posidx,:)=-spkwv(posidx,:);%Reverse temporarily flipped waveforms
    %spkwv=diag(posidx)*spkwv; %Reverse temporarily flipped waveforms
    
    %Toss spikes with identical timestamps
    spkwv=spkwv([false;diff(spkts)>0],:);
    spkts=spkts([false;diff(spkts)>0]);
end


%Decimate wideband signal to create LFP
if isempty(lfpfq)
    lfpts=[];
    lfp=[];
elseif Fs==lfpfq
    lfpts=ts;
    lfp=wb;
else
    dsfactor=round(Fs./lfpfq);
    lfpfq=Fs./dsfactor; %Fix when Fs is not an integer multiple of lfpfq
    
    %Design anti-aliasing low-pass filter
    if isempty(lowFilt)
        lowFilt=designfilt('lowpassiir','FilterOrder',10,...
            'HalfPowerFrequency',lfpfq/2,'SampleRate',Fs);
    end
    
    %Separate LFP into epochs and downsample data
    epochidx=cumsum([1; diff(ts(:))>mingap]);
    [lfpts,lfp]=deal(cell(max(epochidx),1));
    for m=1:max(epochidx)
        curlfp=wb(epochidx==m);
        curts=ts(epochidx==m);
        
        %Regularly sample data
        newts=min(curts):1/Fs:max(curts); %#ok<*AGROW> 
        newlfp=interp1(curts,curlfp,newts,'linear','extrap');
                
        %Resample timestamps
        lfpts{m}=newts(1:dsfactor:end);
        
        clear curlfp
        clear curts
        clear newts
        
        %Filter and downsample data. 
        if lowFilt.isfir
            gd=unique(lowts.grpdelay);
            assert(numel(gd)==1,'FIR filter will induce phase distortion');
            
            newlfp=[newlfp zeros(1,gdelay)]; %compensate for group delay
            newlfp=filter(lowFilt,newlfp,2); %forward filter
            lfp{m}=newlfp(1,gdelay+1:dsfactor:end); %downsample after delay            
        else
            newlfp=[newlfp(Fs:-1:1) newlfp newlfp(end:-1:(end-Fs+1))];
                %pad with one second on either side of epoch
            newlfp=filtfilt(lowFilt,newlfp); %bidirectional filter
            lfp{m}=newlfp(Fs+1:dsfactor:end-Fs); %remove pad and downsample
            clear newlfp
        end
    end
    
    %Concatenate downsampled data
    lfpts=cell2mat(lfpts);
    lfp=cell2mat(lfp);
end

%Store processing method
meth=struct('Function','processWB','Version',vers,'LFPFilter',lowFilt,...
    'LFPfq',lfpfq,'SpikeFilter',sfilter,'Spikefq',spkfq,...
    'SpikeBuffer',spkbuff,'N_std',n_std,'SavePositiveWaveforms',poswav,...
    'DateProcessed',date);
end