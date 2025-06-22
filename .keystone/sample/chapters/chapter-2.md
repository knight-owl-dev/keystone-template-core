# Markdown Formatting Capabilities

Keystone supports advanced formatting through [Pandoc's fenced div syntax](https://pandoc.org/MANUAL.html#extension-fenced_divs), using the form `::: div-name` and `:::`.

This lets you apply custom styling or behavior by wrapping sections of content in named blocks — like `::: dialog` for character conversations.

## Styled Dialog Blocks

Dialogs are useful for formatting conversations or character interactions in narrative text.
The `dialog` div works with standard Markdown bullet lists — each `-` line becomes a stylized dialog line in the output.

### Example Output Using Dialog Blocks

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

### Markdown Snippet Using Dialog Blocks

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

## Unstyled Dialog

> Do not mix **styled** and **unstyled dialog** in the same text. Pick one style and stick with it for consistency.

If you prefer not to use the dialog block, you can still format dialog in Markdown. This is useful for simple conversations or when you want to avoid the extra styling. Use double dashes (`--`) to indicate dialog lines, and separate them with line breaks or double spaces. This method is less visually distinct but can be more straightforward.

For example, you can write with double spaces or line breaks to separate dialog lines and use double dashes:

### Example Output Using Unstyled Dialog

-- Who’s there?  
-- Just the wind.  
-- The wind doesn’t knock.  

The door creaked open, but no one was there.

-- Are you sure we should be here?  
-- It’s too late to turn back now.  

## Dialog Prose

Prose-style dialog presents conversations in the flow of narrative paragraphs, rather than using bullet points or script formatting.

Each spoken line is wrapped in quotation marks and usually begins a new paragraph. This style is common in fiction, short stories, and novels. It allows dialog to blend naturally with narration, emotion, and pacing — ideal for immersive storytelling.

No special syntax is needed; just write your dialog using standard Markdown. The output will format it as prose.

**TIP:** Markdown treats paragraphs as blocks separated by either a blank line or two spaces at the end of a line. To separate dialog lines from surrounding text, use a blank line — it’s more reliable across editors and avoids issues with trailing whitespace being trimmed automatically.

### Example Output Using Line Breaks

The wind stirred the grass in slow, whispering waves.

"It's quiet," she said. "Too quiet."

He glanced at her, brow raised. "You always say that."

She smiled, the corners of her mouth tugged upward like a secret she'd just decided to share. "And I'm usually right."

The hilltop was empty. No birdsong. No trees creaking. Just the breeze, brushing past them like it had somewhere more important to be.

"Still think this is the right place?" he asked.

"For now," she said. "But stay close. Just in case."

They moved on.

Not quickly. Just... together.

### Example Output Using Double Spaces

The wind stirred the grass in slow, whispering waves.  
"It's quiet," she said. "Too quiet."  
He glanced at her, brow raised. "You always say that."  
She smiled, the corners of her mouth tugged upward like a secret she'd just decided to share. "And I'm usually right."  
The hilltop was empty. No birdsong. No trees creaking. Just the breeze, brushing past them like it had somewhere more important to be.  
"Still think this is the right place?" he asked.  
"For now," she said. "But stay close. Just in case."  
They moved on.  
Not quickly. Just... together.  

::: pagebreak
:::

## Using Custom LaTeX Inserts

> **Note:** LaTeX inserts are rendered only in **PDF output**. They will not appear in EPUB or DOCX.

Keystone supports embedded LaTeX for advanced formatting that goes beyond standard Markdown. This includes typesetting math, inserting symbols, and controlling layout — all inline with your content.

To restrict LaTeX content to PDF builds only, wrap it in a `::: latex-only` block. This ensures the content is excluded from other formats like EPUB or DOCX.

### Example Output Using LaTeX Inserts

> **Note:** If you see no table here, you're viewing it in another format. The table will be rendered in PDF output only.

::: latex-only
\begin{center}
\begin{tabular}{|c|c|}
  \hline
  \textbf{Feature} & \textbf{Supported?} \\
  \hline
  Markdown         & \tick \\
  LaTeX Inserts    & \tick \\
  Lua Filters      & \tick \\
  Dockerized Builds & \tick \\
  \hline
\end{tabular}
\end{center}
:::

### Markdown Snippet Using LaTeX Inserts

Here's the corresponding Markdown snippet for the LaTeX table:

```latex
::: latex-only
\begin{center}
\begin{tabular}{|c|c|}
  \hline
  \textbf{Feature} & \textbf{Supported?} \\
  \hline
  Markdown         & \tick \\
  LaTeX Inserts    & \tick \\
  Lua Filters      & \tick \\
  Dockerized Builds & \tick \\
  \hline
\end{tabular}
\end{center}
:::
```

The use of `::: latex-only` is a custom Keystone feature. It allows you to specify that the content inside the **div** should only be rendered in LaTeX output, not in other formats like DOCX or EPUB.

::: pagebreak
:::

## Including Images in Markdown

Markdown makes it easy to include images in your content. Just use the standard syntax:

```markdown
::: {#fig-keystone .figure}
![Keystone](assets/keystone-example.jpg){ width=25% }
:::
```

Which will render as:

::: {#fig-keystone .figure}
![Keystone](assets/keystone-example.jpg){ width=25% }
:::

::: pagebreak
:::

## Page Breaks

If you need to start a new page in your document, you can use the `::: pagebreak` directive. This is useful for separating sections or chapters in your output.

The page break will be rendered in PDF and EPUB output, but not in DOCX.

For example, to create a page break, you can write:

```markdown
::: pagebreak
:::

## My Sample Chapter

This is a new chapter that starts on a new page.
```

## Poem Dates

If you want to include dates in your poems, you can use the `::: poem-date` directive. This is useful for indicating when a poem was written or published while maintaining consistent formatting.

For example, to include a date in your poem, you can write:

```markdown
Line of the poem  
Line of the poem  

::: poem-date
2023-10-01
:::
```

Which renders as:

Line of the poem  
Line of the poem  

::: poem-date
2023-10-01
:::
