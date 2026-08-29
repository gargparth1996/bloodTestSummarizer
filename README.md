# BloodTestSummarizer (iOS, Swift 6, UIKit)

Upload a blood test PDF, send it to Claude, get back a plain-language
summary in a native table view — overall impression, per-test findings
with normal/low/high/critical flags, general suggestions, and a
disclaimer to see a real doctor.

## Two things to know before you build this

**1. This wasn't compiled or run.** These files were generated as plain
text, not inside Xcode, so I can't guarantee it builds without a typo
fix somewhere. The code is complete and should be close, but budget
some time for the usual first-build friction.

**2. Claude can't run on-device.** There's no Anthropic SDK or exported
model you can embed in the app to process PDFs locally — every summary
requires a network call to Anthropic's API. That shapes the two
questions below.

## Architecture: don't call Anthropic directly from a shipping app

`ClaudeAPIService` as written calls `api.anthropic.com` straight from
the app, using an API key baked in at build time via `Info.plist` /
`Local.xcconfig`. That's fine for testing on your own device. It is
**not safe to distribute** — anyone can pull the compiled binary apart
and extract the key, then run up your Anthropic bill.

`backend-example/server.js` is a minimal Node/Express server that holds
the real API key server-side and forwards requests. Before shipping:

1. Deploy something like `server.js` (any host that can run Node, or
   port the same three lines of logic to your language of choice).
2. Change `ClaudeAPIService.baseURL` to your server's URL.
3. Delete the `x-api-key` header logic from `ClaudeAPIService` — your
   server adds that, not the app.
4. Add real auth/rate-limiting to the server so strangers can't use it
   as a free proxy.

## Project structure

```
BloodTestSummarizer/
  App/
    AppDelegate.swift
    SceneDelegate.swift
  Models/
    BloodTestSummary.swift        # Codable struct matching Claude's JSON output
  Services/
    ClaudeAPIModels.swift         # request/response wire types for the Messages API
    ClaudeAPIService.swift        # builds the request, sends the PDF, parses the reply
    APIConfiguration.swift        # reads the (dev-only) API key from Info.plist
  ViewControllers/
    MainViewController.swift      # upload button + UIDocumentPickerViewController
    SummaryViewController.swift   # table view of the parsed summary
    FindingCell.swift             # one row per blood test value, with a color-coded flag
  Resources/
    Info.plist
    Local.xcconfig.example
backend-example/
  server.js                       # minimal proxy holding the API key server-side
```

## Getting it running

1. Open Xcode → **File → New → Project → iOS → App**. Name it
   `BloodTestSummarizer`, interface: **Storyboard is not needed** —
   uncheck "Use Storyboard" if offered, or just delete
   `Main.storyboard` if Xcode creates one (this project builds its UI
   entirely in code from `SceneDelegate`).
2. Delete the placeholder `AppDelegate.swift`, `SceneDelegate.swift`,
   and `Info.plist` Xcode generates, and drag in the folders above in
   their place (make sure "Copy items if needed" is checked).
3. Set the deployment target to iOS 17+ and the Swift Language Version
   to **Swift 6** in Build Settings.
4. Copy `Resources/Local.xcconfig.example` to `Resources/Local.xcconfig`,
   fill in an API key from the Anthropic Console, and add
   `Local.xcconfig` to your `.gitignore`. Wire it up in
   **Project → Info tab → Configurations** for the Debug configuration.
5. Build and run on a simulator or device (Files app access works on
   both). Tap **Upload Blood Test PDF**, pick a file, wait for the
   summary.

## A few things worth knowing about the API call itself

- PDFs are sent as a base64 `document` content block (Claude reads the
  actual layout/tables visually, not just extracted text) — see
  [Anthropic's PDF support docs](https://docs.claude.com/en/docs/build-with-claude/pdf-support).
- Anthropic's request-size limit is currently 32MB and 100 pages per
  request; `ClaudeAPIService` checks the byte size before sending.
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

Blood test PDFs are sensitive health data. This starter project sends
them straight to Anthropic's API and doesn't persist anything locally
or on the example backend — but if you build this out further, think
about whether you need encryption at rest, a data retention policy, and
whatever health-data regulations apply in your jurisdiction (e.g. HIPAA
in the US) before handling real patient data at any scale beyond your
own personal use.
