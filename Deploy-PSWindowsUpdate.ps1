<#
.SYNOPSIS
    This script will automatically install all avaialable windows updates on a device and will automatically reboot if needed, after reboot, windows updates will continue to run until no more updates are available.

.PARAMETER URL
    User the Computer parameter to specify the Computer to remotely install windows updates on.

.PARAMETER PSWinLocation
    Location of PSWindowsUpdate Module directory on your network share.
        
.PARAMETER JobThrottleCount
    Maximum amount of concurrent background jobs allowed. (Too many will max local resources)
#>

[CmdletBinding()]

param (

    [Parameter(Mandatory=$true,Position=1)]
    [String[]] $Computername,

    [Parameter(DontShow)]
    [String] $PSWinLocation = "\\Server01\EnterpriseServices\Modules\PSWindowsUpdate",

    [Parameter(ValueFromPipeline=$true)]
    [String]$JobThrottleCount = 10
)

function UpdateWindows {

    foreach($Computer in $Computername) {

        $i=0
        $j=0

        #Install PSWindows updates module
        if(!(Test-Path "\\$Computer\C$\Windows\System32\WindowsPowerShell\v1.0\Modules\PSWindowsUpdate")) {

            Copy-Item -Path $PSWinLocation -Destination "\\$Computer\C$\Windows\System32\WindowsPowerShell\v1.0\Modules" -Recurse -Force
        }

        While(@(Get-Job -State Running).Count -ge $JobThrottleCount) {
    
            Start-Sleep 1
        }

        Write-Progress -Activity "Begin Windows Update Processes..." -Status ("Percent Complete:" + "{0:N0}" -f ((($i++) / $Computername.count) * 100) + "%") -CurrentOperation "Processing $(eaf))..." -PercentComplete ((($j++) / $Names.count) * 100)
   
    
        Start-Job {

            Do {

                Do {
    
                    $Session = New-PSSession -ComputerName $Computer
                    "Reconnecting remotely to $Computer"
                    Sleep -Seconds 5
                } Until ($Session.State -Match "Opened")

                #Retrieves a list of available updates
                Write-Output "Checking for new updates available on $using:Computer"

                $Updates = Invoke-Command -SessionName $Session { 
                
                    Get-WUlist -Verbose 
                }
                
                #Counts how many updates are available
                $UpdateNumber = ($Updates.KB).Count

                #If there are available updates proceed with installing the updates and then reboot the remote machine
                if($Updates -ne $null) {

                    #Remote command to install windows updates, creates a scheduled task on remote computer
                    $Script = {

                        Import-Module PSWindowsUpdate
                        Get-WindowsUpdate -AcceptAll -Install | Out-File C:\PSWindowsUpdate.log
                    }

                    Invoke-WUjob -ComputerName $using:Computer -Script $Script -Confirm:$false -RunNow

                    #Show update status until the amount of installed updates equals the same as the amount of updates available
                    Sleep -Seconds 30

                    Do {
    
                        $UpdateStatus = Get-Content "\\$using:Computer\C$\PSWindowsUpdate.log"
                        Write-Output "Currently processing the following update:"

                        Get-Content "\\$using:Computer\C$\PSWindowsUpdate.log" | Select-Object -Last 1

                        Sleep -Seconds 10

                        $ErrorActionPreference = ‘SilentlyContinue’
                        $InstalledNumber = ([Regex]::Matches($UpdateStatus, "Installed" )).Count
                        $ErrorActionPreference = ‘Continue’
                    } Until ($InstalledNumber -eq $UpdateNumber)

                    #Restarts the remote computer and waits till it starts up again
                    Write-Output "Restarting remote computer"
                        
                    Restart-Computer -Wait -ComputerName $using:Computer -Force
                }
            } Until($Updates -eq $null)
        } -Name "Windows Update [$using:Computer]"
    }

    $Jobs = Get-Job | Where { $_.State -eq "Running" }
    $Total = $Jobs.Count
    $Running = $Jobs.Count

    While($Running -gt 0){

        Write-Progress -Activity "Installing Windows Updates (Awaiting Results: $(($Running)))..." -Status ("Percent Complete:" + "{0:N0}" -f ((($Total - $Running) / $Total) * 100) + "%") -PercentComplete ((($Total - $Running) / $Total) * 100) -ErrorAction SilentlyContinue
        $Running = (Get-Job | Where { $_.State -eq "Running" }).Count
    }
}

#Call main function 
UpdateWindows | Receive-Job -Wait -AutoRemoveJob

#Removes schedule task from computer
Invoke-Command -ComputerName $Computername -ScriptBlock {

    Unregister-ScheduledTask -TaskName PSWindowsUpdate -Confirm:$false
}
