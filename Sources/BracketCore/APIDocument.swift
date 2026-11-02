import Foundation

public struct APIDocument {
    public static let extensions = ["json", "yaml", "yml"]
    public static let maximumSize = 32 * 1024 * 1024
    public let url: URL
    public let data: Data

    public init(url: URL) throws {
        guard url.isFileURL, Self.extensions.contains(url.pathExtension.lowercased()) else {
            throw DocumentError.unsupportedType
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw DocumentError.unsupportedType }
        guard (values.fileSize ?? 0) <= Self.maximumSize else { throw DocumentError.tooLarge }
        let data = try Data(contentsOf: url)
        guard data.count <= Self.maximumSize else { throw DocumentError.tooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw DocumentError.invalidEncoding }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DocumentError.empty }
        self.url = url.standardizedFileURL.resolvingSymlinksInPath()
        self.data = data
    }
}

public enum DocumentError: LocalizedError {
    case unsupportedType, tooLarge, invalidEncoding, empty

    public var errorDescription: String? {
        switch self {
        case .unsupportedType: return "Choose a Swagger or OpenAPI file with a .json, .yaml, or .yml extension."
        case .tooLarge: return "This file exceeds the 32 MB limit. Choose a smaller API definition."
        case .invalidEncoding: return "This file is not UTF-8 text. Save it as UTF-8, then open it again."
        case .empty: return "This file is empty. Choose a file that contains an API definition."
        }
    }
}
