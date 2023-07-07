# global settings setup both for running unit test and used by the main application
# all thoses parameters car be overwritten within :
# - $ProjectRoot\config.ps1 : for main application
# - $ProjectRoot\config.test.ps1 : for unit tests application
#
# this offer the ability, if needed to have different platforms (vCenter, MECM, Horizon) for running tests and production code

$ProjectRoot = $PSScriptRoot
$LogDir = "$ProjectRoot/log"
$LibDir = "$ProjectRoot/lib"

$TestDir = "$PSScriptRoot/tests"
$TestDataPath = "$TestDir/data"
$TestLogDir = "$TestDir/log"
$TestLogFile = "$LogDir/TestLog.log"


$CREDENTIALS_TARGET_HORIZON = "VDI-Pool-Updater-HORIZON"
$CREDENTIALS_TARGET_VCENTER = "VDI-Pool-Updater-VCenter-Server-Account"
$CREDENTIALS_TARGET_MECM    = "VDI-Pool-Updater-MECM-Account"

# Time in minutes until the TS execution will be considered has not working (timout).
# The time measured here start only after initial detection of the TS deployment (when step1 is reached)
# which can takes 10 more minutes
$SMS_TS_EXECUTION_MAX_EXECUTION_MINUTES = 60
$SMS_TS_SUCCESS_ActionName = "TS Finished Successfully"
$SMS_TS_FAILURE_ActionName = "TS Execution Failed"


$MAX_VM_DEPLOYMENT_RETRIES = 4

$LOGLEVEL = "Info"  # Error, Info, Verbose, Debug