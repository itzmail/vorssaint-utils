// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Security
import CryptoKit

enum FanControlIdentifiers {
    #if VORSSAINT_DEVELOPMENT
    static let appBundleID = "com.itzmail.solvane.dev"
    #else
    static let appBundleID = "com.itzmail.solvane"
    #endif

    static let helperID = "\(appBundleID).fan-control"
    static let plistName = "\(helperID).plist"

    // The upstream release pins its Apple Developer Team ID here. This fork is
    // self-signed, so both ends pin the leaf certificate it was signed with:
    // an app and helper from any other signer fail the connection.
    static var appCodeRequirement: String {
        "identifier \"\(appBundleID)\" and certificate leaf = H\"\(currentLeafCertificateSHA1() ?? zeroHash)\""
    }

    static var helperCodeRequirement: String {
        "identifier \"\(helperID)\" and certificate leaf = H\"\(currentLeafCertificateSHA1() ?? zeroHash)\""
    }

    private static let zeroHash = String(repeating: "0", count: 40)

    private static func currentLeafCertificateSHA1() -> String? {
        var dynamicCode: SecCode?
        guard SecCodeCopySelf([], &dynamicCode) == errSecSuccess,
              let selfCode = dynamicCode else {
            return nil
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(selfCode, [], &staticCode) == errSecSuccess,
              let staticSelfCode = staticCode else {
            return nil
        }

        var signingInfo: CFDictionary?
        guard SecCodeCopySigningInformation(staticSelfCode, SecCSFlags(rawValue: kSecCSSigningInformation), &signingInfo) == errSecSuccess,
              let info = signingInfo as? [String: Any] else {
            return nil
        }

        guard let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first else {
            return nil
        }

        let data = SecCertificateCopyData(leaf) as Data
        let digest = Insecure.SHA1.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

@objc protocol FanControlXPCProtocol {
    func status(withReply reply: @escaping (Data) -> Void)
    func startMaximumCooling(withReply reply: @escaping (Data) -> Void)
    func applyConfiguration(_ configuration: Data, withReply reply: @escaping (Data) -> Void)
    func heartbeat(withReply reply: @escaping (Data) -> Void)
    func restoreAutomatic(withReply reply: @escaping (Data) -> Void)
    func restoreOwnedControl(withReply reply: @escaping (Data) -> Void)
    func prepareForUnregister(withReply reply: @escaping (Data) -> Void)
}

enum FanControlIPC {
    static func encode(_ response: FanControlResponse) -> Data {
        // Every value in this closed response model is JSON encodable. Keeping
        // one deterministic fallback avoids ever violating the XPC reply shape.
        (try? JSONEncoder().encode(response))
            ?? Data(#"{"succeeded":false,"snapshot":{"fans":[],"isCooling":false},"error":"controlFailed"}"#.utf8)
    }

    static func decode(_ data: Data) -> FanControlResponse? {
        try? JSONDecoder().decode(FanControlResponse.self, from: data)
    }

    static func encode(_ configuration: FanControlConfiguration) -> Data? {
        try? JSONEncoder().encode(configuration)
    }

    static func decodeConfiguration(_ data: Data) -> FanControlConfiguration? {
        guard let configuration = try? JSONDecoder().decode(FanControlConfiguration.self,
                                                              from: data),
              FanControlPolicy.validConfiguration(configuration) else { return nil }
        return configuration
    }
}
