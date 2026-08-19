#!/usr/bin/env python3
"""
本地语音服务（供 Godot 游戏调用）。

依赖：
    pip install -r tools/requirements-tts.txt

接口：
    GET  /health   -> {"ok": true}
    GET  /voices   -> {"provider": "edge", "voices": [{"id": "...", "name": "...", "provider": "edge|sovits"}]}
                      （Edge 中文声音池 + GPT-SoVITS 角色声音池，带缓存）
    POST /tts      -> 音频流（Content-Type 由合成引擎决定：Edge=audio/mpeg，GPT-SoVITS=audio/wav），请求体:
                      {"text": "...", "voice": "...", "provider": "edge|sovits",
                       "rate": "+20%", "volume": "+0%"}

启动：
    python tools/tts_server.py [--port 17820]

说明：服务常驻本地，多请求并发生成并缓存相同文本，保证游戏内语音快速流畅。
Edge 走微软在线 TTS；GPT-SoVITS 走本机 Gradio 服务（voice.py 中的 index_tts）。
"""

import argparse
import asyncio
import io
import json
import os
import shutil
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

try:
    import edge_tts
except ImportError:
    print("缺少依赖：请先运行 pip install edge-tts", file=sys.stderr)
    sys.exit(1)

# 加载根目录 voice.py（GPT-SoVITS 合成逻辑），失败时仅 Edge 可用
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)
try:
    import voice as voice_module
except Exception as exc:  # noqa: BLE001
    voice_module = None
    print("警告：无法加载 voice.py，GPT-SoVITS 语音不可用（%s）" % exc, file=sys.stderr)

DEFAULT_PORT = 17820
AUDIO_CACHE = {}
CACHE_MAX = 300
VOICE_CACHE = {"voices": None, "fetched_at": 0.0}
VOICE_REFRESH_SECONDS = 600.0
SOVITS_JSON = os.path.join(PROJECT_ROOT, "gpt_sovits.json")
SERVER_VERSION = 2

PROVIDER_EDGE = "edge"
PROVIDER_SOVITS = "sovits"


async def _fetch_voices() -> list:
    raw = await edge_tts.list_voices()
    voices = [v["ShortName"] for v in raw if str(v.get("Locale", "")).startswith("zh-")]
    return sorted(set(voices))


def get_voices(force_refresh: bool = False) -> list:
    import time
    now = time.time()
    if (
        VOICE_CACHE["voices"] is None
        or force_refresh
        or now - VOICE_CACHE["fetched_at"] > VOICE_REFRESH_SECONDS
    ):
        VOICE_CACHE["voices"] = asyncio.run(_fetch_voices())
        VOICE_CACHE["fetched_at"] = now
    return VOICE_CACHE["voices"]


async def _synthesize(text: str, voice: str, rate: str, volume: str) -> bytes:
    communicate = edge_tts.Communicate(text, voice, rate=rate, volume=volume)
    chunks = []
    async for chunk in communicate.stream():
        if chunk.get("type") == "audio":
            chunks.append(chunk["data"])
    return b"".join(chunks)


def synthesize(text: str, voice: str, rate: str, volume: str) -> bytes:
    key = (voice, rate, volume, text)
    if key in AUDIO_CACHE:
        return AUDIO_CACHE[key]
    data = asyncio.run(_synthesize(text, voice, rate, volume))
    if not data:
        raise RuntimeError("合成结果为空，请检查声音名是否正确")
    AUDIO_CACHE[key] = data
    if len(AUDIO_CACHE) > CACHE_MAX:
        # 简单 FIFO 淘汰，防止缓存无限增长
        for old_key in list(AUDIO_CACHE.keys())[: len(AUDIO_CACHE) - CACHE_MAX]:
            AUDIO_CACHE.pop(old_key, None)
    return data


def sovits_characters() -> list:
    if voice_module is None:
        return []
    return voice_module.sovits_characters(SOVITS_JSON)


