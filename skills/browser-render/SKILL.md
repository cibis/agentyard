---
name: browser-render
description: Render any website URL as a visual screenshot inline in the chat. Use whenever the user asks to see, show, open, preview, or render a page.
---

# Browser Render Skill

Render any URL as an inline screenshot in the chat window using the browser tool.

## When to use

- User says "show me", "open", "render", "preview", "screenshot", "what does X look like"
- User pastes a URL and wants to see the page
- You need to verify how a page looks after making changes

## URL Translation (REQUIRED before navigating)

You run inside Docker. Always translate URLs before passing them to the browser tool:

| User says | Use instead |
|---|---|
| `http://localhost:9081/...` | `http://host.docker.internal:9081/...` |
| `http://localhost:9080/...` | `http://host.docker.internal:9080/...` |
| `http://localhost:<any-port>` | `http://host.docker.internal:<any-port>` |

External URLs (https://example.com, etc.) need no translation.

## Step-by-step

### 1. Open the page

```
browser tool — action: "open", url: "<translated-url>"
```

### 2. Take a full-page screenshot

```
browser tool — action: "screenshot", fullPage: true
```

The screenshot is returned as an inline image in the chat automatically.

### 3. Optional — labeled snapshot for interaction

If the user wants to interact with the page (click, fill forms, etc.), use a labeled snapshot instead:

```
browser tool — action: "snapshot", labels: true
```

This returns both the element tree (for `act` commands) and a labeled screenshot showing numbered element refs.

## Compact one-liner pattern

For simple "show me this page" requests, open and screenshot in two sequential tool calls. Do not narrate between them — just show the image.

## After rendering

- **Always tell the user:** *"The screenshot is visible in the tool result above."* The UI renders it directly — the user sees it even if you cannot process the image.
- Never say you cannot display the screenshot. You don't need to see it for the user to see it.
- Always report the final URL so the user knows what page loaded.
- If the user wants to interact (click, fill forms), take a labeled snapshot: `action: "snapshot", labels: true` and use the numbered refs with `act`.

---

## Vision bridge — when you need to understand the page

If the user asks questions about the page content and you cannot process the screenshot image, run:

```bash
bash /app/skills/agentyard/browser-render/vision-bridge.sh <translated-url>
```

This screenshots the URL with system chromium, sends the image to Claude Haiku (vision), and returns a plain-text description you can read and reason about.

**When to use:**
- User asks "what's on this page?", "does it look correct?", "what does the error say?"
- You need to extract text, form fields, or layout details from the page

**When NOT to use:**
- User just wants to see the page → `browser screenshot` is enough (they see the tool card)
- Page is already open and you just need interactive refs → use `snapshot` with `labels: true`
