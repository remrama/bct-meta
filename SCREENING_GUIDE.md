# Screening guide

How to install ASReview and screen the BCT meta-analysis search results, for both reviewers.

## What we're looking for

Studies that measured **Breath Counting Task (BCT) accuracy** and report either (a) a correlation
between BCT accuracy and a mindfulness, wellbeing, or executive-function measure, or (b) BCT
accuracy before and after an intervention, with a comparison group.

The BCT (Levinson et al., 2014): participants attend to their breathing and press one key on
breaths 1–8 and a different key on breath 9, then start again. The score is the share of cycles
counted correctly. Close variants (a different count length, mouse instead of keys) count too.
The MBAS (bell-probe questions during meditation) and MBE tasks do **not**.

## 1. Set up

### Install (once)

1. Install git (<https://git-scm.com/downloads>) and uv
   (<https://docs.astral.sh/uv/getting-started/installation/>).
2. Open a terminal: **Terminal** on macOS, **PowerShell** on Windows.
3. Go to the folder where you want the project, then download it:

   ```sh
   cd ~/Documents
   git clone https://github.com/remrama/bct-meta.git
   ```

### Start ASReview (every session)

1. Open a terminal and go into the project folder:

   ```sh
   cd ~/Documents/bct-meta
   git pull
   uv run asreview lab
   ```

2. When you're done for the session, go back to the terminal and press `Ctrl+C` to quit.

## 2. Calibration round (40 records, about 20 minutes)

1. Create a new project named `calibration_<your initials>` using
   `derivatives/search/calibration_set.csv`. Keep the default model.
2. Label all 40 records using the rules in §4.
3. Export (§5) and send the export to Remy. We then go through the disagreements together and
   clarify the rules if needed. Rule changes are logged at the bottom of this file.

## 3. Full screen (1,270 records, about 3–4 hours; sessions can be split)

1. Create a new project named `screening_<your initials>` using
   `derivatives/search/candidates_asreview.csv`. Eight records arrive already labelled relevant:
   these are known BCT studies, used as the model's starting point. Leave them as they are.
2. Keep the default model and settings.
3. **Label every record.** If ASReview suggests stopping, ignore it and continue until no
   unlabelled records are left. Progress saves automatically, so you can close and come back.

## 4. Rules

Decide from the title and abstract only. Don't look up the full text. **If unsure, mark it
Relevant.**

**Relevant** if any of these apply:
- It mentions breath counting as a task, measure, or score ("breath counting task",
  "breath count accuracy", "BCT").
- It's an empirical study in humans of mindfulness, meditation, mind wandering, or attention
  (including training and intervention studies), and the abstract doesn't rule out a
  breath-counting measure. Many studies mention the BCT only in their Methods section.
- Breath counting appears only as the practice ("participants practised counting breaths"). Full
  text decides whether accuracy was scored.
- You can't read the language. Mark Relevant and add the note `language`.

Theses, conference papers, and preprints count the same as journal articles.

**Irrelevant** if any of these apply:
- It isn't empirical, or has no new data: a review, meta-analysis, commentary, editorial,
  theoretical paper, book chapter, or study protocol.
- "Breath count" is used in a medical or physiological sense: respiratory-rate counting,
  single-breath count test, ventilation, pneumonia, apnoea, monitoring devices.
- The sample isn't human.
- The only breath-attention measure is the MBAS or MBE.
- The topic is clearly unrelated to mindfulness, meditation, attention, or breathing.

For anything borderline, add a short note (`unsure`, `MBAS?`, `language`). One word is enough.

## 5. Export and hand in

When you've finished (do this for the calibration round as well):

1. In the project, export the **dataset** as CSV, with all three groups ticked: Relevant,
   Irrelevant, and Not seen. Name it `ta_<initials>.csv` (calibration: `calibration_<initials>.csv`).
2. Also export the **project** file: `ta_<initials>.asreview`.
3. Send both files to Remy. Don't commit, share, or discuss them until both reviewers have
   handed in.

## 6. What happens next (for information)

- The exports are committed to `sourcedata/screening/`, and title/abstract agreement (Cohen's κ)
  is computed.
- Every record that **either** reviewer marked Relevant goes to full-text screening. There is
  nothing to resolve at the title/abstract stage.
- Full text: both reviewers again, independently. Each excluded study gets the first reason
  that applies:
  1. `not_empirical`: no new data.
  2. `no_bct`: BCT accuracy wasn't measured. This includes MBAS/MBE only, and breath counting
     used only as a practice.
  3. `no_eligible_analysis`: BCT accuracy was measured, but there's no correlation with a
     mindfulness, wellbeing, or EF measure, and no pre/post comparison with a comparison group.
  4. `no_data`: the needed numbers aren't reported.

  Disagreements are settled by discussion. If two papers share participants, that is noted, not
  excluded.

## Rule changes

| Date | Change | Why |
|---|---|---|
|  |  |  |
