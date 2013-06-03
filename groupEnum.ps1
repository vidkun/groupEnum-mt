[CmdletBinding(SupportsShouldProcess=$true)]
<#
.NAME
    groupEmun.ps1
.SYNOPSIS
    Enumerate Windows group membership
.DESCRIPTION
    groupEnum will recursivley enumerate the membership of any specfifed group, returning a list of users only (no groups). Results will be printed to the screen and written out to both text and csv files.
.SYNTAX
    groupEmun.ps1 [-d | -domain <domain name>] [-printName {true | false}] [-printSID {true | false}] [-printGroup {true | false}] $syntax += " [-printDisabled {true | false}] [-printPasswordAge {true | false}] {-g | -group} <group name> {-s | -source} <source file> {-r | -results} <results file> {-c | -csv} <CSV file>
.PARAMETER d
    domain of root group. Default: localhost
.PARAMETER printName
    {true|false} Display user name. Default: true
.PARAMETER printSID
    {true|false} Display user SID. Default: false
.PARAMETER printGroup 
    {true|false} Display inheritance chain. Default: false
.PARAMETER printDisabled 
    {true|false} Print whether or not the group is disabled. Default: true
.PARAMETER printPasswordAge 
    {true|false} Print age of user's password in days. Default: false
.PARAMETER g -group -rootGroupName
    <group name> group which to enumerate membership. Default: Administrators
.PARAMETER s -source -sourceFile
    <file name> source file of hosts to iterate through. Default: hosts.txt
.PARAMETER r -results -resultsFile
    <file name> text file to write out results to. Default: admins.txt
.PARAMETER c -csv -csvFile
    <file name> CSV file to write results to in CSV format. Default: admins.csv
.LINK
    https://github.com/vidkun/groupEnum
.NOTES
    Author: vidkun & Doct0rZ
    Date: 20130603
.EXAMPLE
    .\groupEnum.ps1 -g "Administrators"
    This will dsiplay all of the users that inherit permissions from local Administrators group
#>


#define parameters
param(
    [alias("d")]
    [string]$domain           = $env:computername,
    [string]$printName        = "true",
    [string]$printSID         = "false",
    [string]$printGroup       = "true",
    [string]$printDisabled    = "true",
    [string]$printPasswordAge = "false",
    [alias("s","source")][string]$sourceFile = ".\hosts.txt",
    [alias("r","results")][string]$resultsFile = ".\admins.txt",
    [alias("c","csv")][string]$csvFile = ".\admins.csv",
    [alias("g","group")]$rootGroupName = "Administrators"
);

# declare some variables
[String]$FileName = "groupEnum.ps1";    # name of the script file



