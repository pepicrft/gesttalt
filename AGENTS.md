# Gesttalt development instructions

## Changelog

- Keep the public changelog current. Every change that affects what users can see or do must add or update an entry under `priv/changelog`.
- Name entries `YYYY-MM-DD-slug.md`, explain what changed and why it matters, and reserve the changelog for user-facing changes rather than internal maintenance.

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
