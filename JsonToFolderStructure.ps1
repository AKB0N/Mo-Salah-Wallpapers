<#
.SYNOPSIS
Converts a JSON string or file to a folder structure with lowercase folder names and {foldername}.json in each folder.

.DESCRIPTION
This script takes a JSON string or a path to a JSON file as input and creates a folder structure on your file system that mirrors the hierarchy represented in the JSON.
It uses the lowercase version of the keys in the JSON objects as folder names and creates a {foldername}.json file inside each folder where {foldername} is the lowercase version of the folder's name.

.PARAMETER JsonString
The JSON string to convert.  If provided, this will be used directly.

.PARAMETER JsonFile
Path to a JSON file. If provided and JsonString is not, the script will read the JSON from this file.

.PARAMETER RootFolder
The root folder where the structure will be created. Defaults to the current directory.

.PARAMETER RootFolderName
An optional name for a root folder to be created inside RootFolder. If specified, the entire JSON structure will be created under this folder.

.EXAMPLE
# Create a folder structure from a JSON string in the current directory
@"
{
    "Project": {
        "Source": {
            "Scripts": {},
            "Styles": {}
        },
        "Assets": {
            "Images": {},
            "Audio": {}
        },
        "Documentation": {}
    }
}
"@ | .\JsonToFolderStructure.ps1

.EXAMPLE
# Create a folder structure from a JSON file in a specific root folder
.\JsonToFolderStructure.ps1 -JsonFile "C:\path\to\structure.json" -RootFolder "D:\Output"

.EXAMPLE
# Create a folder structure from a JSON string under a named root folder in the current directory
@"
{
    "MyWebApp": {
        "public": {
            "css": {},
            "js": {}
        },
        "private": {
            "config": {}
        }
    }
}
"@ | .\JsonToFolderStructure.ps1 -RootFolderName "WebAppStructure"

.NOTES
Requires PowerShell v3 or later due to ConvertFrom-Json.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, ValueFromPipeline=$true, HelpMessage="The JSON string to convert.")]
    [string]$JsonString,

    [Parameter(Mandatory=$false, HelpMessage="Path to a JSON file to convert.")]
    [string]$JsonFile,

    [Parameter(Mandatory=$false, HelpMessage="The root folder where the structure will be created. Defaults to current directory.")]
    [string]$RootFolder = ".",

    [Parameter(Mandatory=$false, HelpMessage="An optional name for a root folder to be created.")]
    [string]$RootFolderName
)

begin {
    # Resolve the root folder path
    $ResolvedRootFolder = Resolve-Path -Path $RootFolder
    if (-not $ResolvedRootFolder) {
        Write-Error "Root folder '$RootFolder' not found."
        return
    }
    $RootFolderPath = $ResolvedRootFolder.Path

    # Determine the JSON input source
    if ($JsonFile) {
        try {
            $jsonContent = Get-Content -Path $JsonFile -Raw -ErrorAction Stop
        } catch {
            Write-Error "Error reading JSON file '$JsonFile': $_"
            return
        }
    } elseif ($JsonString) {
        $jsonContent = $JsonString
    } else {
        Write-Error "No JSON input provided. Please provide either -JsonString or -JsonFile."
        return
    }

    try {
        $jsonObject = ConvertFrom-Json -InputObject $jsonContent -ErrorAction Stop
    } catch {
        Write-Error "Error parsing JSON: $_"
        Write-Error "Ensure the JSON is valid."
        return
    }

    # If RootFolderName is specified, create the root folder
    if ($RootFolderName) {
        $fullRootPath = Join-Path -Path $RootFolderPath -ChildPath $RootFolderName
        Write-Verbose "Creating root folder: '$fullRootPath'"
        try {
            New-Item -ItemType Directory -Path $fullRootPath -Force | Out-Null # Force creates if it doesn't exist
        } catch {
            Write-Error "Error creating root folder '$fullRootPath': $_"
            return
        }
    } else {
        $fullRootPath = $RootFolderPath
    }
}

process {
    function Create-FolderStructure {
        param(
            [Parameter(Mandatory=$true)]
            [PSObject]$Object,
            [Parameter(Mandatory=$true)]
            [string]$CurrentPath
        )

        foreach ($propertyName in $Object.PSObject.Properties) {
            $folderName = $propertyName.Name
            $lowerFolderName = $folderName.ToLower() # Convert folder name to lowercase
            $folderPath = Join-Path -Path $CurrentPath -ChildPath $lowerFolderName # Use lowercase name for folder path

            Write-Verbose "Creating folder: '$folderPath' (from JSON key: '$folderName')" # Verbose output now shows original JSON key
            try {
                New-Item -ItemType Directory -Path $folderPath -Force | Out-Null # Force creates if it doesn't exist

                # Create {foldername}.json inside the folder
                $jsonFileName = "$($lowerFolderName).json" # Use lowercase name for json filename as well
                $jsonFilePath = Join-Path -Path $folderPath -ChildPath $jsonFileName
                $folderNameJsonContent = ConvertTo-Json -InputObject @{ "name" = $lowerFolderName } -Compress # Ensure lowercase name in json content
                Write-Verbose "Creating file: '$jsonFilePath' with content: '$folderNameJsonContent'"
                try {
                    $folderNameJsonContent | Out-File -FilePath $jsonFilePath -Encoding UTF8 -ErrorAction Stop
                } catch {
                    Write-Warning "Warning: Could not create file '$jsonFilePath'. $($_.Exception.Message)"
                }

            } catch {
                Write-Warning "Warning: Could not create folder '$folderPath'. $($_.Exception.Message)"
                continue # Skip to the next property if folder creation fails
            }

            $propertyValue = $propertyName.Value
            if ($propertyValue -is [PSObject]) {
                Write-Verbose "Recursing into object property: '$propertyName.Name' (lowercase folder: '$lowerFolderName')" # Verbose output includes lowercase folder name
                Create-FolderStructure -Object $propertyValue -CurrentPath $folderPath
            } elseif ($propertyValue -is [System.Collections.ArrayList]) {
                Write-Verbose "Handling array property: '$propertyName.Name' (Arrays will be ignored for folder structure)"
                # You can choose to handle arrays differently if needed, e.g., create numbered folders for array items.
                # For now, we'll ignore arrays as directly creating folders from array indices might not be desired.
            }
            # You can add handling for other types if needed (e.g., Hashtable, etc.)
        }
    }

    Write-Verbose "Starting folder structure creation in: '$fullRootPath'"
    Create-FolderStructure -Object $jsonObject -CurrentPath $fullRootPath

    Write-Host "Folder structure created successfully in '$fullRootPath'."
}

end {}