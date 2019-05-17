<#
.SYNOPSIS
Script to create a vm from a custom image with no public IP retrieving all required credentials from secrets stored in keyvault or prompting the user for them if no keyvault specified

.DESCRIPTION
Log in to Azure first using Connect-AzAccount. If you wanted to run this completely automated without embedding credentials, why not try out Managed Identity and running this from an Azure VM.
Just uncomment line 211 to log in with a managed identity.

If you don't specify a Service Principal and you're logging in manually, don't bother specifying the SubscriptionID or TenantID, make sure you're in the right context before calling this script
If you are using a Service Principal and don't specify the Subscription or Tenant it will use them from your current context
The ID you initially log in with is used to retrieve the Service Principal to do the actual creation with along with the local username and password and the  AD username and password
The idea of this is so you don't have to give the Service Principal access to Keyvault. If you're using a Managed Identity for the initial log in, give it access to the Key Vault!
I should probably refactor a bit so you can use and MI for the whole thing and no seperate SP.
If you don't give a key vault name, you will be prompted for the required credentials (and the whole script will run in the initial login context)
If you don't specify an AD Domain to join, it will skip that part.

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

.PARAMETER ImageID
Resource ID of the Custom Image to use

.PARAMETER adUsernameSecretName
Name of the Keyvault Secret storing the Username to use to join AD Domain

.PARAMETER adPassSecretName
Name of the Keyvault Secret storing the Password to use to join AD Domain

.PARAMETER ADDomain
FQDN of the Active Directory Domain to join. Set to None to skip joining a domain

.PARAMETER ADOU
OU for the Computer Object to be created on the domain, in Distinguished Name format.

.EXAMPLE
.\CreateWin10.ps1 -ADDomain zeus.badasscomputers.co.uk -ADOU "OU=AADDC Computers,DC=zeus,DC=badasscomputers,DC=co,DC=uk" -LicenseType Windows_Client -VMName depwin10 -ImageID "/subscriptions/44d9a18a-92e1-4d8d-bae4-f8aad05ac661/resourceGroups/rg-infra-dev-neu/providers/Microsoft.Compute/galleries/GalleryDevNeu/images/Win10Client"
Create a VM named "depwin10" using the image specified, join it to the zeus.badasscomputers.co.uk domain in the AADC Computers OU and apply Windows Client licensing.

.NOTES
    Author: Paul Latham
    Date:   17th May 2019
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


    [Parameter(Position=17,Mandatory=$true,HelpMessage="Image to use, in my example it's a custom win 10 image in a shared image gallery")]
    [ValidateNotNullOrEmpty()]
    [string] $ImageID,


    [Parameter(Position=18,HelpMessage="Name of the Keyvault Secret storing the Username to use to join AD Domain")]
    [ValidateNotNullOrEmpty()]
    [string] $adUsernameSecretName = "adUsername",    


    [Parameter(Position=19,HelpMessage="Name of the Keyvault Secret storing the Password to use to join AD Domain")]
    [ValidateNotNullOrEmpty()]
    [string] $adPassSecretName = "adPassword",


    [Parameter(Position=20,HelpMessage="FQDN of the Active Directory Domain to join. Set to None to skip joining a domain")]
    [ValidateNotNullOrEmpty()]
    [string] $ADDomain = "cloud.corp.contoso.com",   


    [Parameter(Position=21,HelpMessage="OU for Computer Object on Domain (Distinguished Name Format)")]
    [ValidateNotNullOrEmpty()]
    [string] $ADOU = "Undefined"

    )


#Suppress Breaking Change Warnings because they're annoying
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

#Log in to Azure using Managed Identity, you'll need access to give the managed identity access to Key Vault to retrieve the secrets if using KeyVault.
#Connect-AzAccount -Identity -Subscription $SubscriptionID -Tenant $TenantID

#Skip retrieving credentials from KeyVault if KV not set
if ($KV -ne "Undefined")
{
#Retrieve Service Principal Secrets and create credential object
$SPCredential = New-Object System.Management.Automation.PSCredential ((Get-AzKeyVaultSecret -VaultName $KV -Name $SPName).SecretValueText, (Get-AzKeyVaultSecret -VaultName $KV -Name $SPSecretName).SecretValue)

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

$LocalCredentials = (Get-Credential -Title "Local Administrator Credentials" -Message "Enter the username and password for the built in local administrator account on the VM")

#Skip retrieving the AD join credentials if the AD Domain is set to the example Contoso domain
if ($ADDomain -ne "cloud.corp.contoso.com")
{
#Retrive the AD username and password secrets and create a credential object
$ADCredential = (Get-Credential -Title "Domain Join Credentials" -Message "Enter the username and password of the account to be used to join the domain")
}
}

#Skip logging in as Service Principal if no key vault is set (the rest of the script will run in your logged in context)
#Not going to give the opportunity to specify the SP details not coming from KeyVault to protect people from sticking the secret in here in plain text

#if ($KV -ne "Undefined" -and $UseMachineIdentity -eq $false)
if ($KV -ne "Undefined")
{
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
$VirtualMachine = Set-AzVMSourceImage -VM $VirtualMachine -Id $ImageID
$VirtualMachine = Set-AzVMBootDiagnostic -VM $VirtualMachine -Enable -ResourceGroupName $ResourceGroupName -StorageAccountName $DiagAccountName

#Create the VM using this configuration
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

    }