# Function to check and install a PowerShell module
function Ensure-ModuleInstalled {
    param (
        [string]$moduleName,
        [switch]$forceInstall
    )
    
    $module = Get-Module -ListAvailable -Name $moduleName

    if ($null -eq $module -or $forceInstall) {
        Write-Host "Module $moduleName is not installed or force install is requested. Installing now..."
        Install-Module -Name $moduleName -Force -AllowClobber -Scope CurrentUser
        Import-Module $moduleName
    } else {
        Write-Host "Module $moduleName is already installed."
    }
}

# Check and ensure required modules are installed
Ensure-ModuleInstalled -moduleName "Az"
Ensure-ModuleInstalled -moduleName "Az.VMware"

# Function to check if the user is logged in to Azure
function Check-AzureLogin {
    try {
        $context = Get-AzContext
        if (-not $context) {
            throw "Not logged in"
        }
        Write-Host "Logged in as $($context.Account.Id)"
    } catch {
        Write-Host "Not logged in to Azure. Please login using Connect-AzAccount."
        Connect-AzAccount
    }
}

# Check if the user is logged into Azure
Check-AzureLogin

# List and select AVS cluster
$clusters = Get-AzVMwarePrivateCloud
$clusterTable = $clusters | Select-Object Name, Location | Sort-Object Name

Write-Host "List of AVS Clusters:"
$index = 1
foreach ($cluster in $clusterTable) {
    Write-Host "$index`: $($cluster.Name) - $($cluster.Location)"
    $index++
}

$selectedNumber = Read-Host "Enter the number of the AVS cluster you want to work with"
$selectedCluster = $clusters[$selectedNumber - 1]

# App Registration
$appName = "ZertoZVMApp"

Write-Host "Creating Azure AD App Registration: $appName"

$app = New-AzADApplication -DisplayName $appName

Write-Host "Waiting for Process to finish up..."
Start-Sleep -Seconds 5

Write-Host "Trying to get Azure AD App ... "

$app = Get-AzADApplication -DisplayName $appName
if ($null -eq $app) {
    Write-Error "Failed to create Azure AD Application."
    exit
}

Write-Host "Application ID: $($app.AppId)"

# Create a service principal for the app registration
Write-Host "Creating a Service Principal for $appName"

$servicePrincipal = New-AzADServicePrincipal -ApplicationId $app.AppId
if ($null -eq $servicePrincipal) {
    Write-Error "Failed to create service principal."
    exit
}

Write-Host "Waiting for Process to finish up..."
Start-Sleep -Seconds 5

# Create a client secret
Write-Host "Creating Client Secret for $appName"

$endDate = (Get-Date).AddYears(1)
$secret = New-AzADAppCredential -ObjectId $app.Id -EndDate $endDate
$secretValue = $secret.SecretText
if ($null -eq $secretValue) {
    Write-Error "Failed to create client secret."
    exit
}

Write-Host "Waiting for Process to finish up..."
Start-Sleep -Seconds 5

# Assign Contributor role to the App registration
Write-Host "Assigning Subscription Contributor Role to $appName"

$subscriptionId = (Get-AzContext).Subscription.Id
$roleAssignment = New-AzRoleAssignment -ObjectId $servicePrincipal.Id -RoleDefinitionName "Contributor" -Scope "/subscriptions/$subscriptionId"
if ($null -eq $roleAssignment) {
    Write-Error "Failed to assign Contributor role."
    exit
}

# Output details
$tenantId = (Get-AzContext).Tenant.Id
$appId = $app.AppId
$tokenUrl = "https://management.core.windows.net/.default" # Default Token URL
$avsName = $selectedCluster.Name
$avsResourceGroup = $selectedCluster.ResourceGroupName

Write-Host "Subscription Tenant ID: $tenantId"
Write-Host "Application (Client) ID: $appId"
Write-Host "App Registration (Client) Secret Value: $secretValue"
Write-Host "Token URL: $tokenUrl"
Write-Host "Subscription ID: $subscriptionId"
Write-Host "AVS Cloud Name: $avsName"
Write-Host "AVS Cloud Resource Group: $avsResourceGroup"
