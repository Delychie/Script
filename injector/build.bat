@echo off
REM Build the GUI injector, the console injector, and the sample test DLL.
REM
REM Run this from a "Developer Command Prompt for VS" (so cl.exe / rc.exe are
REM on PATH), or from any prompt if you have MinGW-w64 (g++ / windres) on PATH.
REM
REM IMPORTANT: injector and target must have the SAME bitness (both x64 or
REM both x86). A 64-bit injector cannot inject into a 32-bit process here,
REM and vice versa. Use the matching Developer Command Prompt (x64 or x86).

setlocal

where cl >nul 2>nul
if %ERRORLEVEL%==0 goto build_msvc

where g++ >nul 2>nul
if %ERRORLEVEL%==0 goto build_mingw

echo [-] Neither cl.exe (MSVC) nor g++ (MinGW) found on PATH.
echo     Open a "Developer Command Prompt for VS" or install MinGW-w64.
exit /b 1

:build_msvc
echo [*] Building with MSVC (cl.exe)...
rc /nologo /fo resource.res resource.rc
if %ERRORLEVEL% neq 0 exit /b 1
cl /nologo /EHsc /O2 gui.cpp resource.res /Fe:injector-gui.exe /link /SUBSYSTEM:WINDOWS
if %ERRORLEVEL% neq 0 exit /b 1
cl /nologo /EHsc /W4 /O2 injector.cpp /Fe:injector.exe
if %ERRORLEVEL% neq 0 exit /b 1
cl /nologo /LD /EHsc /O2 sample_dll.cpp /Fe:sample.dll
if %ERRORLEVEL% neq 0 exit /b 1
del *.obj *.res >nul 2>nul
goto done

:build_mingw
echo [*] Building with MinGW (g++ / windres)...
windres resource.rc -O coff -o resource.res
if %ERRORLEVEL% neq 0 exit /b 1
g++ -std=c++17 -municode -O2 gui.cpp resource.res -o injector-gui.exe -mwindows -lcomctl32 -lcomdlg32 -lgdi32 -luxtheme
if %ERRORLEVEL% neq 0 exit /b 1
g++ -std=c++17 -municode -O2 injector.cpp -o injector.exe
if %ERRORLEVEL% neq 0 exit /b 1
g++ -shared -O2 sample_dll.cpp -o sample.dll
if %ERRORLEVEL% neq 0 exit /b 1
del resource.res >nul 2>nul
goto done

:done
echo [+] Done: injector-gui.exe, injector.exe, sample.dll
endlocal
