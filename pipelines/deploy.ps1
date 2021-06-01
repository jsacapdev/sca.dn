<#
.Deploy Infrastructure
#

.DESCRIPTION
Create a resource group, upload all linked templates to a storage account, make them public, deploy the linked templates and then set the puiblic access to off

.PARAMETER CoreResourceGroupName
The resource group that has the linked templates for deployment

.PARAMETER LinkedStorageAccount
The storage account for linked template deployment

.PARAMETER LinkedStorageContainer
The storage account linked template container for deployment

.PARAMETER ResourceGroupName
The resource to create (if it does not exist) and to deploy to

.PARAMETER EnvironmentTagName
The tag name for the envioroment for any resources that we creatd

.NOTES
#>
param(
    [string]$CoreResourceGroupName,
    [string]$LinkedStorageAccount,
    [string]$LinkedStorageContainer,
    [string]$ResourceGroupName,
    [string]$EnvironmentTagName
)

# global variables
$linkedStorageAccount =  $LinkedStorageAccount # premium gateway linked templates storage
$linkedStorageContainer = $LinkedStorageContainer # linked templates

<#
.Check Azure CLI For Error
#

.DESCRIPTION
The Azure CLI and Powershell Core together cannot recognise an error. This is a workaround so that if a error occurred, stop running the script

.PARAMETER message
The error message to report back when stopping the script

#>
function CLICheckAndFailOnError($message) {
    if (!$?) {
        Write-Error $message
        return
    }
}

<#
.Upload files to azure storage
#

.DESCRIPTION
Upload files to azure storage

.PARAMETER files
Files to upload

.EXAMPLE
An example

#>
function UploadFileToBlobStorage([string[]]$files, $folderPrefix) {

    foreach ($file in $files) {
        $name = Split-Path $file -leaf
        "Uploading '$file' to '$name'"
        az storage blob upload --account-name $linkedStorageAccount -f $file -c $linkedStorageContainer -n $name
        CLICheckAndFailOnError("Unable to upload '$file' to storage account 'patterns'")
    }
}

"Starting deployment '$($env:BUILD_BUILDID)' in Resource Group '$ResourceGroupName'"
"Core Resource Group -> '$CoreResourceGroupName'"
"Linked Storage Account -> '$LinkedStorageAccount'"
"Linked Storage Container -> '$LinkedStorageContainer'"
"Environment Tag Name -> '$EnvironmentTagName'"

# create the resource group
az group create -n $ResourceGroupName -l westeurope --tags "DataClassification=Internal" "Service=LIP" "Criticality=Core Services" "Environment=$EnvironmentTagName"

CLICheckAndFailOnError("Failed to create resource group '$ResourceGroupName'")

"Creating storage account '$linkedStorageAccount' in Resource Group '$CoreResourceGroupName'"

# create a storage account to use for the arm linked templates
az storage account create -n $linkedStorageAccount -g $CoreResourceGroupName -l uksouth --sku Standard_LRS --kind StorageV2

CLICheckAndFailOnError("Failed to create storage account '$linkedStorageAccount'")

# get a connection string to the linked template storage account
$connection = $(az storage account show-connection-string -g $CoreResourceGroupName --name $linkedStorageAccount --query connectionString -o json | ConvertFrom-Json)

"Creating storage container '$linkedStorageContainer' in account '$linkedStorageAccount' in Resource Group '$CoreResourceGroupName'"

# create the linked templates container
az storage container create -n $linkedStorageContainer -g $CoreResourceGroupName --connection-string $connection

# get the template files that we want to upload to a linked template location
$files = Get-ChildItem . -Filter *.template.json | Where-Object { $_.Name -ne "master.template.json" }

# upload all the linked templates to a location where the master template can reference them
UploadFileToBlobStorage $files

# get the policy files that we want to upload to a linked template location
$files = Get-ChildItem  . -Filter *.xml 

# upload all the policies to a location where the master template can reference them
UploadFileToBlobStorage $files

$expiretime = (Get-Date).AddMinutes(60.0).ToUniversalTime().ToString("yyyy-MM-ddTHH:mmZ")

$token = $(az storage container generate-sas --name $linkedStorageContainer --expiry $expiretime --permissions r --connection-string $connection -o json)

$containerUri = "$(az storage account show -g $CoreResourceGroupName -n $linkedStorageAccount --query primaryEndpoints.blob -o json | ConvertFrom-Json)$linkedStorageContainer"

# start the deployment of the infrastructure
az deployment group create --name $($env:BUILD_BUILDID) --resource-group $ResourceGroupName --template-file ./master.template.json --parameters "@master.parameters.json" "containerUri=$containerUri" "containerSasToken=$token" --debug

CLICheckAndFailOnError("Failed to deploy master temaplte to '$ResourceGroupName'")

"Finished deployment in Resource Group '$ResourceGroupName'"
