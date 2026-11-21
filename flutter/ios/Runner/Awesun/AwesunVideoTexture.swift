import CoreImage
import Flutter
import IOSurface
import UIKit
import VideoToolbox

/// The compressed stream crosses the bridge. Flutter receives the decoder's
/// original IOSurface-backed pixel buffer, without a pixel readback or a Dart image.
final class AwesunVideoTexture: NSObject, FlutterTexture {
    static let shared = AwesunVideoTexture()

    private let state = NSLock()
    private let decoderLock = NSLock()
    private var registry: FlutterTextureRegistry?
    private var channel: FlutterMethodChannel?
    private var textureId: Int64?
    private var pixelBuffer: CVPixelBuffer?
    private var presentedSize = CGSize.zero
    private var presentQueued = false
    private var generation: UInt64 = 0
    private var frameSerial: UInt64 = 0
    private var outputFailed = false
    private var decoder: VTDecompressionSession?
    private var format: CMVideoFormatDescription?
    private var parameters: [UInt8: Data] = [:]
    private var codec: UInt32 = 0
    private var display: Int32 = -1
    private var unconfiguredKeyframes = 0
    private var badKeyframes = 0
    private let captureContext = CIContext()

    func attach(registry: FlutterTextureRegistry?, channel: FlutterMethodChannel) {
        self.registry = registry
        self.channel = channel
    }

    func configure(enabled: Bool) -> Bool {
        guard let registry = registry else { return false }
        if enabled {
            guard Self.supportedCodecs != 0 else { return false }
            state.lock()
            let registered = textureId != nil
            state.unlock()
            if !registered {
                let id = registry.register(self)
                guard id != 0 else { return false }
                state.lock()
                textureId = id
                generation &+= 1
                state.unlock()
            }
            return true
        }

        state.lock()
        let id = textureId
        textureId = nil
        generation &+= 1
        pixelBuffer = nil
        presentedSize = .zero
        presentQueued = false
        state.unlock()
        if let id = id { registry.unregisterTexture(id) }
        decoderLock.lock()
        resetDecoder()
        parameters.removeAll(keepingCapacity: true)
        codec = 0
        display = -1
        unconfiguredKeyframes = 0
        badKeyframes = 0
        decoderLock.unlock()
        return false
    }

