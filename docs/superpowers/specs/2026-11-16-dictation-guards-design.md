# Dictée : garde-fous contre le texte inventé

Date : 2026-11-16. Taille : petite modification.

## Pourquoi

Une dictée s'est terminée par la liste du vocabulaire perso (« Nillor, Qonto, Edelweiss, … ») alors qu'elle n'avait
pas été prononcée. Cause probable : le vocabulaire est donné au modèle de correction sous forme de liste
(« Orthographe à respecter : a, b, c ») et le modèle la recopie ; `plausible()` ne vérifie que les mots perdus, pas les
mots ajoutés, donc l'ajout passe sur un segment long. Hex (anomalyco/hex) a eu le même défaut avec Whisper et jette
toute sortie qui ne fait que réciter le vocabulaire, plus les prises quasi muettes.

But : ce qui est collé = ce qui a été dit. Non-but : améliorer la reconnaissance elle-même (moteur, Parakeet : plus tard,
séparément). Anti-but : jeter une vraie dictée (voix faible, phrase qui cite vraiment deux clients).

## Approches

1. **Garde-fous après coup** (retenue) : filtres déterministes sur le texte et le niveau audio, aucune dépendance.
2. Retirer le vocabulaire du modèle de correction : supprime la cause, mais perd l'orthographe des noms dans les phrases.
3. Changer de moteur (Parakeet) : ne règle pas les noms seul (pas de vocabulaire natif), 640 Mo, chantier séparé.

## Conception

1. **Anti-récitation** : un segment brut (avant correction) où au moins 3 occurrences de termes du vocabulaire couvrent au moins la
   moitié des mots est vidé. Rattrape la reconnaissance qui invente sur un blanc.
2. **Refus des ajouts du modèle** : la correction est rejetée (on garde le segment d'origine) si
   - au moins 2 occurrences de termes du vocabulaire apparaissent dans la sortie sans être dans l'entrée (un seul nom corrigé est accepté), ou
   - moins de 75 % des mots de la sortie existaient dans l'entrée (même mesure que `retained`, dans l'autre sens).
   Pas appliqué aux commandes sur la sélection (une traduction change tous les mots).
3. **Consigne reformulée** : « Si l'un de ces mots apparaît mal écrit, écris-le ainsi : … N'ajoute jamais ces mots
   s'ils ne sont pas dans le texte. »
4. **Filtre de silence** : on retient le niveau RMS maximal de la prise ; s'il reste sous −50 dBFS (comme Hex), rien
   n'est collé ni mis dans l'historique. Seuil en dur, marqué `ponytail:` (bouton de réglage si un micro faible est jeté).

Les fonctions pures (récitation, ajouts) vont dans un petit fichier Foundation seul, vérifié par
`scripts/dictation-selftest/main.swift` (même modèle que les autres selftests), avec le cas de la capture.

Laissé au constructeur : nom exact des fonctions, emplacement des appels dans `cleanChunk` / `llm` / `stop`.
Hors code : la liste de substitutions contient des doublons et une entrée abîmée (« —-arr ») à relire dans
Réglages > Dictée.
