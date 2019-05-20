<#
.SYNOPSIS
Script to create a vm from a marketplace or custom image with no public IP retrieving all required credentials from secrets stored in keyvault or prompting the user for them if no keyvault specified

.DESCRIPTION
Log in to Azure first using Connect-AzAccount or if you're using an AzureVM with a Managed Identity specify UseMachineIdentity to be true.

If you don't specify a Service Principal and you're logging in manually, don't bother specifying the SubscriptionID or TenantID, make sure you're in the right context before calling this script

If you are using a Service Principal and don't specify the Subscription or Tenant it will use them from your current context

The ID you initially log in with is used to retrieve the Service Principal to do the actual creation with along with the local username and password and the  AD username and password
Unless you have specified UseMachineIdentity to be True, in which case the Managed Identity will be used

The idea of this is so you don't have to give the Service Principal access to Keyvault. If you're using a Managed Identity for the initial log in, give it access to the Key Vault!

If you don't give a key vault name, you will be prompted for the required credentials (and the whole script will run in the initial login context)

If you don't specify an AD Domain to join, it will skip that part.

Scenarios that should work:
Manual log in, retrieve secrets from KV, build with SP
 UseMachineIdentity False, Define KV, Skipsplogin False
Manual log in, specify credentials, build with Manual log in
 UseMachineIdentity False, don't define KV
Machine log in, retrieve secrets from KV, build with SP
 UseMachineIdentity True, Define KV, SkipSpLogin False
Machine log in, specify credentials, build with Machine log in
 UseMachineIdentity True, don't define KV, SkipSpLogin True
Machine log in, retrieve credentials from kv, build with Machine log in
 UseMachineIdentity True, define kv, SkipSpLogin True
Manual log in, retrieve credentials from kv, build with Manual log in
 UseMachineIdentity False, define kv, SkipSpLogin True

.PARAMETER SubscriptionID 
Subscription ID to log in to if using Service Principal

.PARAMETER TenantID 
Tenant ID to log in to if using Service Principal

.PARAMETER ResourceGroupName
Resource Group to deploy to

.PARAMETER LocationName 
Azure Region to deploy to

.PARAMETER NetworkName
Vnet to deploy to

.PARAMETER SubnetName
Subnet to deploy to

.PARAMETER StaticIP 
Set to $true if a static Private IP is required - default is $false

.PARAMETER DiagAccountName
Storage Account for boot diagnostics

.PARAMETER VMName
Name for the Virtual Machine

.PARAMETER VMSize
Virtual Machine Size, defaults to Standard_DS2_v2 - use Get-AzVMSize to find what's available in each region

.PARAMETER LicenseType
License Type - Set to Windows_Server to use Hybrid Use Benefit, Windows_Client if it's a Client OS or None for PAYG Server Licensing which is the default

.PARAMETER SubnetID
Specific the Subnet ID if you don't have the rights to read the vnet into a variable for us to discover the ID from the name

.PARAMETER KV
Name of the KeyVault to retrieve secrets from

.PARAMETER UsernameSecret
Name of the secret in the Keyvault containing the local administrator username

.PARAMETER PassSecret
Name of the secret in the Keyvault containing the local administrator password

.PARAMETER SPName
Name of the secret storing the Service Principal name in Keyvault

.PARAMETER SPSecretName
Name of the SP Secret in KeyVault

.PARAMETER adUsernameSecretName
Name of the Keyvault Secret storing the Username to use to join AD Domain

.PARAMETER adPassSecretName
Name of the Keyvault Secret storing the Password to use to join AD Domain

.PARAMETER ADDomain
FQDN of the Active Directory Domain to join. Set to None to skip joining a domain

.PARAMETER ADOU
OU for the Computer Object to be created on the domain, in Distinguished Name format

.PARAMETER ImageID
Resource ID of Custom Image to use - if you set this the ImagePublisher/Offer/SKU and Version Parameters are ignored

.PARAMETER ImagePublisher
Image Publisher, for Windows Server use MicrosoftWindowsServer but for SQL it's MicrosoftSQLServer

.PARAMETER ImageOffer
Image Offer, for just Windows Server use WindowsServer but for SQL it's e.g. SQL2017-WS2016 - Defaults to just WindowsServer

.PARAMETER ImageSKU
Image SKU - for Windows Server e.g. 2019-Datacenter, 2016-Datacenter or SQL e.g. Enterprise, Standard - Default is 2016-Datacenter-smalldisk

.PARAMETER ImageVersion
Specific image version, default is latest

.PARAMETER UseManagedIdentity
Use managed identity to access KeyVault, default is False

.PARAMETER SkipSpLogin
Skip logging in with a service principal when using KeyVault and use the logged in context for the build

