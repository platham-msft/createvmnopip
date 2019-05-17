<#
.SYNOPSIS
Script to create a vm from a marketplace image  with no public IP retrieving all required credentials from secrets stored in keyvault or prompting the user for them if no keyvault specified

.DESCRIPTION
If you wanted to make this really short, you could.

.PARAMETER SubID 
Subscription ID to log in to

.PARAMETER TenantID 
Tenant ID to log in to

.PARAMETER ResourceGroupName
Resource Group to deploy to

.PARAMETER LocationName 
Azure Region to deploy to

.PARAMETER NetworkName
Vnet to deploy to

.PARAMETER SubnetName
Subnet to deploy to

.PARAMETER StaticIP 
Static Private IP required - default is False

.PARAMETER DiagAccountName
Storage Account for boot diagnostics

.PARAMETER VMName
Name for the Virtual Machine

.PARAMETER VMSize
Virtual Machine Size, defaults to Standard_DS2_v2 - use Get-AzVMSize to find what's available in each region

.PARAMETER LicenseType
License Type - Default None, set to Windows_Server to use Hybrid Use Benefit

.PARAMETER ImgVersion
Specific image version, default is latest

.PARAMETER KV
Name of the KeyVault to retrieve secrets from

.PARAMETER UsernameSecret
Name of the secret in the Keyvault containing the local administrator username

.PARAMETER PasswordSecret
Name of the secret in the Keyvault containing the local administrator password

.PARAMETER SPName
Name of the secret storing the Service Principal name in Keyvault

.PARAMETER SPSecretName
Name of the SP Secret in KeyVault

.PARAMETER ImageSKU
Image SKU - for Windows Server e.g. 2019-Datacenter, 2016-Datacenter or SQL e.g. Enterprise, Standard - Default is 2016-Datacenter-smalldisk

.PARAMETER ImagePublisher
Image Publisher, for Windows Server use MicrosoftWindowsServer but for SQL it's MicrosoftSQLServer

.PARAMETER ImageOffer
Image Offer, for just Windows Server use WindowsServer but for SQL it's e.g. SQL2017-WS2016 - Defaults to just WindowsServer

.EXAMPLE
.\CreateAzureOtherVM.ps1 -VmName deptest07
Create a VM named "deptest07" leaving everything else as default

.EXAMPLE
.\CreateAzureOtherVM.ps1 -VmName -deptest07 -LicenseType Windows_Server
Create a VM named "deptest07" and turn on Hybrid Use Benefit for Windows Server

.EXAMPLE
.\CreateAzureOtherVM.ps1 -VmName sqltest01 -ImagePublisher "MicrosoftSQLServer" -ImageOffer "SQL2017-WS2016" -ImageSKU "Standard" -StaticIP $true
Create a VM named "sqltest01" running Windows Server 2016 and SQL Server 2017 Standard with a static private IP address

.NOTES
    Author: Paul Latham
    Date:   7th May 2019
#>

#Define the parameters for the script
Param (

    [Parameter(Position=0,HelpMessage="Subscription ID to log in to")]

    [ValidateNotNullOrEmpty()]

    [string] $SubID = "44d9a18a-92e1-4d8d-bae4-f8aad05ac661",


    [Parameter(Position=1,HelpMessage="Tenant ID to log in to")]

    [ValidateNotNullOrEmpty()]

    [string] $TenantID = "db214e4f-1038-4036-b890-bcd6bf754309",

     
    [Parameter(Position=2,HelpMessage="Resource Group to deploy to")]

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


    [Parameter(Position=6,HelpMessage="Static Private IP required")]

    [ValidateNotNullOrEmpty()]

    [boolean] $StaticIP = $false,


    [Parameter(Position=7,HelpMessage="Storage Account for boot diagnostics")]

    [ValidateNotNullOrEmpty()]

    [string] $DiagAccountName = "deploytestneudiag",


    [Parameter(Position=8,HelpMessage="Name for the Virtual Machine")]

    [ValidateNotNullOrEmpty()]

    [string] $VMName = "deptest42",


    [Parameter(Position=9,HelpMessage="Virtual Machine Size, defaults to Standard_DS2_v2 - use Get-AzVMSize to find what's available in each region")]

    [ValidateNotNullOrEmpty()]

    [string] $VMSize = "Standard_DS2_v2",


    [Parameter(Position=10,HelpMessage="License Type - Default None, set to Windows_Server to use Hybrid Use Benefit")]

    [ValidateNotNullOrEmpty()]

    [string] $LicenseType = "None",

    
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

    [string] $SPSecretName = "BuildSpSecret",


    [Parameter(Position=17,HelpMessage="Image SKU - for Windows Server e.g. 2019-Datacenter, 2016-Datacenter or SQL e.g. Enterprise, Standard - Default is 2016-Datacenter-smalldisk")]

    [ValidateNotNullOrEmpty()]

    [string] $ImageSKU = "2016-Datacenter-smalldisk",


    [Parameter(Position=18,HelpMessage="Image Publisher, for Windows Server use MicrosoftWindowsServer but for SQL it's MicrosoftSQLServer")]

    [ValidateNotNullOrEmpty()]

    [string] $ImagePublisher = "MicrosoftWindowsServer",


    [Parameter(Position=19,HelpMessage="Image Offer, for just Windows Server use WindowsServer but for SQL it's e.g. SQL2017-WS2016 - Defaults to just WindowsServer")]

    [ValidateNotNullOrEmpty()]

    [string] $ImageOffer = "WindowsServer"

)

