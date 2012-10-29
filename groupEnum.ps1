# groupEnum.ps1
# Enumerate Windows group membership
#
# Author: Neil Zimmerman (ncztch@rit.edu)
# Date: 10.11.2012

#define parameters
param(
    [alias("d")]
    [string]$domain     = "localhost",
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
    $rootGroupObj = new-object System.Security.Principal.NTAccount($domain, $rootGroupName)
    $isValid = isGroup($rootGroupObj)
    if ( $isValid -eq "False" ) {
        $acct = $rootGroupObj.ToString()
        $host.ui.WriteErrorLine("Error: $acct is not a valid account")
        Exit
	}
    
    # recursivley get members
    $rootName = $rootGroupObj.ToString().Split("\")[1] 
    $global:userList = New-Object System.Collections.ArrayList
    $global:groupStack = New-Object System.Collections.Stack
    $sid = getSID($rootGroupObj)
    $global:groupStack.Push(@{ "ntobj" = $rootGroupObj; "name" = "$rootName"; "path" = "\"; "sid" = $sid})
    while($global:groupStack.Count -ne 0) {
        # get the current group info
        $currGroup = $global:groupStack.Pop()
        $path = $currGroup["path"] + $currGroup["name"]  + "\"
        #Write-Host $currGroup["name"]
        # Get members of group
        $winnt = "WinNT://" + $domain + "/" + $currGroup["name"] + ",group" 
        $group =[ADSI]"$winnt"
        $members = @($group.psbase.Invoke("Members"))
        $members | foreach { 
            $memName = $_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null)
            #Write-Host "$memName"
            $currObj = new-object System.Security.Principal.NTAccount($domain, $memName)
            $isAGroup = isGroup($currObj)
            #Write-Host $isAGroup
            $isAUser = isUser($currObj)
            #Write-Host $isAUser
            if ( $isAGroup -ne "True" ) {
                #Write-Host "group -> $memname"
                $sid = getSID($currObj)
                $global:groupStack.Push(@{ "ntobj" = $currObj; "name" = "$memName"; "path" = $path; "sid" = $sid})
			} elseif ( $isAUser -ne "True" ) {
                #Write-Host "user -> $memname"
                $sid = getSID($currObj)
                Write-Host $sid
                $global:userList.Add(@{ "ntobj" = $currObj; "name" = "$memName"; "path" = $path; "sid" = $sid})
			}
        }
	}
	
    # print users
    foreach ($user in $global:userList) {
        $output = ""
        
        if ($printGroup -eq "true") { $output += $user['path']}
        if ($printName -eq "true") { $output += $user['name']}
        if ($printSID -eq "true") { 
            if ($printGroup -eq "true" -or $printName -eq "true") { $output += ',' }
            $output += $user['sid']
        }
        Write-Host $output
	}
}



# determine if NT Object is a group
function isGroup([System.Security.Principal.NTAccount]$ntObj) {
    
    ($d, $g) = $rootGroupObj.ToString().split("\")
    try {
        $result = [System.DirectoryServices.DirectoryEntry]::Exists("WinNT://$d/$g,group")
        return "$result"
	} catch {
        return "False"
	}
}

# determine if NT Object is a user
function isUser([System.Security.Principal.NTAccount]$ntObj) {
    
    ($d, $g) = $rootGroupObj.ToString().split("\")
    try {
        $result = [System.DirectoryServices.DirectoryEntry]::Exists("WinNT://$d/$g,user")
        return "$result"
	} catch {
        return "False"
	}
}

function getSID([System.Security.Principal.NTAccount]$ntObj) {
    try {
    $sid = $ntObj.Translate([System.Security.Principal.SecurityIdentifier])
	} catch {}
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