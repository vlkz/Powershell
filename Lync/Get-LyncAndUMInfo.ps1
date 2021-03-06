function Get-LyncAndUMInfo {
    <#
    .SYNOPSIS
    Gather lync enabled user information for current domain.
    .DESCRIPTION
    Gather lync enabled user information for current domain. This is meant to be run on a Lync server and uses both the Lync
    and AD modules. Exchange UM information is pulled directly from AD attributes. Information gathered includes:
        Name                    -> AD account name
        Enabled                 -> AD enabled state
        FirstName               -> First Name
        LastName                -> Last Name
        Email                   -> Email as seen in AD
        SipAddress              -> Primary sip address
        ADPhone                 -> Primary telephone number from AD
        EnterpriseVoiceEnabled  -> If the account is enterprise voice enabled or not
        DialPlan                -> Lync dial plan
        VoicePolicy             -> Lync voice policy
        LyncPinSet              -> If a Lync pin is set
        LyncTelURI              -> Full Lync phone URI
        LyncPrivateLine         -> Private phone URI if assigned
        LyncPhone               -> Primary phone of URI (tel:+#########)
        LyncPhoneExt            -> Extension of URI (;ext=####)
        VoicemailEnabled        -> If the account is voicemail enabled
        VoicemailExtension      -> The voicemail extension (EUM smtp proxy address)

    The UM enabled auto-attendant information is pulled directly from contacts in AD as well.
    .EXAMPLE
    $Users = Get-LyncAndUMInfo
    $Users | Export-Csv AllLyncEnabledUserInfo.csv -NoTypeInformation
    $Users | where {(-not $_.Enabled) -and $_.EnterpriseVoiceEnabled} | Export-Csv DisabledWithLyncNumbersStillAssigned.csv -NoTypeInformation
    $Users | where {$_.Enabled -and $_.EnterpriseVoiceEnabled -and (-not $_.LyncPinSet)} | Export-Csv EnabledWithLyncNumbersAssignedButNoPINSet.csv -NoTypeInformation
    $Users | where {$_.Enabled -and $_.EnterpriseVoiceEnabled -and (-not $_.VoicemailEnabled)} | Export-Csv EnabledWithLyncNumbersAssignedButNoVoicemailConfigured.csv -NoTypeInformation

    Description
    -----------
    Collects information about all Lync enabled users in the domain and creates 4 reports.

    1. AllLyncEnabledUserInfo.csv -> All information gathered with this function
    2. DisabledWithLyncNumbersStillAssigned.csv -> All disabled accounts still enterprise voice enabled
    3. EnabledWithLyncNumbersAssignedButNoPINSet.csv -> All enterprise voice enabled accounts without a set pin
    4. EnabledWithLyncNumbersAssignedButNoVoicemailConfigured.csv -> All enterprise voice enabled accounts without voicemail boxes configured

    .OUTPUTS
    PSObject
    .LINK
    http://the-little-things.net/
    .LINK
    https://github.com/zloeber/Powershell
    .NOTES
    Author:  Zachary Loeber
    Version History: 
        11/09/2014
        - Created script
        02/07/2015
        - Added AD telephone number to output
    #>
    [CmdletBinding()] 
    param ()
    begin {
        Import-Module Lync -ErrorAction:SilentlyContinue -Verbose:$false
        if ((get-module lync) -eq $null) {
            Write-Warning "Get-LyncAndUMInfo: This script must be run on a lync server. Exiting!"
            Break
        }
        $ADUserProperties = @('Name','GivenName','Surname','SamAccountName','mail','proxyAddresses','msRTCSIP-UserEnabled','msRTCSIP-Line','msExchUMEnabledFlags','msExchUMDtmfMap','msRTCSIP-PrimaryUserAddress','telephoneNumber')
        $ADContactProperties = @('Name','GivenName','sn','mail','msRTCSIP-Line','msRTCSIP-PrimaryUserAddress')
    }
    process {}
    end {
        Get-ADUser -Verbose:$false -LDAPFilter "(&(objectCategory=person)(objectClass=user)(msRTCSIP-UserEnabled=*))" -Properties $ADUserProperties | Where {($_.'msRTCSIP-UserEnabled' -ne $null) -and ($_.'msRTCSIP-UserEnabled' -ne $false)} | Foreach {
            Write-Verbose "Get-LyncAndUMInfo: Processing User - $($_.Name)($($_.'msRTCSIP-PrimaryUserAddress'))"
            $LyncInfo = Get-CSUser -Verbose:$false $_.'msRTCSIP-PrimaryUserAddress' | Select SipAddress,EnterpriseVoiceEnabled,ExUmEnabled,DialPlan,VoicePolicy,PrivateLine, `
                                                    @{'n'='LyncPINSet';'e'={if ($_.EnterpriseVoiceEnabled){($_ | Get-CSClientPinInfo -Verbose:$false).IsPinSet} else {$false}}}
            if ($LyncInfo.ExUmEnabled) {
                $VoicemailExtension = $_.proxyAddresses | Where {$_ -match '^eum:(\d+).*$'} | Foreach {$Matches[1]}
            }
            else {
                $VoicemailExtension = $null
            }
            $UserProps = @{
                'Name' = $_.Name
                'Type' = 'User'
                'Enabled' = $_.Enabled
                'FirstName' = $_.GivenName
                'LastName' = $_.Surname
                'Email' = $_.mail
                'ADPhone' = $_.telephoneNumber
                'SipAddress' = $LyncInfo.SipAddress
                'EnterpriseVoiceEnabled' = $LyncInfo.EnterpriseVoiceEnabled
                'DialPlan' = $LyncInfo.DialPlan
                'VoicePolicy' = $LyncInfo.VoicePolicy
                'LyncPinSet' = $LyncInfo.LyncPinSet
                'LyncTelURI' = $_.'msRTCSIP-Line'
                'LyncPrivateLine' = $LyncInfo.PrivateLine
                'LyncPhone' = if ($_.'msRTCSIP-Line' -match '^tel:(\+\d+).*$'){$matches[1]} else {$null}
                'LyncPhoneExt' = if ($_.'msRTCSIP-Line' -match '^.*ext=(.*)$'){$matches[1]} else {$null}
                'VoicemailEnabled' = $LyncInfo.ExUmEnabled
                'VoicemailExtension' = $VoicemailExtension
            }
            New-Object PSObject -Property $UserProps
        }
        # Get any auto-attendants and subscriber access ad objects
        Get-ADObject -Verbose:$false -LDAPFilter "(&(objectCategory=person)(objectClass=contact)(msRTCSIP-Line=*))" -Properties $ADContactProperties | Foreach {
            $UserProps = @{
                'Name' = $_.Name
                'Type' = 'Contact'
                'Enabled' = $null
                'FirstName' = $_.GivenName
                'LastName' = $_.sn
                'Email' = $_.mail
                'ADPhone' = $_.telephoneNumber
                'SipAddress' = $_.'msRTCSIP-PrimaryUserAddress'
                'EnterpriseVoiceEnabled' = $null
                'DialPlan' = $null
                'VoicePolicy' = $null
                'LyncPinSet' = $null
                'LyncTelURI' = $_.'msRTCSIP-Line'
                'LyncPrivateLine' = $null
                'LyncPhone' = if ($_.'msRTCSIP-Line' -match '^tel:(\+\d+).*$'){$matches[1]} else {$null}
                'LyncPhoneExt' = if ($_.'msRTCSIP-Line' -match '^.*ext=(.*)$'){$matches[1]} else {$null}
                'VoicemailEnabled' = $null
                'VoicemailExtension' = $null
            }
            New-Object PSObject -Property $UserProps
        }
    }
}