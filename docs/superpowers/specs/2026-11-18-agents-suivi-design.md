# Agents : s'y retrouver entre plusieurs sessions, voir où elles en sont, statistiques

Date : 2026-11-18. Taille : projet (quatre volets dans l'onglet Agents existant).

## Pourquoi

Plusieurs sessions Claude tournent souvent en même temps, parfois sur le même projet pour des sujets différents. Dans le
notch, on s'y perd et on se trompe : on ne sait plus quelle session est laquelle, on valide la mauvaise, et on ne voit pas
où en est une session sans ouvrir l'outil complet. Inspiration : Vorssaint (suivi des agents dans son Dynamic Island,
dépense du jour, modèles et projets les plus utilisés, activité en grille).

Les sessions viennent surtout de **T3 Code et Delta**, de moins en moins du terminal.

## Constat dans le code (main, dfe09d1)

- `AgentsView.agentHeaderContent` affiche `title ?? project` : le projet disparaît dès qu'il y a un titre. La
  `PermissionCard` affiche le projet sans le sujet. Le sélecteur seul montre les deux (`project — title`).
- `title` = première ligne du premier prompt (`AgentStore`, `UserPromptSubmit`), souvent peu parlante.
- `prompting` = première session de `store.sessions` en attente. `upsert` remet la session en tête à **chaque**
  événement, status line comprise (envoyée en continu). Avec deux validations en attente, la carte peut donc basculer
  d'une session à l'autre sous le curseur : on croit autoriser A, on autorise B. Aucun indicateur d'autres attentes.
- Progression actuelle : état, 3 dernières étapes, `ActivityCard` (fichier courant, diff +/−). Ça dit ce qu'il fait, pas
  où il en est.
- Listes de tâches : sur 118 sessions de 10+ actions, ~13 en ont une (4 `TaskCreate`/`TaskUpdate`, 9
  `mcp__ccd_turn__update_plan`, app de bureau). **T3 Code : 0 sur 31**, Delta : l'outil n'existe pas. Une consigne
  CLAUDE.md « crée une liste de tâches » n'aurait donc presque aucun effet : écartée.

- L'app est **sandboxée** (`boringNotch.entitlements`) : elle ne lit pas `~/.claude/` et ne peut pas exécuter `delta`.
  Les scripts de hook (`scripts/agent-*.sh`) tournent eux hors sandbox.
- `AgentStore` garde **un** répondeur par `session_id` et considère tout autre événement de la session comme « traité
  ailleurs » (lignes 131-134). Un sous-agent parallèle de la même session efface donc la carte affichée.

## Buts, non-buts, anti-buts

- But : savoir en un coup d'œil quelle session est laquelle, laquelle attend quoi, où elle en est, et ne jamais valider la
  mauvaise. Une page de statistiques en complément.
- Non-buts : Codex dans les statistiques (plus tard) ; la commande en cours en détail (c'est le rôle de l'outil complet) ;
  une facture réelle (forfait).
- Anti-buts : une barre ou une durée restante inventée ; une carte qui change pendant qu'on clique ; un notch qui déborde
  (hauteur ouverte fixe, 190 pt) ; ralentir l'app en relisant des centaines de Mo de journaux.

## Approches

- Progression : **A. chrono + bande d'activité** (retenue) ; B. durée estimée d'après les sessions passées, écartée
  (barre inventée, fausse quand on en a besoin). Liste de tâches réelle affichée en plus quand elle existe.
- Statistiques : **A. lecture des journaux locaux `~/.claude/projects/**/*.jsonl`** (retenue : tout l'historique, T3 et
  Delta compris) ; B. seulement les événements reçus par le notch, écartée (historique qui commence à l'installation,
  sessions ratées jamais comptées).
- Nom et validation : une seule voie raisonnable (ci-dessous).

## Conception

### 1. Nom : « Projet · Sujet » partout

- En-tête de session, carte de validation, carte de question, carte de plan, sélecteur : toujours le projet **et** le
  sujet.
- Sujet, par ordre de préférence : titre du fil Delta / T3 Code s'il peut être relié à la session, sinon première ligne du
  premier prompt (actuel).
