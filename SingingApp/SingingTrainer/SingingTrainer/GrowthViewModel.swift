import Foundation

@MainActor
final class GrowthViewModel: ObservableObject {
    
    enum Range: CaseIterable, Hashable {
        case d7, d30, d90, all
        var label: String {
            switch self {
            case .d7: "7日"
            case .d30: "30日"
            case .d90: "90日"
            case .all: "全"
            }
        }
        var days: Int? {
            switch self {
            case .d7: 7
            case .d30: 30
            case .d90: 90
            case .all: nil
            }
        }
    }
    
    struct ScorePoint: Identifiable {
        let id = UUID()
        let t: Date      // ★回ごとなら日時 / 日別平均なら day start
        let score: Double
    }
    
    struct BestSummary {
        let sessionId: String?
        let score: Double
        let subtitle: String
    }
    
    // =========================================================
    // ★成長画面専用DTO（/api/historyのJSONと1:1）
    // =========================================================
    private struct GrowthHistoryItem: Identifiable, Decodable {
        let id: String
        let songId: String
        let userId: String
        let createdAt: String
        
        let score100: Double?
        let score100Strict: Double?
        let score100OctaveInvariant: Double?
        
        let meanAbsCents: Double?
        let percentWithinTol: Double?
        let tolCents: Double?
        let sampleCount: Int?
        
        let sessionId: String?
    }
    
    // Inputs
    let userId: String
    @Published var range: Range = .d30
    @Published var songFilter: String? = nil  // nil = 全曲
    
    // Outputs
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    
    @Published private(set) var availableSongs: [String] = []
    
    // ★グラフ用
    @Published private(set) var takeScorePoints: [ScorePoint] = []   // 回ごと
    @Published private(set) var dailyScorePoints: [ScorePoint] = []  // 1日平均
    
    @Published private(set) var bestItem: BestSummary?
    
    // KPI strings
    @Published private(set) var kpiAvgScore: String = "-"
    @Published private(set) var kpiAvgMeanAbsCents: String = "-"
    @Published private(set) var kpiAvgWithinTolPercent: String = "-"
    @Published private(set) var kpiCount: String = "-"
    
    init(userId: String) {
        self.userId = userId
    }
    
    func reload() {
        Task { await loadAndAggregate() }
    }
    
    private func loadAndAggregate() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let all = try await fetchAllHistory()
            
            // 曲一覧
            let songs = Set(all.map { $0.songId })
            availableSongs = Array(songs).sorted()
            
            // フィルタ
            let filtered = applyLocalFilter(items: all)
            
            // 集計
            aggregate(items: filtered)
            
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }
    
    // =========================================================
    // API（/api/history/<userId>）
    // =========================================================
    private func fetchAllHistory() async throws -> [GrowthHistoryItem] {
        // 実機の場合 127.0.0.1 は iPhone を指すので注意
        let url = AnalysisAPI.shared.baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("history")
            .appendingPathComponent(userId)
        let (data, resp) = try await URLSession.shared.data(from: url)
        
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw NSError(domain: "HistoryAPI", code: code, userInfo: [NSLocalizedDescriptionKey: raw])
        }
        
        struct Response: Decodable {
            let ok: Bool
            let userId: String
            let message: String?
            let items: [GrowthHistoryItem]
        }
        
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        
        do {
            let decoded = try dec.decode(Response.self, from: data)
            return decoded.items
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw NSError(domain: "HistoryDecode", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "\(error)\nRAW=\n\(raw)"])
        }
    }
    
    // =========================================================
    // フィルタ
    // =========================================================
    private func applyLocalFilter(items: [GrowthHistoryItem]) -> [GrowthHistoryItem] {
        var x = items
        
        // 曲
        if let songFilter {
            x = x.filter { $0.songId == songFilter }
        }
        
        // 期間
        if let days = range.days,
           let from = Calendar.current.date(byAdding: .day, value: -days, to: Date()) {
            x = x.filter { item in
                guard let d = parseISO8601(item.createdAt) else { return false }
                return d >= from
            }
        }
        
        return x
    }
    
    // =========================================================
    // 集計
    // =========================================================
    private func aggregate(items: [GrowthHistoryItem]) {
        
        kpiCount = "\(items.count)回"
        
        let scores: [Double] = items.map { item in
            item.score100OctaveInvariant ?? item.score100 ?? item.score100Strict ?? 0
        }
        kpiAvgScore = formatAvg(scores, suffix: "")
        
        let meanAbs: [Double] = items.compactMap { $0.meanAbsCents }
        kpiAvgMeanAbsCents = formatAvg(meanAbs, suffix: "")
        
        let within: [Double] = items.compactMap { $0.percentWithinTol }.map { $0 * 100.0 }
        kpiAvgWithinTolPercent = formatAvg(within, suffix: "%")
        
        // ★回ごと points（ここが今回の本命）
        takeScorePoints = items
            .compactMap { it -> ScorePoint? in
                guard let d = parseISO8601(it.createdAt) else { return nil }
                let s = it.score100OctaveInvariant ?? it.score100 ?? it.score100Strict ?? 0
                return ScorePoint(t: d, score: s)
            }
            .sorted { $0.t < $1.t }
        
        // ★1日平均 points
        let cal = Calendar.current
        var byDay: [Date: [Double]] = [:]
        for it in items {
            guard let d = parseISO8601(it.createdAt) else { continue }
            let day = cal.startOfDay(for: d)
            let s = it.score100OctaveInvariant ?? it.score100 ?? it.score100Strict ?? 0
            byDay[day, default: []].append(s)
        }
        
        dailyScorePoints = byDay
            .map { (day, arr) in
                ScorePoint(t: day, score: arr.reduce(0, +) / Double(arr.count))
            }
            .sorted { $0.t < $1.t }
        
        // ベスト
        var best: GrowthHistoryItem?
        var bestScore: Double = -Double.infinity
        for it in items {
            let s = it.score100OctaveInvariant ?? it.score100 ?? it.score100Strict ?? 0
            if s > bestScore {
                bestScore = s
                best = it
            }
        }
        
        if let best {
            let dateText = parseISO8601(best.createdAt).map { dateShort($0) } ?? "-"
            bestItem = BestSummary(
                sessionId: best.sessionId,
                score: bestScore,
                subtitle: "\(dateText) / \(best.songId)"
            )
        } else {
            bestItem = nil
        }
    }
    
    // =========================================================
    // Utils
    // =========================================================
    private func formatAvg(_ xs: [Double], suffix: String) -> String {
        guard !xs.isEmpty else { return "-" }
        let v = xs.reduce(0, +) / Double(xs.count)
        return String(format: "%.1f%@", v, suffix)
    }
    
    private func parseISO8601(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
    
    private func dateShort(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f.string(from: d)
    }
}
