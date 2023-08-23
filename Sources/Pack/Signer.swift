import Foundation

protocol Signer {
    func codesign(url: URL, entitlements: URL?) async throws
}
