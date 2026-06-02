# Onboarding + Target-Recommendation Research

**Purpose:** Spec for how this weight-loss app should (1) collect info during onboarding and (2) recommend personalized targets (calories, protein/macros, steps, water, goal-weight range) for a **non-expert user who has body-image sensitivity, loves food, and tends to under-eat / restrict.**

**Design north star for THIS user:** She is *not* the typical "wants to crash diet" user. Her failure mode is under-eating, restriction, and self-criticism. So the product's job is the opposite of most apps: **give permission to eat enough, frame the numbers as a floor-to-aim-for (not a ceiling to fear), prioritize protein + food volume so she stays full, and never shame.** Most of the apps below are tuned for restrictors-who-want-to-restrict-harder; we deliberately invert their tone while reusing their math.

---

## TL;DR recommendations (read this first)

1. **Use Mifflin–St Jeor → TDEE → modest deficit.** Industry standard (MyFitnessPal, Noom-equivalent, Lose It!, MacroFactor all start here). Formula + multipliers in §3.
2. **Cap the deficit; never go aggressive by default.** Recommend losing **0.5–1% of body weight/week** (MacroFactor uses 0.25–1%). For our restricting user, **default to the gentle end (~0.5%/wk, a ~250–300 kcal deficit), not 1–2 lb/wk.**
3. **Hard calorie floor.** Never recommend below **1200 kcal (women) / 1500 kcal (men)** — this is MyFitnessPal's published floor and a widely-cited clinical minimum. For our user, set the *displayed* target comfortably above the floor and frame it as "eat *at least* this."
4. **Protein is the hero macro.** Target **1.6–2.2 g/kg body weight** (fat-loss + muscle-preservation consensus across MacroFactor and the research). Present protein as "this is how you keep your strength and stay full," not as a restriction.
5. **Goal weight = a RANGE, framed gently.** Compute a healthy-BMI range (BMI 18.5–24.9) but **lead with behavior/feeling, show the range as optional, and never auto-fill an aggressive low number.** Add BMI-sensitivity caveats. (§7)
6. **Steps: recommend ~7,000–8,000/day, not 10,000.** The 10k number is a 1960s marketing artifact; mortality benefit largely plateaus ~7,000. (§5)
7. **Water: ~half body-weight in ounces** (rule of thumb), reconciled with the National Academy of Medicine ~9 cups (women)/~13 cups (men) total fluids. (§6)
8. **Tone: kind, teaching, non-shaming; screen for eating disorders and route out if positive.** Noom explicitly asks about active eating disorders at intake; we should too. (§8)

---

## 1. What the leading apps collect, in what order

