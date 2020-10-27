Azure SQL Database - Scale using scheduled autoscaling
======================================================

            

This Azure Automation runbook enables vertically scaling of an Azure SQL Database according to a schedule. Autoscaling based on a schedule allows you to scale your solution according to predictable resource demand. For example you could require a high capacity
 (e.g. P2) on Monday during peak hours, while the rest of the week the traffic is decreased allowing you to scale down (e.g. P1). Outside business hours and during weekends you could then scale down further to a minimum (e.g. S0). This runbook can be scheduled
 to run hourly. The code checks the scalingSchedule parameter to decide if scaling needs to be executed, or if the database is in the desired state already and no work needs to be done. The script is Timezone aware.


jorgklein.com for more information and a step-by-step setup guide


 

 


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

    Weekdays start at 0 (sunday) and end at 6 (saturday).

    If the script is executed outside the scaling schedule time slots

    that you defined, the defaut edition/tier (see below) will be 

    configured.



.PARAMETER scalingScheduleTimeZone

    Time Zone of time slots in $scalingSchedule. 

    Available time zones: [System.TimeZoneInfo]::GetSystemTimeZones().



.PARAMETER defaultEdition

    Azure SQL Database Edition that wil be used outside the slots 

    specified in the scalingSchedule paramater value.

    Example values: Basic, Standard, Premium RS, Premium.

    For more information on editions/tiers levels, 

    http://msdn.microsoft.com/en-us/library/azure/dn741336.aspx 

 

.PARAMETER defaultTier   

    Azure SQL Database Tier that wil be used outside the slots 

    specified in the scalingSchedule paramater value.

    Example values: Basic, S0, S1, S2, S3, PRS1, PRS2, PRS4, 

    PRS6, P1, P2, P4, P6, P11, P15.



.EXAMPLE

        -resourceGroupName myResourceGroup

        -azureRunAsConnectionName AzureRunAsConnection

        -serverName myserver

        -databaseName myDatabase

        -scalingSchedule [{WeekDays:[1], StartTime:'06:59:59', 

            StopTime:'17:59:59', Edition: 'Premium', Tier: 'P2'},

            {WeekDays:[2,3,4,5], StartTime:'06:59:59', 

            StopTime:'17:59:59', Edition: 'Premium', Tier: 'P1'}]

        -scalingScheduleTimeZone W. Europe Standard Time

        -defaultEdition Standard

        -defaultTier S0

   

.NOTES   

    Author: Jorg Klein

    Last Update: 18/09/2017   

#>  

param(

[parameter(Mandatory=$true)]

[string] $resourceGroupName,



[parameter(Mandatory=$true)]

[string] $azureRunAsConnectionName,



[parameter(Mandatory=$true)]

[string] $serverName,



[parameter(Mandatory=$true)]

[string] $databaseName,



[parameter(Mandatory=$true)]

[string] $scalingSchedule,



[parameter(Mandatory=$true)]

[string] $scalingScheduleTimeZone,



[parameter(Mandatory=$true)]

[string] $defaultEdition,



[parameter(Mandatory=$true)]

[string] $defaultTier

)



Write-Output 'Script started.'



#Authenticate with Azure Automation Run As account (service principal)  

$runAsConnectionProfile = Get-AutomationConnection `

-Name $azureRunAsConnectionName

Add-AzureRmAccount -ServicePrincipal `

-TenantId $runAsConnectionProfile.TenantId `

-ApplicationId $runAsConnectionProfile.ApplicationId `

-CertificateThumbprint ` $runAsConnectionProfile.CertificateThumbprint | Out-Null

Write-Output 'Authenticated with Automation Run As Account.'



#Get current date/time and convert to $scalingScheduleTimeZone

$stateConfig = $scalingSchedule | ConvertFrom-Json

$startTime = Get-Date

Write-Output 'Azure Automation local time: $startTime.'

$toTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById($scalingScheduleTimeZone)

Write-Output 'Time zone to convert to: $toTimeZone.'

$newTime = [System.TimeZoneInfo]::ConvertTime($startTime, $toTimeZone)

Write-Output 'Converted time: $newTime.'

$startTime = $newTime



#Get current day of week, based on converted start time

$currentDayOfWeek = [Int]($startTime).DayOfWeek

Write-Output 'Current day of week: $currentDayOfWeek.'



# Get the scaling schedule for the current day of week

$dayObjects = $stateConfig | Where-Object {$_.WeekDays -contains $currentDayOfWeek } `

