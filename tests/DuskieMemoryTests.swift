import Foundation

@main
struct DuskieMemoryTests {
    static func main() throws {
        func packet(version: UInt32 = 1, state: UInt32 = 2, bytes: UInt64 = 2_147_483_648,
                    target: UInt64 = 2_147_483_648, error: Int32 = 0, pid: Int32 = 123) -> Data {
            var data = Data()
            func append<T: FixedWidthInteger>(_ value: T) {
                var value = value.littleEndian
                withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
            }
            append(version); append(state); append(bytes); append(target); append(error); append(pid)
            return data
        }
        let held = try DuskieMemoryStatus.decode(packet())
        precondition(held.active && held.bytes == 2_147_483_648 && held.title == "Held" && held.pid == 123)
        let failed = try DuskieMemoryStatus.decode(packet(state: 4, bytes: 0, error: 12))
        precondition(!failed.active && failed.error == 12 && failed.title == "Failed")
        for invalid in [Data(), packet(version: 2), packet(state: 5), packet(bytes: 3_000_000_000)] {
            do { _ = try DuskieMemoryStatus.decode(invalid); fatalError("Invalid status accepted") }
            catch is POSIXError { }
        }
        print("Duskie worker protocol: 64-bit allocation, states, errors and invalid records passed")
    }
}
