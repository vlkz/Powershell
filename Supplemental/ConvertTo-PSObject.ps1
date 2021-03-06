function ConvertTo-PSObject {
    <#
    .SYNOPSIS
    Convert an array of two psobjects and join them based on a similar property.
    .DESCRIPTION
    Take an array of two like psobject and convert it to a singular psobject based on two shared 
    properties across all psobjects in the array. Similar to a SQL join.
    .PARAMETER InputObject
    An array of psobjects to convert.
    .PARAMETER propname
    The property to use as the key value.
    .PARAMETER valname
    Value to include in result.
    .EXAMPLE
    $obj = @()
    $a = @{ 
    'PropName' = 'Property 1'
    'Val1' = 'Value 1'
    }x 
    $b = @{ 
    'PropName' = 'Property 2'
    'Val1' = 'Value 2'
    }
    $obj += new-object psobject -property $a
    $obj += new-object psobject -property $b

    $c = $obj | ConvertTo-PSObject -propname 'PropName' -valname 'Val1'
    $c.'Property 1'
    
    Value 1
    
    Description
    -----------
    Join two object, $a and $b by PropName and include value 'Val1'.
    
    .NOTES
    Author: Zachary Loeber
    Site: the-little-things.net
    #>
    [cmdletbinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSObject[]]$InputObject,
        [string]$propname,
        [string]$valname
    )

    begin {
        $allObjects = @()
        $returnobject = New-Object psobject
    }
    process {
        $allObjects += $inputObject
    }
    end {
        $allObjects = @($allObjects | Select -First 2)
        if ($allObjects.Count -eq 2)
        {
            foreach ($obj in $allObjects)
            {
                $props = @(($obj | Get-Member | Where {$_.MemberType -eq 'NoteProperty'}).Name)
                if (($props -contains $propname) -and ($props -contains $valname))
                {
                    $returnobject | Add-Member -NotePropertyName $obj.$propname -NotePropertyValue $obj.$valname
                }
            }
            $returnobject
        }
    }
}