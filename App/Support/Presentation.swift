import LinedModel
import SwiftUI

extension Binding where Value == String? {
    /// Whether the optional holds a value; setting it to `false` clears the value.
    var isPresent: Binding<Bool> {
        Binding<Bool> {
            wrappedValue != nil
        } set: { isPresent in
            if !isPresent { wrappedValue = nil }
        }
    }
}

extension PaperTemplate {
    var displayName: LocalizedStringKey {
        switch self {
        case .blank: "Blank"
        case .lined: "Lined"
        case .squared: "Squared"
        case .dotted: "Dotted"
        }
    }

    var symbolName: String {
        switch self {
        case .blank: "rectangle.portrait"
        case .lined: "text.justify"
        case .squared: "squareshape.split.3x3"
        case .dotted: "circle.grid.3x3"
        }
    }
}

extension LibrarySortOrder {
    var displayName: LocalizedStringKey {
        switch self {
        case .name: "Name"
        case .dateModified: "Date Modified"
        case .dateCreated: "Date Created"
        }
    }
}

/// A page or cover picture on white paper, with the soft edge and shadow of a sheet.
struct PagePicture: View {
    static let cornerRadius: CGFloat = 5

    let image: CGImage?
    /// Width divided by height.
    let aspectRatio: CGFloat

    var body: some View {
        ZStack {
            Color.white
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(.rect(cornerRadius: Self.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .strokeBorder(.black.opacity(0.12), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.14), radius: 5, y: 2)
    }
}
