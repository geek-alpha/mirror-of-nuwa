@echo off
rem 一键启动 AI 语音服务（Edge TTS 本地服务，端口 17820）
rem 依赖：python + edge-tts（首次运行请先执行：pip install -r tools/requirements-tts.txt）
cd /d "%~dp0"
python tools\tts_server.py --port 17820
if errorlevel 1 (
  echo.
  echo 启动失败：请确认已安装 Python 与 edge-tts，或服务可能已在运行。
  pause
)
