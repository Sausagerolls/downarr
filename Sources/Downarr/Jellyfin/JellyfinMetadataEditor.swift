import SwiftUI

/// Full metadata editor. Writes a raw-JSON patch so untouched DTO fields survive the POST.
struct JellyfinMetadataEditor: View {
    let item: JellyfinItem

    @EnvironmentObject private var jellyfin: JellyfinStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var originalTitle: String
    @State private var sortName: String
    @State private var overview: String
    @State private var tagline: String
    @State private var year: String
    @State private var premiere: Date
    @State private var hasPremiere: Bool
    @State private var communityRating: String
    @State private var criticRating: String
    @State private var officialRating: String
    @State private var genres: String
    @State private var studios: String
    @State private var tags: String
    @State private var productionLocations: String
    @State private var indexNumber: String
    @State private var parentIndexNumber: String
    @State private var providerIDs: [ProviderEntry]
    @State private var lockData: Bool
    @State private var lockedFields: Set<String>

    @State private var editorInfo: JellyfinMetadataEditorInfo?
    @State private var saving = false

    private struct ProviderEntry: Identifiable, Equatable {
        let id = UUID()
        var key: String
        var value: String
    }

    init(item: JellyfinItem) {
        self.item = item
        _name = State(initialValue: item.Name ?? "")
        _originalTitle = State(initialValue: item.OriginalTitle ?? "")
        _sortName = State(initialValue: item.ForcedSortName ?? item.SortName ?? "")
        _overview = State(initialValue: item.Overview ?? "")
        _tagline = State(initialValue: item.Taglines?.first ?? "")
        _year = State(initialValue: item.ProductionYear.map(String.init) ?? "")
        _premiere = State(initialValue: item.PremiereDate ?? Date())
        _hasPremiere = State(initialValue: item.PremiereDate != nil)
        _communityRating = State(initialValue: item.CommunityRating.map { String(format: "%.1f", $0) } ?? "")
        _criticRating = State(initialValue: item.CriticRating.map { String(format: "%.0f", $0) } ?? "")
        _officialRating = State(initialValue: item.OfficialRating ?? "")
        _genres = State(initialValue: (item.Genres ?? []).joined(separator: ", "))
        _studios = State(initialValue: (item.Studios?.compactMap(\.Name) ?? []).joined(separator: ", "))
        _tags = State(initialValue: (item.Tags ?? []).joined(separator: ", "))
        _productionLocations = State(initialValue: (item.ProductionLocations ?? []).joined(separator: ", "))
        _indexNumber = State(initialValue: item.IndexNumber.map(String.init) ?? "")
        _parentIndexNumber = State(initialValue: item.ParentIndexNumber.map(String.init) ?? "")
        let known = ["Imdb", "Tmdb", "Tvdb"]
        var entries = (item.ProviderIds ?? [:]).map { ProviderEntry(key: $0.key, value: $0.value) }
        for key in known where !entries.contains(where: { $0.key == key }) {
            entries.append(ProviderEntry(key: key, value: ""))
        }
        _providerIDs = State(initialValue: entries.sorted { $0.key < $1.key })
        _lockData = State(initialValue: item.LockData ?? false)
        _lockedFields = State(initialValue: Set(item.LockedFields ?? []))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Edit metadata").font(.headline)
                    Text(item.displayName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if item.isLocked {
                    Pill(text: "Item locked", tint: Theme.warning, icon: "lock.fill")
                }
            }
            .padding(14)
            .hairline()

            HSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        group("Titles") {
                            labelled("Title") { TextField("", text: $name) }
                            labelled("Original title") { TextField("", text: $originalTitle) }
                            labelled("Sort title") { TextField("", text: $sortName) }
                            labelled("Tagline") { TextField("", text: $tagline) }
                        }

                        group("Overview") {
                            TextEditor(text: $overview)
                                .font(.system(size: 11.5))
                                .frame(height: 130)
                                .padding(4)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                        }

                        group("Release") {
                            labelled("Year") { TextField("", text: $year).frame(width: 80) }
                            HStack {
                                Text("Premiere date")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 120, alignment: .leading)
                                Toggle("", isOn: $hasPremiere).labelsHidden()
                                DatePicker("", selection: $premiere, displayedComponents: .date)
                                    .labelsHidden()
                                    .disabled(!hasPremiere)
                                Spacer()
                            }
                            if item.kind == .episode {
                                labelled("Episode number") { TextField("", text: $indexNumber).frame(width: 80) }
                                labelled("Season number") { TextField("", text: $parentIndexNumber).frame(width: 80) }
                            }
                            if item.kind == .season {
                                labelled("Season number") { TextField("", text: $indexNumber).frame(width: 80) }
                            }
                        }

