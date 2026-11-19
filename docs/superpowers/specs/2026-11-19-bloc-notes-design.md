# Bloc-notes dans l'encoche

Date : 2026-11-19. Taille : projet.

## Pourquoi

Noter une idée, un numéro, une commande sans changer d'application ni ouvrir une fenêtre. Inspiration : le
« Scratchpad » de Vorssaint (notes en onglets dans le Dynamic Island). Choix de l'utilisateur : écrire **dans
l'encoche**.

But : ouvrir l'encoche, cliquer, taper, partir — la note est sauvegardée. Non-buts : aperçu Markdown, export,
synchronisation, recherche (plus tard). Anti-buts : l'encoche qui vole le clavier sans clic explicite ; perdre du texte
(fermeture, redémarrage, plantage) ; l'encoche qui se ferme pendant la frappe.

## Contrainte principale

La fenêtre de l'encoche (`BoringNotchSkyLightWindow`, créée par `createBoringNotchWindow` dans `boringNotchApp.swift`,
style `[.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]`) renvoie `canBecomeKey = false` : elle ne reçoit
jamais le clavier. Un `nonactivatingPanel` peut devenir fenêtre clé **sans activer l'app** : l'app au premier plan le
reste, seule la frappe va au panneau. C'est ce qu'il faut, à vérifier en premier.

## Approches

1. **Clavier prêté à l'encoche le temps de la frappe** (retenue, choix de l'utilisateur) : `canBecomeKey` vrai
   seulement pendant l'édition.
2. Petite fenêtre flottante pour écrire : sans risque, mais une fenêtre de plus. **Repli** si l'approche 1 est
   impossible (vérifié en tâche 1), sans redemander.
3. Les deux : écarté pour l'instant.

## Conception

- **Onglet « Notes »** (module `NotesModule`, icône `note.text`), ajouté à `NotchModules.all` ; activable / réordonnable
  comme les autres (Réglages → Apparence).
- **Mise en page** (640 × 190 pt, barre d'onglets comprise) : une rangée de pastilles en haut, une par note (titre =
  première ligne non vide, tronquée, « Nouvelle note » si vide) + bouton « + » ; dessous, la zone de texte de la note
  choisie, défilante. Jusqu'à **5 notes** ; « + » grisé à 5. Supprimer : clic droit sur une pastille → « Supprimer »
  (confirmation si la note n'est pas vide).
- **Clavier** :
  - Un clic dans la zone de texte autorise la fenêtre à devenir clé et lui donne le focus. Rien d'autre ne prend le
    clavier (ni l'ouverture de l'encoche au survol, ni l'arrivée sur l'onglet).
  - Pendant l'édition : l'encoche ne se ferme pas au départ de la souris (`SharingStateManager.beginInteraction()`).
  - Fin d'édition : Échap, clic hors de l'encoche, changement d'onglet ou fermeture de l'encoche → la fenêtre rend le
    clavier (`resignKey`, `canBecomeKey` repasse à faux), `endInteraction()`. L'app qui était devant reçoit de nouveau
    la frappe sans clic.
  - ⌘A, ⌘C, ⌘V, ⌘X, ⌘Z fonctionnent dans la zone de texte.
- **Sauvegarde** : à chaque modification, écriture différée d'1 s dans `Application Support/notes.json` (conteneur de
  l'app), et immédiate à la fin d'édition et à la fermeture de l'app. Lecture au lancement. Fichier illisible : on le
  renomme `notes.json.bak` et on repart vide (jamais d'écrasement silencieux).
- **Texte simple** (pas de mise en forme). Taille 12 pt, police système.

## Laissé au constructeur

- Le mécanisme exact pour rendre la fenêtre clé (propriété dynamique sur la fenêtre, `makeKey`, `NSTextView` enveloppé
  ou `TextEditor` SwiftUI), le style des pastilles, la confirmation de suppression.
