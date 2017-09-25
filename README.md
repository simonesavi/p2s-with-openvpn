# Point-to-Site (P2S) connection using OpenVPN infrastructure

PowerShell script to create an Azure Point-to-Site (P2S) connection based on OpenVPN infrastructure.

## Getting Started

### Prerequisites

The access to VM will be done using SSH public-key authentication, for this we require a couple of keys. These could be generate using [Puttygen](https://www.chiark.greenend.org.uk/~sgtatham/putty/latest.html) tool.
The details of keys generation are beyond the scope of this article but you can find hundreds guides on Internet that can help you.
Furthermore it is required a working directory, on the terminal where PowerShell script will be executed, where store script.

### Automatic deploy process

The proposed automation tool is formed by two core parts:
1. A PowerShell script used to prepare Azure infrastructure
2. A Bash script used to execute CentOS server auto-configuration

## PowerShell script

The script start with a series of variables declaration. Most of them are self-explanatory and they are the name of the Azure objects that we will create.
The most important variables that are to be modified are:
* subscriptionId: It is the ID of your Azure subscription - **Required at startup as parameter**
* publichSSHkey: This is the path of your SSH public key - **Required at startup as parameter**
* workingdir: It is the directory where the script files are deployed
* gwUsername: Virtual machine user
* location: It is the Azure location where infrastructure will be created
* ipVnet: Is the target space address that the script will use for the VNet creation
* vnetSubnet: Is the netmask used with ipVnet for the VNet creation
* maskSubnet: Is the subnet netmask used with ipVnet for the creation of server’s subnet
* nicAddress: Virtual machine network interface card static IP
* gwVmSize: OpenVPN virtual machine Azure size
* rgName: Resource Group name – **NOTE**: all created objects will be placed in same RG
* OpenVPNServerNet: Is the target space address of VPN
* OpenVPNServerMask: Is the netmask of VPN network

The tasks executed by script are:

1. Select Azure subscription
	
	During this step will be showed a popup in which insert your Azure access credentials.

2. Create Network Security Group (NSG)

	It is created a NSG with two incoming rules:
	* TCP port 22: Used to access VM via SSH protocol
	* TCP port 443: This is used by OpenVPN clients to access server

3. Create VNet and Subnet

	Like official Azure P2S solution it is created a VNet and a Subnet that will contains the OpenVPN server.

4. Create OpenVPN server

	In this step will be created a VM based on the CentOS 7.3 image provided by OpenLogic.
	The VM will have an OS managed disk, a public IP address and monitoring disabled.
	The VM size can be controlled with variable gwVmSize.

	**NOTE**: the default size value is very small (A2 Basic) and must be increased depending on the network traffic volume you will want to manage. We suggest to start with this dimension and eventually resize VM later.

5. Create Storage Account and load Bash script

	A Blob storage account will be created with a dual purpose:
	1. To archive the Bash script that will be used to configure OpenVPN server
	2. To maintain the configuration files that must be used by OpenVPN client
	
	At this point of procedure the script simply create storage account and load Bash script on it. The Bash script loaded will be the one that is present in working directory.

6. Configure and set [Azure Custom Script Virtual Machine Extension (2.0)](https://github.com/Azure/custom-script-extension-linux)

	To launch the bash configuration script on new VM we need to use an Extension. This is a very interesting code part that we want to highlight:
	```powershell
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

	```
	In the variable SettingsString is it contained the location of the script on the Storage Account and the command that will be executed on the target VM. It is important to note that this command could be altered if, example, we need to pass other type of parameters to Bash script.
	
	All the parameters that Bash script accept in input are clearly visible inspecting the beginning part of Bash script source code.
	In PowerShell script only the most important parameters are set to have a more readable code.    
	
	The variable PrivateConf contains the credentials that are need to access the Storage Account.

	The last instruction set the extension that automatically run the command indicated in “commandToExecute”.

## Bash script

The script start setting variable with the value sent as parameter during the script execution.

You can inspect the first “while getopts” construct. In his body un can see the couples option/script variable, e.g. the option -v is used to pass at script the value that variable VNET while assume.

The most important variables that must be modified are the ones that are set by Power Shell script in the "*Configure Azure Custom Script Virtual Machine Extension (2.0)*" step.

The tasks executed by script are:

1. Extra Packages for Enterprise Linux (EPEL) installation

	It will be installed the EPEL package for CentOS distribution. This permit to use a pre-packaged version of OpenVPN server without compile him from source code.

2. OpenVPN and Easy RSA installation

	It will be installed the OpenVPN and Easy RSA packages provided by EPEL.

	Easy RSA is a small RSA key management tool, based on the openssl command line tool, that it will be used to generate keys and certificates needs to establish VPN tunnels.

3. **OPTIONAL** - CentOS update

	This step was disabled (commented) because its execution could be very long. This slow down the whole installation process.

4. Enable Swap

	The used OS image is provided without a Swap configuration. This space normally is allocated as a dedicated disk partition but to avoid disk manipulation it will be created a swap file.

5. IPv6 Disable

	It is disabled because it is not used in this configuration.

6. Server keys and certificate generation

	In this step the Easy RSA tool will be configured (**NOTE**: some of variables that was unchanged in step one are used here e.g. KEY_COUNTRY).

	Subsequently keys and certificate of a private Certification Authority (CA) will be generated. This CA is used to sign the certificate that OpenVPN server will use during the client/server authentication process.

7. OpenVPN configuration

	A basic OpenVPN server configuration is executed.

8. Firewall configuration

	The CentOS firewall will be configured. This give and additional level of protection (remember that is already present a NSG configuration) but more important enable IP Masquerade, that is a NAT function used to translate source IP address of the packets coming from VPN network (that use a dedicate addressing) in IP address that can be routed inside VNet.

9. OpenVPN Client Certificate Generation

	It will be generated the first certificate that it will be used by the client during the client/server authentication process.

	**NOTE**: The parameter `--exclude=WALinuxAgent` was added to avoid problem described [here](https://github.com/Azure/WALinuxAgent/issues/178). To update Azure agent run `yum -y update` manually at the end of installation.

10. Azure CLI installation

	An Azure CLI installation is need to interact with the Azure Blob storage.

11. Client file configuration upload

	All the data that client need to authenticate itself to OpenVPN server are loaded on Azure Blob storage.
	
	In addition to this a basic configuration file for the OpenVPN client it will be generated and loaded on Azure.

**NOTE**: All the configuration process could be very long (half hour or more) especially if you chose to execute system update.

## End of the installation

When the PowerShell script execution end a **VM reboot is required**.

Next you must download from the Azure Blob storage, in "script" container:

	1. ca.crt: Certification Authority (CA) certificate 
	2. client.crt: Client certificate
	3. client.key: Client private key
	4. client.ovpn: Client config file

**NOTE**: During download check that files extension will be correct to avoid errors due to wrong file name (e.g. client.key with some browser is saved as client_key.txt).

All this data must be used to configure OpenVPN client.

**IMPORTANT**: You must change the remote value in file client.ovpn with the public IP of OpenVPN server.

Example if you use OpenVPN client available in the [official project site](https://openvpn.net) you must put all this files in a subdirectory (choose a name that you prefer) in config directory.

## Generate new client credentials

Chose a username e.g. pippo

Login in the OpenVPN server and execute following commands:
```bash
sudo su
cd /etc/openvpn/rsa/
source ./vars
./build-key pippo
```
Answer all the questions.

At the end you will find following files to give to new client together with `ca.crt` and `client.ovpn`
```bash
/etc/openvpn/rsa/keys/pippo.crt
/etc/openvpn/rsa/keys/pippo.key
```

## Security tips

1. After setup, and after you done a check that all functions properly, you **must** close port 22 removing the rules on Network Security Group (NSG). In this way you close the access to administrative interface from Internet. You could continue to manage your OpenVPN server using its private IP after you have established a VPN connection.

	The port 22 was opened from Internet to permit monitoring of deployment. Indeed, after become root, you can follow the execution of bash command on OpenVPN server using the `tail -f` command with the log file.
2. The Easy RSA store all the private keys and certificates on OpenVPN server. If an attacker gain access to file system could steal the key to generate valid credentials for VPN. For this it is important to plane a relocation of Easy RAS with its working directory on other location if you want maintain this server up and running for long period.
3. If CentOS update (`yum -y update`) was not executed during installation execute it as soon as possible. An updated system is less vulnerable to attacks.

	**NOTE**: This operation could reset firewall configuration. To go back to correct configuration execute again the steps of firewall configuration that you can find inside Bash script.
