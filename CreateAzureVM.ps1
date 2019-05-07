#This script is for creating a vm without a public ip, with all credentials used secured in key vault

#Define the parameters for the script
Param (

    [Parameter(Position=0,HelpMessage="Subscription ID to log in to")]

    [ValidateNotNullOrEmpty()]

    [string] $SubID = "44d9a18a-92e1-4d8d-bae4-f8aad05ac661",


    [Parameter(Position=1,HelpMessage="Tenant ID to log in to")]

    [ValidateNotNullOrEmpty()]

    [string] $TenantID = "db214e4f-1038-4036-b890-bcd6bf754309",

     
    [Parameter(Position=2,HelpMessage="Resource Group to deploy into")]

    [ValidateNotNullOrEmpty()]

    [string] $ResourceGroupName = "deploytestneu-rg",
    

    [Parameter(Position=3,HelpMessage="Azure Region to deploy to")]

    [ValidateNotNullOrEmpty()]

    [string] $LocationName = "northeurope",
        
    
    [Parameter(Position=4,HelpMessage="Vnet to deploy to")]

    [ValidateNotNullOrEmpty()]

    [string] $NetworkName = "vnet-prod-neu",


    [Parameter(Position=5,HelpMessage="Subnet to deploy to")]

    [ValidateNotNullOrEmpty()]

    [string] $SubnetName = "default",


    [Parameter(Position=6,HelpMessage="Storage Account for boot diagnostics")]

    [ValidateNotNullOrEmpty()]

    [string] $DiagAccountName = "deploytestneudiag",


    [Parameter(Position=7,HelpMessage="Name for the Virtual Machine")]

    [ValidateNotNullOrEmpty()]

    [string] $VMName = "deptest01",


    [Parameter(Position=8,HelpMessage="Virtual Machine Size, defaults to Standard_DS2_v2 - use Get-AzVMSize to find what's available in each region")]

    [ValidateNotNullOrEmpty()]

    [string] $VMSize = "Standard_DS2_v2",


    [Parameter(Position=9,HelpMessage="Licence Type - Default None, set to Windows_Server to use Hybrid Use Benefit")]

    [ValidateNotNullOrEmpty()]

    [string] $LicenceType = "None",


    [Parameter(Position=10,HelpMessage="Server OS Image SKU e.g. 2019-Datacenter, 2016-Datacenter, 2012-R2-Datacenter, default is 2016-Datacenter-smalldisk")]

    [ValidateNotNullOrEmpty()]

    [string] $ServerOS = "2016-Datacenter-smalldisk",

    
    [Parameter(Position=11,HelpMessage="Specific image version, default is latest")]

    [ValidateNotNullOrEmpty()]

    [string] $ImgVersion = "latest",


    [Parameter(Position=12,HelpMessage="Name of the KeyVault to retrieve secrets from")]

    [ValidateNotNullOrEmpty()]

    [string] $KV = "badassinfraprodneukv",
    

    [Parameter(Position=13,HelpMessage="Name of the secret in the Keyvault containing the local administrator username")]

    [ValidateNotNullOrEmpty()]

    [string] $UsernameSecret = "LocalAdminUsername",


    [Parameter(Position=14,HelpMessage="Name of the secret in the Keyvault containing the local administrator password")]

    [ValidateNotNullOrEmpty()]

    [string] $PasswordSecret = "BuildPassword",


    [Parameter(Position=15,HelpMessage="Name of the secret storing the Service Principal name in Keyvault")]

    [ValidateNotNullOrEmpty()]

    [string] $SPName = "BuildSp",


    [Parameter(Position=16,HelpMessage="Name of the SP Secret in KeyVault")]

    [ValidateNotNullOrEmpty()]

    [string] $SPSecretName = "BuildSpSecret"

)

#Suppress Breaking Change Warnings because they're annoying
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

#Log in to Azure using the Managed Identity of the VM
#Connect-AzAccount -Identity -Subscription $SubID

#Retrieve Service Principal Secrets and create credential object
$SPCredential = New-Object System.Management.Automation.PSCredential ((Get-AzKeyVaultSecret -VaultName $KV -Name $SPName).SecretValueText, (Get-AzKeyVaultSecret -VaultName $KV -Name $SPSecretName).SecretValue)

#Retrive the local admin username and password secrets and create a credential object
$LocalCredentials = New-Object System.Management.Automation.PSCredential ((Get-AzKeyVaultSecret -VaultName $KV -Name $UsernameSecret).SecretValueText, (Get-AzKeyVaultSecret -VaultName $KV -Name $PasswordSecret).SecretValue)

#Log in to Azure using the Service Principal
Connect-AzAccount -ServicePrincipal -Credential $SPCredential -Subscription $SubID -Tenant $TenantID

#Name the NIC the VMName with "nic" appended to the end
$NICName = $VMName + "nic"

#We need to load the vnet object into a variable, then create the NIC and attach to the vnet
$Vnet = Get-AzVirtualNetwork -Name $NetworkName

#Get the ID of the subnet named in SubnetID variable
$SubnetID = (Get-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $Vnet).Id

#Create the NIC and store the object in a variable
$NIC = New-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -Location $LocationName -SubnetId $SubnetID

#Optional code for setting the  IP as static
$NIC| Set-AzNetworkInterfaceIpConfig -Name $NIC.IpConfigurations[0].Name -PrivateIpAddress $NIC.IpConfigurations[0].PrivateIpAddress -SubnetId $SubnetID -Primary
$NIC| Set-AzNetworkInterface
#/Optional code for setting the  IP as static

#Set the Computer (Host) name to be the same as the VM Name
$ComputerName = $VMName

#Put all the configuration for the VM into a variable
$VirtualMachine = New-AzVMConfig -VMName $VMName -VMSize $VMSize
$VirtualMachine = Set-AzVMOperatingSystem -VM $VirtualMachine -Windows -ComputerName $ComputerName -Credential $LocalCredentials -ProvisionVMAgent -EnableAutoUpdate
$VirtualMachine = Add-AzVMNetworkInterface -VM $VirtualMachine -Id $NIC.Id
$VirtualMachine = Set-AzVMSourceImage -VM $VirtualMachine -PublisherName 'MicrosoftWindowsServer' -Offer 'WindowsServer' -Skus $ServerOS -Version $ImgVersion
$VirtualMachine = Set-AzVMBootDiagnostic -VM $VirtualMachine -Enable -ResourceGroupName $ResourceGroupName -StorageAccountName $DiagAccountName

#Create the VM using this configuration
New-AzVM -ResourceGroupName $ResourceGroupName -Location $LocationName -VM $VirtualMachine -LicenseType $LicenceType -Verbose