Import-Module ./DeployModule.psm1

# === Variables ===
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
$env:DB_PASSWORD = (Get-Content ".env" | Where-Object { $_ -match '^DB_PASSWORD=' }) -replace 'DB_PASSWORD=', ''
$sqlAdminPassword = ConvertTo-SecureString $env:DB_PASSWORD -AsPlainText -Force


# === Execution ===
Ensure-AzModules
Connect-ToAzure $tenantId
Ensure-ResourceGroup $resourceGroup $location
$ctx = Ensure-StorageAccount $resourceGroup $storageAccountName $location
Ensure-StorageContainer $ctx $containerName
Download-File $bacpacUrl $filePath
Upload-FileToBlob $filePath $ctx $containerName $blobName
Write-Host "Blob accessible at : $blobUrl"

Create-SqlServer $resourceGroup $location $serverName $sqlAdminUser $sqlAdminPassword
Configure-SqlFirewall $resourceGroup $serverName
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

$serverFqdn = "$serverName.database.windows.net"
Write-Host "`n Your SQL Server is accessible at: $serverFqdn"
Write-Host " Connect using SQL Server Management Studio (SSMS), Azure Data Studio, or JDBC/ODBC:"
Write-Host "   Server: $serverFqdn"
Write-Host "   Database: $databaseName"
Write-Host "   Username: $sqlAdminUser"
