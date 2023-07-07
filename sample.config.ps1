# override desired value that are set on config.global.ps1
# variables defined here are uses by main code only.
# unit tests have their own config file that must be defined (see comments in config.global.ps1)
$VDI_SERVER = "<VDI SERVER FQDN>"
$VCENTER_SERVER = "<VCENTER SERVER FQDN>"
$VCENTER_PORT = 443

$SMS_SERVER = "<SMS SERVER>"
$SMS_SITECODE = "<SITE CODE>"
$SMS_MONITORED_TS_NAME = "<TS NAME TO MONITOR WHEN THE VDI DEPLOYMENT OCCURS>"
$SMS_TS_SUCCESS_ActionName = "TS Finished Successfully"
$SMS_TS_FAILURE_ActionName = "TS Execution Failed"


$VDI_POOLS_AVAILABLES = @(
    [PSCustomObject]@{
        Name = "<POOL_NAME_1>"
        VM   = "<VM_MASTER_1>"
    },
    [PSCustomObject]@{
        Name = "<POOL_NAME_2>"
        VM   = "<VM_MASTER_2>"
    }
)