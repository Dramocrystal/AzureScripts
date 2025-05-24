# Azure Website Deployment with PowerShell

This repository contains PowerShell scripts to automate the deployment of a static website to Azure using Blob Storage and a Windows Virtual Machine running IIS.

## 📁 Folder: `1_Website-Deployment`

---

## 🧩 Script Overview

### 1. Upload Website to Azure Blob Storage

This script:
- Creates a resource group and storage account
- Sets up a public Blob container
- Compresses the local HTML folder
- Uploads the `.zip` to the container

📄 Script file: `blob-storage.ps1`

```powershell
# Key steps:
- Create/verify resource group
- Create/verify storage account (with public blob access)
- Create/verify blob container
- Compress the `.\html` folder
- Upload the archive as `website.zip`
```

---

### 2. Deploy Windows VM and Host Website

This script:
- Creates a Windows VM (if not already present)
- Installs IIS
- Downloads and unzips the website archive from Azure Blob Storage
- Deploys it to the IIS default root (`C:\inetpub\wwwroot`)
- Outputs the public IP of the VM

📄 Script file: `vm-setup.ps1`

```powershell
# Key steps:
- Create/verify VM
- Install IIS with `Install-WindowsFeature`
- Download `website.zip` from blob storage
- Extract to web root
- Print the VM's public IP for browser access
```

---

## ⚙️ PowerShell Setup and Initialization

Before using the scripts, follow these steps to set up your PowerShell environment:

```powershell
# Step 1
Install-Module -Name Az -AllowClobber -Scope CurrentUser

# Step 2
Import-Module -Name Az -Force -Scope Global

# Step 3
Update-Module -Name Az

# Step 4
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser

# Step 5 (Login)
Connect-AzAccount -Tenant b94e2438-32a6-4e27-82f4-7b301370a6d8
# Or (alternative)
Connect-AzAccount -Tenant b94e2438-32a6-4e27-82f4-7b301370a6d8 -UseDeviceAuthentication

# Step 6 Try creating a ressource group (Optional)
New-AzResourceGroup -Name "rg-YOUR_NAME-stage" -Location "canadaeast"
```

---

## ✅ Notes
- Scripts use the `Az` module and assume default permissions in Azure.
- Passwords should **not** be hardcoded in production scripts. Consider using [Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/) instead.
---

## 🧹 Cleanup (Optional)
To delete all resources created by these scripts use the command:
```powershell
Remove-AzResourceGroup -Name "rg-YOURNAME-stage" -Force
```

---

## 📡 Output Example

Once deployed, your website should be accessible at:
```
http://<your-vm-public-ip>
```

---

## 🔗 Running the Deployment Scripts

These scripts are designed to be **chained together** and run in sequence. After setting up your PowerShell environment, execute the following in your terminal:

```powershell
.\deploy.ps1
```

- `blob-storage.ps1`: Uploads your compressed website files to Azure Blob Storage.
- `vm-setup.ps1`: Creates a VM and pulls the website archive from the blob to host it using IIS.

⚠️ Make sure both scripts and html folder are in the same directory and that you've completed the PowerShell setup steps before running them.

---

## ✍️ Author
Yazid Asselah  
Azure PowerShell Automation - Internship Project