                        group("Ratings") {
                            labelled("Community rating") { TextField("", text: $communityRating).frame(width: 80) }
                            labelled("Critic rating") { TextField("", text: $criticRating).frame(width: 80) }
                            HStack {
                                Text("Parental rating")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 120, alignment: .leading)
                                Picker("", selection: $officialRating) {
                                    Text("None").tag("")
                                    ForEach(ratingOptions, id: \.self) { Text($0).tag($0) }
                                }
                                .labelsHidden()
                                .frame(width: 180)
                                Spacer()
                            }
                        }

                        group("Classification") {
                            labelled("Genres") { TextField("comma separated", text: $genres) }
                            labelled("Studios") { TextField("comma separated", text: $studios) }
                            labelled("Tags") { TextField("comma separated", text: $tags) }
                            labelled("Locations") { TextField("comma separated", text: $productionLocations) }
                        }

                        group("Provider IDs") {
                            ForEach($providerIDs) { $entry in
                                HStack {
                                    TextField("Provider", text: $entry.key)
                                        .frame(width: 110)
                                    TextField("ID", text: $entry.value)
                                        .font(.system(size: 11, design: .monospaced))
                                }
                            }
                            Button {
                                providerIDs.append(ProviderEntry(key: "", value: ""))
                            } label: {
                                Label("Add provider", systemImage: "plus")
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .padding(14)
                }
                .frame(minWidth: 420)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        group("Locking") {
                            Toggle("Lock this item (block automatic metadata refreshes)", isOn: $lockData)
                                .toggleStyle(.checkbox)
                                .font(.caption)
                            Divider()
                            Text("Lock individual fields")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(JellyfinLockableField.allCases) { field in
                                Toggle(field.label, isOn: Binding(
                                    get: { lockedFields.contains(field.rawValue) },
                                    set: { on in
                                        if on { lockedFields.insert(field.rawValue) }
                                        else { lockedFields.remove(field.rawValue) }
                                    }))
                                    .toggleStyle(.checkbox)
                                    .font(.caption)
                            }
                        }

                        group("Item") {
                            KeyValueRow(key: "Type", value: item.ItemType ?? "—")
                            KeyValueRow(key: "Jellyfin ID", value: item.Id)
                            KeyValueRow(key: "Path", value: item.Path ?? "—")
                            KeyValueRow(key: "Added", value: Fmt.dateTime(item.DateCreated))
                        }
                    }
                    .padding(14)
                }
                .frame(minWidth: 260, idealWidth: 300)
            }

            Divider()
            HStack {
                Text("Fields left blank are cleared on the server.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button {
                    Task { await save() }
                } label: {
                    if saving { ProgressView().controlSize(.small) } else { Text("Save") }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.jellyfin)
                .keyboardShortcut(.defaultAction)
                .disabled(saving)
            }
            .padding(14)
        }
        .frame(width: 960, height: 700)
        .task { editorInfo = await jellyfin.metadataEditorInfo(id: item.Id) }
    }

    private var ratingOptions: [String] {
        let fromServer = (editorInfo?.ParentalRatingOptions ?? []).compactMap(\.Name)
        if fromServer.isEmpty {
            return ["GB-U", "GB-PG", "GB-12", "GB-15", "GB-18", "G", "PG", "PG-13", "R", "NC-17",
                    "TV-G", "TV-PG", "TV-14", "TV-MA"]
        }
        var options = fromServer
        if let current = item.OfficialRating, !current.isEmpty, !options.contains(current) {
            options.insert(current, at: 0)
        }
        return options
    }

    @ViewBuilder
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            content()
        }
        .card()
    }

    @ViewBuilder
    private func labelled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            content()
        }
    }

    private func save() async {
        saving = true
        var changes: [String: JSONValue] = [
            "Name": .string(name),
            "OriginalTitle": originalTitle.isEmpty ? .null : .string(originalTitle),
            "ForcedSortName": sortName.isEmpty ? .null : .string(sortName),
            "SortName": sortName.isEmpty ? .null : .string(sortName),
            "Overview": .string(overview),
            "Taglines": tagline.isEmpty ? .array([]) : .array([.string(tagline)]),
            "Genres": .array(splitList(genres).map { .string($0) }),
            "Tags": .array(splitList(tags).map { .string($0) }),
            "ProductionLocations": .array(splitList(productionLocations).map { .string($0) }),
            "Studios": .array(splitList(studios).map { .object(["Name": .string($0)]) }),
            "LockData": .bool(lockData),
            // Only known-valid MetadataField names may be sent; anything else 400s the whole save.
            "LockedFields": .array(lockedFields
                .filter { JellyfinLockableField(rawValue: $0) != nil }
                .sorted()
                .map { .string($0) }),
            "OfficialRating": officialRating.isEmpty ? .null : .string(officialRating),
        ]

        changes["ProductionYear"] = Int(year).map { .number(Double($0)) } ?? .null
        changes["CommunityRating"] = Double(communityRating).map { .number($0) } ?? .null
        changes["CriticRating"] = Double(criticRating).map { .number($0) } ?? .null
        changes["PremiereDate"] = hasPremiere ? .string(Coders.iso8601.string(from: premiere)) : .null
        if !indexNumber.isEmpty { changes["IndexNumber"] = Int(indexNumber).map { .number(Double($0)) } ?? .null }
        if !parentIndexNumber.isEmpty {
            changes["ParentIndexNumber"] = Int(parentIndexNumber).map { .number(Double($0)) } ?? .null
        }

        var ids: [String: JSONValue] = [:]
        for entry in providerIDs {
            let key = entry.key.trimmingCharacters(in: .whitespaces)
            let value = entry.value.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty else { continue }
            ids[key] = .string(value)
        }
        changes["ProviderIds"] = .object(ids)

        let ok = await jellyfin.saveMetadata(itemID: item.Id, changes: changes)
        saving = false
        if ok { dismiss() }
    }

    private func splitList(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
