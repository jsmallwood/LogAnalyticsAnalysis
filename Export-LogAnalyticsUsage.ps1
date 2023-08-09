#Requires -Modules PSWriteExcel

<#
.SYNOPSIS
  A script to export usage data from Log Analytics to an excel file
   
  Note This script leverages the Az cmdlets
 
.NOTES
   AUTHOR: Jason Smallwood
   LASTEDIT: August 6th, 2023 1.2

.TODO

.LINK

#>

param(
    [String] $Timespan = '7d',
    [Decimal] $AnalyticsLogsCostPerGB = 2.76,
    [Decimal] $BasicLogsCostPerGB = 0.50,
    [Object] $Subscriptions,
    [String] $Directory = $PSScriptRoot,
    [String] $FileName = "$(Get-Date -Format 'MM-dd-yyyy') - Log Analytics Workspaces.xlsx"
)

#region Variables
    $File = $Directory+'\'+$FileName
    $allWorkspaces = @()
    $allWorkspaceTables = @()
    $allSolutionIngestion = @()
    $allResourceIngestionVolumeByDataType = @()
#endregion

#region Helper Queries
Function Invoke-AzArgQuery
{
    [CmdletBinding(
        ConfirmImpact="Medium",
        DefaultParameterSetName=$null,
        HelpUri=$null,
        SupportsPaging=$true,
        SupportsShouldProcess=$true,
        PositionalBinding=$true
    )]

    param(
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            Position=0)]
            [ValidateNotNullOrEmpty()]
            [String] $Query,
        [Parameter(Mandatory=$false,
            ValueFromPipeline=$true,
            Position=1)]
            [ValidateNotNullOrEmpty()]
            [Object] $Subscription,
        [Parameter(Mandatory=$false,
            ValueFromPipeline=$true,
            Position=2)]
            [ValidateNotNullOrEmpty()]
            [Int] $PageSize

    )

    Begin {
            #region Error Action Preference
            $errorAction = $PSBoundParameters["ErrorAction"]
            if(-not $errorAction) { $errorAction = $ErrorActionPreference }
        #endregion

        #region Bound Parameters
            $boundParameters = @{
                Verbose = $PSBoundParameters.ContainsKey("Verbose");
                #Confirm = $PSBoundParameters.ContainsKey("Confirm");
                Debug = $PSBoundParameters.ContainsKey("Debug");
                #WhatIf = $PSBoundParameters.ContainsKey("WhatIf");
            }
        #endregion

        if(!($Subscription)) { $Subscriptions = Get-AzSubscription @boundParameters -ErrorAction $errorAction | Where-Object { ($_.State -eq "Enabled") -and ($_.Name -ne 'Access to Azure Active Directory') } | ForEach-Object { "$($_.Id)"} }

        if(!($PageSize)) { $ARGPageSize = 1000 } Else { $ARGPageSize = $PageSize }
    }

    Process {
        $result = [System.Collections.ArrayList]@()
        try {
        $resultsSoFar = 0
        do
        {
            if ($resultsSoFar -eq 0)
            {
                $queryResults = Search-AzGraph -Query $Query -First $ARGPageSize -Subscription $subscriptions @boundParameters -ErrorAction $errorAction
            }
            else
            {
                $queryResults = Search-AzGraph -Query $Query -First $ARGPageSize -Skip $resultsSoFar -Subscription $subscriptions @boundParameters -ErrorAction $errorAction
            }
            if ($queryResults -and $queryResults.GetType().Name -eq "PSResourceGraphResponse")
            {
                $queryResults = $queryResults.Data
            }
            $resultsCount = $queryResults.Count
            $resultsSoFar += $resultsCount
            $result += $queryResults
            Remove-Variable -Name queryResults

        } while ($resultsCount -eq $ARGPageSize)
        } catch {
            Write-Error $_
        }
    }

    End {
        Return $result
    }
}

