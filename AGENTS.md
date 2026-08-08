# Gesttalt development instructions

## Writing

- Avoid acronyms. When one is necessary, include its full name and a link to a website that explains the concept.

## Elixir

- Minimize explicit raising patterns and raising function variants. Prefer pattern matching on tagged return values and function heads so invalid states fail where they are introduced.

## Tests

- Never modify global state from a test. This includes application environment changes such as `Application.put_env/3`.
- Pass configuration and dependencies directly to the code under test.
- Every Elixir test module must run with `async: true`.

## Changelog

- Keep the public changelog current. Every change that affects what users can see or do must add or update an entry under `priv/changelog`.
- Name entries `YYYY-MM-DD-slug.md`, explain what changed and why it matters, and reserve the changelog for user-facing changes rather than internal maintenance.
- Format entries for [NimblePublisher](https://github.com/dashbitco/nimble_publisher) with a metadata map containing `title` and `summary`, followed by `---` and the Markdown body.

## Cascading Style Sheets

- Give every route a single, stable identifier on its outermost rendered element.
- Give every reusable component a stable identifier. When a component can appear more than once, derive a unique identifier from its record or field identifier.
- Scope route and component styles from that identifier. Use native nested syntax and select internal structure through `data-part="..."` attributes.
- Keep `assets/css/app.css` as an import manifest. Put route styles in `assets/css/routes/<route>.css` and reusable component styles in `assets/css/components/<component>.css`.
- Keep only document-wide foundations, such as tokens and element normalization, in `assets/css/foundation.css`.
- Do not introduce page-specific selectors into foundations or style a component's internal structure from another route's file.

Example:

```css
#admin-media {
  & > [data-part="upload-form"] {
    display: grid;

    & > [data-part="field"] {
      gap: 0.35rem;
    }
  }
}
```

## GitHub pull requests

- Do not use em dashes in comments or reviews.
- Write comments and reviews as if Pepicrft wrote them directly. Do not frame them as assistant output unless explicitly requested.
- Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) for pull request titles in the form `type(gesttalt): summary`.
- Structure descriptions with the applicable headings `## What changed`, `## Why`, `## Root cause`, `## Approach`, `## Impact`, and `## Validation`.
- Use concise prose. Bullets are appropriate for concrete changes and validation, but the whole description should not be a terse file list.

## Web application verification

- Run the application locally and verify behavior with [headless Chrome](https://developer.chrome.com/docs/chromium/headless).
- Capture screenshots during verification.
- Include verification screenshots in the [GitHub pull request](https://docs.github.com/en/pull-requests) description. For fixes, include before and after screenshots.
