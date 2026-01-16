import Foundation

extension String {
    var firstEmojiString: String? {
        for character in self {
            if character.isEmojiLike {
                return String(character)
            }
        }
        return nil
    }
}

private extension Character {
    var isEmojiLike: Bool {
        unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation || scalar.properties.isEmoji
        }
    }
}

