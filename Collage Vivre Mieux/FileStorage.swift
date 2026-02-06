import Foundation
import UIKit

enum FileStorage {
    static func documentsDir() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func saveJPEG(_ image: UIImage, quality: CGFloat = 0.85) throws -> String {
        let name = UUID().uuidString + ".jpg"
        let url = documentsDir().appendingPathComponent(name)
        guard let data = image.jpegData(compressionQuality: quality) else {
            throw NSError(domain: "jpeg", code: 1)
        }
        try data.write(to: url, options: .atomic)
        return name
    }

    static func loadImage(filename: String) -> UIImage? {
        let url = documentsDir().appendingPathComponent(filename)
        return UIImage(contentsOfFile: url.path)
    }
}
