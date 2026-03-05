import SwiftUI

/// Settings screen — presets up front, Advanced hidden by default.
struct SettingsView: View {
    @StateObject private var vm = SettingsViewModel()
    @State private var showAdvanced = false

    var body: some View {
        NavigationStack {
            ZStack {
                TCColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: TCSpacing.lg) {
                        // ── Volume ──
                        settingsSection(
                            icon: "speaker.wave.2.fill",
                            title: "Volume",
                            hint: "Match this to how loudly you naturally speak."
                        ) {
                            presetRow(
                                options: VolumePreset.allCases,
                                selected: vm.volumePreset,
                                friendlySubtitle: volumeSubtitle,
                                onSelect: { vm.applyVolumePreset($0) }
                            )
                        }

                        // ── Speed ──
                        settingsSection(
                            icon: "metronome.fill",
                            title: "Speaking Speed",
                            hint: "135–185 wpm builds trust. Too fast loses them."
                        ) {
                            presetRow(
                                options: SpeedPreset.allCases,
                                selected: vm.speedPreset,
                                friendlySubtitle: speedSubtitle,
                                onSelect: { vm.applySpeedPreset($0) }
                            )
                        }

                        // ── Ending Tone ──
                        settingsSection(
                            icon: "arrow.down.right.circle.fill",
                            title: "Sentence Endings",
                            hint: "Ending low sounds authoritative. Ending high sounds uncertain."
                        ) {
                            HStack(spacing: TCSpacing.xs) {
                                toneButton(
                                    label: "Down",
                                    subtitle: "Authority",
                                    tone: .down,
                                    isSelected: vm.desiredEndingTone == .down
                                )
                                toneButton(
                                    label: "Up",
                                    subtitle: "Friendly",
                                    tone: .up,
                                    isSelected: vm.desiredEndingTone == .up
                                )
                            }
                        }

                        // ── Advanced ──
                        advancedSection

                        // ── Framework Reference ──
                        frameworkCard

                        // ── Reset ──
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                vm.resetToDefaults()
                            }
                        } label: {
                            Text("Reset to Recommended")
                                .font(TCFont.callout)
                                .foregroundStyle(TCColor.textSecondary)
                        }
                        .padding(.top, TCSpacing.xxs)

                        // ── Footer ──
                        VStack(spacing: TCSpacing.xxs) {
                            Text("ToneCoach v1.0")
                                .font(TCFont.caption)
                                .foregroundStyle(TCColor.textTertiary)
                            Text("All audio is processed on-device.")
                                .font(TCFont.caption)
                                .foregroundStyle(TCColor.textTertiary)
                        }
                        .padding(.bottom, TCSpacing.md)
                    }
                    .padding(.top, TCSpacing.sm)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Section Container

