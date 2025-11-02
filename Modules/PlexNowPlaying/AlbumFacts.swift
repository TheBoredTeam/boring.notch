import Foundation

/// Modelo unificado para los “facts” del álbum mostrados en la columna derecha.
public struct AlbumFacts: Sendable, Equatable {
    public var releaseDate: String?            // ej. "1990-03-19" o "1990"
    public var label: String?                  // ej. "Mute Records"
    public var producers: [String]             // acreditados
    public var personnel: [String]             // músicos / ingenieros

    // NUEVOS
    public var country: String?                // origen de la edición (ej. "MX", "US", "UK")
    public var genres: [String]?               // géneros/subgéneros (ej. ["Rock", "Alternative Rock"])
    public var notes: String?                  // notas editoriales (Discogs "notes")

    public var catalogNumber: String?          // número de catálogo
    public var chartPeaks: [[String: String]]? // opcional, por país
    public var sources: [String]               // links/refs
    public var summaryMD: String?              // markdown opcional

    public init(
        releaseDate: String? = nil,
        label: String? = nil,
        producers: [String] = [],
        personnel: [String] = [],
        country: String? = nil,
        genres: [String]? = nil,
        notes: String? = nil,
        catalogNumber: String? = nil,
        chartPeaks: [[String: String]]? = nil,
        sources: [String] = [],
        summaryMD: String? = nil
    ) {
        self.releaseDate = releaseDate
        self.label = label
        self.producers = producers
        self.personnel = personnel
        self.country = country
        self.genres = genres
        self.notes = notes
        self.catalogNumber = catalogNumber
        self.chartPeaks = chartPeaks
        self.sources = sources
        self.summaryMD = summaryMD
    }
}
