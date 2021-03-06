Function Get-RemoteRolesAndFeatures
{
    <#
    .SYNOPSIS
        Gather remote installed roles and features from a windows server or workstation.
    .DESCRIPTION
        Gather remote installed roles and features from a windows server or workstation. Workstation features get stored in OptionalFeatures, 
        servers which are 2008 or greater are stored in Win2008Features
    .PARAMETER ComputerName
        Specifies the target computer for data query.
    .PARAMETER ThrottleLimit
        Specifies the maximum number of systems to inventory simultaneously 
    .PARAMETER Timeout
        Specifies the maximum time in second command can run in background before terminating this thread.
    .PARAMETER ShowProgress
        Show progress bar information
    .EXAMPLE
        PS > (Get-RemoteRolesAndFeatures).Win2008Features
 
        Name                            ID           ParentID
        ----                            --           --------
        File Services                    6                  0
        Active Directory Domain Serv... 10                  0
        
        Description
        -----------
        Get the roles and features installed on the localhost and display the results.
    .NOTES
        Author: Zachary Loeber
        Requires: Powershell 2.0

        Version History
        1.0.1: 12/17/2013
        - Initial release

        1.0.0: 10/12/2013
        - Initial creation
    .LINK
        http://www.the-little-things.net/
    .LINK
        http://nl.linkedin.com/in/zloeber
    #>
    [CmdletBinding()]
    PARAM
    (
        [Parameter(HelpMessage="Computer or computers to gather information from",
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        [ValidateNotNullOrEmpty()]
        [Alias('DNSHostName','PSComputerName')]
        [string[]]
        $ComputerName=$env:computername,
       
        [Parameter(HelpMessage="Maximum number of concurrent threads")]
        [ValidateRange(1,65535)]
        [int32]
        $ThrottleLimit = 32,
 
        [Parameter(HelpMessage="Timeout before a thread stops trying to gather the information")]
        [ValidateRange(1,65535)]
        [int32]
        $Timeout = 120,
 
        [Parameter(HelpMessage="Display progress of function")]
        [switch]
        $ShowProgress,
        
        [Parameter(HelpMessage="Set this if you want the function to prompt for alternate credentials")]
        [switch]
        $PromptForCredential,
        
        [Parameter(HelpMessage="Set this if you want to provide your own alternate credentials")]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty
    )

    BEGIN
    {
        # Gather possible local host names and IPs to prevent credential utilization in some cases
        Write-Verbose -Message 'Roles And Features: Creating local hostname list'
        $IPAddresses = [net.dns]::GetHostAddresses($env:COMPUTERNAME) | Select-Object -ExpandProperty IpAddressToString
        $HostNames = $IPAddresses | ForEach-Object {
            try {
                [net.dns]::GetHostByAddress($_)
            } catch {
                # We do not care about errors here...
            }
        } | Select-Object -ExpandProperty HostName -Unique
        $LocalHost = @('', '.', 'localhost', $env:COMPUTERNAME, '::1', '127.0.0.1') + $IPAddresses + $HostNames
 
        Write-Verbose -Message 'Roles And Features: Creating initial variables'
        $runspacetimers       = [HashTable]::Synchronized(@{})
        $runspaces            = New-Object -TypeName System.Collections.ArrayList
        $bgRunspaceCounter    = 0
        
        if ($PromptForCredential)
        {
            $Credential = Get-Credential
        }
        
        Write-Verbose -Message 'Roles And Features: Creating Initial Session State'
        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        foreach ($ExternalVariable in ('runspacetimers', 'Credential', 'LocalHost'))
        {
            Write-Verbose -Message "Roles And Features: Adding variable $ExternalVariable to initial session state"
            $iss.Variables.Add((New-Object -TypeName System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList $ExternalVariable, (Get-Variable -Name $ExternalVariable -ValueOnly), ''))
        }
        
        Write-Verbose -Message 'Roles And Features: Creating runspace pool'
        $rp = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $ThrottleLimit, $iss, $Host)
        $rp.ApartmentState = 'STA'
        $rp.Open()
 
        # This is the actual code called for each computer
        Write-Verbose -Message 'Roles And Features: Defining background runspaces scriptblock'
        $ScriptBlock = {
            [CmdletBinding()]
            Param
            (
                [Parameter(Position=0)]
                [string]
                $ComputerName,
 
                [Parameter(Position=1)]
                [int]
                $bgRunspaceID
            )
            $runspacetimers.$bgRunspaceID = Get-Date
            
            try
            {
                Write-Verbose -Message ('Roles And Features: Runspace {0}: Start' -f $ComputerName)
                $WMIHast = @{
                    ComputerName = $ComputerName
                    ErrorAction = 'Stop'
                }
                if (($LocalHost -notcontains $ComputerName) -and ($Credential -ne $null))
                {
                    $WMIHast.Credential = $Credential
                }

                # General variables
                $PSDateTime = Get-Date
                
                #region Get Optional Features
                Write-Verbose -Message ('Roles And Features: Runspace {0}: information' -f $ComputerName)

                # Modify this variable to change your default set of display properties
                $defaultProperties    = @('ComputerName','OptionalFeatures','Win2008Features')
                                                         
                # WMI data
                $wmi_optfeatures = Get-WmiObject @WMIHast -Class Win32_OptionalFeature
                
                $OptionalFeatures = @()
                $Win2008Features = @()
                foreach ($optfeature in $wmi_optfeatures)
                {
                    if ($optfeature.InstallState -eq 1)
                    {
                        $OptionalFeaturesProperty = @{
                            'Name' = $optfeature.Name
                            'Caption' = $optfeature.Caption
                        }
                        $OptionalFeatures += New-Object -TypeName PSObject -Property $OptionalFeaturesProperty
                    }
                }
                try
                {
                    $wmi_2008features = Get-WmiObject @WMIHast -Class Win32_ServerFeature
                    foreach ($win2008feature in $wmi_2008features)
                    {
                        $Win2008FeatureProperty = @{
                            'Name' = $win2008feature.Name
                            'ID' = $win2008feature.ID
                            'ParentID' = $win2008feature.ParentID
                        }
                        $Win2008Features += New-Object -TypeName PSObject -Property $Win2008FeatureProperty
                    }
                }
                catch
                {
                    Write-Verbose -Message ('Roles And Features: {0}: Class not available (System is likely not Windows 2008 or above)' -f $ComputerName)
                }
                $ResultProperty = @{
                    'PSComputerName' = $ComputerName
                    'PSDateTime' = $PSDateTime
                    'ComputerName' = $ComputerName
                    'OptionalFeatures' = $OptionalFeatures
                    'Win2008Features' = $Win2008Features
                }
                $ResultObject = New-Object -TypeName PSObject -Property $ResultProperty
                
                # Setup the default properties for output
                $ResultObject.PSObject.TypeNames.Insert(0,'My.WindowsFeatures.Info')
                $defaultDisplayPropertySet = New-Object System.Management.Automation.PSPropertySet('DefaultDisplayPropertySet',[string[]]$defaultProperties)
                $PSStandardMembers = [System.Management.Automation.PSMemberInfo[]]@($defaultDisplayPropertySet)
                $ResultObject | Add-Member MemberSet PSStandardMembers $PSStandardMembers

                Write-Output -InputObject $ResultObject
                #endregion Data Collection
            }
            catch
            {
                Write-Warning -Message ('Roles And Features: {0}: {1}' -f $ComputerName, $_.Exception.Message)
            }
            Write-Verbose -Message ('Roles And Features: Runspace {0}: End' -f $ComputerName)
        }
 
        Function Get-Result
        {
            [CmdletBinding()]
            Param 
            (
                [switch]$Wait
            )
            do
            {
                $More = $false
                foreach ($runspace in $runspaces)
                {
                    $StartTime = $runspacetimers.($runspace.ID)
                    if ($runspace.Handle.isCompleted)
                    {
                        Write-Verbose -Message ('Roles And Features: Thread done for {0}' -f $runspace.IObject)
                        $runspace.PowerShell.EndInvoke($runspace.Handle)
                        $runspace.PowerShell.Dispose()
                        $runspace.PowerShell = $null
                        $runspace.Handle = $null
                    }
                    elseif ($runspace.Handle -ne $null)
                    {
                        $More = $true
                    }
                    if ($Timeout -and $StartTime)
                    {
                        if ((New-TimeSpan -Start $StartTime).TotalSeconds -ge $Timeout -and $runspace.PowerShell)
                        {
                            Write-Warning -Message ('Timeout {0}' -f $runspace.IObject)
                            $runspace.PowerShell.Dispose()
                            $runspace.PowerShell = $null
                            $runspace.Handle = $null
                        }
                    }
                }
                if ($More -and $PSBoundParameters['Wait'])
                {
                    Start-Sleep -Milliseconds 100
                }
                foreach ($threat in $runspaces.Clone())
                {
                    if ( -not $threat.handle)
                    {
                        Write-Verbose -Message ('Roles And Features: Removing {0} from runspaces' -f $threat.IObject)
                        $runspaces.Remove($threat)
                    }
                }
                if ($ShowProgress)
                {
                    $ProgressSplatting = @{
                        Activity = 'Roles And Features: Getting info'
                        Status = 'Roles And Features: {0} of {1} total threads done' -f ($bgRunspaceCounter - $runspaces.Count), $bgRunspaceCounter
                        PercentComplete = ($bgRunspaceCounter - $runspaces.Count) / $bgRunspaceCounter * 100
                    }
                    Write-Progress @ProgressSplatting
                }
            }
            while ($More -and $PSBoundParameters['Wait'])
        }
    }
    PROCESS
    {
        foreach ($Computer in $ComputerName)
        {
            $bgRunspaceCounter++
            $psCMD = [System.Management.Automation.PowerShell]::Create().AddScript($ScriptBlock)
            $null = $psCMD.AddParameter('bgRunspaceID',$bgRunspaceCounter)
            $null = $psCMD.AddParameter('ComputerName',$Computer)
            $null = $psCMD.AddParameter('Verbose',$VerbosePreference)
            $psCMD.RunspacePool = $rp
 
            Write-Verbose -Message ('Roles And Features: Starting {0}' -f $Computer)
            [void]$runspaces.Add(@{
                Handle = $psCMD.BeginInvoke()
                PowerShell = $psCMD
                IObject = $Computer
                ID = $bgRunspaceCounter
           })
           Get-Result
        }
    }
     END
    {
        Get-Result -Wait
        if ($ShowProgress)
        {
            Write-Progress -Activity 'Roles And Features: Getting share session information' -Status 'Done' -Completed
        }
        Write-Verbose -Message "Roles And Features: Closing runspace pool"
        $rp.Close()
        $rp.Dispose()
    }
}


#Uncomment this to create graphviz role/feature dependecy diagrams
#$a.Win2008Features | Sort-Object ParentID,ID
#$b = $a.Win2008Features | Sort-Object ParentID,ID
#
#$Diagram = @'
#digraph test {
# rankdir = LR
# 
#'@
#ForEach ($Feature in $b)
#{
#    ForEach ($Feature2 in $b)
#    {
#        if ($Feature2.ParentID -eq $Feature.ID)
#        {
#            $Diagram += 
#@"
#
# "$($Feature.Name)" -> "$($Feature2.Name)"[label = ""]
#"@
#        }
#    }
#}
#
#$Diagram += @'
#
#}
#'@
##
### Uncomment the following to create a file to later convert into a graph with dot.exe
#$Diagram | Out-File -Encoding ASCII '.\rolesandfeatures.txt'
## Otherwise feed it into dot.exe and automatically open it up
#$Diagram | & 'dot.exe' -Tpng -o RolesAndFeatures.png
#ii RolesAndFeatures.png