# Variables
$resourceGroup = "rg-yazid-stage"
$location = "canadaeast"
$storageAccountName = "yazidstorage"
$containerName = "yazid-web"
$localFolderPath = ".\html"


$requiredModules = @("Az.Accounts", "Az.Resources", "Az.Storage", "Az.Compute")

foreach ($module in $requiredModules) {
    if (-not (Get-Module -Name $module -ListAvailable)) {
        Write-Host "Importing module: $module"
        Import-Module $module
    } else {
        Write-Host "Module already available: $module"
    }
}

#1 Se connecter 
Connect-AzAccount -Tenant "b94e2438-32a6-4e27-82f4-7b301370a6d8"

#2 Regarder si le ressource group existe (SilentlyContinue pour ignorer error : will store null)
$rg = Get-AzResourceGroup -Name $resourceGroup -ErrorAction SilentlyContinue

#Si le rg, n'existe pas creer un nouveau
if (-not $rg) {
    Write-Host "Creating resource group '$resourceGroup'..."
    New-AzResourceGroup -Name $resourceGroup -Location $location
#else, utiliser le ressource group existant
} else {
    Write-Host "Resource group '$resourceGroup' already exists in $($rg.Location)"
}

#3 Creer un storage account 

# Regarder si le storage account exists deja
$existingStorage = Get-AzStorageAccount -ResourceGroupName $resourceGroup `
                                        -Name $storageAccountName `
                                        -ErrorAction SilentlyContinue
# Si non, creer un nouveau
if (-not $existingStorage) {
    Write-Host "Creating storage account '$storageAccountName'..."
    $storageAccount = New-AzStorageAccount -ResourceGroupName $resourceGroup `
                                           -Name $storageAccountName `
                                           -Location $location `
                                           -SkuName Standard_LRS `
                                           -Kind StorageV2 `
                                           -AllowBlobPublicAccess $true
} else {
    Write-Host "Storage account '$storageAccountName' already exists."
    $storageAccount = $existingStorage
    #Allow public access
    Set-AzStorageAccount -ResourceGroupName $resourceGroup `
                        -Name $storageAccountName `
                        -AllowBlobPublicAccess $true
}

#4 Grab le contexte (les parametres d'identification/connection) pour l'utiliser plus tard
$ctx = $storageAccount.Context

#5 Creer le container
# Check if container exists
$existingContainer = Get-AzStorageContainer -Name $containerName -Context $ctx -ErrorAction SilentlyContinue
#Blob permission allows anyone with a direct URL to a blob to view it, cannot view the rest of the files container
if (-not $existingContainer) {
    Write-Host "Creating container '$containerName'..."
    New-AzStorageContainer -Name $containerName -Context $ctx -Permission Blob
} else {
    Write-Host "Container '$containerName' already exists."
}



#6 Compress the folder and upload as ZIP
Write-Host "Compressing folder '$localFolderPath'..."

$zipFilePath = ".\website.zip"

# Remove existing ZIP if it exists
if (Test-Path $zipFilePath) {
    Remove-Item $zipFilePath -Force
}

# Compress the folder
Compress-Archive -Path "$localFolderPath\*" -DestinationPath $zipFilePath
Write-Host "Folder compressed to $zipFilePath"

# Upload the ZIP to blob storage
$blobName = "website.zip"
Write-Host "Uploading ZIP to blob storage..."
Set-AzStorageBlobContent -File $zipFilePath -Container $containerName -Blob $blobName -Context $ctx -Force

# Show blob URL
$blobUrl = "https://$($storageAccountName).blob.core.windows.net/$containerName/$blobName"
Write-Host "`nZIP uploaded! Access it at:"
Write-Host $blobUrl


#8 Effacer le ressource group (uncomment)
#Remove-AzResourceGroup -Name $resourceGroup -Force
