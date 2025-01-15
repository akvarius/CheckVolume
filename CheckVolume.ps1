<#
    .SYNOPSIS
    Get volume health and size
    Send signal to healthcheck.io

    .DESCRIPTION

    .PARAMETER CheckID
    Each test you create in Healthceck.io have an ID
    On success, a signal will be sendt like this:     https://hc-ping.com/<CheckID>
    On error a fail signal will be sendt with the same ID
    
    .LINK
    http://www.github.com/akvarius

#>

Param (
    [String]$CheckID,
    [String]$Settingspath,

    # PctMin specifies minimum % free space for small and medium volumes (< 2 TB)
    # (For larger volumes, threshold is 1GB)
    $PctMin = 7
)

$RemainingMinimum = 1GB

$FoundProblem = $false
$ErrMsg = @()

#$RatioMin = 0.07
#$RatioMin = 0.1
$RatioMin = $PctMin / 100



Function Invoke-BalloonTip {
    <#
    .Synopsis
        Display a balloon tip message in the system tray.

    .Description
        This function displays a user-defined message as a balloon popup in the system tray. This function
        requires Windows Vista or later.

    .Parameter Message
        The message text you want to display.  Recommended to keep it short and simple.

    .Parameter Title
        The title for the message balloon.

    .Parameter MessageType
        The type of message. This value determines what type of icon to display. Valid values are

    .Parameter SysTrayIcon
        The path to a file that you will use as the system tray icon. Default is the PowerShell ISE icon.

    .Parameter Duration
        The number of seconds to display the balloon popup. The default is 1000.

    .Inputs
        None

    .Outputs
        None

    .Notes
         NAME:      Invoke-BalloonTip
         VERSION:   1.0
         AUTHOR:    Boe Prox
    #>

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$True,HelpMessage="The message text to display. Keep it short and simple.")]
        [string]$Message,

        [Parameter(HelpMessage="The message title")]
         [string]$Title="Attention $env:username",

        [Parameter(HelpMessage="The message type: Info,Error,Warning,None")]
        [System.Windows.Forms.ToolTipIcon]$MessageType="Info",
     
        [Parameter(HelpMessage="The path to a file to use its icon in the system tray")]
        [string]$SysTrayIconPath='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',     

        [Parameter(HelpMessage="The number of milliseconds to display the message.")]
        [int]$Duration=1000, 


        [String[]]$MoreInfo

    )

    Add-Type -AssemblyName System.Windows.Forms

    If (-NOT $global:balloon) {
        $global:balloon = New-Object System.Windows.Forms.NotifyIcon

        #Mouse double click on icon to dispose
        [void](Register-ObjectEvent -InputObject $balloon -EventName MouseClick -SourceIdentifier IconClicked -Action {
            #Perform cleanup actions on balloon tip

            #$MoreInfo
 #          $msgBoxInput = [System.Windows.Forms.MessageBox]::Show($MoreInfo, $Title, 'YesNo') # , 'Information', 'Button1', 'ServiceNotification'
            
            # start notepad


            Write-Verbose 'Disposing of balloon'
            $global:balloon.dispose()
            Unregister-Event -SourceIdentifier IconClicked
            Remove-Job -Name IconClicked
            Remove-Variable -Name balloon -Scope Global
        })
    }

    #Need an icon for the tray
    $path = Get-Process -id $pid | Select-Object -ExpandProperty Path

    #Extract the icon from the file
    $balloon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($SysTrayIconPath)

    #Can only use certain TipIcons: [System.Windows.Forms.ToolTipIcon] | Get-Member -Static -Type Property
    $balloon.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]$MessageType
    $balloon.BalloonTipText  = $Message
    $balloon.BalloonTipTitle = $Title
    $balloon.Visible = $true

    #Display the tip and specify in milliseconds on how long balloon will stay visible
    $balloon.ShowBalloonTip($Duration)

    Write-Verbose "Ending function"

}

