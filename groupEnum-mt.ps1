[CmdletBinding(SupportsShouldProcess=$true)]
<#
.NAME
    groupEmun.ps1
.SYNOPSIS
    Enumerate Windows group membership
.DESCRIPTION
    groupEnum will recursively enumerate the membership of any specified group, returning a list of users only (no groups). Results will be printed to the screen and written out to both text and csv files.
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
.PARAMETER h -host -ComputerName
    <target host> Host machine to enumerate groups for Default: localhost
.LINK
    https://github.com/vidkun/groupEnum-mt
.NOTES
    Author: vidkun
    Date: 20130603
    Original code based on groupEnum from Doct0rZ (https://github.com/Doct0rZ/groupEnum)
.EXAMPLE
    .\groupEnum.ps1 -g "Administrators"
    This will display all of the users that inherit permissions from local Administrators group
#>

#define parameters
param(
    [alias("d")]
    [string]$domain           = $ComputerName,
    [string]$printName        = "true",
    [string]$printSID         = "true",
    [string]$printGroup       = "true",
    [string]$printDisabled    = "true",
    [string]$printPasswordAge = "true",
    #[string]$date             = $(Get-Date -format yyyyMMdd_HHmm), # uncomment if running standalone
    [string]$date             = "", # uncomment if running multithreaded
    [alias("directory")][string]$Dir              = "",
    #[alias("s","source")][string]$sourceFile = "$Dir\hosts.txt",
    [alias("r","results")][string]$resultsFile = "$Dir\$date.admins.txt",
    [alias("c","csv")][string]$csvFile = "$Dir\$date.admins.csv",
    [Parameter(Position=0)][alias("h","host")][string]$ComputerName = "localhost",
    [alias("g","group")]$rootGroupName = "Administrators"
);

# declare some variables
[String]$FileName = "groupEnum-mt.ps1";    # name of the script file

# Main function
function global:main([string]$ComputerName) {
 
    # check that group exists, verify it is a group instead of user, and whether it's a local or domain group
    if ($domain -eq $ComputerName) { 
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
           
    # recursively get members if it is a valid group
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
                    "sid" = getGroupSID($rootGroupObj);
                    "domain" = $ComputerName
	}
	
	#add root group to the stack of groups
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
			# get the account name of all members in the group
            $memName = $_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null)
			# get the domain\machine name of the account. domain accounts give the domain, local accounts give the machine name
            $memdom = $_.GetType().InvokeMember("Parent", 'GetProperty', $null, $_, $null).split("/")[-1]
			# if member domain matches the target machine name, currObj is set to just the account name (for local accounts)
            if ($memdom -eq $ComputerName) {
                $currObj = new-object System.Security.Principal.NTAccount($memName)
			# otherwise currObj is set created for the domain and account (for domain accounts)
	        } else {
                $currObj = new-object System.Security.Principal.NTAccount($memdom, $memName)
	        }

            <#$sid = getSID($currObj)
            $newObj = @{    "ntobj" = $currObj;
                            "name" = "\" + $memName;
                            "path" = $path;
                            "sid" = $sid;
                            "domain" = $memdom
            }#>

            # if member is a group: get group's SID, build object, and add it to the stack
            if ( isGroup($currObj) ) {
				$sid = getGroupSID($currObj)
				$newObj = @{    "ntobj" = $currObj;
	                            "name" = "\" + $memName;
	                            "path" = $path;
	                            "sid" = $sid;
	                            "domain" = $memdom
	            }
                Write-Verbose ("Found group: \" + $newObj['domain'] + $newObj['name'])
                $groupStack.Push($newObj)
            # if member is a user: get user's SID, build object, check disabled and password age, and add to userTable
			} elseif ( isUser($currObj) ) {
				$sid = getUserSID($currObj)
				$newObj = @{    "ntobj" = $currObj;
	                            "name" = "\" + $memName;
	                            "path" = $path;
	                            "sid" = $sid;
	                            "domain" = $memdom
	            }
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
				$newObj = @{    "ntobj" = $currObj;
	                            "name" = "\" + $memName;
	                            "path" = $path;
	                            "sid" = $sid;
	                            "domain" = $memdom
	            }
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
    #$out | Sort-Object | Out-File $resultsFile -Append -Encoding utf8

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
    $csvout
    
    
}

# determine if NT Object is a group
function global:isGroup([System.Security.Principal.NTAccount]$o) {
    
	# split "domain\account" into separate variable
    ($d, $g) = $o.ToString().split("\")
	
	#if object isn't domain\account format and only account name, move it to variable g and set d to machine name. usually means it is local not domain
    if ($g -eq $null) {
        $g = $d;
        $d = $ComputerName;
	}
    try {
        [boolean]$result = [System.DirectoryServices.DirectoryEntry]::Exists("WinNT://$d/$g,group")
        return $result
	} catch {
        return $false
	}
}

# determine if NT Object is a user
function global:isUser([System.Security.Principal.NTAccount]$o) {
	
   	# split "domain\account" into separate variable
    ($d, $g) = $o.ToString().split("\")
	
	#if object isn't domain\account format and only account name, move it to variable g and set d to machine name. usually means it is local not domain
    if ($g -eq $null) {
        $g = $d;
        $d = $ComputerName;
	}
    try {
        $result = [System.DirectoryServices.DirectoryEntry]::Exists("WinNT://$d/$g,user")
        return $result
	} catch {
        return $false
	}
}

# translate user to SID
function global:getUserSID([System.Security.Principal.NTAccount]$o) {
	($h, $a) = $o.ToString().split("\")
	if ($a -eq $null) {
        $a = $h;
        $h = $ComputerName;
	}
	$filter = "name= '" + $a + "'"
	# if user is local account get SID from the target machine
	if ($h -eq $ComputerName) {
    	try {
    	$usid = (Get-WmiObject win32_useraccount -ComputerName $h -Filter "$filter" -Credential $creds).sid
		} catch { }
    return $usid
	}
	# otherwise grab SID for domain user
	else {
		try {
		$usid = $o.Translate([System.Security.Principal.SecurityIdentifier])
		} catch { }
		return $usid
	}
}

# translate group to SID
function global:getGroupSID([System.Security.Principal.NTAccount]$o) {
	($h, $a) = $o.ToString().split("\")
	if ($a -eq $null) {
        $a = $h;
        $h = $ComputerName;
	}
	$filter = "name= '" + $a + "'"
	# if user is local account get SID from the target machine
	if ($h -eq $ComputerName) {
    	try {
    	$gsid = (Get-WmiObject win32_group -ComputerName $h -Filter "$filter" -Credential $creds).sid
		} catch { }
    	return $gsid
	}
	# otherwise grab SID for domain group
	else {
		try {
		$gsid = $o.Translate([System.Security.Principal.SecurityIdentifier])
		} catch { }
		return $gsid
	}
}

# call main if script called directly
if ($MyInvocation.MyCommand.Name -eq $FileName) {
	# getting SIDs for local account on remote machines requires local admin rights to the target machine
	$creds = Get-Credential -Message "Please authenticate with an admin account"
    main $ComputerName
    Exit
}
