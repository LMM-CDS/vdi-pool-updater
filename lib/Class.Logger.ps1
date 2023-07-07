enum LogLevel {
    None
    Error
    Warning
    Info
    Verbose
    Debug
}
$retryMax = 20

# function Write-Log {

#     [CmdletBinding()]
#     Param(
#           [parameter(Mandatory=$false)]
#           [String]$Path,

#           [parameter(Mandatory=$true)]
#           [String]$Message,

#           [parameter(Mandatory=$true)]
#           [String]$Component,

#           [Parameter(Mandatory=$true)]
#           [ValidateSet("Info", "Warning", "Error", "Verbose", "Debug")]
#           [String]$Type,

# 		  [switch]$TeeToSTDOUT
#     )

#     switch ($Type) {
#         "Info" { [int]$Type = 1 }
#         "Warning" { [int]$Type = 2 }
#         "Error" { [int]$Type = 3 }
#     }

#     # Create a log entry
#     $Content = "<![LOG[$Message]LOG]!>" +`
#     "<time=`"$(Get-Date -Format "HH:mm:ss.ffffff")`" " +`
#     "date=`"$(Get-Date -Format "M-d-yyyy")`" " +`
#     "component=`"$Component`" " +`
#     "context=`"$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)`" " +`
#     "type=`"$Type`" " +`
#     "thread=`"$([Threading.Thread]::CurrentThread.ManagedThreadId)`" " +`
#     "file=`"`">"


# 	if ("$Path" -eq "") {
#         Write-Warning "Won't log since Path is null!"
#         Write-Host "$Component : ($Type) $Message"
# 	} else {
#         if (!(Test-Path "$Path")) {
#             $PathFolder = $Path | Split-Path
#             $FileName = $Path | Split-Path -leaf
#             New-Item -Path $PathFolder -Name $FileName -ItemType File | Out-Null
# 		}
# 		for($retry=0; $retry -le $retryMax; $retry++){
#             if ($TeeToSTDOUT) {
#                 Write-Host "$Message"
# 			}
# 			try { # we retry a few times because there are sometimes IO problems...
# 				Write-Output $Content | Out-file "$Path" -append
# 				#Add-Content -Path $Path -Value $Content -ErrorAction Stop
# 				if ($retry -gt 0) { Write-Host "Written to log after $retry attempt" }
# 				break
# 			} catch {
#                 Write-Warning "An error occured trying to write to log file $Path."
# 				Write-Warning "Waiting 200ms and retrying ($retry / $retryMax)..."
# 				Start-Sleep -Milliseconds 200
# 			}
# 		}
# 	}
# }

function Write-Log {

    [CmdletBinding()]
    Param(
        [parameter(Mandatory = $false)]
        [String]$Path,

        [parameter(Mandatory = $true)]
        [String]$Message,

        [parameter(Mandatory = $true)]
        [String]$Component,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Info", "Warning", "Error", "Verbose", "Debug")]
        [String]$Type,

        [switch]$TeeToSTDOUT
    )
    $timestamp = Get-Date -Format "yyyy/MM/dd hh:mm:ss:fff"
    $line = "$timestamp [$($Component.PadRight(35))] ($($Type.PadRight(8))) : $Message"
    if ($TeeToSTDOUT) {
        Write-Host "$line"
    }
    Write-Output $line | Out-File $Path -Append
}


class Logger {
    [string] $Path
    [bool] $TeeToSTDOUT
    [string]$Component
    [LogLevel]$LogLevel

    Logger([string]$Path, [bool]$TeeToSTDOUT) {
        $this.Initialize($Path, $TeeToSTDOUT)
    }

    Logger([string]$Path) {
        $this.Initialize($Path, $true)
    }

    [Logger] GetChildLogger($Component) {
        $newLogger = [Logger]::new($this.Path, $this.TeeToSTDOUT)
        $newLogger.Component = $Component
        $newLogger.LogLevel = $this.LogLevel
        return $newLogger
    }

    Initialize([string]$Path, [bool]$TeeToSTDOUT) {
        $this.LogLevel = [LogLevel]::Info
        $this.Path = $Path
        $this.TeeToSTDOUT = $TeeToSTDOUT
        $this.Component = "Main"
        If (!(Test-Path $this.Path)) {
            $parent = $(Split-Path -Parent $this.Path)
            if (!(Test-Path $parent)){ New-Item -ItemType Directory $parent }
            Write-Output "" | Out-File $this.Path
        }
        $this.Debug('Logger started')

    }

    [void] SetLogLevel([LogLevel]$LogLevel) {
        $this.LogLevel = $LogLevel
    }

    [void] Info($Message) {
        $this.Log([LogLevel]::Info, $Message)
    }
    [void] Verbose($Message) {
        $this.Log([LogLevel]::Verbose, $Message)
    }
    [void] Debug($Message) {
        $this.Log([LogLevel]::Debug, $Message)
    }
    [void] Warning($Message) {
        $this.Log([LogLevel]::Warning, $Message)
    }
    [void] Error($Message) {
        $this.Log([LogLevel]::Error, $Message)
    }

    [void] Log([LogLevel]$Type, [string]$Message) {
        if ($this.LogLevel -ge $Type) {
            $this._Log($this.Path, $this.Component, $Message, $Type, $this.TeeToSTDOUT)
        }
    }

    [void] _Log($Path, $Component, $Message, $Type, $TeeToSTDOUT) {
        Write-Log $Path -Component $Component -Message $Message -Type $Type -TeeToSTDOUT:$TeeToSTDOUT
    }

    [string]_GetTimestamp() {
        return Get-Date -Format "yyy-MM-dd hh:mm:ss.fff"
    }
}


