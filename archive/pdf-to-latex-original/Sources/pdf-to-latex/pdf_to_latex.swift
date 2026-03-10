import ArgumentParser
import Foundation

@main
struct PDFToLatexCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pdf-to-latex",
        abstract: "macOS 上的 PDF 轉 LaTeX 工作流骨架。",
        discussion: """
        這個 CLI 先處理可重現的本地步驟：建立專案、掃描 PDF 頁面、維護 manifest，
        後續再往 block segmentation、AI 轉寫、像素驗證與 lossless 組裝擴充。
        """,
        version: "0.1.0",
        subcommands: [
            InitProject.self,
            Segment.self,
            RenderPages.self,
            SegmentBlocks.self,
            TranscribeBlocks.self,
            Resume.self,
            DetectChapters.self,
            AssembleTex.self,
            Status.self,
        ],
        defaultSubcommand: Status.self
    )
}
