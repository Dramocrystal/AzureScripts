# Azure Deploy Script v2 (Modular)

This PowerShell project automates the deployment of a website to an Azure Virtual Machine with IIS using a modular, reusable structure.

## 🧱 Features

- Creates an Azure Resource Group
- Creates or updates a Storage Account with blob container
- Compresses and uploads a static website to blob storage
- Deploys a Windows VM with IIS
- Installs the website in `C:\inetpub\wwwroot\catwebsite`
- Modular functions (`.psm1`) for reuse and clarity

## 📁 Folder Structure

```
azure-deploy-script-v2/
├── DeployModule.psm1      # All modular functions (resource group, storage, VM, etc.)
├── deploy.ps1             # Main script: sets variables and calls module functions
├── html/                  # Your local static website folder
├── website.zip            # Auto-generated during deployment
└── README.md
```

## 🚀 Getting Started

### Prerequisites

- PowerShell 7+ (or Windows PowerShell 5.1+)
- Azure PowerShell modules installed:
  ```powershell
  Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force
  ```

### Usage

1. Clone this repo:
   ```bash
   git clone https://github.com/yourusername/azure-deploy-script-v2.git
   cd azure-deploy-script-v2
   ```

2. Customize variables in `deploy.ps1`:
   ```powershell
   $resourceGroup = "rg-myproject"
   $location = "canadaeast"
   $storageAccountName = "mystorage123"
   ...
   ```

3. Run the script:
   ```powershell
   ./deploy.ps1
   ```

4. Your site will be available at:
   ```
   http://<public-ip>/catwebsite
   ```

## 🔐 Security Note

Never commit your passwords or secrets to Git. Use Azure Key Vault or a separate `secrets.ps1` file (excluded in `.gitignore`) for credentials.

## 📦 Future Improvements

- Parametrized CLI usage (`.ps1 -rg myRG -vmName myVM`)
- Add teardown/destroy script
- Add logging or error handling

## 📄 License

MIT
