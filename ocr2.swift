import Foundation
import Vision
import AppKit
import CoreImage

let p = CommandLine.arguments[1]
guard let src = CIImage(contentsOf: URL(fileURLWithPath: p)) else { print("NOIMG"); exit(1) }
let ctx = CIContext()

func render(_ img: CIImage, scale: CGFloat) -> CGImage? {
    let s = img.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    return ctx.createCGImage(s, from: s.extent)
}
func ocr(_ cg: CGImage, level: VNRequestTextRecognitionLevel) -> String {
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = level
    req.usesLanguageCorrection = false
    req.automaticallyDetectsLanguage = false
    req.minimumTextHeight = 0.0
    let h = VNImageRequestHandler(cgImage: cg, options: [:])
    do { try h.perform([req]) } catch { return "" }
    return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
}
func cc(_ img: CIImage, sat: CGFloat, contrast: CGFloat, bright: CGFloat) -> CIImage {
    CIFilter(name: "CIColorControls", parameters: [kCIInputImageKey: img, kCIInputSaturationKey: sat, kCIInputContrastKey: contrast, kCIInputBrightnessKey: bright])!.outputImage!
}
var variants: [(String, CIImage)] = [("orig", src)]
for c in [1.6, 2.4, 3.5, 5.0] as [CGFloat] {
    let g = cc(src, sat: 0.0, contrast: c, bright: 0.02)
    variants.append(("g\(c)", g))
    variants.append(("gi\(c)", CIFilter(name: "CIColorInvert", parameters: [kCIInputImageKey: g])!.outputImage!))
}
let s0 = CIFilter(name: "CISharpenLuminance", parameters: [kCIInputImageKey: cc(src, sat: 0.0, contrast: 2.4, bright: 0.02), kCIInputSharpnessKey: 1.2])!.outputImage!
variants.append(("sharp", s0))
variants.append(("sharpi", CIFilter(name: "CIColorInvert", parameters: [kCIInputImageKey: s0])!.outputImage!))

var cands: [String: Int] = [:]
var best = ""
for (name, v) in variants {
    for scale in [3.0, 5.0, 8.0] as [CGFloat] {
        guard let cg = render(v, scale: scale) else { continue }
        let t = ocr(cg, level: .accurate).trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { continue }
        print("\(name)x\(Int(scale)): \(t)")
        let cleaned = t.filter { ($0.isLetter && $0.isASCII) || $0.isNumber }
        if cleaned.count >= 3 { cands[cleaned, default: 0] += 1 }
        if cleaned.count > best.filter({ ($0.isLetter && $0.isASCII) || $0.isNumber }).count { best = cleaned }
    }
}
var vote = cands.sorted { $0.value > $1.value }.map { "\($0.key)|\($0.value)" }
print("CANDS:" + vote.prefix(8).joined(separator: ","))
print("BEST:" + best)
