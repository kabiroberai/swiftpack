struct StringError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) {
        self.description = description
    }
}

extension BinaryInteger {
    var littleEndianBytes: some RandomAccessCollection<UInt8> {
        (0..<(bitWidth / 8)).lazy.map { UInt8(truncatingIfNeeded: self >> ($0 * 8)) }
    }

    var bigEndianBytes: some RandomAccessCollection<UInt8> {
        littleEndianBytes.reversed()
    }
}
