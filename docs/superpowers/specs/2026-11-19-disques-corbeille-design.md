# Réglages rapides : éjecter les disques et vider la corbeille

Date : 2026-11-19. Taille : petite modification.

## Pourquoi

Deux gestes fréquents sans ouvrir le Finder : éjecter les disques externes avant de débrancher, vider la corbeille.
Inspiration : les « Quick toggles » de Vorssaint. Seuls ces deux-là ont été retenus (« Rester éveillé » existe déjà).

But : un clic chacun depuis l'onglet Focus. Non-buts : mode sombre, masquer le bureau, verrouiller (non retenus).
Anti-buts : vider la corbeille sans confirmation ; éjecter le disque système ou un disque interne.

## Approches

- Corbeille : **demander au Finder par Apple Event** (retenue : l'app est sandboxée et ne peut pas toucher `~/.Trash`,
  et le Finder gère les fichiers verrouillés et volumes externes) ; supprimer les fichiers soi-même, écartée.
- Éjection : **`NSWorkspace.unmountAndEjectDevice(at:)`** sur les volumes éjectables (retenue) ; `diskutil` en
  processus, écartée (pas d'exécution de processus depuis la sandbox). **À vérifier en premier** : que l'appel marche
  depuis l'app sandboxée. Repli si refusé : Apple Event au Finder (`eject disk`), même autorisation que la corbeille.

## Conception

- Une colonne étroite (≈ 44 pt) à droite des trois tuiles de l'onglet Focus (`FocusView`), deux boutons icône empilés,
  même style que les tuiles (`FocusTile`) :
  - **Éjecter** (`eject`) : nombre de volumes éjectables en badge ; grisé s'il n'y en a aucun ; un clic éjecte tous les
    volumes éjectables non internes. Échec d'un volume (fichier ouvert) : le bouton passe en rouge 2 s et l'infobulle
    nomme le volume.
  - **Vider la corbeille** (`trash`) : premier clic → le bouton devient « Confirmer ? » (teinte rouge) pendant 3 s ;
    second clic dans ce délai → la corbeille est vidée ; sinon retour à l'état normal. Grisé si la corbeille est vide
    (si on peut le savoir sans accès à `~/.Trash`, sinon toujours actif).
- Volumes éjectables : `FileManager.mountedVolumeURLs(includingResourceValuesForKeys:options: [.skipHiddenVolumes])`
  avec `volumeIsEjectableKey == true` ou `volumeIsRemovableKey == true`, et `volumeIsInternalKey != true`. Rafraîchi à
  l'ouverture de l'onglet et sur `NSWorkspace.didMountNotification` / `didUnmountNotification`.
- Sandbox : ajouter `com.apple.finder` à `com.apple.security.temporary-exception.apple-events`. Au premier usage, macOS
  demande l'autorisation « Boring Notch veut contrôler Finder » ; si refusée, le bouton affiche l'échec (rouge 2 s,
  infobulle « Autorisation refusée : Réglages Système → Confidentialité → Automatisation »).

## Laissé au constructeur

- Icônes exactes, durée de l'état d'échec, la détection « corbeille vide ».
