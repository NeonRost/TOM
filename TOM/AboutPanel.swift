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

struct AboutView: View {
    @Environment(\.openWindow) private var openWindow

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text("TOM – Tuco on Meth")
                .font(.title3.bold())
            Text("Version \(version)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("TOM wird ohne jede Gewährleistung bereitgestellt. Weitergabe und Veränderung sind unter den Bedingungen der GNU GPL v3 gestattet.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Button("Lizenztext anzeigen") {
                openWindow(id: "license")
            }
            .buttonStyle(.link)
            .font(.caption)
            Text(copyright)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
        .padding(24)
        .frame(width: 300)
    }
}

struct LicenseView: View {
    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "Die LICENSE-Datei wurde im App-Bundle nicht gefunden. Der Lizenztext ist unter https://www.gnu.org/licenses/gpl-3.0.txt abrufbar."
        }
        return text
    }

    var body: some View {
        ScrollView {
            Text(licenseText)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .frame(minWidth: 540, idealWidth: 540, minHeight: 440, idealHeight: 480)
    }
}
