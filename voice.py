import json
import os
import uuid
import urllib.request


SOVITS_URL_DEFAULT = "http://127.0.0.1:7860/"
SOVITS_OUTPUT_DIR_DEFAULT = r"D:\AI\turing_movies\audio"
SOVITS_JSON_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gpt_sovits.json")

_GRADIO_API = "/gradio_api/call"
_UPLOAD_API = "/gradio_api/upload"


def _sovits_params(text, infer_mode, output_dir):
    """ GPT-SoVITS /gen_single 的参数数组（顺序即 Gradio API 的参数顺序）。"""
    return [
        text,
        infer_mode,
        output_dir,
        120,  # max_text_tokens_per_sentence
        4,    # sentences_bucket_max_size
        True, # do_sample
        0.8,  # top_p
        30,   # top_k
        1,    # temperature
        0,    # batch_size（批次推理）
        3,    # batch_threshold
        10,   # split_interval
        600,  # speed_factor
    ]


def _upload_file(audio_path, sovits_url):
    """ 把本地参考音频 multipart 上传到 Gradio，返回临时文件路径（相当于 handle_file）。"""
    boundary = "----CodexFormBoundary" + uuid.uuid4().hex
    with open(audio_path, "rb") as f:
        audio_bytes = f.read()
    parts = [
        ("--" + boundary).encode() + b"\r\n",
        ('Content-Disposition: form-data; name="files"; filename="%s"\r\n'
         % os.path.basename(audio_path)).encode("utf-8"),
        b"Content-Type: application/octet-stream\r\n\r\n",
        audio_bytes + b"\r\n",
        ("--" + boundary + "--").encode() + b"\r\n",
    ]
    req = urllib.request.Request(
        sovits_url.rstrip("/") + _UPLOAD_API,
        data=b"".join(parts),
        headers={"Content-Type": "multipart/form-data; boundary=" + boundary},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        uploaded = json.loads(resp.read().decode("utf-8"))
    if not uploaded or not isinstance(uploaded[0], str):
        raise RuntimeError("GPT-SoVITS 音频上传失败：%s" % uploaded)
    return uploaded[0]


def sovits_http_tts(text, refer_voice_path, infer_mode="批次推理",
                    sovits_url=SOVITS_URL_DEFAULT, output_dir=SOVITS_OUTPUT_DIR_DEFAULT):
    """ 直接调用 Gradio HTTP API（等价于 curl POST /gradio_api/call/gen_single）：
        1. 上传参考音频 → 2. POST 生成请求拿 event_id → 3. 流式读取结果里的音频路径。
        返回 (音频路径, 音频 bytes)；失败抛异常（由调用方重试/兜底）。
    """
    try:
        base = sovits_url.rstrip("/")
        temp_path = _upload_file(refer_voice_path, base)
        data = [{"path": temp_path, "meta": {"_type": "gradio.FileData"}}] + \
            _sovits_params(text, infer_mode, output_dir)
        req = urllib.request.Request(
            base + _GRADIO_API + "/gen_single",
            data=json.dumps({"data": data}).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=60) as resp:
            event_id = json.loads(resp.read().decode("utf-8"))["event_id"]

        audio_path = None
        with urllib.request.urlopen(
            urllib.request.Request(base + _GRADIO_API + "/gen_single/" + event_id),
            timeout=300,
        ) as resp:
            for raw in resp:
                line = raw.decode("utf-8", "replace").strip()
                if not line.startswith("data:"):
                    continue
                data_str = line[len("data:"):].strip()
                if data_str in ("null", ""):
                    continue
                try:
                    obj = json.loads(data_str)
                except Exception:
                    continue
                if isinstance(obj, list):
                    # 生成过程事件：obj[0].value.path 为音频文件路径
                    if len(obj) > 1 and isinstance(obj[1], str):
                        audio_path = obj[1]
                    if audio_path is None and len(obj) > 0 and isinstance(obj[0], dict):
                        v = obj[0].get("value")
                        if isinstance(v, dict) and isinstance(v.get("path"), str):
                            audio_path = v["path"]
                elif isinstance(obj, dict):
                    if obj.get("msg") == "process_completed":
                        out_data = obj.get("output", {}).get("data")
                        if isinstance(out_data, list) and len(out_data) > 1 \
                                and isinstance(out_data[1], str):
                            audio_path = out_data[1]
                        break
                    if obj.get("msg") == "error":
                        raise RuntimeError("GPT-SoVITS 生成报错：%s"
                                           % json.dumps(obj, ensure_ascii=False)[:300])
        if not audio_path or not os.path.isfile(audio_path):
            raise RuntimeError("GPT-SoVITS 未返回有效音频路径: %s" % audio_path)
        with open(audio_path, "rb") as fh:
            return audio_path, fh.read()
    except Exception as e:
        print(e)
        raise


def index_tts(text, character_name="星见雅", infer_mode="批次推理",
              sovits_url=SOVITS_URL_DEFAULT, output_dir=SOVITS_OUTPUT_DIR_DEFAULT,
              use_http=True):
    """ Generate TTS using GPT-SoVITS (直接 HTTP 直调，等价 curl 方案).
    Args:
        text (str): The text to convert to speech.
        character_name (str): 角色名（对应 gpt_sovits.json 中的条目）.
        infer_mode (str, optional): 普通推理 or 批次推理.
        sovits_url (str, optional): GPT-SoVITS Gradio 服务地址.
        output_dir (str, optional): 生成音频的保存目录.
        use_http (bool, optional): True 走 gradio HTTP API 直调（默认）；
                                   False 回退 gradio_client 库。
    Returns:
        tuple (保存路径, 音频 bytes)；失败时返回 (None, None).
    """
    with open(SOVITS_JSON_PATH, "r", encoding="utf-8") as f:
        sovits_cfg = json.load(f)
        refer_voice_path = sovits_cfg[character_name]["ref_audio_path"]
    if use_http:
        return sovits_http_tts(text, refer_voice_path, infer_mode, sovits_url, output_dir)
    # 兜底：gradio_client 库方式（需要 pip install gradio-client）
    from gradio_client import Client, handle_file
    client = Client(sovits_url)
    result = client.predict(
        prompt=handle_file(refer_voice_path) if refer_voice_path else None,
        text=text,
        infer_mode=infer_mode,
        output_dir_input=output_dir,
        max_text_tokens_per_sentence=120,
        sentences_bucket_max_size=4,
        param_6=True,
        param_7=0.8,
        param_8=30,
        param_9=1,
        param_10=0,
        param_11=3,
        param_12=10,
        param_13=600,
        api_name="/gen_single")
    audio_path = result[1]
    if not audio_path or not os.path.isfile(audio_path):
        raise RuntimeError("GPT-SoVITS 未返回有效音频路径: %s" % audio_path)
    with open(audio_path, "rb") as fh:
        return audio_path, fh.read()


def sovits_tts_bytes(text, character_name="星见雅", infer_mode="批次推理",
                     sovits_url=SOVITS_URL_DEFAULT, output_dir=SOVITS_OUTPUT_DIR_DEFAULT):
    """ 便捷入口：只返回音频 bytes（供 tools/tts_server.py 直接转发给客户端）。"""
    _path, data = index_tts(text, character_name, infer_mode, sovits_url, output_dir)
    return data


def sovits_characters(path=SOVITS_JSON_PATH):
    """ 读取 gpt_sovits.json，返回可用的 GPT-SoVITS 角色名列表。"""
    try:
        with open(path, "r", encoding="utf-8") as f:
            cfg = json.load(f)
        return list(cfg.keys())
    except Exception as e:
        print(e)
        return []


if __name__ == "__main__":
    # asyncio.run(text_to_speech_edge(text="你好，世界！".strip(), filename="hello.mp3", voice="zh-CN-YunxiNeural"))
    audio_path, data = index_tts("你是谁？好像在哪里见过你呀。", character_name="光头强")
    print(audio_path, len(data) if data else 0)
