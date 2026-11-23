# Chat standards: what an AI chat screen has to get right, and where Sprout stands

The coach chat is the part of Sprout people use most, and a chat with a model fails in
more ways than a screen that reads the user's own data. This document records what the
standard is for each of those ways (Apple's documentation, the two providers' API
references, and how established chat products behave), what Sprout's chat did when this
was written, what was measured, and what is still open.

- **Date:** 2026-11-22 to 2026-11-23. **Branch:** `bryan/chat-robustness`, from `b22f23f`.
- **"Before"** means the chat at `b22f23f` plus the measuring probe (`d02aea7`). Every
  `file:line` in the "Sprout before" columns is a line of that tree.
- **Words used:** *verified* = run, with the output in hand; *read* = the code path or the
  source was read, not run; *open* = not done. Sources were fetched on the dates above;
  several vendor pages have changed since earlier versions, and that is said where it matters.
- Apple pages are cited by their public URL. Nothing here is quoted at length: each claim is
  a paraphrase followed by the page it comes from.

## 1. Long transcripts

### The standard

- **Fetch a window, not the table.** SwiftData's `FetchDescriptor` has `fetchLimit` (the
  most rows a fetch returns; with no limit it returns all of them) and `fetchOffset`, which
  together give a page
  ([fetchLimit](https://developer.apple.com/documentation/swiftdata/fetchdescriptor/fetchlimit),
  [fetchOffset](https://developer.apple.com/documentation/swiftdata/fetchdescriptor/fetchoffset)).
  A bare `@Query` fetches every instance of the model
  ([Query](https://developer.apple.com/documentation/swiftdata/query)); Apple's own sample
  passes a descriptor with a limit to `@Query` when it wants fewer
  ([FetchDescriptor](https://developer.apple.com/documentation/swiftdata/fetchdescriptor)).
- **Chat products page.** Stream's SwiftUI message list loads a page of 25 and the next
  chunk when the reader gets near the end of what is loaded
  ([Stream, message list](https://getstream.io/chat/docs/sdk/ios/swiftui/chat-channel-components/message-list/));
  its API pages older messages by "older than this id"
  ([Stream, pagination](https://getstream.io/chat/docs/ios-swift/channel_pagination/)), a
  cursor, not an offset. Sendbird's collection has `hasPrevious` / `loadPrevious` for the
  same thing
  ([Sendbird, message collection](https://sendbird.com/docs/chat/sdk/v4/ios/local-caching/using-message-collection/message-collection)).
  Discord moved its chat list to a native list with view recycling for the same reason
  ([Discord, 2025](https://discord.com/blog/supercharging-discord-mobile-our-journey-to-a-faster-app)).
- **Start at the newest message without scrolling there.** `defaultScrollAnchor(_:)`
  (iOS 17) sets where a scroll view starts and how it treats changes of content size
  ([defaultScrollAnchor](https://developer.apple.com/documentation/swiftui/view/defaultscrollanchor(_:))).
- **Positioning.** `scrollPosition(id:anchor:)` (iOS 17) and the `ScrollPosition` type
  (iOS 18: `scrollTo(edge:)`, `scrollTo(id:anchor:)`, `scrollTo(y:)`, `isPositionedByUser`)
  bind the position; SwiftUI tries to keep a bound position stable when content changes,
  and with lazy stacks the layout has to be marked with `scrollTargetLayout()`
  ([scrollPosition](https://developer.apple.com/documentation/swiftui/view/scrollposition(id:anchor:)),
  [ScrollPosition](https://developer.apple.com/documentation/swiftui/scrollposition),
  [scrollTargetLayout](https://developer.apple.com/documentation/swiftui/view/scrolltargetlayout(isenabled:)),
  [WWDC23 "Beyond scroll views"](https://developer.apple.com/videos/play/wwdc2023/10159/)).
  `onScrollGeometryChange` (iOS 18) reports offsets and sizes; Apple warns against updating
  large parts of the app from it
  ([onScrollGeometryChange](https://developer.apple.com/documentation/swiftui/view/onscrollgeometrychange(for:of:action:))).
- **Lazy or not.** Apple's guidance is to start with plain stacks and go lazy after
  profiling, because lazy stacks trade some layout correctness for speed
  ([Creating performant scrollable stacks](https://developer.apple.com/documentation/swiftui/creating-performant-scrollable-stacks)).
  A lazy stack estimates the height of rows it has not laid out, so a jump to a far row
  has to instantiate and measure what is in between
  ([Fatbobman, List or LazyVStack](https://fatbobman.com/en/posts/list-or-lazyvstack/)).
  Whether a lazy stack frees rows that scrolled away is version-dependent and not something
  Apple states
  ([forum thread 775204](https://developer.apple.com/forums/thread/775204)).
- **Prepending is the hard part.** A scroll view keeps its offset when rows are inserted
  above the visible ones, so the content jumps. An Apple engineer's answer is
  `scrollPosition(id:)` with `scrollTargetLayout()`; in the same thread developers report
  that multi-row prepends still jump, and describe the flipped-scroll-view workaround
  ([forum thread 731271](https://developer.apple.com/forums/thread/731271)). Stream notes
  that a lazy stack can still be sizing the newest rows as a scroll lands
  ([stream-chat-swiftui #1675](https://github.com/GetStream/stream-chat-swiftui/pull/1675)).
- **Jump to latest.** Stream ships a scroll-to-bottom button in both its SDKs
  ([Stream UIKit, message list](https://getstream.io/chat/docs/sdk/ios/uikit/components/message-list/)).
  No vendor documentation was found for ChatGPT's, Slack's or Discord's equivalent; they
  exist in the products, and that is observation, not a source.

### What Sprout does now

`ChatTranscript` fetches the newest 40 messages with `fetchLimit` (41 are asked for, only
to learn whether anything older exists), the page before the oldest loaded message when
the reader gets within 240 pt of the top (cursor: "created at or before the oldest loaded
timestamp", widened by the rows that share that timestamp, so rows with equal timestamps
are neither lost nor doubled), and only what is newer than the newest loaded row when a
message arrives. The arithmetic is `ChatWindow`, a pure type with 21 tests. The rows on
screen are value copies (`ChatRow`), so a deleted message cannot be read after the store
has let go of it.

The list is a `LazyVStack` in a `ScrollView` with `defaultScrollAnchor(.bottom)` (opens at
the newest message with no programmatic scroll), a `ScrollPosition(idType: UUID.self)`
over `scrollTargetLayout()`, a "Load earlier messages" row that is also a button, a
"Beginning of your conversation" marker, and a jump-to-latest button with a count of
messages that arrived while the reader was further up.

### Keeping the position when a page is prepended: what was tried, with numbers

Measured with a UI test that scrolls to the top of the first page with real swipes, lets
the scroll come to rest, taps "Load earlier messages", and compares where the top bubble
is before and after (iPhone 17 Pro simulator, iOS 26.4, 201-message seeded conversation).
0 pt is the goal.

| Approach | Top bubble moved by |
|---|---|
| `ScrollPosition(edge:)`, then `scrollTo(y: oldOffset + growth)` when the content height changes | off screen (a full page) |
| `ScrollPosition(edge:)`, then `scrollTo(id: anchor, anchor:)` with an anchor computed to restore the row's distance from the top, in the same update as the insert | 329 pt |
| KVO on the backing `UIScrollView.contentSize`, moving `contentOffset` by the growth | broke the layout (content shifted sideways and past the end): SwiftUI and UIKit fought over the offset |
| A plain `VStack` (exact sizes) with `ScrollPosition(idType:)` | off screen; also slower to open (540–650 ms vs 360–440 ms) and 75 MB vs 44 MB |
| **`LazyVStack` + `ScrollPosition(idType:)` + `scrollTargetLayout()`, nothing else** | **−31, +156, −7 pt on three successive pages; −6, +173, +5 and −21, +163, 0 on two more runs** |
| The same, plus an explicit `scrollTo(y:)` correction once the held row had been laid out again | oscillated between two positions for four frames, ended 16–43 pt off |

So Sprout ships the last-but-one row: identity-based position, nothing added. Over three
runs of three page loads each, from rest, the top bubble moved 0 to 31 pt on six loads and
156 to 173 pt on the other three (the second page of each run): it stays on screen every
time, and it is not pixel-stable. The cause is the one Apple's
performance article names: a lazy stack does not know the height of the 40 rows it has
just been given until it lays them out, and it positions the row being held from an
estimate. The corrections fail for the same reason from the other side: an explicit
scroll in the same update as the insert is computed from that estimate too, and an explicit
scroll afterwards replaces the identity-based position with a point, which the next
layout pass then moves.

While the reader is scrolling (the usual way to reach older messages) pages load ahead of
the finger and the shift is inside the motion. A UI test swipes from the newest message
of a 201-message conversation to "Beginning of your conversation" through four page loads
without stalling (14 swipes).

**Open:** exact position on prepend. The two routes that would give it are a
`UICollectionView`-backed list (cell sizes are known before insertion, and UIKit lets the
offset be moved in the same layout pass) or a flipped scroll view (older messages are
appended at the far end, which never moves the viewport). The flipped view was not tried
because the input bar is a bottom safe-area inset, and in a flipped scroll view that inset
lands at the wrong end.

A long jump to the bottom of a lazy stack can also land short for the same reason
(measured: about 100 pt short from five pages up), so "jump to latest" scrolls, and 0.4 s
later finishes the scroll if it is not at the end and the reader has not moved.

## 2. Selecting text

### The standard

- **SwiftUI `Text` cannot select a range on the iOS versions Sprout supports.** Apple's
  page for `textSelection(_:)` says that on iOS 26 and earlier the menu items it adds act on
  the entire contents of the `Text`; range selection with handles is described for iOS 27
  and later, and for macOS
  ([textSelection](https://developer.apple.com/documentation/swiftui/view/textselection(_:))).
  The page changed with iOS 27; older write-ups that say "iOS can only select everything"
  describe the versions Sprout targets (18 and 26).
- **Range selection therefore means a `UITextView`.** No Apple sentence says this in so many
  words; it follows from the line above and from `UITextView.isSelectable`
  ([isSelectable](https://developer.apple.com/documentation/uikit/uitextview/isselectable)).
  A text view is sized inside SwiftUI with `sizeThatFits(_:uiView:context:)` (iOS 16)
  ([sizeThatFits](https://developer.apple.com/documentation/swiftui/uiviewrepresentable/sizethatfits(_:uiview:context:))).
  SwiftUI's `TextSelection` type (iOS 18) is for `TextField` and `TextEditor`, not `Text`
  ([TextSelection](https://developer.apple.com/documentation/swiftui/textselection)).
- **The edit menu is extended, not replaced.** `textView(_:editMenuForTextIn:suggestedActions:)`
  (iOS 16; marked deprecated in the iOS 27 SDK) returns the system actions plus the app's own
  ([UITextViewDelegate](https://developer.apple.com/documentation/uikit/uitextviewdelegate/textview(_:editmenufortextin:suggestedactions:)),
  [UIEditMenuInteraction](https://developer.apple.com/documentation/uikit/uieditmenuinteraction)).
  The HIG asks for custom commands to sit near the related system ones, and for people to be
  able to select and copy non-editable text
  ([HIG, edit menus](https://developer.apple.com/design/human-interface-guidelines/edit-menus)).
- **One menu per item.** The HIG says to give an item either a context menu or an edit
  menu, not both ([HIG, context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus)).
  That decides the design: a reply whose text is selectable cannot also have a long-press
  context menu.
- **What the products do.** ChatGPT's iOS release notes of 28 February 2025 added
  long-press to select text and moved the message actions to be always visible under the
  message (as reproduced by
  [applech2](https://applech2.com/archives/20250306-chatgpt-for-ios-support-long-press-to-select.html);
  OpenAI's own help page describes the Android app:
  [help.openai.com 8142208](https://help.openai.com/en/articles/8142208)). No source was
  found for how Claude's iOS app does it.
- **Streaming and selection.** No source was found for the claim that re-setting a text
  view's attributed text clears its selection. It is how UIKit behaves in this app (the
  representable only assigns the text when it changed, for that reason), but that is
  practice, not a citation.

### What Sprout does now, exactly

- **A coach reply** (once it has finished typing itself out) is one `UITextView`
  (`SelectableMarkdownText`). Long-press or double-tap selects a word; the handles extend
  the selection across the whole reply, including across paragraphs, list items and
  headings. The edit menu is the system's, with **Ask about this** added in front.
  Copy writes readable text: a soft line break is a line break, a list marker is followed
  by a space, a rule is `---`.
- **What cannot be selected:** the user's own messages (they have a context menu with Copy
  instead, per the one-menu rule); a reply during the 1.1 s it is typing itself out; a
  selection cannot span two messages; the settled confirm cards and the failure row are not
  selectable.
- **Markdown and look.** The same block parser as before feeds an attributed string:
  paragraphs 6 pt apart, headings in the headline font, bullets and numbers in the accent
  colour with a hanging indent, a hairline rule, bold / italic / code / strikethrough /
  links. A unit test lays the same five messages out both ways (SwiftUI and the text view)
  and requires the heights to agree within 1.5 pt (measured: equal for plain paragraphs,
  1 pt apart with a heading, 0.3 pt with a rule), so the bubble does not jump when a reply
  settles from the typing animation into the text view.
- **Two things TextKit does differently from SwiftUI's `Text`, both found by measuring.**
  It puts the font's leading under the last line of every paragraph (1.7 pt at the default
  size), which made every bubble taller; the gap between blocks and the bottom of the view
  give it back. And a text view that cannot scroll draws only the lines that fit its text
  container: the first attempt at giving that leading back shortened the view itself, and
  every reply whose last line wrapped lost that line (seen in a screenshot; now a test).

## 3. Message actions

### The standard

- A context menu's items must also be reachable some other way, unavailable items are
  hidden rather than dimmed, and destructive items go last
  ([HIG, context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus)).
- ChatGPT keeps copy, read aloud and share in a row under the response with an overflow
  menu ([help.openai.com 8142208](https://help.openai.com/en/articles/8142208)), offers
  stop and regenerate
  ([help.openai.com 7996703](https://help.openai.com/en/articles/7996703-troubleshooting-chatgpt-error-messages)),
  and thumbs-down feedback ([help.openai.com 6783457](https://help.openai.com/en/articles/6783457-what-is-chatgpt)).
  Quoting a selected passage into the next message exists in ChatGPT; the only source found
  is a user's forum post describing the reference chip above the input
  ([community.openai.com](https://community.openai.com/t/unrendered-markdown-in-the-ask-chatgpt-reply-feature/1388930)).
  Claude lets a user edit an earlier message, which branches the conversation
  ([support.claude.com](https://support.claude.com/en/articles/17153992-what-are-artifacts-and-how-do-i-use-them)).
- No source was found for a convention on deleting single messages.

### What Sprout does now

| Action | A coach reply | The user's own message |
|---|---|---|
| Copy the whole message | action row under the reply; VoiceOver action | context menu; VoiceOver action |
| Copy a passage | select, then Copy | no |
| Ask about this (quote into the composer) | on a selection (edit menu) or the whole reply (action row; VoiceOver action) | context menu; VoiceOver action |
| Share | action row; the system menu on a selection | context menu |
| Delete (with confirmation) | action row overflow; VoiceOver action | context menu, last and red; VoiceOver action |
| Retry | the failure row under the failed message | same |

The action row is always under the newest reply; a tap on an older reply shows that
reply's row. "Ask about this" puts the passage above the message field as a quoted
reference; it travels inside the message as a Markdown block quote followed by the
question, which is what the model reads and what the bubble splits back into a reference
and a question (`ChatQuote`). The existing `AskVitaCenter` bus carries the quote, so
another screen can quote into the composer the same way.

Open: regenerate a reply that did arrive, edit-and-resend, read aloud, feedback
(thumbs). Edit-and-resend needs a decision about what happens to the turns after the
edited message (Claude branches); none of the four needs a schema change.

## 4. Failures

### What the providers say

- **Anthropic status codes**: 400 `invalid_request_error`, 401 `authentication_error`,
  402 `billing_error`, 403 `permission_error`, 404 `not_found_error`, 413
  `request_too_large`, 429 `rate_limit_error`, 500 `api_error`, 504 `timeout_error`, 529
  `overloaded_error`; every response carries a `request-id`; a 429 from a spend cap has no
  `retry-after` and keeps failing
  ([errors](https://platform.claude.com/docs/en/api/errors)). After a 429, wait at least
  the `retry-after` seconds ([rate limits](https://platform.claude.com/docs/en/api/rate-limits)).
- **Anthropic stop reasons** arrive with HTTP 200: `end_turn`, `max_tokens`,
  `stop_sequence`, `tool_use`, `pause_turn`, `refusal`, `model_context_window_exceeded`.
  A `max_tokens` stop can leave a tool call half-written, and the advice is to retry with a
  higher cap; an empty `end_turn` should not be retried unchanged
  ([handling stop reasons](https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons)).
  Partial output of a refused turn is to be discarded
  ([refusals](https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback)).
- **Tool results**: one `tool_result` for every `tool_use` in the assistant turn, in the
  next user message, with `is_error` for a failed or invalid call
  ([handle tool calls](https://platform.claude.com/docs/en/agents-and-tools/tool-use/handle-tool-calls)).
  Parallel tool use is on by default
  ([parallel tool use](https://platform.claude.com/docs/en/agents-and-tools/tool-use/parallel-tool-use)).
- **OpenAI**: 401 for a bad key; 429 for a rate limit (follow `Retry-After` when present)
  and, separately, 429 for exhausted credit or a spend limit, where retrying does not help;
  500; 503 overloaded; exponential backoff with a retry limit
  ([error codes](https://developers.openai.com/api/docs/guides/error-codes)). Failed
  requests count against the per-minute limit
  ([rate limits](https://developers.openai.com/api/docs/guides/rate-limits)). Chat
  Completions ends a choice with `finish_reason` `stop`, `length`, `tool_calls` or
  `content_filter`, and a refusal comes in the message's own `refusal` field
  ([chat completions](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)).
  A Responses result can be `incomplete` with a reason (`max_output_tokens`,
  `content_filter`)
  ([responses](https://developers.openai.com/api/reference/resources/responses/methods/create)).
  `context_length_exceeded` was found documented only on the Agents API errors page
  ([agents errors](https://developers.openai.com/api/docs/guides/agents-api/errors)); it is
  what the other endpoints return in practice, and that part is experience, not a source.
- **Both vendors' SDKs retry twice by default** with short exponential backoff, on
  connection errors, 408, 409, 429 and 5xx
  ([openai-python](https://raw.githubusercontent.com/openai/openai-python/main/README.md),
  [Anthropic Python SDK](https://platform.claude.com/docs/en/cli-sdks-libraries/sdks/python)).
  Sprout's clients retry once.
- **Apple**: `URLError.Code` separates no connection, a lost connection, a timeout, an
  unreachable host and cellular data being disallowed
  ([URLError.Code](https://developer.apple.com/documentation/foundation/urlerror/code)).
  An app that leaves the foreground is suspended shortly after; `beginBackgroundTask`
  buys a finite, unguaranteed amount of time (about 30 seconds in practice)
  ([extending background execution](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time),
  [forum thread 85066](https://developer.apple.com/forums/thread/85066)); background
  `URLSession`s are for uploads and downloads, not for a request like this one
  ([background configuration](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background(withidentifier:))).
  Idempotent requests can simply be retried; others need their own logic
  ([QA1941](https://developer.apple.com/library/archive/qa/qa1941/_index.html)).
- **What the user should be told**: why it failed and what they can do, without blame
  ([HIG, feedback](https://developer.apple.com/design/human-interface-guidelines/feedback),
  [HIG, writing](https://developer.apple.com/design/human-interface-guidelines/writing));
  keep what they typed and offer a way forward
  ([NN/g, error messages](https://www.nngroup.com/articles/error-message-guidelines/)).
  Apple Messages marks an undelivered message and offers Try Again
  ([support.apple.com 118433](https://support.apple.com/en-us/118433)).

### What Sprout does now, failure by failure

Every row is a branch of `CoachTurnEngine` with a test in `CoachTurnEngineTests`, run
through the real client against scripted responses in each wire format it applies to
(Anthropic Messages, OpenAI Chat Completions, OpenAI Responses). In every row the user's
message is already saved before the request leaves and is still there afterwards.

| What happened | How it is recognised | What the user sees | What they can do |
|---|---|---|---|
| Offline | `URLError` no connection / data not allowed | "I can't reach the internet right now…" | Try again |
| Connection dropped | `URLError` lost connection, host unreachable | "The connection dropped before I could answer…" | Try again |
| Timeout | `URLError.timedOut` (60 s), HTTP 408 / 504 | "That took too long to come back…" | Try again |
| No key | the client cannot be built | which provider's key is missing | Open AI settings, Try again |
| Key rejected | 401, 403 | "{Provider} didn't accept your API key…" | Open AI settings, Try again |
| Model not available | 404 | the model set for the coach is not offered on this key | Open AI settings, Try again |
| Out of credit / over a spend limit | 402; 429 `insufficient_quota` and the billing family; Anthropic's 400 naming the credit balance | it is fixed on the provider's console, waiting does not help | Open AI settings; **not retried automatically** |
| Rate limit | 429 | "{Provider} asked us to slow down…" with the wait | a countdown, then Try again |
| Overloaded | 529, 503 | "{Provider} is overloaded right now…" | Try again |
| Provider error | other 5xx | "{Provider} had a problem on its side…" | Try again |
| Reply cut off by the output cap | `max_tokens` / `length` / `max_output_tokens` | what did arrive stays on screen, then "My reply got cut off…" | Try again (replaces the partial reply) |
| Cut off in the middle of a tool call | same, with a tool call present | nothing is applied; same message | Try again |
| Conversation too large | 413; a 400 naming the context length; `model_context_window_exceeded` | "That's more than I can take in at once…" | shorten the message (no Retry: the same request fails the same way) |
| Refusal with text (OpenAI) | `refusal` field / content part | the model's words, as its reply | — |
| Refusal with no text | `refusal` stop reason, `content_filter` | "I can't help with that one…" | rephrase (no Retry) |
| A tool call the app rejects | `CoachTools.parse` returns `.invalid` | nothing; the reason goes back to the model as an error result and it answers | — |
| Two tool calls in one turn | the client exposes the first | the first is applied; the follow-up tells the model only that one ran, and it asks for the second again | — |
| The model keeps asking for tools | five chained tools | the sixth call forbids tools; a tool asked for anyway is ignored | — |
| A second tap on send | a turn is in flight | nothing: one message, one request | — |
| Double tap (the second lands on Stop) | Stop within 0.6 s of the send | nothing: the turn continues | — |
| Stop | the user taps the stop button | "Stopped. Your message is still here." A late reply is not shown | Try again |
| The follow-up call fails after a tool was applied | any of the above, on a later call of the turn | the failure; the Undo banner is still there | Try again re-issues **that call**: the tool is not applied twice |
| App leaves the foreground mid-request | — | the turn holds a background task, so a reply seconds away still arrives and is saved | — |
| App is closed mid-request | on the next open the newest message is the user's and nothing is in flight | "I didn't get to answer this one." | Try again |
| The screen goes away mid-request | — | the turn's task keeps the engine alive; the reply is saved | — |
| Unreadable 2xx body | the client's decode error | "I got a reply I couldn't read…" | Try again |

The clients' one automatic retry now reads `retry-after` / `retry-after-ms`: a wait of up
to five seconds is sat out, a longer one is handed to the user as a countdown instead of
being retried into, and an exhausted account is not retried at all.

## 5. Sending, the keyboard, accessibility

- **Stop.** ChatGPT's stop button is the reference
  ([help.openai.com 7996703](https://help.openai.com/en/articles/7996703-troubleshooting-chatgpt-error-messages)).
  Sprout's send button becomes a stop button while a reply is on its way. A stop in the
  first 0.6 s after a send is ignored, so a double tap on send cannot cancel what it sent
  (verified by a UI test that double-taps).
- **Double send.** A request that is retried should not perform its effect twice; Stripe's
  idempotency keys are the usual statement of the idea
  ([Stripe](https://docs.stripe.com/api/idempotent_requests)). Neither model API has an
  idempotency key, so Sprout prevents the second request instead: one turn at a time,
  enforced in the engine rather than by a disabled button.
- **Keyboard.** The input bar is a bottom `safeAreaInset`, so the keyboard changes the
  scroll view's inset and not its frame
  ([safeAreaInset](https://developer.apple.com/documentation/swiftui/view/safeareainset(edge:alignment:spacing:content:)-4s51l));
  the list dismisses the keyboard interactively
  ([scrollDismissesKeyboard](https://developer.apple.com/documentation/swiftui/view/scrolldismisseskeyboard(_:))).
  Both were already so and are unchanged.
- **VoiceOver.** A new reply is announced
  ([AccessibilityNotification.Announcement](https://developer.apple.com/documentation/accessibility/accessibilitynotification/announcement));
  each bubble is one element with Copy / Ask about this / Delete as named actions, which
  VoiceOver offers in the Actions rotor
  ([accessibilityAction(named:)](https://developer.apple.com/documentation/swiftui/view/accessibilityaction(named:_:)),
  [UIAccessibilityCustomAction](https://developer.apple.com/documentation/uikit/uiaccessibilitycustomaction)).
  "Load earlier messages" is a button, so it does not depend on scrolling. Not verified
  with VoiceOver running: no test here turns it on.
- **Dynamic Type.** The reply text view builds its fonts from `preferredFont` for the
  environment's size category and rebuilds when it changes
  ([UIFontMetrics](https://developer.apple.com/documentation/uikit/uifontmetrics),
  [HIG, typography](https://developer.apple.com/design/human-interface-guidelines/typography));
  a unit test checks the largest accessibility size produces a larger font. Not looked at
  on screen at the accessibility sizes.
- **Hit targets.** The HIG's default control size on iOS is 44 × 44 pt with a 28 × 28 pt
  minimum ([HIG, accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)).
  The jump button is 44 × 44; the action-row icons are 40 × 34.

## 6. What the chat did before, by reading and by running

- **Rows loaded.** `@Query(sort: \ChatMessage.createdAt)` with no limit
  (`CoachView.swift:16`): every stored message, on opening the tab and again after every
  insert. The probe logged `rows_loaded` equal to `rows_in_store` at every size (verified).
- **Rows rendered.** `ForEach(Array(messages.enumerated()))` in a `LazyVStack`
  (`CoachView.swift:206–207`): the array of all rows is rebuilt on every body evaluation,
  including each keystroke in the message field (read).
- **Opening position.** `proxy.scrollTo(lastID, anchor: .bottom)` from `onAppear`
  (`CoachView.swift:247`, `263–283`): a programmatic scroll to the far end of a lazy stack.
- **History sent to the model.** The last 16 messages that are neither the welcome seed nor
  a decision marker, trimmed to start on a user turn (`CoachView.swift:480–482`, constant
  at `:82`), selected by filtering the whole array. Unchanged in what it selects; it is now
  a fetch with a limit of 16 (`CoachTurnEngine.recentHistory`), and a test proves the two
  select the same rows.
- **Memory fold.** After each final reply, everything older than the window and newer than
  the high-water mark was sent to the fold model in one call (`CoachView.swift:766–823`).
  With no mark yet (a long conversation whose folds had been failing, or one that predates
  the feature) that is the entire backlog in one prompt. Now at most 40 messages per fold,
  oldest first, the rest after the following replies.

Defects found are listed in section 9.

## 7. Measurements

**How.** `--demo-long-chat <n>` (DEBUG) replaces the conversation with n seeded messages:
the welcome, then alternating user and coach turns of realistic length, some with lists,
headings, bold and a rule. `--chat-probe` (DEBUG) logs, when the newest message's row has
appeared **and** the main queue has run again, the time since the process started (from
the kernel's process start time, so the fetch before the first `body` is inside the
number), the time since `CoachView.init`, and the process's physical footprint
(`task_info`, the number Xcode's memory gauge shows); and the footprint again five seconds
later. Each size: seed, quit, then three cold launches straight into the chat tab
(`--demo-tab coach`). iPhone 17 Pro simulator, iOS 26.4, Debug build, on an Apple-silicon
Mac. A simulator runs on the Mac's CPU: a phone is slower, by a factor that was not
measured.

| Messages stored | Rows fetched: before | after | Tab created → usable, ms (median of 3; range): before | after | Process start → usable, ms: before | after | Memory when usable, MB: before | after |
|---|---|---|---|---|---|---|---|---|
| 3 | 3 | 3 | 276 (268–298) | 331 (321–385) | 856 | 927 | 37.6 | 40.0 |
| 200 | 200 | 40 | 337 (334–358) | 332 (320–346) | 927 | 899 | 45.6 | 42.4 |
| 1,000 | 1,000 | 40 | 358 (347–389) | 352 (320–352) | 946 | 934 | 55.9 | 42.3 |
| 5,000 | 5,000 | 40 | 677 (615–679) | 337 (329–345) | 1289 | 912 | 113.0 | 42.7 |

- **Before:** time and memory both grow with the conversation, because all of it is
  fetched: from the 3-message demo chat to 5,000 messages the tab takes
  401 ms longer to become usable and the process holds
  75 MB more, about 14 MB per 1,000 messages. Memory grows
  without bound in the sense that matters: in proportion to how much has ever been said.
  On this hardware 5,000 messages did load (in about 0.7 s); "it just won't load"
  was not reproduced on the simulator, and a phone was not measured.
- **The short chat got slightly slower:** with three messages the tab takes about 55 ms
  longer to become usable and holds about 2 MB more. That is the cost of laying replies out
  in text views (so they can be selected) and of the scroll bookkeeping; it is the same
  at every size.
- **After:** 40 rows are fetched at every size; the time and the memory at 5,000 messages
  are the same as at 200 to within the spread of the three runs. Memory now grows with how
  far back the reader scrolls in a session (40 rows a page), not with the conversation.
- Five seconds after becoming usable the footprint after was 1.4 MB
  higher at the median and at most 7.4 MB higher in any run, the same at every size
  (before, at 5,000 messages: up to 11.2 MB higher). Nothing keeps loading in the background.
- What was **not** measured: sending a message into a long conversation (before, every
  insert re-ran the unlimited query; after, it is one fetch of the rows newer than the
  newest loaded one), scrolling frame rate, and conversations with photos.

An eager `VStack` over the same 40 rows was also measured, because Apple's advice is to
start there: 540–650 ms to usable and 75 MB, against 360–440 ms and 44 MB for the lazy
stack (both under the UI test runner, which is slower than a plain launch), and SwiftUI's identity-based position did not hold a prepended page in it at all.
The lazy stack stays.

## 8. Feature or failure → standard → Sprout before → gap → now

"Before" cites `b22f23f`. Status: **fixed** = implemented on this branch and covered by a
test or a run named in the row; **partly** = improved, with the rest stated; **open** = not done.

| # | Feature or failure | The standard | Sprout before (`file:line`) | Gap | Now |
|---|---|---|---|---|---|
| 1 | Rows fetched when the chat opens | a page, by `fetchLimit` (§1) | every row: `@Query(sort: \ChatMessage.createdAt)`, `CoachView.swift:16` | memory (about 14 MB per 1,000 messages) and open time grow with the conversation (§7) | **fixed**: 40 rows at any length (`ChatTranscript`; `ChatTranscriptTests`, measured §7) |
| 2 | Earlier messages | load the previous page at the top (§1) | none needed: everything was loaded | — | **fixed**: `ChatWindow`, loads within 240 pt of the top, and a button (`ChatWindowTests`; UI run §10) |
| 3 | Position when a page is prepended | the rows on screen do not move (§1) | not applicable | new requirement | **partly**: the top row stays on screen but moved 0–173 pt in nine measured loads at rest (§1). Exact hold is **open** |
| 4 | Opening position | newest message, no visible scroll (§1) | programmatic `scrollTo` from `onAppear`, `CoachView.swift:247`, `263–283` | a jump to the far end of a lazy stack on every open | **fixed**: `defaultScrollAnchor(.bottom)` (UI run §10) |
| 5 | Jump to latest | a button while scrolled up (§1) | none | missing | **fixed**, with an unseen count (UI run §10) |
| 6 | A message arriving while the reader is scrolled up | do not move the reader | every new row scrolled to the bottom, `CoachView.swift:244` | reading history was interrupted | **fixed**: counted instead; the user's own send still scrolls down (`ChatWindowTests`) |
| 7 | Selecting part of a reply | a `UITextView` on iOS 18/26 (§2) | `.textSelection(.enabled)` on the bubble, `CoachView.swift:977`: whole text only | no range selection | **fixed** for replies (`SelectableMarkdownText`; UI run §10). The user's own messages: whole-message Copy |
| 8 | Copy a whole message | one tap or one menu item (§3) | only through that modifier's system menu, `CoachView.swift:977` | not discoverable | **fixed**: action row, context menu, VoiceOver action |
| 9 | Share | same (§3) | same modifier | same | **fixed** |
| 10 | Ask about a passage | quote into the next message (§3) | "Ask Vita about this" existed for cards only, `AskVita.swift:34–55` | not for chat text | **fixed** (`ChatQuote`; `ChatMessageFeaturesTests`; UI run §10) |
| 11 | Retry a failed turn | keep the message, offer Try Again (§4) | a banner and nothing else, `CoachView.swift:98–103` | the user retyped | **fixed** (`CoachTurnEngine.retry`; UI run §10) |
| 12 | Delete a message | no cited convention | none | missing | **fixed**, with confirmation |
| 13 | Regenerate a reply that arrived | ChatGPT has it (§3) | none | missing | **open** |
| 14 | Edit and resend | Claude branches (§3) | none | missing | **open** (needs a decision about the turns after the edit) |
| 15 | Read aloud, feedback | ChatGPT has both (§3) | none | missing | **open** (feedback has nowhere to go: there is no backend) |
| 16 | Error messages | say why and what to do (§4) | two messages, `CoachView.swift:739–745`, plus the missing-key banner, `:844–859` | a rejected key, a rate limit and an outage read the same | **fixed**: 17 causes (`CoachTurnErrorTests`) |
| 17 | `retry-after` | wait what the provider says (§4) | one retry after a fixed 0.7 s, `AnthropicClient.swift:312`, `OpenAIClient.swift:282` | a retry inside the wait; a long wait surfaced as a generic error | **fixed** (`CoachTurnEngineTests`) |
| 18 | Exhausted credit | do not retry (§4) | retried like a rate limit, same lines | a pointless second request, then a generic error | **fixed** |
| 19 | Reply cut off by the output cap | say so; never act on a half-written tool call (§4) | the client dropped the tool call (`AnthropicClient.swift:115`, `OpenAIClient.swift:551`, `:706`) and told nobody; with no prose the user got "I'm here 💚", `CoachView.swift:553–556` | a request silently not carried out | **fixed** |
| 20 | Refusal | show it as what it is (§4) | not recognised; OpenAI's refusal text was dropped (`OpenAIClient.swift:534`) and became "I'm here 💚" | misleading reply | **fixed** |
| 21 | Conversation too large | name it; retrying cannot help (§4) | generic error | misleading "try again" | **fixed** in the message. **Open**: the 16-message window is not trimmed by size, and every photo in it is re-sent each turn (`CoachView.swift:485–492`) |
| 22 | A tool call the app rejects | error result back to the model (§4) | did so, `CoachView.swift:575–581` | untested | **tested**, all three wire formats |
| 23 | Two tool calls in one turn | one result per call (§4) | the client keeps the first, `AnthropicClient.swift:105`, `:128` | works by an extra round trip | **tested**. **Open**: `disable_parallel_tool_use` / `parallel_tool_calls: false` is not sent; changing the request needs the paid evaluation |
| 24 | Runaway tool chain | a bound that always ends the turn | tools forbidden at depth 5, `CoachView.swift:85`, `:710`, but a tool returned anyway was applied and the chain went on | no hard stop | **fixed** |
| 25 | Retry after a tool was applied | do not perform the effect twice (§5) | no retry; asking again could log the item again | duplicate writes | **fixed**: Retry re-issues the failed call only |
| 26 | A second tap on send | one turn | guarded by `!isSending`, `CoachView.swift:449` | correct, untested | **tested**; and a double tap can no longer land on Stop |
| 27 | Stop | a stop control (§5) | none | missing | **fixed** (UI run §10) |
| 28 | App backgrounded mid-request | finish if seconds away; otherwise say so (§4) | no background task; a dead request left the message with no reply and no sign | silent loss of the turn | **fixed** (background task; "I didn't get to answer this one" on the next open). The background task is tested with a recorder, not by suspending the app |
| 29 | Reply after the screen is gone | still saved | saved, because the task captured the view's context | untested | **tested** |
| 30 | The user's message is never lost | saved before the call (§4) | saved first, `CoachView.swift:472–474` | correct, untested | **tested** |
| 31 | Memory fold batch | bounded prompts | everything unfolded in one call, `CoachView.swift:766–775` | a long backlog in one prompt | **fixed**: 40 per fold |
| 32 | Keyboard and safe area | inset, interactive dismiss (§5) | `CoachView.swift:123`, `:239` | none | unchanged |
| 33 | VoiceOver: new reply | announce (§5) | none | silent | **fixed** (read; not run with VoiceOver on) |
| 34 | VoiceOver: message actions | named actions (§5) | label and value only, `CoachView.swift:978–979` | no actions | **fixed** (read; not run with VoiceOver on) |
| 35 | Dynamic Type | all sizes (§5) | SwiftUI text | none | kept: the text view follows the size category (unit test; not viewed at accessibility sizes) |
| 36 | Token-by-token streaming | products stream as the model writes | the whole reply is awaited, then typed out, `MarkdownMessage.swift:177` | long replies feel slower than they are | **open** (the clients are not streaming clients) |
| 37 | "Ask Vita" from a card while a reply is on its way | ask it | the card appeared and the question was dropped, `CoachView.swift:181–186` | silent loss | **fixed** in the view (no unit test: view logic) |

## 9. Defects found

Lines are of `b22f23f`. Each fix has the test named; the turn logic lived in private
methods of a view, so "fails on the old code" means the test drives a path the old code
handled the way the row describes.

1. `CoachView.swift:16` — the chat loaded every stored message (and re-fetched them after
   every insert). Measured: about 14 MB of memory per 1,000 messages just to open the tab, and 0.4 s longer
   to open at 5,000.
   Fixed; `ChatTranscriptTests.testOpeningLoadsOnePageNotTheConversation`.
2. `CoachView.swift:553–556` with `AnthropicClient.swift:115`, `OpenAIClient.swift:551`,
   `:706` — a reply cut off in the middle of a tool call, with no prose, showed "I'm here 💚"
   and did nothing. Fixed; `testACutOffWithNoTextShowsTheFailureNotTheFallback`.
3. `CoachView.swift:739–745` — a rejected key, a rate limit, an outage and a timeout all
   read "Something went wrong on my end". Fixed; `CoachTurnErrorTests`, and one engine test
   per cause.
4. `CoachView.swift:685–737` — when the call after an applied tool failed there was no way
   to get the reply except asking again, which could apply the tool a second time. Fixed;
   `testRetryAfterAFailedFollowUpDoesNotApplyTheToolAgain`.
5. `CoachView.swift:572–604`, `:710` — past the depth cap the request forbade tools, but a
   tool call that came back anyway was applied and the chain continued. Fixed;
   `testTheChainStopsAtTheDepthCapEvenIfTheModelKeepsAskingForTools`.
6. `CoachView.swift:766–775` — the first memory fold of a long, unfolded conversation sent
   all of it in one prompt. Fixed; `testALongBacklogIsFoldedInBatchesOldestFirst`.
7. `OpenAIClient.swift:534` (Chat Completions) and `:691` (Responses) — a refusal's text was
   ignored, so the user saw "I'm here 💚". Fixed;
   `testARefusalWithTextIsTheReplyAndOneWithoutIsAFailureThatCannotBeRetried`.
8. `AnthropicClient.swift:312`, `OpenAIClient.swift:282` — the automatic retry ignored
   `retry-after` and retried an exhausted account. Fixed;
   `testALongRetryAfterIsNotSatOutByTheClient`,
   `testAnAccountOutOfCreditIsNotRetriedAndIsNotCalledARateLimit`.
9. `CoachView.swift:181–186` — "Ask Vita about this" from a card while a reply was on its
   way showed the card and never asked the question. Fixed in the view; no unit test.
10. `CoachView.swift:244` — a message arriving while the reader was scrolled up pulled them
    to the bottom. Fixed; `testAReplyThatArrivesWhileTheReaderIsScrolledUpIsCountedNotFollowed`.
11. No line (an absence) — a message whose reply never arrived (the app was closed
    mid-request) stayed in the conversation with no sign and no retry. Fixed;
    `testAnUnansweredMessageFromAnEarlierRunOffersRetryWithoutDuplicatingIt`.
12. `CoachView.swift:480–492` — a stored message with no text and no photo would have been
    sent as an empty text block, which both providers reject. It cannot be created from the
    UI; hardened anyway. `testHistoryWindowRule`.

Found while building this and fixed before it was committed: with the send button turning
into a stop button in place, the second tap of a double tap cancelled the turn the first
tap started (`testAStopInTheInstantAfterSendIsIgnored`, and a UI run that double-taps).

Found by reading and **left open** (a fix needs a test, and this one is view lifecycle):

13. `MarkdownMessage.swift:191–192`, `:196–197` — the typing reveal cancels its task when
    the row disappears and, because it has already started once, never restarts when the
    row comes back. A reply that scrolls out of the lazy stack during the 1.1 s reveal
    would stay cut short until the next launch, and its completion callback would never
    run (on this branch that also means it never becomes selectable). Not reproduced.

## 10. Not verified

- **A real phone.** Every time and every megabyte here is from a simulator on a Mac.
- **A real provider.** No request left the machine. Every response a test or a UI run saw
  was written by hand from the providers' documented shapes (and, for the shapes the
  existing client tests already used, from those). A provider that answers differently
  from its documentation is not covered.
- **iOS 18.** The deployment target is 18.0; everything was run on iOS 26.4 only.
  `ScrollPosition`, `onScrollGeometryChange` and `onScrollPhaseChange` are iOS 18 APIs, so
  it builds for 18; how the scroll position behaves there on a prepend was not measured.
- **VoiceOver.** The announcement of a new reply and the named actions on a bubble were
  written and read, not exercised with VoiceOver on.
- **Dynamic Type on screen.** A unit test checks the reply text is built at the
  accessibility sizes; the screen was not looked at with them.
- **The light theme.** Screenshots and UI runs used the dark demo profile only.
- **Backgrounding.** The turn begins and ends a background task (asserted with a recorder).
  The app was not actually sent to the background mid-request, and what iOS does when the
  time runs out is as documented, not observed.
- **Network conditions.** Offline, timeout and a dropped connection are a transport that
  throws the corresponding `URLError`; no network was actually cut.
- **The share sheet** was not opened; photos in the chat were not exercised in a UI run,
  and a conversation with many photos was not measured.
- **"Ask Vita about this" from a card while a reply is on its way** (defect 9): fixed in
  the view, with no test.
- **Sending and scrolling with a very long conversation**, as opposed to opening it: the
  per-send work is now a 16-row fetch and a tail fetch, by reading; it was not timed.

**What the UI runs did and did not reach by touch.** A throwaway XCUITest target (kept
out of the repository) drove the Debug build with real swipes, taps and long presses:
opening at the newest message, scrolling up, the jump button, loading earlier pages by
scrolling and by the button, the context menu on the user's message, selecting text in a
reply, "Ask about this" from both, typing and sending, a failure and its Retry, the
rate-limit countdown, a rejected key and the AI settings sheet, the confirm card, the Undo
banner, a double tap on send, deleting a message, and the action row of an older reply.
Three things came from DEBUG launch arguments because nothing on the device can produce
them without a key or the network: the 201-message conversation (`--demo-long-chat`), the
model's replies and failures (`--chat-debug-script`, a canned transport under the real
engine and client), and, for the measurement of a page load at rest only, holding the
automatic load so the row could be tapped (`--chat-debug-do hold`).

## 11. Screenshots

In `docs/screenshots/review/`, dark demo profile, from the UI runs described above:
`chat-long-latest.png` (a 201-message conversation opened at its newest message),
`chat-jump-to-latest.png`, `chat-load-earlier.png` (the top of the first page),
`chat-context-menu.png` (long press on the user's message), `chat-selection-ask.png` (a
selection in a reply with "Ask about this" in the edit menu), `chat-quoted-composer.png`,
`chat-quoted-sent.png`, `chat-error-retry.png`, `chat-rate-limit.png`,
`chat-key-rejected.png`, `chat-confirm-card.png`, `chat-delete-confirm.png`.
