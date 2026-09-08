# MarkEditor

Editor de Markdown nativo para macOS com visão dupla: o arquivo à esquerda, o
Markdown renderizado à direita, atualizando em tempo real enquanto você digita.

## Recursos

- **Visão dupla** — editor à esquerda, preview formatado à direita, com scroll
  sincronizado nos dois sentidos e divisor ajustável (posição lembrada).
- **Preview instantâneo** — renderiza a cada tecla, sem debounce; diff por
  bloco no DOM repinta só o que mudou.
- **Modos de exibição** — somente editor (⌘1), dividido (⌘2) ou somente
  preview (⌘3), também no seletor da barra de ferramentas.
- **Preview caprichado** — headings, listas, tarefas (`- [ ]`), tabelas GFM,
  código, citações, imagens e links (abrem no navegador).
- **Highlight no editor** — realce leve da sintaxe Markdown enquanto edita.
- **Exportar** — HTML standalone com o visual do preview (⌥⇧⌘E) e PDF
  paginado (⇧⌘E), no menu Arquivo.
- **Atalhos de escrita** — ⌘B/⌘I/⌘K (menu Formatar), Enter continua listas
  (inclusive tarefas e numeradas), Tab/Shift-Tab indentam itens.
- **Toques de conforto** — colar URL sobre uma seleção cria `[texto](url)`;
  `->`/`<-` viram →/← fora de código; barra de status mostra "Salvo ✓".
- **Personalização** — em Ajustes (⌘,): aparência (claro/escuro/automático,
  claro por padrão), fonte e tamanho do editor, fonte, tamanho e entrelinha
  do preview.
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
