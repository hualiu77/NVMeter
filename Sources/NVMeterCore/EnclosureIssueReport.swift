import Foundation

/// Public report payload, deliberately independent of device snapshots and raw diagnostics.
public struct EnclosureIssueReport: Sendable {
    public struct USBBridge: Sendable {
        let vendorID: UInt16
        let productID: UInt16

        public init?(vendorID: Int?, productID: Int?) {
            guard let vendorID, let productID,
                  let vendor = UInt16(exactly: vendorID),
                  let product = UInt16(exactly: productID) else { return nil }
            self.vendorID = vendor
            self.productID = product
        }

        var formattedID: String { String(format: "%04x:%04x", Int(vendorID), Int(productID)) }
    }

    public enum Outcome: Sendable {
        case blocked
        case working(args: [String])
    }

    public let title: String
    public let body: String

    public init(outcome: Outcome, bridge: USBBridge?, version: String, os: OperatingSystemVersion) {
        let summary: String
        let probe: String
        switch outcome {
        case .blocked:
            summary = "Enclosure report: SMART unavailable"
            probe = "NVMeter could not read SMART for this enclosure."
        case .working(let args):
            summary = "Working bridge: SMART available"
            if let known = SmartctlProbe.typeLadder.first(where: { $0 == args }) {
                probe = "NVMeter read SMART using `\(known.joined(separator: " "))`."
            } else {
                probe = "NVMeter read SMART. No recognized probe type to include."
            }
        }

        title = bridge.map { "\(summary) (USB \($0.formattedID))" } ?? summary
        let identity = bridge.map { "USB vendor:product ID: `\($0.formattedID)`" }
            ?? "USB vendor:product ID unavailable. Add it manually if known."
        body = """
        ## Enclosure report

        \(probe)
        \(identity)

        **Fill in if you know:**
        - Enclosure brand + model:
        - Drive model:
        - Connection (cable, hub, dock):

        Please leave out serial numbers, volume names and unrelated devices.

        ## Environment

        - NVMeter \(version)
        - macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)
        """
    }
}
