import Foundation

enum BundledSoundBank {
    static var url: URL? {
        Bundle.main.url(forResource: "GeneralUser-GS", withExtension: "sf2")
    }

    static var displayName: String {
        "GeneralUser GS"
    }
}
