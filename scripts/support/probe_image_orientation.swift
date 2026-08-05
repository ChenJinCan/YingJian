import Foundation
import ImageIO

guard CommandLine.arguments.count == 2 else {
  FileHandle.standardError.write(Data("usage: probe_image_orientation.swift IMAGE\n".utf8))
  exit(2)
}

let url = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
guard
  let source = CGImageSourceCreateWithURL(url, nil),
  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
    as? [CFString: Any]
else {
  FileHandle.standardError.write(Data("unable to read ImageIO properties\n".utf8))
  exit(1)
}

let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
print(orientation)
