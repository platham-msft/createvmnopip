#Log in to my subscription in my PLDEMOORG Tenant
Connect-AzAccount -SubscriptionID 44d9a18a-92e1-4d8d-bae4-f8aad05ac661 -TenantID db214e4f-1038-4036-b890-bcd6bf754309

#Log in to my subscription in my PLDEMOORG Tenant using the Managed Identity of the VM this is running on (only works in Azure)
Connect-AzAccount -SubscriptionID 44d9a18a-92e1-4d8d-bae4-f8aad05ac661 -TenantID db214e4f-1038-4036-b890-bcd6bf754309 -Identity

#Create a Windows 10 VM joined to zeus domain using the credentials in my keyvault
.\CreateWin10.ps1 `
-ResourceGroupName deploytestneu-rg `
-ADDomain zeus.badasscomputers.co.uk `
-LicenseType Windows_Client `
-LocationName northeurope `
-NetworkName vnet-prod-neu `
-SubnetName default `
-DiagAccountName deploytestneudiag `
-KV badassinfraprodneukv `
-ImageID "/subscriptions/44d9a18a-92e1-4d8d-bae4-f8aad05ac661/resourceGroups/rg-infra-dev-neu/providers/Microsoft.Compute/galleries/GalleryDevNeu/images/Win10Client"