# MarkEditor

Editor de Markdown nativo para macOS com visão dupla: o arquivo à esquerda, o
Markdown renderizado à direita, atualizando em tempo real enquanto você digita.

## Recursos

- **Visão dupla** — editor à esquerda, preview formatado à direita, com scroll
  sincronizado (editor → preview) e divisor ajustável.
- **Modos de exibição** — somente editor (⌘1), dividido (⌘2) ou somente
  preview (⌘3), também no seletor da barra de ferramentas.
- **Preview caprichado** — headings, listas, tarefas (`- [ ]`), tabelas GFM,
  código, citações, imagens e links (abrem no navegador).
- **Highlight no editor** — realce leve da sintaxe Markdown enquanto edita.
- **Personalização** — em Ajustes (⌘,): fonte e tamanho do editor, fonte,
  tamanho e entrelinha do preview.
- **Light mode** — o app é desenhado para modo claro, sempre.
- Documento nativo do macOS: abrir/salvar `.md`, autosave, undo, renomear pelo
  título da janela, arquivos recentes.

## Build

Requer Xcode (ou Command Line Tools com Swift 5.10+).

```bash
make app     # gera build/MarkEditor.app
make run     # builda e abre o app
make icon    # regenera Resources/AppIcon.icns
make clean
```

O projeto é um pacote SwiftPM puro — `Scripts/build-app.sh` monta o bundle
`.app` a partir do executável + `Support/Info.plist` e assina ad-hoc. Também dá
para abrir a pasta no Xcode e rodar o target `MarkEditor` direto.

## Estrutura

```
Sources/MarkEditor/
  MarkEditorApp.swift        # App + DocumentGroup + Settings
  MarkdownDocument.swift     # FileDocument (.md / texto)
  ContentView.swift          # split view, toolbar, barra de status
  Editor/                    # NSTextView + highlight de sintaxe
  Preview/                   # WKWebView + renderer HTML (swift-markdown)
  Settings/                  # chaves, fontes e tela de Ajustes
Support/Info.plist           # tipos de documento, metadados do bundle
Scripts/                     # build do .app e geração do ícone
```
