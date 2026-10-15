import Foundation

/// A parsed Vim command: `[count] [operator [count]] (motion | text object | simple command)`.
struct VimCommand: Equatable {
    enum Operator: Character { case delete = "d", change = "c", yank = "y" }

    enum Motion: Equatable {
        case left, right, down, up
        case wordForward(big: Bool), wordBackward(big: Bool), wordEnd(big: Bool)
        case lineStart, firstNonBlank, lineEnd
        case documentStart, documentEnd
        case find(Character, forward: Bool, till: Bool)
        case repeatFind(reversed: Bool)
        case paragraphForward, paragraphBackward
        case nextLine, previousLine
        case searchNext(reversed: Bool)
    }

    enum TextObject: Equatable {
        case word(big: Bool), quote(Character), bracket(open: Character, close: Character), paragraph
    }

    enum Simple: Equatable {
        case deleteChar, deleteCharBefore, deleteToEnd, changeToEnd, yankLine
        case substituteChar, substituteLine
        case putAfter, putBefore
        case openBelow, openAbove
        case insert, append, insertAtLineStart, appendAtLineEnd
        case joinLines, replaceChar(Character), toggleCase
        case undo, redo, repeatLastChange
        case visual, visualLine
        case commandLine(Character)
        case searchWord(forward: Bool)
        case centerCursor, halfPageDown, halfPageUp
        case escape
        // Visual mode only.
        case swapVisualEnds, lowercase, uppercase
    }

    enum Action: Equatable {
        case motion(Motion)
        case textObject(TextObject, around: Bool)
        /// `dd`, `cc`, `yy`.
        case wholeLines
        case simple(Simple)
    }

    var count: Int?
    var op: Operator?
    var action: Action

    enum Parse: Equatable {
        case incomplete
        case invalid
        case complete(VimCommand)
    }

    /// Parses the keys typed so far. In visual mode operators apply to the selection right away.
    static func parse(_ keys: [VimKey], visual: Bool) -> Parse {
        var index = 0
        func peek() -> VimKey? { index < keys.count ? keys[index] : nil }

        func count() -> Int? {
            var digits = ""
            while case .char(let char)? = peek(), char.isASCII, let digit = char.wholeNumberValue,
                !(digits.isEmpty && digit == 0)
            {
                digits.append(char)
                index += 1
            }
            return digits.isEmpty ? nil : Int(digits.prefix(6))
        }

        let firstCount = count()
        guard let key = peek() else { return .incomplete }
        index += 1

        if visual, let simple = visualSimple(key) {
            return index == keys.count ? .complete(VimCommand(count: firstCount, action: .simple(simple))) : .invalid
        }
        if !visual, case .char(let char) = key, let op = Operator(rawValue: char) {
            let secondCount = count()
            let total = multiply(firstCount, secondCount)
            guard let next = peek() else { return .incomplete }
            index += 1
            if next == key { return finish(VimCommand(count: total, op: op, action: .wholeLines)) }
            if case .char(let scope) = next, scope == "i" || scope == "a" {
                guard let objectKey = peek() else { return .incomplete }
                index += 1
                guard let object = textObject(objectKey) else { return .invalid }
                return finish(VimCommand(count: total, op: op, action: .textObject(object, around: scope == "a")))
            }
            switch motion(next, keys: keys, index: &index) {
            case .incomplete: return .incomplete
            case .invalid: return .invalid
            case .complete(let motion): return finish(VimCommand(count: total, op: op, action: .motion(motion)))
            }
        }
        if visual, case .char(let scope) = key, scope == "i" || scope == "a" {
            guard let objectKey = peek() else { return .incomplete }
            index += 1
            guard let object = textObject(objectKey) else { return .invalid }
            return finish(VimCommand(count: firstCount, action: .textObject(object, around: scope == "a")))
        }
        if !visual, let simple = simple(key, keys: keys, index: &index) {
            switch simple {
            case .incomplete: return .incomplete
            case .invalid: return .invalid
            case .complete(let simple): return finish(VimCommand(count: firstCount, action: .simple(simple)))
            }
        }
        if case .escape = key { return finish(VimCommand(action: .simple(.escape))) }
        switch motion(key, keys: keys, index: &index) {
        case .incomplete: return .incomplete
        case .invalid: return .invalid
        case .complete(let motion): return finish(VimCommand(count: firstCount, action: .motion(motion)))
        }

        func finish(_ command: VimCommand) -> Parse {
            index == keys.count ? .complete(command) : .invalid
        }
    }

    private static func multiply(_ first: Int?, _ second: Int?) -> Int? {
        switch (first, second) {
        case (nil, nil): nil
        case (let value?, nil), (nil, let value?): value
        case (let first?, let second?): min(first * second, 999_999)
        }
    }

    private enum Partial<Value> {
        case incomplete, invalid
        case complete(Value)
    }

