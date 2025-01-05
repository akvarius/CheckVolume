@echo off& CLS
REM To enable sending a signal to healtcheck.io:
REM -CheckID xxxxxxxx
powershell.exe -executionpolicy bypass -file "%~dpn0.ps1" %1 %2 %3 %4 %5 %6 %7 %8 %9
