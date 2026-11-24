# A pixel character from a photo (G8)

How the custom character is made, what OpenAI's documentation did and did not confirm
about the call, and what is still unverified. Read on 2026-11-22. The call was first made
for real on 2026-11-23, on generated faces: what that confirmed, and what it did not, is in
"The evaluation" at the end and in EVAL_REPORT 23.

## Decisions already made (by the owner)

1. Version 1 makes ONE character image per person, no per-mood frames. Wherever the two
   built-in characters swap frames by mood or blink, a custom character shows its one image.
2. The photo is sent to OpenAI only after a consent step that says so in plain words, and
   the photo is never stored. Only the finished character PNG is kept.
3. With no OpenAI key, a refusal, a network failure or a bad response, the flow continues
   with a built-in character. The step is always skippable.
4. The two existing users keep their built-in characters. Anyone can make a custom one
   later from Settings.

## Sources

- Image generation guide: <https://developers.openai.com/api/docs/guides/image-generation>
- API reference, "Create image edit": <https://developers.openai.com/api/reference/resources/images/methods/edit>
- Model pages: <https://developers.openai.com/api/docs/models/gpt-image-2.6-flare>,
  <https://developers.openai.com/api/docs/models/gpt-image-2.6-sunburst>
- Error codes guide: <https://developers.openai.com/api/docs/guides/error-codes>

The pages were read through a fetch tool that summarises long pages, so a quotation below
is a quotation of that reading. The live call is the check that matters; it was run on
2026-11-23 (EVAL_REPORT 23).

## The request: `POST https://api.openai.com/v1/images/edits`

| What | Confirmed by | What the code sends |
|---|---|---|
| Endpoint, `Authorization: Bearer <key>` | guide curl examples, reference | as documented |
| Both 2.6 models support `v1/images/edits`; neither supports `v1/responses` | both model pages | the Image API, not the Responses tool |
| Body format | The reference's formal schema is **JSON only** (`images: [{image_url \| file_id}]`, `image_url` may be a base64 data URL). **Multipart is shown only in the guide's curl examples.** | multipart (`AvatarGenerator.buildRequest`) |
| Image field name | guide: `-F 'image=@kitchen.webp;type=image/webp'` with `gpt-image-2.6-flare` (one image); `-F "image[]=@..."` repeated (several) | one part named `image`, `filename="photo.jpg"`, `Content-Type: image/jpeg` |
| `model` | reference: default `gpt-image-2.6-sunburst`; ids `gpt-image-2.6-flare`, `gpt-image-2.6-sunburst` | `AIConfig.avatarImage.model` = `gpt-image-2.6-flare` (NOT chosen by measurement) |
| `prompt` | reference: required, 1 to 32,000 characters | `AvatarGenerator.prompt`, version `avatar-v1` |
| `background` | reference: `transparent` \| `opaque` \| `auto` (default `auto`); "When using `transparent`, set the output format to `png` or `webp`" | `transparent` |
| `output_format` | reference: `png` (default) \| `webp` \| `jpeg` \| `gif` \| `svg`; the edit endpoint does not do SVG | `png` |
| `size` | reference: `1024x1024`, `1536x1024`, `1024x1536`, `auto`, and custom sizes (multiples of 16, aspect 1:3 to 3:1) | `1024x1024` |
| `quality` | reference: `low` \| `medium` \| `high` \| `auto` (default `auto`); guide: Sunburst and Flare in 2.6 and 2.5 also take `xhigh` and `max` | `medium` (NOT chosen by measurement) |
| `n` | reference: 1 to 10, default 1 | not sent (the default is the one image wanted) |
| `moderation` | reference: `auto` (default) \| `low` | not sent |
| `input_fidelity` | reference: `high`/`low` on `gpt-image-1.5`; "For `gpt-image-2`, omit this parameter". **Not stated for the 2.6 models.** | not sent |
| `safety_identifier` | reference: optional, recommended | not sent (it would be one more thing about the person leaving the device) |

### Not confirmed by the documentation

- **Transparent background on the 2.6 models.** The reference names
  `gpt-image-2.5-sunburst` / `-flare` as supporting `transparent` and says it is in preview
  for `gpt-image-2`; it says "available for supported GPT Image models" and does not name
  2.6. The guide's sentence on transparency names no model. If a 2.6 model rejects
  `background=transparent`, the call fails with an HTTP error; if it accepts it and paints
  a background anyway, the image fails validation. Either way the person gets a built-in
  character, and the `Avatar` evaluation's `transparent_top_corners` score will show it.
- **Whether `background`, `output_format` and `size` are accepted as multipart fields.** They
  are documented parameters of the endpoint, but the guide's multipart examples use only
  `model`, `prompt`, `quality`, `image`, `mask` and `markup`.
- **The HTTP status of a moderation block.** Not stated. The code keys on `error.code`,
  not on the status.
- **Limits on the input image.** The guide states "less than 50MB" for an image and its
  mask; formats are not listed for the 2.6 models. The app uploads a JPEG of at most
  1024 px on its longest side, far under any stated limit.
- **A per-image price.** Neither model page has one; cost is tokens at the listed rates.

Every wire name is a constant in `AvatarGenerator.Wire`, and the request values are the
one `AIConfig.avatarImage` setting, so a correction is a one-line change. If multipart
turns out to be wrong for 2.6, the JSON body (`images: [{"image_url": "data:image/jpeg;base64,..."}]`)
is the documented alternative.

## The response

- `data[0].b64_json`: the image, base64. "Returned by default for GPT image models"; they
  do not support `url` output.
