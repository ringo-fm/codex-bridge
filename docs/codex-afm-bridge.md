# Codex Apple Foundation Models Bridge Design

## Conclusion

`codex-afm-bridge` is an OpenAI Responses API compatibility server for Codex that uses Apple Foundation Models internally.

The intended architecture is:

```text
Codex
  -> OpenAI Responses API compatible local HTTP server
    -> Swift daemon
      -> Apple Foundation Models
```

This is not a full OpenAI API implementation. It is a Codex-oriented minimal compatibility layer whose first goal is to make Apple Foundation Models usable as a local Codex model provider.

## Goals

- Expose a local OpenAI Responses API-compatible endpoint to Codex.
- Implement the smallest useful subset of `/v1/responses` first.
- Use Swift and Apple's Foundation Models framework internally.
- Keep all model execution local to the Apple device.
- Preserve Codex as the executor for shell, patch, approval, and sandbox behavior.
- Avoid making the bridge itself a shell executor.

## Non-goals

- Full OpenAI API compatibility.
- Replacing GPT-class coding models with guaranteed equivalent quality.
- Implementing Chat Completions first.
- Implementing remote hosting or multi-user deployment.
- Executing shell commands inside the bridge.
- Treating Apple Foundation Models as if they natively speak OpenAI Responses API.

## High-level architecture

```text
Codex CLI / IDE
  ↓ OpenAI Responses API compatible HTTP
codex-afm-bridge
  ├─ HTTP Adapter
  │   ├─ POST /v1/responses
  │   ├─ GET  /v1/responses/{id}
  │   ├─ GET  /v1/models
  │   └─ optional: POST /v1/responses/{id}/cancel
  │
  ├─ Responses Translator
  │   ├─ OpenAI input[] -> AFM transcript
  │   ├─ instructions/system/developer -> AFM instructions
  │   ├─ stream=true -> SSE events
  │   └─ AFM output -> OpenAI response object
  │
  ├─ AFM Runtime
  │   ├─ LanguageModelSession pool
  │   ├─ availability check
  │   ├─ prewarm
  │   ├─ generation options
  │   └─ cancellation
  │
  └─ Compatibility Layer
      ├─ text-only mode
      ├─ function/tool-call mode
      ├─ unsupported feature fallback
      └─ diagnostics
```

Recommended implementation:

```text
Codex -> Swift daemon -> FoundationModels
```

Prototype implementation:

```text
Codex -> Node/Rust HTTP server -> Swift CLI -> FoundationModels
```

The Swift daemon is preferred because it can keep sessions warm, stream responses, support cancellation, and maintain a small session pool.

## Codex configuration

Example `~/.codex/config.toml`:

```toml
model = "apple-foundation-local"
model_provider = "apple_fm"

model_reasoning_summary = "none"
model_supports_reasoning_summaries = false

[model_providers.apple_fm]
name = "Apple Foundation Models Local Bridge"
base_url = "http://127.0.0.1:8765/v1"
wire_api = "responses"
env_key = "AFM_BRIDGE_API_KEY"
request_max_retries = 0
stream_max_retries = 0
stream_idle_timeout_ms = 600000
supports_websockets = false
```

The bridge should require:

```text
Authorization: Bearer $AFM_BRIDGE_API_KEY
```

## API surface

### Required for MVP

```http
GET  /health
GET  /v1/models
POST /v1/responses
GET  /v1/responses/{id}
```

### Optional after MVP

```http
POST /v1/responses/{id}/cancel
POST /v1/responses/{id}/input_items
```

### Deferred

```http
POST /v1/responses/compact
GET  /v1/conversations/*
WebSocket transport
batch
file upload
embeddings
image generation
```

## `/v1/models`

Return a small static model list:

```json
{
  "object": "list",
  "data": [
    {
      "id": "apple-foundation-local",
      "object": "model",
      "created": 0,
      "owned_by": "apple-foundation-models-local"
    }
  ]
}
```

Additional aliases can be supported later:

```text
apple-foundation-local
apple-foundation-fast
apple-foundation-structured
```

## `/v1/responses` input subset

MVP supports:

```json
{
  "model": "apple-foundation-local",
  "instructions": "You are a coding assistant.",
  "input": [
    {
      "role": "user",
      "content": [
        { "type": "input_text", "text": "Explain this repository." }
      ]
    }
  ],
  "stream": true
}
```

Field behavior:

| OpenAI Responses field | Bridge behavior |
|---|---|
| `model` | Accept `apple-foundation-local`; reject unsupported models |
| `instructions` | Convert into AFM session instructions |
| `input: string` | Convert to one user message |
| `input[].role` | Convert role into transcript text |
| `input_text` | Supported |
| `input_image` | Reject in v0; possible future Vision integration |
| `input_file` | Reject in v0, except explicit text payload support later |
| `stream` | Convert AFM streaming to SSE |
| `temperature` | Best-effort mapping to AFM generation options |
| `max_output_tokens` | Best-effort mapping to AFM generation limit |
| `reasoning` | Ignore or record in diagnostics |
| `tools` | Reject in v0; staged support later |

