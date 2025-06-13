Import-Module ./DeployModule.psm1

# === Variables ===
# Read passwords from .env
$envVars = Get-Content ".env"
$env:DB_PASSWORD = ($envVars | Where-Object { $_ -match '^DB_PASSWORD=' }) -replace 'DB_PASSWORD=', ''
$env:VM_PASSWORD = ($envVars | Where-Object { $_ -match '^VM_PASSWORD=' }) -replace 'VM_PASSWORD=', ''




$tenantId = "b94e2438-32a6-4e27-82f4-7b301370a6d8"
$resourceGroup = "rg-yazid-stage"
$location = "canadacentral"
$storageAccountName = "yazidstorage"
$containerName = "yazid-data"

$bacpacUrl = "https://github.com/Microsoft/sql-server-samples/releases/download/wide-world-importers-v1.0/WideWorldImportersDW-Full.bacpac"
$filePath = ".\WideWorldImportersDW-Full.bacpac"
$blobName = "WideWorldImportersDW-Full.bacpac"
$blobUrl = "https://$storageAccountName.blob.core.windows.net/$containerName/$blobName"

$serverName = "yazid-sql"
$databaseName = "WideWorldDW"
$sqlAdminUser = "sqladminuser"
$sqlAdminPassword = ConvertTo-SecureString $env:DB_PASSWORD -AsPlainText -Force

$vmName = "yazid-vm-web"
$adminUsername = "azureuser"
$adminPassword = ConvertTo-SecureString $env:VM_PASSWORD -AsPlainText -Force
$vmSize = "Standard_B2s"
$image = "Win2019Datacenter"


# === Execution ===
Ensure-AzModules
Connect-ToAzure $tenantId
Ensure-ResourceGroup $resourceGroup $location

# === Create Storage + Upload BACPAC ===
$ctx = Ensure-StorageAccount $resourceGroup $storageAccountName $location
Ensure-StorageContainer $ctx $containerName
Download-File $bacpacUrl $filePath
Upload-FileToBlob $filePath $ctx $containerName $blobName
Write-Host "Blob accessible at: $blobUrl"

# === Deploy VM First ===
$vmIp = Deploy-VM $resourceGroup $location $vmName $adminUsername $adminPassword $vmSize $image
Write-Host "`n VM deployed with public IP: $vmIp"

# === Create SQL Server ===
Create-SqlServer $resourceGroup $location $serverName $sqlAdminUser $sqlAdminPassword

# === Configure Firewall Rules ===
$myIp = Get-PublicIp
Configure-SqlFirewall $resourceGroup $serverName "AllowAzureServices" "0.0.0.0"
Configure-SqlFirewall $resourceGroup $serverName "MyPublicIP" $myIp
Configure-SqlFirewall $resourceGroup $serverName "MyVM" $vmIp

# === Migrate Data into SQL Database ===
Migrate-Data-To-DB `
    -resourceGroup $resourceGroup `
    -serverName $serverName `
    -databaseName $databaseName `
    -storageAccountName $storageAccountName `
    -containerName $containerName `
    -blobName $blobName `
    -blobUrl $blobUrl `
    -adminUser $sqlAdminUser `
    -adminPassword $sqlAdminPassword

# === Output SQL Connection Info ===
$serverFqdn = "$serverName.database.windows.net"
Write-Host "`nYour SQL Server is accessible at: $serverFqdn"
Write-Host "Connect using SQL Server Management Studio (SSMS), Azure Data Studio, or JDBC/ODBC:"
Write-Host "  Server: $serverFqdn"
Write-Host "  Database: $databaseName"
Write-Host "  Username: $sqlAdminUser"

