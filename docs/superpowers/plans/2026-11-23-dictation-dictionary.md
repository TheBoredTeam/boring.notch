# Dictée : dictionnaire de mots et remplacements plus fiables

**Spec :** aucune spec séparée ; la proposition validée par l'utilisateur fait foi (dictionnaire simple « un mot par ligne »,
remplacements plus solides, reconnaissance réellement guidée derrière un réglage pour comparer).

**Contexte :** pipeline actuel dans `boringNotch/modules/Dictation/` : micro → `SpeechTranscriber` (SpeechAnalyzer) →
`TextCleanup.cleanChunk` (règles + modèle Apple on-device) → `TextCleanup.finish` (substitutions `avant => après`, Defaults
`.dictationSubstitutions`). `TextCleanup.vocabulary()` (cibles des substitutions) est passé à la reconnaissance via
`AnalysisContext.contextualStrings` (Dictation.swift ~l.222) et au modèle. **Apple confirme que `SpeechTranscriber` ignore
`contextualStrings` ; seul `DictationTranscriber` les utilise.**

## Global Constraints

- Français partout (UI, commentaires). Commentaires courts, style du fichier ; `// ponytail:` pour les simplifications assumées.
- Logique pure dans un fichier **Foundation seul** (`DictationWords.swift`), testée par `scripts/dictation-selftest/main.swift`
  (pas de XCTest dans ce projet). Commande de test :
  `swiftc boringNotch/modules/Dictation/DictationGuards.swift boringNotch/modules/Dictation/DictationWords.swift scripts/dictation-selftest/main.swift -o "$TMPDIR/dictation-selftest" && "$TMPDIR/dictation-selftest"` → doit afficher `OK`.
  Mettre à jour la ligne de commande en tête de `main.swift` en conséquence.
- Build : `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -derivedDataPath build/dd build 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'` → `BUILD SUCCEEDED`.
  Le dossier `boringNotch/modules` est un groupe synchronisé : un nouveau fichier y est compilé sans toucher au `.pbxproj`.
- Correspondance : mot entier (`(?<![\p{L}\p{N}])…(?![\p{L}\p{N}])`), insensible à la casse, comme `substitute` actuel.
- Aucune approximation floue/phonétique sur le texte final (risque de faux remplacements).
- Pas de nouvelle dépendance. Commits en français, un par tâche minimum.

## Task 1 : logique pure `DictationWords`

Créer `boringNotch/modules/Dictation/DictationWords.swift` (`import Foundation` seulement), `enum DictationWords` :

- `static func rules(_ raw: String) -> [(from: String, to: String)]` : une règle par ligne `avant => après` (exactement un
  `=>`), `from`/`to` trimés, `from` non vide. Doublons de `from` (insensible à la casse) : **la première l'emporte**.
  Résultat trié par longueur de `from` **décroissante** (tri stable), pour que « boring notch » passe avant « notch ».
- `static func substitute(_ text: String, rules: [(from: String, to: String)]) -> String` : applique les règles dans l'ordre
  reçu, mot entier, insensible à la casse, `to` inséré littéralement (`escapedTemplate`).
- `static func words(_ raw: String) -> [String]` : dictionnaire, un mot ou une expression par ligne, trimé, lignes vides et
  lignes contenant `=>` ignorées, doublons insensibles à la casse retirés (premier gardé), ordre conservé.
- `static func fixCase(_ text: String, words: [String]) -> String` : chaque occurrence (mot entier, insensible à la casse)
  d'un mot du dictionnaire prend sa graphie exacte ; mots les plus longs d'abord.
- `static func vocabulary(words: [String], rules: [(from: String, to: String)]) -> [String]` : dictionnaire puis cibles
  `to` non vides, dédoublonné insensible à la casse, 100 premiers.
- `static func isCaseOnly(_ a: String, _ b: String) -> Bool` : vrai si `a != b` et `a.lowercased() == b.lowercased()`
  (après trim espaces/ponctuation).

Étendre `scripts/dictation-selftest/main.swift` (garder les assertions existantes) avec au moins :
- `rules("Boring Notch => X\nnotch => N\nboring notch => Y\n=> z\nmal formé")` → 2 règles, première `from == "Boring Notch"`
  `to == "X"`, ordre long → court.