# Main function
function main {
    
    # check that group exists
    if ($domain -eq $env:computername) {
        $rootGroupObj = new-object System.Security.Principal.NTAccount($rootGroupName)
	} else {
        $rootGroupObj = new-object System.Security.Principal.NTAccount($domain, $rootGroupName)
	}
    [boolean]$isValid = isGroup($rootGroupObj)
    if ( $isValid -eq $false ) {
        $acct = $rootGroupObj.ToString()
        $host.ui.WriteErrorLine("Error: $acct is not a valid account")
        Exit
	}
    
    $machines = get-content $sourceFile
    foreach ($ComputerName in $machines) {
    
    # recursivley get members
    if ($rootGroupObj.ToString().Contains("\")) {
        $rootName = $rootGroupObj.ToString().Split("\")[1]
	} else {
        $rootName = $rootGroupObj.ToString()
	}
    
    $ComputerName

    $userTable = New-Object System.Collections.HashTable
    $groupStack = New-Object System.Collections.Stack
    $rootNtObj = @{ "ntobj" = $rootGroupObj;
                    "name" = "\" + $rootName;
                    "path" = "";
                    "sid" = getSID($rootGroupObj);
                    "domain" = $ComputerName
	}
    $groupStack.Push($rootNtObj)
    while($groupStack.Count -gt 0) {
        # get the current group info
        $currGroup = $groupStack.Pop()
        # set path for children
        $path = $currGroup["path"] + $currGroup["name"] 
        # Get members of group
        $winnt = "WinNT://" + $currGroup["domain"] + "/" + $currGroup["name"] + ",group" 
        $group = [ADSI]"$winnt"
        $members = @($group.psbase.Invoke("Members"))
        Write-Verbose ("Getting members of group: \" + $currGroup['domain'] + $currGroup['name'])
        $members | foreach { 
            $memName = $_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null)
            $memdom = $_.GetType().InvokeMember("Parent", 'GetProperty', $null, $_, $null).split("/")[-1]
            if ($memdom -eq $env:computername) {
                $currObj = new-object System.Security.Principal.NTAccount($memName)
	        } else {
                $currObj = new-object System.Security.Principal.NTAccount($memdom, $memName)
	        }

            $sid = getSID($currObj)
            $newObj = @{    "ntobj" = $currObj;
                            "name" = "\" + $memName;
                            "path" = $path;
                            "sid" = $sid;
                            "domain" = $memdom
            }
            # if member is a group, add it to the stack
            if ( isGroup($currObj) ) {
                Write-Verbose ("Found group: \" + $newObj['domain'] + $newObj['name'])
                $groupStack.Push($newObj)
            # if member is a 
			} elseif ( isUser($currObj) ) {
                Write-Verbose ("Found user: \" + $newObj['domain'] + $newObj['name'])
                # check if user is disabled
                $winnt = "WinNT://" + $newObj['domain'] +"/" + $newObj['name'] + ",user"
                $newObj["disabled"] = ([ADSI]"$winnt").AccountDisabled
                # get password age
                $newObj["passwd_age"] = [math]::Round(([ADSI]"$winnt").InvokeGet('PasswordAge') / 86400 )
                if ($userTable.Contains($newObj['sid']) -ne $true) {
                    $userTable.Add($newObj['sid'], $newObj)
				}
			} elseif ($memdom -eq "NT AUTHORITY") {
                Write-Verbose ("Found object: " + $newObj['domain'] + $newObj['name'])
                $newObj["disabled"] = $false
                $newObj["passwd_age"] = "-1"
                if ($userTable.Contains($newObj['sid']) -ne $true) {
                    $userTable.Add($newObj['sid'], $newObj)
				}
			}
        }
	}

    # print users
    $out = New-Object System.Collections.ArrayList
    foreach ($user in $userTable.Values) {
        $line = $ComputerName + ": " + "\" + $user['domain']
        if ($printGroup -like "true") { $line += $user['path']}
        if ($printName -like "true") { $line += $user['name']}
        if ($printSID -like "true") { 
            if ($printGroup -like "true" -or $printName -like "true") { $line += ',' }
            $line += $user['sid']
        }
        if ($printPasswordAge -like "true") { $line += " (Password Age = " + $user["passwd_age"] + " days)" }
        if (($printDisabled -like "true") -and $user["disabled"]) { $line += " [DISABLED]" }
        [void]$out.Add($line)
    }
    
    $out | Sort-Object
    $out | Sort-Object | Out-File $resultsFile -Append -Encoding utf8

    $csvout = @()
    foreach ($user in $userTable.Values) {
        $output = "" | Select Computer,Account,Path,SID,Age,Disabled
        $output.Computer = $ComputerName
        $output.Account = $user["domain"] + $user["name"]
        $output.Path = $user["path"]
        $output.Disabled = $user["disabled"]
        $output.SID = $user["sid"]
        $output.Age = $user["passwd_age"]

        $csvout =  $csvout + $output       
    
    }
    $csvout | Export-Csv $csvFile -Append -NoTypeInformation -Force 
    }
}



# determine if NT Object is a group
function isGroup([System.Security.Principal.NTAccount]$o) {
    
    ($d, $g) = $o.ToString().split("\")

    if ($g -eq $null) {
        $g = $d;
        $d = $ENV:COMPUTERNAME;
	}
    try {
        [boolean]$result = [System.DirectoryServices.DirectoryEntry]::Exists("WinNT://$d/$g,group")
        return $result
	} catch {
        return $false
	}
}

# determine if NT Object is a user
function isUser([System.Security.Principal.NTAccount]$o) {
    
    ($d, $g) = $o.ToString().split("\")

    if ($g -eq $null) {
        $g = $d;
        $d = $ENV:COMPUTERNAME;
	}
    try {
        $result = [System.DirectoryServices.DirectoryEntry]::Exists("WinNT://$d/$g,user")
        return $result
	} catch {
        return $false
	}
}

# translate NTAccount object to SID
function getSID([System.Security.Principal.NTAccount]$o) {
    try {
    $sid = $o.Translate([System.Security.Principal.SecurityIdentifier])
	} catch { }
    return $sid.value
}

# call main if script called directly
if ($MyInvocation.MyCommand.Name -eq $FileName) {
	main
    Exit
}
