function [ts,signal,Fs,header]=importCSC_tossBadPackets(filename,opt)
%Import Neuralynx CSC data for spike sorting.  Drops acquired packets that
%contain an impossible number of samples within a packet or occur outside
%the possible recording session.
%
%filename - name of CSC file to import
%opt - struct populating options
%   %extractMode - Neuralynx import extract option (1=all data)
%   %exModeVector - Neuralynx import extract modifier (ignored when mode=1)
%       %Note: See comments in Nlx2MatCSC for details.
%   %maxpacket - maximum size of legitimate packet (default: 512)
%   %maxjump - maximum span of time within one recording session (seconds)
%   %fixinverted - invert signals based on indicator in CSC header
%
%Output:
%ts - timestamps in seconds
%signal - imported raw Neuralynx CSC signal (e.g. wideband)
%Fs - sampling frequency of signal
%header - NLX file header
%
%*NOTE: 24 hour recordings will result in erroneous data deletion using 
%default settings.  Change maxjump field in "opt".  See Lines 48-52, 86-89
%
%Jon Rueckemann and Yoni Browning, 2017

if nargin<1
    [filename,dirname]=uigetfile;
    filename=[dirname '\' filename];
end

%Default values for import options
if nargin>1 && isfield(opt,'extractMode')
    extractMode=opt.extractMode;
else
    extractMode=1;
end
if nargin>1 && isfield(opt,'extractModeVector')
    %Specify subset of file based on extractMode method.
    exModeVector=opt.exModeVector;
else
    exModeVector=[]; %ignored when extracting all data: extractMode=1
end
if nargin>1 && isfield(opt,'maxpacket')
    %Maximum packet size; larger packets are errors and will be dropped
    maxpacket=opt.maxpacket;
else
    maxpacket=512;
end
if nargin>1 && isfield(opt,'maxjump')
    %Max time difference from the start of the recording
    maxjump=opt.maxjump*1000000; %1000000us/sec
else
    maxjump=24*3600*1000000; %24hr * 3600sec/hr * 1000000us/sec
end
if nargin>1 && isfield(opts,'fixInverted')
    fixinverted=opts.fixInverted;
else
    fixinverted=1;
end


%Load CSC data
fieldFlag=ones(1,5); %Field selection settings:
    %(1)-Timestamps, (2)-Channel Numbers, (3)-Sample Frequency,
    %(4)-Number of Valid Samples, (5)-Samples
    
if ~isunix % windows machine
    [pkts,chNum,Fs,NV,data,header]=...
        Nlx2MatCSC(filename,fieldFlag,1,extractMode,exModeVector);
else % anything else
      [pkts,chNum,Fs,NV,data,header]=...
        Nlx2MatCSC_v3(filename,fieldFlag,1,extractMode,exModeVector); 
end

assert(all(diff(chNum)==0),['Bad CSC data: More than one channel '...
    'detected in CSC.']);

%Convert AD counts to millivolts
mVidx=contains(header,'-ADBitVolts','IgnoreCase',true);
assert(sum(mVidx)==1,['CSC header is not properly formatted for AD '...
    'conversion to mV']);
idx=isstrprop(header{mVidx},'digit');
mVscalar=str2double(header{mVidx}(find(idx,1,'first'):find(idx,1,'last')));
data=data.*mVscalar;

%Flip inverted CSC data
if fixinverted
    invertstatus=header(contains(header,'InputInverted'));
    if contains(invertstatus,'True')
        data=-data;
    end
end

%Check that the first packet timestamp is legitimate
assert(pkts(1)>0,'Bad CSC data: First timestamp not a positive number.');

%Find packets that are too large to be possible
bigpacket=NV>maxpacket;

%Find packets that occur at impossible times: big jumps or negative numbers
bigjump=abs(pkts-pkts(1))>maxjump | pkts<0;

%Drop packets that cannot be valid
drop=bigpacket | bigjump;
pkts(drop)=[];
Fs(drop)=[];
data(:,drop)=[];
if any(drop)
    warning([num2str(sum(drop)) ' packets were dropped due to ' ...
        'acquisition error.']);
end

%Confirm packet time is monotonically increasing
assert(all(diff(pkts)>0),['Bad CSC data: Timestamps are not '...
    'monotonically increasing']);

%Constitute timestamps
dt=1000000./Fs; %Neuralynx timestamps are in microseconds
ts=arrayfun(@(x,y,z) ((0:x-1)*y+z)',NV,dt,pkts,'uni',0);
ts=cell2mat(ts');
ts=ts./1000000; %Convert timestamps to seconds

%Confirm reconstructed time is monotonically increasing
assert(all(diff(ts)>0),['Bad CSC data: Timestamps are not '...
    'monotonically increasing']);

%Sample valid data
signal=cellfun(@(x,y) x(1:y),num2cell(data,1),num2cell(NV),'uni',0);
signal=cell2mat(signal');
end
