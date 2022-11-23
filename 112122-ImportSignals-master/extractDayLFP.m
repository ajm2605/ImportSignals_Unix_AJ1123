function [LFP,LFPts,filelist,badidx]=extractDayLFP(foldername,idx,targetfiles,exacttarget)
%Concatenate LFP data within a day
%[Add ability to reject idx groups that surpass the indices of the LFP]
%
%Jon Rueckemann 2018

if nargin<1 || isempty(foldername)
    foldername=uigetdir;
end

if nargin<2
    idx=[];
elseif isnumeric(idx)
    if any(diff(idx)>1) %divide idx into separate cells if any idx jump > 1
        epochidx=cumsum([1 diff(idx)~=1]);
        newidx=cell(max(epochidx),1);
        for n=1:max(epochidx)
            newidx{n}=idx(epochidx==n);
        end
        idx=newidx;
    else
        idx={idx};
    end
elseif ~iscell(idx)
    error('idx input must be a cell array or numeric array.');
end
if nargin<3 || isempty(targetfiles)
    targetfiles=[];
end
if nargin<4 || isempty(exacttarget)
    exacttarget=true;
end

%List of valid files in directory
files=dir(foldername);
filelist={files.name};
filelist=filelist(~[files.isdir] & contains(filelist,'.mat') ...
    & contains(filelist,'CSC'));

%Target specified files
if ~isempty(targetfiles)
    if exacttarget
        filelist=filelist(ismember(filelist,targetfiles));
    else
        filelist=filelist(contains(filelist,targetfiles));
    end
end

if isempty(filelist)
    [LFP,LFPts]=deal([]);
    return;
end
filelist=fullfile(foldername,filelist);

%Concatenate LFP data across channels
for m=1:numel(filelist)
    matobj=matfile(filelist{m});
    disp(filelist{m});
    if isempty(idx)
        if m==1
            [LFPts,LFP]=deal(nan(numel(filelist),size(matobj.lfp,1)));
        end
        LFPts(m,:)=matobj.lfpts;
        LFP(m,:)=matobj.lfp;
        badidx=false;
    else
        %Reject index arrays that are not contained within record
        badidx=cellfun(@(x) any(x<1)|any(x>max(size(matobj,'lfp'))),idx);
        if all(badidx)
            [LFP,LFPts]=deal([]);
            return;
        end
        idx=idx(~badidx);
        
        %Iterate through remaining indices
        if m==1
            [LFPts,LFP]=deal(cellfun(@(x) nan(numel(filelist),numel(x)),...
                idx,'uni',0));
        end
        for n=1:numel(idx)
            LFPts{n}(m,:)=matobj.lfpts(1,idx{n});
            LFP{n}(m,:)=matobj.lfp(1,idx{n});
        end
    end
end
if ~iscell(LFPts)
    if nnz(diff(LFPts))==0
        LFPts=LFPts(1,:);
    end
else
    if all(cellfun(@(x) nnz(diff(x))==0,LFPts))
        LFPts=cellfun(@(x) x(1,:),LFPts,'uni',0);
    end
end
end