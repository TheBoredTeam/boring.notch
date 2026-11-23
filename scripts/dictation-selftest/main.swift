// Auto-test de la logique pure de la dictée (garde-fous, dictionnaire et substitutions).
// swiftc boringNotch/modules/Dictation/DictationGuards.swift boringNotch/modules/Dictation/DictationWords.swift scripts/dictation-selftest/main.swift -o "$TMPDIR/dictation-selftest" && "$TMPDIR/dictation-selftest"

import Foundation

typealias G = DictationGuards
func check(_ cond: Bool, _ msg: String) { if !cond { print("FAIL: \(msg)"); exit(1) } }

let vocab = ["Nillor", "Qonto", "Edelweiss", "culottes courtes", "Hostinger", "Rotowash", "HELEBOR", "TAILSCALE", "YOTO"]
let said = "Je voudrais optimiser la prise de notes. Les rendus ne sont pas toujours réels."
let capture = said + "\n\nNillor, Qonto, Edelweiss, culottes courtes, Edelweiss, Hostinger, Rotowash, HELEBOR, Et culottes courtes, TAILSCALE, —-arr, YOTO.."

check(G.dropRecitation(capture, vocabulary: vocab).trimmingCharacters(in: .whitespacesAndNewlines) == said, "liste récitée retirée")
let real = "J'ai appelé Qonto puis Hostinger ce matin pour le contrat."
check(G.dropRecitation(real, vocabulary: vocab) == real, "vraie phrase avec deux clients gardée")
check(G.dropRecitation("Qonto", vocabulary: vocab) == "Qonto", "un seul terme : gardé")
check(G.dropRecitation("Qonto et Hostinger.", vocabulary: vocab) == "Qonto et Hostinger.", "segment court qui cite deux clients : gardé")
check(G.dropRecitation("Synolia, Qonto et Tailscale.", vocabulary: vocab + ["Synolia"]) == "Synolia, Qonto et Tailscale.", "phrase réelle avec trois termes : gardée")
check(!G.addsVocabulary("J'ai payé Qonto hier pour le devis.", to: "j'ai payé kanto hier pour le devis", vocabulary: vocab), "nom mal entendu corrigé par le modèle : accepté")
check(G.dropRecitation(capture, vocabulary: []) == capture, "vocabulaire vide : rien ne change")
check(G.addsVocabulary(capture, to: said, vocabulary: vocab), "liste ajoutée par le modèle détectée")
check(!G.addsVocabulary("Paiement Qonto reçu.", to: "paiement qonto reçu", vocabulary: vocab), "terme dit puis capitalisé : pas un ajout")
check(!G.addsVocabulary(capture, to: said, vocabulary: []), "vocabulaire vide : aucun ajout détecté")
check(G.retained(said, of: capture) < 0.75, "mesure inverse : la sortie contient trop de mots nouveaux")
check(G.retained("Les enfants sont arrivés.", of: "les enfant sont arrivé") >= 0.75, "accords corrigés : pas des ajouts")

// Dictionnaire et substitutions perso.
typealias W = DictationWords
let r = W.rules("Boring Notch => X\nnotch => N\nboring notch => Y\n=> z\nmal formé")
check(r.count == 2 && r[0].from == "Boring Notch" && r[0].to == "X" && r[1].from == "notch", "règles : doublon, vide et mal formé écartés, long avant court")
check(W.substitute("le boring notch et la notch", rules: r) == "le X et la N", "substitution : la règle longue passe avant la courte")
check(W.substitute("notchbar", rules: [("notch", "N")]) == "notchbar", "substitution : mot entier seulement")
check(W.substitute("a", rules: [("a", "$1\\")]) == "$1\\", "substitution : cible insérée littéralement")
check(W.words("Synolia\n\n  synolia \nTailscale\na => b") == ["Synolia", "Tailscale"], "mots : trim, doublons, lignes de règle ignorées")
check(W.fixCase("chez SYNOLIA et synolia, synoliaX", words: ["Synolia"]) == "chez Synolia et Synolia, synoliaX", "casse : graphie exacte, mot entier")
check(W.fixCase("boring notch notch", words: ["notch", "Boring Notch"]) == "Boring Notch notch", "casse : expression longue non défaite par le mot court")
check(W.vocabulary(words: ["Synolia"], rules: [("sinolia", "Synolia"), ("qonto", "Qonto")]) == ["Synolia", "Qonto"], "vocabulaire : mots puis cibles, dédoublonné")
check(W.vocabulary(words: (0..<150).map { "m\($0)" }, rules: []).count == 100, "vocabulaire : 100 premiers")
check(W.isCaseOnly("synolia", "Synolia"), "casse seule : vrai")
check(!W.isCaseOnly("sinolia", "Synolia"), "casse seule : lettres différentes")
check(!W.isCaseOnly("a", "a"), "casse seule : identiques")
check(W.isOnlyInitialCapital("maison", "Maison"), "majuscule initiale seule : vrai")
check(!W.isOnlyInitialCapital("synolia", "SYNOLIA"), "majuscule initiale seule : tout en capitales, faux")
check(!W.isOnlyInitialCapital("sYnolia", "Synolia"), "majuscule initiale seule : autre casse, faux")
check(W.words("Synolia\r\nQonto") == ["Synolia", "Qonto"], "mots : CRLF")
check(W.isCaseOnly(" synolia.", "Synolia"), "casse seule : ponctuation ignorée")
print("OK")
