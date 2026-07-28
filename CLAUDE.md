# TOM

macOS-Menüleisten- und Fenster-App (SwiftUI, macOS 13+). Xcode-Projekt wird von XcodeGen aus `project.yml` erzeugt.

## Mehrsprachigkeit

Die App ist mehrsprachig über `TOM/Localizable.xcstrings`. Basissprache ist **Englisch**, Übersetzungen bestehen für **Deutsch** und **Spanisch**.

Bei jeder Änderung an sichtbaren Texten müssen alle drei Sprachen mitgepflegt werden.

Am Ende jeder Aufgabe prüfen, ob unübersetzte Einträge zurückgeblieben sind, und diese melden.

### Hinweise zur Umsetzung

- Neue Texte im Code auf Englisch schreiben – das Literal ist zugleich der Schlüssel im Katalog.
- SwiftUI lokalisiert nur String-**Literale**. Texte, die über eine String-Variable in die Ansicht kommen (Tastenbezeichnungen, Maustasten, Fehlermeldungen), müssen ihre Übersetzung selbst per `String(localized:)` nachschlagen.
- Übersetzungen kurz halten: Beschriftungen dürfen nicht wesentlich länger werden als im Englischen, sonst bricht das Layout um. Besonders empfindlich sind Abschnittsüberschriften, Schalterbeschriftungen und die Intervall-Zeile.
- Unübersetzte Einträge findet man mit:
  ```sh
  python3 -c "import json;c=json.load(open('TOM/Localizable.xcstrings'));[print(k) for k,v in c['strings'].items() for l in ('de','es') if l not in v.get('localizations',{})]"
  ```

### In einer bestimmten Sprache starten (ohne Systemumstellung)

```sh
TOM.app/Contents/MacOS/TOM -AppleLanguages '(es)'
```
