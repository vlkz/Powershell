function New-SQLQuery {
     <#
     .SYNOPSIS
        Returns data from a SQL query.
     .DESCRIPTION
        Returns data from a SQL query. Assumes integrated authentication.
     .EXAMPLE
        New-SQLQuery -Server Server1 -Instance LYNC -Database lis -Query 'Select * from lis'
     #>
    [CmdletBinding(SupportsShouldProcess = $True)] 
    param (
        [string]$Server,
        [string]$Instance = '',
        [string]$Database,
        [string]$Query
    )
 
    #Define SQL Connection String
    [string]$ServerAndInstance = $Server
    if ($Instance -ne '')
    {
        [string]$ServerAndInstance = "$ServerAndInstance\$Instance"
    }
    [string]$connstring = "server=$ServerAndInstance;database=$Database;trusted_connection=true;"
 
    #Define SQL Command
    [object]$command = New-Object System.Data.SqlClient.SqlCommand
    $command.CommandText = $Query
 
    # Define SQL connection
    [object]$connection = New-Object System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = $connstring
    $connection.Open()
    $command.Connection = $connection
    
    # Create SQL data adapter and associate the query with it
    [object]$sqladapter = New-Object System.Data.SqlClient.SqlDataAdapter
    $sqladapter.SelectCommand = $command
 
    # Execute query
    [object]$results = New-Object System.Data.Dataset
    $recordcount = $sqladapter.Fill($results)
    $connection.Close()
    return $Results.Tables[0]
}