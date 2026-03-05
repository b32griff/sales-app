# ToneCoach On-Device Smoke Test

**Duration:** ~5 minutes
**Requires:** Physical iPhone with microphone access

---

## Setup

1. Build and run ToneCoach on a physical device (simulator lacks real mic input).
2. Grant microphone permission when prompted.
3. Ensure you are in a quiet-ish room where you can speak at normal volume.

---

## Test 1: Session Start + Volume Card (1 min)

**Steps:**
1. Tap **Start** on the Practice screen.
2. Stay silent for 3 seconds.
3. Speak a sentence at normal volume (e.g., "The quarterly results exceeded expectations").

**Expected:**
- Volume card shows "Ready" initially, then updates to a dB reading within 1 second of speaking.
- Waveform graph animates smoothly (no freezes or flicker).
- Status shows "In Range" (green) if your volume is within the target band shown in the footer.

---

## Test 2: Cadence Warm-up Gate (1 min)

**Steps:**
1. While the session is running, watch the Cadence card.
2. Speak 2 short words and wait. Note the cadence label.
3. Continue speaking naturally for 3+ seconds with 3+ distinct words.

**Expected:**
- Cadence card shows "--" (idle) until both conditions are met: 3 seconds elapsed AND 3+ words detected.
- After the gate opens, a WPM number appears (e.g., "142 wpm").
- If speaking too fast or slow, a coaching banner pill appears ("Slow down" or "Speed up").

---

## Test 3: Tone Grading (1 min)

**Steps:**
1. Speak a clear declarative sentence ending with a downward pitch: "We should move forward with this plan."
2. Pause for 1-2 seconds (phrase boundary).
3. Speak a question with upward pitch: "Does that make sense?"
4. Pause again.

**Expected:**
- Tone card updates after each phrase boundary (1.5s cooldown between results).
- Downward-ending declarative sentence should show a **pass** (green checkmark).
- Upward-ending question should show a **fail** (red X) or **unknown** (gray ?).
- Short or ambiguous phrases may show unknown (gray ?) — this is correct behavior.

---

## Test 4: Coaching Prompts (30s)

**Steps:**
1. Speak very quietly (whisper) for 5+ seconds.
2. OR speak very loudly for 5+ seconds.

**Expected:**
- After ~4 seconds, a coaching prompt banner appears at the top (e.g., "Project your voice" or "Ease your volume").
- Prompt auto-dismisses or can be tapped to dismiss.
- No more than 1 prompt per 4 seconds (no rapid-fire banners).

---

## Test 5: Session End + Summary (1 min)

**Steps:**
1. Tap **End Session** (or the stop button).
2. Review the Session Complete screen.

**Expected:**
- Authority Score displays (0-100) with a color ring.
- Metrics grid shows: Down-tone %, Volume in-range %, Avg WPM, Pause ratio.
- A takeaway line appears below the score (e.g., "Focus on ending sentences with downward inflection").
- Tapping **Done** returns to the main screen.
- The session appears in History with the correct score badge.

---

## Test 6: History (30s)

**Steps:**
1. Navigate to the History tab.
2. Verify the session you just completed is listed.

**Expected:**
- Session row shows date, duration, and authority score badge.
- Score badge color: green (70+), yellow (40-69), red (<40).
- If this is your first session, the trend chart area shows "One more session to see trends".
- If 2+ sessions exist, trend lines appear for Authority Score and individual metrics.

---

## Pass Criteria

All 6 tests must show expected behavior. Known acceptable deviations:
- Short phrases (< 400ms) yielding "unknown" grade is intentional, not a bug.
- Cadence may briefly show 0 wpm during the warm-up gate — this is correct.
- CoreData warnings in console logs are harmless (simulator artifact).