    private func settingsSection<Content: View>(
        icon: String,
        title: String,
        hint: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: TCSpacing.sm) {
            // Header
            HStack(spacing: TCSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(TCColor.accent)
                Text(title)
                    .font(TCFont.headline)
                    .foregroundStyle(TCColor.textPrimary)
            }

            Text(hint)
                .font(TCFont.caption)
                .foregroundStyle(TCColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            content()
        }
        .padding(TCSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: TCRadius.md)
                .fill(TCColor.surface)
        )
        .padding(.horizontal, TCSpacing.md)
    }

    // MARK: - Preset Row (generic)

    private func presetRow<P: SettingsPreset>(
        options: [P],
        selected: P?,
        friendlySubtitle: @escaping (P) -> String,
        onSelect: @escaping (P) -> Void
    ) -> some View {
        HStack(spacing: TCSpacing.xs) {
            ForEach(options, id: \.label) { option in
                let isSelected = option == selected
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        onSelect(option)
                    }
                } label: {
                    VStack(spacing: TCSpacing.xxxs) {
                        Text(option.label)
                            .font(TCFont.callout)
                            .foregroundStyle(isSelected ? .white : TCColor.textSecondary)
                        Text(friendlySubtitle(option))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(isSelected ? .white.opacity(0.7) : TCColor.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, TCSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: TCRadius.sm)
                            .fill(isSelected ? TCColor.accent : TCColor.surfaceAlt)
                    )
                }
            }
        }
    }

    // MARK: - Friendly Subtitles

    private func volumeSubtitle(_ preset: VolumePreset) -> String {
        switch preset {
        case .soft:   return "Quiet room"
        case .normal: return "Recommended"
        case .loud:   return "Noisy space"
        }
    }

    private func speedSubtitle(_ preset: SpeedPreset) -> String {
        switch preset {
        case .slow:   return "110–150 wpm"
        case .normal: return "135–185 wpm"
        case .fast:   return "160–210 wpm"
        }
    }

    // MARK: - Ending Tone Button

    private func toneButton(label: String, subtitle: String, tone: PhraseEndingTone, isSelected: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                vm.desiredEndingTone = tone
            }
        } label: {
            VStack(spacing: TCSpacing.xxxs) {
                Text(label)
                    .font(TCFont.callout)
                    .foregroundStyle(isSelected ? .white : TCColor.textSecondary)
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? .white.opacity(0.7) : TCColor.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, TCSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: TCRadius.sm)
                    .fill(isSelected ? TCColor.accent : TCColor.surfaceAlt)
            )
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(spacing: TCSpacing.sm) {
                Text("Override the preset ranges with exact values.")
                    .font(TCFont.caption)
                    .foregroundStyle(TCColor.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, TCSpacing.xxs)

                sliderRow(label: "Vol low",  value: $vm.targetDBMin,  range: -70...(-20), unit: "dB")
                sliderRow(label: "Vol high", value: $vm.targetDBMax,  range: -50...(-10), unit: "dB")

                Divider().background(TCColor.surfaceAlt)

                sliderRow(label: "Speed low",  value: $vm.targetWPMMin, range: 80...180, unit: "wpm")
                sliderRow(label: "Speed high", value: $vm.targetWPMMax, range: 100...220, unit: "wpm")
            }
        } label: {
            HStack(spacing: TCSpacing.xs) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13))
                    .foregroundStyle(TCColor.textTertiary)
                Text("Advanced")
                    .font(TCFont.headline)
                    .foregroundStyle(TCColor.textPrimary)
            }
        }
        .tint(TCColor.textTertiary)
        .padding(TCSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: TCRadius.md)
                .fill(TCColor.surface)
        )
        .padding(.horizontal, TCSpacing.md)
    }

    // MARK: - Slider Row

    private func sliderRow(label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        HStack(spacing: TCSpacing.xs) {
            Text(label)
                .font(TCFont.caption)
                .foregroundStyle(TCColor.textSecondary)
                .frame(width: 68, alignment: .leading)

            Slider(value: value, in: range)
                .tint(TCColor.accent)

            Text("\(Int(value.wrappedValue)) \(unit)")
                .font(TCFont.mono)
                .foregroundStyle(TCColor.textPrimary)
                .frame(width: 56, alignment: .trailing)
        }
    }

    // MARK: - Framework Card

    private var frameworkCard: some View {
        VStack(alignment: .leading, spacing: TCSpacing.xs) {
            Text("Tone Framework")
                .font(TCFont.caption)
                .foregroundStyle(TCColor.textTertiary)

            VStack(alignment: .leading, spacing: 6) {
                frameworkRow(text: "Volume — be heard clearly",          icon: "speaker.wave.2.fill")
                frameworkRow(text: "Speed — 135–185 wpm sweet spot",    icon: "metronome.fill")
                frameworkRow(text: "Articulation — round out every word", icon: "text.word.spacing")
                frameworkRow(text: "Pauses — let your points land",     icon: "pause.circle.fill")
                frameworkRow(text: "Pitch — end low for authority",      icon: "arrow.down.right.circle.fill")
            }
        }
        .padding(TCSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: TCRadius.md)
                .fill(TCColor.surface)
        )
        .padding(.horizontal, TCSpacing.md)
    }

    private func frameworkRow(text: String, icon: String) -> some View {
        HStack(spacing: TCSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(TCColor.accent)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TCColor.textSecondary)
        }
    }
}
