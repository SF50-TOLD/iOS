// Runs the formatted-report parsers over a NOTAM corpus.
//
// Reads Model Training corpus records (JSON Lines with `id` and `notam_text`) from standard input and
// writes one line per record to standard output, `{"id": …, "extraction": …}`, where the extraction is
// `null` when the parsers decline. A count of readings and declines goes to standard error.
//
//     gzip -dc data/corpus.jsonl.gz | swift run notam-corpus > parsed.jsonl

import Foundation
import NOTAMModel
import NOTAMParsing

struct CorpusRecord: Decodable {
  let id: String
  let notam_text: String
}

struct ParsedRecord: Encodable {
  let id: String
  let extraction: NOTAMExtraction?
}

let decoder = JSONDecoder(), encoder = JSONEncoder()

encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

let parser = FormattedReportParser()
var readCount = 0, declinedCount = 0

while let line = readLine(strippingNewline: true) {
  guard !line.isEmpty else { continue }
  let record = try decoder.decode(CorpusRecord.self, from: Data(line.utf8))
  let extraction = parser.parse(notamText: record.notam_text).map(NOTAMExtraction.init)
  if extraction == nil { declinedCount += 1 } else { readCount += 1 }
  let output = try encoder.encode(ParsedRecord(id: record.id, extraction: extraction))
  FileHandle.standardOutput.write(output + Data("\n".utf8))
}

FileHandle.standardError.write(Data("read \(readCount), declined \(declinedCount)\n".utf8))
