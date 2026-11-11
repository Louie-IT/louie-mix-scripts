#Requires -Version 5.1
<#
.SYNOPSIS
    Continuous internal server connectivity checker.

.DESCRIPTION
    Designed to run manually from a jump host during an incident.

    Checks each server for:
      - DNS resolution
      - ICMP connectivity
      - ICMP response time (ms)
      - TCP port 3389 connectivity

    The screen refreshes automatically after each test cycle.

    Press Ctrl+C to stop.
#>


# ============================================================
# CONFIGURATION
# ============================================================

$Servers = @(

    [PSCustomObject]@{
        Name        = "LOCALHOST"
        Description = "Localhost testing machine"
    }

    [PSCustomObject]@{
        Name        = "SERVER01"
        Description = "SQL Server"
    }

    [PSCustomObject]@{
        Name        = "SERVER02"
        Description = "Web Server"
    }

    [PSCustomObject]@{
        Name        = "SERVER03"
        Description = "File Server"
    }

    [PSCustomObject]@{
        Name        = "SERVER04"
        Description = "Integration Server"
    }

    # Add remaining servers here.
)


# Number of seconds to wait after a completed cycle
# before starting the next cycle.
$RefreshIntervalSeconds = 30


# Maximum TCP connection wait time in milliseconds.
$TcpTimeoutMilliseconds = 2000


# TCP port to test.
$TcpPort = 3389



# ============================================================
# FUNCTIONS
# ============================================================

function Test-TcpPort {

    param (
        [Parameter(Mandatory = $true)]
        [string]$ComputerName,

        [Parameter(Mandatory = $true)]
        [int]$Port,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutMilliseconds
    )


    $TcpClient = $null
    $AsyncResult = $null


    try {

        $TcpClient = New-Object System.Net.Sockets.TcpClient


        $AsyncResult = $TcpClient.BeginConnect(
            $ComputerName,
            $Port,
            $null,
            $null
        )


        $ConnectedInTime = $AsyncResult.AsyncWaitHandle.WaitOne(
            $TimeoutMilliseconds,
            $false
        )


        if (-not $ConnectedInTime) {

            return $false
        }


        $TcpClient.EndConnect($AsyncResult)


        if ($TcpClient.Connected) {

            return $true
        }
        else {

            return $false
        }
    }

    catch {

        return $false
    }

    finally {

        if ($null -ne $AsyncResult) {

            if ($null -ne $AsyncResult.AsyncWaitHandle) {

                $AsyncResult.AsyncWaitHandle.Close()
            }
        }


        if ($null -ne $TcpClient) {

            $TcpClient.Close()
        }
    }
}



function Write-Status {

    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("OK", "FAIL", "SKIP")]
        [string]$Status,

        [int]$Width = 7
    )


    $DisplayStatus = $Status.PadRight($Width)


    switch ($Status) {

        "OK" {

            Write-Host $DisplayStatus `
                -ForegroundColor Green `
                -NoNewline
        }


        "FAIL" {

            Write-Host $DisplayStatus `
                -ForegroundColor Red `
                -NoNewline
        }


        "SKIP" {

            Write-Host $DisplayStatus `
                -ForegroundColor Yellow `
                -NoNewline
        }
    }
}



# ============================================================
# VALIDATE SERVER LIST
# ============================================================

$ValidServers = @()


foreach ($Server in $Servers) {

    if ($null -eq $Server) {

        continue
    }


    if ($null -eq $Server.Name) {

        continue
    }


    $ServerName = $Server.Name.ToString().Trim()


    if ($ServerName.Length -eq 0) {

        continue
    }


    # Prevent duplicate server names.

    $AlreadyExists = $false


    foreach ($ExistingServer in $ValidServers) {

        if ($ExistingServer.Name -eq $ServerName) {

            $AlreadyExists = $true
            break
        }
    }


    if (-not $AlreadyExists) {

        $ValidServers += $Server
    }
}


$Servers = $ValidServers



