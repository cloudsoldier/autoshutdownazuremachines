
To set tags to all the resource groups in a subscription 


$resourceGroups = Get-AzResourceGroup

foreach($rg in $resourceGroups){
$taglist = $rg.tags
              $taglist += @{Tag1="Tag1Value";Tag2="Tag2Value";Tag3="Tag3Value"}

Set-AzResourceGroup -ResourceGroupName $rg.ResourceGroupName -Tag $taglist
} 
