# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

param(
	[Parameter(Mandatory=$True)]
	[string]$subscriptionId,

	[Parameter(Mandatory=$True)]
	[string]$publichSSHkey
)

## Most important variables ##
$workingdir = 'c:\script'
$gwUsername = 'principaluser'
$location = 'westeurope'
$ipVnet = '192.167.0.0'
$vnetSubnet = '255.255.0.0'
$maskSubnet = '255.255.255.0'
$nicAddress = '192.167.0.4'
$gwVmSize = 'Basic_A0'
$rgName = 'OpenVPN-gw'
$OpenVPNServerNet="10.6.0.0"
$OpenVPNServerMask="255.255.255.0"
## End of most important variables ##
$fileProfile = "$workingdir\azureprofile.json"
$scripName = 'p2s-initialization.sh'
$scriptPath = "$workingdir\$scripName"
$nsgName = 'OpenVPN-gw-nsg'
$gwSubnetName = 'OpenVPN-gw-subnet'
$vnetName = 'OpenVPN-gw-vnet'
$nicName = 'OpenVPN-gw-nic'
$publicIpName = 'OpenVPN-gw-publicip'
$gwVmName = 'OpenVPN-gw-vm'
$gwOSDiskName = 'OpenVPN-gw-os-hdd'
$gwStorageAccountName = 'openvpngwstorageacc'
$gwContainerName = 'gw-client-data'
$scriptContainerName = 'script'
$ExtensionName = 'CustomScript'
$Publisher = 'Microsoft.Azure.Extensions'
$Version = '2.0'

function cidr($ip, $subnet) {
    $Mask = $subnet.split(".")
    $CIDR = 0
    $Octet = 0
    Foreach ($Octet in $Mask){
        if ($Octet -eq 255){$CIDR += 8}
        if ($Octet -eq 254){$CIDR += 7}
        if ($Octet -eq 252){$CIDR += 6}
        if ($Octet -eq 248){$CIDR += 5}
        if ($Octet -eq 240){$CIDR += 4}
        if ($Octet -eq 224){$CIDR += 3}
        if ($Octet -eq 192){$CIDR += 2}
        if ($Octet -eq 128){$CIDR += 1}
    }

    return "$ip/$CIDR"
}

if (Test-Path  ($fileProfile)) {
    Import-AzureRmContext -Path $fileProfile
} else {
    Add-AzureRmAccount
    Save-AzureRmContext -Path $fileProfile -Force
}

Write-Host "1. Select Azure subscription" -ForegroundColor Green
Write-Host ""

Select-AzureRmSubscription -SubscriptionId $subscriptionId
(Get-AzureRmContext).Subscription

Write-Host "2. Create Network Security Group (NSG)" -ForegroundColor Green
Write-Host ""

New-AzureRmResourceGroup -Location $location -Name $rgName

Write-Host "3. Create VNet and Subnet" -ForegroundColor Green
Write-Host ""

$nsgRules = @()

$nsgRules += New-AzureRmNetworkSecurityRuleConfig -Name ssh-rule -Description "Allow SSH" -Access Allow -Protocol Tcp `
           -Direction Inbound -Priority 100 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * `
           -DestinationPortRange 22

$nsgRules += New-AzureRmNetworkSecurityRuleConfig -Name https-rule -Description "Allow HTTPS" -Access Allow -Protocol Tcp `
           -Direction Inbound -Priority 101 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * `
           -DestinationPortRange 443

$nsg = New-AzureRmNetworkSecurityGroup -Name $nsgName -ResourceGroupName $rgName -Location $location -SecurityRules $nsgRules

$subnetCidr=cidr $ipVnet $maskSubnet
$gwSubnet = New-AzureRmVirtualNetworkSubnetConfig -Name $gwSubnetName -AddressPrefix $subnetCidr -NetworkSecurityGroup $nsg

$vnetCidr=cidr $ipVnet $vnetSubnet
$gwVnet = New-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $rgName -Location $location -AddressPrefix $vnetCidr -Subnet $gwSubnet

$gwPublicIP = New-AzureRmPublicIpAddress -Name $publicIpName -AllocationMethod Static -ResourceGroupName $rgName -Location $location

