//
//  TIFFDeflateExtension.m
//  DownloadNASR
//
//  Provides DEFLATE decompression support for tiff-ios library.
//  The tiff-ios library has DEFLATE as a stub - this implements it using zlib.
//

#import <TIFF/TIFFDeflateCompression.h>
#import <zlib.h>

@implementation TIFFDeflateCompression (Deflate)

// Intentionally overriding the stub implementation that throws "Not Implemented"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"
- (NSData *)decodeData:(NSData *)data withByteOrder:(CFByteOrder)byteOrder {
  if (data == nil || data.length == 0) {
    return data;
  }

  // Allocate output buffer - GeoTIFF tiles can be large
  // Start with 4x input size and grow if needed
  NSUInteger outputCapacity = data.length * 4;
  NSMutableData *output = [NSMutableData dataWithLength:outputCapacity];

  z_stream stream;
  memset(&stream, 0, sizeof(stream));

  stream.next_in = (Bytef *)data.bytes;
  stream.avail_in = (uInt)data.length;
  stream.next_out = (Bytef *)output.mutableBytes;
  stream.avail_out = (uInt)outputCapacity;

  // Initialize with automatic header detection (zlib or raw deflate)
  // windowBits = 15 + 32 enables automatic header detection
  int result = inflateInit2(&stream, 15 + 32);
  if (result != Z_OK) {
    // Try raw deflate (no header)
    result = inflateInit2(&stream, -15);
    if (result != Z_OK) {
      return nil;
    }
  }

  NSMutableData *decompressed = [NSMutableData data];

  do {
    stream.next_out = (Bytef *)output.mutableBytes;
    stream.avail_out = (uInt)outputCapacity;

    result = inflate(&stream, Z_NO_FLUSH);

    if (result == Z_STREAM_ERROR || result == Z_DATA_ERROR || result == Z_MEM_ERROR) {
      inflateEnd(&stream);
      return nil;
    }

    NSUInteger bytesDecompressed = outputCapacity - stream.avail_out;
    [decompressed appendBytes:output.bytes length:bytesDecompressed];

  } while (result != Z_STREAM_END && stream.avail_in > 0);

  inflateEnd(&stream);

  return decompressed;
}
#pragma clang diagnostic pop

@end
