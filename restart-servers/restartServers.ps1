<#
.SYNOPSIS
    Safely restart one or more predefined remote servers.

.DESCRIPTION
    Displays a numbered server list and allows an administrator to:
      - Restart one server
      - Restart all servers
      - Exit without making changes

    Before confirmation, the script performs an ICMP connectivity check.
    servers that fail the check are excluded from the restart operation.

    Supports -WhatIf for a dry run.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param()

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

$Computers = @(
    [PSCustomObject]@{
        Name        = "server01"
        Description = "Number 1 server"
    }

    [PSCustomObject]@{
        Name        = "server02"
        Description = "Number 2 server"
    }

    [PSCustomObject]@{
        Name        = "server03"
        Description = "Operations server"
    }

    [PSCustomObject]@{
        Name        = "server04"
        Description = "Database server"
    }
)

# Use $false if applications should not be forced to close.
$ForceRestart = $true

# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------

function Show-Menu {

    Clear-Host

    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "          Server Restart Tool            " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host

    for ($i = 0; $i -lt $Computers.Count; $i++) {

        Write-Host (
            "  {0}. {1} - {2}" -f
            ($i + 1),
            $Computers[$i].Name,
            $Computers[$i].Description
        )
    }

    Write-Host
    Write-Host "  A. Restart ALL servers" -ForegroundColor Yellow
    Write-Host "  Q. Quit"
    Write-Host
}

# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

Show-Menu

$Selection = (Read-Host "Select a server").Trim()

if ($Selection -eq 'Q') {

    Write-Host
    Write-Host "No changes made." -ForegroundColor Green
    return
}

if ($Selection -eq 'A') {

    $Targets = @($Computers)
}
elseif (
    $Selection -match '^\d+$' -and
    [int]$Selection -ge 1 -and
    [int]$Selection -le $Computers.Count
) {

    $Targets = @($Computers[[int]$Selection - 1])
}
else {

    Write-Warning "Invalid selection. No servers were restarted."
    return
}

# ---------------------------------------------------------------------------
# Connectivity Pre-check
# ---------------------------------------------------------------------------

Write-Host
Write-Host "Checking server connectivity..." -ForegroundColor Cyan
Write-Host

$ConnectivityResults = foreach ($Target in $Targets) {

    try {

        $IsOnline = Test-Connection `
            -ComputerName $Target.Name `
            -Count 1 `
            -Quiet `
            -ErrorAction Stop
    }
    catch {

        $IsOnline = $false
    }

    if ($IsOnline) {

        Write-Host (
            "  [ONLINE]  {0} - {1}" -f
            $Target.Name,
            $Target.Description
        ) -ForegroundColor Green
    }
    else {

        Write-Host (
            "  [OFFLINE] {0} - {1}" -f
            $Target.Name,
            $Target.Description
        ) -ForegroundColor Red
    }

    [PSCustomObject]@{
        Computer    = $Target
        IsReachable = $IsOnline
    }
}

# Only reachable servers continue to the restart stage.
$ReachableTargets = @(
    $ConnectivityResults |
        Where-Object { $_.IsReachable } |
        ForEach-Object { $_.Computer }
)

$UnreachableTargets = @(
    $ConnectivityResults |
        Where-Object { -not $_.IsReachable } |
        ForEach-Object { $_.Computer }
)

# Stop safely if none of the selected servers responded.
if ($ReachableTargets.Count -eq 0) {

    Write-Host
    Write-Warning "None of the selected servers passed the connectivity check."
    Write-Warning "No restart commands were sent."
    return
}

# ---------------------------------------------------------------------------
# Final Safety Check
# ---------------------------------------------------------------------------

Write-Host
Write-Host "server(s) ready for restart:" -ForegroundColor Yellow

foreach ($Target in $ReachableTargets) {

    Write-Host (
        "  - {0} - {1}" -f
        $Target.Name,
        $Target.Description
    ) -ForegroundColor Yellow
}

