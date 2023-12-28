# HAE_PowerShell_Utils
Utility Modules, Functions, and Scripts for PowerShell




### Date-Based File Transfer Utility for large file directories:
-----------------------------------------
This Powershell script, when run, will migrate all files recursively from the source directory to the destination directory.

    The source directory is defined by the string literal value to the SourceParentDirectory property. 
        This should be formatted as a literal path in Config.json.
        
    The destination directory is defined by the string literal value to the DestinationParentDirectory property. 
        This should be formatted as a literal path in Config.json.

Only files with a last-modified date later than the timestamp present in TimeStampFile.txt will be migrated.

    If no timestamp is present, a back-looking date offset will be used.
        This is defined as the int value to the DefaultDaysOffset property in Config.json.

    A new Timestamp is generated in the TimeStampFile.txt file upon each successful script execution.
  
Files in the target directory will be backed up in the Archive directory.

    A folder will be created for each day the utility is run. 
  
    The utility will automatically delete archive folders based on a back-looking date offset.
        This is defined as the int value to the BackupDaysOffset property in Config.json.

All copies (source to destination and destination to archive) will have their job outputs logged in LogFile.txt.
  
