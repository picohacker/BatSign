//
//  RemoteImage.swift
//  BatSign
//
//  Cached remote image view — avoids AsyncImage entirely (its closure
//  overloads shifted across SDKs) and adds an in-memory cache so source
//  icons, banners and screenshots don't re-download while scrolling.
//

import SwiftUI
import UIKit

@MainActor
final class RemoteImageCache: ObservableObject {
    static let shared = RemoteImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        cache.countLimit = 300
    }

    nonisolated func cachedImage(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    nonisolated func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var loadToken = UUID()

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            if let cached = RemoteImageCache.shared.cachedImage(for: url) {
                image = cached
                return
            }
            image = nil
            let token = UUID()
            loadToken = token
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard loadToken == token else { return }
                if let decoded = UIImage(data: data) {
                    RemoteImageCache.shared.store(decoded, for: url)
                    image = decoded
                }
            } catch {
                // keep placeholder
            }
        }
    }
}
