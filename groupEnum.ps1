# groupEnum.ps1
# Enumerate Windows group membership
#
# Author: Neil Zimmerman (ncztch@rit.edu)
# Date: 10.11.2012

#define parameters
param(
    [alias("d")]
    [string]$domain     = $env:computername,
    [string]$printName  = "true",
    [string]$printSID   = "false",
    [string]$printGroup = "false",
    [Parameter(Mandatory=$true)][alias("g","group")]$rootGroupName
);

# declare some variables
[String]$FileName = "groupEnum.ps1";    # name of the script file

# syntax help string
$syntax = ".\$FileName [-domain <domain name>] [-printName {true | false}]"
$syntax += " [-printSID {true | false}] [-printGroup {true | false}]"
$syntax += " -group <group name>"



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
    
    # recursivley get members
    if ($rootGroupObj.ToString().Contains("\")) {
        $rootName = $rootGroupObj.ToString().Split("\")[1]
	} else {
        $rootName = $rootGroupObj.ToString()
	}
    
    $userTable = New-Object System.Collections.HashTable
    $groupStack = New-Object System.Collections.Stack
    $rootNtObj = @{ "ntobj" = $rootGroupObj;
                    "name" = "\" + $rootName;
                    "path" = "";
                    "sid" = getSID($rootGroupObj);
                    "domain" = $domain
	}
    $groupStack.Push($rootNtObj)
    while($groupStack.Count -gt 0) {
        # get the current group info
        $currGroup = $groupStack.Pop()
        # set path for children
        $path = $currGroup["path"] + $currGroup["name"] 
        # Get members of group
        $winnt = "WinNT://" + $currGroup["domain"] + "/" + $currGroup["name"] + ",group" 
        $group =[ADSI]"$winnt"
        $members = @($group.psbase.Invoke("Members"))
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
                $groupStack.Push($newObj)
            # if member is a 
			} elseif ( isUser($currObj) ) {
                if ($userTable.Contains($newObj['sid']) -ne $true) {
                    $userTable.Add($newObj['sid'], $newObj)
				}
			}
        }
	}

    # print users
    $out = New-Object System.Collections.ArrayList
    foreach ($user in $userTable.Values) {
        $line = "\" + $user['domain']
        if ($printGroup -eq "true") { $line += $user['path']}
        if ($printName -eq "true") { $line += $user['name']}
        if ($printSID -eq "true") { 
            if ($printGroup -eq "true" -or $printName -eq "true") { $line += ',' }
            $line += $user['sid']
        }
        [void]$out.Add($line)
    }
    $out | Sort-Object
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

# in the event of a syntax error
function syntax_error {
    $err_msg =  "Usage Error`n"
    $err_msg += "Syntax: $syntax`n"
    $host.ui.WriteErrorLine($err_msg)
    Exit
}

# in the event of a syntax error
function print_help {
    $help_msg =  "Syntax: $syntax"
    Write-Host $help_msg
    Exit
}

# call main if script called directly
if ($MyInvocation.MyCommand.Name -eq $FileName) {
	main
    Exit
}