@echo off
::
:: Windows Server 2012 R2 Standard
:: Windows Server 2016 Datacenter
:: Windows 10 Pro
:: Windows Server 2008 R2 Standard
:: Windows Server 2019 Standard
::
::#######################################################################
::
:: SET THE LOG SIZE - What local size they will be
:: ---------------------
echo Set the log size ...
:: 
wevtutil sl Security /ms:1048576000 
::
wevtutil sl System /ms:262144000
::
wevtutil sl "Windows Powershell" /ms:262144000
::
wevtutil sl "Microsoft-Windows-PowerShell/Operational" /ms:524288000
::
wevtutil sl "Microsoft-Windows-Sysmon/Operational" /ms:524288000
::
echo Set the log size completed
::
:: ---------------------------------------------------------------------
:: ENABLE The Winrm log
:: ---------------------------------------------------------------------
::
echo Enable The Winrm log ...
::
wevtutil sl "Microsoft-Windows-WinRM/Operational" /e:true
::
echo Enable The Winrm log completed
::
::#######################################################################
::
:: SET Events to log the Command Line
:: ---------------------
::
echo Set events to log the Command Line ...
::
reg add "hklm\software\microsoft\windows\currentversion\policies\system\audit" /v ProcessCreationIncludeCmdLine_Enabled /t REG_DWORD /d 1 /f
::
echo Set events to log the Command Line completed
::
::  Force Advance Audit Policy
::
echo Force Advance Audit Policy ...
::
Reg add "hklm\System\CurrentControlSet\Control\Lsa" /v SCENoApplyLegacyAuditPolicy /t REG_DWORD /d 1 /f
::
echo Force Advance Audit Policy completed
::
::  Set Module Logging for PowerShell
::
echo Set module logging for powershell ...
::
reg add "hklm\Software\Policies\Microsoft\Windows\PowerShell\ModuleLogging" /v EnableModuleLogging /t REG_DWORD /d 1 /f
reg add "hklm\Software\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" /v EnableScriptBlockLogging /t REG_DWORD /d 1 /f
::
echo Set module logging for powershell completed
::
::#######################################################################
::
:: CAPTURE THE SETTINGS - BEFORE they have been modified
:: ---------------------
::
echo Capture the settings before they been modified ...
::
Auditpol /get /category:* > AuditPol_BEFORE_%computername%.txt
::
echo Capture the settings before they been modified completed
::
::
::#######################################################################
::#######################################################################
::
echo Setting group policy ...
::
:: ACCOUNT MANAGEMENT
:: ---------------------
::
:: Sets - the entire category - Auditpol /set /category:"Account Management" /success:enable /failure:enable
::
Auditpol /set /subcategory:"Security Group Management" /success:enable
Auditpol /set /subcategory:"Other Account Management Events" /success:enable
Auditpol /set /subcategory:"User Account Management" /success:enable
::
::#######################################################################
::
:: Detailed Tracking
:: ---------------------
::
Auditpol /set /subcategory:"Process Creation" /success:enable
::
::#######################################################################
::
:: DS Access
:: ---------------------
::
Auditpol /set /subcategory:"Directory Service Changes" /success:enable
Auditpol /set /subcategory:"Directory Service Access" /success:enable
::
::#######################################################################
::
:: Logon/Logoff
:: ---------------------
::
Auditpol /set /subcategory:"Account Lockout" /failure:enable
Auditpol /set /subcategory:"Logon" /success:enable /failure:enable
Auditpol /set /subcategory:"Special Logon" /success:enable
::
::#######################################################################
::
:: Object Access
:: ---------------------
:: WARNING:  This next item is a VERY noisy items and requires the Windows Firewall to be in at least an ALLOW ALLOW configuration in Group Ploicy
::
Auditpol /set /subcategory:"File Share" /success:enable
Auditpol /set /subcategory:"Other Object Access Events" /success:enable
Auditpol /set /subcategory:"Filtering Platform Packet Drop" /success:disable /failure:disable
Auditpol /set /subcategory:"Filtering Platform Connection" /success:disable /failure:disable
::
::#######################################################################
::
:: Policy Change
:: ---------------------
::
Auditpol /set /subcategory:"Audit Policy Change" /success:enable
Auditpol /set /subcategory:"Authentication Policy Change" /success:enable
::
::#######################################################################
::
:: Privilege Use
:: ---------------------
::
Auditpol /set /subcategory:"Sensitive Privilege Use" /success:enable
::
echo 'Setting group policy completed'
::
::#######################################################################
::
:: CAPTURE THE SETTINGS - AFTER they have been modified
:: ---------------------
::
echo Capture the settings after they have been modified ...
::
Auditpol /get /category:* > AuditPol_AFTER_%computername%.txt
::
echo Capture the settings after they have been modified completed
::
echo:
echo *****************
echo Setting completed
::
:: The End
::
