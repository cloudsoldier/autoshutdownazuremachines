This script will add tags to all the virtuals machines in the subscription.
 #Add agreed tags 
# Get a list of all virtual machines in subscription
    $resourceManagerVMList = @(Get-AzResource | where {$_.ResourceType -like "Microsoft.*/virtualMachines"} | sort Name)

      Write-Output "Processing [$($resourceManagerVMList.Count)] virtual machines found in subscription"


foreach($vm in $resourceManagerVMList)
    {
        $taglist = $vm.tags
		$taglist += @{Sponsor="";Owner="";DXC_AutoDeploy="";Expiry_Date="";Product="";Shared="";Environment="";Client="";Server_Role="";WBS="";Instance="";Deployed_By=""}
        $schedule = $null

        # Check for direct tag or group-inherited tag
        if($vm.ResourceType -eq "Microsoft.Compute/virtualMachines")
        {
            # The AutoShutdownSchedule Tag has a null value.
            Set-AzResource -ResourceGroupName $vm.ResourceGroupName -Name $vm.name -ResourceType "Microsoft.Compute/VirtualMachines" -Tag $taglist -Force
            Write-Output "[$($vm.Name)]: Added the default Tags."
            continue
        }
        else
        {
            Write-Output "[$($vm.Name)]: [$($vm.Tags.AutoShutdownSchedule)] Tag value already exists. No action is neccessary"   
            }
			
            continue
       }  
