$machines = @("test1","test2","test3") # use this line to specify one or more specific target machines to enumerate
# $machines = Get-Content .\hosts.txt # use this line to iterate through a text file list of target machines to enumerate

# Get number of cores present and set max threads to double that.
$numCores = gwmi -class win32_processor -Property "numberOfCores" | Select-Object -Property "numberOfCores"
$maxThreads = $numCores.numberOfCores * 2
$sleepTimer = 500
$date = Get-Date -format yyyyMMdd_HHmm

# Get current directory to pass along for proper output directory
$invocation = (Get-Variable MyInvocation).Value
$Dir = Split-Path $invocation.MyCommand.Path

# Kill any existing jobs so they don't interfere with results
"Killing existing jobs..."
Get-Job | Remove-Job -Force
"All jobs are dead!"

$i = 0
ForEach($ComputerName in $machines) {
    # Check number of threads. If too many - take a nap
    While ($(Get-Job -State running).count -ge $maxThreads) {
        Write-Progress -Activity "Enumerating Groups" -Status "Waiting for threads to close" -CurrentOperation "$i threads created - $($(Get-Job -state running).count) threads open" -PercentComplete ($i / $machines.count * 100)
        Start-Sleep -Milliseconds $sleepTimer
    }
    
    # Start jobs 
	i++
    Start-Job {param($ComputerName,$date,$Dir); L:\Scripts\testing\groupEnum-mt.ps1 -host $ComputerName -date $date -directory $Dir } -ArgumentList $ComputerName,$date,$Dir -Name $ComputerName | Out-Null
    Write-Progress -Activity "Enumerating Groups" -Status "Starting Threads" -CurrentOperation "$i threads created - $($(Get-Job -state running).count) threads open" -PercentComplete ($i / $machines.count * 100)
    }
     
    Get-Job | Wait-Job
    Get-Job | Receive-Job | Select-Object -ExcludeProperty RunspaceID | Export-csv $Dir\$date.wtf.csv -Append -NoTypeInformation -Force 
