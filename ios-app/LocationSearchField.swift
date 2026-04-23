import SwiftUI
import MapKit

/// A self-contained location input field with live autocomplete suggestions.
/// Drop it in anywhere you need a pickup or destination input.
///
/// Usage:
///   LocationSearchField(
///       icon: "location.north.line.fill",
///       iconColor: .blue,
///       label: "Pickup Location",
///       text: $pickupText,
///       onSelect: { completion in … }
///   ) {
///       // optional trailing content (e.g. "Use Current" button)
///   }
struct LocationSearchField<Trailing: View>: View {
    // MARK: - Inputs
    let icon: String
    let iconColor: Color
    let label: String
    @Binding var text: String
    var onSelect: (MKLocalSearchCompletion) -> Void
    @ViewBuilder var trailing: () -> Trailing

    // MARK: - Private state
    @StateObject private var search = LocationSearchService()
    @FocusState  private var isFocused: Bool
    @State private var showSuggestions = false

    // Convenience init for the common case with no trailing view
    init(
        icon: String,
        iconColor: Color = .gray,
        label: String,
        text: Binding<String>,
        onSelect: @escaping (MKLocalSearchCompletion) -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.label = label
        self._text = text
        self.onSelect = onSelect
        self.trailing = trailing
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Main input row ──────────────────────────────────────────
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 42)

                VStack(alignment: .leading, spacing: 6) {
                    Text(label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.gray.opacity(0.95))

                    TextField(
                        "",
                        text: $text,
                        prompt: Text("Enter location")
                            .foregroundColor(Color.gray.opacity(0.82))
                    )
                    .font(.system(size: 16, weight: .regular))
                    .minimumScaleFactor(0.85)
                    .truncationMode(.tail)
                    .lineLimit(1)
                    .foregroundStyle(Color.black.opacity(0.85))
                    .focused($isFocused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .onChange(of: text) { newValue in
                        search.queryFragment = newValue
                        showSuggestions = isFocused && !newValue.isEmpty
                    }
                    .onChange(of: isFocused) { focused in
                        showSuggestions = focused && !text.isEmpty
                    }
                }

                Spacer(minLength: 8)
                trailing()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: showSuggestions ? 0 : 24, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: showSuggestions ? 0 : 24, style: .continuous)
                    .stroke(Color.black.opacity(showSuggestions ? 0 : 0.04), lineWidth: 1)
            )
            .shadow(color: .black.opacity(showSuggestions ? 0 : 0.04), radius: 6, y: 2)

            // ── Suggestions dropdown ────────────────────────────────────
            if showSuggestions && !search.suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(search.suggestions.prefix(6), id: \.self) { suggestion in
                        Button {
                            text = suggestion.title + (suggestion.subtitle.isEmpty ? "" : ", \(suggestion.subtitle)")
                            showSuggestions = false
                            isFocused = false
                            search.queryFragment = ""
                            onSelect(suggestion)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.gray.opacity(0.5))
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Color.black.opacity(0.85))
                                        .lineLimit(1)

                                    if !suggestion.subtitle.isEmpty {
                                        Text(suggestion.subtitle)
                                            .font(.system(size: 13, weight: .regular))
                                            .foregroundStyle(Color.gray.opacity(0.75))
                                            .lineLimit(1)
                                    }
                                }

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if suggestion != search.suggestions.prefix(6).last {
                            Divider()
                                .padding(.leading, 58)
                        }
                    }
                }
                .background(Color.white)
                .overlay(
                    Rectangle()
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: 0, style: .continuous)
                )
                .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(showSuggestions ? 0.10 : 0.04), radius: showSuggestions ? 16 : 6, y: showSuggestions ? 8 : 2)
        .animation(.easeInOut(duration: 0.18), value: showSuggestions)
        .animation(.easeInOut(duration: 0.18), value: search.suggestions.count)
    }
}
