# groupEnum.ps1
# Enumerate Windows group membership
#
# Author: Neil Zimmerman (ncztch@rit.edu)
# Date: 10.11.2012

# declare some variables
[String]$FileName = "groupEnum.ps1";    # name of the script file
[int]$name_output = 1;	                # output mode for user names (0-2)
                                        ## 0 - do not print user name
                                        ## 1 - print user name w/o group
                                        ## 2 - print username preceeded by group
[int]$sid_output = 1;                   # output mode for user SIDs
                                        ## 0 - do not print user SID
                                        ## 1 - print user SID
[String]$syntax = ".\$FileName [-domain <domain name>] [-printSID {true | false}] [-printSID {true | false}] [-printSID {true | false}]"

# Main function
function main {

    [String]$rootGroup = "";
    [string]$output_args = "";
    [string]$serachScope = "local";     # local (default) or domain to query
    
#    print_help
    # parse arguments
    Write-Host $args.count
    if ($args.length -lt 1) { syntax_error }
    $i = 0;
	foreach ($arg in $args) {
        $i++                            # keep track of position in args array
        # store last argument as group name
        if ($i -eq $args.length) {
            #if ($arg[0] -eq "-") { syntax_error }
            $rootGroup = $arg
		}
	}
	
}

# in the event of a syntax error
function syntax_error {
    $err_msg =  "Usage Error`n"
    $err_msg += "Syntax: $filename [-sSnNmMuhv] [-l | -d domain] group_name`n"
    $host.ui.WriteErrorLine($err_msg)
    Exit
}

# in the event of a syntax error
function print_help {
    $help_msg =  "Syntax: $filename [-d domain_name] group_name`n"
    $help_msg += "Options:`n"
    
    Write-Host $help_msg
    Exit
}

# call main if script called directly
if ($MyInvocation.MyCommand.Name -eq $FileName) {
	main;
}