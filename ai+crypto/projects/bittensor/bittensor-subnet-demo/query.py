"""
Bittensor LLM 推理示例

两个可直接调用的子网：
  SN64 (Chutes)   - https://chutes.ai      - 无服务器 AI 平台，支持任意模型
  SN19 (Nineteen) - https://nineteen.ai    - 高频推理，低延迟

注册 SN64（一次性）：
  pip install chutes
  chutes register
  chutes keys create --name demo-key --admin   → 得到 cpk_xxx

注册 SN19：
  在 https://nineteen.ai/app/api 申请 API key
"""

import os, json, contextlib, requests
from openai import OpenAI

CHUTES_KEY   = os.environ.get("CHUTES_API_KEY",  "cpk_your_key_here")
NINETEEN_KEY = os.environ.get("NINETEEN_API_KEY", "your_nineteen_key_here")

# ── SN64 Chutes（openai SDK）────────────────────────────────────────────────
print("=== SN64 Chutes (https://llm.chutes.ai/v1) ===")

client64 = OpenAI(api_key=CHUTES_KEY, base_url="https://llm.chutes.ai/v1")

try:
    models = client64.models.list()
    print("可用模型（前 5）:", [m.id for m in list(models)[:5]])
except Exception as e:
    print(f"  获取模型失败: {e}")

try:
    resp = client64.chat.completions.create(
        model="deepseek-ai/DeepSeek-V3-0324",
        messages=[{"role": "user", "content": "你好，请用一句话介绍你自己"}],
        max_tokens=128,
        temperature=0.7,
    )
    print(f"回复: {resp.choices[0].message.content}")
    print(f"model={resp.model}  tokens={resp.usage.total_tokens}")
except Exception as e:
    print(f"  请求失败: {e}")


# ── SN19 Nineteen（requests + streaming，官方示例风格）─────────────────────
print("\n=== SN19 Nineteen (https://api.nineteen.ai/v1) ===")

url = "https://api.nineteen.ai/v1/chat/completions"
headers = {
    "Authorization": f"Bearer {NINETEEN_KEY}",
    "Content-Type": "application/json",
}
data = {
    "messages": [{"role": "user", "content": "你好，请用一句话介绍你自己"}],
    "model": "unsloth/Llama-3.2-3B-Instruct",
    "temperature": 0.5,
    "max_tokens": 500,
    "top_p": 0.5,
    "stream": True,
}

try:
    response = requests.post(url, headers=headers, json=data, timeout=30)
    if response.status_code != 200:
        raise Exception(response.text)

    print("回复: ", end="")
    for line in response.content.decode().split("\n"):
        if not line:
            continue
        with contextlib.suppress(Exception):
            chunk = json.loads(line.split("data: ")[1].strip())
            print(chunk["choices"][0]["delta"]["content"], end="", flush=True)
    print()
except Exception as e:
    print(f"  请求失败: {e}")


# ── 读取链上 Metagraph 数据（无需 API key）────────────────────────────────────
print("\n=== 链上数据：SN19 Metagraph ===")
try:
    import bittensor as bt
    sub  = bt.Subtensor(network="finney")
    meta = sub.metagraph(netuid=19)
    print(f"节点总数: {meta.n}  总质押: {meta.S.sum():.0f} TAO")
    # 不依赖 torch，用内置 sorted 按 incentive 排序
    top5 = sorted(range(meta.n), key=lambda uid: float(meta.I[uid]), reverse=True)[:5]
    print("Top 5 Miners (incentive 最高 = 服务质量最好):")
    for uid in top5:
        print(f"  UID {uid:3d} | incentive={float(meta.I[uid]):.4f} | trust={float(meta.TS[uid]):.4f}")
except Exception as e:
    print(f"  {e}")

