#This logs in to Azure using the Managed Identity of the VM
Connect-AzAccount -Identity

#Azure Region to deploy to
$LocationName = "northeurope"

#Existing Resource Group to deploy into
$ResourceGroupName = "deploytestneu-rg"

#Existing vnet to deploy to
$NetworkName = "deploytestneu-rg"

#Existing Storage Account for boot diagnostics
$DiagAccountName = "deploytestneudiag"

#Computer (Host) Name, VM Name in Azure
$ComputerName = "deptest01"
$VMName = "deptest01"

#VM SKU (Size)
$VMSize = "Standard_DS2_v2"

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