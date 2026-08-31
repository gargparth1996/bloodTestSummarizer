# BloodTestSummarizer (iOS, Swift 6, UIKit)

Upload a blood test PDF, send it to Claude, get back a plain-language
summary in a native table view — overall impression, per-test findings
with normal/low/high/critical flags, general suggestions, and a
disclaimer to see a real doctor.

## Architecture: don't call Anthropic directly from a shipping app

`ClaudeAPIService` as written calls `api.anthropic.com` straight from
the app, using an API key baked in at build time via `Info.plist` /
`Local.xcconfig`. That's fine for testing on your own device. It is
**not safe to distribute** — anyone can pull the compiled binary apart
and extract the key, then run up your Anthropic bill.

Before shipping:

1. Stand up a small backend (any language/host) that holds the real API
   key server-side and forwards requests to Anthropic on the app's
   behalf.
2. Change `ClaudeAPIService.baseURL` to point at that server.
3. Delete the `x-api-key` header logic from `ClaudeAPIService` — your
   server adds that, not the app.
4. Add real auth/rate-limiting to the server so strangers can't use it
   as a free proxy.

There is no backend included in this repo yet — that's on you to build
before distributing the app to anyone else.

## Project structure

```
BloodTestSummarizer/
  App/
    AppDelegate.swift
    SceneDelegate.swift               # builds UI in code, roots a
                                       # UINavigationController on MainViewController
  Enums/
    APIConfiguration.swift            # reads the (dev-only) API key from Info.plist
    APIError.swift                    # typed, user-facing error messages
    SummarizeEvent.swift              # streaming events (.progress / .finished)
    SummarizePhase.swift              # coarse progress phases inferred from the JSON stream
  Models/
    BloodTestSummary.swift            # Codable struct matching Claude's JSON output
    ClaudeAPIRequestModels.swift      # wire types for Messages API requests
    ClaudeAPIResponseModels.swift     # wire types for Messages API responses
    ClaudeAPIStreamModels.swift       # wire types for SSE stream events
  Services/
    ClaudeAPIService.swift            # builds the request, streams the PDF, parses the reply
  ViewControllers/
    MainViewController.swift          # upload button; delegates picker + networking to MainViewModel
    SummaryViewController.swift       # table view of the parsed summary
    ViewModels/
      MainViewModel.swift             # UIDocumentPickerDelegate, drives the summarize flow,
                                       # reports back via the ActionableDelegate protocol
  Views/
    FindingCell.swift                 # one row per blood test value, with a color-coded flag
    LoadingIndicatorView.swift        # ring progress driven by real streaming signal, not a timer
  Resources/
    Info.plist
```

## Getting it running

1. Open `BloodTestSummarizer.xcodeproj` in Xcode (scheme
   **BloodTestSummarizer**, deployment target iOS 17+, Swift Language
   Version 6).
2. Create an untracked `Resources/Local.xcconfig` defining
   `ANTHROPIC_API_KEY = <your key from the Anthropic Console>`, and wire
   it up in **Project → Info tab → Configurations** for the Debug
   configuration. `Info.plist` should reference it as the unexpanded
   placeholder `$(ANTHROPIC_API_KEY)` — never commit a real key there.
3. Build and run on a simulator or device (Files app access works on
   both). Tap **Upload Blood Test PDF**, pick a file, wait for the
   summary.

From the CLI: `xcodebuild -list -project BloodTestSummarizer.xcodeproj`
to inspect targets/schemes, or
`xcodebuild -scheme BloodTestSummarizer build` (add `-destination` for
a specific simulator) to build headlessly. There's no CLI test suite or
lint config yet.

## A few things worth knowing about the API call itself

- `MainViewController` presents the document picker but delegates all
  picking/networking logic to `MainViewModel`, which conforms to
  `UIDocumentPickerDelegate` directly and reports progress back through
  the `ActionableDelegate` protocol (`setLoading`, `update(phase:testsFound:)`,
  `complete(summary:)`, `presentError`).
- PDFs are sent as a base64 `document` content block (Claude reads the
  actual layout/tables visually, not just extracted text) — see
  [Anthropic's PDF support docs](https://docs.claude.com/en/docs/build-with-claude/pdf-support).
- Anthropic's request-size limit is currently 32MB; `ClaudeAPIService`
  checks the byte size before sending and surfaces `APIError.fileTooLarge`
  if it's over.
- The response is streamed (`stream: true`); `LoadingIndicatorView` is
  driven off real progress signals inferred from which JSON keys have
  appeared in the buffer so far, not a timer.
- The system prompt asks Claude to return strict JSON matching
  `BloodTestSummary`, and to avoid naming specific diagnoses or
  medications — it's positioned as an explainer, not a diagnostic tool.
  Keep the in-app disclaimer visible; this app is a convenience layer
  for reading results, not a substitute for the person's own doctor.
- Model string used is `claude-sonnet-5` — check
  [docs.claude.com](https://docs.claude.com/en/docs/about-claude/models)
  for the current model lineup if this project sits unused for a while,
  as model names do change over time.

## Privacy note

Blood test PDFs are sensitive health data. This project sends them
straight to Anthropic's API and doesn't persist anything locally beyond
the current session — but if you build this out further, think about
whether you need encryption at rest, a data retention policy, and
whatever health-data regulations apply in your jurisdiction (e.g. HIPAA
in the US) before handling real patient data at any scale beyond your
own personal use.
