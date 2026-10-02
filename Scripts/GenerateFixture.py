"""Original synthesized pulse/chord fixture; contains no recordings or licensed samples."""
from pathlib import Path
import math, struct, wave
output = Path(__file__).resolve().parents[1] / 'Tests/Fixtures/StudioPulse.wav'
output.parent.mkdir(parents=True, exist_ok=True)
rate, duration = 22050, 16
with wave.open(str(output), 'wb') as audio:
    audio.setnchannels(1); audio.setsampwidth(2); audio.setframerate(rate)
    samples = bytearray()
    for index in range(rate * duration):
        t = index / rate
        phase = t % 0.5
        pulse = math.exp(-phase * 25) * math.sin(2 * math.pi * 80 * t)
        chord = sum(math.sin(2 * math.pi * f * t) for f in (261.63, 329.63, 392.0)) / 3
        fade = min(1, t * 10, (duration - t) * 10)
        value = fade * (0.35 * pulse + 0.15 * chord)
        samples.extend(struct.pack('<h', int(value * 32767)))
    audio.writeframes(samples)
print(output.name)
