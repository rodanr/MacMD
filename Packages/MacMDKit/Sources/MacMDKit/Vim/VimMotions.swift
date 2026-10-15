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

    /// `w` after an operator (`dw`, `c2w`, `y3W`), ported from Vim's `fwd_word()` with `eol` set: on the last
    /// word it stops where it crosses a line end, and blank lines count as words. Nil when it can't move.
    func wordForwardForOperator(from position: Int, count: Int, big: Bool) -> Int? {
        /// Vim's `inc_cursor()`: one step right. 0 = moved, 2 = moved onto the line's end, 1 = moved to the next
        /// line's start, nil = nowhere to go. A line's end is its line break position here.
        func step(_ position: Int) -> (Int, Int)? {
            let end = contentEnd(position)
            if position >= end {
                let following = lineEnd(position)
                guard following < length || (following == length && !endsWithLineBreak && following > position) else {
                    return nil
                }
                return following < length ? (following, 1) : nil
            }
            let moved = next(position)
            return (moved, moved >= end ? 2 : 0)
        }
        func kind(_ position: Int) -> Int {
            position >= contentEnd(position) ? 0 : characterClass(at: position, big: big)
        }

        var cursor = position
        for iteration in 0..<max(count, 1) {
            let isLast = iteration == max(count, 1) - 1
            let start = kind(cursor)
            let onLastLine = lineIndex(cursor) == lineCount - 1
            // At the very end: fail if nothing moved; otherwise the operator ends where earlier steps got to.
            guard let (first, crossed) = step(cursor) else { return cursor == position ? nil : cursor }
            // Vim fails here ("started at the last char in the file"), but with an operator pending the failure is
            // ignored and the cursor has already reached the line's end: `dw` on the last word still deletes it.
            if crossed >= 1, onLastLine { return first }
            cursor = first
            if crossed >= 1, isLast { return cursor }
            if start != 0 {
                while kind(cursor) == start {
                    guard let (moved, crossed) = step(cursor) else { return cursor }
                    cursor = moved
                    if crossed >= 1, isLast { return cursor }
                }
            }
            while kind(cursor) == 0 {
                if isLineStart(cursor), isEmptyLine(cursor) { break }  // a blank line is a word
                guard let (moved, crossed) = step(cursor) else { return cursor }
                cursor = moved
                if crossed >= 1, isLast { return cursor }
            }
        }
        return cursor
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

    /// `}`: past any blank lines, then through the paragraph, to the blank line after it (or the end).
    func paragraphForward(from position: Int, count: Int) -> Int {
        var line = lineStart(position)
        for _ in 0..<count {
            while line < length, isBlankLine(line) { line = lineEnd(line) }
            while line < length, !isBlankLine(line) { line = lineEnd(line) }
        }
        return min(line, length)
    }

    /// `{`: the same, backwards, to the blank line before the paragraph (or the start).
    func paragraphBackward(from position: Int, count: Int) -> Int {
        var line = lineStart(position)
        for _ in 0..<count {
            while line > 0, isBlankLine(line) { line = lineStart(line - 1) }
            while line > 0, !isBlankLine(line) { line = lineStart(line - 1) }
        }
        return line
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
        guard around else { return NSRange(lower..<upper) }
        if kind == 0 {
            // `aw` on white space: the space plus the word after it.
            guard upper < end else { return NSRange(lower..<upper) }
            let next = characterClass(at: upper, big: big)
            var wordEnd = upper
            while wordEnd < end, characterClass(at: wordEnd, big: big) == next { wordEnd = self.next(wordEnd) }
            return NSRange(lower..<wordEnd)
        }
        var extended = upper
        while extended < end, isBlank(extended) { extended = next(extended) }
        if extended == upper {
            // No trailing space: take the leading space instead, unless it is the line's indentation.
            var leading = lower
            while leading > lineBegin, isBlank(previous(leading)) { leading = previous(leading) }
            if leading > lineBegin { lower = leading }
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
        // Like Vim: on a quote, pair quotes counting from the line start; elsewhere use the nearest quote on each
        // side; with none around the cursor, the first pair after it.
        let pair: (Int, Int)
        if quotes.contains(position), let found = pairs.first(where: { $0.0 == position || $0.1 == position }) {
            pair = found
        } else if let before = quotes.last(where: { $0 < position }), let after = quotes.first(where: { $0 > position })
        {
            pair = (before, after)
        } else if let found = pairs.first(where: { $0.0 > position }) {
            pair = found
        } else {
            return nil
        }
        guard around else { return NSRange(next(pair.0)..<pair.1) }
        // Like Vim: trailing white space is included, or leading white space when there is none.
        var lower = pair.0
        var upper = next(pair.1)
        let lineEnd = contentEnd(position)
        if upper < lineEnd, isBlank(upper) {
            while upper < lineEnd, isBlank(upper) { upper = next(upper) }
        } else {
            let lineBegin = lineStart(position)
            while lower > lineBegin, isBlank(previous(lower)) { lower = previous(lower) }
        }
        return NSRange(lower..<upper)
    }

    func bracketObject(open: Character, close: Character, at position: Int, around: Bool) -> NSRange? {
        let openString = String(open)
        let closeString = String(close)
        var opening: Int?
        var depth = 0
        var current = min(position, length)
        if current < length, character(at: current) == openString { opening = current }
        while opening == nil, current > 0 {
            current = previous(current)
            let char = character(at: current)
            if char == closeString {
                depth += 1
            } else if char == openString {
                if depth == 0 { opening = current } else { depth -= 1 }
            }
        }
        if opening == nil {
            // Not inside a pair: use the next one after the cursor, as Vim 9 does.
            var ahead = min(position, length)
            while ahead < length, character(at: ahead) != openString { ahead = next(ahead) }
            if ahead < length { opening = ahead }
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
    func paragraphObject(at position: Int, around: Bool) -> NSRange? {
        let blank = isBlankLine(position)
        var first = lineStart(position)
        while first > 0, isBlankLine(first - 1) == blank { first = lineStart(first - 1) }
        var last = lineEnd(position)
        while last < length, isBlankLine(last) == blank { last = lineEnd(last) }
        if around {
            if blank, last >= length { return nil }  // trailing blank lines have no paragraph after them
            if last < length {
                while last < length, isBlankLine(last) != blank { last = lineEnd(last) }
            } else {
                while first > 0, isBlankLine(first - 1) != blank { first = lineStart(first - 1) }
            }
        }
        // A blank-only stretch with no paragraph next to it is not a paragraph object (Vim fails too).
        if around, (first..<last).allSatisfy({ isNewline($0) || isBlank($0) }) { return nil }
        return NSRange(first..<last)
    }
}
