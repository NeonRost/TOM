# TOM

macOS menu bar and window app (SwiftUI, macOS 13+). The Xcode project is generated from `project.yml` with XcodeGen. The project is an open source repository on GitHub.

## README

`README.md` is written in English and contains parts that **must be preserved unchanged**, even when the file is otherwise rewritten:

- the repository image embeds (`<img src="images/TOM_Icon.png" …>` and `<img src="images/TOM_Screenshot.png" …>`) including their position, size and `alt` text
- the **Support** section with the Ko-fi link (https://ko-fi.com/neonrost)

Before editing the file, check that these parts are present, and make sure they are still there afterwards, unchanged. The images live in the `images/` folder.

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
