# boringCode

Fork do [Boring Notch](https://github.com/TheBoredTeam/boring.notch) (branch `dev`) que integra
recursos do [Open Island](https://github.com/Octane0411/open-vibe-island): monitorar agentes de IA
(Claude Code, Codex) no notch, aprovar ações e voltar pro terminal certo.

- **Dono:** @reesoousa (UX designer — explicar decisões técnicas em linguagem simples).
- **Licença:** GPL-3.0 (os dois projetos). Código portado do Open Island mantém crédito no
  cabeçalho do arquivo (`// Adaptado de Open Island (github.com/Octane0411/open-vibe-island), GPL-3.0`).
- **Idioma:** responder em pt-BR.

## Stack

- Swift 5/6 + SwiftUI + AppKit, projeto Xcode (`boringNotch.xcodeproj`), macOS 14+.
- App **sem sandbox** (ver "Módulo de agentes") + helper XPC (`BoringNotchXPCHelper/`)
  para trabalho privilegiado (Accessibility, brilho, notificações).
- Versão atual: **0.1.0 "Astronaut Cat"** (`MARKETING_VERSION` no projeto; apelido em
  `BoringCodeRelease.name`, `AboutView.swift`).
- SPM: Defaults (settings), Sparkle (updates), SkyLightWindow, Lottie, Pow, KeyboardShortcuts,
  LaunchAtLogin, swiftui-introspect, swift-collections, AsyncXPCConnection, MacroVisionKit.

## Identidade do app (não conflitar com o Boring Notch instalado)

| | Upstream | boringCode |
|---|---|---|
| Nome / executável | `Boring Notch` | `boringCode` |
| Bundle ID | `theboringteam.boringnotch` | `com.reesoousa.boringcode` |
| Helper XPC | `theboringteam.boringnotch.BoringNotchXPCHelper` | `com.reesoousa.boringcode.BoringNotchXPCHelper` |
| Sparkle feed | appcast do upstream | `https://reesoousa.github.io/boringCode/appcast.xml` (ainda não existe) |

`PRODUCT_MODULE_NAME` continua `boringNotch` (os testes usam `@testable import boringNotch`).
O nome do serviço XPC é derivado do bundle ID em `XPCHelperClient.swift`.

## Estrutura

```
boringNotch/                 # app principal
  boringNotchApp.swift       # @main + AppDelegate
  ContentView.swift          # raiz do notch: estados, hover, abas, live activities
  enums/generic.swift        # NotchState (closed/open), NotchViews (abas)
  models/                    # BoringViewModel (estado por tela), Constants.swift (Defaults.Keys)
  managers/                  # singletons: NotchWindowManager, MusicManager, Battery...
  components/
    Notch/                   # janela (BoringNotchSkyLightWindow), header, home, LiveActivityStack
    Tabs/                    # TabSelectionView (barra de abas)
    Settings/                # SettingsView + Views/
    Shelf/ Music/ Calendar/ OSD/ LiveActivities/ Webcam/ Onboarding/
BoringNotchXPCHelper/        # helper XPC
Shared/                      # protocolo XPC
boringNotchTests/
reference/open-island/       # clone SÓ LEITURA do Open Island (ignorado via .git/info/exclude)
```

Pontos de extensão para o módulo de agentes:
- **Nova aba:** case em `NotchViews` + `TabModel` em `TabSelectionView.swift` + case no switch
  de `ContentView` (conteúdo aberto).
- **Indicador no notch fechado:** novo case em `LiveActivityItem` (`components/Notch/LiveActivityStack.swift`),
  incluir em `ContentView.liveActivities` e na largura do "chin".
- **Alertas transitórios:** `SneakContentType` / `toggleSneakPeek` em `BoringViewCoordinator`.
- **Settings:** chave em `Defaults.Keys` (`models/Constants.swift`) + aba em `SettingsView`.

## Compilar e rodar

```bash
# compilar + assinar + instalar a ÚNICA cópia em /Applications + abrir (é o fluxo padrão)
scripts/install-dev.sh            # --no-open para só instalar

# instalador (ver "Distribuição")
scripts/make-dmg.sh   # → dist/boringCode-<versão>.dmg

# testes
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -derivedDataPath build.noindex test
```

- **Nunca abrir o app de dentro de `build.noindex/`** nem copiar à mão: só existe uma cópia,
  `/Applications/boringCode.app`. O sufixo `.noindex` esconde os builds do Spotlight/Finder e o
  script tira-os do registro de apps (antes apareciam 3 "boringCode" no Finder).
- **Assinatura de dev estável:** `install-dev.sh` re-assina tudo com o certificado local
  `boringCode Dev` (criado uma vez por `scripts/setup-dev-signing.sh` no chaveiro de login,
  autoassinado, só desta máquina). Ad-hoc (`-`) muda de identidade a cada build e o macOS
  pedia Acessibilidade/Automação de novo; com o certificado a identidade é
  `identifier "com.reesoousa.boringcode" and certificate leaf = H"…"` e as permissões ficam.
  O projeto Xcode continua ad-hoc (a re-assinatura é só no script).
- Rodar junto com o Boring Notch de `/Applications` funciona, mas os dois desenham no notch —
  feche o instalado para testar visualmente.
- Projeto Xcode: ad-hoc (`CODE_SIGN_IDENTITY[sdk=macosx*] = "-"`), sem Team.
- **O build Release ad-hoc cai na abertura** (library validation recusa o
  `MediaRemoteAdapter.framework`: "different Team IDs"). O Debug roda. Ver "Distribuição".

## Regras de git

- **Nunca** commitar direto em `main` nem `dev`. Uma branch por feature: `feat/...`
  (ou `fix/...`, `chore/...`), partindo da `dev` atualizada.
- **Conventional Commits em pt-BR** (`feat: adiciona aba de agentes`).
- Commit e push livres nas branches de feature. PR → `dev` do **fork** (`reesoousa/boringCode`).
- **Sem** force-push, rebase de branch publicada ou rewrite de histórico sem perguntar.
- Remotes: `origin` = fork (`reesoousa/boringCode`), `upstream` = `TheBoredTeam/boring.notch`.
  Sincronizar: `git fetch upstream && git merge upstream/dev` (numa branch, nunca direto na `dev`).
- `reference/` nunca entra no git.

## Distribuição (pendente — próximos passos do DMG)

Objetivo: `.dmg` fácil para os colegas da empresa (vários usam Mac). Pausado até o dono escolher
a assinatura. `scripts/make-dmg.sh` já faz: build Release → `codesign --verify` → dmgbuild (hashes
travados, venv em `build.noindex/dmgenv`) → `dist/boringCode-<versão>.dmg` (layout `Configuration/dmg/`).

1. **Escolher a assinatura** (decisão do dono):
   - **Developer ID da empresa** (recomendado; perguntar ao TI) → assinar + notarizar, abre sem alerta.
   - **Apple ID pessoal grátis** (Xcode › Ajustes › Contas) → dá Team ID, resolve a queda; colegas
     liberam uma vez em Ajustes › Privacidade e Segurança › "Abrir mesmo assim".
   - **`com.apple.security.cs.disable-library-validation`** → funciona sem conta, menos protegido;
     também exige "Abrir mesmo assim". Pedir OK explícito (o classificador pode barrar).
2. Configurar `DEVELOPMENT_TEAM`/identidade (ou o entitlement) e, se Developer ID, notarização
   (`xcrun notarytool` + `stapler`) dentro do `make-dmg.sh`.
3. Gerar o DMG a partir da `dev` e **testar abrindo o app de dentro do DMG montado**
   (crash → `~/Library/Logs/DiagnosticReports/boringCode-*.ips`).
4. Opcional: fundo próprio do DMG (660×400, `Configuration/dmg/.background/background.tiff`).
5. Updates: Sparkle aponta para `https://reesoousa.github.io/boringCode/appcast.xml` (não existe);
   gerar chave EdDSA própria + GitHub Pages, ou desligar a busca automática até lá.
6. Publicar como Release no GitHub (`gh release create v0.1.0 dist/boringCode-0.1.0.dmg`).

## Módulo de agentes (`boringNotch/agents/`)

Decisões de produto (definidas pelo dono):
- **Aba "Agentes"** no notch aberto (ao lado de Home/Shelf). Lista sessões, aprovar/recusar, clique → foca terminal/editor.
- **Notch fechado** (prioridade sempre do layout do Boring Notch):
  - só música → capa à esquerda, espectro à direita (original).
  - música + agente → música à esquerda (interações normais), **indicador do agente no lugar do espectro**.
  - só agente → padrão Open Island nos dois lados: status geral à esquerda (✻ / ! / ? / ✓ / ✗),
    um quadradinho por sessão à direita (cor = status; pulsa quando espera você).
- **Hover nas áreas do agente** abre o notch direto na aba Agentes; esquerda/centro/arrastar arquivo = normal.
- **Perguntas (AskUserQuestion)** respondidas no notch (opções + "Outra…"); ExitPlanMode vira aprovação.
- **Nome:** tudo que o usuário vê diz "boringCode" (traduções no xcstrings, chaves iguais ao upstream).
  Sobre credita Boring Notch e Open Island.
- **Pedido de aprovação** expande o notch sozinho na aba Agentes e fecha sozinho quando resolvido.
- Tudo **ligado por padrão** (público-alvo: devs). Configurações em Ajustes › "Agentes de IA".
- **Agentes/hosts:** Claude Code (Terminal/iTerm, extensão VS Code/Cursor, app Claude) e Codex
  (CLI, VS Code, app Codex = `ChatGPT.app`, bundle `com.openai.codex`, `codex://threads/<id>`).
  Cores: Claude laranja, Codex azul.
- **Animação calma:** ✻ vetorial gira 8 s/volta e respira; parado com Reduzir movimento.
  Nada frenético/chamativo quando ocioso. Ícone da aba: `>_` sem caixa (`AgentPromptGlyph`).
- **Som sutil** ao concluir (som do sistema, padrão Bottle, volume 0,35).
- **Logo** (arte-fonte em `logo/`): ícone do app (grade 824/1024), barra de menus (SVG template
  `menubarIcon`), boas-vindas. Sobre no padrão Apple: "Feito para pessoas não tão chatas assim."
- **LocalSend** no Shelf (Quick Share), abrindo o app direto; AirDrop continua padrão.
- **Guardrails de design:** seguir a linguagem visual do Boring Notch (preto, cinza, cantos 12, SF Symbols,
  mesmas geometrias de live activity). Não alterar layouts existentes além do slot do espectro.
- Strings: chave em inglês + tradução pt-BR em `Localizable.xcstrings` (script python, preservando ordem:
  `json.dumps(d, indent=2, separators=(',', ' : '), ensure_ascii=False)`, sem `sort_keys`).
  Conflitos entre branches nesse arquivo: resolver pela **união das chaves**.

Arquitetura:
- `AgentHookInstaller` (`.claude` e `.codex`) escreve `~/Library/Application Support/boringCode/bin/boringcode-hook` (sh + curl)
  e adiciona entradas em `~/.claude/settings.json` / `~/.codex/hooks.json` (+ `[features] hooks = true`
  no `config.toml`) identificadas por `boringCode/bin/boringcode-hook` (backup `*.boringcode-backup.*`,
  mantém 5). Não toca hooks de outras ferramentas. Script: `boringcode-hook <Evento> [claude|codex]`.
- O script faz `curl --unix-socket agents.sock` → `AgentHookServer` (HTTP mínimo, POSIX socket).
  `PermissionRequest` fica pendurado (timeout 86400) até aprovar/recusar; se o hook morrer
  (respondeu no terminal) o servidor detecta EOF e tira do notch. Fail-open sem o app.
- `AgentSessionStore` (@MainActor) = reducer de eventos → `AgentSession` (status, atividade, TTY, PID).
  Poda sessões cujo PID morreu. `AgentTerminalFocus` = AppleScript por TTY / abrir pasta no VS Code.
- **App sem sandbox** (aprovado pelo dono em 2026-09-30): precisa escrever em `~/.claude`, controlar
  Terminal/iTerm e o socket (limite de 104 bytes no sun_path estoura dentro do container).
- Testar o núcleo sem o app: compilar `agents/AgentHookServer.swift`, `AgentModels.swift`,
  `AgentHookInstaller.swift` + um `main.swift` com `swiftc` e usar socket em caminho curto.
- Convive com Open Island instalado: se os dois estiverem abertos, ambos seguram o PermissionRequest.
