# Tooling & custo de tokens

Ambiente de desenvolvimento otimizado para reduzir o consumo de contexto do agente.
Configurado em 2026-07-28.

## RTK (Rust Token Killer)

Proxy de CLI que filtra e comprime a saída de comandos **antes** dela entrar no
contexto do modelo.

| Item | Valor |
|---|---|
| Binário | `C:\Users\diogo\.local\bin\rtk.exe` |
| Versão | 0.44.1 |
| PATH | `C:\Users\diogo\.local\bin` (PATH de usuário, permanente) |
| Hook | `~/.claude/settings.json` → `PreToolUse`, matcher `Bash\|PowerShell` |
| Telemetria | desativada (`rtk telemetry disable`) |
| Regras Antigravity | `.agents/rules/antigravity-rtk-rules.md` |

O hook reescreve o comando antes da execução: `git status` → `rtk git status`.

### O que o RTK realmente intercepta

Verificado por pipe-test nesta máquina, não por leitura de README:

| Intercepta | Não intercepta |
|---|---|
| `git status`, `git diff`, `git log` | `rojo build`, `rojo sourcemap` |
| `git add`, `git commit` | `selene`, `stylua` |
| `ls`, `cat` (→ `rtk read`), `grep` | `wally install`, `aftman install` |

**O toolchain Roblox inteiro fica fora do RTK.** O ganho aqui vem de git e de
inspeção de arquivos, não do build. Não espere economia em `rojo build`.

Ferramentas nativas do Claude Code (`Read`, `Grep`, `Glob`) **não** passam pelo
hook de Bash — elas nunca são reescritas, por design.

### Comandos

```bash
rtk gain              # dashboard de economia
rtk gain --history    # histórico por comando
rtk discover          # varre o histórico procurando oportunidades perdidas
rtk proxy <cmd>       # executa sem filtro (debug)
```

Os números de token do `rtk gain` são estimados como `bytes / 4` — as
porcentagens são confiáveis, os valores absolutos são aproximados.

### Depois de mover ou atualizar o binário

O PATH é lido no boot do Claude Code. Se `rtk` sair do lugar, os comandos
reescritos quebram com `rtk: command not found` até reiniciar.

## ccusage

Analisador de custo que lê os JSONL locais de sessão. Não requer instalação:

```bash
npx -y ccusage@latest monthly     # custo por mês e por modelo
npx -y ccusage@latest daily
npx -y ccusage@latest session
```

## Bloqueio de leitura

`.claude/settings.json` (versionado) nega leitura de conteúdo redundante:

```
Packages/  ServerPackages/  DevPackages/  .rojo/  .git/
*.rbxl  *.rbxlx  *.rbxm  *.rbxmx  sourcemap.json
```

`wally.lock` fica **fora** da lista de propósito: é pequeno e é o primeiro lugar
onde se olha quando `wally install` falha.

`.claudecodeignore` **não existe** no Claude Code — o mecanismo real é
`permissions.deny` com regras `Read(...)`. O `.gitignore` cobre o lado de busca,
já que `respectGitignore` é `true` por padrão.

Para liberar um desses caminhos pontualmente, edite a lista `deny` — não há
override por comando.

## Plugins

| Plugin | Origem | Escopo |
|---|---|---|
| `superpowers` | `obra/superpowers-marketplace` | user |
| `obsidian` | `kepano/obsidian-skills` | user |

```bash
claude plugin list
claude plugin install <nome>@<marketplace>
claude plugin marketplace list
```

## graphify

Indexador semântico. O executável vive fora do PATH:

```
C:\Users\diogo\Projects\LuauProjects\LEARNINGS\.venv\Scripts\graphify.exe
```

Skill em `~/.claude/skills/graphify/SKILL.md`, acionada por `/graphify`.
Este projeto **não** tem `graphify-out/` — o grafo existente é do `Rythm_System`.
