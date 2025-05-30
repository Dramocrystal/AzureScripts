# deploy.ps1

Import-Module ./DeployModule.psm1

# === Variables ===
$resourceGroup = "rg-yazid-stage"
$location = "canadaeast"
$storageAccountName = "yazidstorage"
$containerName = "yazid-web"
$localFolderPath = ".\html"
$zipFilePath = ".\website.zip"
$blobName = "website.zip"
$tenantId = "b94e2438-32a6-4e27-82f4-7b301370a6d8"

$vmName = "yazid-vm-web"
$adminUsername = "azureuser"
$adminPassword = ConvertTo-SecureString "b2i2025!" -AsPlainText -Force
$vmSize = "Standard_B2s"
$image = "Win2019Datacenter"
$blobUrl = "https://$storageAccountName.blob.core.windows.net/$containerName/$blobName"

# === Execution ===
Ensure-AzModules
Connect-ToAzure $tenantId
Ensure-ResourceGroup $resourceGroup $location
$storageAccount = Ensure-StorageAccount $resourceGroup $storageAccountName $location
$ctx = $storageAccount.Context
Ensure-StorageContainer $ctx $containerName
Upload-ZipToBlob $localFolderPath $zipFilePath $ctx $containerName $blobName
Deploy-VMWithWebsite $resourceGroup $location $vmName $adminUsername $adminPassword $vmSize $image $blobUrl
