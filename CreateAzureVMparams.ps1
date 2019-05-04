#This script is for creating a vm without a public ip, with all credentials used secured in key vault
#Define the parameters for the script
Param (

    [Parameter(Position=0,HelpMessage="Subscription ID to log in to")]

    [ValidateNotNullOrEmpty()]

    [string] $SubID = "ae6dcf2f-4706-4430-9053-1f68cb1145aa",

    
    [Parameter(Position=1,HelpMessage="Resource Group to deploy into")]

    [ValidateNotNullOrEmpty()]

    [string] $ResourceGroupName = "deploytestneu-rg",
    

    [Parameter(Position=2,HelpMessage="Azure Region to deploy to")]

    [ValidateNotNullOrEmpty()]

    [string] $LocationName = "northeurope",
        
    
    [Parameter(Position=3,HelpMessage="Vnet to deploy to")]

    [ValidateNotNullOrEmpty()]

    [string] $NetworkName = "deploytestneu-rg",


    [Parameter(Position=4,HelpMessage="Subnet to deploy to")]

    [ValidateNotNullOrEmpty()]

    [string] $SubnetName = "default",


    [Parameter(Position=5,HelpMessage="Storage Account for boot diagnostics")]

    [ValidateNotNullOrEmpty()]

    [string] $DiagAccountName = "deploytestneudiag",


    [Parameter(Position=6,HelpMessage="Name for the Virtual Machine")]

    [ValidateNotNullOrEmpty()]

    [string] $VMName = "deptest01",


    [Parameter(Position=7,HelpMessage="Virtual Machine Size")]

    [ValidateNotNullOrEmpty()]

    [string] $VMSize = "Standard_DS2_v2",


    [Parameter(Position=8,HelpMessage="Licence Type - Set to Windows_Server to use Hybrid Use Benefit")]

    [string] $LicenceType = $null,


    [Parameter(Position=9,HelpMessage="Server OS e.g. 2016-Datacenter, 2012-R2-Datacenter, default is 2016-Datacenter-smalldisk")]

    [ValidateNotNullOrEmpty()]

    [string] $ServerOS = "2016-Datacenter-smalldisk",

    
    [Parameter(Position=10,HelpMessage="Specific image version, default is latest")]

    [ValidateNotNullOrEmpty()]

    [string] $ImgVersion = "latest",


    [Parameter(Position=11,HelpMessage="Local administrator account  name")]

    [ValidateNotNullOrEmpty()]

    [string] $VMLocalAdminUser = "lcladmin",


    [Parameter(Position=12,HelpMessage="Name of the KeyVault to retrieve the local administrator password from")]

    [ValidateNotNullOrEmpty()]

    [string] $KV = "MyKeyVault",


    [Parameter(Position=13,HelpMessage="Name of the secret in the Keyvault containing the local administrator password")]

    [ValidateNotNullOrEmpty()]

    [string] $SecretName = "ContosoLocalAdminPassword"


    [Parameter(Position=14,HelpMessage="Service Principal to log in as")]

    [ValidateNotNullOrEmpty()]

    [string] $SP = ""


    [Parameter(Position=15,HelpMessage="Name of the SP Secret in KeyVault")]

    [ValidateNotNullOrEmpty()]

    [string] $SPSecretName = "SPSecret"


)

#Suppress Breaking Change Warnings because they're annoying
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

##I'm sure there must be a better way of doing this than logging in twice??
#Log in to Azure using the Managed Identity of the VM
Connect-AzAccount -Identity -Subscription $SubID

#Retrieve Service Principal Secret and create credential object
$SPCredential = New-Object System.Management.Automation.PSCredential ($SP, (Get-AzKeyVaultSecret -VaultName $KV -Name $SPSecretName).SecretValue)

#Log in to Azure using the Service Principal
Connect-AzAccount -ServicePrincipal -Credential $SPCredential -Subscription $SubID
##/I'm sure there must be a better way of doing this than logging in twice??

#Set the Computer (Host) name to be the same as the VM Name
$ComputerName = $VMName

#Retrieve the local administrator account password from KeyVault
$VMLocalAdminSecurePassword = (Get-AzKeyVaultSecret -VaultName $KV -Name $SecretName).SecretValue

#Load the local admin username and password into a credential object
$Credential = New-Object System.Management.Automation.PSCredential ($VMLocalAdminUser, $VMLocalAdminSecurePassword)

#Name the NIC the VMName with "nic" appended to the end
$NICName = $VMName + "nic"

#We need to load the vnet object into a variable, then create the NIC and attach to the vnet
$Vnet = Get-AzVirtualNetwork -Name $NetworkName

#Get the ID of the subnet named in SubnetID variable
$SubnetID = (Get-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $Vnet).Id

#Create the NIC and store the object in a variable
$NIC = New-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -Location $LocationName -SubnetId $SubnetID

#Put all the configuration for the VM into a variable
$VirtualMachine = New-AzVMConfig -VMName $VMName -VMSize $VMSize
$VirtualMachine = Set-AzVMOperatingSystem -VM $VirtualMachine -Windows -ComputerName $ComputerName -Credential $Credential -ProvisionVMAgent -EnableAutoUpdate
$VirtualMachine = Add-AzVMNetworkInterface -VM $VirtualMachine -Id $NIC.Id
$VirtualMachine = Set-AzVMSourceImage -VM $VirtualMachine -PublisherName 'MicrosoftWindowsServer' -Offer 'WindowsServer' -Skus $ServerOS -Version $ImgVersion
$VirtualMachine = Set-AzVMBootDiagnostic -VM $VirtualMachine -Enable -ResourceGroupName $ResourceGroupName -StorageAccountName $DiagAccountName

#Create the VM using this configuration
New-AzVM -ResourceGroupName $ResourceGroupName -Location $LocationName -VM $VirtualMachine -LicenseType $LicenceType -Verbose