| App | Inputs collected (approx order) | Notes relevant to us |
|---|---|---|
| **MyFitnessPal** | sex → age → height → current weight → activity level → **goal** (lose/maintain/gain) → **weekly rate** (0.25/0.5/0.75/1.0 kg, capped at ~2 lb/wk) → goal weight | Goal weight is collected **but only used for "lbs remaining" reporting — it does NOT change the calorie math.** Calories come from Mifflin-St Jeor TDEE minus the deficit chosen by the weekly-rate slider. Good model for us: decouple goal weight from the daily target so the goal-weight number can't drive restriction. |
| **Noom** | goal weight → motivation/"why" → past diets → activity level → chronic illness (e.g. diabetes) → GLP-1 use → how busy daily life is → **active eating-disorder screen** | Long (15–30 min), psychology-heavy onboarding. **Explicitly asks if the user has an active eating disorder.** Computes a calorie "Weight Loss Zone" (a *range*, not a single number) sized to reach goal weight over ~16 weeks on average. Uses Harris-Benedict per their docs (we'll use Mifflin-St Jeor, which is more accurate). |
| **Lose It!** | account → height, weight, age → sex → weekly weight-loss goal → end goal weight | Calorie "Budget" = BMR × PAL (defaults to sedentary, PAL ≈ 1.45× BMR) minus the deficit for the chosen weekly rate. Simple, fast. |
| **MacroFactor** | brief Q-series to (a) rough-estimate expenditure and (b) set initial calorie + macro targets to goal/preferences; asks exercise type (none / endurance / resistance / both) and where in the protein range they want to sit (low/mid/high) | Best-in-class target logic. Initial estimate from a TDEE equation, then **adapts** calories from logged intake + weight-trend (estimates true expenditure over time). Recommends **0.25–1% bw/week** loss; **protein 1.6–2.2 g/kg bw (or 2.6–3.5 g/kg fat-free mass).** Protein scales with lean mass. |
| **Cal AI** | goal (lose/maintain/gain), activity level, diet preference (balanced/low-carb/keto/vegan/etc.); lets user set custom calorie + macro targets | Photo-based logging is the hook; targets are fairly standard goal+activity → calories+macros. Carries an explicit "not medical advice, consult a professional" disclaimer. |
| **WeightWatchers (Points)** | **25+ question personal assessment**: nutrition, activity, sleep, mindset; plus age/height/weight/sex-at-birth | Converts a metabolic-rate calc (age/height/weight/sex) into a **daily Points Budget (~20–30/day) + weekly Points (~28–49)** for flexibility ("a weekend treat or travel"). The **weekly buffer + ZeroPoint foods are the "you can still eat and enjoy life" mechanism** — useful pattern for our food-loving user. |
| **Zoe** | short quiz (instead of/alongside the gut + blood-fat test in paid tier) on health goals & questions; predicts blood-sugar/blood-fat responses | **Deliberately NO calorie counting.** Scores meals/quality, uses streaks + a friendly coach ("Ziggie"). Model for a *non-numeric, food-quality* framing if we want a low-restriction mode. |

**Pattern to copy:** Sex → age → height → current weight → activity → goal → *gentle* rate → (optional) goal weight, **plus** an early eating-disorder/relationship-with-food screen (Noom) and a "what matters to you" motivation question (Noom/WW) to anchor non-weight goals.

---

## 2. How they COMPUTE the recommendation (the shared backbone)

All the calorie-based apps do the same three steps; only the presentation and deficit size differ:

1. **BMR** via an equation (we use **Mifflin–St Jeor**; MyFitnessPal & most modern tools use it because it's more accurate than Harris-Benedict, which Noom/older tools use).
2. **TDEE** = BMR × activity multiplier (or BMR × PAL).
3. **Daily calorie target** = TDEE − deficit, where deficit is set by the chosen weekly loss rate, **clamped to a minimum floor.**

MacroFactor adds a 4th step we should eventually adopt: **adaptive recalculation** — compare logged intake vs. actual weight-trend change to infer true expenditure and nudge the target. (Phase 2; not required for v1.)

---

## 3. Formulas to cite (verified, copyable)

### Mifflin–St Jeor (BMR), metric
```
Men:   BMR = 10×weight(kg) + 6.25×height(cm) − 5×age(yr) + 5
Women: BMR = 10×weight(kg) + 6.25×height(cm) − 5×age(yr) − 161
```
(For "prefer not to say"/nonbinary, a reasonable default is the average of the two constants, i.e. use −78; state this is an estimate.)

### Activity multiplier → TDEE
```
TDEE = BMR × multiplier
Sedentary (little/no exercise)         × 1.2
Lightly active (1–3 days/wk)           × 1.375
Moderately active (3–5 days/wk)        × 1.55
Very active (6–7 days/wk)              × 1.725
Extra active (hard daily/physical job) × 1.9
```

### Calorie deficit by weekly rate (1 lb fat ≈ 3,500 kcal)
| Weekly loss | Daily deficit | Use for our user? |
|---|---|---|
| 0.25 lb (~0.11 kg) | ~125 kcal | Maintenance-ish / very gentle |
| **0.5 lb (~0.23 kg)** | **~250 kcal** | **DEFAULT for a restricting user** |
| 1.0 lb (~0.45 kg) | ~500 kcal | Standard moderate (cap for most) |
| 2.0 lb (~0.9 kg) | ~1,000 kcal | **Do NOT offer/auto-select** for this user |

**Rate guardrail:** keep loss within **0.5–1% of body weight/week**; above ~1.5%/wk the *proportion* of weight lost as muscle roughly doubles. For a restricting user, default to ~0.5%/wk.

### Protein for fat loss + muscle preservation
- **Target 1.6–2.2 g/kg body weight/day** (consensus; MacroFactor's coached default range).
- Evidence anchors: comparing ~1.0 vs ~2.3 g/kg in a deficit, the low-protein group lost ~1.6 kg muscle vs ~0.3 kg in high-protein; another trial found 1.6 and 2.4 g/kg both spared more lean mass than 0.8 g/kg, with **no extra benefit above ~1.6 g/kg.** So **1.6 g/kg is a defensible single default**; offer up to ~2.2 for resistance trainers.
- Alt basis if body-fat known: ~2.6–3.5 g/kg **fat-free mass.**

### Fat / carbs (after protein is set)
- Reasonable default macro split (MyFitnessPal default): **20% protein / 50% carbs / 30% fat**, then let protein-grams target override.
- Practical floor: **fat ≥ ~0.5 g/kg** for hormones; remainder of calories to carbs (carbs fuel activity + mood — important to *not* demonize for a restrictor).

### Healthy goal-weight RANGE (BMI 18.5–24.9)
```
weight(kg) = BMI × height(m)²
low  = 18.5 × height(m)²
high = 24.9 × height(m)²
```
Present as a **range**, default the suggested target nearer the **middle/upper** of the band (not the 18.5 floor), and show BMI caveats (§7).

### Water (rule of thumb)
- Common heuristic: **~½ body weight (lb) in ounces/day** (e.g., 150 lb → ~75 oz). A wider stated range is 0.5–1 oz per lb.
- Reconcile with **National Academy of Medicine adequate total fluid intake: ~9 cups (~72 oz) women, ~13 cups (~104 oz) men** (includes water from food/all beverages). Add for heat/exercise.
- **Recommendation:** show a friendly target around **½-body-weight-in-oz, but cap the displayed goal to a sane band (~64–100 oz)** and note food/coffee/tea count.

### Steps
- **Recommend ~7,000–8,000 steps/day**, not 10,000. "10,000" came from a 1960s Japanese pedometer brand name, not science.
- Evidence: all-cause mortality risk drops sharply up to **~7,000 steps (~−47%)**; benefits continue but with diminishing returns; older adults plateau ~6,000–8,000, younger ~8,000–10,000. Even ~4,000 beats sedentary.
- **For this user:** frame steps as "movement you enjoy," start from her current baseline + a small bump, not a fixed 10k wall.

---

## 4. Safety guardrails (must-implement)

1. **Calorie floor (hard clamp):** never display a target below **1200 kcal (women) / 1500 kcal (men).** These are MyFitnessPal's published floors and align with cited clinical minimums (below this, adequate micronutrients from food alone are "nearly impossible," and muscle loss + metabolic adaptation accelerate). If the math (TDEE − deficit) drops below the floor, **clamp to the floor and reduce the deficit/rate instead**, and tell the user.
2. **For a restricting user, floor + buffer:** consider showing a target a bit *above* the bare floor and label it "eat *at least* this much." Never reward under-eating in the UI (no "great, you ate 700 kcal!").
3. **Rate clamp:** cap at ≤1% bw/week by default; don't expose a 2 lb/wk option to this user.
4. **Goal-weight sanity check:** if a user enters a goal weight that would put them **below BMI 18.5**, do **not** accept it as a target. Gently explain the healthy range and offer the lowest *healthy* weight instead. Never recommend an unsafe goal weight.
5. **BMI sensitivity:** treat BMI as a rough screen, not truth (it ignores muscle/body-composition, age, ethnicity). Athletes/muscular users can read "overweight" while healthy. Always caveat (§7).
6. **Eating-disorder screen + route-out:** ask early (like Noom). If positive/at-risk, **switch to a no-numbers, behavior-only mode and surface help resources** (e.g., NEDA screening/helpline) rather than serving a calorie deficit. Apps without this are repeatedly linked to disordered-eating harm in the literature.
7. **Medical disclaimer** (like Cal AI): recommendations are estimates, not medical advice; encourage professional consult for medical conditions, pregnancy, GLP-1 use, etc.

---

## 5. "I don't know" defaults (so onboarding never blocks)

| Field | If user says "I don't know" → default |
|---|---|
| **Activity level** | **Sedentary (×1.2).** Safest under-estimate; if anything she'll be told to eat slightly less, so for a restrictor consider defaulting to **Lightly active (×1.375)** so the target isn't punitively low. Let her change it. |
| **Goal weight** | **Don't force it.** Offer "Not sure yet — focus on how I feel" and skip. Optionally show the healthy-BMI range as information only. (Mirrors MyFitnessPal decoupling goal weight from the math + Zoe's no-number approach.) |
| **Weekly rate** | **0.5%/wk (gentle, ~250 kcal deficit).** Never auto-pick aggressive. |
| **Protein preference (low/mid/high)** | **Mid → 1.6 g/kg.** |
| **Exercise type** | **"None/just daily life"** → still set protein at 1.6 g/kg for muscle preservation. |
| **Steps baseline** | If unknown, suggest **7,000** as a friendly target, or "start where you are + 1,000." |
| **Water** | **½ body weight in oz, clamped 64–100 oz.** |
| **Macro split** | **20% P / 50% C / 30% F**, then enforce protein grams. |

General rule: **every "I don't know" yields a safe, non-restrictive default and an easy way to edit later** — never a dead end, never the most aggressive option.

---

## 6. Screen-by-screen onboarding flow (with exact copy)

> Voice: warm, plain-language, second person, no jargon, no shame, teaching as we go. Numbers are framed as *fuel and floors*, not limits. Keep each screen to one idea.

**Screen 0 — Welcome / intent**
> "Hi, I'm so glad you're here. This isn't about eating less and less — it's about eating *enough* to feel good and lose weight in a way that lasts. I'll ask a few questions, then build you a starting plan you can always adjust."
- CTA: "Let's start"

**Screen 1 — Relationship-with-food / safety screen (early, like Noom)**
> "First, a gentle check-in so I can support you the right way."
- "How would you describe your relationship with eating right now?" (e.g., *I often eat less than I think I should* / *It's complicated* / *Pretty balanced*)
- "Have you ever been diagnosed with, or are you currently experiencing, an eating disorder?" (Yes / No / Prefer not to say)
- **If yes / at-risk:** switch to no-numbers mode + show resources: "Thank you for trusting me with that. Because your wellbeing comes first, I'll skip calorie numbers and focus on gentle, supportive habits. If you'd ever like extra support, the NEDA Helpline is here for you." (Provide link.)

**Screen 2 — Basics (the math inputs)**
> "A few basics so I can estimate how much energy your body uses. (You can change any of these later.)"
- Sex assigned at birth (with "prefer not to say" → averaged constant)
- Age
- Height
- Current weight
- Micro-copy under weight: "This is just a starting point for the math — not a judgment."

**Screen 3 — Activity**
> "How active is a typical week for you?" → Sedentary / Lightly / Moderately / Very / Extra (plain descriptions).
- "Not sure?" → defaults to Lightly active. Micro-copy: "No worries — I'll start with a gentle estimate and fine-tune as we go."

**Screen 4 — Your goal & pace (gentle by default)**
> "What feels right for you?" → Lose weight / Maintain / Build strength.
- If "Lose weight": **pace slider defaults to ~0.5%/week**, labeled in feelings not just numbers:
  > "Gentle & steady (recommended) — about ½ lb a week. You'll still eat plenty, and this protects your energy and muscle."
- Cap the slider at 1%/wk. Micro-copy: "Faster isn't better here — going too low on food usually backfires and costs you muscle."

**Screen 5 — Goal weight (optional, de-emphasized)**
> "Want to set a goal weight? Totally optional — many people do great just focusing on how they feel."
- Options: "Suggest a healthy range for me" / "I have one in mind" / "Skip for now."
- If "suggest": show the **BMI 18.5–24.9 range** with this framing:
  > "A weight in roughly **[low]–[high] lb** tends to be a healthy range for your height. This is a wide, flexible band — not a single 'right' number — and it doesn't account for muscle or build, so treat it as a guide, not a verdict."
- If user enters something **below BMI 18.5:** "I want to keep you safe, so I can't set a goal that low. The lowest healthy weight for your height is about **[low] lb** — want to use that, or keep things weight-neutral for now?"

**Screen 6 — The reveal: your starting plan (most important screen)**
Show targets as cards with one-line plain explanations:

> **Your daily fuel: ~[X] calories**
> "This is the amount that lets you lose weight *gently* while still eating enough to feel good. Think of it as a target to *reach*, not a limit to fear — eating too little is the thing that stalls progress."

> **Protein: ~[P] g/day**
> "Protein is your best friend right now — it keeps you full and protects your muscle while you lose fat. Hit this and you'll feel stronger, not depleted."

> **Carbs ~[C] g · Fat ~[F] g**
> "Carbs and fat aren't the enemy — they fuel your energy, hormones, and mood. There's room for the foods you love."

> **Movement: ~[7,000–8,000] steps**
> "You don't need 10,000 — that number was a marketing slogan. Around 7–8k a day gives you most of the health benefit. Start where you are."

> **Water: ~[W] oz**
> "A simple aim; tea, coffee, and water-rich foods all count."

- Footer: "These are smart estimates, not rules. I'll learn from you and adjust. None of this is medical advice."

**Screen 7 — The "you can keep eating and still lose" reassurance (the upsell, done kindly)**
Borrow WW's flexibility framing + volume-eating:
> "Here's the part most diets get wrong: **you don't have to eat tiny portions.** By leaning on protein and high-volume foods — big salads, fruit, veggies, lean proteins — you can fill your plate, feel full, and still be in a gentle deficit. One Penn State study found people ate 400+ fewer calories a day this way *without feeling hungrier.* We'll also keep a little weekly flexibility for treats and dinners out — enjoying food is part of the plan, not a failure."

**Screen 8 — Confirm & start**
> "Your plan's ready. Remember: this adjusts with you, and there's no 'failing' — just learning what works for your body. Let's go."

---

## 7. Goal weight & BMI: how to frame without triggering restriction

- **Lead with behavior and feeling; make weight optional and de-emphasized** (MyFitnessPal already decouples goal weight from the calorie math; Zoe drops the number entirely). Copy goal weight only into "progress/feel" context, **never** into the daily calorie target.
- **Always a RANGE, never a single number,** centered toward the middle/upper of healthy BMI, not the 18.5 floor.
- **State BMI's limits inline:** ignores muscle/body composition, age, ethnicity; athletes can be "overweight" by BMI yet healthy. Offer waist-to-height as a friendlier alt if you add one later.
- **Body-neutral language:** respect/accept the body as-is; avoid "ideal," "should weigh," before/after, or any number presented as a verdict.
- **Hard stop on sub-healthy goals** (BMI < 18.5) — explain kindly and offer the lowest healthy weight instead.

---

## 8. Tone & "kind, teaching, non-shaming" best practices

- **Screen for EDs early and route out** (Noom asks about active eating disorders at intake). Heavy weigh-ins + calorie counting can trigger disordered eating; people who use these apps for body-image (vs health) reasons show markedly more ED symptoms. So: detect, then switch to a no-numbers, supportive mode + resources.
- **Reframe numbers as fuel/floors, not limits.** For a restrictor, the risky message is "eat less"; ours is "eat *enough.*" Celebrate *hitting* protein and *reaching* (not undercutting) calories. **Never** congratulate large under-eating.
- **Behavior-first, weight-neutral wins** (Noom's CBT/ACT/mindfulness lessons; Zoe's quality scores + friendly coach "Ziggie"; intuitive-eating principles): praise consistency, energy, strength, mood — not just the scale.
- **Plain language, teach as you go** (Zoe's "complex science made simple"). One concept per screen.
- **Flexibility as a feature** (WW weekly Points buffer + ZeroPoint foods; volume eating): explicitly tell her she can enjoy food, eat big portions, and have treats. This is both the kind move *and* the retention/"upsell" move.
- **Avoid weight-bias language** entirely — it harms even when unintentional. No "good/bad foods," no "cheat," no "earn it."

---

## 9. Open / uncertain items (flagged)

- **Exact per-app deficit math** (e.g., precise kcal each app subtracts per rate) isn't all officially published; the 3,500-kcal-per-lb model is a teaching approximation, not biologically exact — fine for setting a *starting* target, but real adaptation varies (this is *why* MacroFactor's adaptive approach exists).
- **Noom uses Harris-Benedict** per its own docs; **we should use Mifflin–St Jeor** (more accurate, MyFitnessPal-standard). Don't copy Harris-Benedict.
- **Cal AI / Zoe internal target formulas** are not fully disclosed; treat their methods as directional (Cal AI ≈ standard goal+activity; Zoe ≈ deliberately no calories).
- **Water "½ body weight in oz"** is a popular rule of thumb, not a hard clinical standard; the NAM total-fluid figures are the more authoritative anchor. We reconcile by clamping the displayed goal.
- **WW Points→calories** isn't a public 1:1 mapping; we borrow the *flexibility pattern* (weekly buffer, zero-point foods), not the proprietary Points formula.
- Verify final clamped numbers in-app against a couple of real profiles before shipping (don't trust the spec blindly).

---

## Sources

- MyFitnessPal — How initial goals are calculated (inputs, Mifflin-St Jeor, goal weight only for reporting, 1200/1500 floors): https://support.myfitnesspal.com/hc/en-us/articles/360032625391-How-does-MyFitnessPal-calculate-my-initial-goals
- MyFitnessPal — Macro Calculator (default 20/50/30 split, protein by body weight): https://support.myfitnesspal.com/hc/en-us/articles/24763932864397-Macro-Calculator
- MyFitnessPal calorie-deficit setup & NHS guidance (weekly rate 0.25–1 kg): https://www.boltpharmacy.co.uk/guide/my-fitness-pal-calorie-deficit
- Noom — How Noom determines your Weight Loss Zone (range, Harris-Benedict, ~16 wks): https://www.noom.com/support/faqs/question-topics/food-logging/2016/08/how-does-noom-determine-my-weight-loss-zone/
- Noom — Dynamic Calorie Goals: https://www.noom.com/support/faqs/using-the-app/logging-and-tracking/food-and-water/2025/10/how-to-use-dynamic-calorie-goals/
- Noom review (onboarding questions incl. ED screen, GLP-1, psychology/CBT): https://millennialhawk.com/noom-review/ ; https://www.choosingtherapy.com/noom-review/
- MacroFactor — Algorithms & core philosophy (onboarding Qs, adaptive expenditure, protein by exercise/range): https://macrofactor.com/macrofactors-algorithms-and-core-philosophy/
- MacroFactor — Fat Loss handbook (0.25–1% bw/wk; 1.6–2.2 g/kg or 2.6–3.5 g/kg FFM): https://macrofactor.com/wp-content/uploads/2025/11/MacroFactor-Fat-Loss-Handbook.pdf
- Lose It! calorie budget (BMR × PAL ~1.45, sedentary default): https://www.itscheatdayeveryday.com/about-me/the-lose-it-app-and-counting-calories-to-lose-weight/
- Cal AI (goal/activity/diet inputs, custom targets, not-medical-advice disclaimer): https://www.calai.app/ ; https://apps.apple.com/us/app/cal-ai-calorie-tracker/id6480417616
- WeightWatchers — how Points work (25+ Q assessment; ~20–30 daily + ~28–49 weekly Points; metabolic calc): https://www.weightwatchers.com/us/how-it-works/points-program ; https://health.usnews.com/wellness/food/articles/breaking-down-the-weightwatchers-points-system
- Zoe — how it works (no calorie counting, quiz personalization, meal scoring, coach): https://zoe.com/how-it-works ; https://zoe.com/learn/zoe-2-0-science-made-simple
- Mifflin–St Jeor formula + activity multipliers: https://reference.medscape.com/calculator/846/mifflin-st-jeor-equation ; https://www.omnicalculator.com/health/bmr
- Protein g/kg for fat loss + muscle preservation (1.6–2.2/2.4; low vs high-protein muscle-loss study): https://www.boltpharmacy.co.uk/guide/protein-for-calorie-deficit ; https://examine.com/guides/protein-intake/
- Safe rate of loss 0.5–1% bw/wk; >1.5% doubles muscle-loss proportion: https://vivagenhealth.com/sustainable-weight-loss-rate/ ; https://drbabak.org/muscle-preservation-during-weight-loss/
- Natural bodybuilding contest-prep review (rate-of-loss + protein evidence): https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4033492/
- 1200/1500 kcal minimums & risks of undereating: https://www.precisionnutrition.com/1200-calorie-diet ; https://nutrola.app/en/blog/what-happens-if-you-only-eat-1200-calories
- Step counts — 10k myth, ~7,000 mortality benefit, age plateaus: https://www.nuhs.edu/debunking-the-10000-step-myth-figuring-out-what-actually-matters/ ; https://pmc.ncbi.nlm.nih.gov/articles/PMC9289978/ ; https://www.health.harvard.edu/blog/10000-steps-a-day-or-fewer-2019071117305
- Water intake rules of thumb + NAM adequate-intake figures: https://nutritionsource.hsph.harvard.edu/water/ ; https://www.medicinenet.com/how_much_water_to_drink_based_on_your_weight/article.htm ; https://www.mayoclinic.org/healthy-lifestyle/nutrition-and-healthy-eating/in-depth/water/art-20044256
- Healthy weight range / BMI limitations for muscular/athletic people: https://my.clevelandclinic.org/health/articles/9464-body-mass-index-bmi ; https://www.medicalnewstoday.com/articles/323446
- Apps & disordered eating risk; screen within apps: https://www.center4research.org/fitness-tracking-apps-eating-disorders/ ; https://www.sciencedirect.com/science/article/pii/S1469029225000895 ; https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5658641/
- Eating-disorder screening tool / resources (route-out): https://www.nationaleatingdisorders.org/screening-tool/
- Goal-weight framing / body-neutral / weight-neutral (intuitive eating): https://nutritionsource.hsph.harvard.edu/intuitive-eating/ ; https://withinhealth.com/learn/articles/6-tips-for-redirecting-and-deflecting-discussions-about-weight-and-diet
- Volume eating / satiety (Penn State 400+ kcal finding): https://kaynutrition.com/volume-eating/ ; https://www.seasonhealth.com/blog/high-volume-low-calorie-foods
- Undereating / metabolic adaptation / reverse dieting: https://macrofactor.com/reverse-dieting/ ; https://www.nutrisense.io/blog/can-undereating-cause-weight-gain
