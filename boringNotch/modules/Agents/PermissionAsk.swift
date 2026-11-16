//
//  PermissionAsk.swift
//  boringNotch
//
//  Demande de validation d'un agent, traduite en une phrase française par gabarits locaux
//  (ponytail: aucun appel LLM, donc aucun coût d'API pour l'utilisateur ; un outil inconnu
//  tombe sur la phrase générique, on ajoute un `case` quand un nouvel outil le mérite).
//

import Foundation

struct PermissionAsk: Equatable {
    var question: String      // « Claude veut modifier le fichier Foo.swift. »
    var tool: String          // nom technique brut, affiché en petit
    var details: [String]     // lignes d'appui : chemin, commande, paramètres…

    init(agent: String, tool: String, input i: AgentEnvelope.ToolInput?) {
        self.tool = tool
        let v = "\(agent) veut"
        func name(_ path: String?) -> String { path.map { ($0 as NSString).lastPathComponent } ?? "un fichier" }
        func path(_ p: String?) -> [String] { p.map { [($0 as NSString).abbreviatingWithTildeInPath] } ?? [] }
        func clip(_ s: String, _ n: Int) -> String { s.count > n ? s.prefix(n) + "…" : s }

        switch tool {
        case "Bash", "shell", "local_shell":
            question = "\(v) exécuter une commande."
            details = i?.command.map { [clip($0.split(whereSeparator: \.isNewline).prefix(3).joined(separator: "\n"), 220)] } ?? []
        case "Edit", "MultiEdit":
            question = "\(v) modifier le fichier « \(name(i?.file_path)) »."
            details = path(i?.file_path)
        case "Write":
            question = "\(v) écrire le fichier « \(name(i?.file_path)) »."
            details = path(i?.file_path)
        case "NotebookEdit":
            question = "\(v) modifier le notebook « \(name(i?.scalars["notebook_path"])) »."
            details = path(i?.scalars["notebook_path"])
        case "Read":
            question = "\(v) lire le fichier « \(name(i?.file_path)) »."
            details = path(i?.file_path)
        case "Glob", "Grep":
            question = "\(v) chercher « \(clip(i?.pattern ?? "…", 50)) » dans les fichiers."
            details = path(i?.scalars["path"])
        case "WebFetch":
            let url = i?.scalars["url"]
            question = "\(v) consulter le site \(url.flatMap { URL(string: $0)?.host } ?? "web")."
            details = url.map { [clip($0, 160)] } ?? []
        case "WebSearch":
            question = "\(v) faire une recherche web : « \(clip(i?.scalars["query"] ?? "…", 80)) »."
            details = []
        case "Task", "Agent":
            question = "\(v) lancer un sous-agent\(i?.scalars["subagent_type"].map { " (\($0))" } ?? "")."
            details = (i?.description ?? i?.scalars["prompt"]).map { [clip($0, 160)] } ?? []
        case "Skill":
            question = "\(v) utiliser la compétence « \(i?.scalars["skill"] ?? "…") »."
            details = []
        case "apply_patch":
            question = "\(v) appliquer un correctif au code."
            details = []
        case _ where tool.hasPrefix("mcp__"):
            // mcp__claude_ai_n8n__get_workflow_execution -> service « n8n », action « get workflow execution »
            let parts = tool.dropFirst(5).components(separatedBy: "__")
            func pretty(_ s: String) -> String {
                s.replacingOccurrences(of: "claude_ai_", with: "").replacingOccurrences(of: "plugin_", with: "")
                    .replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
            }
            let action = pretty(parts.dropFirst().joined(separator: " "))
            question = "\(v) utiliser « \(action.isEmpty ? tool : action) » du service \(pretty(parts[0]))."
            details = (i?.scalars ?? [:]).filter { !$0.value.isEmpty }.sorted { $0.key < $1.key }
                .prefix(3).map { "\($0.key) : \(clip($0.value, 80))" }
        default:
            question = "\(v) utiliser l'outil « \(tool) »."
            details = (i?.scalars ?? [:]).sorted { $0.key < $1.key }.prefix(3).map { "\($0.key) : \(clip($0.value, 80))" }
        }
    }
}
