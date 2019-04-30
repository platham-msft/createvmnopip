#Manual (Requires you to enter credentials) example Template for Deploying Win10 Image from Shared Image Gallery

#Log in to Azure - Manually
Connect-AzAccount

#### You need to configure this bit ####

#Image to use, in my example it's a custom win 10 image in a shared image gallery
$ImageID = "/subscriptions/44d9a18a-92e1-4d8d-bae4-f8aad05ac661/resourceGroups/rg-infra-dev-neu/providers/Microsoft.Compute/galleries/GalleryDevNeu/images/Win10Client"

#Domain to join (FQDN)
$ADDomain = "cloud.corp.contoso.com"

#OU for Computer Object (Distinguished Name Format)
$ADOU = "OU=AADDC Computers,DC=cloud,DC=corp,DC=contoso,DC=com"

#Azure Region to deploy to
$LocationName = "northeurope"

#Name of the Resource Group to deploy into
$ResourceGroupName = "rg-infra-prod-neu"

#Name of the Virtual Network (vnet) to connect the VM nic to
$NetworkName = "vnet-prod-neu"

#Name of the Subnet to connect the VM nic to
$SubnetName = "default"

#Storage Account for boot diagnostics
$DiagAccountName = "rginfraprodneudiag"

#Computer (Host) Name
$ComputerName = "deptest11"

#VM name in Azure
$VMName = "deptest11"

#VM SKU (Size)
$VMSize = "Standard_DS2_v2"


#### You don't need to change anything below here ####

#Ask for the local administrator username and password to set
$Credential = (Get-Credential)

#Ask for the username and password to use to join the domain and store it in the ADCredential variable
$ADCredential = (Get-Credential)

#Name the NIC the VMName with "nic" appended to the end
$NICName = $VMName + "nic"

#Load the object of the vnet named in the NetworkName variable into a variable
$Vnet = Get-AzVirtualNetwork -Name $NetworkName

#Get the ID of the subnet named in SubnetID variable
$SubnetID = (Get-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $Vnet).Id

#Create the NIC
$NIC = New-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -Location $LocationName -SubnetId $SubnetID

#Put all the configuration for the VM into the VirtualMachine variable
$VirtualMachine = New-AzVMConfig -VMName $VMName -VMSize $VMSize
$VirtualMachine = Set-AzVMOperatingSystem -VM $VirtualMachine -Windows -ComputerName $ComputerName -Credential $Credential -ProvisionVMAgent -EnableAutoUpdate
$VirtualMachine = Add-AzVMNetworkInterface -VM $VirtualMachine -Id $NIC.Id
$VirtualMachine = Set-AzVMSourceImage -VM $VirtualMachine -Id $ImageID
$VirtualMachine = Set-AzVMBootDiagnostic -VM $VirtualMachine -Enable -ResourceGroupName $ResourceGroupName -StorageAccountName $DiagAccountName

#Create the VM using this configuration
New-AzVM -ResourceGroupName $ResourceGroupName -Location $LocationName -VM $VirtualMachine -LicenseType Windows_Client -Verbose

#Configure the Domain Join Extension to join this machine to the domain, join option documented here: https://docs.microsoft.com/en-us/windows/desktop/api/lmjoin/nf-lmjoin-netjoindomain
Set-AzVMADDomainExtension -OUPath $ADOU -VMName $VMName -ResourceGroupName $ResourceGroupName -Location $LocationName -DomainName $ADDomain -Credential $ADCredential -JoinOption "0x00000003"