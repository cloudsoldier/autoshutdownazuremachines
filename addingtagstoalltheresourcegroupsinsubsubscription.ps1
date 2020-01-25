
##This script will add tags to all Resourcegrous in the specified subscription.

 #Add agreed tags 
# Get a list of all ResourceGroups in subscription
    $resourceGroups = Get-AzResourceGroup
      Write-Output "Processing [$($resourceGroups.Count)] Resourcegroups found in subscription"


foreach($rg in $resourceGroups)
    {
        $taglist = $rg.tags
		$taglist += @{Sponsor="";Owner="";DXC_AutoDeploy="";Expiry_Date="";Product="";Shared="";Environment="";Client="";Server_Role="";WBS="";Deployed_By=""}
       

        Set-AzResourceGroup -ResourceGroupName $rg.ResourceGroupName -Tag $taglist
} 
