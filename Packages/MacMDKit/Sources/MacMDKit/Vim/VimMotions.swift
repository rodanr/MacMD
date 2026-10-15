import Foundation

/// Motions and text objects. Each returns a target position (or range) for a starting position.
extension VimText {
    // MARK: Words

    func wordForward(from position: Int, big: Bool) -> Int {
        var current = position
        let start = characterClass(at: current, big: big)
        if start != 0 {
            while current < length, characterClass(at: current, big: big) == start { current = next(current) }
        }
        while current < length, characterClass(at: current, big: big) == 0 {
            if isNewline(current) {
                let following = next(current)
                // An empty line counts as a word.
                if following >= length || isNewline(following) { return following }
            }
            current = next(current)
        }
        return current
    }

    func wordEnd(from position: Int, big: Bool) -> Int {
        var current = next(position)
        while current < length, characterClass(at: current, big: big) == 0 { current = next(current) }
        guard current < length else { return previous(length) }
        let kind = characterClass(at: current, big: big)
        while next(current) < length, characterClass(at: next(current), big: big) == kind { current = next(current) }
        return current
    }

    func wordBackward(from position: Int, big: Bool) -> Int {
        guard position > 0 else { return 0 }
        var current = previous(position)
        while current > 0, characterClass(at: current, big: big) == 0 {
            if isNewline(current), isNewline(previous(current)) { return current }  // empty line
            current = previous(current)
        }
        let kind = characterClass(at: current, big: big)
        while current > 0, characterClass(at: previous(current), big: big) == kind, kind != 0 {
            current = previous(current)
        }
        return current
    }

    // MARK: Within a line

    /// `f`, `F`, `t`, `T`: the `count`-th occurrence of `target` on the current line.
    func find(_ target: Character, from position: Int, forward: Bool, till: Bool, count: Int) -> Int? {
        let needle = String(target)
        let start = lineStart(position)
        let end = contentEnd(position)
        var found = 0
        if forward {
            var current = next(position)
            while current < end {
                if character(at: current) == needle {
                    found += 1
                    if found == count { return till ? previous(current) : current }
                }
                current = next(current)
            }
        } else {
            var current = position
            while current > start {
                current = previous(current)
                if character(at: current) == needle {
                    found += 1
                    if found == count { return till ? next(current) : current }
                }
            }
        }
        return nil
    }

    // MARK: Paragraphs

    func paragraphForward(from position: Int, count: Int) -> Int {
        var current = position
        for _ in 0..<count {
            var line = lineEnd(current)
            while line < length, isBlankLine(line) { line = lineEnd(line) }
            while line < length, !isBlankLine(line) { line = lineEnd(line) }
            if line >= length { return length }
            current = line
        }
        return current
    }

    func paragraphBackward(from position: Int, count: Int) -> Int {
        var current = lineStart(position)
        for _ in 0..<count {
            guard current > 0 else { return 0 }
            var line = lineStart(current - 1)
            while line > 0, isBlankLine(line) { line = lineStart(line - 1) }
            while line > 0, !isBlankLine(line) { line = lineStart(line - 1) }
            current = line
        }
        return current
    }

    // MARK: Search

    /// Plain-text search that wraps around the document. Lowercase patterns ignore case (smartcase).
    func search(_ pattern: String, from position: Int, forward: Bool, wholeWord: Bool) -> Int? {
        guard !pattern.isEmpty, length > 0 else { return nil }
        var options: NSString.CompareOptions = pattern == pattern.lowercased() ? [.caseInsensitive] : []
        if !forward { options.insert(.backwards) }
        let after = min(next(position), length)
        let passes: [NSRange] =
            forward
            ? [NSRange(after..<length), NSRange(0..<length)]
            : [NSRange(0..<position), NSRange(0..<length)]
        for pass in passes {
            var range = pass
            while range.length > 0 {
                let match = text.range(of: pattern, options: options, range: range)
                guard match.location != NSNotFound else { break }
                if !wholeWord || isWholeWord(match) { return match.location }
                range =
                    forward
                    ? NSRange(NSMaxRange(match)..<NSMaxRange(range))
                    : NSRange(range.location..<match.location)
            }
        }
        return nil
    }

