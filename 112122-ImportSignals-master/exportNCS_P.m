function [NEX] = exportNCS_P(foldername,savelocation,tarlocation,tarNCS,extension,exMethod,exportNEX,datatype,idxmeth)
%EXPORTNCS - Process all Neuralynx cheetah data (*.NCS) from a given folder
%into MAT files.  Spike detection and downsample continuous data from
%wideband signals.  Supports parallel processing.

%Inputs:
% foldername - Parent directory for data
% savelocation - Destination for saving data to mat files
% tarlocation - Folder for zipped processed files.  All data from *.NCS
%               files in this folder (and NEX5) will be zipped together.
%               Default: Empty, which does not produce a *.tar file
% tarNCS - Boolean; include a *.tar file contain *.NCS within larger *.tar
% extension - Extension for which recording data to include (empty, 0001,
%               etc.). Default is empty, only takes files with no extension
% exMethod - Specify data type to be extracted: 'lfp',spike', or 'all'
% exportNEX - Boolean; Create a NEX5, an Offline Sorter compatible file
% datatype - data type saved to NEX5; 'spike','lfp','all'. Default:'spike'
% idxmeth - channel indexing method in NEX5 struct. Default: 'ordinal'.
%
%Output:
% *Update Note: Params no longer exported because Fs can change between
% files. YB 7/16/18
% NEX - NEX5 struct
% 
%*NOTE: Assumes a parallel pool will be automatically assigned to parfor
%
%Jon Rueckemann and Yoni Browning 2018

%Default values
if nargin<1||isempty(foldername)
    foldername=uigetdir([],'Select folder containing *.NCS files.');
end
if nargin<2||isempty(savelocation)
    savelocation=uigetdir([],'Select folder to save processed data.');
end
if nargin<3||isempty(tarlocation)
    tarlocation=[];
end
if nargin<4||isempty(tarNCS)
    tarNCS=true;
end
if nargin<5||isempty(extension)
    extension='';
elseif isnumeric(extension)
    tempext=num2str(extension);
    extension='0000';
    extension(end-numel(tempext)+1:end)=tempext;
end
if nargin<6||isempty(exMethod)
    exMethod='all';
end
if nargin<7||isempty(exportNEX)
    exportNEX=true;
end
if nargin<8||isempty(datatype)
    datatype='spike'; %NEX5 export option, only export spike data
end
if nargin<9||isempty(idxmeth)
    idxmeth='ordinal';
end

%Default variables - hard-coded for consistency across experiments
spkfq=400; %Highpass frequency for spike detection
lfpfqtarget=1000; %Downsample LFP frequency to 1000Hz
spkbuff=[8 24]; %Timestamps before and after the peak of the detected spike
n_std=3.5; %Standard deviations above mean amplitude for spike detection
rawspk=false; %Use raw data instead of filtered data for spikes - false
resamp=true; %Resample spike waveforms to find the local minimum - true
saveupsamp=false; %Saved waveforms are upsampled - false
posspk=false; %Detect positive deflection spikes - false

%List of valid files in directory
files=dir(foldername);
filelist={files.name};
filelist=filelist(~[files.isdir] & [files.bytes]>16384 &...
    contains(filelist,'.ncs') & contains(filelist,extension));
if strcmp(extension,'') %Remove files with '_' when not using extensions
    filelist=filelist(~contains(filelist,'_0'));
end
if isempty(filelist)
    return;
end
filelist=fullfile(foldername,filelist);

if isempty(savelocation)
    warning(['No location specified for save files;' ...
        'only first file will be processed.'])
end

%Iterate through valid files
exfiles=cell(size(filelist));
parfor ii = 1:length(filelist)
    filename=filelist{ii};
    disp(filename);
    [~,chname]=fileparts(filename);
    [ts,wb,ncsFS,header]=importCSC_tossBadPackets(filename);
	
    %Ensure that sampling rate is constant for each packet
    assert(all(diff(ncsFS)==0),'Sampling rate is inconstant in NCS');
    Fs=ncsFS(1);
    
    %Parameter struct for save file
    params=struct('rawFS',Fs,'spkfq',spkfq,'lfpfq',lfpfqtarget,...
        'spkbuff',spkbuff,'n_std',n_std,'rawspk',rawspk,'resamp',resamp,...
        'saveupsamp',saveupsamp);
    
    %Only process CSC data for spikes; not for other signals (e.g. eye)
    if ~contains(chname,'CSC')
        extractMethod='lfp';
    else
        extractMethod=exMethod;
    end
    
    %Specify data to extract
    switch extractMethod
        case 'lfp' %Forego processing spikes
            curspkfq=[];
            curspkbuff=[];
            curlfpfq=lfpfqtarget;
        case {'spike','spk'} %Forego processing LFP
            curspkfq=spkfq;
            curspkbuff=spkbuff;
            curlfpfq=[];
        case {'all','both'} %Process spikes and LFP
            curspkfq=spkfq;
            curspkbuff=spkbuff;
            curlfpfq=lfpfqtarget;
    end
    
    %Extract data from wideband signal
    [spkts,spkwv,lfp,lfpts,lfpfq,meth]=processWB(wb(:),ts(:),Fs,curspkfq,...
        curlfpfq,curspkbuff,n_std,rawspk,resamp,saveupsamp,posspk); 
    
    %Preserve earliest timestamp
    firstts=ts(1);
    
    %Save data for each NCS to MAT file
    exfiles{ii}=fullfile(savelocation, [chname '_ex.mat']);
    parforsave(exfiles{ii},foldername,filename,chname,extractMethod,...
        params,spkts,spkwv,lfp,lfpts,lfpfq,firstts,meth,header);
end

[~,simplefolder]=fileparts(foldername);
if ~strcmp(extension,'')
    simplefolder=[simplefolder '_' extension]; %Add extension suffix
end

if exportNEX
    try
        [NEX,nexpath]=mat2NEX5(savelocation,savelocation,simplefolder,...
            datatype,idxmeth);
        exfiles=[exfiles nexpath];
    catch
        NEX = [];
    end
else
    NEX=[];
end
if ~isempty(tarlocation)
    [~,simplefolder]=fileparts(foldername);
    if tarNCS
        tarpath=[tarlocation '\' simplefolder '_NCS.tar'];
        tar(tarpath,filelist);
        exfiles=[exfiles tarpath];
    end
    tar([tarlocation '\' simplefolder '.tar'],exfiles);
    if tarNCS
        delete(tarpath); %Delete NCS tar
    end
end
end

function []=parforsave(savefile,foldername,filename,chname,...
    extractMethod,params,spkts,spkwv,lfp,lfpts,lfpfq,firstts,meth,header)
save(savefile,'foldername','filename','chname','extractMethod',...
    'params','spkts','spkwv','lfp','lfpts','lfpfq','firstts','meth',...
    'header','-v7.3');
end
