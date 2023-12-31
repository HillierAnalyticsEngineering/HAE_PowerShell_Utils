﻿$configFilePath = "$PSScriptRoot\ConfigFile.`json"
# Using ConvertFrom-String Data to parse key value strings from .json file into hashtable via Pipe method (example 6) here: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertfrom-stringdata?view=powershell-7.4
$config = Get-Content -Path $configFilePath | ConvertFrom-Json
# Gets value at each key and stores into a variable
$sourceParentDirectory = $config.SourceParentDirectory
$destinationParentDirectory = $config.DestinationParentDirectory
$defaultDaysOffset = $config.DefaultDaysOffset
# Gets latest timestamp and path to log file
$latestTransferTimestamp = [DateTime]::MinValue
$logFilePath = "$PSScriptRoot\LogFile.txt"
$timestampFilePath = "$PSScriptRoot\TimeStampFile.txt"
# Recursively iterate through the source parent directory and get a list of file paths
$files = Get-ChildItem -Path $sourceParentDirectory -Recurse | Where-Object { $_.PSIsContainer -eq $false } | Select-Object -ExpandProperty FullName
# Create an array to store objects of source and destination filepath pairs
$paths = @()

# Generate source and destination paths based on the list of files
foreach ($file in $files) {
    $sourcePath = $file
    # remove parent directory for source
    $relativePath = $file -replace [regex]::Escape($sourceParentDirectory), ''
    # add parent directory for destination - create the destination paths based on the recursively-generated paths '$files' for each file
    $destinationPath = Join-Path -Path $destinationParentDirectory -ChildPath $relativePath
    # create an object containing a source & destination pair which can be accessed later in flow from property call
    # get proper directory vs filenames using Split-Path with pipe and leaf/resolve methods here: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/split-path?view=powershell-7.4
    $paths += [PSCustomObject]@{
        SourcePath = $sourcePath | Split-Path
        DestinationPath = $destinationPath | Split-Path
        File = Split-Path -Path $sourcePath -Leaf -Resolve
    }
}


