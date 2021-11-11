# There are 3 places you need to edit:
# YOURAPIIDHERE
# YOURAPISECRETHERE
# YOURGROUPIDHERE


﻿##Exit if not PS5
$shell = $PSVersionTable.PSVersion.Major
If ($shell -lt 5){
    New-Item -Path "C:\" -Name "CSUninstall" -ItemType "Directory"
    New-Item -Path "C:\CSUninstall\" -Name "Uninstall.log" -Value "Current Powershell Version ($shell) Unsupported"
    Remove-Item -Path "$PSCommandPath"
    Exit
}

# Set initial script variables
$scriptPath=$MyInvocation.MyCommand.Path
$scriptWorkingDirectory=split-path($scriptPath)


## Setup Variables for API call
$api = @{
    'client_id' = 'YOURAPIIDHERE'
    'client_secret' = 'YOURAPISECRETHERE'
}
## Gather the machines AID
$aid = [System.BitConverter]::ToString( ((Get-ItemProperty 'HKLM:\SYSTEM\CrowdStrike\{9b03c1d9-3138-44ed-9fae-d9f4c034b88d}\{16e0423f-7058-48c9-a204-725362b67639}\Default' -Name AG).AG)).ToLower() -replace '-',''

## Setup API call and gather token
$token_url =  'https://api.crowdstrike.com/oauth2/token'
$token = (Invoke-RestMethod -Method Post -Uri $token_url -Body $api).access_token

## Request uninstall token
$machine = (Get-CimInstance -ClassName Win32_ComputerSystem).Name
$user = Get-WmiObject Win32_Process -Filter "Name='explorer.exe'" |
  ForEach-Object { $_.GetOwner() } |
  Select-Object -Unique -Expand User
$time = Get-Date
$header = @{
    accept = "application/json"
    authorization = "bearer $token"
    "Content-Type" = "application/json"
}
$uninstall = ConvertTo-Json @{
    audit_message = "Check logs for $time, $user, $machine"
    device_id = $aid
}

$uninstall_url = 'https://api.crowdstrike.com/policy/combined/reveal-uninstall-token/v1'
$uninstall_call = (Invoke-RestMethod -Method Post -Uri $uninstall_url -Headers $header -Body $uninstall).resources
$uninstall_token = $uninstall_call.uninstall_token

## Add to Uninstall Group
$group = '{
    "action_parameters": [
        {
            "name": "filter",
            "value": "(device_id:['+"`'"+${aid}+"`'"+'])"
        }
    ],
    "ids": [
        "YOURGROUPIDHERE"
    ]
}'

$group_url = 'https://api.crowdstrike.com/devices/entities/host-group-actions/v1?action_name=add-hosts'
Invoke-RestMethod -Method Post -Uri $group_url -Headers $header -Body $group | Out-Null

Start-Sleep -s 5

## Uninstall Crowdstrike Sensor

$argumentList="MAINTENANCE_TOKEN=$uninstall_token /quiet"
start-process ".\CsUninstallTool.exe" -argumentlist $argumentList -workingdirectory $scriptWorkingDirectory -Wait -NoNewWindow

Start-Sleep -Seconds 10

$Title = "Crowdstrike Uninstaller"
$fail = "Crowdstrike Uninstall Failed"
$finish = "Crowdstrike Successfully Uninstalled"
If (Test-Path "C:\Windows\System32\drivers\CrowdStrike"){[System.Windows.MessageBox]::Show($fail,$Title,$ok,$icon)}
ElseIf (Test-Path "HKLM:\System\Crowdstrike"){[System.Windows.MessageBox]::Show($fail,$Title,$ok,$icon)}
Else{[System.Windows.MessageBox]::Show($finish,$Title,$ok,$icon)}
Remove-Item -Path "$PSCommandPath"