- `usage` (optional): `input_tokens`, `input_tokens_details.{image_tokens,text_tokens}`,
  `output_tokens`, `total_tokens`, `output_tokens_details.{image_tokens,text_tokens}`.
- Also `created`, `background`, `output_format`, `quality`, `size`. There is no `model`
  field in the documented response, so usage is reported under the model that was requested.

Usage is reported through `AIRuntime.report` (input and output tokens) and kept in full on
`AvatarGenerator.Character.usage`, because image input and text input are priced apart.

## Errors, moderation and refusal

- Error body: `{ "error": { "message", "type", "code", "param" } }` (the error codes guide
  names the fields; it shows no full example).
- A moderation block: `error.code = "moderation_blocked"`, usually with
  `error.type = "image_generation_user_error"`, and optionally
  `error.moderation_details.moderation_stage` = `input` \| `output` \| `unknown`. The guide:
  do not retry these without changing the prompt or the input image, and use `error.code`
  as the stable discriminator. The app maps it to `Failure.refused`, never retries it, and
  shows a generic message.
- Retry: the guide says to retry transient rate-limit and server errors with backoff, never
  quota or user errors. The app retries once on 429 (unless `insufficient_quota`), 500 and 503.
- "Complex prompts may take up to 2 minutes to process": the request timeout is 180 s, and
  the UI says it usually takes under half a minute (measured: 15 to 21 s on `sunburst`, EVAL_REPORT 23, 27) and lets the person cancel or move on.

## Price (list, per million tokens, both 2.6 models, from the model pages)

Text input $5, image input $8, image output $30 (cached input rates apply only to the
Responses tool, not to `/v1/images/edits`). These are in `Graders.imageRates` for the
evaluation's `cost_usd` score. What one character actually costs has to be measured.

## The style the prompt asks for

Taken from the two hand-made characters (`PixelVictoria`, `PixelBryan` in
`Victoria/Features/Companion/PixelCompanion.swift`: 20x24-cell grids, 13 palette
entries each) and the generated `alejandro_base` asset:

- a head-and-shoulders bust of one person, facing straight ahead, centred; the head and
  hair fill about the top two thirds, the shoulders are cut off by the bottom edge;
- a coarse grid (about 32x32 cells on a 1024 output), flat single-colour cells, no
  anti-aliasing, gradients, dithering or texture;
- 12 to 16 colours: skin and one shadow tone, hair and one highlight, a top and one shadow;
- no outline; shapes are blocks of colour;
- dark two-cell pupils with one white catch-light, short solid brows, a small closed smile;
- what makes the person recognisable (hair, skin tone, facial hair, glasses, one or two
  accessories) reduced to a few cells; a plain top with no logo or lettering;
- a fully transparent background, nothing else in the picture.

`docs/pixel-art-refs/` holds reference PHOTOS for other characters, not pixel art; the
style description above comes from the art in the code and the asset catalog.

## What the app checks before it shows a character

`AvatarImage.validateCharacterPNG`: PNG signature and decodable, square, has an alpha
channel, and at least 2% of pixels fully transparent (a painted backdrop leaves none).
Anything else is a typed `AvatarGenerator.Failure` and the built-in character stands.

## Where the character is kept

- `UserProfile.customAvatarPNG` (optional, external storage, so it is a CloudKit asset),
  with `companionAvatarRaw = "custom"`. **The CloudKit Production schema needs a deploy by
  the owner** before a TestFlight build that carries this field.
- A copy of at most 320 px in the App Group container (`WidgetAvatarFile`), next to the
  widget snapshot, which carries the SHA-256 of that file. The widget draws the file only
  when the digest matches, and a neutral mark otherwise.
- The photo: nowhere. It is held in memory by `AvatarCreationModel` until a character is
  accepted or declined, and the upload is re-encoded from pixels, without the camera's
  EXIF block (location, device).

## The evaluation (run twice on 2026-11-23, EVAL_REPORT 23)

`Evals/run.sh Avatar "openai:gpt-image-2.6-flare@low,openai:gpt-image-2.6-flare@medium,openai:gpt-image-2.6-sunburst@medium" 3`

The `@suffix` is the image quality. The cases are the photos in
`Evals/datasets/avatar/photos/` (git-ignored; synthetic or consented only). Scores:
`decodable`, `square_1024`, `has_alpha`, `transparent_top_corners`, `transparent_corners`,
`transparent_share`, `distinct_colours`, `is_pixel_art`, `generation_latency_ms`, the token
counts and `cost_usd`. Each image is saved under the run's `avatars/` folder (git-ignored)
for the owner's rating of likeness and fit, which no code measures.

`Evals/regrade-avatars.sh Evals/runs/<run>` grades a past run's saved characters again
with the graders as they are now, at no cost, and writes `<run>/regrade-avatar.json`.

**Confirmed live, on three generated faces, 18 images:** a transparent background on both
2.6 models; the multipart request as built; the `usage` block and its split of text and
image input; 1024 x 1024 PNG output. Per character: $0.035 at low quality and $0.054 at
medium (tokens at the published rates), about 8 to 10 seconds on `flare` and 20 on
`sunburst`.

**What the models actually return, and the code must not assume otherwise:** no pixel is
at alpha 255. The body of a character is at 253 or 254, and the cleared background has
stray pixels at alpha 1 and 2. The graders treat alpha at or under 8 as clear and at or
over 250 as solid. The app keeps the image as returned.

`Graders.pixelArtColourLimit` is 58 colours after 4-bit quantisation: pixel characters
counted 24 to 45 and photographs 72 to 81, on thirteen images. A small set.

**Still not confirmed:** a real photograph of any kind, a refusal and its HTTP status, and
the flow in the app producing a live image.