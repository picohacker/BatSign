//
//  SourceBrowserView.swift
//  BatSign
//
//  SignOS-style source viewer: browse the IPA's real archive contents,
//  preview plists/profiles/images/text, and export any file.
//

import SwiftUI
import UniformTypeIdentifiers

struct SourceItem: Identifiable, Hashable {
    let name: String
    let fullPath: String
    let isDirectory: Bool
    let size: UInt64
    let childCount: Int

    var id: String { fullPath }
}

struct SourceBrowserView: View {
    let app: AppRecord

    @State private var entries: [ZipEntry] = []
    @State private var loadFailed = false
    @State private var currentPath = ""

    var body: some View {
        Group {
            if loadFailed {
                EmptyState(icon: "archivebox",
                           title: "Couldn't read this IPA",
                           message: "The archive could not be opened for browsing.")
            } else {
                List {
                    if !currentPath.isEmpty {
                        Button {
                            currentPath = parentPath()
                        } label: {
                            Label(parentName(), systemImage: "chevron.left")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.batAmber)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    ForEach(items()) { item in
                        if item.isDirectory {
                            Button {
                                currentPath = item.fullPath
                            } label: {
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(.batAmber.opacity(0.85))
                                    Text(item.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Text("\(item.childCount) items")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.4))
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.3))
                                }
                            }
                            .listRowBackground(Color.white.opacity(0.05))
                        } else {
                            NavigationLink(value: item) {
                                HStack {
                                    Image(systemName: Self.icon(for: item.name))
                                        .foregroundStyle(.white.opacity(0.55))
                                    Text(item.name)
                                        .font(.subheadline)
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file))
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                            }
                            .listRowBackground(Color.white.opacity(0.05))
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(currentPath.isEmpty ? "IPA contents" : (currentPath as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .background(.clear)
        .onAppear(perform: load)
        .navigationDestination(for: SourceItem.self) { item in
            SourceFileView(app: app, entryName: item.fullPath, size: item.size)
        }
    }

    private func load() {
        guard entries.isEmpty, let reader = try? ZipReader(url: app.fileURL) else {
            loadFailed = entries.isEmpty
            return
        }
        entries = reader.entries
        loadFailed = reader.entries.isEmpty
    }

    // MARK: Hierarchy

    private func items() -> [SourceItem] {
        let prefix = currentPath.isEmpty ? "" : "\(currentPath)/"
        var dirs: [String: Int] = [:]
        var files: [SourceItem] = []

        for entry in entries {
            let name = entry.name
            guard !entry.isDirectory else { continue }
            guard name.hasPrefix(prefix), name != prefix else { continue }
            let rest = String(name.dropFirst(prefix.count))
            guard !rest.isEmpty else { continue }
            if let slash = rest.firstIndex(of: "/") {
                let dir = String(rest[..<slash])
                dirs[dir, default: 0] += 1
            } else {
                files.append(SourceItem(name: rest, fullPath: name, isDirectory: false,
                                        size: entry.uncompressedSize, childCount: 0))
            }
        }

        let dirItems = dirs.keys.sorted().map { dir in
            SourceItem(name: dir, fullPath: prefix + dir, isDirectory: true, size: 0, childCount: dirs[dir] ?? 0)
        }
        return dirItems + files.sorted { $0.name < $1.name }
    }

    private func parentPath() -> String {
        guard let idx = currentPath.lastIndex(of: "/") else { return "" }
        return String(currentPath[..<idx])
    }

    private func parentName() -> String {
        let parent = parentPath()
        return parent.isEmpty ? "Archive root" : (parent as NSString).lastPathComponent
    }

    static func icon(for name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "plist": return "plist"
        case "png", "jpg", "jpeg": return "photo"
        case "dylib": return "cube.transparent"
        case "car": return "paintbrush"
        case "strings", "entitlements": return "textformat"
        case "json": return "curlybraces"
        case "lproj": return "globe"
        case "mobileprovision", "provisionprofile": return "seal"
        default:
            if name.hasSuffix(".app") || name.contains("Info") { return "app" }
            return "doc"
        }
    }
}

// MARK: - File preview

struct SourceFileView: View {
    let app: AppRecord
    let entryName: String
    let size: UInt64

    @State private var text: String?
    @State private var image: UIImage?
    @State private var info: String?
    @State private var exportURL: URL?

    private enum PreviewKind {
        case image, plist, profile, text, binary
    }

    private var kind: PreviewKind {
        let ext = (entryName as NSString).pathExtension.lowercased()
        if ["png", "jpg", "jpeg"].contains(ext) { return .image }
        if ext == "mobileprovision" || ext == "provisionprofile" { return .profile }
        if ["plist", "entitlements"].contains(ext) { return .plist }
        if ["json", "xml", "txt", "strings", "js", "html", "css", "md", "h", "c", "m", "mm", "swift", "car"].contains(ext) { return .text }
        if entryName.hasSuffix("Info.plist") { return .plist }
        return .binary
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 260)
                        .padding(18)
                        .glassSurface(cornerRadius: 22)
                }
                if let text {
                    Text(text)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
                        .textSelection(.enabled)
                }
                if let info {
                    Text(info)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                }
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Export this file", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryGlassButtonStyle())
                }
            }
            .padding(18)
            .padding(.bottom, 30)
        }
        .background(.clear)
        .navigationTitle((entryName as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadPreview)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: SourceBrowserView.icon(for: entryName))
                .font(.title3)
                .foregroundStyle(.batAmber)
            Text(entryName)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(2)
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(14)
        .glassSurface(cornerRadius: 18)
    }

    private func loadPreview() {
        guard let reader = try? ZipReader(url: app.fileURL),
              let entry = reader.firstEntry(matching: { $0.name == entryName }) else {
            info = "File could not be read from the archive."
            return
        }

        switch kind {
        case .image:
            if let data = try? reader.readData(entry), data.count < 25 * 1024 * 1024,
               let img = UIImage(data: data) {
                image = img
                makeExport(data)
            } else {
                info = "Image could not be decoded (or is too large to preview)."
                makeExport(try? reader.readData(entry) ?? Data())
            }
        case .plist:
            if let data = try? reader.readData(entry), data.count < 2 * 1024 * 1024 {
                if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                   let xml = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0),
                   let str = String(data: xml, encoding: .utf8) {
                    text = str
                    makeExport(xml)
                } else if let str = String(data: data, encoding: .utf8) {
                    text = str
                    makeExport(data)
                } else {
                    info = "Property list could not be decoded."
                }
            } else {
                info = "File too large to preview (2 MB limit)."
            }
        case .profile:
            if let data = try? reader.readData(entry), let profile = try? ProfileParser.parse(data: data) {
                text = Self.profileSummary(profile)
                if let xml = ProfileParser.entitlementsXML(profile.entitlements) {
                    text? += "\n\n— Entitlements —\n\(xml)"
                }
            } else {
                info = "Profile could not be parsed."
            }
        case .text:
            if let data = try? reader.readData(entry), data.count < 1024 * 1024,
               let str = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                text = str
                makeExport(data)
            } else {
                info = "File too large to preview (1 MB limit)."
            }
        case .binary:
            info = Self.binarySummary(entry)
            makeExport(try? reader.readData(entry) ?? Data())
        }
    }

    private func makeExport(_ data: Data) {
        guard !data.isEmpty else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent((entryName as NSString).lastPathComponent)
        try? data.write(to: url, options: [.atomic])
        exportURL = url
    }

    private static func profileSummary(_ profile: ProvisionProfile) -> String {
        var lines: [String] = []
        lines.append("Name:            \(profile.name)")
        lines.append("Team:            \(profile.teamName)")
        lines.append("Team ID:         \(profile.teamIDs.joined(separator: ", "))")
        if let created = profile.created {
            lines.append("Created:         \(created.formatted(.dateTime))")
        }
        if let expiry = profile.expiration {
            lines.append("Expires:         \(expiry.formatted(.dateTime))")
        }
        lines.append("Kind:            \(profile.kind.label)")
        lines.append("Devices:         \(profile.provisionedDevices.count)")
        lines.append("App ID:          \(profile.applicationIDPrefix).\(profile.applicationIDBundle)")
        if !profile.apsEnvironment.isEmpty {
            lines.append("Push (APS):      \(profile.apsEnvironment)")
        }
        return lines.joined(separator: "\n")
    }

    private static func binarySummary(_ entry: ZipEntry) -> String {
        var lines: [String] = []
        lines.append("Type:            binary / opaque resource")
        lines.append("Compressed:      \(ByteCountFormatter.string(fromByteCount: Int64(entry.compressedSize), countStyle: .file))")
        lines.append("Uncompressed:    \(ByteCountFormatter.string(fromByteCount: Int64(entry.uncompressedSize), countStyle: .file))")
        lines.append("Method:          \(entry.method == 0 ? "stored" : "deflate")")
        return lines.joined(separator: "\n")
    }
}