## Output object

Non-streaming minimal response:

```json
{
  "id": "resp_afm_01J...",
  "object": "response",
  "created_at": 1781770000,
  "status": "completed",
  "model": "apple-foundation-local",
  "output": [
    {
      "id": "msg_afm_01J...",
      "type": "message",
      "status": "completed",
      "role": "assistant",
      "content": [
        {
          "type": "output_text",
          "text": "Repository summary...",
          "annotations": []
        }
      ]
    }
  ],
  "usage": {
    "input_tokens": 1234,
    "output_tokens": 321,
    "total_tokens": 1555
  }
}
```

If exact token usage is unavailable, estimate usage and include a diagnostic marker such as:

```http
x-afm-usage-estimated: true
```

## Streaming

When `stream: true`, return Server-Sent Events compatible with Responses API text streaming.

Minimum event sequence:

```text
event: response.created
data: {"type":"response.created","response":{...}}

event: response.in_progress
data: {"type":"response.in_progress","response":{...}}

event: response.output_item.added
data: {"type":"response.output_item.added","output_index":0,"item":{...}}

event: response.content_part.added
data: {"type":"response.content_part.added","output_index":0,"content_index":0,"part":{"type":"output_text","text":""}}

event: response.output_text.delta
data: {"type":"response.output_text.delta","output_index":0,"content_index":0,"delta":"text chunk"}

event: response.output_text.done
data: {"type":"response.output_text.done","output_index":0,"content_index":0,"text":"full text"}

event: response.completed
data: {"type":"response.completed","response":{...}}
```

The MVP only needs to make text delta streaming stable.

## Prompt mapping

OpenAI-style priority levels should be flattened into a stable AFM prompt format.

Template:

```text
You are responding through an OpenAI Responses API compatibility bridge for Codex.

Priority rules:
1. System and developer instructions are higher priority than user instructions.
2. Do not claim access to tools unless a tool is provided.
3. If a tool call is needed but unsupported, explain the exact limitation.

System instructions:
...

Developer instructions:
...

Conversation:
[user] ...
[assistant] ...
[user] ...
```

This keeps OpenAI role semantics explicit even though AFM is not natively an OpenAI Responses API model.

## Internal Swift interfaces

```swift
struct AFMGenerateRequest {
    let responseID: String
    let model: String
    let instructions: String?
    let transcript: [AFMMessage]
    let stream: Bool
    let temperature: Double?
    let maxOutputTokens: Int?
    let tools: [AFMToolSpec]
}

struct AFMMessage {
    let role: AFMRole
    let text: String
}

enum AFMRole {
    case system
    case developer
    case user
    case assistant
}

struct AFMGenerateResult {
    let text: String
    let usage: AFMUsage?
    let finishReason: String
}
```

Pseudo entrypoint:

```swift
@main
struct CodexAFMBridge {
    static func main() async throws {
        let config = BridgeConfig.load()

        let afm = AFMRuntime()
        try await afm.checkAvailability()

        let server = HTTPServer(
            host: "127.0.0.1",
            port: config.port,
            routes: Routes(afm: afm),
            authToken: config.authToken
        )

        try await server.run()
    }
}
```

Pseudo `/v1/responses` handler:

```swift
func createResponse(_ http: HTTPRequest) async throws -> HTTPResponse {
    let request = try JSONDecoder().decode(ResponsesCreateRequest.self, from: http.body)

    guard request.model == "apple-foundation-local" else {
        throw OpenAIError.unsupportedModel(request.model)
    }

    let normalized = try InputNormalizer.normalize(request)
    let prompt = PromptBuilder.build(from: normalized)

    if request.stream == true {
        return try await streamResponse(request: request, prompt: prompt)
    } else {
        let result = try await afm.generate(prompt)
        let response = OutputMapper.toResponsesObject(
            request: request,
            result: result
        )
        return .json(response)
    }
}
```

## Tool calling strategy

Tool calling is the hardest part. It should be staged.

### v0: text-only

```text
Purpose:
  Allow Codex to use Apple FM as a local text model provider.

Supported:
  output_text only.

Unsupported:
  shell, patch, MCP, structured tool calls.
```

### v1: function-call compatibility

```text
OpenAI function tool
  -> BridgeToolSpec
  -> Apple FM Tool
  -> AFM tool decision
  -> Responses API function_call item
```

Example output item:

```json
{
  "id": "fc_afm_01J...",
  "type": "function_call",
  "status": "completed",
  "call_id": "call_afm_01J...",
  "name": "read_file",
  "arguments": "{"path":"README.md"}"
}
```