|Select-Object Edition, Tier, `

@{Name='StartTime'; Expression = {[datetime]::ParseExact($_.StartTime,'HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)}}, `

@{Name='StopTime'; Expression = {[datetime]::ParseExact($_.StopTime,'HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)}}



# Get the database object

$sqlDB = Get-AzureRmSqlDatabase `

-ResourceGroupName $resourceGroupName `

-ServerName $serverName `

-DatabaseName $databaseName

Write-Output 'DB name: $($sqlDB.DatabaseName)'

Write-Output 'Current DB status: $($sqlDB.Status), edition: $($sqlDB.Edition), tier: $($sqlDB.CurrentServiceObjectiveName)'



if($dayObjects -ne $null) { # Scaling schedule found for this day

    # Get the scaling schedule for the current time. If there is more than one available, pick the first

    $matchingObject = $dayObjects | Where-Object { ($startTime -ge $_.StartTime) -and ($startTime -lt $_.StopTime) } | Select-Object -First 1

    if($matchingObject -ne $null)

    {

        Write-Output 'Scaling schedule found. Check if current edition & tier is matching...'

        if($sqlDB.CurrentServiceObjectiveName -ne $matchingObject.Tier -or $sqlDB.Edition -ne $matchingObject.Edition)

        {

            Write-Output 'DB is not in the edition and/or tier of the scaling schedule. Changing!'

            $sqlDB | Set-AzureRmSqlDatabase -Edition $matchingObject.Edition -RequestedServiceObjectiveName $matchingObject.Tier | out-null

            Write-Output 'Change to edition/tier as specified in scaling schedule initiated...'

            $sqlDB = Get-AzureRmSqlDatabase -ResourceGroupName $resourceGroupName -ServerName $serverName -DatabaseName $databaseName

            Write-Output 'Current DB status: $($sqlDB.Status), edition: $($sqlDB.Edition), tier: $($sqlDB.CurrentServiceObjectiveName)'

        } 

        else 

        {

            Write-Output 'Current DB tier and edition matches the scaling schedule already. Exiting...'

        }

    }

    else { # Scaling schedule not found for current time

        Write-Output 'No matching scaling schedule time slot for this time found. Check if current edition/tier matches the default...'

        if($sqlDB.CurrentServiceObjectiveName -ne $defaultTier -or $sqlDB.Edition -ne $defaultEdition)

        {

            Write-Output 'DB is not in the default edition and/or tier. Changing!'

            $sqlDB | Set-AzureRmSqlDatabase -Edition $defaultEdition -RequestedServiceObjectiveName $defaultTier | out-null

            Write-Output 'Change to default edition/tier initiated.'

            $sqlDB = Get-AzureRmSqlDatabase -ResourceGroupName $resourceGroupName -ServerName $serverName -DatabaseName $databaseName

            Write-Output 'Current DB status: $($sqlDB.Status), edition: $($sqlDB.Edition), tier: $($sqlDB.CurrentServiceObjectiveName)'

        }

        else

        {

            Write-Output 'Current DB tier and edition matches the default already. Exiting...'

        }

    }

}

else # Scaling schedule not found for this day

{

    Write-Output 'No matching scaling schedule for this day found. Check if current edition/tier matches the default...'

    if($sqlDB.CurrentServiceObjectiveName -ne $defaultTier -or $sqlDB.Edition -ne $defaultEdition)

    {

        Write-Output 'DB is not in the default edition and/or tier. Changing!'

        $sqlDB | Set-AzureRmSqlDatabase -Edition $defaultEdition -RequestedServiceObjectiveName $defaultTier | out-null

        Write-Output 'Change to default edition/tier initiated.'

        $sqlDB = Get-AzureRmSqlDatabase -ResourceGroupName $resourceGroupName -ServerName $serverName -DatabaseName $databaseName

        Write-Output 'Current DB status: $($sqlDB.Status), edition: $($sqlDB.Edition), tier: $($sqlDB.CurrentServiceObjectiveName)'

    }

    else

    {

        Write-Output 'Current DB tier and edition matches the default already. Exiting...'

    }

}



Write-Output 'Script finished.'


        
    
TechNet gallery is retiring! This script was migrated from TechNet script center to GitHub by Microsoft Azure Automation product group. All the Script Center fields like Rating, RatingCount and DownloadCount have been carried over to Github as-is for the migrated scripts only. Note : The Script Center fields will not be applicable for the new repositories created in Github & hence those fields will not show up for new Github repositories.
