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

## Integração com agentes (notas do Open Island)

- Detecção: hooks em `~/.claude/settings.json` chamam um CLI que manda JSON por **Unix socket**
  para o app; `PermissionRequest` fica bloqueado no socket até o usuário responder.
- Foco no terminal: AppleScript (`osascript`) casando TTY no Terminal.app/iTerm2.
- **Atenção sandbox:** o boringCode é sandboxed; escrever em `~/.claude`, abrir socket fora do
  container e rodar AppleScript em terminais exige entitlements/exceções ou mover isso para o
  helper XPC / um helper não-sandboxed. Decidir antes de implementar.
