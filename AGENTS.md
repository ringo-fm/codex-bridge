# AGENTS.md

## Project

`codex-afm-bridge` — OpenAI Responses API compatibility server for Codex,
backed by Apple Foundation Models (on-device). Swift daemon using Hummingbird 2.

## Requirements

- macOS 26+ with Apple Intelligence enabled (for live inference)
- Xcode 26+ (full install, `xcode-select` pointing at `Xcode.app`)
- Swift 6.2+

## Layout

```
Sources/CodexAFMBridge/
  main.swift              entry point (top-level async)
  BridgeConfig.swift      env-driven config
  HTTP/                   Hummingbird server, routes, auth, SSE writer
  OpenAI/                 Responses API Codable types + errors
  Translate/              input normalization, prompt builder, output mapper
  AFM/                    FoundationModels runtime + availability
  Compat/                 compatibility profile + diagnostics
  Store/                  in-memory response store (GET /v1/responses/{id})
Tests/CodexAFMBridgeTests/  Swift Testing unit tests (pure logic)
examples/                 codex config + curl smoke scripts
```

## Verify commands

```bash
swift build                                    # build
swift test                                     # unit tests (pure logic, no model needed)
RUN_LIVE_FM_TESTS=1 swift test                 # + live inference (needs Apple Intelligence)
swift run codex-afm-bridge                     # start server on 127.0.0.1:8765
```

## Running the bridge

```bash
export AFM_BRIDGE_API_KEY=dev
swift run codex-afm-bridge
# AFM_BRIDGE_PORT (default 8765), AFM_BRIDGE_HOST (default 127.0.0.1)
# AFM_BRIDGE_LOG_LEVEL, AFM_BRIDGE_DEBUG
```

## Smoke tests

```bash
./examples/curl-response.sh    # non-streaming
./examples/curl-stream.sh      # SSE streaming
```

## Codex config

See `examples/codex-config.toml` — add the `apple_fm` provider and select
`model = "apple-foundation-local"`.

## Known limitations (v0 / codex-minimal)

- 4096-token context ceiling (`SystemLanguageModel.contextSize`) — long
  Codex sessions will hit `context_too_large`.
- text-only; no tool/shell/apply_patch execution. tools are ignored + recorded
  in diagnostics; images/files are rejected with `unsupported_input_type`.
- Token usage is estimated (`x-afm-usage-estimated: true`) unless
  `SystemLanguageModel.tokenCount(for:)` (macOS 26.4+) succeeds.
- Fresh `LanguageModelSession` per request (no session warmth / prewarm in MVP).