Function Invoke-AzLogAnalyticsQuery
{
    [CmdletBinding(
        ConfirmImpact="Medium",
        DefaultParameterSetName=$null,
        HelpUri=$null,
        SupportsPaging=$true,
        SupportsShouldProcess=$true,
        PositionalBinding=$true
    )]

    param(
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            Position=0)]
            [ValidateNotNullOrEmpty()]
            [String] $WorkspaceId,
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            Position=1)]
            [ValidateNotNullOrEmpty()]
            [String] $Query,
        [Parameter(Mandatory=$false,
            ValueFromPipeline=$true,
            Position=2)]        
            [Timespan] $Timespan,
        [Parameter(Mandatory=$false,
            ValueFromPipeline=$true,
            Position=3)]
            [Int] $Wait = 600
    )

    begin {
        #region Error Action Preference
            $errorAction = $PSBoundParameters["ErrorAction"]
            if(-not $errorAction) { $errorAction = $ErrorActionPreference }
        #endregion

        #region Bound Parameters
            $boundParameters = @{
                Verbose = $PSBoundParameters.ContainsKey("Verbose");
                #Confirm = $PSBoundParameters.ContainsKey("Confirm");
                Debug = $PSBoundParameters.ContainsKey("Debug");
                #WhatIf = $PSBoundParameters.ContainsKey("WhatIf");
            }
        #endregion

    }
    process {
        try
        {
            if (-not !($TimeSpan)) {
                $queryResults = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkspaceId -Query $Query -TimeSpan $TimeSpan -Wait $Wait -IncludeStatistics
            } else {
                $queryResults = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkspaceId -Query $Query -Wait $Wait -IncludeStatistics
            }

            if ($queryResults)
            {
                $results = [System.Linq.Enumerable]::ToArray($queryResults.Results)
            }
        }
        catch
        {
            Write-Error -Message "Query failed. Debug the following query in the AOE Log Analytics workspace: $baseQuery"
        }
    }
    end {
        return $results
    }
}

Function List-AzLogAnalyticsWorkspaceTables
{
    [CmdletBinding(
        ConfirmImpact="Medium",
        DefaultParameterSetName=$null,
        HelpUri=$null,
        SupportsPaging=$true,
        SupportsShouldProcess=$true,
        PositionalBinding=$true
    )]

    param(
        [Parameter(Mandatory=$false,
            ValueFromPipeline=$true,
            Position=0)]
            [String] $ResourceId,
        [Parameter(Mandatory=$false,
            ValueFromPipeline=$true,
            Position=1)]
            [String] $SubscriptionId,
        [Parameter(Mandatory=$false,
            ValueFromPipeline=$true,
            Position=2)]
            [Alias('ResourceGroupName')]
            [String] $ResourceGroup,
        [Parameter(Mandatory=$false,
            ValueFromPipeline=$true,
            Position=3)]
            [String] $WorkspaceName
    )

    begin {
            #region Error Action Preference
            $errorAction = $PSBoundParameters["ErrorAction"]
            if(-not $errorAction) { $errorAction = $ErrorActionPreference }
        #endregion

        #region Bound Parameters
            $boundParameters = @{
                Verbose = $PSBoundParameters.ContainsKey("Verbose");
                #Confirm = $PSBoundParameters.ContainsKey("Confirm");
                Debug = $PSBoundParameters.ContainsKey("Debug");
            }
        #endregion

        $apiVersion = "2022-10-01"

        if(-not([String]::IsNullOrEmpty($ResourceId)))
        {
            $Path = $ResourceId
            if([String]::IsNullOrEmpty($SubscriptionId)) { $SubscriptionId = $ResourceId.Split('/')[2] }
            if([String]::IsNullOrEmpty($ResourceGroup)) { $ResourceGroup = $ResourceId.Split('/')[4] }
            if([String]::IsNullOrEmpty($WorkspaceName)) { $WorkspaceName = $ResourceId.Split('/')[8] }
        }
        else
        {
            if(-not([String]::IsNullOrEmpty($SubscriptionId)) -and -not([String]::IsNullOrEmpty($ResourceGroup)) -and -not([String]::IsNullOrEmpty($WorkspaceName))) 
            {  
                $Path = "/subscriptions/$($SubscriptionId)/resourceGroups/$($ResourceGroup)/providers/Microsoft.OperationalInsights/workspaces/$($WorkspaceName)"
            }
            else
            {
                Throw { Write-Error "If a ResourceId is not used a SubscriptionId, ResourceGroup, and WorkspaceName must be used." } 
            }
        }

    }

    process
    {
        if(-not[string]::IsNullOrEmpty($Path))
        {
            $result = @()
            $apiPath = "$($Path)/tables?api-version=$($apiVersion)"

            $SubscriptionName = (Get-AzSubscription | Where-Object { $_.SubscriptionId -eq $Path.Split('/')[2] }).Name

            do {

                if(-not !$content.NextPageLink)
                {
                    $apiPath = $content.NextPageLink
                }

                $tries = 0
                $requestSuccess = $false
                do {
                    try
                    {
                        $tries++
                        $request = Invoke-AzRestMethod -Method Get -Path $apiPath @boundParameters -ErrorAction $errorAction

                        $content = ($request.Content | ConvertFrom-Json)

                        $requestSuccess = $true

                        foreach($r in $content.value)
                        {
                            $obj = [PSCustomObject] @{
                                SubscriptionName = $SubscriptionName
                                ResourceGroup = $Path.Split('/')[4]
                                WorkspaceName = $Path.Split('/')[8]
                                Name = $r.Name
                                RetentionInDays = $r.properties.retentionInDays
                                TotalRetentionInDays = $r.properties.totalRetentionInDays
                                ArchiveRetentionInDays = $r.properties.archiveRetentionInDays
                                RetentionInDaysAsDefault = $r.properties.retentionInDaysAsDefault
                                TotalRetentionInDaysAsDefault = $r.properties.totalRetentionInDaysAsDefault
                                Plan = $r.properties.plan
                                Id = $r.id
                            }

                            $result += $obj
                            Remove-Variable -Name obj -Force -ErrorAction SilentlyContinue
                        }
                    }
                    catch
                    {
                        $ErrorMessage = $_.Exception.Message
                        Write-Error "Error Message: $ErrorMessage. $tries of 3 tries. Waiting 60 seconds..."
                        Start-Sleep -s 60
                    }

                } while (-not($requestSuccess) -and $tries -lt 3)
            } while ($requestSuccess -and -not !($content.NextPageLink))
        } else {
            Throw { Write-Error "If a ResourceId is not used a SubscriptionId, ResourceGroup, and WorkspaceName must be used." } 
        }
    }

    end { return $result }
}
#endregion

