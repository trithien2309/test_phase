# Note:
# Script to check policy was applied to windows host
# Requires -RunAsAdministrator
# Run script by: .\checkGPOconfig-v1.2.ps1
# If running scripts is disabled on this system, try: PowerShell.exe -ExecutionPolicy Bypass -File .\checkGPOconfig-v1.2.ps1

$audits = '[{"name":"Directory Service Changes","value":"Success"},{"name":"Security Group Management","value":"Success"},{"name":"Special Logon","value":"Success"},{"name":"Logon","value":"Success and Failure"},{"name":"Account Lockout","value":"Failure"},{"name":"Other Account Management Events","value":"Success"},{"name":"Sensitive Privilege Use","value":"Success"},{"name":"Audit Policy Change","value":"Success"},{"name":"User Account Management","value":"Success"},{"name":"Process Creation","value":"Success"}]' | ConvertFrom-Json

$policy = @("Include command line in process creation events", "Turn on Module Logging", "Turn on PowerShell Script Block Logging")

auditpol.exe /get /category:* /r > .\auditpol.csv
$CSV = Import-CSV .\auditpol.csv

Write-Host "====================" -ForegroundColor Yellow 
Write-Host "CHECK THE CONFIG GPO" -ForegroundColor Yellow 

$audits | ForEach-Object {
    $i = $_

    if ( $i.name -in $CSV.Subcategory) {
        $CSV | Where-Object Subcategory -eq $i.name | ForEach-Object {
            if ($_.'Inclusion Setting' -contains $i.value) {
                Write-Host ($i.name, "is configured successfully") -ForegroundColor Green
            }
            else {
                Write-Host ($i.name, "is configured failure") -ForegroundColor Green
            }
        }
    }
    else {
        Write-Host ($i.name, "is configured failure") -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "CHECK THE CONFIG Policy" -ForegroundColor Yellow 

$testPath_1 = test-path -path "hklm:software\microsoft\windows\currentversion\policies\system\audit"
$testPath_2 = test-path -path "hklm:Software\Policies\Microsoft\Windows\PowerShell\ModuleLogging"
$testPath_3 = test-path -path "hklm:Software\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"

if (($testPath_1)){
    $val1 = Get-ItemProperty -Path hklm:software\microsoft\windows\currentversion\policies\system\audit
    if ($val1.ProcessCreationIncludeCmdLine_Enabled -eq 1 ) {
        Write-Host ($policy[0], "is configured successfully") -ForegroundColor Green
    }
    else {
        Write-Host ($policy[0], "is configured failure") -ForegroundColor Red
    }
}
else {
    Write-Host ($policy[0], "is configured failure") -ForegroundColor Red
}

if (($testPath_2)){
    $val2 = Get-ItemProperty -Path hklm:Software\Policies\Microsoft\Windows\PowerShell\ModuleLogging
    if ($val2.EnableModuleLogging -eq 1 ) {
        Write-Host ($policy[1], "is configured successfully") -ForegroundColor Green
    }
    else {
        Write-Host ($policy[1], "is configured failure") -ForegroundColor Red
    }
}
else {
    Write-Host ($policy[1], "is configured failure") -ForegroundColor Red
}

if (($testPath_3)){
    $val3 = Get-ItemProperty -Path hklm:Software\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging
    if ($val3.EnableScriptBlockLogging -eq 1 ) {
        Write-Host ($policy[2], "is configured successfully") -ForegroundColor Green
    }
    else {
        Write-Host ($policy[2], "is configured failure") -ForegroundColor Red
    }
}
else {
    Write-Host ($policy[2], "is configured failure") -ForegroundColor Red
}




