# TOM – Tuco on Meth

Kleines macOS-Dienstprogramm mit Fenster und optionalem Menüleisten-Symbol. Zwei unabhängige Funktionen:

- **Computer wachhalten** – verhindert per IOKit Power Assertion, dass Bildschirm und System einschlafen. Keine Sonderrechte nötig.
- **Tastendruck simulieren** – sendet in wählbarer Frequenz (1–600 Sekunden) einen echten Tastendruck per `CGEvent`. Die Taste ist frei wählbar: Buchstaben, Zahlen, Pfeiltasten, Sondertasten (Leertaste, Enter, Strg, …) und die Funktionstasten F13–F19. Praktisch, um z. B. in Spielen als aktiv zu gelten.

Beide Funktionen laufen unabhängig voneinander; Einstellungen bleiben über Neustarts erhalten.

## Systemvoraussetzungen

- macOS 13 (Ventura) oder neuer
- Zum Bauen: Xcode 15+

## Bauen

Das Xcode-Projekt wird mit [XcodeGen](https://github.com/yonaskolb/XcodeGen) aus `project.yml` erzeugt, ist aber auch fertig generiert eingecheckt:

```sh
open TOM.xcodeproj
```

Dann in Xcode bauen und starten (⌘R). Nach Änderungen an `project.yml`:

```sh
brew install xcodegen   # falls noch nicht vorhanden
xcodegen generate
```

## Berechtigungen

- **Computer wachhalten:** keine.
- **Tastendruck simulieren:** benötigt die Berechtigung „Bedienungshilfen“ (Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen). Die App fragt beim ersten Einschalten danach und verlinkt direkt dorthin. Hinweis: Nach einem Neu-Build mit Ad-hoc-Signatur muss die Berechtigung ggf. neu erteilt werden (Häkchen aus- und wieder einschalten).

Die App läuft nicht sandboxed – für die `CGEvent`-Injektion erforderlich.

## Lizenz

Copyright (C) 2026 NeonRost

Dieses Programm ist freie Software, veröffentlicht unter der **GNU General Public License, Version 3** (oder nach deiner Wahl jeder späteren Version). Details in der Datei [LICENSE](LICENSE).
