# 在 Mac 上使用 Local LLM — mlx-swift-lm 指南

## 概述

[mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) 是 Apple MLX 團隊（`ml-explore`）官方維護的 Swift package，讓開發者在 Apple Silicon Mac 上直接跑 LLM / VLM / Embedding 模型，不需要 Python、不需要 Ollama、不需要網路。

一行 dependency，import 即用。

## 四個 Library

```
mlx-swift-lm
├── MLXLMCommon     — 共用 API（ModelContainer, generate, UserInput）
├── MLXLLM          — 純文字 LLM（Llama, Qwen, Gemma 等）
├── MLXVLM          — Vision Language Model（看圖生文、OCR）
└── MLXEmbedders    — Embedding 模型（向量搜尋、語意比對）
```

| Library | 用途 | 典型場景 |
|---------|------|---------|
| **MLXLMCommon** | 共用基礎設施 | 所有 LLM/VLM 都需要 |
| **MLXLLM** | 純文字生成 | 本地摘要、翻譯、程式碼生成 |
| **MLXVLM** | 圖片 + 文字 | OCR、圖片描述、文件理解 |
| **MLXEmbedders** | 文字向量化 | 語意搜尋、相似度比對 |

## 安裝

在 `Package.swift` 加入依賴：

```swift
dependencies: [
    .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "2.30.0"),
]
```

Target 中 import 需要的 library：

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "MLXVLM", package: "mlx-swift-lm"),
        .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
    ]
)
```

## 基本用法（VLM 為例）

```swift
import MLXLMCommon
import MLXVLM

// 1. 載入模型（自動從 HuggingFace 下載，快取在 ~/.cache/huggingface/hub/）
let config = ModelConfiguration(id: "mlx-community/Qwen2.5-VL-3B-Instruct-4bit")
let container = try await VLMModelFactory.shared.loadContainer(configuration: config)

// 2. 準備輸入（圖片 + prompt）
let userInput = UserInput(
    prompt: "OCR the text in this image.",
    images: [.ciImage(CIImage(cgImage: myImage))]
)

// 3. 生成
let output = try await container.perform { (context: ModelContext) in
    let input = try await context.processor.prepare(input: userInput)
    var result = ""
    for await token in try MLXLMCommon.generate(
        input: input,
        parameters: .init(temperature: 0.1),
        context: context
    ) {
        result += token.chunk ?? ""
    }
    return result
}
```

## 模型快取

模型下載後快取在 `~/.cache/huggingface/hub/`，格式為：

```
~/.cache/huggingface/hub/
└── models--mlx-community--Qwen2.5-VL-3B-Instruct-4bit/
    └── snapshots/
        └── <hash>/
            ├── config.json
            ├── model.safetensors
            └── ...