#Suppress Breaking Change Warnings because they're annoying
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

#Log in to Azure using the Managed Identity of the VM (this only works for machines running in Azure!)
Connect-AzAccount -Identity -Subscription $SubID

#Retrieve Service Principal Secrets and create credential object
$SPCredential = New-Object System.Management.Automation.PSCredential ((Get-AzKeyVaultSecret -VaultName $KV -Name $SPName).SecretValueText, (Get-AzKeyVaultSecret -VaultName $KV -Name $SPSecretName).SecretValue)

#Retrive the local admin username and password secrets and create a credential object
$LocalCredentials = New-Object System.Management.Automation.PSCredential ((Get-AzKeyVaultSecret -VaultName $KV -Name $UsernameSecret).SecretValueText, (Get-AzKeyVaultSecret -VaultName $KV -Name $PasswordSecret).SecretValue)

#Log in to Azure using the Service Principal
Connect-AzAccount -ServicePrincipal -Credential $SPCredential -Subscription $SubID -Tenant $TenantID

#Name the NIC the VMName with "nic" appended to the end
$NICName = $VMName + "nic"

#We need to load the vnet object into a variable if we are going to look up the subnet id from the name
$Vnet = Get-AzVirtualNetwork -Name $NetworkName

#Get the ID of the subnet named in SubnetName and store it in the SubnetID variable
$SubnetID = (Get-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $Vnet).Id

#Create the NIC and store the object in a variable
$NIC = New-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -Location $LocationName -SubnetId $SubnetID

#Code for setting the  IP as static
If ($StaticIP -eq $true)
{
$NIC| Set-AzNetworkInterfaceIpConfig -Name $NIC.IpConfigurations[0].Name -PrivateIpAddress $NIC.IpConfigurations[0].PrivateIpAddress -SubnetId $SubnetID -Primary
$NIC| Set-AzNetworkInterface
}

#Set the Computer (Host) name to be the same as the VM Name
$ComputerName = $VMName

#Put all the configuration for the VM into a variable
$VirtualMachine = New-AzVMConfig -VMName $VMName -VMSize $VMSize
$VirtualMachine = Set-AzVMOperatingSystem -VM $VirtualMachine -Windows -ComputerName $ComputerName -Credential $LocalCredentials -ProvisionVMAgent -EnableAutoUpdate
$VirtualMachine = Add-AzVMNetworkInterface -VM $VirtualMachine -Id $NIC.Id
$VirtualMachine = Set-AzVMSourceImage -VM $VirtualMachine -PublisherName $ImagePublisher -Offer $ImageOffer -Skus $ImageSKU -Version $ImgVersion
$VirtualMachine = Set-AzVMBootDiagnostic -VM $VirtualMachine -Enable -ResourceGroupName $ResourceGroupName -StorageAccountName $DiagAccountName
$VirtualMachine = Add-AzVMDataDisk -VM $VirtualMachine -LUN 0 -Caching ReadOnly -DiskSizeinGB 32 -CreateOption Empty

#Create the VM using this configuration
New-AzVM -ResourceGroupName $ResourceGroupName -Location $LocationName -VM $VirtualMachine -LicenseType $LicenseType -Verbose

#If we are using a SQL Server image install the SQL IaaS Agent
If ($ImagePublisher -eq "MicrosoftSQLServer") {Set-AzVMSqlServerExtension -ResourceGroupName $ResourceGroupName -VMName $VMName -name "SQLIaasExtension" -Version 2.0 -Location $LocationName}