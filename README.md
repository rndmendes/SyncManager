# SyncManager
PowerShell Module to Synchronize files and folders.

This module uses Powershell CmdLets to synchronize two folders and all contained files.
It is **bidirectional**, meaning that any change occurred in any side (source or destination) will be replicated.

>*Note:* In this version, any deleted files or folders (in one of the sides) will be created again, 
meaning that there's no "dominant" side. See **TODO** section for more details

## Details
- Supports local and remote shared folders with UNC paths
- Remember to check access rights on shared folders before using.
- Comparison between files is achieved by comparing file hash and "LastWriteTime"
- The files with the most recent write date will overwrite older files.

### Usage
This module exposes a unique function called Sync-FilesAndFolders.

To use, call the module function as below:

<code>Sync-FilesAndFolders -SourcePath "C:\SourceFolder" -DestinationPath "\\SVR01\RemoteFolder" -Log "C:\Logs\logFile.txt" -Sync</code>

- - -
### Parameters
- **SourcePath** is mandatory and has to be a valid path

- **DestinationPath** is mandatory. If it doesn't exist, sourcePath will be cloned to this path

- **Log** is not mandatory and has a default value of "C:\Logs\syncFileStructure_log.txt"

- **Sync** is a switch parameter. If present, bidirectional sync will be performed. If not present, sourcePath will be cloned to destinationPath

* **DominantSide** - a ValidateSet parameter with three possible values: "Left", "Right", "None"
  * If absent or 'None', will perform a bidireactional synchronization.
  * If 'Left', items existing only on the left side will be copied. All non corresponding items on the right side will be deleted
  * If 'Right', items existing only on the right side will be copied. All non corresponding items on the left side will be deleted

## TODO

- Implement PSSession for remote operations