- *Choix de conception :* la recherche du titre Delta / T3 se fait **dans le script de hook** (hors sandbox), qui ajoute
  un champ `topic` à l'enveloppe envoyée au socket. L'app ne lance aucun outil externe.
  - Delta : `delta --json thread list` donne des noms parlants (« Passe batch 1 : lignes 3, 5, 6 »). Le cwd des sessions
    Delta contient l'id du worktree (`.delta/worktrees/<id>/<repo>`). Reste à trouver le lien worktree → fil
    (champs de `thread show`, base locale de Delta). Si aucun lien fiable : repli premier prompt.
  - T3 Code : il génère un titre par une session technique (« Generate a title… », filtrée par `isNoise`). Reste à voir
    si ce titre est lisible (sa réponse, ou l'état local de T3) et rattachable à la session.
- Projet pour un worktree Delta : le nom du dépôt (`<repo>`), pas l'id. Les worktrees Delta vivent aussi sous
  `~/Library/Application Support/Delta/worktrees/<id>/<repo>` ; prendre le projet depuis le `cwd` réel, jamais depuis le
  nom de dossier encodé (perte : `boring.notch` → `boring-notch`).

### 2. Validation : la carte ne change plus sous le curseur

- *Choix de conception :* file **par demande**, pas par session. Répondeurs et file indexés par `tool_use_id` (ou un id
  de demande si le payload `PermissionRequest` n'en a pas), plus par `session_id`. Deux demandes de la même session
  (sous-agents parallèles) coexistent.
- La demande affichée en carte (validation, question, plan) est **figée** jusqu'à ce qu'elle soit traitée. « Traitée
  ailleurs » ne veut plus dire « n'importe quel événement de la session » mais : `PostToolUse` du même `tool_use_id`,
  `UserPromptSubmit`, `Stop` ou `SessionEnd` de la session. Les nouvelles demandes s'empilent derrière, dans l'ordre
  d'arrivée, indépendamment de l'ordre de `sessions`.
- Indicateur « 1 / 2 en attente » sur la carte quand d'autres demandes attendent (compte des demandes).
- Quand la carte vient d'apparaître ou de changer de session, ses boutons de décision sont inactifs pendant un court
  délai (≈ 0,6 s, à ajuster à l'usage), visible (bouton estompé).
- Le son « Glass » reste joué à chaque nouvelle demande.

### 3. Progression : chrono + bande d'activité

```
boring.notch · Carte de validation        ⏱ 12 min · 6 fichiers +184 −32
▮▮▮▯▯▮▮▮▮▮▮▮▮▮▯▮▮▮▮▮▮▮░░░  lecture → écriture → tests
```

- **Chrono** : temps depuis le dernier prompt de l'utilisateur (`UserPromptSubmit`), figé à `Stop`.
- **Bande d'activité** : un trait par action (Pre/PostToolUse), coloré par catégorie : lecture/recherche, modification,
  commande, sous-agent/web, attente de validation (temps passé en `waiting`). Elle se remplit avec le temps : on voit s'il
  explore, écrit, teste ou est bloqué. Résumé texte des grandes phases à droite.
- *Choix de conception :* chrono, bande et totaux couvrent **le tour en cours** (depuis le dernier prompt), c'est ce qui
  dit « où il en est ». La bande est stockée à part de `steps` (limité à 30) et regroupée en tranches si elle dépasse la
  largeur.
- **Totaux** : fichiers modifiés et lignes +/− du tour (compteur remis à zéro à `UserPromptSubmit`, à côté de `diffs`
  qui reste cumulé sur la session pour `ActivityCard`).
- **Liste de tâches réelle** si la session en a une : `TaskCreate`/`TaskUpdate`, `TodoWrite` et
  `mcp__ccd_turn__update_plan` (`items[].content`, `status` pending/in_progress/completed) lus dans `tool_input` de
  PreToolUse. Barre « 3 / 5 tâches » + tâche en cours, à la place du résumé de phases.
- Remplace les 3 dernières étapes dans la vue Progression. `ActivityCard` reste.

### 4. Statistiques : troisième bouton « Stats » à côté de Progression / Forfait

```
 Aujourd'hui 4,20 $ ▲18 %  │ Opus 72 % · Sonnet 28 %
 boring.notch 41 % · qonto-dash 22 % · WPDashboard 15 %
 ▪▪▫▪▪▪▫▪▪▪▪▫▪▪▪▫▪▪  12 dernières semaines
```

- *Choix de conception :* exception de sandbox en lecture seule sur `~/.claude/`
  (`com.apple.security.temporary-exception.files.home-relative-path.read-only` = `/.claude/`). Acceptable : fork
  personnel, signé et installé hors App Store. Le parseur reste dans l'app.
- Source : les journaux `~/.claude/projects/**/*.jsonl` (≈ 500 Mo ici) (messages assistant : `message.model`, `message.usage` avec
  tokens d'entrée, de sortie et de cache ; `timestamp` ; dossier = projet). Les sous-agents (`isSidechain`) comptent.
- **Dépense du jour** en équivalent tarif API, avec tendance par rapport à la moyenne des 7 jours précédents. Libellé
  clair : « valeur API », pas une facture. Grille de tarifs par modèle dans le code (à tenir à jour à la main).
- **Modèles** et **projets** les plus utilisés : part des tokens (ou de la valeur) sur 7 jours.
- **Grille d'activité** façon GitHub : un carré par jour sur 12 semaines, intensité selon la valeur API (ou le nombre de
  messages).
- Lecture incrémentale : mémoriser par fichier la taille déjà lue et ne lire que la suite ; agrégats par jour gardés sur
  disque. Calcul hors du thread principal, rafraîchi à l'ouverture de l'onglet et au plus toutes les minutes.
- Projet depuis le champ `cwd` de chaque ligne (pas le nom de dossier encodé) ; regrouper les worktrees
  (`.delta/worktrees/<id>/<repo>`, `Application Support/Delta/worktrees/<id>/<repo>`, `.claude/worktrees/…`) sous leur
  dépôt.

## Ce qui est laissé au constructeur

- Les couleurs des catégories, les seuils d'intensité de la grille, la mise en page exacte dans 190 pt.
- Le délai d'inactivation des boutons (≈ 0,6 s de départ).
- La façon de relier fil Delta / titre T3 à une session ; repli premier prompt si rien de fiable.
- Un auto-test sans framework (comme `scripts/*-selftest`) pour : l'agrégation des journaux (tokens → valeur, jour,
  projet de worktree), la file d'attente des validations (ordre, figement), le décodage des trois formats de tâches.