def sovits_synthesize(text: str, character_name: str) -> bytes:
    """ 调用 voice.py 的 index_tts 生成 GPT-SoVITS 语音。
    返回 MP3 字节（优先，与 Edge 播放链路一致）；无 ffmpeg 时返回完整 WAV 字节。"""
    if voice_module is None:
        raise RuntimeError("voice.py 未加载，GPT-SoVITS 不可用")
    if character_name not in sovits_characters():
        raise RuntimeError("未知的 GPT-SoVITS 角色：%s" % character_name)
    data = voice_module.sovits_tts_bytes(text, character_name=character_name)
    if not data:
        raise RuntimeError("GPT-SoVITS 合成失败，请确认本机服务已启动（http://127.0.0.1:7860/）")
    # 校验是有效 WAV（客户端会解析头；这里保证数据完整）
    if len(data) < 44 or data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise RuntimeError("GPT-SoVITS 返回的不是有效 WAV 数据")
    return _wav_to_mp3(data)


def _wav_to_mp3(wav_data: bytes) -> bytes:
    """ 用 ffmpeg 把 WAV 转 MP3；失败或没有 ffmpeg 时原样返回 WAV。"""
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        return wav_data
    try:
        proc = subprocess.run(
            [ffmpeg, "-y", "-i", "pipe:0", "-f", "mp3", "-b:a", "192k", "pipe:1"],
            input=wav_data,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=60,
        )
        if proc.returncode == 0 and proc.stdout:
            return proc.stdout
    except Exception as exc:  # noqa: BLE001
        print("ffmpeg 转 MP3 失败：%s" % exc)
    return wav_data


def get_voice_list() -> dict:
    """ 返回带 provider 标记的完整声音池（Edge + GPT-SoVITS）。"""
    edge_voices = [
        {"id": v, "name": v, "provider": PROVIDER_EDGE}
        for v in get_voices()
    ]
    sovits_voices = [
        {"id": name, "name": name, "provider": PROVIDER_SOVITS}
        for name in sovits_characters()
    ]
    return {
        "provider": PROVIDER_EDGE,
        "voices": edge_voices + sovits_voices,
        "count": len(edge_voices) + len(sovits_voices),
    }


class TTSHandler(BaseHTTPRequestHandler):
    def _send_json(self, code: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_audio(self, data: bytes, content_type: str) -> None:
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:
        try:
            if self.path.startswith("/health"):
                self._send_json(200, {"ok": True})
                return
            if self.path.startswith("/version"):
                self._send_json(200, {"version": SERVER_VERSION})
                return
            if self.path.startswith("/voices"):
                force = "refresh=1" in self.path
                if force:
                    get_voices(force_refresh=True)
                self._send_json(200, get_voice_list())
                return
            self._send_json(404, {"error": "not found"})
        except Exception as exc:  # noqa: BLE001
            self._send_json(500, {"error": "获取声音列表失败：%s" % exc})

    def do_POST(self) -> None:
        try:
            length = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(length) if length > 0 else b"{}"
            payload = json.loads(raw.decode("utf-8", "replace"))
            text = str(payload.get("text", "")).strip()
            if not text:
                self._send_json(400, {"error": "text 不能为空"})
                return
            voice = str(payload.get("voice", "zh-CN-YunxiNeural"))
            provider = str(payload.get("provider", PROVIDER_EDGE))
            rate = str(payload.get("rate", "+20%"))
            volume = str(payload.get("volume", "+0%"))
            if provider == PROVIDER_SOVITS or voice in sovits_characters():
                data = sovits_synthesize(text, voice)
                # 优先 MP3（与 Edge 一致）；无 ffmpeg 时退回 WAV
                if data[:3] == b"ID3" or data[2:4] == b"\xff\xfb":
                    self._send_audio(data, "audio/mpeg")
                else:
                    self._send_audio(data, "audio/wav")
            else:
                data = synthesize(text, voice, rate, volume)
                self._send_audio(data, "audio/mpeg")
        except Exception as exc:  # noqa: BLE001
            self._send_json(500, {"error": "TTS 失败：%s" % exc})

    def log_message(self, fmt: str, *args) -> None:
        pass


def main() -> None:
    parser = argparse.ArgumentParser(description="Edge TTS 本地语音服务")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), TTSHandler)
    print("TTS 服务已启动: http://127.0.0.1:%d （Ctrl+C 退出）" % args.port, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
