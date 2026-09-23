"""Write the chirp train the board detects: play it from a phone or speaker.

Matches sw/mic_demo/chirp.c: 20 ms linear chirp 500-6000 Hz with 10% cosine
edges, repeated every 0.3 s. 48 kHz, 16-bit mono PCM.
"""
import argparse
from pathlib import Path
import wave
import numpy as np

FS = 48000
CHIRP_S, PERIOD_S, F0, F1 = .02, .3, 500., 6000.


def chirp(fs=FS):
    t = np.arange(round(CHIRP_S*fs))/fs
    x = np.sin(2*np.pi*(F0*t+(F1-F0)*t**2/(2*CHIRP_S)))
    edge = max(int(.1*len(t)/2), 1)
    ramp = .5-.5*np.cos(np.pi*np.arange(edge)/edge)
    x[:edge] *= ramp; x[-edge:] *= ramp[::-1]
    return x


def train(seconds, fs=FS):
    out, pulse = np.zeros(round(seconds*fs)), chirp(fs)
    for start in range(round(.5*fs), len(out)-len(pulse), round(PERIOD_S*fs)):
        out[start:start+len(pulse)] = pulse
    return out


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--seconds', type=float, default=60.)
    p.add_argument('--out', type=Path, default=Path('chirp_train.wav'))
    args = p.parse_args()
    if not 1 <= args.seconds <= 3600:
        p.error('--seconds must be 1..3600')
    samples = np.round(.5*train(args.seconds)*32767).astype('<i2')
    with wave.open(str(args.out), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(FS); w.writeframes(samples.tobytes())
    print(f'{args.out}: {len(samples)/FS:g} s, {CHIRP_S*1e3:g} ms chirps {F0:g}-{F1:g} Hz every {PERIOD_S:g} s')


if __name__ == '__main__':
    main()
