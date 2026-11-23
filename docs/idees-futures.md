# Idées pour plus tard

Repérées en analysant Oriel 3.0.3 (app fermée, sans licence : on reprend des idées, jamais du code ni des assets). Mises de côté le 2026-11-04.

## Widgets déclaratifs (JSON)
Un widget = un fichier JSON : une source `{url, every}` (HTTPS public uniquement, jamais `localhost` ni le réseau local), une liste d'éléments `title | value | caption | text | symbol | gauge | ring | list | spacer`, des gabarits `{{chemin.vers.valeur}}` remplis à partir de la réponse JSON. Chez Oriel : générateur web, galerie validée, installation par `oriel://widget?url=…`.
Version minimale chez nous : un dossier local de JSON + un moteur de rendu SwiftUI, sans galerie ni schéma d'URL.

## Textos et e-mails dans le notch
Lecture de `~/Library/Messages/chat.db` (Full Disk Access), photos jointes, réponse via AppleScript Messages, effacement quand c'est lu sur l'iPhone. Fragile et sensible côté vie privée.

## Appels (Répondre / Refuser)
Probablement via la bannière FaceTime/Continuité et l'Accessibility. À confirmer en désassemblant Oriel avant de se lancer.

## Musique sur l'écran verrouillé
Fenêtre posée dans l'espace du lock screen (SkyLight, API privée). Vérifier d'abord si boring.notch en amont propose déjà cette brique.

## Autres
- Shazam dans l'île (`ShazamKit` `SHManagedSession`).
- Ajout d'événement en langage naturel (FoundationModels, déjà utilisé par la dictée).
- Spotify : playlists qui contiennent le titre + ajout à une playlist.
- Réunions Zoom / Teams / Meet : muet et quitter depuis le notch (Accessibility).
- Limites d'usage Cursor, Gemini, Copilot à côté de Claude et Codex.
- Pochettes animées Apple Music, fond « verre teinté par la pochette », swipe pour changer de titre, respect de Reduce Transparency.
