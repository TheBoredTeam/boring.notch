# Téléchargements : taille et débit quand le pourcentage est inconnu

Date : 2026-11-19. Taille : petite modification.

## Pourquoi

Le navigateur principal est Firefox. `DownloadMonitor` détecte bien ses fichiers `.part`, mais n'affiche qu'un anneau
qui tourne : on ne sait ni si ça avance ni à quelle vitesse. Firefox (comme Chrome/Arc avec `.crdownload`) n'expose la
taille totale nulle part sans extension : un pourcentage est impossible.

But : voir qu'un téléchargement avance et à quel rythme. Non-but : un pourcentage pour Firefox/Chrome. Anti-but : un
pourcentage ou une durée restante inventés.

## Approches

1. **Taille téléchargée + débit** (retenue) : la taille du fichier temporaire, relue à chaque passage (1 s), donne les
   octets reçus et le débit.
2. Extension Firefox qui envoie la progression : chantier séparé, installation, écartée.
3. Lire la base de Firefox (`places.sqlite`) : verrouillée pendant l'usage, pas de taille totale fiable, écartée.

## Conception

- Pour chaque entrée temporaire sans fraction connue (`.part`, `.crdownload`), mémoriser la taille et l'heure du dernier
  passage ; débit = différence de taille / différence de temps, lissé (moyenne des 3 dernières mesures).
- Pastille : anneau indéterminé (actuel) + `12 Mo · 3,4 Mo/s`. Plusieurs téléchargements : nombre + débit total.
  Safari garde son pourcentage.
- Débit nul pendant plus de 10 s : « en pause » à la place du débit.
- Format des tailles : `ByteCountFormatter` (style fichier), débit avec « /s ».
- L'infobulle (help) liste les noms comme aujourd'hui.

## Laissé au constructeur

- Le nombre exact de mesures pour le lissage, la largeur max du texte de la pastille.
