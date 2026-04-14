//
//  CurrencyConverterView.swift
//  boringNotch
//
//  Created for boringNotch
//

import SwiftUI
import Combine
import Defaults

// MARK: - Response Model

private struct ExchangeRateResponse: Codable {
    let rates: [String: Double]
}

// MARK: - Expression Evaluator
//
// Recursive-descent parser with correct operator precedence (* / before + -).
// Returns nil for malformed / incomplete expressions (e.g. "100+", "100/0").

private func evaluateExpression(_ raw: String) -> Double? {
    let expr = raw
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: ",", with: "")
        .replacingOccurrences(of: "×", with: "*")
        .replacingOccurrences(of: "÷", with: "/")

    guard !expr.isEmpty else { return nil }

    var pos = expr.startIndex

    func peek() -> Character? { pos < expr.endIndex ? expr[pos] : nil }
    func consume() { if pos < expr.endIndex { pos = expr.index(after: pos) } }

    func parseAtom() -> Double? {
        var s = ""
        if let c = peek(), c == "-" || c == "+" { s.append(c); consume() }
        guard let first = peek(), first.isNumber || first == "." else { return nil }
        while let c = peek(), c.isNumber || c == "." { s.append(c); consume() }
        return Double(s)
    }

    func parseTerm() -> Double? {
        guard var left = parseAtom() else { return nil }
        while let op = peek(), op == "*" || op == "/" {
            consume()
            guard let right = parseAtom() else { return nil }
            if op == "*" { left *= right }
            else { guard right != 0 else { return nil }; left /= right }
        }
        return left
    }

    func parseExpr() -> Double? {
        guard var left = parseTerm() else { return nil }
        while let op = peek(), op == "+" || op == "-" {
            consume()
            guard let right = parseTerm() else { return nil }
            left = op == "+" ? left + right : left - right
        }
        return left
    }

    let result = parseExpr()
    return pos == expr.endIndex ? result : nil
}

// MARK: - All Available Currencies
// Used by both the converter (fallback rates) and the Settings toggle list.

let allAvailableCurrencies: [String] = [
    "USD", "EUR", "GBP", "JPY", "CAD",
    "AUD", "CHF", "CNY", "INR", "MXN",
    "BRL", "KRW", "SGD", "HKD", "NOK",
    "SEK", "DKK", "NZD", "ZAR", "TRY"
]

// MARK: - ViewModel

class CurrencyConverterViewModel: ObservableObject {
    @Published var amountText: String = "1"
    @Published var evaluatedAmount: Double = 1.0
    @Published var fromCurrency: String = "AUD"
    @Published var toCurrency: String = "USD"
    @Published var rates: [String: Double] = [:]
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var lastUpdated: String? = nil

    var hasUnevaluatedExpression: Bool {
        let t = amountText.trimmingCharacters(in: .whitespaces)
        return !t.isEmpty && Double(t) == nil
    }

    private var cancellables = Set<AnyCancellable>()

    var resultText: String {
        guard let fromRate = rates[fromCurrency],
              let toRate = rates[toCurrency],
              fromRate > 0 else { return "—" }
        let result = (evaluatedAmount / fromRate) * toRate
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.maximumFractionDigits = 4
        fmt.minimumFractionDigits = 2
        fmt.groupingSeparator = ","
        fmt.usesGroupingSeparator = true
        return fmt.string(from: NSNumber(value: result)) ?? "—"
    }

    init() {
        fromCurrency = Defaults[.defaultFromCurrency]
        toCurrency   = Defaults[.defaultToCurrency]

        $amountText
            .map { Double($0.trimmingCharacters(in: .whitespaces)) }
            .compactMap { $0 }
            .assign(to: &$evaluatedAmount)

        fetchRates()
    }

    func commitExpression() {
        let trimmed = amountText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let plain = Double(trimmed) { evaluatedAmount = plain; return }
        guard let value = evaluateExpression(trimmed) else { return }
        evaluatedAmount = value
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.maximumFractionDigits = 10
        fmt.minimumFractionDigits = 0
        fmt.usesGroupingSeparator = false
        amountText = fmt.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    func swapCurrencies() {
        let temp = fromCurrency
        fromCurrency = toCurrency
        toCurrency = temp
    }

    func fetchRates() {
        isLoading = true
        errorMessage = nil
        guard let url = URL(string: "https://open.er-api.com/v6/latest/USD") else {
            loadFallbackRates(); return
        }
        URLSession.shared.dataTaskPublisher(for: url)
            .map(\.data)
            .decode(type: ExchangeRateResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                if case .failure = completion { self?.loadFallbackRates() }
            } receiveValue: { [weak self] response in
                self?.rates = response.rates
                let fmt = DateFormatter()
                fmt.timeStyle = .short
                self?.lastUpdated = fmt.string(from: Date())
            }
            .store(in: &cancellables)
    }

    private func loadFallbackRates() {
        rates = [
            "USD": 1.0,    "EUR": 0.92,   "GBP": 0.79,  "JPY": 149.5,
            "CAD": 1.36,   "AUD": 1.53,   "CHF": 0.89,  "CNY": 7.24,
            "INR": 83.1,   "MXN": 17.2,   "BRL": 4.97,  "KRW": 1325.0,
            "SGD": 1.34,   "HKD": 7.82,   "NOK": 10.6,  "SEK": 10.4,
            "DKK": 6.88,   "NZD": 1.63,   "ZAR": 18.6,  "TRY": 30.5
        ]
        errorMessage = "Offline"
        isLoading = false
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        lastUpdated = fmt.string(from: Date())
    }
}

// MARK: - View

/// Which currency pill is being edited
private enum CurrencySlot { case from, to }

struct CurrencyConverterView: View {
    @StateObject private var vm = CurrencyConverterViewModel()
    @State private var pickingSlot: CurrencySlot? = nil
    @Default(.enabledCurrencies) private var enabledCurrencies