function ConvertDoubleToBytes {
    # Inspired by https://stackoverflow.com/users/10179421/jasn-hr and the solution in https://stackoverflow.com/questions/37154375/display-disk-size-and-freespace-in-gb
    # Added left padding
    Param (
        [double]$srcDouble
    )

    $txtSize = [Math]::Ceiling($srcDouble/([math]::pow(1024,([Math]::Floor([Math]::Log($srcDouble,1024)))))).ToString().PadLeft(3)
    $txtSize + "$(Switch ([Math]::Floor([Math]::Log($srcDouble,1024))) {
        0 { " Bytes" }
        1 { " KB" }
        2 { " MB" }
        3 { " GB" }
        4 { " TB" }
        5 { " PB" }
    })"
}

$VolumeList = Get-Volume | Where-Object {$_.DriveType -like 'Fixed'} | ForEach-Object {
    If ($_.Size -gt 0) {
        $FreeRatio = $_.SizeRemaining / $_.Size
    } Else {
        $FreeRatio = $null
    }
    $_ | Add-Member -MemberType NoteProperty -Name FreeRatio -Value $FreeRatio

    If ($_.Healthstatus -ne 'Healthy') {
        $FoundProblem = $true

        $NewTxt = @("Volume health problem:", "Drive $($_.DriveLetter)".PadLeft(3), "Label '$($_.FileSystemLabel)'".PadLeft(5), ':', $_.Healthstatus) -join ' '
        $ErrMsg += $NewTxt
        Write-host $NewTxt
    }
    
    # Size thresholds...
    If ($CheckFree -or $true) {
        switch ($_.Size) {
            {$_ -lt 100GB} {
                $COnd = {$_.FreeRatio  -lt $RatioMin}}    # Small      x < 100GB ratioMin 0.07
            {$_ -ge 100GB -and $_ -lt 2TB}   {
                $COnd = {$_.SizeRemaining -lt 10GB -or $_.FreeRatio  -lt $RatioMin}}  # Medium     100GB < x < 2TB, ratioMin 0.07
            {$_ -ge 2TB   -and $_ -lt 10TB}  {
                $COnd = {$_.SizeRemaining -lt 100GB}}  # Big        2TB   < x < 10TB
            {$_ -ge 10TB  -and $_ -ge 10TB}  {
                $COnd = {$_.SizeRemaining -lt 100GB}}  # veryBig    10TB  < x
        }

        If ($_ | Where-Object $Cond ) {
            $FoundProblem = $true

            $NewTxt = @("Free space below limit:", "$($_.DriveLetter)".PadLeft(3), "$($_.FileSystemLabel)".PadLeft(5), (ConvertDoubleToBytes($_.Size)), (ConvertDoubleToBytes($_.SizeRemaining)), "$("{0,7:p}" -F  ($_.FreeRatio))") -join ' '
            $ErrMsg += $NewTxt
            #Write-host $NewTxt
            # Write-host  "Free space below limit:", "$($_.DriveLetter)".PadLeft(3), "$($_.FileSystemLabel)".PadLeft(5), (ConvertDoubleToBytes($_.Size)), (ConvertDoubleToBytes($_.SizeRemaining)), "$($_.FreeRatio)".PadLeft(5)
        }
    }

    $_
}

$ShortList = $VolumeList  | Format-Table @{L="Drive";e={$_.DriveLetter}},
    @{L="Label";e={$_.FileSystemLabel}},
    @{L="Health";e={$_.HealthStatus}},
    @{n="Size"; e={ConvertDoubleToBytes($_.Size)}},
    @{L="Free"; e={ConvertDoubleToBytes($_.SizeRemaining)}},
    @{L="%Free";e={"{0,7:p}" -F  ($_.FreeRatio)}},
    @{L="Path"; e={$_.Path}}


$ErrMsg | out-host
$ShortList | out-host

If ($FoundProblem) {
    Write-Host "Found a problem"

    If ($CheckID) {
        $ErrMsg,$ShortList | Out-String | Invoke-RestMethod "https://hc-ping.com/$CheckID/fail" -headers @{'User-Agent'="$($ENV:Computername) Disk Volume problem"} -method POST
    }

    Invoke-BalloonTip  -Message "$ErrMsg" -Title "Volume problem" 
} Else {
    # Send OK
    Write-Host "Volumes OK"

    If ($CheckID) {
        $ShortList | Out-String| Invoke-RestMethod "https://hc-ping.com/$CheckID" -headers @{'User-Agent'="$($ENV:Computername) Disk Volumes OK"} -method POST
    }
}

