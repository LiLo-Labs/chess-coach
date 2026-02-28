import SwiftUI

// MARK: - Acknowledgments / Open Source Licenses

struct AcknowledgmentsView: View {
    var body: some View {
        List {
            Section {
                Text("Chess Coach is built on the shoulders of great open-source work. Thank you to every author and contributor listed here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }

            ForEach(License.all) { license in
                LicenseRow(license: license)
            }
        }
        .navigationTitle("Acknowledgments")
        .navigationBarTitleDisplayMode(.large)
        .preferredColorScheme(.dark)
    }
}

// MARK: - License Row

private struct LicenseRow: View {
    let license: License
    @State private var isExpanded = false

    var body: some View {
        Section {
            // Header button — tap to expand/collapse
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: AppSpacing.md) {
                    VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                        Text(license.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColor.primaryText)

                        Text(license.copyright)
                            .font(.caption)
                            .foregroundStyle(AppColor.secondaryText)

                        HStack(spacing: AppSpacing.xs) {
                            PillBadge(text: license.spdx, color: AppColor.info)
                            if let note = license.note {
                                PillBadge(text: note, color: AppColor.warning)
                            }
                        }
                        .padding(.top, AppSpacing.xxxs)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.tertiaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Collapsible full license text
            if isExpanded {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(license.text)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(AppColor.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppSpacing.sm)
                }
                .frame(maxHeight: 260)
                .background(AppColor.elevatedBackground, in: RoundedRectangle(cornerRadius: AppRadius.sm))
                .listRowInsets(EdgeInsets(top: 4, leading: AppSpacing.lg, bottom: AppSpacing.sm, trailing: AppSpacing.lg))
            }
        }
    }
}

// MARK: - License Model

private struct License: Identifiable {
    let id: String
    let name: String
    let copyright: String
    let spdx: String
    let note: String?
    let text: String

    static let all: [License] = [
        chessKit,
        chessboardKit,
        chessKitEngine,
        llamaCpp,
        onnxRuntime,
    ]
}

// MARK: - Individual Licenses

// swiftlint:disable line_length
private extension License {

    // MARK: ChessKit

    static let chessKit = License(
        id: "chesskit",
        name: "ChessKit",
        copyright: "Copyright (c) 2020 Alexander Perechnev",
        spdx: "MIT",
        note: nil,
        text: """
MIT License

Copyright (c) 2020 Alexander Perechnev

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""
    )

    // MARK: ChessboardKit

    static let chessboardKit = License(
        id: "chessboardkit",
        name: "ChessboardKit",
        copyright: "Copyright (c) 2025 Oğuzhan Eroğlu <rohanrhu2@gmail.com>",
        spdx: "MIT",
        note: nil,
        text: """
MIT License

Copyright (c) 2025 Oğuzhan Eroğlu <rohanrhu2@gmail.com>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""
    )

    // MARK: ChessKitEngine

    static let chessKitEngine = License(
        id: "chesskitengine",
        name: "ChessKitEngine",
        copyright: "Copyright (c) 2023 ChessKit (https://github.com/chesskit-app)",
        spdx: "MIT",
        note: "Wraps GPL engines",
        text: """
MIT License

Copyright (c) 2023 ChessKit (https://github.com/chesskit-app)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

---

Note: ChessKitEngine links against Stockfish and/or Lc0, which are
distributed under the GNU General Public License v3. The GPL requires
that derivative works also be distributed under the GPL. For the full
terms of the GPL, see https://www.gnu.org/licenses/gpl-3.0.html
"""
    )

    // MARK: llama.cpp

    static let llamaCpp = License(
        id: "llamacpp",
        name: "llama.cpp",
        copyright: "Copyright (c) 2023 Georgi Gerganov",
        spdx: "MIT",
        note: nil,
        text: """
MIT License

Copyright (c) 2023 Georgi Gerganov

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""
    )

    // MARK: ONNX Runtime

    static let onnxRuntime = License(
        id: "onnxruntime",
        name: "ONNX Runtime",
        copyright: "Copyright (c) Microsoft Corporation",
        spdx: "MIT",
        note: nil,
        text: """
MIT License

Copyright (c) Microsoft Corporation

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""
    )
}
// swiftlint:enable line_length
