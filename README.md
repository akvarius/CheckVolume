    .SYNOPSIS
    Get volume health and size
    Send signal to healthcheck.io

    .DESCRIPTION

    .PARAMETER CheckID
    Each test you create in Healthceck.io have an ID
    On success, a signal will be sendt like this:     https://hc-ping.com/<CheckID>
    On error a fail signal will be sendt with the same ID
