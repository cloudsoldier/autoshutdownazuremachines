<#
    .SYNOPSIS
        This Azure Automation runbook adds the AutoShutdownSchedule tag to any VMs missing it in a subscription 

    .DESCRIPTION
        The runbook searches a subscription for VMs without a tag named "AutoShutdownSchedule" and having a value defining the schedule, 
        e.g. "10PM -> 6AM". When it finds an untagged VM it adds the tag named above and sets the value to "18:00->09:00,Saturday,Sunday"

        This is a PowerShell runbook, as opposed to a PowerShell Workflow runbook.

        This runbook requires the "Azure" and "AzureRM.Resources" modules which are present by default in Azure Automation accounts.
        For detailed documentation and instructions, see: 
        
        https://automys.com/library/asset/scheduled-virtual-machine-shutdown-startup-microsoft-azure

    
    .INPUTS
        None.

    .OUTPUTS
        Human-readable informational and error messages produced during the job. Not intended to be consumed by another runbook.

Edited by Paul Bossons 15th Jan 2020.  Amended the script to use the AZ module and removed the refrences to Azure and AzureRM modules.
#>

$VERSION = "1.0"

# Define function to check current time against specified range
function CheckScheduleEntry ([string]$TimeRange)
{    
    # Initialize variables
    $rangeStart, $rangeEnd, $parsedDay = $null
    $currentTime = (Get-Date).ToUniversalTime()
    $midnight = $currentTime.AddDays(1).Date            

    try
    {
        # Parse as range if contains '->'
        if($TimeRange -like "*->*")
        {
            $timeRangeComponents = $TimeRange -split "->" | foreach {$_.Trim()}
            if($timeRangeComponents.Count -eq 2)
            {
                $rangeStart = Get-Date $timeRangeComponents[0]
                $rangeEnd = Get-Date $timeRangeComponents[1]
    
                # Check for crossing midnight
                if($rangeStart -gt $rangeEnd)
                {
                    # If current time is between the start of range and midnight tonight, interpret start time as earlier today and end time as tomorrow
                    if($currentTime -ge $rangeStart -and $currentTime -lt $midnight)
                    {
                        $rangeEnd = $rangeEnd.AddDays(1)
                    }
                    # Otherwise interpret start time as yesterday and end time as today   
                    else
                    {
                        $rangeStart = $rangeStart.AddDays(-1)
                    }
                }
            }
            else
            {
                Write-Output "`tWARNING: Invalid time range format. Expects valid .Net DateTime-formatted start time and end time separated by '->'" 
            }
        }
        # Otherwise attempt to parse as a full day entry, e.g. 'Monday' or 'December 25' 
        else
        {
            # If specified as day of week, check if today
            if([System.DayOfWeek].GetEnumValues() -contains $TimeRange)
            {
                if($TimeRange -eq (Get-Date).DayOfWeek)
                {
                    $parsedDay = Get-Date "00:00"
                }
                else
                {
                    # Skip detected day of week that isn't today
                }
            }
            # Otherwise attempt to parse as a date, e.g. 'December 25'
            else
            {
                $parsedDay = Get-Date $TimeRange
            }
        
            if($parsedDay -ne $null)
            {
                $rangeStart = $parsedDay # Defaults to midnight
                $rangeEnd = $parsedDay.AddHours(23).AddMinutes(59).AddSeconds(59) # End of the same day
            }
        }
    }
    catch
    {
        # Record any errors and return false by default
        Write-Output "`tWARNING: Exception encountered while parsing time range. Details: $($_.Exception.Message). Check the syntax of entry, e.g. '<StartTime> -> <EndTime>', or days/dates like 'Sunday' and 'December 25'"   
        return $false
    }
    
    # Check if current time falls within range
    if($currentTime -ge $rangeStart -and $currentTime -le $rangeEnd)
    {
        return $true
    }
    else
    {
        return $false
    }
    
} # End function CheckScheduleEntry


# Main runbook content
try
{
    $currentTime = (Get-Date).ToUniversalTime()
    Write-Output "Runbook started. Version: $VERSION"
    Write-Output "Current UTC/GMT time [$($currentTime.ToString("dddd, yyyy MMM dd HH:mm:ss"))] will be checked against schedules"

    
#If you used a custom RunAsConnection during the Automation Account setup this will need to reflect that.
$connectionName = "AzureRunAsConnection" 
try
{
 #Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         
    
    "Logging in to Azure..."
    Login-AzAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 

}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

    # Get a list of all virtual machines in subscription
    $resourceManagerVMList = @(Get-AzResource | where {$_.ResourceType -like "Microsoft.*/virtualMachines"} | sort Name)

    # Get resource groups that are tagged for automatic shutdown of resources
    $taggedResourceGroups = @(Get-AzResourceGroup | where {$_.Tags.AutoShutdownSchedule})
    $taggedResourceGroupNames = @($taggedResourceGroups | select -ExpandProperty ResourceGroupName)
    Write-Output "Found [$($taggedResourceGroups.Count)] schedule-tagged resource groups in subscription"    

    # Then assert its correct power state based on the assigned schedule (if present)
    Write-Output "Processing [$($resourceManagerVMList.Count)] virtual machines found in subscription"
    foreach($vm in $resourceManagerVMList)
    {
        $schedule = $null

        # Check for direct tag or group-inherited tag
        if($vm.ResourceType -eq "Microsoft.Compute/virtualMachines" -and $vm.Tags.AutoShutdownSchedule)
        {
            # VM has direct tag (possible for resource manager deployment model VMs). Prefer this tag schedule.
            $schedule = $vm.Tags.AutoShutdownSchedule
            Write-Output "[$($vm.Name)]: Found direct VM schedule tag with value: $schedule"
            
        }
        else
        {
            # No direct or inherited tag. Updating this VM.
			$taglist = $vm.tags
			$taglist += @{AutoShutdownSchedule=""}
            
            #only update if no locks are present
            if (Get-AzResourceLock -ResourceGroupName $vm.ResourceGroupName -ResourceName $vm.name -ResourceType "Microsoft.Compute/VirtualMachines")
            {
                Write-Output "[$($vm.Name)]: Not tagged for shutdown directly, but has Resource Lock.  NOT UPDATED."
            }
            elseif ((get-azvm -ResourceGroupName $vm.ResourceGroupName -ResourceName $vm.name).ProvisioningState -eq 'Failed')
            {
                Write-Output "[$($vm.Name)]: Not tagged for shutdown directly, but has Deployment Failed.  NOT UPDATED."
            }
            else
            {
                Set-AzResource -ResourceGroupName $vm.ResourceGroupName -Name $vm.name -ResourceType "Microsoft.Compute/VirtualMachines" -Tag $taglist -Force
                Write-Output "[$($vm.Name)]: Not tagged for shutdown directly, adding default schedule."

            }
			
            continue
        }

        # Parse the ranges in the Tag value. Expects a string of comma-separated time ranges, or a single time range
        $timeRangeList = @($schedule -split "," | foreach {$_.Trim()})
        
        # Check each range against the current time to see if any schedule is matched
        foreach($entry in $timeRangeList)
        {
           # if((CheckScheduleEntry -TimeRange $entry) -eq $true)
           # {
                break
           # }
        }
    }

    Write-Output "Finished processing virtual machine schedules"
}
catch
{
    $errorMessage = $_.Exception.Message
    throw "Unexpected exception: $errorMessage"
}
finally
{
    Write-Output "Runbook finished (Duration: $(("{0:hh\:mm\:ss}" -f ((Get-Date).ToUniversalTime() - $currentTime))))"
}