### v2: Codex coding-agent compatibility

Codex-specific shell and patch operations should remain Codex-managed.

```text
AFM:
  Decides that a command or patch is needed.

Bridge:
  Converts that intent into a Responses API item.

Codex:
  Handles approval, sandboxing, execution, and file writes.
```

The bridge must not execute shell commands directly.

## Error format

Use OpenAI-compatible error objects:

```json
{
  "error": {
    "message": "Apple Foundation Models are not available on this device.",
    "type": "afm_unavailable",
    "param": null,
    "code": "afm_unavailable"
  }
}
```

Error codes:

| code | Meaning |
|---|---|
| `afm_unavailable` | Apple Foundation Models unavailable on this device |
| `unsupported_model` | Requested model is unsupported |
| `unsupported_input_type` | Image, file, audio, or other unsupported input type |
| `unsupported_tool_type` | Tool type unsupported by current compatibility profile |
| `unsupported_language_or_locale` | AFM rejected language or locale |
| `generation_cancelled` | Request was cancelled |
| `generation_failed` | AFM generation failed |
| `context_too_large` | Input exceeded supported context size |

## Security

```text
bind:
  127.0.0.1 only

auth:
  Authorization: Bearer $AFM_BRIDGE_API_KEY required

network:
  Bridge does not make external network calls by default

logs:
  Do not persist prompts or responses by default
  Debug logging must be explicit opt-in

tool execution:
  Bridge does not execute shell commands
  Shell/patch intent is returned to Codex only

file access:
  Reject remote file URLs by default
  Support explicit text payloads or local allowlists only
```

## Repository layout

```text
codex-afm-bridge/
  Package.swift
  Sources/
    CodexAFMBridge/
      main.swift

      HTTP/
        Server.swift
        Routes.swift
        SSEWriter.swift
        AuthMiddleware.swift

      OpenAI/
        ResponsesRequest.swift
        ResponsesResponse.swift
        ResponsesEvents.swift
        ResponsesError.swift
        ModelsResponse.swift

      Translate/
        InputNormalizer.swift
        PromptBuilder.swift
        OutputMapper.swift
        ToolMapper.swift

      AFM/
        AFMRuntime.swift
        AFMSessionPool.swift
        AFMAvailability.swift
        AFMGeneration.swift
        AFMTools.swift

      Compat/
        CompatibilityProfile.swift
        FeatureFlags.swift
        Diagnostics.swift

  Tests/
    CodexAFMBridgeTests/
      ResponsesTextTests.swift
      StreamingTests.swift
      ErrorTests.swift
      PromptMappingTests.swift
      ToolMappingTests.swift

  examples/
    codex-config.toml
    curl-response.sh
    curl-stream.sh
```

## Compatibility profile

MVP:

```yaml
profile: codex-minimal
features:
  text: true
  stream: true
  usage: estimated
  images: false
  files: text-only
  function_call: false
  shell_call: false
  apply_patch_call: false
  mcp: false
  reasoning_items: false
  encrypted_reasoning: false
```

Future tool profile:

```yaml
profile: codex-tools
features:
  text: true
  stream: true
  function_call: true
  shell_call: synthetic
  apply_patch_call: synthetic
  mcp: passthrough-limited
```

## Implementation phases

### Phase 1: local text provider

```text
1. Start Swift daemon.
2. Implement /health.
3. Implement /v1/models.
4. Implement non-streaming POST /v1/responses.
5. Add Codex custom provider config.
6. Confirm Codex can receive a simple answer from Apple FM.
```

### Phase 2: streaming

```text
1. Convert AFM stream to SSE.
2. Emit response.output_text.delta.
3. Emit response.output_text.done.
4. Emit response.completed.
5. Add cancellation support.
```

### Phase 3: Codex request compatibility

```text
1. Capture actual Codex request bodies.
2. Record unsupported fields in diagnostics.
3. Classify ignored fields vs hard errors.
4. Tune the compatibility profile.
```

### Phase 4: tool-call experiments

```text
1. Support function_call only.
2. Start with read-only tools.
3. Represent shell/apply_patch as synthetic call items.
4. Leave execution, approval, and sandboxing to Codex.
```

## Acceptance criteria

MVP is complete when:

```text
Codex uses model_provider = apple_fm
↓
Codex sends a normal prompt
↓
codex-afm-bridge receives POST /v1/responses
↓
Apple Foundation Models generates the response
↓
The bridge returns a valid Responses API object or text SSE stream
↓
Codex displays the result
```

## Design judgment

```text
MVP:
  Worth implementing.
  /v1/responses text + stream is enough to validate the idea.

Full coding-agent compatibility:
  Requires shell/apply_patch/tool_call compatibility.
  This is the main hard part.

Core rule:
  The bridge translates model output.
  The bridge does not execute commands.
  Codex remains responsible for execution, approval, and sandboxing.
```
