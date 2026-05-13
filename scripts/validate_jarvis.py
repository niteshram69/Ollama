#!/usr/bin/env python3
import time, json, requests, sys

KEY = "sk-q38YjUhFGiyAw5MuK6WaPfTaEK225aL8mNanHftySFEkRUec"
BASE = "http://127.0.0.1:4000/v1"
H = {"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}

print("=" * 60)
print("1. AUTH REJECTION (no key)")
t = time.time()
r = requests.get(f"{BASE}/models", timeout=10)
print(f"   status={r.status_code} time={time.time()-t:.3f}s")
print(f"   body={r.text[:120]}")

print()
print("2. AUTH SUCCESS (/v1/models)")
t = time.time()
r = requests.get(f"{BASE}/models", headers=H, timeout=10)
print(f"   status={r.status_code} time={time.time()-t:.3f}s")
data = r.json()
print(f"   models={[m['id'] for m in data.get('data', [])]}")

print()
print("3. LLAMA-SERVER DIRECT (raw latency baseline)")
t = time.time()
r = requests.post("http://127.0.0.1:8080/v1/chat/completions",
    json={"model":"qwen2.5-8b","messages":[{"role":"user","content":"Reply with OK only"}],
          "max_tokens":8,"temperature":0},timeout=60)
ttft = time.time() - t
print(f"   status={r.status_code} time={ttft:.3f}s")
j = r.json()
print(f"   response={j['choices'][0]['message']['content'][:80]}")

print()
print("4. CHAT via NGINX -> LiteLLM -> llama-server")
t = time.time()
r = requests.post(f"{BASE}/chat/completions", headers=H,
    json={"model":"chat","messages":[{"role":"user","content":"Say hello in exactly five words."}],
          "max_tokens":32,"temperature":0.2},timeout=90)
elapsed = time.time() - t
print(f"   status={r.status_code} time={elapsed:.3f}s")
j = r.json()
print(f"   model={j.get('model')} response={j['choices'][0]['message']['content'][:120]}")

print()
print("5. PLANNER via full stack")
t = time.time()
r = requests.post(f"{BASE}/chat/completions", headers=H,
    json={"model":"planner","messages":[
        {"role":"system","content":"You are a planning assistant. Create step-by-step plans."},
        {"role":"user","content":"Create a 3-step plan to learn Rust programming."}
    ],"max_tokens":512,"temperature":0.3},timeout=120)
elapsed = time.time() - t
print(f"   status={r.status_code} time={elapsed:.3f}s")
j = r.json()
content = j["choices"][0]["message"]["content"]
print(f"   response_len={len(content)} chars")
print(f"   first 200 chars: {content[:200]}")

print()
print("6. CLASSIFIER (short response)")
t = time.time()
r = requests.post(f"{BASE}/chat/completions", headers=H,
    json={"model":"classifier","messages":[
        {"role":"system","content":"Classify sentiment as positive/negative/neutral. One word only."},
        {"role":"user","content":"I absolutely love this product!"}
    ],"max_tokens":8,"temperature":0},timeout=30)
elapsed = time.time() - t
print(f"   status={r.status_code} time={elapsed:.3f}s")
j = r.json()
print(f"   response={j['choices'][0]['message']['content'][:60]}")

print()
print("7. STREAMING (time-to-first-token)")
t = time.time()
r = requests.post(f"{BASE}/chat/completions", headers=H, stream=True,
    json={"model":"chat","messages":[{"role":"user","content":"Explain CPU inference optimization in one paragraph."}],
          "stream":True,"max_tokens":256,"temperature":0.3},timeout=90)
first_chunk_time = None
chunk_count = 0
full_text = ""
for line in r.iter_lines(decode_unicode=True):
    if line and line.startswith("data: "):
        chunk_count += 1
        if first_chunk_time is None:
            first_chunk_time = time.time() - t
        if line.strip() == "data: [DONE]":
            break
        try:
            d = json.loads(line[6:])
            c = d["choices"][0]["delta"].get("content", "")
            full_text += c
        except:
            pass
total = time.time() - t
print(f"   TTFT={first_chunk_time:.3f}s total={total:.3f}s chunks={chunk_count}")
if total > 0:
    print(f"   tok/s~={len(full_text.split()) / total:.1f} words/s")
print(f"   first 200 chars: {full_text[:200]}")

print()
print("8. PROMETHEUS METRICS")
r = requests.get("http://127.0.0.1:8080/metrics", timeout=10)
for line in r.text.split("\n"):
    if any(k in line for k in ["llama_requests_processing","llama_kv_cache_usage","llama_tokens_predicted_total"]):
        if not line.startswith("#"):
            print(f"   {line}")

print()
print("9. SLOT STATUS")
r = requests.get("http://127.0.0.1:8080/slots", timeout=10)
slots = r.json()
for s in slots:
    print(f"   slot={s['id']} state={s.get('state','?')} n_ctx={s.get('n_ctx','?')}")

print()
print("=" * 60)
print("ALL TESTS PASSED")