#region ARG Queries

# Query All Workspaces
$queryLogAnalyticsWorkspaces = @" 
resources
| where type =~ `"microsoft.operationalinsights/workspaces`"
| extend workspaceId = tolower(properties.customerId)
| extend publicNetworkAccessForIngestion = properties.publicNetworkAccessForIngestion
| extend publicNetworkAccessForQuery = properties.publicNetworkAccessForQuery
| extend dataIngestionStatus = properties.workspaceCapping.dataIngestionStatus
| extend dailyQuotaGb = properties.workspaceCapping.dailyQuotaGb
| extend retentionInDays = properties.retentionInDays
| extend skuName = properties.sku.name
| extend enableLogAccessUsingOnlyResourcePermissions = properties.features.enableLogAccessUsingOnlyResourcePermissions
| project name, resourceGroup, location, subscriptionId, workspaceId, publicNetworkAccessForIngestion, publicNetworkAccessForQuery, dataIngestionStatus, dailyQuotaGb, retentionInDays, skuName, enableLogAccessUsingOnlyResourcePermissions, id
"@

# Query All Solutions and Tables for Ingested Volume and Cost
$querySolutionIngestion = @"
let analyticsPrice = $($AnalyticsLogsCostPerGB);
let basicPrice = $($BasicLogsCostPerGB);
let TotalIngestion=toscalar(
    Usage
    | where TimeGenerated > ago($($Timespan))
    | summarize IngestionVolume=sum(Quantity));
Usage
| where TimeGenerated > ago($($Timespan))
| project TimeGenerated, DataType, Solution, Quantity, IsBillable
| summarize
    IngestedEntries = count(),
    SizePerEntryBytes = 1.0 * sum(estimate_data_size(*)) / count(),
    IngestionVolumeGB=sum(Quantity/1024),
    IngestionPercent = (sum(Quantity)) / TotalIngestion,
    AnalyticsLogsCostPerGB = sum(Quantity/1024) * analyticsPrice,
    BasicLogsCostPerGB = sum(Quantity/1024) * basicPrice,
    Billable = any(IsBillable)
    by DataType, Solution
| sort by Solution asc, DataType asc
"@

# Query All Resources and there Billable Ingestion
$queryResourceIngestedVolume = @"
let analyticsPrice = $($AnalyticsLogsCostPerGB);
let basicPrice = $($BasicLogsCostPerGB);
union *
| where TimeGenerated > ago($($Timespan))
| where _IsBillable == true
| summarize IngestedVolumeGB = sum(_BilledSize/1024/1024/1024) by _ResourceId, _IsBillable
| project ResourceName = tostring(split(_ResourceId, "/")[-1]), IngestedVolumeGB, AnalyticsLogsCostPerGB = IngestedVolumeGB * analyticsPrice, BasicLogsCostPerGB = IngestedVolumeGB * basicPrice, ResourceId = _ResourceId, IsBillable = _IsBillable
| sort by IngestedVolumeGB desc
"@

