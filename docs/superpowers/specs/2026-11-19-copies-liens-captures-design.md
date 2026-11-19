# Copies : liens nettoyés et captures d'écran en image

Date : 2026-11-19. Taille : petite modification.

## Pourquoi

Deux défauts de l'onglet Copies :
1. Les liens copiés gardent leurs paramètres de pistage (`utm_source`, `fbclid`, `si`…) : partagés tels quels, ils
   sont longs et pistent.
2. Une capture d'écran copiée s'affiche comme du texte au lieu de l'image. Cause probable : `ClipboardStore.read`
   (`ClipboardModule.swift`) teste le texte (`pb.string(forType: .string)`) **avant** l'image ; les outils de capture
   déposent aussi un texte (nom ou chemin du fichier) à côté de l'image.

But : liens propres partout, captures visibles en image. Non-buts : historique plus long, recherche, épingles
persistantes, collage en texte brut (non retenus). Anti-buts : modifier un texte qui n'est pas un lien seul ; afficher en
image un texte copié depuis une page web qui contient aussi des images.

## Approches

- Liens : **nettoyage automatique dans le presse-papiers macOS** (retenu, comme le mode automatique de Vorssaint) ;
  nettoyage seulement dans la carte, écarté (on recolle le lien sale depuis ⌘V).
- Captures : **l'image l'emporte quand le presse-papiers a une image et pas de texte mis en forme** (retenu) ;
  « toujours l'image d'abord », écarté (une copie depuis une page web avec image deviendrait une image).

## Conception

### Liens

- Ne s'applique que si le texte copié, sans espaces autour, est **un seul** lien `http`/`https` (pas de texte autour).
- Paramètres retirés (noms exacts, insensibles à la casse) : tout `utm_*`, `fbclid`, `gclid`, `dclid`, `gbraid`,
  `wbraid`, `msclkid`, `mc_cid`, `mc_eid`, `igshid`, `igsh`, `si` (seulement sur `youtube.com`, `youtu.be`,
  `open.spotify.com`), `ref_src`, `ref_url`, `_hsenc`, `_hsmi`, `mkt_tok`, `yclid`, `twclid`, `ttclid`, `li_fat_id`.
- Les autres paramètres et le fragment (`#…`) restent dans le même ordre ; plus de paramètre → plus de `?`.
- Si le lien a changé : on réécrit le presse-papiers macOS avec le lien propre (en mémorisant le `changeCount` produit
  pour ne pas le compter comme une nouvelle copie) et la carte montre le lien propre.
- Réglage « Nettoyer les liens copiés » (activé par défaut), à côté du raccourci « Ouvrir les copies » dans les réglages.
- Jamais sur un contenu marqué secret (règle actuelle des mots de passe inchangée).

### Captures

- Ordre de lecture : fichiers (inchangé) → **image si le presse-papiers contient `public.png` ou `public.tiff` et ni
  `public.rtf` ni `public.html`** → texte → image (inchangé).
- À vérifier en premier, sans écraser le presse-papiers de l'utilisateur : les types réellement déposés par ⌘⇧⌃4
  (capture macOS dans le presse-papiers) et, si installé, CleanShot / Shottr. Le résultat va dans le rapport et dans
  un commentaire du code.

## Laissé au constructeur

- L'emplacement exact du réglage, l'implémentation du parcours d'URL (`URLComponents`).
