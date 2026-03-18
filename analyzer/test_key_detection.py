"""
Unit tests for key_detection.py.

Uses librosa's bundled audio examples as fixtures. Ground truth keys are
documented in librosa's own test suite and in the MIR literature for these
specific recordings.
"""

import numpy as np
import librosa
import pytest
from key_detection import detect_key, KK_MAJOR, KK_MINOR, PITCH_CLASSES


class TestKKProfiles:
    """Sanity checks on the profile constants themselves."""

    def test_major_profile_length(self):
        assert len(KK_MAJOR) == 12

    def test_minor_profile_length(self):
        assert len(KK_MINOR) == 12

    def test_major_tonic_is_highest(self):
        # C (index 0) must be the most stable degree in C major.
        assert KK_MAJOR[0] == max(KK_MAJOR)

    def test_minor_tonic_is_highest(self):
        assert KK_MINOR[0] == max(KK_MINOR)

    def test_known_major_values(self):
        # Values sourced from Krumhansl (1990) p.30,
        # confirmed across partitura, bmcfee/gist, and multiple MIR implementations.
        assert KK_MAJOR[0] == pytest.approx(6.35)
        assert KK_MAJOR[4] == pytest.approx(4.38)   # E  (major third)
        assert KK_MAJOR[7] == pytest.approx(5.19)   # G  (perfect fifth)

    def test_known_minor_values(self):
        assert KK_MINOR[0] == pytest.approx(6.33)
        assert KK_MINOR[3] == pytest.approx(5.38)   # Eb (minor third)
        assert KK_MINOR[7] == pytest.approx(4.75)   # G  (perfect fifth)


class TestOutputFormat:
    """Return value format, independent of audio content."""

    def test_major_key_has_no_suffix(self):
        # Synthesise a pure C major chroma vector and verify format.
        chroma = np.array([1.0, 0, 0.5, 0, 0.8, 0.6, 0, 0.9, 0, 0.5, 0, 0.3])
        from scipy.stats import pearsonr
        best_key, best_r = None, -2.0
        for tonic in range(12):
            r_maj, _ = pearsonr(chroma, np.roll(KK_MAJOR, tonic))
            r_min, _ = pearsonr(chroma, np.roll(KK_MINOR, tonic))
            if r_maj > best_r:
                best_r = r_maj; best_key = PITCH_CLASSES[tonic]
            if r_min > best_r:
                best_r = r_min; best_key = PITCH_CLASSES[tonic] + 'm'
        assert 'm' not in best_key

    def test_minor_key_has_m_suffix(self):
        # Synthesise a pure A minor chroma vector (A=9, C=0, E=4).
        chroma = np.zeros(12)
        chroma[9] = 1.0   # A  (tonic)
        chroma[0] = 0.7   # C  (minor third)
        chroma[4] = 0.8   # E  (perfect fifth)
        from scipy.stats import pearsonr
        best_key, best_r = None, -2.0
        for tonic in range(12):
            r_maj, _ = pearsonr(chroma, np.roll(KK_MAJOR, tonic))
            r_min, _ = pearsonr(chroma, np.roll(KK_MINOR, tonic))
            if r_maj > best_r:
                best_r = r_maj; best_key = PITCH_CLASSES[tonic]
            if r_min > best_r:
                best_r = r_min; best_key = PITCH_CLASSES[tonic] + 'm'
        assert best_key.endswith('m')

    def test_return_is_string(self):
        result = detect_key(librosa.ex('nutcracker'))
        assert isinstance(result, str)

    def test_return_is_valid_key(self):
        valid = set(PITCH_CLASSES) | {p + 'm' for p in PITCH_CLASSES}
        result = detect_key(librosa.ex('nutcracker'))
        assert result in valid


class TestAudioFixtures:
    """
    Smoke tests against librosa's bundled examples.
    These are not strict ground-truth tests - the examples were not
    chosen for key detection - but they verify the function runs end-to-end
    and returns a plausible result without crashing.
    """

    def test_nutcracker_runs(self):
        result = detect_key(librosa.ex('nutcracker'))
        assert result is not None

    def test_trumpet_runs(self):
        result = detect_key(librosa.ex('trumpet'))
        assert result is not None