if ($UnreachableTargets.Count -gt 0) {

    Write-Host
    Write-Host "server(s) that will be skipped:" -ForegroundColor Red

    foreach ($Target in $UnreachableTargets) {

        Write-Host (
            "  - {0} - {1}" -f
            $Target.Name,
            $Target.Description
        ) -ForegroundColor Red
    }
}

Write-Host

$Confirmation = (Read-Host "Type RESTART to continue").Trim()

if ($Confirmation -cne 'RESTART') {

    Write-Host
    Write-Host "Restart cancelled. No changes made." -ForegroundColor Green
    return
}

# ---------------------------------------------------------------------------
# Restart Operation
# ---------------------------------------------------------------------------

$RestartResults = [System.Collections.Generic.List[object]]::new()

# Record unreachable servers as skipped.
foreach ($Computer in $UnreachableTargets) {

    $RestartResults.Add(
        [PSCustomObject]@{
            Name        = $Computer.Name
            Description = $Computer.Description
            Status      = "Skipped"
            Details     = "Connectivity check failed"
        }
    )
}

Write-Host

foreach ($Computer in $ReachableTargets) {

    if ($PSCmdlet.ShouldProcess($Computer.Name, "Restart computer")) {

        try {

            Write-Host (
                "Restarting {0} - {1}..." -f
                $Computer.Name,
                $Computer.Description
            ) -ForegroundColor Cyan

            $RestartParameters = @{
                ComputerName = $Computer.Name
                ErrorAction  = "Stop"
            }

            if ($ForceRestart) {
                $RestartParameters.Force = $true
            }

            Restart-Computer @RestartParameters

            Write-Host (
                "Restart command sent successfully to {0}." -f
                $Computer.Name
            ) -ForegroundColor Green

            $RestartResults.Add(
                [PSCustomObject]@{
                    Name        = $Computer.Name
                    Description = $Computer.Description
                    Status      = "Command sent"
                    Details     = "Restart command accepted without error"
                }
            )
        }
        catch {

            $ErrorMessage = $_.Exception.Message

            Write-Host (
                "FAILED: {0} - {1}" -f
                $Computer.Name,
                $Computer.Description
            ) -ForegroundColor Red

            Write-Host "  $ErrorMessage" -ForegroundColor Red

            $RestartResults.Add(
                [PSCustomObject]@{
                    Name        = $Computer.Name
                    Description = $Computer.Description
                    Status      = "Failed"
                    Details     = $ErrorMessage
                }
            )
        }
    }
    else {

        $RestartResults.Add(
            [PSCustomObject]@{
                Name        = $Computer.Name
                Description = $Computer.Description
                Status      = "Not processed"
                Details     = "Restart was not approved by ShouldProcess"
            }
        )
    }
}

# ---------------------------------------------------------------------------
# Restart Summary
# ---------------------------------------------------------------------------

$CommandsSent = @(
    $RestartResults | Where-Object { $_.Status -eq "Command sent" }
).Count

$Failed = @(
    $RestartResults | Where-Object { $_.Status -eq "Failed" }
).Count

$Skipped = @(
    $RestartResults | Where-Object {
        $_.Status -in @("Skipped", "Not processed")
    }
).Count

Write-Host
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "            Restart Summary             " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host

foreach ($Result in $RestartResults) {

    switch ($Result.Status) {

        "Command sent" {
            $Colour = "Green"
        }

        "Failed" {
            $Colour = "Red"
        }

        default {
            $Colour = "Yellow"
        }
    }

    Write-Host (
        "[{0}] {1} - {2}" -f
        $Result.Status.ToUpper(),
        $Result.Name,
        $Result.Description
    ) -ForegroundColor $Colour

    Write-Host "  $($Result.Details)" -ForegroundColor Magenta
}

Write-Host
Write-Host "Restart commands sent : $CommandsSent" -ForegroundColor Green
Write-Host "Failures              : $Failed" -ForegroundColor Red
Write-Host "Skipped               : $Skipped" -ForegroundColor Yellow
Write-Host
