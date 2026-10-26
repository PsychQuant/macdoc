import ArgumentParser
import CoreGraphics
import Foundation
import PDFFormFill
import PDFVisualDiff

/// Shared path handling, output and error messages for the form commands
/// (PsychQuant/macdoc#240).
enum FormCommandSupport {
    static func absoluteURL(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return URL(fileURLWithPath: expanded).standardizedFileURL }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(expanded).standardizedFileURL
    }

    /// An existing input file, reported as missing the way every macdoc command does.
    static func inputURL(_ path: String) throws -> URL {
        try validatedInputURL(absoluteURL(path).path).standardizedFileURL
    }

    /// "x0,y0,x1,y1" in bp → rectangle with a top-left origin.
    static func parseRect(_ text: String) throws -> CGRect {
        let values = text.split(separator: ",", omittingEmptySubsequences: false)
            .map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard values.count == 4, let x0 = values[0], let y0 = values[1], let x1 = values[2], let y1 = values[3],
              [x0, y0, x1, y1].allSatisfy(\.isFinite), x1 > x0, y1 > y0 else {
            throw ValidationError("--preserve 需要四個有限數 x0,y0,x1,y1（bp，x1 > x0、y1 > y0），收到：\(text)")
        }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// Path of `file` relative to `directory` when `file` lies inside it, otherwise absolute.
    static func relativePath(of file: URL, from directory: URL) -> String {
        let fileParts = file.standardizedFileURL.pathComponents
        let dirParts = directory.standardizedFileURL.pathComponents
        guard fileParts.count > dirParts.count, Array(fileParts.prefix(dirParts.count)) == dirParts else {
            return file.standardizedFileURL.path
        }
        return fileParts.dropFirst(dirParts.count).joined(separator: "/")
    }

    static func size(_ size: CGSize, decimals: Int = 2) -> String {
        String(format: "%.\(decimals)f × %.\(decimals)f bp", size.width, size.height)
    }

    /// Two sizes printed with the fewest decimals (2, 4, …, 16) at which
    /// they differ when they are different.
    static func distinctSizes(_ a: CGSize, _ b: CGSize) -> (String, String) {
        for digits in stride(from: 2, through: 16, by: 2) where a == b || size(a, decimals: digits) != size(b, decimals: digits) {
            return (size(a, decimals: digits), size(b, decimals: digits))
        }
        // Shortest notation that reads back to the same value.
        func exact(_ s: CGSize) -> String { "\(Double(s.width)) × \(Double(s.height)) bp" }
        return (exact(a), exact(b))
    }

    /// The A4 classification of a size in either orientation, as
    /// `macdoc pdf compare` reports it, marked when the page is landscape
    /// (page mode a4 normalizes only to portrait A4).
    static func classification(_ size: CGSize) -> String {
        let portrait = CGSize(width: min(size.width, size.height), height: max(size.width, size.height))
        let name = PageGeometry.classify(portrait).rawValue
        return size.width > size.height ? "\(name), landscape" : name
    }

    /// Refuses a diff directory whose artifacts would replace one of `inputs`.
    static func refuseArtifactCollisions(in directory: URL, inputs: [(URL, String)]) throws {
        guard let hit = DiffArtifacts.collision(in: directory, with: inputs) else { return }
        FileHandle.standardError.write(Data("錯誤：差值產物 \(hit.artifact.path) 會蓋掉\(hit.role)；請換一個 --diff-dir\n".utf8))
        throw ExitCode.failure
    }

    /// The status line macdoc prints on stderr after writing a file or directory.
    static func reportWritten(_ url: URL, note: String? = nil) {
        let suffix = note.map { "（\($0)）" } ?? ""
        FileHandle.standardError.write(Data("已寫入: \(url.path)\(suffix)\n".utf8))
    }

    static func printDiffSummary(_ diff: SignedDiff) {
        let ranges = (0..<3).map { "\(["R", "G", "B"][$0]) \(diff.channelMin[$0])..\(diff.channelMax[$0])" }
        print(String(format: "Changed pixels: %d of %d × %d at %.0f dpi; D %@",
                     diff.changedPixelCount, diff.width, diff.height, diff.dpi, ranges.joined(separator: ", ")))
    }

    /// Bands printed per check; the rest are counted.
    static let bandLimit = 10

    /// Prints one line per check plus its bands; returns true when all are 0.
    @discardableResult
    static func printChecks(_ checks: [CheckResult]) -> Bool {
        for check in checks {
            print("\(check.count == 0 ? "✓" : "✗") \(check.check.rawValue): \(check.count) px")
            for band in check.bands.prefix(bandLimit) {
                print(String(format: "    y %.1f–%.1f  x %.1f–%.1f bp  %d px",
                             band.top, band.bottom, band.left, band.right, band.pixels))
            }
            if check.bands.count > bandLimit {
                let more = check.bands.count - bandLimit
                print("    … \(more) more band\(more == 1 ? "" : "s") (all bands are in report.json with --diff-dir)")
            }
        }
        return checks.allSatisfy { $0.count == 0 }
    }

    /// Runs `body` with file descriptor 2 pointed at /dev/null, restoring it
    /// afterwards. For library calls that log noise on stderr; the redirect
    /// covers the whole process while `body` runs.
    static func withStderrSilenced<T>(_ body: () throws -> T) rethrows -> T {
        fflush(stderr)
        let saved = dup(STDERR_FILENO)
        let null = open("/dev/null", O_WRONLY)
        if saved >= 0 && null >= 0 { dup2(null, STDERR_FILENO) }
        defer {
            fflush(stderr)
            if saved >= 0 { dup2(saved, STDERR_FILENO); close(saved) }
            if null >= 0 { close(null) }
        }
        return try body()
    }

    /// Runs `body`; a library or file-system error is printed on stderr in
    /// Traditional Chinese and turned into a failing exit status.
    static func reportingErrors<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as FormFillError {
            FileHandle.standardError.write(Data("錯誤：\(message(for: error))\n".utf8))
            throw ExitCode.failure
        } catch let error as PDFVisualDiffError {
            FileHandle.standardError.write(Data("錯誤：\(message(for: error))\n".utf8))
            throw ExitCode.failure
        } catch let error as CocoaError {
            let path = error.filePath ?? error.userInfo[NSFilePathErrorKey] as? String ?? "（路徑不明）"
            FileHandle.standardError.write(Data("錯誤：無法讀寫檔案：\(path)（\(reason(for: error.code))）\n".utf8))
            throw ExitCode.failure
        } catch let error as POSIXError {
            FileHandle.standardError.write(Data("錯誤：系統呼叫失敗（錯誤代碼 \(error.code.rawValue)）\n".utf8))
            throw ExitCode.failure
        }
    }

    /// A Chinese reason for the common file-system failures; other codes are
    /// named by number, never by the system-language description.
    static func reason(for code: CocoaError.Code) -> String {
        switch code {
        case .fileNoSuchFile, .fileReadNoSuchFile: return "找不到檔案或資料夾"
        case .fileWriteNoPermission, .fileReadNoPermission: return "沒有權限"
        case .fileWriteVolumeReadOnly: return "磁碟區是唯讀的"
        case .fileWriteOutOfSpace: return "磁碟空間不足"
        case .fileWriteFileExists: return "檔案已存在"
        case .fileWriteInvalidFileName, .fileReadInvalidFileName: return "檔名無效"
        default: return "錯誤代碼 \(code.rawValue)"
        }
    }

    static func message(for error: FormFillError) -> String {
        switch error {
        case .unreadablePDF(let path):
            return "無法開啟 PDF：\(path)"
        case .lockedPDF(let path):
            return "PDF 需要密碼才能讀取：\(path)；請先移除密碼"
        case .emptyPDF(let path):
            return "PDF 沒有任何頁面：\(path)"
        case .multiPageOriginal(let pages):
            return "原表有 \(pages) 頁；只支援單頁表單"
        case .engineNotFound(let engine):
            return "找不到 TeX 引擎：\(engine)"
        case .compilationFailed(let logTail):
            return "疊印層編譯失敗；log 最後幾行：\n\(logTail)"
        case .compilationTimedOut(let seconds):
            return String(format: "疊印層編譯超過 %g 秒仍未結束，已停止", seconds)
        case .invalidTimeout(let seconds):
            return "編譯逾時必須是大於 0 的有限秒數，收到 \(seconds)"
        case let .overlayWrongSize(width, height, expectedWidth, expectedHeight):
            return String(format: "疊印層頁面是 %.2f × %.2f bp，成品頁面是 %.2f × %.2f bp；疊印層必須與成品同尺寸"
                + "（--page a4 用 A4，--page original 用原表尺寸），請在 geometry 套件設定紙張大小",
                width, height, expectedWidth, expectedHeight)
        case .overlayPageCount(let pages):
            return "疊印層有 \(pages) 頁；必須剛好一頁"
        case let .notNearA4(width, height):
            return String(format: "原表是 %.2f × %.2f bp，不接近 A4；請用 --page original，"
                + "並讓疊印層與原表同尺寸（form-skeleton 產生的骨架已經是這個尺寸）", width, height)
        case .inkInRemovedStrip(let pixels):
            return "校正成 A4 會裁掉原表 \(pixels) 個有墨的像素；請用 --page original，並讓疊印層與原表同尺寸"
        case .rotatedOriginal(let degrees):
            return "原表頁面旋轉了 \(degrees)°；只支援未旋轉的頁面"
        case .annotatedOriginal(let count):
            return "原表帶有 \(count) 個註解（連結、表單欄位或註記）；蓋印只複製頁面內容，"
                + "這些註解會遺失而逐像素檢查看不到，請先將 PDF 平面化"
        case .rotatedOverlay(let degrees):
            return "疊印層頁面旋轉了 \(degrees)°；只支援未旋轉的疊印層"
        case .overlayInkOffPage(let pixels):
            return "疊印層有 \(pixels) 個有墨像素落在頁面外，表示有字超出頁緣、會被裁掉；請移動或縮短該欄位"
        case .blankFormMacroMissing(let path):
            return "\(path) 裡沒有 \\newcommand{\\BlankForm}{…}（或 \\def\\BlankForm{…}）"
        case .blankFormNotFound(let path):
            return "找不到空白表單：\(path)"
        case .unsafeBlankFormPath(let path):
            return "空白表單的路徑含有 TeX 會誤讀的字元（\\ { } % # ^ 或控制字元）：\(path.debugDescription)；請改檔名或所在資料夾名稱"
        case let .outputIsInput(path, role):
            let names = ["blank form": "空白表單", ".tex source": ".tex 原始檔", "compiled overlay": "編譯後的疊印層"]
            return "不能把成品寫在\(names[role] ?? role)上：\(path)；請用 --output 指定別的檔名"
        case .outputNotAFile(let path):
            return "成品路徑已存在且不是一般檔案（資料夾或符號連結）：\(path)；請用 --output 指定要寫出的 PDF 檔名"
        case let .diffArtifactCollides(path, role):
            let names = ["output": "成品", "blank form": "空白表單", ".tex source": ".tex 原始檔"]
            return "差值產物 \(path) 會蓋掉\(names[role] ?? role)；請換一個 --diff-dir"
        case .unreadableSource(let path):
            return "無法以 UTF-8 讀取 .tex：\(path)"
        case .overlayTextOffPage(let count):
            return "疊印層有 \(count) 處繪圖落在頁外超過 0.9 頁的地方，任何算繪都看不到；請檢查欄位座標"
        case .overlayUnverifiable(let parts):
            return "疊印層有 \(parts) 處無法定位，無法確認是否畫到頁外（字型沒有字寬資料、讀不完的表單物件、"
                + "找不到的資源名稱、讀不到的運算元，或無法解析的內容）；請簡化疊印層"
        case .unstampable(let refusal):
            return "無法把 PDF 的物件複製到成品（\(reason(for: refusal))），這份表單無法照原樣蓋印"
        case .textOutsideNodes(let characters):
            return "疊印層有寫在節點外的文字（\(characters.joined(separator: " "))），不會印出；"
                + "請放進 \\at 節點或刪除（多打的 ; 也算）"
        case .missingCharacters(let characters):
            return "疊印層的字型沒有這些字：\(characters.joined(separator: " "))，xelatex 已把它們略過；"
                + "請改用含有這些字的字型（例如 \\setCJKmainfont，或設定後備字型）"
        case .annotatedOverlay(let count):
            return "疊印層帶有 \(count) 個註解（連結或表單欄位）；蓋印只複製頁面內容，這些註解會遺失，"
                + "請從 .tex 移除（例如 hyperref 的連結與表單欄位）"
        case .outputWriteFailed(let path):
            return "無法寫入：\(path)"
        }
    }

    /// Why stamping was refused, in Chinese; the library's own text is English.
    static func reason(for refusal: StampRefusal) -> String {
        switch refusal {
        case .unreadable(let kind):
            switch kind {
            case .name: return "有讀不到的名稱"
            case .string: return "有讀不到的字串"
            case .number: return "有讀不到的數字"
            case .array: return "有讀不到的陣列"
            case .dictionary: return "有讀不到的字典"
            case .stream: return "有讀不到的串流"
            case .unknown: return "有無法辨識類型的物件"
            }
        case .externalStream: return "有資料存放在外部檔案的串流"
        case .undecodableStream: return "有無法解碼的串流"
        case .nestedTooDeep(let limit): return "物件巢狀超過 \(limit) 層"
        case .nonFiniteNumber: return "有無限大或不是數值的數字"
        case .tooLarge(let limit): return String(format: "複製的內容會超過 %g MB 的上限", Double(limit) / 1_048_576)
        case .compressionFailed: return "串流壓縮失敗"
        case .overlayHasLayers: return "疊印層有自己的圖層，無法和原表的圖層合併"
        case .undecodableOverlayContent: return "疊印層的頁面內容無法解碼"
        case .contentEntryNotStream: return "頁面內容清單裡有不是串流的項目"
        case .unwrittenObject(let number): return "第 \(number) 號物件保留了卻沒有寫出，這是程式內部的錯誤，請回報"
        }
    }

    static func message(for error: PDFVisualDiffError) -> String {
        switch error {
        case .unreadablePDF(let path):
            return "無法開啟 PDF：\(path)"
        case let .pageOutOfRange(index, count):
            return "第 \(index + 1) 頁超出文件範圍（共 \(count) 頁）"
        case .unsupportedRotation(let degrees):
            return "頁面旋轉了 \(degrees)°；只能比對未旋轉的頁面"
        case .invalidResolution(let dpi):
            return "解析度必須介於 \(Int(PageRaster.minDPI)) 到 \(Int(PageRaster.maxDPI)) dpi，收到 \(dpi)"
        case let .bitmapContextUnavailable(width, height):
            return "無法配置 \(width) × \(height) 像素的點陣"
        case let .bitmapTooLarge(width, height, limit):
            return String(format: "%.0f × %.0f 像素的點陣超過上限 %d 像素；請降低 --dpi", width, height, limit)
        case .invalidRegion(let index):
            return "保留區域 \(index) 必須是有限座標，且 x0 < x1、y0 < y1"
        case let .invalidPageSize(width, height):
            return "頁面尺寸必須是正的有限數，收到 \(width) × \(height) bp"
        case let .invalidRaster(width, height, bytes):
            return "點陣大小無效（\(width) × \(height)，\(bytes) bytes）"
        case .sizeMismatch(let detail):
            return "兩份點陣對不齊：\(detail)"
        case .inkInRemovedStrip(let pixels):
            return "校正成 A4 會裁掉 \(pixels) 個有墨的像素"
        case let .artifactWriteFailed(path, code):
            return "無法寫出差值產物：\(path)（\(code.map(reason(for:)) ?? "原因不明")）"
        case .artifactEncodingFailed(let name):
            return "無法編碼差值產物 \(name)"
        }
    }
}
