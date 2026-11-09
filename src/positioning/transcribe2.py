# Transcribe the lecture audio with faster-whisper; write segments with timestamps as they come.
import sys, time, json
import wave
import numpy as np
from faster_whisper import WhisperModel
audio, out, model_name, start, threads = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4]), int(sys.argv[5])
t0 = time.time()
model = WhisperModel(model_name, device="cpu", compute_type="int8", cpu_threads=threads)
prompt = ("Лекция по ортодонтии: позиционирование брекетов. Брекет, паз, слот, дуга, торк, ангуляция, ротация, "
          "инклинация, MBT, Roth, Andrews, клык, премоляр, моляр, резец, режущий край, бугор, высота брекета, "
          "клиническая коронка, ось зуба, окклюзионная плоскость, позиционер, непрямая фиксация, каппа, "
          "ортопантомограмма, трёхмерное планирование.")
w = wave.open(audio, "rb")
pcm = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0
pcm = pcm[int(start * 16000):]
w.close()
segs, info = model.transcribe(pcm, language="ru", beam_size=1, vad_filter=True, initial_prompt=prompt,
                              condition_on_previous_text=True)
with open(out, "w", encoding="utf-8") as f:
    for s in segs:
        f.write(json.dumps({"s": round(s.start + start, 1), "e": round(s.end + start, 1), "t": s.text.strip()}, ensure_ascii=False) + "\n")
        f.flush()
print("done", round(time.time() - t0), "s", info.duration)
