function [NEX,savelocation]=mat2NEX5(foldername,savelocation,filetag,datatype,idxmeth,adjtime)
%MAT2NEX5 - Convert folder of MAT files to NEX5
%
%Inputs:
% foldername - Parent directory for data
% savelocation - Destination for saving NEX5
% filetag - Name of saved NEX5 file
% datatype - Specify data type to be saved: 'lfp','spike', or 'all'
% idxmeth - Specify method of creating numerical channel indexing in NEX5:
%               'CSC' - number by CSC channel, i.e. x from CSCx
%               'ordinal' - index in order of the file processed
%adjtime - Boolean; Subtract first timestamp of the wideband data
%
%
%Output:
% NEX - NEX5 struct
% savelocation - Destination for saving NEX5
%
%Yoni Browning and Jon Rueckemann 2018

%#ok<*ST2NM>

if nargin<1
    foldername=uigetdir;
end
if nargin<2
    savelocation=uigetdir;
end
if nargin<3
    filetag=[];
end
if nargin<4
    datatype='spike';
end
if nargin<5
    idxmeth='ordinal';
end
if nargin<6
    adjtime=true;
end

%Determine which data to add to NEX struct
switch datatype
    case 'lfp'
        getlfp=true;
        getspk=false;
    case {'spike','spk'}
        getlfp=false;
        getspk=true;
    case {'all','both'}
        getlfp=true;
        getspk=true;
    otherwise
        error('Invalid data type selected for export to NEX.');
end


%List of valid files in directory
files=dir(foldername);
filelist={files.name};
filelist=fullfile(foldername,filelist);
filelist=filelist(~[files.isdir] & contains(filelist,'_ex.mat'));

for m=1:numel(filelist)
    matobj=matfile(filelist{m});
    disp(filelist{m});
    firstts=matobj.firstts;
    params=matobj.params;
    Fs=params.rawFS;
    spkbuff=params.spkbuff;
    
    if m==1
        %Create NEX5 struct
        NEX=nexCreateFileData(Fs);
        NEX.tbeg=firstts; %Save true beginning of recording
        foldername=matobj.foldername;
    else
        NEX.tbeg=min(firstts,NEX.tbeg); %Save true beginning of recording
        assert(Fs==NEX.freq,['The sampling rate of the current file '...
            'does not match others in this folder.']);
        assert(strcmp(foldername,matobj.foldername),['The origin folder'...
            ' of the current NCS does not match others in this folder.']);
    end
    
    extractMethod=matobj.extractMethod;
    chname=matobj.chname;
    
    switch lower(idxmeth)
        case 'csc'
            if ~(contains(lower(chname),'eye')||contains(lower(chname),'gr'))
                tempidx=strsplit(lower(chname),'csc');
                assert(~isempty(tempidx{end})&&... %empty token
                    ~isempty(str2num(tempidx{end})),... %non-numerical token
                    'Channel name does not have a valid CSC name forma: CSCx');
                idx=str2num(tempidx{end});
            else
                idx = nan;
            end
        otherwise
            idx=m;
    end
    
    %Add data to NEX struct
    if getlfp
        switch extractMethod
            case {'lfp','all','both'}
                lfpts=matobj.lfpts;
                lfpfq=matobj.lfpfq;
                lfp=matobj.lfp;
                if adjtime
                    lfpts=lfpts-firstts;
                end
                NEX=nexAddContinuous(NEX,lfpts(1),lfpfq,lfp,chname);
            otherwise
                NEX=nexAddContinuous(NEX,firstts,Fs,0,chname);
        end
    end
    if getspk & ~isnan(idx);
        switch extractMethod
            case {'spike','spk','all','both'}
                spkts=matobj.spkts;
                spkwv=matobj.spkwv;
                if adjtime
                    spkts=spkts-firstts;
                end
                NEX=nexAddNeuron(NEX,spkts,chname,idx,0);
                NEX=nexAddWaveform(NEX,Fs,spkts,spkwv',chname,...
                    spkbuff(1),sum(spkbuff)+1,idx,0);
            otherwise
                NEX=nexAddNeuron(NEX,firstts,chname,idx,0);
                NEX=nexAddWaveform(NEX,Fs,firstts,...
                    zeros(1,sum(spkbuff)+1)',chname,spkbuff(1),...
                    sum(spkbuff)+1,idx,0);
        end
    end
end

%Save NEX
if ~isempty(savelocation)
    if isempty(filetag)
        [~,filetag]=fileparts(foldername); %use origin folder name
    end
    writeNex5File(NEX,fullfile(savelocation,[filetag '.nex5']));
    fid=fopen(fullfile(savelocation ,[filetag '_NEX5timeoffset.txt']),'w');
    if adjtime
        fprintf(fid,'%f',firstts);
    else
        fprintf(fid,'%f',0);
    end
    fclose(fid);
end
end