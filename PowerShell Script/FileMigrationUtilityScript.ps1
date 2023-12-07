$configFilePath = "$PSScriptRoot\ConfigFile.`json"
# Using ConvertFrom-String Data to parse key value strings from .json file into hashtable via Pipe method (example 6) here: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertfrom-stringdata?view=powershell-7.4
$config = Get-Content -Path $configFilePath | ConvertFrom-Json
# Gets value at each key and stores into a variable
$sourceParentDirectory = $config.SourceParentDirectory
$destinationParentDirectory = $config.DestinationParentDirectory
$defaultDaysOffset = $config.DefaultDaysOffset
# Gets latest timestamp and path to log file
$latestTransferTimestamp = [DateTime]::MinValue
$logFilePath = "$PSScriptRoot\LogFile.txt"
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


# Get the timestamp of the last file transfer from the log file
$lastTransferTimestamp = Get-Content -Path $logFilePath -ErrorAction SilentlyContinue
Write-Host $lastTransferTimestamp
Write-Host (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
# If the log file contains a timestamp, set it as the start date for Robocopy
if ($lastTransferTimestamp -ne $null) {
    $startDate = [DateTime]::ParseExact($lastTransferTimestamp, "yyyy-MM-dd HH:mm:ss", $null)
    $ts = New-TimeSpan -Start $startDate -End (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $DaysOffset = $ts.Days
} else {
    # If the log file is empty, get items modified based on default days offset in config file
    $DaysOffset = $defaultDaysOffset
}


# Iterate through each source and destination pair in the object array '$paths' created above
#     ROBOCOPY DOCS: https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy
foreach ($path in $paths) {
    $sourcePath = $path.SourcePath
    $destinationPath = $path.DestinationPath
    $file = $path.File

    # Define Robocopy options (see robocopy docs above for more explanation)
    # /COPY:DAT says to copy timestamps from directories
    # /DCOPY:T gets timestamps of directories
    # /R:1 means to retry once
    # /W:1 means to wait one second between retries
    # /V means to produce the verbose (detailed) output
    # /TEE says to write the status output to the console window, and to the log file.
    # /MAXAGE specifies the maximum file age (excludes files older than start date)
    # /LOG+:$logFilePath says to append the status output to $logFilePath (".\LogFile.txt")
    $robocopyOptions = "/MAXAGE:$DaysOffset /E /COPY:DAT /DCOPY:T /R:1 /W:1 /V /TEE /LOG+:`"$logFilePath`""
    $robocopyCommand = "robocopy `"$sourcePath`" `"$destinationPath`" `"$file`" $robocopyOptions"
    Invoke-Expression $robocopyCommand
}

# Output the latest transfer timestamp to the console and update the log file
$latestTransferTimestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$latestTransferTimestamp | Out-File $logFilePath
Write-Host "`n`n Script complete: `nLatest transfer timestamp written to LogFile: $latestTransferTimestamp"
Read-Host -Prompt "Press any key to exit . . ."