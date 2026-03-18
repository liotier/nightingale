"""
Key detection via Krumhansl-Schmuckler algorithm.

Reference: Krumhansl, C.L. & Kessler, E.J. (1982). "Tracing the dynamic
changes in perceived tonal organization in a spatial representation of
musical keys." Psychological Review, 89(4), 334-368.

Profile values from: Krumhansl, C.L. (1990). "Cognitive Foundations of
Musical Pitch." Oxford University Press, p.30.
"""

import numpy as np
import librosa
from scipy.stats import pearsonr

# Krumhansl-Kessler profiles for C major and C minor.
# Index 0 = C, 1 = C#/Db, 2 = D, ..., 11 = B.
KK_MAJOR = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09,
                     2.52, 5.19, 2.39, 3.66, 2.29, 2.88])

KK_MINOR = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53,
                     2.54, 4.75, 3.98, 2.69, 3.34, 3.17])

PITCH_CLASSES = ['C', 'C#', 'D', 'Eb', 'E', 'F',
                 'F#', 'G', 'Ab', 'A', 'Bb', 'B']


def detect_key(audio_path: str) -> str:
    """
    Detect the musical key of an audio file.

    Returns a string in pitch-corrector notation, e.g. 'Am', 'C', 'F#m'.
    Minor keys are suffixed with 'm'; major keys have no suffix.
    """
    y, sr = librosa.load(audio_path)

    # Isolate harmonic content to reduce residual percussive noise.
    y_harmonic = librosa.effects.harmonic(y)

    # Compute mean chroma vector over the full track (12 pitch classes).
    chroma = librosa.feature.chroma_cqt(y=y_harmonic, sr=sr)
    chroma_mean = np.mean(chroma, axis=1)  # shape: (12,)

    best_key = None
    best_r = -2.0

    for tonic in range(12):
        # Rotate profiles so that index 0 aligns with the candidate tonic.
        major_profile = np.roll(KK_MAJOR, tonic)
        minor_profile = np.roll(KK_MINOR, tonic)

        r_major, _ = pearsonr(chroma_mean, major_profile)
        r_minor, _ = pearsonr(chroma_mean, minor_profile)

        if r_major > best_r:
            best_r = r_major
            best_key = PITCH_CLASSES[tonic]         # e.g. 'A'

        if r_minor > best_r:
            best_r = r_minor
            best_key = PITCH_CLASSES[tonic] + 'm'   # e.g. 'Am'

    return best_key
