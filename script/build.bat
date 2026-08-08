@echo off
cd /d "%~dp0\.."
if not exist build mkdir build
odin build src/main -out:build\mouse-drift-city.exe -subsystem:WINDOWS
