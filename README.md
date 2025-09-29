# MicroTunnel-Deployment-Tool
This tool is for deploying MicroTunnel onto end devices and servers

# Sample Scripts
The scripts in this repo will download the latest published and signed version of the MicroTunnelInstaller.exe tool. Executing this tool with the appropriate arguments downloads the latest signed build of the Workstation or Server runners and install them on the Windows computer.

The scripts chain these two events into one script easily deployed via RMM tooling.

# Examples using the DirectDownload script:
To install MicroTunnel on a workstation that will have users daily-driving:

`.\DeployMicroTunnel_DirectDownload.ps1 -OrgId <YOUR_ORG_ID> -ws`

To install MicroTunnel on a server that will be sharing files to users/groups:

`.\DeployMicroTunnel_DirectDownload.ps1 -OrgId <YOUR_ORG_ID> -svr`
