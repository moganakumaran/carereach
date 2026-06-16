# CareReach — multilingual voice questions (tested) + recording storyboard

These questions were run through the **real** app pipeline (browser ASR → `translate_to_english`
on llama-3.3-70b → `grounded_answer` over `mdp.gold.region_signals`) against the **Bihar /
district** view. Translations and answers below are the actual outputs captured on 2026-06-16.

**Before recording:** open the app, set **Geography level = district** and **Filter by state = Bihar**.
In the voice panel, pick the language in the dropdown that matches what you'll speak, tap **🎤 Record
question**, say the sentence clearly (short = more reliable), tap **⏹ Stop (transcribe)**. The app shows
**Heard (lang): …** then **→ English: …** and fills the question box; click **Ask**.

> Free Google recognition is best-effort. If nothing appears, you'll now get a "couldn't transcribe —
> try again" message (not silence). Speak a short, clear sentence and confirm the language matches.

---

## The question set (6 languages, 6 intents)

### 1. Hindi — "where to deploy" (the core ask)
- **Say:** बिहार में हमें मोबाइल मातृ स्वास्थ्य इकाई कहाँ भेजनी चाहिए?
- **Translates to:** *Where should we send the mobile maternal health unit in Bihar?*
- **Answer recommends** REAL deserts (Katihar, Saharsa, Madhepura …) and flags DATA-POOR
  (Sitamarhi, Araria, Kishanganj …) as investigate-first.

### 2. Bengali — "investigate first" (the honesty signal)
- **Say:** মোতায়েনের আগে আমাদের কোন জেলাগুলি আগে তদন্ত করা উচিত?
- **Translates to:** *Which districts should we investigate first before deployment?*
- **Answer lists** the DATA-POOR districts with their gap/confidence numbers (Araria 0.83/0.00,
  Sheikhpura/Lakhisarai 0.00 confidence) — explicitly "not confirmed deserts."

### 3. Tamil — "high gap AND trustworthy" (two signals at once)
- **Say:** எந்த மாவட்டங்களில் அதிக சுகாதார இடைவெளி இருக்கிறது, ஆனால் நம்பகமான தரவும் இருக்கிறது?
- **Translates to:** *Which districts have high health gaps but also have reliable data?*
- **Answer returns** the REAL deserts (high gap + confidence 0.47–0.65) and separates the low-confidence ones.

### 4. Telugu — "real deserts vs just data-poor" (the headline distinction)
- **Say:** ఏ జిల్లాలు నిజమైన వైద్య ఎడారులు, ఏవి కేవలం డేటా-పేదవి?
- **Translates to:** *Which districts are true medical deserts, and which are merely data-poor?*
- **Answer splits** the two groups cleanly with the investigate-first caveat.

### 5. Marathi — "how many" (count accuracy — the bug we fixed)
- **Say:** बिहारमध्ये किती जिल्हे खरे वैद्यकीय वाळवंट आहेत?
- **Translates to:** *How many districts in Bihar are actual medical deserts?*
- **Answer:** *"22 REAL medical deserts and 15 DATA-POOR districts"* — now uses true totals, not the
  example-list length (previously wrongly said 6).

### 6. English — "top 3 and why" (baseline, no translation)
- **Say:** Give me the top 3 districts to deploy a mobile maternal-health unit in Bihar and why.
- **Answer:** Saharsa (0.82/0.61), Madhepura (0.81/0.65), Bhagalpur (0.79/0.60) with reasons, plus
  the investigate-first list.

---

## Evaluation summary

| Dimension | Result |
|---|---|
| Translation fidelity (6 langs) | ✅ All faithful; none "answered" instead of translating (system/user role split holds) |
| Grounding | ✅ Every answer cites real Bihar districts with matching gap/confidence numbers |
| Two-signal honesty | ✅ REAL-vs-DATA-POOR separation preserved in all 6; data-poor never shown as confirmed |
| Count questions | ✅ Fixed — totals (22/15) now injected into context |
| ASR reliability | ⚠️ Free Google recognition is best-effort; failures now show a retry prompt, not silence |

**Two bugs found and fixed by this test pass:** (1) the "Ask" agent was calling the disabled
gemini endpoint; switched to llama-3.3-70b chat. (2) count questions returned the example-list
length; now grounded on true totals.

---

## 30-second voice clip for the video (suggested take)

1. **(0:00)** Bihar + district preselected. "Planners don't always type in English — so ask in your language."
2. **(0:04)** Pick **Hindi**, record: *बिहार में हमें मोबाइल मातृ स्वास्थ्य इकाई कहाँ भेजनी चाहिए?* → Stop.
3. **(0:10)** Point to **Heard (Hindi): … → English: Where should we send the mobile maternal health unit in Bihar?**
   "Transcribed and translated on Databricks."
4. **(0:14)** Click **Ask** → answer names Katihar/Saharsa/Madhepura as real deserts and flags
   Araria/Sitamarhi as investigate-first.
5. **(0:24)** "Same two-signal honesty — in any language." Cut.

> If a live mic clip is risky on camera, record the Hindi take 2–3× beforehand and keep the best;
> the "Heard → English" line makes it obvious the speech path worked.