# Query All Resources and their Billable Ingestion with Actions
$queryResourceIngestedVolumeDataType = @"
let analyticsPrice = $($AnalyticsLogsCostPerGB);
let basicPrice = $($BasicLogsCostPerGB);
let TotalIngestion=toscalar(
    Usage
    | where TimeGenerated > ago(7d)
    | summarize IngestionVolume=sum(Quantity));
union withsource = tt *
| where TimeGenerated > ago(7d)
| where _IsBillable == true
| where isnotempty(_ResourceId)
| project Solution=tt, _IsBillable, _BilledSize, _ResourceId, _SubscriptionId, Resource, ResourceProvider, Category, ResourceType, OperationName, resource_actionName_s
| summarize
    IngestedVolumeGB = round(sum(_BilledSize/1024/1024/1024),2),
    AnalyticsLogsCostPerGB = round(sum(_BilledSize/1024/1024/1024),2) * analyticsPrice,
    BasicLogsCostPerGB = round(sum(_BilledSize/1024/1024/1024),2) * basicPrice
by Solution, _ResourceId, _SubscriptionId, ResourceProvider, ResourceType, Category, OperationName, resource_actionName_s, _IsBillable
| extend ResourceName = split(_ResourceId, '/')[8]
| extend ResourceGroupName = split(_ResourceId, '/')[5]
| project SubscriptionId = _SubscriptionId, ResourceName, Solution, IngestedVolumeGB, AnalyticsLogsCostPerGB, BasicLogsCostPerGB, ResourceProvider, Category, ResourceType, OperationName, ActionName = resource_actionName_s, ResourceId = _ResourceId, IsBillable = _IsBillable
| sort by IngestedVolumeGB
"@

#endregion

#region Main
$objLogAnalyticsWorkspaces = Invoke-AzArgQuery -Query $queryLogAnalyticsWorkspaces | Sort-Object -Property subscriptionId

