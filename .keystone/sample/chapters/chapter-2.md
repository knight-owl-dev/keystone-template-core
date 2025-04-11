# Markdown Formatting Capabilities

Keystone supports advanced formatting through [Pandoc's fenced div syntax](https://pandoc.org/MANUAL.html#extension-fenced_divs), using the form `::: div-name` and `:::`.

This lets you apply custom styling or behavior by wrapping sections of content in named blocks — like `::: dialog` for character conversations.

## Dialog Blocks

Dialogs are useful for formatting conversations or character interactions in narrative text.
The `dialog` div works with standard Markdown bullet lists — each `-` line becomes a stylized dialog line in the output.

### Example Output

::: dialog

- Who’s there?
- Just the wind.
- The wind doesn’t knock.
:::

The door creaked open, but no one was there.

::: dialog

- Are you sure we should be here?
- It’s too late to turn back now.
:::

### Markdown Snippet

Here’s the Markdown you’d write:

```markdown
::: dialog

- Who’s there?
- Just the wind.
- The wind doesn’t knock.
:::

The door creaked open, but no one was there.

::: dialog

- Are you sure we should be here?
- It’s too late to turn back now.
:::
```

**Spacing and line breaks matter** — the dialog block must be separated from surrounding text to render correctly. If you need to insert regular prose between dialog lines, **close the dialog div** (`:::`), add your text, and then **reopen the dialog** with `::: dialog`.

## Dialog Prose

Prose-style dialog presents conversations in the flow of narrative paragraphs, rather than using bullet points or script formatting.

Each spoken line is wrapped in quotation marks and usually begins a new paragraph. This style is common in fiction, short stories, and novels. It allows dialog to blend naturally with narration, emotion, and pacing — ideal for immersive storytelling.

No special syntax is needed; just write your dialog using standard Markdown. The output will format it as prose.

**TIP:** Markdown treats paragraphs as blocks separated by either a blank line or two spaces at the end of a line. To separate dialog lines from surrounding text, use a blank line — it’s more reliable across editors and avoids issues with trailing whitespace being trimmed automatically.

### Whispers on the Ridge (Using Line Breaks)

The wind stirred the grass in slow, whispering waves.

"It's quiet," she said. "Too quiet."

He glanced at her, brow raised. "You always say that."

She smiled, the corners of her mouth tugged upward like a secret she'd just decided to share. "And I'm usually right."

The hilltop was empty. No birdsong. No trees creaking. Just the breeze, brushing past them like it had somewhere more important to be.

"Still think this is the right place?" he asked.

"For now," she said. "But stay close. Just in case."

They moved on.

Not quickly. Just... together.

### Whispers on the Ridge (Using Space)

The wind stirred the grass in slow, whispering waves.  
"It's quiet," she said. "Too quiet."  
He glanced at her, brow raised. "You always say that."  
She smiled, the corners of her mouth tugged upward like a secret she'd just decided to share. "And I'm usually right."  
The hilltop was empty. No birdsong. No trees creaking. Just the breeze, brushing past them like it had somewhere more important to be.  
"Still think this is the right place?" he asked.  
"For now," she said. "But stay close. Just in case."  
They moved on.  
Not quickly. Just... together.  
