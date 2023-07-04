Import-Module VMware.VimAutomation.Core

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls, [Net.SecurityProtocolType]::Tls11, [Net.SecurityProtocolType]::Tls12
class VMDriverVCenter {
    [string] $Server
    [string] $Port
    [Logger] $Logger
    [PSCredential] $Credentials
    [bool] $OpenConsole

    VMDriverVCenter($Server, $Port, $Credential, $Logger){
        $this.Server = $Server
        $this.Port = $Port
        $this.Credentials = $Credential
        $this.Logger = $Logger
        $this.Connect()
    }

    Connect(){
        $this.Logger.Info("Connecting to $($this.Server):$($this.Port)")
        Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false

        VMware.VimAutomation.Core\Connect-VIServer -Server $this.Server -Port $this.Port -Protocol https -Credential $this.Credentials
        $this.Logger.Verbose("Connected to $($this.Server):$($this.Port)")
    }

    StopVM([string] $VMName){
        try {
            $this.Logger.Debug("Retrieving VM object")
            $vm = VMware.VimAutomation.Core\Get-VM -Name $VMName

            if ($vm.PowerState -eq "PoweredOn") {
                $this.Logger.Verbose("Powering off VM")
                $vm | VMware.VimAutomation.Core\Stop-vm -Confirm:$false | Out-Null
            }
            $this.Logger.Verbose("Done")
        } catch {
            $this.Logger.Error($_)
            return
        }

    }

    StartPXE([string] $VMName){
        $this.StartPXE($VMName, $false)
    }
    StartPXE([string] $VMName, $OpenConsole){
        $this.Logger.Info("Booting VM '$VMName' on PXE")
        $vm = $null
        try {
            $this.Logger.Debug("Retrieving VM object")
            $vm = VMware.VimAutomation.Core\Get-VM -Name $VMName

            if ($vm.PowerState -eq "PoweredOn") {
                $this.Logger.Verbose("Powering off VM first")
                $vm | VMware.VimAutomation.Core\Stop-vm -Confirm:$false | Out-Null
            }

            $this.Logger.Debug("Retrieving VM object")

            Start-Sleep -Seconds 5

            $this.Logger.Verbose("Setting boot mode to PXE")
            $this._SetVMBootMode('PXE', $VMName)

            #Start-Sleep -Seconds 3
            $this.Logger.Debug("Retrieving VM object")
            $vm = VMware.VimAutomation.Core\Get-VM -Name $VMName

            $this.Logger.Verbose("Starting VM")
            $vm | VMware.VimAutomation.Core\Start-vm -Confirm:$false | Out-Null

            if ($OpenConsole) {
                $this.Logger.Verbose("Opening Console Window")
                Open-VMConsoleWindow -VM $VMName
            }
            $this.Logger.Verbose("Waiting 30 seconds before reverting boot to disk")
            Start-Sleep -Seconds 30

            $this.Logger.Verbose("Reverting boot to disk")
            $this._SetVMBootMode("Disk", $VMName)
        } catch {
            $this.Logger.Error($_)
            throw $_
        }

    }

    [void] _SetVMBootMode($Mode, $VMName){
        $this.Logger.Debug("Setting VM '$VMName' Boot mode '$Mode'")
        $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
        $spec.extraConfig += New-Object VMware.Vim.OptionValue
        $spec.extraConfig[0].key = "bios.bootDeviceClasses"

        if ($Mode -eq "Disk") {
            $spec.extraConfig[0].value = "allow:hd,cd,fd"

        }
        elseif ($Mode -eq "PXE") {
            $spec.extraConfig[0].value = "allow:net"
        }

        (Get-View (VMware.VimAutomation.Core\Get-VM -Name $VMName).ID).ReconfigVM_Task($spec)  | Out-Null
    }
}