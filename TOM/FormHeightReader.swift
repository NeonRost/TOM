// TOM – menu bar utility that keeps the Mac awake and simulates periodic key presses.
// Copyright (C) 2026 NeonRost
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import AppKit
import SwiftUI

// Eine gruppierte Form meldet SwiftUI keine Eigenhoehe. Ihre Inhaltshoehe steht
// aber im Dokument der zugrunde liegenden NSScrollView – unabhaengig davon, wie
// gross das Fenster gerade ist. Dieser View beobachtet sie, damit sich das
// Fenster an den Inhalt anpasst, ohne gemessene Festwerte pro Zeile.
// Als .background(...) an die Form haengen.
struct FormHeightReader: NSViewRepresentable {
    @Binding var height: CGFloat

    func makeNSView(context: Context) -> ReaderView {
        ReaderView()
    }

    func updateNSView(_ nsView: ReaderView, context: Context) {
        // Die Meldung kommt mitten aus dem Layout der Form; eine Aenderung des
        // States dort ginge verloren. Deshalb erst im naechsten Durchlauf setzen.
        let binding = $height
        nsView.onChange = { newHeight in
            DispatchQueue.main.async {
                if abs(newHeight - binding.wrappedValue) > 0.5 { binding.wrappedValue = newHeight }
            }
        }
        nsView.attachIfNeeded()
    }

    final class ReaderView: NSView {
        var onChange: ((CGFloat) -> Void)?

        private weak var scrollView: NSScrollView?
        private var retries = 0
        private var frameObservers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attachIfNeeded()
        }

        func attachIfNeeded() {
            // Beim Umschalten zwischen Haupt- und Setup-Seite kann die alte Form
            // noch kurz im Fenster haengen; verschwindet sie, neu suchen.
            if let scrollView, scrollView.window == nil { detach() }
            guard scrollView == nil, window != nil else { return }
            // Die Form legt ihre Scroll-View und deren Dokument unter Umstaenden
            // erst ein paar Durchlaeufe spaeter an.
            guard let found = scrollViewBehindSelf(), let document = found.documentView else {
                retryLater()
                return
            }
            retries = 0
            scrollView = found
            document.postsFrameChangedNotifications = true
            found.postsFrameChangedNotifications = true
            frameObservers = [document, found].map { view in
                NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification, object: view, queue: .main
                ) { [weak self] _ in
                    self?.report()
                }
            }
            report()
        }

        // Auch die eigene Groesse geht in die Rechnung ein.
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            report()
        }

        private func detach() {
            frameObservers.forEach(NotificationCenter.default.removeObserver)
            frameObservers = []
            scrollView = nil
        }

        private func retryLater() {
            guard retries < 50 else { return }
            retries += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                self?.attachIfNeeded()
            }
        }

        private func report() {
            guard let scrollView else { return }
            guard scrollView.window != nil, let document = scrollView.documentView else {
                detach()
                attachIfNeeded()
                return
            }
            // Im Fenster reicht die Scroll-View oben unter die Titelleiste und
            // gleicht das mit einem contentInset aus. Fuer das Dokument sichtbar
            // ist ihre Hoehe abzueglich der Insets; gesucht ist die Hoehe der
            // Form (= dieses Views), bei der das genau der Dokumenthoehe entspricht.
            let insets = scrollView.contentInsets
            let overhang = scrollView.frame.height - bounds.height
            // Mitten im Layout passen die Rahmen kurz nicht zusammen; der
            // naechste Aufruf bringt den stimmigen Stand.
            guard overhang >= 0 else { return }
            onChange?(ceil(document.frame.height + insets.top + insets.bottom - overhang))
        }

        // Als Hintergrund hat dieser View denselben Rahmen wie die Form. Gesucht
        // ist also die Scroll-View, die im Fenster genau an dieser Stelle liegt.
        private func scrollViewBehindSelf() -> NSScrollView? {
            guard let root = window?.contentView else { return nil }
            let target = convert(bounds, to: nil)
            var best: (view: NSScrollView, distance: CGFloat)?
            for candidate in Self.scrollViews(in: root) {
                let frame = candidate.convert(candidate.bounds, to: nil)
                // Oben reicht die Scroll-View unter die Titelleiste, daher nur
                // links, rechts und unten vergleichen.
                guard frame.maxY >= target.maxY - 1 else { continue }
                let distance = abs(frame.minX - target.minX) + abs(frame.maxX - target.maxX)
                    + abs(frame.minY - target.minY)
                if distance < (best?.distance ?? 4) { best = (candidate, distance) }
            }
            return best?.view
        }

        private static func scrollViews(in view: NSView) -> [NSScrollView] {
            if let scrollView = view as? NSScrollView { return [scrollView] }
            return view.subviews.flatMap(scrollViews(in:))
        }

        deinit {
            detach()
        }
    }
}
