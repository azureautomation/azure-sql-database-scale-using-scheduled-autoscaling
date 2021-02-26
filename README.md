# Azure SQL Database - Scale using scheduled autoscaling

## Description

This Azure Automation runbook enables vertically scaling of an Azure SQL Database according to a schedule. Autoscaling based on a schedule allows you to scale your solution according to predictable resource demand. For example you could require a high capacity (e.g. P2) on Monday during peak hours, while the rest of the week the traffic is decreased allowing you to scale down (e.g. P1). Outside business hours and during weekends you could then scale down further to a minimum (e.g. S0). This runbook can be scheduled to run hourly. The code checks the scalingSchedule parameter to decide if scaling needs to be executed, or if the database is in the desired state already and no work needs to be done. The script is Timezone aware.

jorgklein.com for more information and a step-by-step setup guide


## Requirements

* Azure Automation Account
  * Import this runbook: Process Automation.Runbooks
  * Install Shared Resources.Modules = `AzureRM.Automation` + `AzureRM.Sql`

## Parameters

```
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
    Last Update: February 2021
```

> TechNet gallery is retiring! This script was migrated from TechNet script center to GitHub by Microsoft Azure Automation product group. All the Script Center fields like Rating, RatingCount and DownloadCount have been carried over to Github as-is for the migrated scripts only. Note : The Script Center fields will not be applicable for the new repositories created in Github & hence those fields will not show up for new Github repositories.