# Get the timestamp of the last file transfer from the timestamp file
$lastTransferTimestamp = Get-Content -Path $timestampFilePath -ErrorAction SilentlyContinue
Write-Host $lastTransferTimestamp
Write-Host (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
# If the log file contains a timestamp, set it as the start date for Robocopy
if ($lastTransferTimestamp -ne $null) {
    $startDate = [DateTime]::ParseExact($lastTransferTimestamp, "yyyy-MM-dd HH:mm:ss", $null)
    $ts = New-TimeSpan -Start $startDate -End (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $DaysOffset = $ts.Days
} else {
    # If the log file is empty, get items modified based on default days offset in config file
    [int]$DaysOffset = [convert]::ToInt32($defaultDaysOffset, 10)
}

# If there is no archive folder, make one, otherwise do nothing
if (Test-Path -Path "$PSScriptRoot\Archive") {
    # Do Nothing
} else {
    New-Item -Path "$PSScriptRoot\Archive" -ItemType Directory
}
$archiveCurrentDatePath = "$PSScriptRoot\Archive\" + (Get-Date).ToString("yyyy-MM-dd")

# Empty Log File
'' | Out-File $logFilePath
$todayDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
"Script Initiated on $todayDate.`n`nBelow is a detailed summary of robocopy file migration jobs completed:`n`n" | Out-File -append $logFilePath

# Iterate through each source and destination pair in the object array '$paths' created above
#     ROBOCOPY DOCS: https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy

# PARALLEL BATCH 1 - ARCHIVE (BACKUP) FILE TRANSFER ----------

    $archiveJobs = @()

    foreach ($path in $paths) {
        $sourcePath = $path.SourcePath
        $destinationPath = $path.DestinationPath
        $file = $path.File
        $archiveDirectorySubPath = $destinationPath -replace [regex]::Escape($destinationParentDirectory), ''
        $archivePath = $archiveCurrentDatePath + $archiveDirectorySubPath

        if ( ((Get-Date) - (ls ($sourcePath + '\\' + $file)).LastWriteTime).Days -lt $DaysOffset -or ((Get-Date) - (ls ($sourcePath + '\\' + $file)).LastWriteTime).Days -eq 0) {
            #Add file to archive folder
            $robocopyOptionsArchive = "/MAXAGE:$DaysOffset /COPY:DAT /DCOPY:T /R:1 /W:1 /V /TEE"
            $robocopyCommandArchive = "robocopy `"$destinationPath`" `"$archivePath`" `"$file`" $robocopyOptions"
            # create guid for job, and add guid to list of guids for getting job-data on completion
            $id = [System.Guid]::NewGuid()
            $archiveJobs += $id
            # start robocopy as a background process (parallel processing) 
            # Note that this awaits the associated main file transfer to complete (using guid)
            Start-Job -Name $id -Scriptblock { Invoke-Expression $using:robocopyCommandArchive } 
        }
    }

    # Basically, check every second to see if jobs are done yet.
    While (Get-Job -State "Running") {
        cls
        Get-Job
        Start-Sleep 1 
    }
    # Clear the host for brevity
    cls
    # Show completed job listing and write to terminal
    Get-Job
    write-host "`n`nArchive Jobs completed, Writing output . . .`n"

    # Write all of the completed job info to the log file (waiting until all complete prevents thread-locking)
    foreach($job in $archiveJobs) {
        Receive-Job -Name $job | Out-File -Append $logFilePath
    }

    # Removes all jobs to ensure no jobs are still running among those started
        foreach($job in $archiveJobs) {
        Remove-Job -Name $job -ErrorAction SilentlyContinue
    }

# PARALLEL BATCH 2 - MAIN (REPLACEMENT OR ADDITION) FILE TRANSFER ----------

    $jobs = @()

    foreach ($path in $paths) {
        $sourcePath = $path.SourcePath
        $destinationPath = $path.DestinationPath
        $file = $path.File
        $archiveDirectorySubPath = $destinationPath -replace [regex]::Escape($destinationParentDirectory), ''
        $archivePath = $archiveCurrentDatePath + $archiveDirectorySubPath

        if ( ((Get-Date) - (ls ($sourcePath + '\\' + $file)).LastWriteTime).Days -lt $DaysOffset -or ((Get-Date) - (ls ($sourcePath + '\\' + $file)).LastWriteTime).Days -eq 0) {
            # Define Robocopy options (see robocopy docs above for more explanation)
            $robocopyOptions = "/E /MAXAGE:$DaysOffset /COPY:DAT /DCOPY:T /R:1 /W:1 /V /TEE"
            $robocopyCommand = "robocopy `"$sourcePath`" `"$destinationPath`" `"$file`" $robocopyOptions"
            # create guid for job, and add guid to list of guids for getting job-data on completion
            $id1 = [System.Guid]::NewGuid()
            $jobs += $id
            # start robocopy as a background process (parallel processing)
            Start-Job -Name $id -Scriptblock { Invoke-Expression $using:robocopyCommand }
        }
    }

    # Basically, check every second to see if jobs are done yet.
    While (Get-Job -State "Running") {
        cls
        Get-Job
        Start-Sleep 1 
    }
    # Clear the host for brevity
    cls
    # Show completed job listing and write to terminal
    Get-Job
    write-host "`n`nJobs completed, writing output . . .`n"

    # Write all of the completed job info to the log file (waiting until all complete prevents thread-locking)
    foreach($job in $jobs) {
        Receive-Job -Name $job | Out-File -Append $logFilePath
    }

    # Removes all jobs to ensure no jobs are still running among those started
    foreach($job in $jobs) {
        Remove-Job -Name $job -ErrorAction SilentlyContinue
    }

# Output the latest transfer timestamp to the console and update the log file
$latestTransferTimestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$latestTransferTimestamp | Out-File $timestampFilePath

#Delete archive directories with dates older than '$backupDaysOffset' (Defined in JSON config file)
[int]$backupDaysOffset = [convert]::ToInt32('-' + $config.BackupDaysOffset, 10)
$checkDate = (Get-Date).AddDays($backupDaysOffset)
Get-ChildItem -Path "$PSScriptRoot\Archive\" | ForEach-Object {
    $content = ($_.PSPath -split '[\\]')[-1]
    $contentDate = [DateTime]::ParseExact($content, "yyyy-MM-dd", $null)
    if ($contentDate -lt $checkDate) {
        Remove-Item -Path "$PSScriptRoot\Archive\$_" -Recurse 
    }
}

"`n`n Script complete: `nLatest transfer timestamp written to LogFile: $latestTransferTimestamp" | Out-File -append $logFilePath
Write-Host "`n`n Script complete: `nLatest transfer timestamp written to LogFile: $latestTransferTimestamp"
Read-Host -Prompt "Press any key to exit . . ."