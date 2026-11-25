import Foundation

/// A page size in points (1/72 inch), the unit all page content is positioned in.
public struct PageSize: Equatable, Codable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public init(format: PaperFormat, orientation: PageOrientation) {
        let portrait = format.portraitSize
        switch orientation {
        case .portrait: self = portrait
        case .landscape: self = PageSize(width: portrait.height, height: portrait.width)
        }
    }
}

public enum PaperFormat: String, CaseIterable, Codable, Sendable {
    case a4
    case letter

    var portraitSize: PageSize {
        switch self {
        case .a4: PageSize(width: 595, height: 842)
        case .letter: PageSize(width: 612, height: 792)
        }
    }
}

public enum PageOrientation: String, CaseIterable, Codable, Sendable {
    case portrait
    case landscape
}

public enum PaperTemplate: String, CaseIterable, Codable, Sendable {
    case blank
    case lined
    case squared
    case dotted
}

/// Namespace for the identifier of a PDF file stored inside a notebook package.
public enum PDFSource {
    public typealias ID = Identifier<PDFSource>
}

/// What a page shows beneath the ink.
public enum PageBackground: Equatable, Sendable {
    case paper(PaperTemplate)
    case pdf(source: PDFSource.ID, pageIndex: Int)
}

extension PageBackground: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, template, source, pageIndex
    }

    private enum Kind: String, Codable {
        case paper, pdf
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .paper:
            self = .paper(try container.decode(PaperTemplate.self, forKey: .template))
        case .pdf:
            self = .pdf(
                source: try container.decode(PDFSource.ID.self, forKey: .source),
                pageIndex: try container.decode(Int.self, forKey: .pageIndex)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .paper(let template):
            try container.encode(Kind.paper, forKey: .kind)
            try container.encode(template, forKey: .template)
        case .pdf(let source, let pageIndex):
            try container.encode(Kind.pdf, forKey: .kind)
            try container.encode(source, forKey: .source)
            try container.encode(pageIndex, forKey: .pageIndex)
        }
    }
}

/// One page of a notebook. Content drawn on the page is stored per page, keyed by the page's identifier,
/// and positioned in the page's own coordinate space: points, origin at the top-left corner.
public struct Page: Identifiable, Equatable, Codable, Sendable {
    public typealias ID = Identifier<Page>

    public let id: ID
    public var size: PageSize
    public var background: PageBackground

    public init(id: ID = ID(), size: PageSize, background: PageBackground) {
        self.id = id
        self.size = size
        self.background = background
    }

    /// A new page to follow this one: same size, on the given paper or else on this page's paper.
    /// PDF pages are followed by blank paper.
    public func successor(template: PaperTemplate? = nil) -> Page {
        let inherited: PaperTemplate = if case .paper(let own) = background { own } else { .blank }
        return Page(size: size, background: .paper(template ?? inherited))
    }
}
