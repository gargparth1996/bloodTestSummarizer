# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An iOS app (Swift 6, UIKit, no storyboards) that summarizes blood test PDFs. The
user uploads a PDF; the app sends it to the Anthropic Messages API (model
`claude-sonnet-5`), streams back a structured JSON summary, and renders it as a
native table view: an overall plain-language impression, per-test findings with
normal/low/high/critical flags, general (non-prescriptive) suggestions, and a
disclaimer to see a real doctor. This is an explainer layer over lab results,
not a diagnostic tool — the system prompt explicitly avoids naming diagnoses or
medications, and the UI keeps that disclaimer visible.

## Build / run

There's no CLI test suite or lint config — this is a single Xcode app target,
built and run through Xcode.

- Open `BloodTestSummarizer.xcodeproj`, scheme **BloodTestSummarizer**, deployment
  target iOS 17+, Swift Language Version 6.
- `xcodebuild -list -project BloodTestSummarizer.xcodeproj` to inspect
  targets/schemes from the CLI; `xcodebuild -scheme BloodTestSummarizer build`
  (add `-destination` for a specific simulator) to build headlessly.
- Requires `ANTHROPIC_API_KEY` to be resolvable at runtime — see below.

## The API key setup

`APIConfiguration.apiKey` (`BloodTestSummarizer/Enums/APIConfiguration.swift`)
reads `ANTHROPIC_API_KEY` out of `Info.plist` via
`Bundle.main.object(forInfoDictionaryKey:)`. The intended flow:

1. Create an untracked `Resources/Local.xcconfig` defining `ANTHROPIC_API_KEY = <key>`,
   and wire it up in **Project → Info tab → Configurations** for the Debug
   configuration.
2. `Info.plist` references it as the unexpanded placeholder `$(ANTHROPIC_API_KEY)`.
3. Xcode substitutes the real value at build time, so the key never lands in
   version control.

Never commit a real key into `Info.plist` — only the placeholder belongs in
version control.

## Architecture

Everything lives under `BloodTestSummarizer/`, organized by role rather than
by feature (small app, one feature):

```
App/            AppDelegate, SceneDelegate — builds UI in code, no storyboard.
                SceneDelegate roots a UINavigationController on MainViewController.
Enums/          APIConfiguration (key lookup), APIError (typed, user-facing
                error messages), SummarizeEvent / SummarizePhase (streaming
                progress signal — see below).
Models/         BloodTestSummary (the Codable shape Claude's JSON must match),
                ClaudeAPIRequestModels / ClaudeAPIResponseModels /
                ClaudeAPIStreamModels (wire types for the Messages API).
Services/       ClaudeAPIService — the only thing that talks to the network.
ViewControllers/MainViewController (upload button + document picker view;
                delegates all logic to MainViewModel),
                SummaryViewController (renders the parsed summary).
                ViewModels/MainViewModel (drives the picker + summarize flow,
                reports back through the ActionableDelegate protocol).
Views/          FindingCell (one row per lab value), LoadingIndicatorView
                (ring progress driven by real streaming signal, not a timer).
```

### Request/response flow

`MainViewController` doesn't own the picker/networking logic directly — that's
split out into `MainViewModel` (`BloodTestSummarizer/ViewControllers/ViewModels/MainViewModel.swift`)
under a lightweight MVVM split, both injected via `init` for testability.

1. `MainViewController` presents `UIDocumentPickerViewController` restricted to
   `.pdf`, with `picker.delegate` set to the **view model**, not the view
   controller. `MainViewModel` conforms to `UIDocumentPickerDelegate` and
   handles `documentPicker(_:didPickDocumentsAt:)` itself. Picked files may
   live outside the sandbox, so it wraps the read in
   `startAccessingSecurityScopedResource()`.
2. `ClaudeAPIService.summarize(pdfData:)` returns an `AsyncThrowingStream<SummarizeEvent, Error>`.
   It POSTs to the Messages API with `stream: true`, sending the PDF as a
   base64 `document` content block alongside a text instruction (Claude reads
   the PDF's visual layout/tables directly — see
   [PDF support docs](https://docs.claude.com/en/docs/build-with-claude/pdf-support)).
   Request size is checked client-side against Anthropic's 32MB limit
   (`APIError.fileTooLarge`) before sending.
3. The system prompt (in `ClaudeAPIService.systemPrompt`) instructs Claude to
   return *only* JSON matching `BloodTestSummary`'s shape — no markdown fences,
   no commentary. `stripCodeFences` defensively strips fences anyway, since
   models don't always comply. **If you change `BloodTestSummary`'s fields,
   update the system prompt's schema description to match, and vice versa.**
4. As SSE chunks arrive, `runSummarize` accumulates raw text and infers a
   coarse `SummarizePhase` (`.uploading` → `.analyzing` → `.extractingFindings`
   → `.buildingRecommendations` → `.finalizing`) by checking which JSON keys
   have appeared in the buffer so far — not a timer. It also counts
   `"testName"` occurrences to report `testsFound`. Each step yields a
   `.progress` event; cancelling the consuming `Task` (via `MainViewModel.cancelLoading()`,
   wired to `LoadingIndicatorView.onCancel`) aborts the request via
   `AsyncThrowingStream`'s `onTermination`.
5. Once the stream ends, the full buffer is parsed as `BloodTestSummary` and
   yielded as a single `.finished` event. Decode failures map to
   `APIError.decoding`; an empty buffer (e.g. the model stopped early) maps to
   `APIError.incompleteResponse(stopReason:)`.
6. `MainViewModel` reports progress back to `MainViewController` through the
   `ActionableDelegate` protocol (`setLoading(_:)`, `update(phase:testsFound:)`,
   `complete(summary:)`, `presentError(_:)`) — each call hops back onto
   `@MainActor` via `Task { @MainActor in ... }`. `MainViewController` (the
   delegate) drives `LoadingIndicatorView` off these callbacks and pushes
   `SummaryViewController` from `complete(summary:)`.
7. `SummaryViewController` is a plain `UITableViewController` with four fixed
   sections (impression, findings, recommendations, disclaimer) — findings use
   `FindingCell`, which color-codes the flag badge (green/blue/orange/red for
   normal/low/high/critical).

### Security posture (by design, not accidental)

`ClaudeAPIService` calls `api.anthropic.com` directly from the client, with
the API key attached as an `x-api-key` header. That's acceptable for running
on your own device but **not safe to ship** — the key can be extracted from a
distributed binary. Before any real distribution, the intended change (per
README and in-code comments) is to point `baseURL` at your own backend that
holds the key server-side and drop the `x-api-key` header logic from the
client entirely. There is no backend in this repo yet — building one is on
whoever ships this.

## Privacy

Blood test PDFs are sensitive health data. This app sends them straight to
Anthropic's API and doesn't persist anything locally beyond the current
session. Building this out further (encryption at rest, a data retention
policy, HIPAA or equivalent compliance) is a prerequisite before handling real
patient data at any scale beyond personal use.