if ($Servers.Count -eq 0) {

    Write-Host ""
    Write-Host "No valid servers have been configured." `
        -ForegroundColor Red

    return
}



# Prevent an accidentally aggressive refresh rate.

if ($RefreshIntervalSeconds -lt 10) {

    Write-Host ""
    Write-Host `
        "Refresh interval increased to the minimum of 10 seconds." `
        -ForegroundColor Yellow

    $RefreshIntervalSeconds = 10
}



# Prevent an excessively short TCP timeout.

if ($TcpTimeoutMilliseconds -lt 500) {

    Write-Host ""
    Write-Host `
        "TCP timeout increased to the minimum of 500 milliseconds." `
        -ForegroundColor Yellow

    $TcpTimeoutMilliseconds = 500
}



# ============================================================
# PREPARE MONITORING
# ============================================================

$PreviousProgressPreference = $ProgressPreference

$ProgressPreference = "SilentlyContinue"



# ============================================================
# CONTINUOUS MONITORING
# ============================================================

try {

    while ($true) {


        $CycleStart = Get-Date

        $Results = @()



        # ====================================================
        # CHECK EACH SERVER
        # ====================================================

        foreach ($Server in $Servers) {


            $ServerName = $Server.Name.ToString().Trim()



            # ------------------------------------------------
            # DESCRIPTION
            # ------------------------------------------------

            $ServerDescription = "-"


            if ($null -ne $Server.Description) {

                $TempDescription =
                    $Server.Description.ToString().Trim()


                if ($TempDescription.Length -gt 0) {

                    $ServerDescription = $TempDescription
                }
            }



            # ------------------------------------------------
            # DNS RESOLUTION
            # ------------------------------------------------

            $DnsStatus = "FAIL"

            $IPAddress = "-"


            try {

                $DnsAddresses =
                    [System.Net.Dns]::GetHostAddresses(
                        $ServerName
                    )


                $IPv4Address = $null


                foreach ($Address in $DnsAddresses) {

                    if (
                        $Address.AddressFamily -eq
                        [System.Net.Sockets.AddressFamily]::InterNetwork
                    ) {

                        $IPv4Address = $Address
                        break
                    }
                }


                if ($null -ne $IPv4Address) {

                    $DnsStatus = "OK"

                    $IPAddress =
                        $IPv4Address.IPAddressToString
                }
            }

            catch {

                $DnsStatus = "FAIL"

                $IPAddress = "-"
            }



            # ------------------------------------------------
            # ICMP + RESPONSE TIME
            # ------------------------------------------------

            $PingStatus = "SKIP"

            $Latency = "-"


            if ($DnsStatus -eq "OK") {

                try {

                    $PingResult = Test-Connection `
                        -ComputerName $ServerName `
                        -Count 1 `
                        -ErrorAction Stop


                    if ($null -ne $PingResult) {

                        $PingStatus = "OK"

                        $Latency =
                            $PingResult.ResponseTime.ToString() + "ms"
                    }

                    else {

                        $PingStatus = "FAIL"

                        $Latency = "-"
                    }
                }

                catch {

                    $PingStatus = "FAIL"

                    $Latency = "-"
                }
            }



            # ------------------------------------------------
            # TCP PORT 3389
            # ------------------------------------------------

            $TcpStatus = "SKIP"


            if ($DnsStatus -eq "OK") {

                $TcpSucceeded = Test-TcpPort `
                    -ComputerName $ServerName `
                    -Port $TcpPort `
                    -TimeoutMilliseconds $TcpTimeoutMilliseconds


                if ($TcpSucceeded) {

                    $TcpStatus = "OK"
                }

                else {

                    $TcpStatus = "FAIL"
                }
            }



            # ------------------------------------------------
            # OVERALL SERVER STATUS
            # ------------------------------------------------

            if (
                ($DnsStatus -eq "OK") -and
                ($PingStatus -eq "OK") -and
                ($TcpStatus -eq "OK")
            ) {

                $OverallStatus = "OK"
            }

            else {

                $OverallStatus = "ISSUE"
            }



            # ------------------------------------------------
            # SAVE RESULT
            # ------------------------------------------------

            $Results += [PSCustomObject]@{

                Server      = $ServerName

                Description = $ServerDescription

                DNS         = $DnsStatus

                ICMP        = $PingStatus

                Latency     = $Latency

                TCP3389     = $TcpStatus

                IP          = $IPAddress

                Overall     = $OverallStatus
            }
        }



        # ====================================================
        # CYCLE INFORMATION
        # ====================================================

        $CycleEnd = Get-Date


        $ElapsedSeconds =
            ($CycleEnd - $CycleStart).TotalSeconds


        $CycleDuration =
            "{0:N1}" -f $ElapsedSeconds



        # ====================================================
        # REFRESH DISPLAY
        # ====================================================

        Clear-Host


        Write-Host "SERVER CONNECTIVITY CHECK" `
            -ForegroundColor Cyan


        Write-Host (
            "Source: {0} | Updated: {1} | Cycle: {2}s" -f
            $env:COMPUTERNAME,
            $CycleEnd.ToString("dd/MM/yyyy HH:mm:ss"),
            $CycleDuration
        ) -ForegroundColor Yellow


        Write-Host (
            "Interval: {0}s | ICMP: 1 echo | TCP: {1} | Stop: Ctrl+C" -f
            $RefreshIntervalSeconds,
            $TcpPort
        ) -ForegroundColor Yellow


        Write-Host ""



        # ====================================================
        # COLUMN HEADINGS
        # ====================================================

        Write-Host (
            "{0,-17} {1,-21} {2,-6} {3,-6} {4,-9} {5,-8} {6}" -f
            "SERVER",
            "DESCRIPTION",
            "DNS",
            "ICMP",
            "LATENCY",
            "TCP3389",
            "IP ADDRESS"
        ) -ForegroundColor White


        Write-Host ("-" * 88) `
            -ForegroundColor DarkGray



        # ====================================================
        # DISPLAY SERVER RESULTS
        # ====================================================

        foreach ($Result in $Results) {


            # Shorten long server names only for display.

            if ($Result.Server.Length -gt 16) {

                $DisplayServer =
                    $Result.Server.Substring(0, 13) + "..."
            }

            else {

                $DisplayServer =
                    $Result.Server
            }



            # Shorten long descriptions only for display.

            if ($Result.Description.Length -gt 20) {

                $DisplayDescription =
                    $Result.Description.Substring(0, 17) + "..."
            }

            else {

                $DisplayDescription =
                    $Result.Description
            }



            # Server + Description

            Write-Host (
                "{0,-17} {1,-21} " -f
                $DisplayServer,
                $DisplayDescription
            ) -NoNewline



            # DNS

            Write-Status `
                -Status $Result.DNS `
                -Width 6



            # ICMP

            Write-Status `
                -Status $Result.ICMP `
                -Width 6



            # Latency

            if ($Result.ICMP -eq "OK") {

                Write-Host (
                    "{0,-9}" -f $Result.Latency
                ) `
                    -ForegroundColor Green `
                    -NoNewline
            }

            else {

                Write-Host (
                    "{0,-9}" -f "-"
                ) `
                    -ForegroundColor DarkGray `
                    -NoNewline
            }



            # TCP 3389

            Write-Status `
                -Status $Result.TCP3389 `
                -Width 8



            # IP Address

            Write-Host $Result.IP
        }



        # ====================================================
        # SUMMARY
        # ====================================================

        $CheckedCount = $Results.Count


        $OkCount = @(
            $Results |
                Where-Object {
                    $_.Overall -eq "OK"
                }
        ).Count


        $IssueCount =
            $CheckedCount - $OkCount



        Write-Host ""


        Write-Host "$CheckedCount checked" `
            -ForegroundColor Cyan `
            -NoNewline


        Write-Host " | " `
            -NoNewline


        Write-Host "$OkCount OK" `
            -ForegroundColor Green `
            -NoNewline


        Write-Host " | " `
            -NoNewline



        if ($IssueCount -eq 0) {

            Write-Host "0 issues" `
                -ForegroundColor Green
        }

        else {

            Write-Host "$IssueCount issues" `
                -ForegroundColor Red
        }



        Write-Host (
            "Next refresh after {0} seconds... (Ctrl+C to stop)" -f
            $RefreshIntervalSeconds
        ) -ForegroundColor Yellow



        # ====================================================
        # REFRESH DELAY
        # ====================================================

        # The delay happens only after ALL servers have been
        # tested. Monitoring cycles therefore cannot overlap.

        Start-Sleep -Seconds $RefreshIntervalSeconds
    }
}

finally {

    $ProgressPreference =
        $PreviousProgressPreference


    Write-Host ""

    Write-Host "Connectivity monitoring stopped." `
        -ForegroundColor Yellow
}