.EXAMPLE
.\CreateWin10.ps1 -ADDomain zeus.badasscomputers.co.uk -ADOU "OU=AADDC Computers,DC=zeus,DC=badasscomputers,DC=co,DC=uk" -LicenseType Windows_Client -VMName depwin10 -ImageID "/subscriptions/44d9a18a-92e1-4d8d-bae4-f8aad05ac661/resourceGroups/rg-infra-dev-neu/providers/Microsoft.Compute/galleries/GalleryDevNeu/images/Win10Client"
Create a VM named "depwin10" using the image specified, join it to the zeus.badasscomputers.co.uk domain in the AADC Computers OU and apply Windows Client licensing.

.NOTES
    Author: Paul Latham
    Date:   18th May 2019
#>

#Define the parameters for the script
Param (

    [Parameter(Position=0,HelpMessage="Subscription ID to log in to")]
    [ValidateNotNullOrEmpty()]
    [string] $SubscriptionID = "Undefined",


    [Parameter(Position=1,HelpMessage="Tenant ID to log in to")]
    [ValidateNotNullOrEmpty()]
    [string] $TenantID = "Undefined",

     
    [Parameter(Position=2,Mandatory=$true,HelpMessage="Resource Group to deploy to")]
    [ValidateNotNullOrEmpty()]
    [string] $ResourceGroupName,
    

    [Parameter(Position=3,Mandatory=$true,HelpMessage="Azure Region to deploy to")]
    [ValidateNotNullOrEmpty()]
    [string] $LocationName,
        
    
    [Parameter(Position=4,Mandatory=$true,HelpMessage="Vnet to deploy to")]
    [ValidateNotNullOrEmpty()]
    [string] $NetworkName,


    [Parameter(Position=5,HelpMessage="Subnet to deploy to")]
    [ValidateNotNullOrEmpty()]
    [string] $SubnetName,


    [Parameter(Position=6,HelpMessage="Static Private IP required")]
    [ValidateNotNullOrEmpty()]
    [boolean] $StaticIP = $false,


    [Parameter(Position=7,Mandatory=$true,HelpMessage="Storage Account for boot diagnostics")]
    [ValidateNotNullOrEmpty()]
    [string] $DiagAccountName,


    [Parameter(Position=8,HelpMessage="Name for the Virtual Machine")]
    [ValidateNotNullOrEmpty()]
    [string] $VMName = "az-vm" + (Get-Random -Maximum 99 -Minimum 1),


    [Parameter(Position=9,HelpMessage="Virtual Machine Size, defaults to Standard_DS2_v2 - use Get-AzVMSize to find what's available in each region")]
    [ValidateNotNullOrEmpty()]
    [string] $VMSize = "Standard_DS2_v2",


    [Parameter(Position=10,HelpMessage="Set to Windows_Server to use Hybrid Use Benefit, Windows_Client if it's a Client OS or None for PAYG Server Licensing")]
    [ValidateNotNullOrEmpty()]
    [string] $LicenseType = "None",

    
    [Parameter(Position=11,HelpMessage="Specify the SubnetID if you don't have the rights to read the vnet to discover it")]
    [ValidateNotNullOrEmpty()]
    [string] $SubnetID = "Undefined",


    [Parameter(Position=12,HelpMessage="Name of the KeyVault to retrieve secrets from")]
    [ValidateNotNullOrEmpty()]
    [string] $KV = "Undefined",
    

    [Parameter(Position=13,HelpMessage="Name of the secret in the Keyvault containing the local administrator username")]
    [ValidateNotNullOrEmpty()]
    [string] $UsernameSecret = "LocalAdminUsername",


    [Parameter(Position=14,HelpMessage="Name of the secret in the Keyvault containing the local administrator password")]
    [ValidateNotNullOrEmpty()]
    [string] $PassSecret = "BuildPassword",


    [Parameter(Position=15,HelpMessage="Name of the secret storing the Service Principal name in Keyvault")]
    [ValidateNotNullOrEmpty()]
    [string] $SPName = "BuildSp",


    [Parameter(Position=16,HelpMessage="Name of the SP Secret in KeyVault")]
    [ValidateNotNullOrEmpty()]
    [string] $SPSecretName = "BuildSpSecret",
 

    [Parameter(Position=17,HelpMessage="Name of the Keyvault Secret storing the Username to use to join AD Domain")]
    [ValidateNotNullOrEmpty()]
    [string] $adUsernameSecretName = "adUsername",    


    [Parameter(Position=18,HelpMessage="Name of the Keyvault Secret storing the Password to use to join AD Domain")]
    [ValidateNotNullOrEmpty()]
    [string] $adPassSecretName = "adPassword",


    [Parameter(Position=19,HelpMessage="FQDN of the Active Directory Domain to join. Set to None to skip joining a domain")]
    [ValidateNotNullOrEmpty()]
    [string] $ADDomain = "cloud.corp.contoso.com",   


    [Parameter(Position=20,HelpMessage="OU for Computer Object on Domain (Distinguished Name Format)")]
    [ValidateNotNullOrEmpty()]
    [string] $ADOU = "Undefined",


    [Parameter(Position=21,HelpMessage="Resource ID of Custom Image to use. Overrides anything entered for ImagePublisher/Offer/SKU/Version")]
    [ValidateNotNullOrEmpty()]
    [string] $ImageID = "Undefined",

    [Parameter(Position=22,HelpMessage="Image Publisher, for Windows Server use MicrosoftWindowsServer but for SQL it's MicrosoftSQLServer")]
    [ValidateNotNullOrEmpty()]
    [string] $ImagePublisher = "MicrosoftWindowsServer",


    [Parameter(Position=23,HelpMessage="Image Offer, for just Windows Server use WindowsServer but for SQL it's e.g. SQL2017-WS2016 - Defaults to just WindowsServer")]
    [ValidateNotNullOrEmpty()]
    [string] $ImageOffer = "WindowsServer",


    [Parameter(Position=24,HelpMessage="Image SKU - for Windows Server e.g. 2019-Datacenter, 2016-Datacenter or SQL e.g. Enterprise, Standard - Default is 2016-Datacenter-smalldisk")]
    [ValidateNotNullOrEmpty()]
    [string] $ImageSKU = "2016-Datacenter-smalldisk",


    [Parameter(Position=25,HelpMessage="Specific image version, default is latest")]
    [ValidateNotNullOrEmpty()]
    [string] $ImgVersion = "latest",


    [Parameter(Position=26,HelpMessage="Data disk size in GB")]
    [ValidateNotNullOrEmpty()]
    [int] $DataDiskSize = 0,

    [Parameter(Position=27,HelpMessage="Use managed identity to retrieve secrets from KV")]
    [ValidateNotNullOrEmpty()]
    [boolean] $UseManagedIdentity = $false,

    [Parameter(Position=28,HelpMessage="Skip logging in with a service principal when using KeyVault and use the logged in context for the build")]
    [ValidateNotNullOrEmpty()]
    [boolean] $SkipSpLogin = $false

    )

