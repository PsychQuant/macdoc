import ArgumentParser
import Foundation

struct BlockSegmentationPipeline {
    let bootstrap = ProjectBootstrap()
    let store = ManifestStore()

    func resolvePageNumbers(total: Int, firstPage: Int?, lastPage: Int?) throws -> [Int] {
        let first = max(firstPage ?? 1, 1)
        let last = min(lastPage ?? total, total)
        guard total > 0 else {
            return []
        }
        guard first <= last else {
            throw ValidationError("頁碼範圍無效: \(first)-\(last)")
        }
        return Array(first...last)
    }

    func ensurePageRecords(in project: inout ResolvedProject) throws {
        if project.manifest.pages.isEmpty {
            project.manifest.pages = bootstrap.pageRecords(from: try PDFScanner().scan(pdfAt: project.pdfURL))
        }
    }

    func ensureRenderedPages(in project: inout ResolvedProject, pageNumbers: [Int], dpi: Double) throws {
        let missingPageNumbers = pageNumbers.filter { pageNumber in
            guard project.manifest.pages.indices.contains(pageNumber - 1) else { return true }
            let page = project.manifest.pages[pageNumber - 1]
            guard let path = page.renderedImagePath else { return true }
            guard FileManager.default.fileExists(atPath: path) else { return true }
            guard let renderedDPI = page.renderedDPI else { return true }
            return renderedDPI < dpi
        }

        if missingPageNumbers.isEmpty {
            return
        }

        let outputDirectory = project.root.appendingPathComponent("pages", isDirectory: true)
        let renderedPages = try PageRenderer().renderPages(
            pdfAt: project.pdfURL,
            outputDirectory: outputDirectory,
            dpi: dpi,
            firstPage: missingPageNumbers.min(),
            lastPage: missingPageNumbers.max()
        )
        let renderedByPage = Dictionary(uniqueKeysWithValues: renderedPages.map { ($0.pageNumber, $0.imagePath) })
        project.manifest.pages = project.manifest.pages.map { page in
            var updated = page
            if let imagePath = renderedByPage[page.number] {
                updated.renderedImagePath = imagePath
                updated.renderedDPI = dpi
            }
            return updated
        }
    }

    func segmentBlocks(in project: inout ResolvedProject, pageNumbers: [Int], pageDPI: Double) throws -> [BlockRecord] {
        try ensurePageRecords(in: &project)
        try ensureRenderedPages(in: &project, pageNumbers: pageNumbers, dpi: max(pageDPI, 216))

        let segmenter = BlockSegmenter()
        let cropper = BlockImageCropper()
        var generatedBlocks: [BlockRecord] = []

        for pageNumber in pageNumbers {
            let blockDirectory = project.root
                .appendingPathComponent("blocks", isDirectory: true)
                .appendingPathComponent(String(format: "page-%04d", pageNumber), isDirectory: true)
            try? FileManager.default.removeItem(at: blockDirectory)

            let pageRecord = project.manifest.pages[pageNumber - 1]
            guard let pageImagePath = pageRecord.renderedImagePath else {
                throw ValidationError("第 \(pageNumber) 頁缺少渲染圖片。")
            }

            let pageImageURL = URL(fileURLWithPath: pageImagePath)
            let pageImage = try CGImageLoader.load(from: pageImageURL)
            let detectedBlocks = try segmenter.segment(
                pageImage: pageImage,
                pageWidth: pageRecord.width,
                pageHeight: pageRecord.height
            )

            var pageBlocks: [BlockRecord] = []
            for (index, block) in detectedBlocks.enumerated() {
                let blockID = String(format: "p%04d-b%04d", pageNumber, index + 1)
                let blockImageURL = blockDirectory.appendingPathComponent("block-\(String(format: "%04d", index + 1)).png")

                try cropper.crop(
                    pageImageURL: pageImageURL,
                    pageWidth: pageRecord.width,
                    pageHeight: pageRecord.height,
                    bbox: block.bbox,
                    outputURL: blockImageURL
                )

                pageBlocks.append(
                    BlockRecord(
                        id: blockID,
                        page: pageNumber,
                        type: block.type,
                        status: .segmented,
                        bbox: block.bbox,
                        imagePath: blockImageURL.path,
                        latexPath: nil,
                        textPreview: block.textPreview,
                        notes: nil
                    )
                )
            }

            generatedBlocks.append(contentsOf: pageBlocks)
            project.manifest.blocks.removeAll { $0.page == pageNumber }
            project.manifest.blocks.append(contentsOf: pageBlocks)
            project.manifest.blocks.sort { lhs, rhs in
                if lhs.page != rhs.page {
                    return lhs.page < rhs.page
                }
                return lhs.id < rhs.id
            }
            project.manifest.updatedAt = Support.nowISO8601()
            try store.save(project.manifest, to: project.manifestURL)
        }

        return generatedBlocks
    }

    func ensureBlocks(in project: inout ResolvedProject, pageNumbers: [Int], pageDPI: Double) throws -> [BlockRecord] {
        try ensurePageRecords(in: &project)
        let selectedSet = Set(pageNumbers)
        let existing = project.manifest.blocks.filter { selectedSet.contains($0.page) }
        let missingPages = pageNumbers.filter { pageNumber in
            let blocks = existing.filter { $0.page == pageNumber }
            guard !blocks.isEmpty else { return true }
            return blocks.contains { block in
                guard let imagePath = block.imagePath else { return true }
                return !FileManager.default.fileExists(atPath: imagePath)
            }
        }

        if missingPages.isEmpty {
            return existing.sorted { lhs, rhs in
                if lhs.page != rhs.page {
                    return lhs.page < rhs.page
                }
                return lhs.id < rhs.id
            }
        }

        _ = try segmentBlocks(in: &project, pageNumbers: pageNumbers, pageDPI: pageDPI)
        return project.manifest.blocks.filter { selectedSet.contains($0.page) }.sorted { lhs, rhs in
            if lhs.page != rhs.page {
                return lhs.page < rhs.page
            }
            return lhs.id < rhs.id
        }
    }
}