    var body: some View {
        // converterContent always owns the layout height.
        // The grid is an overlay — it paints over the converter without
        // participating in layout, so the window size never changes.
        converterContent
            .overlay(alignment: .topLeading) {
                if let slot = pickingSlot {
                    currencyGrid(slot: slot)
                        // Fill the exact same bounds as converterContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(Color.black)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .topTrailing)),
                                removal:   .opacity.combined(with: .scale(scale: 0.97, anchor: .topTrailing))
                            )
                        )
                }
            }
            .animation(.smooth(duration: 0.18), value: pickingSlot == nil)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .onDisappear { NSApp.keyWindow?.resignKey() }
    }

    // MARK: Converter content

    @ViewBuilder
    private var converterContent: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Input row
            HStack(spacing: 8) {
                TextField("Amount", text: $vm.amountText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(vm.hasUnevaluatedExpression ? Color.yellow : Color.white)
                    .animation(.smooth(duration: 0.15), value: vm.hasUnevaluatedExpression)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .onSubmit { vm.commitExpression() }
                    .onKeyPress(.tab) { vm.commitExpression(); return .handled }

                currencyPill(label: vm.fromCurrency, slot: .from)
            }

            // Divider + swap
            HStack(spacing: 6) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)

                Button {
                    withAnimation(.spring(duration: 0.3)) { vm.swapCurrencies() }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color(nsColor: .secondarySystemFill)))
                }
                .buttonStyle(.plain)

                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            }

            // Result row
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Text(vm.resultText)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(vm.hasUnevaluatedExpression ? .white.opacity(0.25) : .white.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)

                    if vm.hasUnevaluatedExpression {
                        Text("↩")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.yellow.opacity(0.55))
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                .animation(.smooth(duration: 0.2), value: vm.hasUnevaluatedExpression)

                currencyPill(label: vm.toCurrency, slot: .to)
            }

            // Footer
            HStack(spacing: 4) {
                if vm.isLoading {
                    ProgressView().scaleEffect(0.45).frame(width: 10, height: 10)
                    Text("Fetching rates…")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                } else if let err = vm.errorMessage {
                    Image(systemName: "wifi.slash").font(.system(size: 9)).foregroundStyle(.orange.opacity(0.7))
                    Text(err).font(.system(size: 9, weight: .medium)).foregroundStyle(.orange.opacity(0.7))
                } else if let updated = vm.lastUpdated {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 9)).foregroundStyle(.green.opacity(0.6))
                    Text("Live · \(updated)").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.3))
                }
                Spacer()
                Button { vm.fetchRates() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
                .disabled(vm.isLoading)
            }
        }
    }

    // MARK: Currency pill button

    @ViewBuilder
    private func currencyPill(label: String, slot: CurrencySlot) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.18)) {
                pickingSlot = slot
            }
        } label: {
            HStack(spacing: 3) {
                Text(label)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color(nsColor: .secondarySystemFill)))
        }
        .buttonStyle(.plain)
    }

    // MARK: Inline currency grid

    @ViewBuilder
    private func currencyGrid(slot: CurrencySlot) -> some View {
        VStack(spacing: 8) {

            // Header
            HStack {
                Text(slot == .from ? "From currency" : "To currency")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
                Spacer()
                Button {
                    withAnimation(.smooth(duration: 0.18)) { pickingSlot = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.25))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // 5-column grid — enabled currencies, max 4 rows for the default 10
            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(enabledCurrencies, id: \.self) { currency in
                    let current = slot == .from ? vm.fromCurrency : vm.toCurrency
                    let isSelected = currency == current

                    Button {
                        withAnimation(.smooth(duration: 0.15)) {
                            if slot == .from { vm.fromCurrency = currency }
                            else             { vm.toCurrency  = currency }
                            pickingSlot = nil
                        }
                    } label: {
                        Text(currency)
                            .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                            .foregroundStyle(isSelected ? .black : .white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(isSelected ? Color.white : Color(nsColor: .secondarySystemFill))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