- `substitute("le boring notch et la notch", rules: …)` → `"le X et la N"`.
- `substitute("notchbar", rules: [("notch","N")])` inchangé (mot entier).
- `words("Synolia\n\n  synolia \nTailscale\na => b")` → `["Synolia", "Tailscale"]`.
- `fixCase("chez SYNOLIA et synolia, synoliaX", words: ["Synolia"])` → `"chez Synolia et Synolia, synoliaX"`.
- `vocabulary(words: ["Synolia"], rules: [("sinolia","Synolia"),("qonto","Qonto")])` → `["Synolia", "Qonto"]`.
- `isCaseOnly("synolia", "Synolia")` vrai ; `isCaseOnly("sinolia", "Synolia")` faux ; `isCaseOnly("a", "a")` faux.

Ne pas encore brancher ces fonctions dans `TextCleanup` (Task 2).

## Task 2 : dictionnaire branché et réglages

- `boringNotch/models/Constants.swift` : à côté de `dictationSubstitutions`, ajouter
  `static let dictationDictionary = Key<String>("dictationDictionary", default: "")` (un mot par ligne).
- `TextCleanup.swift` :
  - `substitute(_:)` délègue à `DictationWords.substitute(text, rules: DictationWords.rules(Defaults[.dictationSubstitutions]))`.
  - `finish(_:)` : après les substitutions, appliquer `DictationWords.fixCase(_, words: DictationWords.words(Defaults[.dictationDictionary]))`.
  - `vocabulary()` renvoie `DictationWords.vocabulary(words:rules:)` (dictionnaire + cibles) ; mettre à jour son commentaire.
  - `learn(from:to:)` : mêmes garde-fous qu'aujourd'hui ; si `DictationWords.isCaseOnly(a, b)` et `b` est un seul mot,
    la suggestion est **le mot seul** `b` (entrée de dictionnaire) au lieu de `a => b`. Les « connus » incluent aussi les mots
    du dictionnaire (insensible à la casse) et les suggestions sans `=>`.
  - `accept(_:)` : suggestion contenant `=>` → ajoutée aux substitutions (comme aujourd'hui) ; sinon → ajoutée au dictionnaire.
- `DictationSettings.swift` :
  - Nouvelle section **« Dictionnaire »** placée **avant** « Substitutions » : `TextEditor` monospacé lié à
    `.dictationDictionary`, `minHeight: 110`. Footer : « Un mot ou un nom par ligne (ex. : Synolia). La dictée les écrit
    toujours avec cette orthographe et ces majuscules ; ils guident aussi le modèle de correction. Pour un mot que la
    reconnaissance entend de travers, ajoute plutôt une substitution. »
  - Footer « Substitutions » : ajouter « Les règles les plus longues passent en premier. ».
  - Bouton « Accepter » des suggestions : appeler `TextCleanup.accept(rule)` (la vue est déjà en macOS 26) au lieu de
    dupliquer la logique. Footer des suggestions : mentionner qu'une correction de majuscules seule devient un mot du dictionnaire.
- Build doit passer ; selftest toujours `OK`.

## Task 3 : reconnaissance guidée (expérimental, réglage)

- `Constants.swift` : `static let dictationGuidedRecognition = Key<Bool>("dictationGuidedRecognition", default: false)`.
- `Dictation.swift` (préparation ~l.211-236) : si le réglage est actif, utiliser
  `DictationTranscriber(locale:contentHints: [], transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])`
  (locale via `DictationTranscriber.supportedLocale(equivalentTo:)`) à la place de `SpeechTranscriber` ; même téléchargement
  d'assets, même `SpeechAnalyzer`, même `setContext` avec `contextualStrings[.general] = vocab`, même boucle de résultats
  (`isFinal`, `text`) — factoriser juste ce qu'il faut pour ne pas dupliquer la boucle. Sinon, comportement actuel inchangé.
  Log `info` indiquant quel module est utilisé.
- Corriger le commentaire actuel qui laisse croire que `SpeechTranscriber` tient compte du vocabulaire.
- `DictationSettings.swift`, section « Nettoyage » ou « Dictionnaire » : `Defaults.Toggle("Reconnaissance guidée par le
  dictionnaire (expérimental)", key: .dictationGuidedRecognition)` avec footer : « Utilise le modèle de dictée d'Apple, qui
  tient compte du dictionnaire et des substitutions pendant l'écoute. Peut être moins précis sur les longues dictées : compare. »
- Build doit passer ; selftest toujours `OK`.
