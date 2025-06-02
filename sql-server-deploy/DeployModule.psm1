function Ensure-AzModules {
    $requiredModules = @("Az.Accounts", "Az.Resources", "Az.Storage", "Az.Compute", "Az.Sql")
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -Name $module -ListAvailable)) {
            Import-Module $module
        }
    }
}

function Connect-ToAzure ($tenantId) {
    Connect-AzAccount -Tenant $tenantId
}

function Ensure-ResourceGroup ($resourceGroup, $location) {
    $rg = Get-AzResourceGroup -Name $resourceGroup -ErrorAction SilentlyContinue
    if (-not $rg) {
        New-AzResourceGroup -Name $resourceGroup -Location $location
    }
}

function Ensure-StorageAccount ($resourceGroup, $storageAccountName, $location) {
    # Check if storage account exists
    $existingStorage = Get-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccountName -ErrorAction SilentlyContinue

    if (-not $existingStorage) {
        Write-Host "Creating storage account: $storageAccountName"
        New-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccountName `
                             -Location $location -SkuName Standard_LRS -Kind StorageV2 `
                             -AllowBlobPublicAccess $true | Out-Null
    } else {
        Write-Host "Storage account exists: $storageAccountName"
        Set-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccountName `
                             -AllowBlobPublicAccess $true | Out-Null
    }

    # Always generate the storage context using access key (not Azure AD)
    $keys = Get-AzStorageAccountKey -ResourceGroupName $resourceGroup -Name $storageAccountName
    $ctx = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $keys[0].Value

    Write-Host "Storage context created using access key."
    return ($ctx | Select-Object -First 1) # Ensure scalar, not array
}




function Ensure-StorageContainer ($ctx, $containerName) {
    $existingContainer = Get-AzStorageContainer -Name $containerName -Context $ctx -ErrorAction SilentlyContinue
    if (-not $existingContainer) {
        New-AzStorageContainer -Name $containerName -Context $ctx -Permission Blob
    }
}

function Upload-ZipToBlob ($localFolderPath, $zipFilePath, $ctx, $containerName, $blobName) {
    if (Test-Path $zipFilePath) {
        Remove-Item $zipFilePath -Force
    }
    Compress-Archive -Path "$localFolderPath\*" -DestinationPath $zipFilePath
    Set-AzStorageBlobContent -File $zipFilePath -Container $containerName -Blob $blobName -Context $ctx -Force
}

function Upload-FileToBlob ($filePath, $ctx, $containerName, $blobName) {
    if (-not (Test-Path $filePath)) {
        throw "File not found at $filePath"
    }
    
    Set-AzStorageBlobContent -File $filePath `
                             -Container $containerName `
                             -Blob $blobName `
                             -Context $ctx `
                             -Force

    Write-Host "Uploaded $blobName to container '$containerName'"
}


function Download-File ($url, $destinationPath) {
    if (-not (Test-Path $destinationPath)) {
        Write-Host "Downloading file from $url..."
        Invoke-WebRequest -Uri $url -OutFile $destinationPath -UseBasicParsing
        Write-Host "File downloaded to $destinationPath"
    } else {
        Write-Host "File already exists at $destinationPath"
    }
}

function Create-SqlServer ($resourceGroup, $location, $serverName, $adminUser, $adminPassword) {
    $existing = Get-AzSqlServer -ResourceGroupName $resourceGroup -ServerName $serverName -ErrorAction SilentlyContinue
    if (-not $existing) {
        Write-Host "Creating Azure SQL Server: $serverName..."
        $cred = New-Object -TypeName PSCredential -ArgumentList $adminUser, $adminPassword

        try {
            $server = New-AzSqlServer -ResourceGroupName $resourceGroup `
                                      -ServerName $serverName `
                                      -Location $location `
                                      -SqlAdministratorCredentials $cred

            # Confirm creation
            $server = Get-AzSqlServer -ResourceGroupName $resourceGroup -ServerName $serverName
            Write-Host "SQL Server created: $($server.FullyQualifiedDomainName)"
        } catch {
            Write-Host "Failed to create SQL Server: $_"
            throw
        }
    } else {
        Write-Host "SQL Server $serverName already exists."
    }
}


function Migrate-Data-To-DB(
    $resourceGroup,
    $serverName,
    $databaseName,
    $storageAccountName,
    $containerName,
    $blobName,
    $blobUrl,
    $adminUser,
    $adminPassword
) {

    $keys = Get-AzStorageAccountKey -ResourceGroupName $resourceGroup -Name $storageAccountName
    $storageKey = $keys[0].Value
    Write-Host "Importing $blobName into database $databaseName..."


    $import = New-AzSqlDatabaseImport -ResourceGroupName $resourceGroup `
                                      -ServerName $serverName `
                                      -DatabaseName $databaseName `
                                      -StorageKeyType "StorageAccessKey" `
                                      -StorageKey $storageKey `
                                      -StorageUri $blobUrl `
                                      -AdministratorLogin $adminUser `
                                      -AdministratorLoginPassword $adminPassword `
                                      -Edition "Premium" `
                                      -ServiceObjectiveName "P1" `
                                      -DatabaseMaxSizeBytes 5368709120
    Write-Host "Import started. Status: $($import.Status)"
    return $import
}

function Configure-SqlFirewall ($resourceGroup, $serverName) {
    # Allow Azure services
    New-AzSqlServerFirewallRule `
        -ResourceGroupName $resourceGroup `
        -ServerName $serverName `
        -FirewallRuleName "AllowAzureServices" `
        -StartIpAddress "0.0.0.0" `
        -EndIpAddress "0.0.0.0" | Out-Null

    # Get your current public IP
    $myIp = (Invoke-RestMethod -Uri "https://api.ipify.org").ToString()

    # Allow your IP
    New-AzSqlServerFirewallRule `
        -ResourceGroupName $resourceGroup `
        -ServerName $serverName `
        -FirewallRuleName "MyPublicIP" `
        -StartIpAddress $myIp `
        -EndIpAddress $myIp | Out-Null

    Write-Host "SQL firewall rules configured (Azure + $myIp)"
}

