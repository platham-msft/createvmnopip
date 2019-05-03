#Define the parameters for the script
Param (

    [Parameter(Position=0,HelpMessage="The directory with all the drivers in you want to import, it should have a CSV in the root called Manufacturer_Model.CSV")]

    [ValidateNotNullOrEmpty()]

    [string] $GoldFolder = "\\sccm01\e$\Source\Drivers\home_pc",



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

    [string] $VMSize = "Standard_DS2_v2"


)



#Logs in to Azure using the Managed Identity of the VM
Connect-AzAccount -Identity

#Set the Computer (Host) name to be the same as the VM Name
$ComputerName = $VMName

#Local Admin Username and Password for the VM to be deployed. You could use keyvault for the password, but if you're happy with libcrypto for now let's reinvent as little as possible
$VMLocalAdminUser = "LocalAdminUser"
$VMLocalAdminSecurePassword = ConvertTo-SecureString YourPasswordHere! -AsPlainText -Force

#Name the NIC the VMName with "nic" appended to the end
$NICName = $VMName + "nic"

#We need to load the vnet object into a variable, then create the NIC and attach to the vnet. Notice the Subnet ID, you'll need to configure this correctly for your EXTERNAL, INTERNAL or MANAGEMENT subnet.
$Vnet = Get-AzVirtualNetwork -Name $NetworkName
$NIC = New-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -Location $LocationName -SubnetId $Vnet.Subnets[0].Id

#Load the local admin username and password into a credential object
$Credential = New-Object System.Management.Automation.PSCredential ($VMLocalAdminUser, $VMLocalAdminSecurePassword);

#Put all the configuration for the VM into a variable
$VirtualMachine = New-AzVMConfig -VMName $VMName -VMSize $VMSize
$VirtualMachine = Set-AzVMOperatingSystem -VM $VirtualMachine -Windows -ComputerName $ComputerName -Credential $Credential -ProvisionVMAgent -EnableAutoUpdate
$VirtualMachine = Add-AzVMNetworkInterface -VM $VirtualMachine -Id $NIC.Id
$VirtualMachine = Set-AzVMSourceImage -VM $VirtualMachine -PublisherName 'MicrosoftWindowsServer' -Offer 'WindowsServer' -Skus '2016-Datacenter' -Version latest
$VirtualMachine = Set-AzVMBootDiagnostic -VM $VirtualMachine -Enable -ResourceGroupName $ResourceGroupName -StorageAccountName $DiagAccountName

#Create the VM using this configuration
New-AzVM -ResourceGroupName $ResourceGroupName -Location $LocationName -VM $VirtualMachine -Verbose