@echo off
rem Build APK FamLoc secara ter-detach agar tidak mati saat sesi shell berakhir
set PATH=D:\flutter\bin;%PATH%
set ANDROID_HOME=C:\Users\awand\AppData\Local\Android\Sdk
cd /d "D:\app android\FamLocation\apps\mobile"
call flutter build apk --debug > "D:\app android\FamLocation\build_log.txt" 2>&1
echo BUILD_EXIT=%ERRORLEVEL% >> "D:\app android\FamLocation\build_log.txt"