    private static func motion(_ key: VimKey, keys: [VimKey], index: inout Int) -> Partial<Motion> {
        func nextChar() -> Partial<Character> {
            guard index < keys.count else { return .incomplete }
            defer { index += 1 }
            if case .char(let char) = keys[index] { return .complete(char) }
            return .invalid
        }
        switch key {
        case .left, .backspace, .char("h"): return .complete(.left)
        case .right, .char("l"), .char(" "): return .complete(.right)
        case .down, .char("j"), .ctrl("n"): return .complete(.down)
        case .up, .char("k"), .ctrl("p"): return .complete(.up)
        case .char("w"): return .complete(.wordForward(big: false))
        case .char("W"): return .complete(.wordForward(big: true))
        case .char("b"): return .complete(.wordBackward(big: false))
        case .char("B"): return .complete(.wordBackward(big: true))
        case .char("e"): return .complete(.wordEnd(big: false))
        case .char("E"): return .complete(.wordEnd(big: true))
        case .char("0"): return .complete(.lineStart)
        case .char("^"): return .complete(.firstNonBlank)
        case .char("$"): return .complete(.lineEnd)
        case .char("G"): return .complete(.documentEnd)
        case .char("g"):
            switch nextChar() {
            case .incomplete: return .incomplete
            case .complete("g"): return .complete(.documentStart)
            default: return .invalid
            }
        case .char(let char) where "fFtT".contains(char):
            switch nextChar() {
            case .incomplete: return .incomplete
            case .invalid: return .invalid
            case .complete(let target):
                return .complete(.find(target, forward: char == "f" || char == "t", till: char == "t" || char == "T"))
            }
        case .char(";"): return .complete(.repeatFind(reversed: false))
        case .char(","): return .complete(.repeatFind(reversed: true))
        case .char("}"): return .complete(.paragraphForward)
        case .char("{"): return .complete(.paragraphBackward)
        case .enter, .char("+"): return .complete(.nextLine)
        case .char("-"): return .complete(.previousLine)
        case .char("n"): return .complete(.searchNext(reversed: false))
        case .char("N"): return .complete(.searchNext(reversed: true))
        default: return .invalid
        }
    }

    private static func simple(_ key: VimKey, keys: [VimKey], index: inout Int) -> Partial<Simple>? {
        switch key {
        case .char("x"): return .complete(.deleteChar)
        case .char("X"): return .complete(.deleteCharBefore)
        case .char("D"): return .complete(.deleteToEnd)
        case .char("C"): return .complete(.changeToEnd)
        case .char("Y"): return .complete(.yankLine)
        case .char("s"): return .complete(.substituteChar)
        case .char("S"): return .complete(.substituteLine)
        case .char("p"): return .complete(.putAfter)
        case .char("P"): return .complete(.putBefore)
        case .char("o"): return .complete(.openBelow)
        case .char("O"): return .complete(.openAbove)
        case .char("i"): return .complete(.insert)
        case .char("a"): return .complete(.append)
        case .char("I"): return .complete(.insertAtLineStart)
        case .char("A"): return .complete(.appendAtLineEnd)
        case .char("J"): return .complete(.joinLines)
        case .char("~"): return .complete(.toggleCase)
        case .char("u"): return .complete(.undo)
        case .ctrl("r"): return .complete(.redo)
        case .char("."): return .complete(.repeatLastChange)
        case .char("v"): return .complete(.visual)
        case .char("V"): return .complete(.visualLine)
        case .char(":"): return .complete(.commandLine(":"))
        case .char("/"): return .complete(.commandLine("/"))
        case .char("?"): return .complete(.commandLine("?"))
        case .char("*"): return .complete(.searchWord(forward: true))
        case .char("#"): return .complete(.searchWord(forward: false))
        case .ctrl("d"): return .complete(.halfPageDown)
        case .ctrl("u"): return .complete(.halfPageUp)
        case .char("r"):
            guard index < keys.count else { return .incomplete }
            defer { index += 1 }
            if case .char(let char) = keys[index] { return .complete(.replaceChar(char)) }
            return .invalid
        case .char("z"):
            guard index < keys.count else { return .incomplete }
            defer { index += 1 }
            return keys[index] == .char("z") ? .complete(.centerCursor) : .invalid
        default: return nil
        }
    }

    private static func visualSimple(_ key: VimKey) -> Simple? {
        switch key {
        case .char("d"), .char("x"): .deleteChar
        case .char("c"), .char("s"): .substituteChar
        case .char("y"): .yankLine
        case .char("p"), .char("P"): .putAfter
        case .char("o"): .swapVisualEnds
        case .char("~"): .toggleCase
        case .char("u"): .lowercase
        case .char("U"): .uppercase
        case .char("J"): .joinLines
        case .char("v"): .visual
        case .char("V"): .visualLine
        case .escape, .ctrl("["): .escape
        default: nil
        }
    }

    private static func textObject(_ key: VimKey) -> TextObject? {
        switch key {
        case .char("w"): .word(big: false)
        case .char("W"): .word(big: true)
        case .char("p"): .paragraph
        case .char("\""): .quote("\"")
        case .char("'"): .quote("'")
        case .char("`"): .quote("`")
        case .char("("), .char(")"), .char("b"): .bracket(open: "(", close: ")")
        case .char("["), .char("]"): .bracket(open: "[", close: "]")
        case .char("{"), .char("}"), .char("B"): .bracket(open: "{", close: "}")
        case .char("<"), .char(">"): .bracket(open: "<", close: ">")
        default: nil
        }
    }
}
