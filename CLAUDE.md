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
- App **sandboxed** (`boringNotch/boringNotch.entitlements`) + helper XPC (`BoringNotchXPCHelper/`)
  para trabalho privilegiado (Accessibility, brilho, notificações).
- SPM: Defaults (settings), Sparkle (updates), SkyLightWindow, Lottie, Pow, KeyboardShortcuts,
  LaunchAtLogin, swiftui-introspect, swift-collections, AsyncXPCConnection, MacroVisionKit.

## Identidade do app (não conflitar com o Boring Notch instalado)

| | Upstream | boringCode |
|---|---|---|
| Nome / executável | `Boring Notch` | `boringCode` |
| Bundle ID | `theboringteam.boringnotch` | `com.reesoousa.boringcode` |
| Helper XPC | `theboringteam.boringnotch.BoringNotchXPCHelper` | `com.reesoousa.boringcode.BoringNotchXPCHelper` |
| Sparkle feed | appcast do upstream | `https://reesoousa.github.io/boring.notch/appcast.xml` (ainda não existe) |

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
# build Debug (saída em ./build, já no .gitignore)
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug \
  -derivedDataPath build -destination 'platform=macOS,arch=arm64' build

# rodar (encerra instância anterior)
pkill -x boringCode; open build/Build/Products/Debug/boringCode.app

# testes
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -derivedDataPath build test
```

- Rodar junto com o Boring Notch de `/Applications` funciona, mas os dois desenham no notch —
  feche o instalado para testar visualmente.
- Assinatura atual: ad-hoc (`CODE_SIGN_IDENTITY[sdk=macosx*] = "-"`), sem Team. Permissões do
  macOS (Accessibility, Automation) podem ser pedidas de novo a cada rebuild.

## Regras de git

- **Nunca** commitar direto em `main` nem `dev`. Uma branch por feature: `feat/...`
  (ou `fix/...`, `chore/...`), partindo da `dev` atualizada.
- **Conventional Commits em pt-BR** (`feat: adiciona aba de agentes`).
- Commit e push livres nas branches de feature. PR → `dev` do **fork** (`reesoousa/boring.notch`).
- **Sem** force-push, rebase de branch publicada ou rewrite de histórico sem perguntar.
- Remotes: `origin` = fork (`reesoousa/boring.notch`), `upstream` = `TheBoredTeam/boring.notch`.
  Sincronizar: `git fetch upstream && git merge upstream/dev` (numa branch, nunca direto na `dev`).
- `reference/` nunca entra no git.

## Distribuição (pendente)

Objetivo: forma fácil de mandar pro pessoal da empresa.
- Ideal: `.dmg` assinado com **Developer ID** + notarizado (abre sem alerta). Requer Apple
  Developer Program. Script base de DMG: `Configuration/dmg/`.
- Sem conta paga: build ad-hoc → cada pessoa libera em Ajustes › Privacidade e Segurança.
- Updates: Sparkle apontando para appcast próprio no GitHub Pages do fork (gerar nova chave EdDSA).

## Módulo de agentes (`boringNotch/agents/`)

Decisões de produto (definidas pelo dono):
- **Aba "Agentes"** no notch aberto (ao lado de Home/Shelf). Lista sessões, aprovar/recusar, clique → foca terminal/editor.
- **Notch fechado:** com agente rodando, o indicador fica **do lado direito, no lugar do mini espectro de áudio**.
  Sem agente, o espectro volta. Sem música, vira uma live activity própria (contagem | notch | indicador).
- **Hover no indicador** abre o notch direto na aba Agentes; o resto do hover segue o Boring Notch normal.
- **Pedido de aprovação** expande o notch sozinho na aba Agentes e fecha sozinho quando resolvido.
- Tudo **ligado por padrão** (público-alvo: devs). Configurações em Ajustes › "AI Agents".
- **Hosts suportados:** Claude Code no terminal (Terminal/iTerm), extensão do Claude para VS Code
  (e Cursor), app Claude (aba Code). Codex fica para depois.
- **Guardrails de design:** seguir a linguagem visual do Boring Notch (preto, cinza, cantos 12, SF Symbols,
  mesmas geometrias de live activity). Não alterar layouts existentes além do slot do espectro.
- Strings: chave em inglês + tradução pt-BR em `Localizable.xcstrings` (script python, preservando ordem).

Arquitetura:
- `ClaudeHookInstaller` escreve `~/Library/Application Support/boringCode/bin/boringcode-hook` (sh + curl)
  e adiciona entradas em `~/.claude/settings.json` identificadas por `boringCode/bin/boringcode-hook`
  (backup `settings.json.boringcode-backup.*`, mantém 5). Não toca hooks de outras ferramentas.
- O script faz `curl --unix-socket agents.sock` → `AgentHookServer` (HTTP mínimo, POSIX socket).
  `PermissionRequest` fica pendurado (timeout 86400) até aprovar/recusar; se o hook morrer
  (respondeu no terminal) o servidor detecta EOF e tira do notch. Fail-open sem o app.
- `AgentSessionStore` (@MainActor) = reducer de eventos → `AgentSession` (status, atividade, TTY, PID).
  Poda sessões cujo PID morreu. `AgentTerminalFocus` = AppleScript por TTY / abrir pasta no VS Code.
- Limite de 104 bytes no caminho do socket (sun_path) — o caminho dentro do container do sandbox
  estoura (112). **O módulo exige app sem sandbox** (decisão pendente com o dono).
- Testar o núcleo sem o app: compilar `agents/AgentHookServer.swift`, `AgentModels.swift`,
  `ClaudeHookInstaller.swift` + um `main.swift` com `swiftc` e usar socket em caminho curto.
- Convive com Open Island instalado: se os dois estiverem abertos, ambos seguram o PermissionRequest.
