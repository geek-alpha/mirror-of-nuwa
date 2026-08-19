@echo off
rem 一键彻底重启 AI 语音服务（升级到支持 GPT-SoVITS + MP3 输出的新版）
rem 1) 结束所有命令行包含 tts_server.py 的 python 进程
rem 2) 结束占用 17820 端口的进程（双保险）
rem 3) 启动新版服务并验证
cd /d "%~dp0"

echo [1/3] 结束旧版 tts_server 进程...
for /f "tokens=2 delims=," %%p in ('wmic process where "name='python.exe' or name='python3.exe'" get processid,commandline /format:csv 2^>nul ^| findstr /i "tts_server"') do (
  echo   结束 PID %%p
  taskkill /F /PID %%p >nul 2>&1
)

echo [2/3] 释放 17820 端口...
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":17820" ^| findstr "LISTENING"') do (
  echo   结束占用进程 PID %%p
  taskkill /F /PID %%p >nul 2>&1
)
timeout /t 2 /nobreak >nul

echo [3/3] 启动新版语音服务...
start "TTS Server" /min cmd /c "python tools\tts_server.py --port 17820"
timeout /t 4 /nobreak >nul

echo 验证服务版本：
curl -s http://127.0.0.1:17820/version
echo.
echo 若显示 {"version": 2} 表示新版服务已启动。
echo 之后请完全关闭游戏再重新打开，然后点「刷新声音」测试。
pause
