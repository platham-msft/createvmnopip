#This logs in to Azure using the Managed Identity of the VM
Connect-AzAccount -Identity

#Local Admin Username and Password for the VM to be deployed. You could use keyvault for the password, but if you're happy with libcrypto for now let's reinvent as little as possible
$VMLocalAdminUser = "LocalAdminUser"
$VMLocalAdminSecurePassword = ConvertTo-SecureString YourPasswordHere! -AsPlainText -Force

#Azure Region to deploy to
$LocationName = "northeurope"

#Resource Group to deploy into
$ResourceGroupName = "deploytestneu-rg"

#Computer (Host) Name, VM Name in Azure, and VM Size
$ComputerName = "deptest01"
$VMName = "deptest01"
$VMSize = "Standard_DS2_v2"

#What vnet to deploy to, and what to call the NIC
$NetworkName = "deploytestneu-rg"
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
$VirtualMachine = Set-AzVMBootDiagnostic -VM $VirtualMachine -Enable -ResourceGroupName deploytestneu-rg -StorageAccountName deploytestneudiag

#Create the VM using this configuration
New-AzVM -ResourceGroupName $ResourceGroupName -Location $LocationName -VM $VirtualMachine -Verbose