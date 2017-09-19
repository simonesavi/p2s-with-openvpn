# Point-to-Site (P2S) connection using OpenVPN infrastructure

PowerShell script to create an Azure Point-to-Site (P2S) connection based on OpenVPN infrastructure.

## Getting Started

### Prerequisites

The access to VM will be done using SSH public-key authentication, for this we require a couple of keys. These could be generate using [Puttygen](https://www.chiark.greenend.org.uk/~sgtatham/putty/latest.html) tool.
The details of keys generation are beyond the scope of this article but you can find hundreds guide on Internet that can help you.
Furthermore it is required a working directory where store script.

### Automatic deploy process

The proposed automation tool is formed by two core parts:
1. A PowerShell script used to prepare Azure infrastructure
2. A Bash script used to execute CentOS server auto-configuration

## PowerShell script

The script start with a series of variables declaration. Most of them are self-explanatory and they are the name of the Azure objects that we will create.
The most important variables that are to be modified are:
* workingdir: It is the directory where the script files are deployed
* subscriptionId: It is the ID of your Azure subscription
* gwUsername: Virtual machine user
* publichSSHkey: This is the path of your SSH public key
* location: It is the Azure location where infrastructure will be created
* ipVnet: Is the target space address that the script will use for the VNet creation
* vnetSubnet: Is the netmask used with ipVnet for the VNet creation
* maskSubnet: Is the subnet netmask used with ipVnet for the creation of server’s subnet
* nicAddress: Virtual machine network interface card static IP
* gwVmSize: OpenVPN virtual machine Azure size
* rgName: Resource Group name – NOTE: all created objects will be placed in same RG
* OpenVPNServerNet: Is the target space address of VPN
* OpenVPNServerMask: Is the netmask of VPN network

The tasks executed by script are:

1. Select Azure subscription
	
	During this step will be showed a popup in which insert your Azure access credentials.

2. Create Network Security Group (NSG)