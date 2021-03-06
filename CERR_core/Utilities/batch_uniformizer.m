function logS = batch_uniformizer(sourceDirName, destinDirName, destinDCMDirName)
%
% function logS = batch_uniformizer(dirName)
%
% This function uniformizes CERR plans in the passed source directory and
% writes them to the destination directory
%
% APA, 08/19/2011

% sourceDirName = '/Users/aptea/Documents/MSKCC/Projects/TRISMUS/TRISMUS CERR';
% destinDCMDirName = '/Users/aptea/Documents/MSKCC/Projects/TRISMUS/TRISMUS CERR DICOM';
% destinDirName = '/Users/aptea/Documents/MSKCC/Projects/TRISMUS/TRISMUS CERR UNIFORM';


fileC = {};
if strcmpi(sourceDirName,'\') || strcmpi(sourceDirName,'/')
    filesTmp = getCERRfiles(sourceDirName(1:end-1));
else
    filesTmp = getCERRfiles(sourceDirName);
end
fileC = [fileC filesTmp];

% Initialize waitbar
hWait = waitbar(0,'Uniformizing cohort of CERR plans. Please wait...');

logS = struct('maxDiff','', 'fileName', '');

numFiles = length(fileC);

%Load CERR plan
for iFile=1:numFiles
    
    %Update Waitbar
    drawnow
    
    waitbar(iFile/numFiles,hWait)    
    
    %Load CERR plan
    try
        planC = loadPlanC(fileC{iFile}, tempdir);
        planC = updatePlanFields(planC);
        indexS = planC{end};
        
        %Check for mesh representation and load meshes into memory
        currDir = cd;
        meshDir = fileparts(which('libMeshContour.dll'));
        cd(meshDir)
        for strNum = 1:length(planC{indexS.structures})
            if isfield(planC{indexS.structures}(strNum),'meshRep') && ~isempty(planC{indexS.structures}(strNum).meshRep) && planC{indexS.structures}(strNum).meshRep
                try
                    calllib('libMeshContour','loadSurface',planC{indexS.structures}(strNum).strUID,planC{indexS.structures}(strNum).meshS)
                catch
                    planC{indexS.structures}(strNum).meshRep    = 0;
                    planC{indexS.structures}(strNum).meshS      = [];
                end
            end
        end
        cd(currDir)
        
        stateS.optS = CERROptions;
        
        %Check color assignment for displaying structures
        [assocScanV,relStrNumV] = getStructureAssociatedScan(1:length(planC{indexS.structures}),planC);
        for scanNum = 1:length(planC{indexS.scan})
            scanIndV = find(assocScanV==scanNum);
            for i = 1:length(scanIndV)
                strNum = scanIndV(i);
                colorNum = relStrNumV(strNum);
                if isempty(planC{indexS.structures}(strNum).structureColor)
                    color = stateS.optS.colorOrder( mod(colorNum-1, size(stateS.optS.colorOrder,1))+1,:);
                    planC{indexS.structures}(strNum).structureColor = color;
                end
            end
        end
        
        %Check dose-grid
        for doseNum = 1:length(planC{indexS.dose})
            if planC{indexS.dose}(doseNum).zValues(2) - planC{indexS.dose}(doseNum).zValues(1) < 0
                planC{indexS.dose}(doseNum).zValues = flipud(planC{indexS.dose}(doseNum).zValues);
                planC{indexS.dose}(doseNum).doseArray = flipdim(planC{indexS.dose}(doseNum).doseArray,3);
            end
        end
        
        %Check whether uniformized data is in cellArray format.
        if ~isempty(planC{indexS.structureArray}) && iscell(planC{indexS.structureArray}(1).indicesArray)
            planC = setUniformizedData(planC,planC{indexS.CERROptions});
            indexS = planC{end};
        end
        
        if length(planC{indexS.structureArrayMore}) ~= length(planC{indexS.structureArray})
            for saNum = 1:length(planC{indexS.structureArray})
                if saNum == 1
                    planC{indexS.structureArrayMore} = struct('indicesArray', {[]},...
                        'bitsArray', {[]},...
                        'assocScanUID',{planC{indexS.structureArray}(saNum).assocScanUID},...
                        'structureSetUID', {planC{indexS.structureArray}(saNum).structureSetUID});
                    
                else
                    planC{indexS.structureArrayMore}(saNum) = struct('indicesArray', {[]},...
                        'bitsArray', {[]},...
                        'assocScanUID',{planC{indexS.structureArray}(saNum).assocScanUID},...
                        'structureSetUID', {planC{indexS.structureArray}(saNum).structureSetUID});
                end
            end
        end
                
        
        %Create uniform slices
        % planC = createUniformlySlicedPlanC(planC);
        
        
        
        % Check scan grid and correct for numerical noise
        zValuesV = [planC{indexS.scan}.scanInfo(:).zValue];
        zDiffV = diff(zValuesV);
        meanDiff = mean(zDiffV);
        maxDifference = max(abs((zDiffV - meanDiff)));
        
        % Write to log
        [jnk, fileName] = fileparts(fileC{iFile}); 
        logS(iFile).maxDiff = maxDifference;
        logS(iFile).fileName = fileName;
        
        
        if maxDifference < 0.05
            newZvalsV = linspace(zValuesV(1), zValuesV(end), length(zValuesV));
        else
            continue;
        end
        
        for sliceNum = 1:length(planC{indexS.scan}.scanInfo)
            
            planC{indexS.scan}.scanInfo(sliceNum).zValue = newZvalsV(sliceNum);
            
        end
        
        
        % Assign appropriate z-coordinates to structures
        for strNum = 1:length(planC{indexS.structures}(strNum))
            
            for slcNum = 1:length(planC{indexS.structures}(strNum).contour)
                
                for segNum = 1:length( planC{indexS.structures}(strNum).contour(slcNum).segments)
                    
                    if ~isempty( planC{indexS.structures}(strNum).contour(slcNum).segments(segNum).points)
                        
                         planC{indexS.structures}(strNum).contour(slcNum).segments(segNum).points(:,3) = newZvalsV(slcNum);
                        
                    end
                    
                end
                
            end         
            
        end                
        
        %Save plan to destination directory               
        save_planC(planC,[], 'passed', fullfile(destinDirName,fileName));
        
        % Export DICOM
        dcmFolderName =  fullfile(destinDCMDirName,strtok(fileName,'.'));
        if ~exist(dcmFolderName, 'dir')
            mkdir(dcmFolderName)
        end
        
        CERRExportDICOM(fullfile(destinDirName,fileName), dcmFolderName)
        
        
        
    catch
        
        disp([fileC{iFile}, ' failed to load'])
        continue
        
    end
    
end

close(hWait)


    