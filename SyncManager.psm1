<#
.SYNOPSIS
Synchronize folders.

.DESCRiPTION
Synchronizes all files and folders for the two given paths, by comparing file hashes and "LastWriteDate".

.PARAMETER SourcePath
The source path from which folders and files will be copied. The reference container. This path must exist.
If not, script will be terminated.

.PARAMETER DestinationPath
The destination folder where all folders and files will be copied to.
If it does't exist, user will be prompted to create.
If 'Yes', everything will be copied.
if 'No', script will be terminated.

.PARAMETER Log
Log file for logging errors.
If it doesn't exist, will be created.
If not defined, default name will be used ("C:\Logs\syncFileStructure_log.txt").

.PARAMETER Sync
Switch Parameter. If present, synchronization will be performed. If not, destination path will be overwritten.

.PARAMETER DominantSide
ValidateSet Parameter
Possible Values: 'None', 'Left', 'Right'
If absent or 'None', performs a bidirectional synchronization.
If 'Left', the left side structure will be dominant and all extra objects on the right side will be deleted. Extra objects on the left side will e created on the right site
If 'Right', the right side structure will be dominant and all extra objects on the left side will be deleted. Extra objects on the right side will e created on the left site

.EXAMPLE
Sync-FilesAndFolders -SourcePath "C:\MySourceFolder" -DestinationPath "\\SVR01\SharedFolder" -Sync
Synchronize folders C:\MySourceFolder and \\SVR01\SharedFolder.
.EXAMPLE
Sync-FilesAndFolders -SourcePath "C:\MySourceFolder" -DestinationPath "\\SVR01\SharedFolder"
Bulk copy from left to right with no synchronization. Right side will be overwriten
.EXAMPLE
Sync-FilesAndFolders -SourcePath "C:\MySourceFolder" -DestinationPath "\\SVR01\SharedFolder" -Sync -DominantSide Left
Performs bidirectional synchronization but the left side is predominant, e.g., extra objects in the left side will be copied to the right side
and extra objects in the right side will be deleted

.LINK
https://github.com/rndmendes/SyncManager

