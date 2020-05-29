<#
 .Synopsis
  Synchronize folders.

 .Description
  Synchronizes all files and folders for the two given paths, by comparing file hashes and "LastWriteDate".

 .Parameter SourcePath
  The source path from which folders and files will be copy. The reference container. This path must exist.
  If not, script will be terminated.

 .Parameter DestinationPath
  The destination folder where all folders and files will be copied to.
  If it does't exist, user will be prompted to create.
  If 'Yes', everything will be copied.
  if 'No', script will be terminated.

 .Parameter Log
  Log file for logging errors.
  If it doesn't exist, will be created.
  If not defined, default name will be used ("C:\Logs\syncFileStructure_log.txt").

 .Parameter Sync
  Switch Parameter. If present, synchronization will be performed. If not, destination path will be overwritten.

 .Example
   # Synchroniza folders C:\MySourceFolder and \\SVR01\SharedFolder.
   Sync-FilesAndFolders -SourcePath "C:\MySourceFolder" -DestinationPath "\\SVR01\SharedFolder" -Sync
#>
function Sync-FilesAndFolders{
    [CmdLetBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory,ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$SourcePath,
        [Parameter(Mandatory,ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationPath,
        [Parameter()]
        [string]$Log,
        [Parameter()]
        [switch]$Sync=$false
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
                    New-Item -Path (($file.DirectoryName).Replace($SourcePath,$DestinationPath)) -ItemType Directory | Out-Null
                    logActions -logFile $Log -logText "New directory created: $(($file.DirectoryName).Replace($SourcePath,$DestinationPath))"
                    New-Item -Path ($file.FullName).Replace($SourcePath,$DestinationPath) -ItemType File | Out-Null
                    logActions -logFile $Log -logText "New file created: $(($file.FullName).Replace($SourcePath,$DestinationPath))"
                }else{
                    #The destination folder exists, but not the file
                    if(-not (Test-Path -Path ($file.FullName).Replace($SourcePath,$DestinationPath))){
                        New-Item -Path ($file.FullName).Replace($SourcePath,$DestinationPath) -ItemType File | Out-Null
                        logActions -logFile $Log -logText "New file created: $(($file.FullName).Replace($SourcePath,$DestinationPath))"
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
                    New-Item -Path (($file.DirectoryName).Replace($DestinationPath,$SourcePath)) -ItemType Directory | Out-Null
                    logActions -logFile $Log -logText "New directory created: $(($file.DirectoryName).Replace($DestinationPath,$SourcePath))"
                    New-Item -Path ($file.FullName).Replace($DestinationPath,$SourcePath) -ItemType File | Out-Null
                    logActions -logFile $Log -logText "New file created: $(($file.FullName).Replace($DestinationPath,$SourcePath))"
                }else{
                    #The destination folder exists, but not the file
                    if(-not (Test-Path -Path ($file.FullName).Replace($DestinationPath,$SourcePath))){
                        New-Item -Path ($file.FullName).Replace($DestinationPath,$SourcePath) -ItemType File | Out-Null
                        logActions -logFile $Log -logText "New file created: $(($file.FullName).Replace($DestinationPath,$SourcePath))"
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
                New-Item -Path ($_.InputObject.FullName).Replace($SourcePath,$DestinationPath) -ItemType Directory | Out-Null
                logActions -logFile $Log -logText "New directory created: $(($_.InputObject.FullName).Replace($SourcePath,$DestinationPath))"
            }
        }elseif($_.SideIndicator -eq '=>'){
            if(-not (Test-Path -Path (($_.InputObject.FullName).Replace($DestinationPath,$SourcePath)))){
                New-Item -Path ($_.InputObject.FullName).Replace($DestinationPath,$SourcePath) -ItemType Directory | Out-Null
                logActions -logFile $Log -logText "New directory created: $(($_.InputObject.FullName).Replace($DestinationPath,$SourcePath))"
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