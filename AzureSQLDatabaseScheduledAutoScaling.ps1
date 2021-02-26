<#
.SYNOPSIS
    Vertically scale an Azure SQL Database up or down according to a
    schedule using Azure Automation.

.DESCRIPTION
    This Azure Automation runbook enables vertically scaling of
    an Azure SQL Database according to a schedule. Autoscaling based
    on a schedule allows you to scale your solution according to
    predictable resource demand. For example you could require a
    high capacity (e.g. P2) on Monday during peak hours, while the rest
    of the week the traffic is decreased allowing you to scale down
    (e.g. P1). Outside business hours and during weekends you could then
    scale down further to a minimum (e.g. S0). This runbook
    can be scheduled to run hourly. The code checks the
    scalingSchedule parameter to decide if scaling needs to be
    executed, or if the database is in the desired state already and
    no work needs to be done. The script is Timezone aware.

.PARAMETER environmentName
    Name of Azure Cloud environment. Default is AzureCloud, only change
    when on Azure Government Cloud, for example AzureUSGovernment.

.PARAMETER resourceGroupName
    Name of the resource group to which the database server is
    assigned.

.PARAMETER azureRunAsConnectionName
    Azure Automation Run As account name. Needs to be able to access
    the $serverName.

.PARAMETER serverName
    Azure SQL Database server name.

.PARAMETER databaseName
    Azure SQL Database name (case sensitive).

.PARAMETER scalingSchedule
    Database Scaling Schedule. It is possible to enter multiple
    comma separated schedules: [{},{}]
    Keys: WeekDays, StartTime, StopTime, Edition and Tier
    Weekdays start at 0 (sunday) and end at 6 (saturday).
    If the script is executed outside the scaling schedule time slots
    that you defined, the defaut edition/tier (see below) will be
    configured.
    Example: [{WeekDays:[1], StartTime:"06:59:59″, StopTime:"17:59:59″, Edition: “Premium", Tier: “P2″}, {WeekDays:[2,3,4,5], StartTime:"06:59:59″, StopTime:"17:59:59", Edition: “Premium", Tier: “P1"}]

.PARAMETER scalingScheduleTimeZone
    Time Zone of time slots in $scalingSchedule.
    Available time zones: [System.TimeZoneInfo]::GetSystemTimeZones().

.PARAMETER defaultEdition
    Azure SQL Database Edition that will be used outside the slots
    specified in the scalingSchedule paramater value.
    Available values: Basic, Standard, Premium.

.PARAMETER defaultTier
    Azure SQL Database Tier that will be used outside the slots
    specified in the scalingSchedule paramater value.
    Example values: Basic, S0, S1, S2, S3, P1, P2, P4, P6, P11, P15.

.EXAMPLE
    -environmentName AzureCloud
    -resourceGroupName myResourceGroup
    -azureRunAsConnectionName AzureRunAsConnection
    -serverName myserver
    -databaseName myDatabase
    -scalingSchedule [{ Edition: 'Standard', Tier: 'S1'}]
    -scalingScheduleTimeZone W. Europe Standard Time
    -defaultEdition Standard
    -defaultTier S0

.NOTES
    Author: Jorg Klein
    Last Update: Nov 2018  
#>

param(
[parameter(Mandatory=$false)]
[string] $environmentName = "AzureCloud",   

[parameter(Mandatory=$true)]
[string] $resourceGroupName,

[parameter(Mandatory=$false)]
[string] $azureRunAsConnectionName = "AzureRunAsConnection",

[parameter(Mandatory=$true)]
[string] $serverName,

[parameter(Mandatory=$true)]
[string] $databaseName,

[parameter(Mandatory=$true)]
[string] $scalingSchedule,

[parameter(Mandatory=$false)]
[string] $scalingScheduleTimeZone = "W. Europe Standard Time",

[parameter(Mandatory=$false)]
[string] $defaultEdition = "Standard",

[parameter(Mandatory=$false)]
[string] $defaultTier = "S0"
)

filter timestamp {"[$(Get-Date -Format G)]: $_"}

Write-Output "Script started." | timestamp

$VerbosePreference = "Continue"
$ErrorActionPreference = "Stop"

#Authenticate with Azure Automation Run As account (service principal)
$runAsConnectionProfile = Get-AutomationConnection -Name $azureRunAsConnectionName
$environment = Get-AzureRmEnvironment -Name $environmentName
Add-AzureRmAccount -Environment $environment -ServicePrincipal `
-TenantId $runAsConnectionProfile.TenantId `
-ApplicationId $runAsConnectionProfile.ApplicationId `
-CertificateThumbprint ` $runAsConnectionProfile.CertificateThumbprint | Out-Null
Write-Output "Authenticated with Automation Run As Account."  | timestamp

#Get current date/time and convert to $scalingScheduleTimeZone
$stateConfig = $scalingSchedule | ConvertFrom-Json
$startTime = Get-Date
Write-Output "Azure Automation local time: $startTime." | timestamp
$toTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById($scalingScheduleTimeZone)
Write-Output "Time zone to convert to: $toTimeZone." | timestamp
$newTime = [System.TimeZoneInfo]::ConvertTime($startTime, $toTimeZone)
Write-Output "Converted time: $newTime." | timestamp
$startTime = $newTime