    private static var supportedCodecs: UInt32 {
        let h264: UInt32 = VTIsHardwareDecodeSupported(kCMVideoCodecType_H264) ? 1 : 0
        let hevc: UInt32 = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC) ? 2 : 0
        return h264 | hevc
    }

    func capabilities() -> UInt32 {
        state.lock()
        let active = textureId != nil
        state.unlock()
        return active ? Self.supportedCodecs : 0
    }

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        state.lock()
        let current = pixelBuffer
        state.unlock()
        return current.map { Unmanaged.passRetained($0) }
    }

    func screenshotPNG() -> Data? {
        state.lock()
        let current = pixelBuffer
        state.unlock()
        guard let current = current else { return nil }
        let image = CIImage(cvPixelBuffer: current)
        guard let snapshot = captureContext.createCGImage(image, from: image.extent) else {
            return nil
        }
        return UIImage(cgImage: snapshot).pngData()
    }

    fileprivate func decode(codec incoming: UInt32, display screen: Int32,
                            data: Data, pts: Int64, key: Bool) -> Int32 {
        decoderLock.lock()
        defer { decoderLock.unlock() }
        let capability = incoming == 1 ? UInt32(1) : UInt32(2)
        guard capabilities() & capability != 0 else { return -1 }

        if incoming != codec || screen != display {
            resetDecoder()
            parameters.removeAll(keepingCapacity: true)
            codec = incoming
            display = screen
            unconfiguredKeyframes = 0
            badKeyframes = 0
        }

        guard let units = Self.nalUnits(data) else { return fail() }
        let types: [UInt8] = incoming == 1 ? [7, 8] : [32, 33, 34]
        var payload = Data()
        var newParameters = false
        var containsPicture = false
        for unit in units {
            guard let first = unit.first else { continue }
            let type = incoming == 1 ? first & 0x1f : (first >> 1) & 0x3f
            if types.contains(type) {
                newParameters = newParameters || parameters[type] != unit
                parameters[type] = unit
                continue
            }
            if incoming == 1 ? (1...5).contains(type) : type <= 31 { containsPicture = true }
            var length = UInt32(unit.count).bigEndian
            withUnsafeBytes(of: &length) { payload.append(contentsOf: $0) }
            payload.append(unit)
        }

        if newParameters { resetDecoder() }
        if decoder == nil {
            guard types.allSatisfy({ parameters[$0] != nil }) else {
                if key { unconfiguredKeyframes += 1 }
                return unconfiguredKeyframes > 1 ? fail() : 0
            }
            guard openDecoder(types: types) else { return fail() }
            unconfiguredKeyframes = 0
        }
        guard containsPicture, let format = format, let decoder = decoder else { return 0 }
        guard let sample = Self.sample(payload, format: format, pts: pts) else { return fail() }
        state.lock()
        let before = frameSerial
        outputFailed = false
        state.unlock()
        let status = VTDecompressionSessionDecodeFrame(
            decoder, sampleBuffer: sample, flags: [], frameRefcon: nil, infoFlagsOut: nil
        )
        state.lock()
        let count = frameSerial
        let failed = outputFailed
        state.unlock()
        if status == kVTVideoDecoderBadDataErr {
            // The bounded receiver queue requests a keyframe after a discontinuity.
            // Keep the current texture and let that recovery take place.
            if key {
                badKeyframes += 1
                if badKeyframes >= 3 { return fail() }
            }
            return 0
        }
        if status != noErr || failed { return fail() }
        if count != before {
            badKeyframes = 0
            return 1
        }
        return 0
    }

    // Both Annex B and four-byte length prefixes occur with hardware encoders.
    private static func nalUnits(_ data: Data) -> [Data]? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return nil }
        func startCode(at index: Int) -> Int {
            if index + 2 >= bytes.count || bytes[index] != 0 || bytes[index + 1] != 0 { return 0 }
            if bytes[index + 2] == 1 { return 3 }
            if index + 3 < bytes.count && bytes[index + 2] == 0 && bytes[index + 3] == 1 { return 4 }
            return 0
        }

        var result: [Data] = []
        let first = startCode(at: 0)
        if first != 0 {
            var from = first
            var index = first
            while index < bytes.count {
                let prefix = startCode(at: index)
                if prefix == 0 {
                    index += 1
                } else {
                    if from < index { result.append(Data(bytes[from..<index])) }
                    index += prefix
                    from = index
                }
            }
            if from < bytes.count { result.append(Data(bytes[from..<bytes.count])) }
        } else {
            var index = 0
            while index + 4 <= bytes.count {
                let length = (Int(bytes[index]) << 24) | (Int(bytes[index + 1]) << 16) |
                    (Int(bytes[index + 2]) << 8) | Int(bytes[index + 3])
                index += 4
                if length <= 0 || length > bytes.count - index { return nil }
                result.append(Data(bytes[index..<(index + length)]))
                index += length
            }
            if index != bytes.count { return nil }
        }
        return result.isEmpty ? nil : result
    }

    private static func sample(_ data: Data, format: CMVideoFormatDescription,
                               pts: Int64) -> CMSampleBuffer? {
        guard !data.isEmpty else { return nil }
        var block: CMBlockBuffer?
        let allocation = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: data.count,
            blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
            dataLength: data.count, flags: 0, blockBufferOut: &block
        )
        guard allocation == noErr, let block = block else { return nil }
        let copy = data.withUnsafeBytes { bytes -> OSStatus in
            guard let base = bytes.baseAddress else { return -1 }
            return CMBlockBufferReplaceDataBytes(with: base, blockBuffer: block,
                                                 offsetIntoDestination: 0, dataLength: data.count)
        }
        guard copy == noErr else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid,
            presentationTimeStamp: CMTime(value: pts, timescale: 1000), decodeTimeStamp: .invalid)
        var size = data.count
        var sample: CMSampleBuffer?
        let status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample
        )
        return status == noErr ? sample : nil
    }

    private func openDecoder(types: [UInt8]) -> Bool {
        let values = types.compactMap { parameters[$0].map { NSData(data: $0) } }
        guard values.count == types.count else { return false }
        let pointers = values.map { $0.bytes.assumingMemoryBound(to: UInt8.self) }
        let sizes = values.map(\.length)
        var description: CMFormatDescription?
        let status: OSStatus = withExtendedLifetime(values) {
            codec == 1
            ? CMVideoFormatDescriptionCreateFromH264ParameterSets(
                allocator: kCFAllocatorDefault, parameterSetCount: values.count,
                parameterSetPointers: pointers, parameterSetSizes: sizes, nalUnitHeaderLength: 4,
                formatDescriptionOut: &description)
            : CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                allocator: kCFAllocatorDefault, parameterSetCount: values.count,
                parameterSetPointers: pointers, parameterSetSizes: sizes, nalUnitHeaderLength: 4,
                extensions: nil, formatDescriptionOut: &description)
        }
        guard status == noErr, let description = description else { return false }
        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { reference, _, status, _, image, _, _ in
                guard let reference = reference else { return }
                Unmanaged<AwesunVideoTexture>.fromOpaque(reference).takeUnretainedValue()
                    .receive(status: status, image: image)
            },
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
        var output: VTDecompressionSession?
        let result = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault, formatDescription: description,
            decoderSpecification: nil, imageBufferAttributes: attributes as CFDictionary,
            outputCallback: &callback, decompressionSessionOut: &output
        )
        guard result == noErr, let output = output else { return false }
        format = description
        decoder = output
        return true
    }

    private func resetDecoder() {
        if let decoder = decoder { VTDecompressionSessionInvalidate(decoder) }
        decoder = nil
        format = nil
    }

    private func receive(status: OSStatus, image: CVImageBuffer?) {
        state.lock()
        defer { state.unlock() }
        guard textureId != nil else { return }
        guard status == noErr else {
            outputFailed = status != kVTVideoDecoderBadDataErr
            return
        }
        guard let image = image else { return }
        guard CVPixelBufferGetIOSurface(image) != nil else { outputFailed = true; return }
        pixelBuffer = image
        frameSerial &+= 1
        guard !presentQueued else { return }
        presentQueued = true
        let currentGeneration = generation
        DispatchQueue.main.async { [weak self] in self?.publish(generation: currentGeneration) }
    }

    private func publish(generation expected: UInt64) {
        state.lock()
        guard generation == expected, let id = textureId else { state.unlock(); return }
        presentQueued = false
        guard let image = pixelBuffer else { state.unlock(); return }
        let size = CGSize(width: CVPixelBufferGetWidth(image), height: CVPixelBufferGetHeight(image))
        let changed = size != presentedSize
        presentedSize = size
        state.unlock()
        registry?.textureFrameAvailable(id)
        if changed {
            channel?.invokeMethod("nativeVideoTexture", arguments: [
                "id": id, "width": Int(size.width), "height": Int(size.height)
            ])
        }
    }

    private func fail() -> Int32 {
        resetDecoder()
        state.lock()
        let expected = generation
        pixelBuffer = nil
        presentedSize = .zero
        state.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.state.lock()
            let current = self.generation == expected && self.textureId != nil &&
                self.pixelBuffer == nil
            self.state.unlock()
            if current { self.channel?.invokeMethod("nativeVideoTexture", arguments: nil) }
        }
        return -1
    }
}

@_cdecl("rustdesk_ios_texture_capabilities")
func rustdesk_ios_texture_capabilities() -> UInt32 {
    AwesunVideoTexture.shared.capabilities()
}

@_cdecl("rustdesk_ios_texture_decode")
func rustdesk_ios_texture_decode(_ codec: UInt32, _ display: Int32,
                                 _ bytes: UnsafePointer<UInt8>?, _ length: Int,
                                 _ pts: Int64, _ key: Bool) -> Int32 {
    guard let bytes = bytes, (1...(16 * 1024 * 1024)).contains(length) else { return -1 }
    return AwesunVideoTexture.shared.decode(codec: codec, display: display,
                                           data: Data(bytes: bytes, count: length), pts: pts, key: key)
}