    private func isWholeWord(_ range: NSRange) -> Bool {
        let before = range.location == 0 || characterClass(at: previous(range.location), big: false) != 1
        let after = NSMaxRange(range) >= length || characterClass(at: NSMaxRange(range), big: false) != 1
        return before && after
    }

    func word(at position: Int) -> String? {
        guard position < length, characterClass(at: position, big: false) == 1 else { return nil }
        guard let range = wordObject(at: position, around: false, big: false) else { return nil }
        return text.substring(with: range)
    }

    // MARK: Text objects

    func wordObject(at position: Int, around: Bool, big: Bool) -> NSRange? {
        let lineBegin = lineStart(position)
        let end = contentEnd(position)
        guard position < end else { return nil }
        let kind = characterClass(at: position, big: big)
        var lower = position
        while lower > lineBegin, characterClass(at: previous(lower), big: big) == kind { lower = previous(lower) }
        var upper = next(position)
        while upper < end, characterClass(at: upper, big: big) == kind { upper = next(upper) }
        guard around, kind != 0 else { return NSRange(lower..<upper) }
        var extended = upper
        while extended < end, isBlank(extended) { extended = next(extended) }
        if extended == upper {
            while lower > lineBegin, isBlank(previous(lower)) { lower = previous(lower) }
        }
        return NSRange(lower..<extended)
    }

    func quoteObject(_ quote: Character, at position: Int, around: Bool) -> NSRange? {
        let needle = String(quote)
        var quotes: [Int] = []
        var current = lineStart(position)
        let end = contentEnd(position)
        while current < end {
            if character(at: current) == needle, current == 0 || character(at: previous(current)) != "\\" {
                quotes.append(current)
            }
            current = next(current)
        }
        var pairs: [(Int, Int)] = []
        var index = 0
        while index + 1 < quotes.count {
            pairs.append((quotes[index], quotes[index + 1]))
            index += 2
        }
        guard
            let pair = pairs.first(where: { $0.0 <= position && position <= $0.1 })
                ?? pairs.first(where: { $0.0 > position })
        else { return nil }
        return around ? NSRange(pair.0..<next(pair.1)) : NSRange(next(pair.0)..<pair.1)
    }

    func bracketObject(open: Character, close: Character, at position: Int, around: Bool) -> NSRange? {
        let openString = String(open)
        let closeString = String(close)
        var opening: Int?
        var depth = 0
        var current = min(position, length)
        if current < length, character(at: current) == openString { opening = current }
        if opening == nil, current < length, character(at: current) == closeString { depth = 1 }
        while opening == nil, current > 0 {
            current = previous(current)
            let char = character(at: current)
            if char == closeString {
                depth += 1
            } else if char == openString {
                if depth == 0 { opening = current } else { depth -= 1 }
            }
        }
        guard let start = opening else { return nil }
        depth = 0
        current = next(start)
        while current < length {
            let char = character(at: current)
            if char == openString {
                depth += 1
            } else if char == closeString {
                if depth == 0 {
                    return around ? NSRange(start..<next(current)) : NSRange(next(start)..<current)
                }
                depth -= 1
            }
            current = next(current)
        }
        return nil
    }

    /// `ip` / `ap`: whole lines, so the result is linewise.
    func paragraphObject(at position: Int, around: Bool) -> NSRange {
        let blank = isBlankLine(position)
        var first = lineStart(position)
        while first > 0, isBlankLine(first - 1) == blank { first = lineStart(first - 1) }
        var last = lineEnd(position)
        while last < length, isBlankLine(last) == blank { last = lineEnd(last) }
        if around {
            if last < length {
                while last < length, isBlankLine(last) != blank { last = lineEnd(last) }
            } else {
                while first > 0, isBlankLine(first - 1) != blank { first = lineStart(first - 1) }
            }
        }
        return NSRange(first..<last)
    }
}