```

與 `huggingface-cli` 和 Hub Swift 共用快取，不會重複下載。

## MLXVLM 預設模型

MLXVLM 內建以下預設 `ModelConfiguration`，可直接使用：

### OCR / 文件理解

| 預設名稱 | HuggingFace repo | 參數量 | 說明 |
|---------|-----------------|--------|------|
| `qwen2_5VL3BInstruct4Bit` | mlx-community/Qwen2.5-VL-3B-Instruct-4bit | 3B | 文件理解強，推薦 |
| `qwen3VL4BInstruct4Bit` | lmstudio-community/Qwen3-VL-4B-Instruct-MLX-4bit | 4B | 最新 Qwen VLM |
| `qwen3VL4BInstruct8Bit` | mlx-community/Qwen3-VL-4B-Instruct-8bit | 4B | 8-bit 精度更高 |
| `qwen2VL2BInstruct4Bit` | mlx-community/Qwen2-VL-2B-Instruct-4bit | 2B | 輕量 |
| `paligemma3bMix448_8bit` | mlx-community/paligemma-3b-mix-448-8bit | 3B | Google，OCR 專門訓練 |

### 通用 VLM

| 預設名稱 | HuggingFace repo | 參數量 | 說明 |
|---------|-----------------|--------|------|
| `gemma3_4B_qat_4bit` | mlx-community/gemma-3-4b-it-qat-4bit | 4B | Google Gemma 3 |
| `gemma3_12B_qat_4bit` | mlx-community/gemma-3-12b-it-qat-4bit | 12B | 較大，需 16GB+ RAM |
| `gemma3_27B_qat_4bit` | mlx-community/gemma-3-27b-it-qat-4bit | 27B | 需 32GB+ RAM |
| `mistral3_3B_Instruct_4bit` | mlx-community/Ministral-3-3B-Instruct-2512-4bit | 3B | Mistral |
| `smolvlminstruct4bit` | mlx-community/SmolVLM-Instruct-4bit | ~2B | HuggingFace，輕量 |

### 輕量 / 實驗性

| 預設名稱 | HuggingFace repo | 參數量 | 說明 |
|---------|-----------------|--------|------|
| `fastvlm` | mlx-community/FastVLM-0.5B-bf16 | 0.5B | Apple 自研，極快 |
| `smolvlm` | HuggingFaceTB/SmolVLM2-500M-Video-Instruct-mlx | 0.5B | 支援影片 |
| `lfm2_vl_1_6B_4bit` | mlx-community/LFM2-VL-1.6B-4bit | 1.6B | Liquid Foundation |
| `lfm2_5_vl_1_6B_4bit` | mlx-community/LFM2.5-VL-1.6B-4bit | 1.6B | Liquid Foundation v2.5 |

### 使用預設模型

```swift
// 用預設 configuration（不需要手動輸入 repo ID）
let container = try await VLMModelFactory.shared.loadContainer(
    configuration: VLMRegistry.qwen2_5VL3BInstruct4Bit
)
```

### 使用自訂模型

任何 `mlx-community` 上的模型（或自己轉換的），只要架構在支援清單內，都能用：

```swift
let config = ModelConfiguration(id: "mlx-community/some-other-model-4bit")
let container = try await VLMModelFactory.shared.loadContainer(configuration: config)
```

## 支援的 VLM 架構

MLXVLM 支援以下 VLM 架構（決定了哪些 HuggingFace 模型能載入）：

| 架構 class | 代表模型家族 | 來源 |
|-----------|------------|------|
| `GlmOcr` | GLM-OCR | 智譜 |
| `Qwen2VL` | Qwen2-VL | 阿里 |
| `Qwen25VL` | Qwen2.5-VL | 阿里 |
| `Qwen3VL` | Qwen3-VL | 阿里 |
| `Gemma3` | Gemma 3 | Google |
| `PaliGemma` | PaliGemma | Google |
| `FastVLM` | FastVLM | Apple |
| `SmolVLM` | SmolVLM / SmolVLM2 | HuggingFace |
| `Mistral3VLM` | Mistral Small 3.1 | Mistral |
| `PixtralVLM` | Pixtral | Mistral |
| `Idefics3` | Idefics3 | HuggingFace |
| `LFM2VL` | Liquid Foundation Model | Liquid AI |

## macdoc 的整合方式

macdoc 的 `ocr-swift` package 使用 MLXVLM 做 OCR：

```
ocr-swift (packages/ocr-swift)
├── OCRCore/Pipeline/OCRPipeline.swift   — 載入模型、跑 VLM generate
├── OCRCore/Models/ModelLoader.swift     — HuggingFace 快取查找
└── 依賴: MLXVLM + MLXLMCommon
```

CLI 入口：`macdoc ocr <file> [--model <repo>] [--pages N-M]`

預設模型：`EZCon/GLM-OCR-8bit-mlx`（GLM-OCR 的 MLX 8-bit 量化版）

## 記憶體需求參考

| 模型大小 | 量化 | 大約 RAM 用量 | 建議最低 RAM |
|---------|------|-------------|------------|
| 0.5B | bf16 | ~1 GB | 8 GB |
| 1.6B | 4-bit | ~1.5 GB | 8 GB |
| 2-3B | 4-bit | ~2-3 GB | 8 GB |
| 3B | 8-bit | ~4-5 GB | 16 GB |
| 4B | 4-bit | ~3-4 GB | 16 GB |
| 4B | 8-bit | ~6-7 GB | 16 GB |
| 12B | 4-bit | ~8-10 GB | 16 GB |
| 27B | 4-bit | ~16-18 GB | 32 GB |

同時跑兩個模型（如 ensemble OCR）需要加總。例如 GLM-OCR 8-bit (~5 GB) + Qwen2.5-VL 4-bit (~3 GB) ≈ 8 GB，16 GB RAM 的 Mac 可以處理。

## OCR 用途的模型選擇注意事項

**不是所有 VLM 都適合 OCR。** 通用 VLM（如 Gemma 4）傾向「理解→改寫」而非忠實轉錄，會出現幻覺、引用錯誤、內容丟失。OCR 用途必須選擇 OCR-specialized 模型。

| 模型 | OCR 忠實度 | 問題 |
|------|-----------|------|
| GLM-OCR | 極高 | 逐字轉錄，引用正確，Unicode 正確 |
| Gemma 4 (8B) | 低 | 改寫原文、捏造引用、重複輸出、丟失 27% 內容 |

選擇標準：模型是否為 OCR 任務專門訓練/微調，而非通用圖片理解。

## 相關資源

- [mlx-swift-lm GitHub](https://github.com/ml-explore/mlx-swift-lm) — 原始碼
- [mlx-swift GitHub](https://github.com/ml-explore/mlx-swift) — 底層 MLX tensor 運算
- [MLXVLM API 文件](https://swiftpackageindex.com/ml-explore/mlx-swift-lm/main/documentation/mlxvlm) — Swift Package Index
- [mlx-community](https://huggingface.co/mlx-community) — HuggingFace 上的 MLX 格式模型
- [Ensemble OCR 設計](ensemble-ocr-design.md) — macdoc 的 ensemble OCR pipeline 設計
