%Add scripts to matpath
addpath(genpath('/home/ubuntu/Documents/MATLAB'));
addpath(genpath('/home/ubuntu/Desktop/112122-ImportSignals-master'));

%Storing ncs here
tempData = '/home/ubuntu/Documents/dataOut/tempData';
%Storing generated mats here
tempOut =  '/home/ubuntu/Documents/dataOut/tempOut';

inBucket = 'samunder700raw/';
outBucket = 'samunder700receive/';
%% Get all files on the s3 data bucket
command = ['aws s3 ls s3://', inBucket, ' --recursive'];
[status out] = system(command);
out = splitlines(out);

out = cellfun(@(x) split(x, ' '), out, 'UniformOutput', false);
out(cellfun(@(x) length(x)==1, out)) = [];
bytes = cellfun(@(x) x(end-1), out, 'UniformOutput', false);
out= cellfun(@(x) x(end), out, 'UniformOutput', false);
%%
dataPaths = string(out);
dataPaths = dataPaths(contains(dataPaths, 'ncs') & contains(dataPaths, 'CSC'));
[a b c] = fileparts(dataPaths);
[f g] = fileparts(a);
[C ic ia] = unique(g);
uniqueDays = a(ic);
uniqueDays = fullfile(inBucket, uniqueDays)

numberOfNCS = zeros(size(uniqueDays));
medianNCSSize = zeros(size(uniqueDays));
parfor i = 1:length(uniqueDays)
    thisDay = uniqueDays{i};
    [path dayName] = fileparts(thisDay);
    thisDayData = fullfile(tempData, dayName);
    

    command = ['aws s3 ls ''s3://' char(thisDay) '/'' --recursive'];
    
    [status out] = system(command);
    if length(out)>0
        out = splitlines(out);
        out = cellfun(@(x) split(x, ' '), out, 'UniformOutput', false);
        out(cellfun(@(x) length(x)==1, out)) = [];
        bytes = cellfun(@(x) x(end-1), out, 'UniformOutput', false);
        out= cellfun(@(x) x(end), out, 'UniformOutput', false);
        bytes = [bytes{:}]';
        bytes = cellfun(@(x)str2num(x), bytes);
        out = [out{:}]';
        ncsBool = contains(out, '.ncs');
        numberOfNCS(i) = sum(ncsBool);
        bytes = bytes(ncsBool);
        thisSize = max(bytes)
        medianNCSSize(i) = thisSize;
    end
    
end

[B I] = sort(medianNCSSize);
uniqueDays = uniqueDays(I);
uniqueDays = uniqueDays(B>0);
B = B(B>0);
B
%%
logPath = '/home/ubuntu/Documents/dataOut/logFiles';

completeDir = dir(fullfile(logPath, 'complete'));
completeName = {completeDir.name}';
completeName = completeName(~(strcmp(completeName,'.')|strcmp(completeName,'..')));
completeBool = cellfun(@(x)contains(x, completeName), uniqueDays);

rerunErrors = false;
if ~rerunErrors
    errorDir = dir(fullfile(logPath, 'error'));
    errorName = {errorDir.name}';
    errorName = errorName(~(strcmp(errorName,'.')|strcmp(errorName,'..')));
    errorBool = cellfun(@(x)contains(x, errorName), uniqueDays);
    
    completeBool = completeBool | errorBool;
end
runTheseUniqueDays = uniqueDays(~completeBool)

for i = 1:length(runTheseUniqueDays)
    try 
        thisDay = runTheseUniqueDays{i}
        [path dayName] = fileparts(thisDay); 
        thisDayData = fullfile(tempData, dayName);
        thisDayOut = fullfile(tempOut, dayName);  
        
        logFile = fullfile(logPath,'complete',dayName);
        
        if exist(char(thisDayData), 'dir')
            rmdir(thisDayData, 's');
        end

        mkdir(thisDayData);
        command = ['aws s3 sync ''s3://' char(thisDay) ''' ' char(thisDayData)];
        [status out] = system(command);

        if exist(char(thisDayOut), 'dir')
            rmdir(thisDayOut, 's');
        end

        mkdir(thisDayOut);

        extraFiles = dir(thisDayData);
        extraFiles = {extraFiles.name}';
        extraFiles = extraFiles(contains(extraFiles, 'EYE')|contains(extraFiles, 'Eye')|contains(extraFiles, 'nev')|contains(extraFiles, 'config'));
        extraFiles = fullfile(thisDayData, extraFiles);
        for m =1:length(extraFiles)
            copyfile(extraFiles{m},thisDayOut)
        end

        exportNCS_P(thisDayData, thisDayOut, [],[],'.ncs'); %fix this so it process the correct ncs's
        batchSessionFlagNoise(thisDayOut);
        
        %command = ['aws s3 sync /home/ubuntu/Documents/dataOut/tempOut/ s3://ajtestreceive/'];
        %Folder on s3 bucket to recieve tempOut data
        s3thisDayPath = ['s3://', outBucket, dayName, '/'];
        %Copy output data to the s3 bucket
        command = ['aws s3 cp ' thisDayOut ' ' s3thisDayPath ' --recursive'];%/home/ubuntu/Documents/dataOut/tempOut/ s3://ajtestreceive/'];
        status = system(command);
        
        %If status is 0, command executed successfully. If not, throw error
        %as data was not successfuly copied
        if (status>0)
            error('Failed to copy output to s3 bucket');
        end
        %check to makes sure copy worked
        
        logID = fopen(logFile, 'a+');
        fprintf(logID, [thisDay, ' completed']);
        fclose(logID);

    catch err
        errorID = fopen(fullfile(logPath, 'error', dayName), 'a+');
        fprintf(errorID, '%s\n',err.message);
        fprintf(errorID, '%s', err.getReport('extended', 'hyperlinks','off'))
        fclose(errorID)
    end
    
    if exist(thisDayData, 'dir')
        rmdir(thisDayData, 's');
    end
    
     if exist(thisDayOut, 'dir')
        rmdir(thisDayOut, 's');
    end
end




