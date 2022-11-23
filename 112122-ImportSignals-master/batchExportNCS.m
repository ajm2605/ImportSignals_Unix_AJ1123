function [folderlist,errorfolder]=batchExportNCS(parentfolder,savefolder,tarlocation,tarNCS,extension,exMethod,exportNEX,datatype,idxmeth,runpar)
%BATCHEXPORTNCS - Process all Neuralynx cheetah data (*.NCS) contained in 
%folders within a superordinate parent folder, and export data with a
%similar folder structure to the save destination.  
%Spike detection and downsample continuous data from wideband signals.
%
%Inputs:
% parentfolder - Parent directory of folders containing data
% savefolder - Destination folder containing folders of saved mat files
% tarlocation - Folder for zipped processed files.  All data from *.NCS 
%               files in this folder (and NEX5) will be zipped together.
%               Default: Empty, which does not produce a *.tar file
% tarNCS - Boolean; include a *.tar file contain *.NCS within larger *.tar
% extension - Extension on recording data to include (empty, 0001, etc).
%               Accepts cell arrays of strings or numbers, numerical
%               arrays, and the string 'all' (tries extensions:{'', 1-25}).
%               Empty, only takes files with no extension. Default: 'all'            
% exMethod - Specify data type to be extracted: 'lfp',spike', or 'all'
% exportNEX - Boolean; Create a NEX5, an Offline Sorter compatible file
% datatype - data type saved to NEX5; 'spike','lfp','all'. Default:'spike'
% idxmeth - channel indexing method in NEX5 struct. Default: 'ordinal'.
%
%Output:
% folderlist - list of folders processed
%
%Jon Rueckemann and Yoni Browning 2018

%Default values
if nargin<1||isempty(parentfolder)
    parentfolder=uigetdir([],...
        'Select parent folder containing folders with *.NCS files.');
end
if nargin<2||isempty(savefolder)
    savefolder=uigetdir([],'Select folder to save processed data.');
end
if nargin<3
    tarlocation=[];
end
if nargin<4||isempty(tarNCS)
    tarNCS=true;
end
if nargin<5||isempty(extension)
    extension='all';
end
if nargin<6||isempty(exMethod)
    exMethod='all';
end

if nargin<7||isempty(exportNEX)
    exportNEX=false;
end
if nargin<8||isempty(datatype)
    datatype='spike'; %NEX5 export option, only export spike data
end
if nargin<9||isempty(idxmeth)
    idxmeth='ordinal';
end
if nargin<10||isempty(runpar)
    runpar=true;
end

%Create file extension list
if ischar(extension)&&strcmpi(extension,'all')
    extension=[{''} num2cell(1:25)];
elseif isnumeric(extension)
    extension=num2cell(extension);
end
for n=1:numel(extension)
    if isnumeric(extension{n})
        tempext=num2str(extension{n});
        extension{n}='0000';
        extension{n}(end-numel(tempext)+1:end)=tempext;
    end
end

%List of valid folders in directory
folders=dir(parentfolder);
folderlist={folders.name};
folderlist=folderlist([folders.isdir]&...
    ~strcmp(folderlist,'.')&~strcmp(folderlist,'..')&...
    ~strcmp(folderlist,'$RECYCLE.BIN')&...
    ~strcmp(folderlist,'System Volume Information'));

errorfolder=[];
for m=1:numel(folderlist)
    try
        curfolder=fullfile(parentfolder,folderlist{m});
        cursave=fullfile(savefolder,folderlist{m});
        mkdir(cursave);
        for n=1:numel(extension)
            if runpar
                exportNCS_P(curfolder,cursave,tarlocation,tarNCS,...
                    extension{n},exMethod,exportNEX,datatype,idxmeth);
            else
                exportNCS(curfolder,cursave,tarlocation,tarNCS,...
                    extension{n},exMethod,exportNEX,datatype,idxmeth);
            end
        end
    catch
        warning(['Error processing ' folderlist{m}]);
        errorfolder=[errorfolder; folderlist{m}]; %#ok<AGROW>
    end
end
end