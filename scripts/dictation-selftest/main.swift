// Auto-test des garde-fous de la dictée (récitation du vocabulaire, ajouts du modèle).
// swiftc boringNotch/modules/Dictation/DictationGuards.swift scripts/dictation-selftest/main.swift -o "$TMPDIR/dictation-selftest" && "$TMPDIR/dictation-selftest"

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
check(G.dropRecitation(capture, vocabulary: []) == capture, "vocabulaire vide : rien ne change")
check(G.addsVocabulary(capture, to: said, vocabulary: vocab), "liste ajoutée par le modèle détectée")
check(!G.addsVocabulary("Paiement Qonto reçu.", to: "paiement qonto reçu", vocabulary: vocab), "terme dit puis capitalisé : pas un ajout")
check(!G.addsVocabulary(capture, to: said, vocabulary: []), "vocabulaire vide : aucun ajout détecté")
check(G.retained(said, of: capture) < 0.75, "mesure inverse : la sortie contient trop de mots nouveaux")
check(G.retained("Les enfants sont arrivés.", of: "les enfant sont arrivé") >= 0.75, "accords corrigés : pas des ajouts")
print("OK")