.OUTPUTS
Only to log file
#>
function Sync-FilesAndFolders{
    [CmdLetBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$SourcePath,
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationPath,
        [Parameter()]
        [string]$Log,
        [Parameter()]
        [switch]$Sync=$false,
        [Parameter()]
        [ValidateSet('Left','Right','None')]
        [string]$DominantSide='None'
    )

    $error.Clear()
    if(-not $Log){
        $Log = "C:\Logs\syncFileStructure_log.txt"
        New-Item -ItemType File -Path $Log -Force | Out-Null
    }
    try{
        if(-not (Test-Path -Path $SourcePath)){
            throw "The provided SourcePath $SourcePath does not exist."
        }
    }catch{
        Write-Error $error[0].Exception.Message
        return
    }        
    if(-not(Test-Path -Path $DestinationPath)){
        $create = Read-Host "Detination path does not exist. Create? [Y / N]"
        if($create -eq 'Y'){
            New-Item -Path $DestinationPath -ItemType Directory | Out-Null
            robocopy $SourcePath $DestinationPath /mir /log: $Log
            return
        }else{
            Write-Output "Script was terminated."
            return
        }
    }

    $DestinationFiles = Get-ChildItem -Path $DestinationPath -Recurse -File -ErrorAction SilentlyContinue
    $SourceFiles = Get-ChildItem -Path $SourcePath -Recurse -File -ErrorAction SilentlyContinue
    if((-not $Sync) -or (-not $DestinationFiles)){
        robocopy $SourcePath $DestinationPath /mir /log: $Log
    }else{
        $objCollection = New-Object System.Collections.ArrayList
        Compare-Object -ReferenceObject $SourceFiles -DifferenceObject $DestinationFiles -IncludeEqual -Property LastWriteTime,Name -PassThru | 
        ForEach-Object {
            $objProps = [ordered]@{}
            if($_.SideIndicator -eq '<='){
                # The destination folder and file do not exist
                if(-not (Test-Path (($_.DirectoryName).Replace($SourcePath,$DestinationPath)))){
                    if(($DominantSide -eq 'Left') -or ($DominantSide -eq 'None')){
                        Write-Debug "No folder nor file - Left or None"
                        Copy-Item -Path ($_.DirectoryName) -Destination (($_.DirectoryName).Replace($SourcePath,$DestinationPath)) -Recurse | Out-Null
                        logActions -logFile $Log -logText "Directory copied: $(($_.FullName).Replace($SourcePath,$DestinationPath))"
                        $objProps.Add("ObjectType","Directory;File")
                        $objProps.Add("Path",$_.DirectoryName)
                        $objProps.Add("Action","Copy")
                        $objProps.Add("From","Left")
                        $objProps.Add("To","Right")                        
                    }else{
                        Remove-Item -Path $_.DirectoryName -Force -Recurse | Out-Null
                        logActions -logFile $Log -logText "Deleted directory and files: $($_.DirectoryName)"
                        $objProps.Add("ObjectType","Directory;File")
                        $objProps.Add("Path",$_.DirectoryName)
                        $objProps.Add("Action","Delete")
                        $objProps.Add("From","Left")
                        $objProps.Add("To","")                        
                    }
                }else{
                    #The destination folder exists, but not the file
                    if(-not (Test-Path -Path ($_.FullName).Replace($SourcePath,$DestinationPath))){
                        if(($DominantSide -eq 'Left') -or ($DominantSide -eq 'None')){
                            Copy-Item -Path ($_.FullName) -Destination ($_.FullName).Replace($SourcePath,$DestinationPath) | Out-Null
                            logActions -logFile $Log -logText "New file created: $(($_.FullName).Replace($SourcePath,$DestinationPath))"
                            $objProps.Add("ObjectType","File")
                            $objProps.Add("Path",($_.FullName).Replace($SourcePath,$DestinationPath))
                            $objProps.Add("Action","Copy")
                            $objProps.Add("From","Left")
                            $objProps.Add("To","Right")
                        }else{
                            Remove-Item -Path $_.FullName -Force | Out-Null
                            logActions -logFile $Log -logText "Deleted file: $($_.FullName)"
                            $objProps.Add("ObjectTypr","File")
                            $objProps.Add("Path",$_.FullName)
                            $objProps.Add("Action","Delete")
                            $objProps.Add("From","Left")
                            $objProps.Add("To","")                            
                        }
                    }else{ # The file exists in both sides, lets compare the file hash
                        $destFile = Get-Item -Path ($_.FullName).Replace($SourcePath,$DestinationPath)
                        #Determine which one has the most recent write date
                        if($_.LastWriteTime -gt $destFile.LastWriteTime){
                            Remove-Item -Path $destFile.FullName | Out-Null
                            Copy-Item -Path $_.FullName -Destination $destFile.FullName | Out-Null
                            logActions -logFile $Log -logText "File updated: $($destFile.FullName)"
                            $objProps.Add("ObjectType","File")
                            $objProps.Add("Path",$destFile.FullName)
                            $objProps.Add("Action","Update")
                            $objProps.Add("from","Left")
                            $objProps.Add("To","Right")                                        
                        }elseif($_.LastWriteTime -lt $destFile.LastWriteTime){
                            Remove-Item -Path $_.FullName | Out-Null
                            Copy-Item -Path $destFile.FullName -Destination $_.FullName | Out-Null 
                            logActions -logFile $Log -logText "File updated: $($_.FullName)"
                            $objProps.Add("ObjectType","File")
                            $objProps.Add("Path",$_.FullName)
                            $objProps.Add("Action","Update")
                            $objProps.Add("From","Left")      
                            $objProps.Add("To","Right")                           
                        }
                    }                    
                }
            }elseif($_.SideIndicator -eq '=>'){
                # The source folder and file do not exist
                if(-not (Test-Path (($_.DirectoryName).Replace($DestinationPath,$SourcePath)))){
                    if(($DominantSide -eq 'Right') -or ($DominantSide -eq 'None')){
                        Copy-Item -Path $_.DirectoryName -Destination (($_.DirectoryName).Replace($DestinationPath,$SourcePath)) -Recurse | Out-Null
                        logActions -logFile $Log -logText "Directory Copied to: $(($_.FullName).Replace($DestinationPath,$SourcePath))"
                        $objProps.Add("ObjectType","Directory;File")
                        $objProps.Add("Path",$_.DirectoryName)
                        $objProps.Add("Action","Copy")
                        $objProps.Add("From","Right")      
                        $objProps.Add("To","Left")                            
                    }else{
                        Remove-Item -Path $_.DirectoryName -Force -Recurse | Out-Null
                        logActions -logFile $Log -logText "Deleted directory and files: $($_.DirectoryName)"  
                        $objProps.Add("ObjectType","Directory;File")
                        $objProps.Add("Path",($_.DirectoryName))
                        $objProps.Add("Action","Delete")
                        $objProps.Add("From","Right")      
                        $objProps.Add("To","")                                                 
                    }

                }else{
                    #The destination folder exists, but not the file
                    if(-not (Test-Path -Path ($_.FullName).Replace($DestinationPath,$SourcePath))){
                        if(($DominantSide -eq 'Right') -or ($DominantSide -eq 'None')){
                            Copy-Item -Path $_.FullName -Destination ($_.FullName).Replace($DestinationPath,$SourcePath) | Out-Null
                            logActions -logFile $Log -logText "File copied to: $(($_.FullName).Replace($DestinationPath,$SourcePath))"
                            $objProps.Add("ObjectType","File")
                            $objProps.Add("Path",$_.FullName)
                            $objProps.Add("Action","Copy")
                            $objProps.Add("From","Right")      
                            $objProps.Add("To","Left")                            
                        }else{
                            Remove-Item -Path $_.FullName -Force -Recurse | Out-Null
                            logActions -logFile $Log -logText "Deleted file: $($_.FullName)"
                            $objProps.Add("ObjectType","File")
                            $objProps.Add("Path",$_.FullName)
                            $objProps.Add("Action","Delete")
                            $objProps.Add("From","Right")      
                            $objProps.Add("Side","")                                                        
                        }
                    }else{ # The file exists in both sides, lets compare the file hash
                        $destFile = Get-Item -Path ($_.FullName).Replace($DestinationPath,$SourcePath)
                        #Determine which one has the most recent write date
                        if($_.LastWriteTime -gt $destFile.LastWriteTime){
                            Remove-Item -Path $destFile.FullName | Out-Null
                            Copy-Item -Path $_.FullName -Destination $destFile.FullName | Out-Null
                            logActions -logFile $Log -logText "File updated: $($destFile.FullName)"
                            $objProps.Add("ObjectType","File")
                            $objProps.Add("Path",$_.FullName)
                            $objProps.Add("Action","Update")
                            $objProps.Add("From","Right")      
                            $objProps.Add("To","Left")                                        
                        }elseif($_.LastWriteTime -lt $destFile.LastWriteTime){
                            Remove-Item -Path $_.FullName | Out-Null
                            Copy-Item -Path $destFile.FullName -Destination $_.FullName | Out-Null
                            logActions -logFile $Log -logText "File updated: $($_.FullName)"
                            $objProps.Add("ObjectType","File")
                            $objProps.Add("Path",$destFile.FullName)
                            $objProps.Add("Action","Update")
                            $objProps.Add("From","Left")      
                            $objProps.Add("Side","Right")                                 
                        }
                    }
                }           
            }
            if($objProps.Count -ne 0){
                $objOperations = New-Object -TypeName psobject -Property $objProps
                $objCollection.Add($objOperations) | Out-Null
            }

        }
    }
    #Region Empty Folders
    Compare-Object  -ReferenceObject (Get-ChildItem -Path $SourcePath -Recurse -Directory) `
                    -DifferenceObject (Get-ChildItem -Path $DestinationPath -Recurse -Directory) |
    ForEach-Object {
        $objProps = @{}
        if($_.SideIndicator -eq '<='){
            if(-not (Test-Path -Path (($_.InputObject.FullName).Replace($SourcePath,$DestinationPath)))){
                if(($DominantSide -eq 'Left') -or ($DominantSide -eq 'None')){
                    New-Item -Path ($_.InputObject.FullName).Replace($SourcePath,$DestinationPath) -ItemType Directory | Out-Null
                    logActions -logFile $Log -logText "New directory created: $(($_.InputObject.FullName).Replace($SourcePath,$DestinationPath))"
                    $objProps.Add("ObjectType","Directory")
                    $objProps.Add("Path",($_.InputObject.FullName).Replace($SourcePath,$DestinationPath))
                    $objProps.Add("Action","Create")
                    $objProps.Add("From","")      
                    $objProps.Add("To","Right")                        
                }else{
                    Remove-Item -Path $_.InputObject.FullName -Force | Out-Null
                    logActions -logFile $Log -logText "Deleted directory: $($_.InputObject.FullName)"
                    $objProps.Add("ObjectType","Directory")
                    $objProps.Add("Path",$_InputObject.Fullname)
                    $objProps.Add("Action","Delete")
                    $objProps.Add("From","Left")      
                    $objProps.Add("To","")                           
                }

            }
        }elseif($_.SideIndicator -eq '=>'){
            if(-not (Test-Path -Path (($_.InputObject.FullName).Replace($DestinationPath,$SourcePath)))){
                if(($DominantSide -eq 'Right') -or ($DominantSide -eq 'None')){
                    New-Item -Path ($_.InputObject.FullName).Replace($DestinationPath,$SourcePath) -ItemType Directory | Out-Null
                    logActions -logFile $Log -logText "New directory created: $(($_.InputObject.FullName).Replace($DestinationPath,$SourcePath))"
                    $objProps.Add("ObjectType","Directory")
                    $objProps.Add("Path",($_.InputObject.FullName).Replace($DestinationPath,$SourcePath))
                    $objProps.Add("Action","Create")
                    $objProps.Add("From","")      
                    $objProps.Add("To","Left")                           
                }else{
                    Remove-Item -Path $_.InputObject.FullName -Force | Out-Null
                    logActions -logFile $Log -logText "Deleted directory: $($_.InputObject.FullName)"
                    $objProps.Add("ObjectType","Directory")
                    $objProps.Add("Path",$_InputObject.Fullname)
                    $objProps.Add("Action","Delete")
                    $objProps.Add("From","Right")      
                    $objProps.Add("To","")                         
                }
            }            
        }
        if($objProps.Count -ne 0){
            $objOperations = New-Object -TypeName psobject -Property $objProps
            $objCollection.Add($objOperations) | Out-Null
        }

    }
    if($objCollection.Count -ne 0){
        $objCollection
    }else{
        Write-Output "No changes detected"
    }

    #EndRegion
}

function logActions {
    param(
        [Parameter()]
        [string]$logText,
        [Parameter()]
        [string]$logFile
    )
    $Dt = Get-Date
    $dtLogText = "[$Dt] $logText"
    Add-Content -Path $logFile -Value $dtLogText
}