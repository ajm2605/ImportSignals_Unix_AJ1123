%Mount EFS before getting started
if isunix
    command = 'sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport 10.0.0.161:/ efs';
    system(command);
end

%% Useful Paths
workingPath = '/home/ubuntu/Documents/dataOut/';
dataPath = '/home/ubuntu/efs';

dataDir = dir(dataPath);
dataDir=dataDir(~ismember({dataDir.name},{'.','..'}));
names = {dataDir.name}

paths = findRecordingPaths(dataPath);


%%
for i = 1:numel(paths)
    curFolder = paths{i};
    tmp = split(curFolder, 'efs');
    curSave = fullfile(workingPath, tmp{2});

    %exportNCS(curFolder, curSave);
    %sessionFlagNoise(curSave);
    %command = 'aws s3 sync /home/ubuntu/Documents/dataOut s3://matlabtestreceive';
    %arn:aws:s3:::ajfortesting
    %status = system(command);
    %if status
    %    rmdir(curSave, 'dir');
    %end
end


function [paths] = findRecordingPaths(searchMe)
    searchMeDir = dir(searchMe);

    searchMeDir=searchMeDir(~ismember({searchMeDir.name},{'.','..'}));
    names = {searchMeDir.name};
    
    folders = names([searchMeDir.isdir]);
    year = contains(names, '2017') | contains(names, '2018') | contains(names, '2019') |contains(names, '2020') |contains(names, '2021') ;
    names = names([searchMeDir.isdir] & year & contains(names, '_') & contains(names, '-'));
    
    returnMe = string(fullfile(searchMe, names));
    
    for i = 1:length(folders)
        out = findRecordingPaths(fullfile(searchMe, folders{i}));
        returnMe = [returnMe, out];
    end
    
    paths = returnMe;
    
end
