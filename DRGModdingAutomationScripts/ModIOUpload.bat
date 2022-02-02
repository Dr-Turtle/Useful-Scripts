@echo off
setlocal enableDelayedExpansion

::Set active directory to the dir the bat is in
pushd %~dp0

call VerifyVars.bat noPause

::Find variables in config.ini
for /f "tokens=1,2 delims==" %%g in (Config.ini) do (
	REM Variables modname and ProjectFile need to be treated differently, all other variables in Config.ini are paths
	if %%g==ModName (
		set ModName=%%h
		set PakName=%%h.pak
	) else if %%g==ProjectFile (
		REM Resolve to path w/ drive letter
		set ProjectFolder=%%~dph
		REM Resolve to file name w/ extension
		set ProjectFile=%%~nxh
	) else (
		REM Resolve qualified path name
		set %%g=%%~fh
	)
)
::Find variables in ModIOConfig.ini
for /f "delims=" %%g in (ModIOConfig.ini) do (set "%%g")

::If verbose is enabled, -v will be added to tar and curl commands
if /I %Verbose%==true (
	set VerboseParam=-v
) else (
	set VerboseParam=
)


::If called from ModIOQuickTestMod.bat, use pak in .\Temp
if "%2"=="UseTempPak" (
	set PakLocation="%cd%\Temp"
) else (
	set PakLocation="%SteamInstall%\FSD\Mods\%ModName%"
)

set Version=%MajorVersion%^.%MinorVersion%

if /I %AddVersionToModName%==true (
	copy %PakLocation%\%ModName%.pak %cd%\Temp\%ModName%%Version%.pak
	set ModName=%ModName%%Version%
	set PakLocation="%cd%\Temp"
)

call CopyWhitelistedFiles.bat noPause
call StripBlacklistedFiles.bat noPause

::Deletes old files and sets the new zip name to save
del %LastZip%
del %LastPak%

::Saves paths to old files to delete next run
call :SaveToConfig SaveLastZip "%ZipLocation%\%ModName%.zip"
call :SaveToConfig SaveLastPak "%cd%\Temp\%ModName%.pak"

::creates zip with pak inside to upload to mod.io
tar %VerboseParam% -acf "%ZipLocation%\%ModName%.zip" -C %PakLocation% %ModName%.pak

::checks if tar returned an error
if not %errorlevel%==0 (
	if /I %Verbose%==true (
		echo tar.exe exited with code %errorlevel%, aborting
	) else (
		echo echo tar.exe exited with code %errorlevel%, aborting ^(try enabling verbose in ModIOConfig^.ini for more info^)
	)
	pause
	exit /b 2
)

::Prompts user to enter a changelog if enabled
if /I %AskForChangelog%==true (
	set /P ChangelogInput=Enter Changelog ^(This can be disabled in ModIOConfig^.ini^):
) else (
	set ChangelogInput=%ChangeLog%
)

::Make call to mod.io api to upload mod
curl %VerboseParam% -X POST "https://api.mod.io/v1/games/%gameID%/mods/%modID%/files" ^
	-H "Authorization: Bearer %Token%" ^
	-H "Content-Type: multipart/form-data" ^
	-H "Accept: application/json" ^
	-F "filedata=@%ZipLocation%\%ModName%.zip" ^
	-F "version=%Version%" ^
	-F "changelog=%ChangelogInput%"

::checks if curl returned an error
if not %errorlevel%==0 (
	if /I %Verbose%==true (
		echo curl.exe exited with code %errorlevel%, aborting
	) else (
		echo echo curl.exe exited with code %errorlevel%, aborting ^(try enabling verbose in ModIOConfig^.ini for more info^)
	)
	pause
	exit /b 2
)

::Increases minor version by 1 if enabled
if /I %AutoIncrementVersion%==true (
	set /a MinorVersion=%MinorVersion%+1
)
::Saves new minor version
call :SaveToConfig SaveMinorVersion

::Pauses unless called from another script using the noPause argument
if not "%1"=="noPause" (
	pause
)

::Called whenever a value needs to be saved to config
:SaveToConfig
	(
		for /F "tokens=1,2 delims==" %%g in (ModIOConfig.ini) do (
			set LineWasSet=false
			if /I %%g==MinorVersion (
				if /I %AutoIncrementVersion%==true (
					if "%1"=="SaveMinorVersion" (
						set /A MinorVersion=%%h+1
						set "line=%%g=!MinorVersion!"
						set LineWasSet=true
					)
				)
			)
			if %%g==LastZip (
				if "%1"=="SaveLastZip" (
					set "line=%%g=%2%"
					set LineWasSet=true
				)
			)
			if %%g==LastPak (
				if "%1"=="SaveLastPak" (
					set "line=%%g=%2%"
					set LineWasSet=true
				)
			)
			if !LineWasSet!==false (
				set "line=%%g=%%h"
			)
			echo !line!
		)
	) > TempModIOConfig.ini
	del ModIOConfig.ini
	rename TempModIOConfig.ini ModIOConfig.ini
	exit /B 0
