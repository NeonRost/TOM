# TOM

macOS menu bar and window app (SwiftUI, macOS 13+). The Xcode project is generated from `project.yml` with XcodeGen. The project is an open source repository on GitHub.

## README

`README.md` is written in English. Its layout follows the PhotoCraft style: a centered header (icon, tagline, badges, buttons, link row), a four-column table of advantages, and a two-column grid of feature cells, each with a screenshot, a one-line caption, a heading and text.

Parts that **must be preserved unchanged**, even when the file is otherwise rewritten:

- the two repository image embeds, `<img src="images/TOM_Icon.png" width="200" alt="TOM Icon">` and `<img src="images/TOM_Screenshot.png" width="400" alt="TOM Screenshot">`: the tags themselves (file, size, alt text) stay as they are; each sits in its own centered paragraph near the top, the icon first, the screenshot below the link row
- the **Support** section with the Ko-fi link (https://ko-fi.com/neonrost)

Before editing the file, check that these parts are present, and make sure they are still there afterwards, unchanged. All images live in the `images/` folder.

The feature grid uses `images/TOM_<Section>_dark.png` / `_light.png`, switched with a `<picture>` element. They are crops of the running app (English, one section each) and need to be retaken when a section's layout changes. GitHub does not render custom CSS: only tables, centered paragraphs and badges are available.

## Localization

The app is localized through `TOM/Localizable.xcstrings`. The base language is **English**; translations exist for **German** and **Spanish**.

Any change to user-visible text must be carried through all three languages.

At the end of every task, check whether untranslated entries are left behind, and report them.

### Implementation notes

- Write new text in the code in English – the literal doubles as the key in the catalog.
- SwiftUI only localizes string **literals**. Text that reaches the view through a String variable (key names, mouse buttons, error messages) has to look up its own translation via `String(localized:)`.
- Keep translations short: labels must not grow much longer than the English source, or the layout wraps. Section headers, switch labels and the interval row are the sensitive spots.
- Find untranslated entries with:
  ```sh
  python3 -c "import json;c=json.load(open('TOM/Localizable.xcstrings'));[print(k) for k,v in c['strings'].items() for l in ('de','es') if l not in v.get('localizations',{})]"
  ```

### Launching in a specific language (without changing system settings)

```sh
TOM.app/Contents/MacOS/TOM -AppleLanguages '(es)'
```
