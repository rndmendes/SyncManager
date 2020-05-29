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
        Write-Verbose "A file path was not provided. Using the default file: $Log"
        New-Item -ItemType File -Path $Log -Force | Out-Null
    }
    try{
        if(-not (Test-Path -Path $SourcePath)){
            throw "The provided SourcePath $SourcePath does not exist."
        }
    }catch{
        Write-Error $error[0].Exception.Message
        exit
    }        
    if(-not(Test-Path -Path $DestinationPath)){
        $create = Read-Host "Detination path does not exist. Create? [Y / N]"
        if($create -eq 'Y'){
            New-Item -Path $DestinationPath -ItemType Directory | Out-Null
            robocopy $SourcePath $DestinationPath /mir /log+: $Log
            exit
        }else{
            Write-Output "Script was terminated."
            exit
        }
    }
    Write-Debug $DominantSide
    #$sourceFiles = Get-ChildItem -Path $SourcePath -Recurse -File | ForEach-Object {Get-FileHash -Path $_.FullName}
    $DestinationFiles = Get-ChildItem -Path $DestinationPath -Recurse -File | ForEach-Object {Get-FileHash -Path $_.FullName} -ErrorAction SilentlyContinue

    if((-not $Sync) -or (-not $DestinationFiles)){
        robocopy $SourcePath $DestinationPath /mir /log+: $Log
    }else{
        Compare-Object  -ReferenceObject (Get-ChildItem -Path $SourcePath -Recurse -File | ForEach-Object {Get-FileHash -Path $_.FullName}) `
                        -DifferenceObject (Get-ChildItem -Path $DestinationPath -Recurse -File | ForEach-Object {Get-FileHash -Path $_.FullName}) `
                        -Property Path, Hash -PassThru |
        Select-Object Hash, Path, SideIndicator |
        ForEach-Object {
            $file = Get-Item -Path $_.Path
            if($_.SideIndicator -eq '<='){
                # The destination folder and file do not exist
                if(-not (Test-Path (($file.DirectoryName).Replace($SourcePath,$DestinationPath)))){
                    if(($DominantSide -eq 'Left') -or ($DominantSide -eq 'None')){
                        Write-Debug "No folder nor file - Left or None"
                        New-Item -Path (($file.DirectoryName).Replace($SourcePath,$DestinationPath)) -ItemType Directory | Out-Null
                        logActions -logFile $Log -logText "New directory created: $(($file.DirectoryName).Replace($SourcePath,$DestinationPath))"
                        New-Item -Path ($file.FullName).Replace($SourcePath,$DestinationPath) -ItemType File | Out-Null
                        logActions -logFile $Log -logText "New file created: $(($file.FullName).Replace($SourcePath,$DestinationPath))"
                    }else{
                        Remove-Item -Path $file.DirectoryName -Force -Recurse | Out-Null
                        logActions -logFile $Log -logText "Deleted directory and files: $($file.DirectoryName)"
                    }
                }else{
                    #The destination folder exists, but not the file
                    if(-not (Test-Path -Path ($file.FullName).Replace($SourcePath,$DestinationPath))){
                        if(($DominantSide -eq 'Left') -or ($DominantSide -eq 'None')){
                            New-Item -Path ($file.FullName).Replace($SourcePath,$DestinationPath) -ItemType File | Out-Null
                            logActions -logFile $Log -logText "New file created: $(($file.FullName).Replace($SourcePath,$DestinationPath))"
                        }else{
                            Remove-Item -Path $file.FullName -Force | Out-Null
                            logActions -logFile $Log -logText "Deleted file: $($file.FullName)"
                        }
                    }else{ # The file exists in both sides, lets compare the file hash
                        $destFile = Get-Item -Path ($file.FullName).Replace($SourcePath,$DestinationPath)
                        if($_.Hash -ne ($destFile | Get-FileHash)){
                            #Determine which one has the most recent write date
                            if($file.LastWriteTime -gt $destFile.LastWriteTime){
                                Remove-Item -Path $destFile.FullName | Out-Null
                                Copy-Item -Path $file.FullName -Destination $destFile.FullName | Out-Null
                                logActions -logFile $Log -logText "File updated: $($destFile.FullName)"
                            }elseif($file.LastWriteTime -lt $destFile.LastWriteTime){
                                Remove-Item -Path $file.FullName | Out-Null
                                Copy-Item -Path $destFile.FullName -Destination $file.FullName | Out-Null 
                                logActions -logFile $Log -logText "File updated: $($file.FullName)"                              
                            }
                        }
                    }                    
                }
            }elseif($_.SideIndicator -eq '=>'){
                # The source folder and file do not exist
                if(-not (Test-Path (($file.DirectoryName).Replace($DestinationPath,$SourcePath)))){
                    if(($DominantSide -eq 'Right') -or ($DominantSide -eq 'None')){
                        New-Item -Path (($file.DirectoryName).Replace($DestinationPath,$SourcePath)) -ItemType Directory | Out-Null
                        logActions -logFile $Log -logText "New directory created: $(($file.DirectoryName).Replace($DestinationPath,$SourcePath))"
                        New-Item -Path ($file.FullName).Replace($DestinationPath,$SourcePath) -ItemType File | Out-Null
                        logActions -logFile $Log -logText "New file created: $(($file.FullName).Replace($DestinationPath,$SourcePath))"
                    }else{
                        Remove-Item -Path $file.DirectoryName -Force -Recurse | Out-Null
                        logActions -logFile $Log -logText "Deleted directory and files: $($file.DirectoryName)"                        
                    }

                }else{
                    #The destination folder exists, but not the file
                    if(-not (Test-Path -Path ($file.FullName).Replace($DestinationPath,$SourcePath))){
                        if(($DominantSide -eq 'Right') -or ($DominantSide -eq 'None')){
                            New-Item -Path ($file.FullName).Replace($DestinationPath,$SourcePath) -ItemType File | Out-Null
                            logActions -logFile $Log -logText "New file created: $(($file.FullName).Replace($DestinationPath,$SourcePath))"
                        }else{
                            Remove-Item -Path $file.FullName -Force | Out-Null
                            logActions -logFile $Log -logText "Deleted file: $($file.FullName)"                            
                        }
                    }else{ # The file exists in both sides, lets compare the file hash
                        $destFile = Get-Item -Path ($file.FullName).Replace($DestinationPath,$SourcePath)
                        if($_.Hash -ne ($destFile | Get-FileHash)){
                            #Determine which one has the most recent write date
                            if($file.LastWriteTime -gt $destFile.LastWriteTime){
                                Remove-Item -Path $destFile.FullName | Out-Null
                                Copy-Item -Path $file.FullName -Destination $destFile.FullName | Out-Null
                                logActions -logFile $Log -logText "File updated: $($destFile.FullName)"
                            }elseif($file.LastWriteTime -lt $destFile.LastWriteTime){
                                Remove-Item -Path $file.FullName | Out-Null
                                Copy-Item -Path $destFile.FullName -Destination $file.FullName | Out-Null
                                logActions -logFile $Log -logText "File updated: $($file.FullName)"
                            }
                        }
                    }                    
                }           
            }
        }
    }
    #Region Empty Folders
    #$sourceFolders = Get-ChildItem -Path $SourcePath -Recurse -Directory
    #$DestinationFolders = Get-ChildItem -Path $DestinationPath -Recurse -Directory
    Compare-Object  -ReferenceObject (Get-ChildItem -Path $SourcePath -Recurse -Directory) `
                    -DifferenceObject (Get-ChildItem -Path $DestinationPath -Recurse -Directory) |
    ForEach-Object {
        if($_.SideIndicator -eq '<='){
            if(-not (Test-Path -Path (($_.InputObject.FullName).Replace($SourcePath,$DestinationPath)))){
                if(($DominantSide -eq 'Left') -or ($DominantSide -eq 'None')){
                    New-Item -Path ($_.InputObject.FullName).Replace($SourcePath,$DestinationPath) -ItemType Directory | Out-Null
                    logActions -logFile $Log -logText "New directory created: $(($_.InputObject.FullName).Replace($SourcePath,$DestinationPath))"
                }else{
                    Remove-Item -Path $_.InputObject.FullName -Force | Out-Null
                    logActions -logFile $Log -logText "Deleted item: $($_.InputObject.FullName)"
                }

            }
        }elseif($_.SideIndicator -eq '=>'){
            if(-not (Test-Path -Path (($_.InputObject.FullName).Replace($DestinationPath,$SourcePath)))){
                if(($DominantSide -eq 'Right') -or ($DominantSide -eq 'None')){
                    New-Item -Path ($_.InputObject.FullName).Replace($DestinationPath,$SourcePath) -ItemType Directory | Out-Null
                    logActions -logFile $Log -logText "New directory created: $(($_.InputObject.FullName).Replace($DestinationPath,$SourcePath))"
                }else{
                    Remove-Item -Path $_.InputObject.FullName -Force | Out-Null
                    logActions -logFile $Log -logText "Deleted item: $($_.InputObject.FullName)"
                }
            }            
        }
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