#Get current day of week, based on converted start time
$currentDayOfWeek = [Int]($startTime).DayOfWeek
Write-Output "Current day of week: $currentDayOfWeek." | timestamp

# Get the scaling schedule for the current day of week
$dayObjects = $stateConfig | Where-Object {$_.WeekDays -contains $currentDayOfWeek } `
|Select-Object Edition, Tier, `
@{Name="StartTime"; Expression = {[datetime]::ParseExact(($startTime.ToString("yyyy:MM:dd")+":"+$_.StartTime),"yyyy:MM:dd:HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)}}, `
@{Name="StopTime"; Expression = {[datetime]::ParseExact(($startTime.ToString("yyyy:MM:dd")+":"+$_.StopTime),"yyyy:MM:dd:HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)}}

# Get the database object
$sqlDB = Get-AzureRmSqlDatabase `
-ResourceGroupName $resourceGroupName `
-ServerName $serverName `
-DatabaseName $databaseName
Write-Output "DB name: $($sqlDB.DatabaseName)" | timestamp
Write-Output "Current DB status: $($sqlDB.Status), edition: $($sqlDB.Edition), tier: $($sqlDB.CurrentServiceObjectiveName)" | timestamp

if($dayObjects -ne $null) { # Scaling schedule found for this day
    # Get the scaling schedule for the current time. If there is more than one available, pick the first
    $matchingObject = $dayObjects | Where-Object { ($startTime -ge $_.StartTime) -and ($startTime -lt $_.StopTime) } | Select-Object -First 1
    if($matchingObject -ne $null)
    {
        Write-Output "Scaling schedule found. Check if current edition/tier is matching..." | timestamp
        if($sqlDB.CurrentServiceObjectiveName -ne $matchingObject.Tier -or $sqlDB.Edition -ne $matchingObject.Edition)
        {
            Write-Output "DB is not in the edition and/or tier of the scaling schedule. Changing!" | timestamp
            $sqlDB | Set-AzureRmSqlDatabase -Edition $matchingObject.Edition -RequestedServiceObjectiveName $matchingObject.Tier | out-null
            Write-Output "Change to edition/tier as specified in scaling schedule initiated..." | timestamp
            $sqlDB = Get-AzureRmSqlDatabase -ResourceGroupName $resourceGroupName -ServerName $serverName -DatabaseName $databaseName
            Write-Output "Current DB status: $($sqlDB.Status), edition: $($sqlDB.Edition), tier: $($sqlDB.CurrentServiceObjectiveName)" | timestamp
        }
        else
        {
            Write-Output "Current DB tier and edition matches the scaling schedule already. Exiting..." | timestamp
        }
    }
    else { # Scaling schedule not found for current time
        Write-Output "No matching scaling schedule time slot for this time found. Check if current edition/tier matches the default..." | timestamp
        if($sqlDB.CurrentServiceObjectiveName -ne $defaultTier -or $sqlDB.Edition -ne $defaultEdition)
        {
            Write-Output "DB is not in the default edition and/or tier. Changing!" | timestamp
            $sqlDB | Set-AzureRmSqlDatabase -Edition $defaultEdition -RequestedServiceObjectiveName $defaultTier | out-null
            Write-Output "Change to default edition/tier initiated." | timestamp
            $sqlDB = Get-AzureRmSqlDatabase -ResourceGroupName $resourceGroupName -ServerName $serverName -DatabaseName $databaseName
            Write-Output "Current DB status: $($sqlDB.Status), edition: $($sqlDB.Edition), tier: $($sqlDB.CurrentServiceObjectiveName)" | timestamp
        }
        else
        {
            Write-Output "Current DB tier and edition matches the default already. Exiting..." | timestamp
        }
    }
}
else # Scaling schedule not found for this day
{
    Write-Output "No matching scaling schedule for this day found. Check if current edition/tier matches the default..." | timestamp
    if($sqlDB.CurrentServiceObjectiveName -ne $defaultTier -or $sqlDB.Edition -ne $defaultEdition)
    {
        Write-Output "DB is not in the default edition and/or tier. Changing!" | timestamp
        $sqlDB | Set-AzureRmSqlDatabase -Edition $defaultEdition -RequestedServiceObjectiveName $defaultTier | out-null
        Write-Output "Change to default edition/tier initiated." | timestamp
        $sqlDB = Get-AzureRmSqlDatabase -ResourceGroupName $resourceGroupName -ServerName $serverName -DatabaseName $databaseName
        Write-Output "Current DB status: $($sqlDB.Status), edition: $($sqlDB.Edition), tier: $($sqlDB.CurrentServiceObjectiveName)" | timestamp
    }
    else
    {
        Write-Output "Current DB tier and edition matches the default already. Exiting..." | timestamp
    }
}

Write-Output "Script finished." | timestamp