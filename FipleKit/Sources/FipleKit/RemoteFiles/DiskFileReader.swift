import Foundation
import UniformTypeIdentifiers

/// The real, read-only filesystem reader used on the Mac.
///
/// Conforms to ``FileReading`` and therefore exposes only reads — there is no
/// method here that deletes, moves, or writes a file. This is the concrete half
/// of the read-only safety invariant.
public struct DiskFileReader: FileReading {
    public init() {}

    public func metadata(at url: URL) throws -> FileMetadata {
        let values = try url.resourceValues(forKeys: [
            .fileSizeKey, .contentModificationDateKey, .contentTypeKey,
        ])
        let size = Int64(values.fileSize ?? 0)
        let modified = values.contentModificationDate ?? Date(timeIntervalSince1970: 0)
        let type = values.contentType?.identifier
            ?? UTType(filenameExtension: url.pathExtension)?.identifier
            ?? "public.data"
        return FileMetadata(sizeBytes: size, modifiedAt: modified, contentType: type)
    }

    public func readData(at url: URL) throws -> Data {
        // `.mappedIfSafe` avoids pulling a large file fully into memory; still a
        // pure read — the file is never modified.
        try Data(contentsOf: url, options: .mappedIfSafe)
    }
}