foreach ($workspace in $objLogAnalyticsWorkspaces)
{
    Get-AzSubscription -SubscriptionId $workspace.SubscriptionId | Set-AzContext

    $SubscriptionName = (Get-AzSubscription | Where-Object { $_.SubscriptionId -eq $workspace.subscriptionId }).Name

    #region Workspace Details
    $obj = [PSCustomObject] @{
        "Subscription Name" = $SubscriptionName
        "Workspace Name" = $workspace.Name
        "Resource Group" = $workspace.ResourceGroup
        "Location" = $workspace.location
        "SKU" = $workspace.skuName
        "Daily Quota" = $workspace.dailyQuotaGb
        "Retention In Days" = $workspace.retentionInDays
        "WorkspaceId" = $workspace.WorkspaceId
    }
    $allWorkspaces += $obj
    #endregion

    #region Workspace Tables
    $results = List-AzLogAnalyticsWorkspaceTables -SubscriptionId $workspace.ResourceId.Split('/')[2] -ResourceGroup $workspace.ResourceId.Split('/')[4] -WorkspaceName $workspace.ResourceId.Split('/')[8]
    foreach($r in $results)
    {
        $obj = [PSCustomObject] @{
            "Subscription Name" = $r.SubscriptionName
            "Workspace Name" = $workspace.Name
            "Resource Group" = $r.ResourceGroup
            "Table Name" = $r.Name
            Plan = $r.Plan
            RetentionInDays = $r.RetentionInDays
            RetentionInDaysAsDefault = $r.RetentionInDaysAsDefault
            ArchiveRetentionInDays = $r.ArchiveRetentionInDays
            TotalRetentionInDays = $r.TotalRetentionInDays
            TotalRetentionInDaysAsDefault = $r.TotalRetentionInDaysAsDefault
            "WorkspaceId" = $workspace.WorkspaceId
        }

        $allWorkspaceTables += $obj
    }
    #endregion

    #region Solution Ingested Volume
    $results = Query-LogAnalytics -Query $querySolutionIngestion -WorkspaceId $workspace.WorkspaceId
    Foreach ($r in $results) {
        $obj = [PSCustomObject] @{
            "Workspace" = $workspace.Name
            "WorkspaceId" = $workspace.WorkspaceId
        }

        $properties = ($r | Get-Member -MemberType NoteProperty | Select Name).Name

        Foreach ($property in $properties) {
            If (($property -notmatch "^(\b([A-Z]{1}))") -eq $false) {
                $property = $property.Substring(0,1).ToUpper() + $property.Substring(1)
            }
            $obj | Add-Member -MemberType NoteProperty -Name $property -Value ($r | Select-Object -ExpandProperty $property)
        }

        $allSolutionIngestion += $obj
    }
    #endregion

    #region Resource Ingested Volume
    <#
    $results = Query-LogAnalytics -Query $queryResourceIngestedVolume -WorkspaceId $workspace.WorkspaceId
    Foreach ($r in $results) {
        $obj = [PSCustomObject] @{
            "Workspace" = $workspace.Name
            "WorkspaceId" = $workspace.WorkspaceId
        }

        $properties = ($r | Get-Member -MemberType NoteProperty | Select Name).Name

        Foreach ($property in $properties) {
            If (($property -notmatch "^(\b([A-Z]{1}))") -eq $false) {
                $property = $property.Substring(0,1).ToUpper() + $property.Substring(1)
            }
            $obj | Add-Member -MemberType NoteProperty -Name $property -Value ($r | Select-Object -ExpandProperty $property)
        }

        $allResourcesIngestion += $obj
    }
    #>
    #endregion

    #region Resource and Data Type Ingested Volume
    $results = Query-LogAnalytics -Query $queryResourceIngestedVolumeDataType -WorkspaceId $workspace.WorkspaceId
    Foreach ($r in $results) {
        $obj = [PSCustomObject] @{
            "Workspace" = $workspace.Name
            "WorkspaceId" = $workspace.WorkspaceId
        }

        $properties = ($r | Get-Member -MemberType NoteProperty | Select Name).Name

        Foreach ($property in $properties) {
            If (($property -notmatch "^(\b([A-Z]{1}))") -eq $false) {
                $property = $property.Substring(0,1).ToUpper() + $property.Substring(1)
            }
            $obj | Add-Member -MemberType NoteProperty -Name $property -Value ($r | Select-Object -ExpandProperty $property)
        }

        $allResourceIngestionVolumeByDataType += $obj
    }
    #endregion
}
#endregion


#region Export to Excel
$objExcel = New-ExcelDocument

Set-ExcelProperties -ExcelDocument $objExcel -Title 'Azure Log Analytics Workspaces'

Remove-ExcelWorksheet -ExcelDocument $objExcel -ExcelWorksheet (Get-ExcelWorksheet -ExcelDocument $objExcel -Name 'Sheet1')

$objWorksheet = Add-ExcelWorkSheet -ExcelDocument $objExcel -WorksheetName 'Workspaces' -Option Replace -Suppress $false
Add-ExcelWorksheetData -ExcelDocument $objExcel -ExcelWorksheet $objWorksheet -DataTable $allWorkspaces -AutoFit -FreezeTopRow -TableName 'tabWorkspaces' -TableStyle Medium2

$objWorksheet = Add-ExcelWorkSheet -ExcelDocument $objExcel -WorksheetName 'Tables' -Option Replace -Suppress $false
Add-ExcelWorksheetData -ExcelDocument $objExcel -ExcelWorksheet $objWorksheet -DataTable $allWorkspaceTables -AutoFit -FreezeTopRow -TableName 'tabTables' -TableStyle Medium2

$objWorksheet = Add-ExcelWorkSheet -ExcelDocument $objExcel -WorksheetName 'Solutions' -Option Replace -Suppress $false
Add-ExcelWorksheetData -ExcelDocument $objExcel -ExcelWorksheet $objWorksheet -DataTable $allSolutionIngestion -AutoFit -FreezeTopRow -TableName 'tabSolutions' -TableStyle Medium2

$objWorksheet = Add-ExcelWorkSheet -ExcelDocument $objExcel -WorksheetName 'Resources' -Option Replace -Suppress $false
Add-ExcelWorksheetData -ExcelDocument $objExcel -ExcelWorksheet $objWorksheet -DataTable $allResourceIngestionVolumeByDataType -AutoFit -FreezeTopRow -TableName 'tabResourceType' -TableStyle Medium2

#>

Save-ExcelDocument -ExcelDocument $objExcel -FilePath $File -OpenWorkBook
#endregion