#Suppress Breaking Change Warnings because they're annoying
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

#If no Subscription specified, get the current context Subscription and use that
if ($SubscriptionID -eq "Undefined")
{
    $Context = Get-AzContext
    $SubscriptionID = $Context.Subscription.SubscriptionId
}

#If no Tenant is specified, get the current context Tenant and use that
if ($TenantID -eq "Undefined")
{
    $Context = Get-AzContext
    $TenantID = $Context.Subscription.TenantId
}

#Log in to Azure using Managed Identity if set, you'll need access to give the managed identity access to Key Vault to retrieve the secrets if using KeyVault
if ($UseManagedIdentity) {Connect-AzAccount -Identity -Subscription $SubscriptionID -Tenant $TenantID}

#Skip retrieving credentials from KeyVault if KV not set
if ($KV -ne "Undefined")
{

#Only retrieve Service Principal if SkipSpLogin is False
if ($SkipSpLogin -eq $false)
{
    #Retrieve Service Principal Secrets and create credential object
    $SPCredential = New-Object System.Management.Automation.PSCredential ((Get-AzKeyVaultSecret -VaultName $KV -Name $SPName).SecretValueText, (Get-AzKeyVaultSecret -VaultName $KV -Name $SPSecretName).SecretValue)
}

#Retrive the local admin username and password secrets and create a credential object
$LocalCredentials = New-Object System.Management.Automation.PSCredential ((Get-AzKeyVaultSecret -VaultName $KV -Name $UsernameSecret).SecretValueText, (Get-AzKeyVaultSecret -VaultName $KV -Name $PassSecret).SecretValue)

#Skip retrieving the AD join credentials if the AD Domain is set to the example Contoso domain
if ($ADDomain -ne "cloud.corp.contoso.com")
{
#Retrive the AD username and password secrets and create a credential object
$ADCredential = New-Object System.Management.Automation.PSCredential ((Get-AzKeyVaultSecret -VaultName $KV -Name $adUsernameSecretName).SecretValueText, (Get-AzKeyVaultSecret -VaultName $KV -Name $adPassSecretName).SecretValue)
}
}

#Ask for credentials if no KV set
if ($KV -eq "Undefined")
{
#Ask for local administrator username and password and create a credential object
$LocalCredentials = (Get-Credential -Title "Local Administrator Credentials" -Message "Enter the username and password for the built in local administrator account on the VM")

#Skip retrieving the AD join credentials if the AD Domain is set to the example Contoso domain
if ($ADDomain -ne "cloud.corp.contoso.com")
{
#Ask for AD username and password and create a credential object
$ADCredential = (Get-Credential -Title "Domain Join Credentials" -Message "Enter the username and password of the account to be used to join the domain")
}
}

