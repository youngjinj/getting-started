# Claude Code 환경 백업

- 백업일: 2026-04-02
- 원본: `~/.claude/`

## 복원

```bash
bash restore.sh
```

복원 후 수동 작업:
1. API 키 설정: `claude config set primaryApiKey <your-key>`
2. 플러그인 설치: `claude plugin install oh-my-claudecode@omc`
3. 플러그인 설치: `claude plugin install clangd-lsp@claude-plugins-official`

## 백업 대상

| 파일 | 역할 |
|------|------|
| `settings.json` | 권한 규칙, 플러그인 활성화, 환경변수, HUD 설정 |
| `CLAUDE.md` | 글로벌 지시사항 (OMC 멀티 에이전트 설정) |
| `skills/jira/SKILL.md` | CUBRID JIRA 이슈 조회 스킬 |
| `skills/omc-learned/md2html/SKILL.md` | Markdown → HTML 변환 스킬 (1280px, 좌측 목차) |
| `skills/omc-reference/SKILL.md` | OMC 에이전트 카탈로그/레퍼런스 |
| `hud/omc-hud.mjs` | 상태바(status line) 스크립트 |

## 백업 제외

| 파일/디렉토리 | 이유 |
|---|---|
| `config.json` | **API 키 포함** — git에 커밋하면 안 됨. 새 환경에서 `claude config set primaryApiKey` 로 직접 설정 |
| `plugins/` (97MB) | 원격에서 재설치 가능. `restore.sh`의 플러그인 설치 명령으로 복원 |
| `projects/` | 세션별 subagent 메타데이터. 경로(`-home-cubrid-github-cubrid`)에 종속되어 다른 환경에서 의미 없음 |
| `todos/` | 세션별 태스크 상태. 세션 종료 시 소멸 |
| `sessions/` | 대화 이력. 환경 설정과 무관 |
| `session-env/` | 세션별 환경변수 스냅샷. 임시 데이터 |
| `backups/` | Claude Code 내부 자동 백업 (config.json 변경 이력) |
| `debug/` | 디버그 로그 |
| `ide/` | IDE 연동 lock 파일 |
| `shell-snapshots/` | 쉘 환경 스냅샷. 임시 데이터 |

## 프로젝트별 백업 (.omc)

`.omc/`는 `~/.claude/`와 달리 **프로젝트(레포)별** 디렉토리이다. 프로젝트마다 별도로 백업해야 한다.

`omc-cubrid/` 에 cubrid 레포의 `.omc` 중 보존 가치가 있는 파일만 백업한다.

| 파일 | 역할 | 백업? |
|------|------|-------|
| `specs/` | 딥 인터뷰 결과물 (분석 문서) | **O** |
| `project-memory.json` | OMC가 축적한 프로젝트 지식 (핫 패스, 환경 정보) | **O** |
| `sessions/` | 세션 이력 — 임시 런타임 데이터 | X |
| `state/` | HUD/에이전트 런타임 상태 — 임시 데이터 | X |

복원: `omc-cubrid/` 내용을 해당 프로젝트의 `.omc/`로 복사.

## 새 스킬 추가 시

1. `~/.claude/skills/omc-learned/<name>/SKILL.md` 에 스킬 생성
2. 이 디렉토리의 `skills/omc-learned/<name>/SKILL.md` 에도 복사
3. 커밋
