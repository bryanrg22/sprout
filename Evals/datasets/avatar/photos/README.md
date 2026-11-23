# Photos for the `Avatar` evaluation

The cases of `Evals/run.sh Avatar ...` are the image files in this folder
(`.jpg`, `.jpeg`, `.png`, `.heic`, `.webp`), one case per file, the file name (without its
extension) as the case id.

**Only two kinds of photo go here:**

1. **Synthetic** faces: generated images of people who do not exist.
2. **Consented** photos: a real person who has agreed, knowing that the photo is uploaded
   to OpenAI's image API by the evaluation, and that the pixel character made from it is
   saved on this machine under `Evals/runs/<run>/avatars/`.

Never a photo taken from the web, a public figure, or anyone who has not been asked.

**Nothing in this folder is committed.** `.gitignore` excludes every file here except this
README, and excludes the generated characters under `Evals/runs/*/avatars/`. The repository
is public; a face does not belong in it. Keep the set fixed between runs you want to
compare (same files, same names), since a result is only comparable on the same photos.

A useful set covers what the prompt has to get right: different hair lengths and colours,
skin tones, glasses, facial hair, a hat, a busy background, a face that is not centred,
and a photo with two people in it (the prompt asks for one).

What the code grades, per image: decodable, square 1024, alpha channel, transparent
corners, share of transparent pixels, number of distinct colours after quantisation (is it
pixel art), latency, tokens and list-price cost. The image models return "solid" at alpha
253 or 254 and leave traces of alpha 1 and 2 in the background, so the graders count
alpha at or over 250 as solid and at or under 8 as clear (EVAL_REPORT 23). After a grader
changes, `Evals/regrade-avatars.sh <run>` grades a past run's saved images again for free. What it does not grade: likeness, and fit
with the two existing characters. Those are the owner's own rating of the saved images.