#Skip logging in as a Service Principal if no key vault is set or SkipSpLogin is set (the rest of the script will run in your logged in context)
if ($KV -ne "Undefined" -and $SkipSpLogin -eq $false)
{
#Log in to Azure using the Service Principal
Connect-AzAccount -ServicePrincipal -Credential $SPCredential -Subscription $SubscriptionID -Tenant $TenantID
}

#Name the NIC the VMName with "nic" appended to the end
$NICName = $VMName + "nic"

#Get the ID of the subnet named in SubnetName and store it in the SubnetID variable if the SubnetID variable hasn't been set already
if ($SubnetID -eq "Undefined")
{
    #We need to load the vnet object into a variable if we are going to look up the subnet id from the name
    $Vnet = Get-AzVirtualNetwork -Name $NetworkName
    #Store the Subnet with the name in SubnetName in SubnetID
    $SubnetID = (Get-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $Vnet).Id
}

#Create the NIC
$NIC = New-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -Location $LocationName -SubnetId $SubnetID

#Setting the IP as static if the StaticIP variable is true
If ($StaticIP -eq $true)
{
$NIC| Set-AzNetworkInterfaceIpConfig -Name $NIC.IpConfigurations[0].Name -PrivateIpAddress $NIC.IpConfigurations[0].PrivateIpAddress -SubnetId $SubnetID -Primary
$NIC| Set-AzNetworkInterface
}

#Set the Computer (Host) name to be the same as the VM Name
$ComputerName = $VMName

#Put all the configuration for the VM into the VirtualMachine variable
$VirtualMachine = New-AzVMConfig -VMName $VMName -VMSize $VMSize
$VirtualMachine = Set-AzVMOperatingSystem -VM $VirtualMachine -Windows -ComputerName $ComputerName -Credential $LocalCredentials -ProvisionVMAgent -EnableAutoUpdate
$VirtualMachine = Add-AzVMNetworkInterface -VM $VirtualMachine -Id $NIC.Id
$VirtualMachine = Set-AzVMBootDiagnostic -VM $VirtualMachine -Enable -ResourceGroupName $ResourceGroupName -StorageAccountName $DiagAccountName

#If ImageID has been set, use that
if ($ImageID -ne "Undefined")
{
    $VirtualMachine = Set-AzVMSourceImage -VM $VirtualMachine -Id $ImageID
    
}

#If ImageID is undefined, use a Marketplace image
if ($ImageID -eq "Undefined")
{
    $VirtualMachine = Set-AzVMSourceImage -VM $VirtualMachine -PublisherName $ImagePublisher -Offer $ImageOffer -Skus $ImageSKU -Version $ImgVersion
}

#Create and attach a Data Disk of the specified size if required
if ($DataDiskSize -ne 0)
{
    $VirtualMachine = Add-AzVMDataDisk -VM $VirtualMachine -LUN 0 -Caching ReadOnly -DiskSizeinGB $DataDiskSize -CreateOption Empty
}

#Go ahead and create the VM using this configuration
New-AzVM -ResourceGroupName $ResourceGroupName -Location $LocationName -VM $VirtualMachine -LicenseType $LicenseType -Verbose

#Only proceed with domain join if ADDomain is not the contoso example
if ($ADDomain -ne "cloud.corp.contoso.com")
    {
    #Configure the Domain Join Extension to join this machine to the domain, join option documented here: https://docs.microsoft.com/en-us/windows/desktop/api/lmjoin/nf-lmjoin-netjoindomain

    #If the OU is specified in ADOU then use it
    if ($ADOU -ne "Undefined")
        {
        Set-AzVMADDomainExtension -OUPath $ADOU -VMName $VMName -ResourceGroupName $ResourceGroupName -Location $LocationName -DomainName $ADDomain -Credential $ADCredential -JoinOption "0x00000003" -Restart
        }

    #If ADOU is left as undefined proceed and use domain default
    if ($ADOU -eq "Undefined")
        {
        Set-AzVMADDomainExtension -VMName $VMName -ResourceGroupName $ResourceGroupName -Location $LocationName -DomainName $ADDomain -Credential $ADCredential -JoinOption "0x00000003" -Restart
        }

#If we are using a SQL Server image install the SQL IaaS Agent
If ($ImagePublisher -eq "MicrosoftSQLServer") {Set-AzVMSqlServerExtension -ResourceGroupName $ResourceGroupName -VMName $VMName -name "SQLIaasExtension" -Version 2.0 -Location $LocationName}

    }