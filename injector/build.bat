@echo off
REM Build the injector and the sample test DLL.
REM
REM Run this from a "Developer Command Prompt for VS" (so cl.exe is on PATH),
REM or from any prompt if you have MinGW's g++ on PATH.
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
cl /nologo /EHsc /W4 /O2 injector.cpp /Fe:injector.exe
if %ERRORLEVEL% neq 0 exit /b 1
cl /nologo /LD /EHsc /O2 sample_dll.cpp /Fe:sample.dll
if %ERRORLEVEL% neq 0 exit /b 1
del *.obj >nul 2>nul
goto done

:build_mingw
echo [*] Building with MinGW (g++)...
g++ -std=c++17 -municode -O2 injector.cpp -o injector.exe
if %ERRORLEVEL% neq 0 exit /b 1
g++ -shared -O2 sample_dll.cpp -o sample.dll
if %ERRORLEVEL% neq 0 exit /b 1
goto done

:done
echo [+] Done: injector.exe and sample.dll
endlocal