$gwSubnetId = (Get-AzureRmVirtualNetworkSubnetConfig -Name $gwSubnetName  -VirtualNetwork $gwVnet).Id

$IPConfig = New-AzureRmNetworkInterfaceIpConfig -Name "IPConfig" -PublicIpAddressId $gwPublicIP.Id -SubnetId $gwSubnetId `
            -PrivateIpAddress $nicAddress

$gwNic = New-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $rgName -Location $location -IpConfiguration $IPConfig

Write-Host "4. Create OpenVPN server" -ForegroundColor Green
Write-Host ""

$vm = $null
$vm = New-AzureRmVMConfig -VMName $gwVmName -VMSize $gwVmSize
$vm = Set-AzureRmVMSourceImage -VM $vm -PublisherName "OpenLogic" -Offer "CentOS" -Skus "7.3" -Version "latest"
$vm = Add-AzureRmVMNetworkInterface -VM $vm -Id $gwNic.Id -Primary
# Define managed disk
$vm = Set-AzureRmVMOSDisk -VM $vm -Name $gwOSDiskName -StorageAccountType StandardLRS -CreateOption FromImage -Caching ReadWrite
# Define a credential object
$securePassword = ConvertTo-SecureString ' ' -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ($gwUsername, $securePassword)
$vm = Set-AzureRmVMOperatingSystem -VM $vm -Linux -ComputerName $gwVmName -Credential $cred -DisablePasswordAuthentication
# Configure SSH Keys
$sshPublicKey = Get-Content $publichSSHkey
$vm = Add-AzureRmVMSshPublicKey -VM $vm -KeyData $sshPublicKey -Path "/home/$gwUsername/.ssh/authorized_keys"
$vm = Set-AzureRmVMBootDiagnostics -VM $vm -Disable
$vm = New-AzureRmVM -ResourceGroupName $rgName -Location $location -VM $vm

Write-Host "5. Create Storage Account and load Bash script" -ForegroundColor Green
Write-Host ""

$randomNum = Get-Random -minimum 100 -maximum 999
$gwStorageAccountName = "$gwStorageAccountName$randomNum"
$gwStorageAccount = New-AzureRmStorageAccount -ResourceGroupName $rgName -Location $location -Name $gwStorageAccountName -SkuName Standard_LRS `
                    -AccessTier Hot -EnableEncryptionService Blob -Kind BlobStorage
Set-AzureRmCurrentStorageAccount -ResourceGroupName $rgName -Name $gwStorageAccountName
$gwContainer = New-AzureStorageContainer -Name $gwContainerName -Permission Off
$scriptContainer = New-AzureStorageContainer -Name $scriptContainerName -Permission Off
Set-AzureStorageBlobContent -File $scriptPath -Container $scriptContainerName

$storageAccountKeys = Get-AzureRmStorageAccountKey -ResourceGroupName $rgName -Name $gwStorageAccountName
$key0 = $StorageAccountKeys | Select-Object -First 1 -ExpandProperty Value

Write-Host "6. Configure and set Azure Custom Script Virtual Machine Extension (2.0)" -ForegroundColor Green
Write-Host ""

$SettingsString = "{
    `"fileUris`":[`"https://$gwStorageAccountName.blob.core.windows.net/$scriptContainerName/$scripName`"],
    `"commandToExecute`":`"sh $scripName -v $ipVnet -m $vnetSubnet -a $gwStorageAccountName -t $gwContainerName -y $key0 -c $OpenVPNServerNet -k $OpenVPNServerMask`"
}"

$PrivateConf = "{
    `"storageAccountName`": `"$gwStorageAccountName`",
    `"storageAccountKey`": `"$key0`"
}"

Set-AzureRmVMExtension -ResourceGroupName $rgName -VMName $gwVmName -Location $location `
  -Name $ExtensionName -Publisher $Publisher `
  -ExtensionType $ExtensionName -TypeHandlerVersion $Version `
  -Settingstring $SettingsString -ProtectedSettingString $PrivateConf -ErrorAction SilentlyContinue