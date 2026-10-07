import SwiftUI

/// Start / end / duration fields kept in sync through `TimeRangeModel`.
/// Edits commit on Return or focus loss, so typing never fights the sync.
/// Invalid input reverts to the last valid value. Takes no initial focus.
struct TimeRangeEditor: View {
    @Binding var startMinutes: Int
    @Binding var durationMinutes: Int

    @Environment(\.theme) private var theme

    private enum Field: Hashable { case start, end, duration }

    @FocusState private var focus: Field?
    @State private var startText = ""
    @State private var endText = ""
    @State private var durationText = ""

    private var model: TimeRangeModel {
        TimeRangeModel(start: startMinutes, duration: durationMinutes)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            column("Start") {
                field($startText, .start, width: 60, alignment: .center)
            }
            column("End") {
                field($endText, .end, width: 60, alignment: .center)
            }
            column("Duration") {
                HStack(spacing: 4) {
                    field($durationText, .duration, width: 52, alignment: .trailing)
                    Text("min")
                        .font(.system(size: Theme.FontSize.caption))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .onAppear(perform: refresh)
        .onChange(of: startMinutes) { _, _ in refresh() }
        .onChange(of: durationMinutes) { _, _ in refresh() }
        .onChange(of: focus) { old, _ in
            if let old { commit(old) }
        }
    }

    private func column<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: Theme.FontSize.caption))
                .foregroundStyle(theme.textTertiary)
            content()
        }
    }

    private func field(_ text: Binding<String>, _ id: Field, width: CGFloat, alignment: TextAlignment) -> some View {
        TextField("", text: text)
            .focused($focus, equals: id)
            .frame(width: width)
            .multilineTextAlignment(alignment)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: Theme.FontSize.callout, design: .monospaced))
            .onSubmit { commit(id) }
    }

    private func commit(_ id: Field) {
        var m = model
        switch id {
        case .start:
            if let v = TimeRangeModel.parseTime(startText) { m.setStart(v) }
        case .end:
            if let v = TimeRangeModel.parseTime(endText) { m.setEnd(v) }
        case .duration:
            if let v = TimeRangeModel.parseDuration(durationText) { m.setDuration(v) }
        }
        startMinutes = m.start
        durationMinutes = m.duration
        refresh()
    }

    private func refresh() {
        let m = model
        startText = TimeRangeModel.format(m.start)
        endText = TimeRangeModel.format(m.end)
        durationText = String(m.duration)
    }
}
