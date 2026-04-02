---
name: md2html
description: Markdown 파일을 1280px 고정 좌측 목차가 있는 HTML로 변환
triggers:
  - md2html
  - html로 변환
  - html로 만들어
  - markdown to html
argument-hint: "<markdown-file-path>"
---

# md2html Skill

## Purpose

Markdown(.md) 파일을 읽기 좋은 HTML 문서로 변환한다. 1280px 너비에 최적화되고, 좌측에 sticky 목차가 있어 스크롤 중에도 원하는 섹션으로 이동할 수 있다.

## When to Activate

- 사용자가 `/md2html <파일경로>` 로 호출할 때
- "html로 변환해줘", "html로 만들어줘" 등의 요청과 함께 md 파일 경로가 주어질 때

## Workflow

1. 주어진 Markdown 파일을 읽는다 (큰 파일은 분할 읽기)
2. 마크다운 구조를 파싱하여 HTML로 변환한다
3. 같은 디렉토리에 `.html` 확장자로 파일을 생성한다

## HTML 스타일 사양

### 레이아웃
- 최대 너비: **1280px**, 가운데 정렬
- 좌측 **260px sticky 목차** (다크 테마 `#1a1a2e`, 높이 100vh, overflow-y auto)
- 우측 **본문 영역** (흰 배경, padding 40px 48px)

### 목차 (TOC)
- h2는 `.toc-h2` (굵게, margin-top 8px)
- h3는 `.toc-h3` (padding-left 16px, font-size 12px)
- h4는 `.toc-h4` (padding-left 28px, font-size 11.5px)
- 스크롤 위치에 따라 **현재 섹션 자동 하이라이트** (`.active` 클래스, 색상 `#8be9fd`)
- 클릭 시 **smooth scroll** + URL hash 업데이트
- 목차가 길면 TOC 자체도 스크롤되어 active 항목이 보이도록 처리

### 타이포그래피
- 본문: 15px, line-height 1.7, font-family: system-ui + "Noto Sans KR"
- h1: 28px, 하단 3px `#4361ee` 보더
- h2: 22px, 하단 2px `#e8e8f0` 보더, margin-top 48px
- h3: 17px, margin-top 32px
- h4: 15px, margin-top 24px

### 코드
- 인라인 `code`: 배경 `#f0f1f6`, 색상 `#c7254e`, font-size 13px
- 코드 블록 `pre`: 다크 배경 `#1e1e2e`, 색상 `#cdd6f4`, border-radius 8px
- 구문 강조 클래스: `.cm` (주석, `#6c7086`), `.kw` (키워드, `#cba6f7`), `.st` (문자열, `#a6e3a1`)

### 테이블
- 전체 너비, border-collapse
- 헤더: 배경 `#f0f1f6`, 하단 2px 보더
- 행 hover: 배경 `#f8f8fc`

### 특수 요소
- **callout 박스**: `.callout-warning` (노란색), `.callout-info` (파란색), `.callout-note` (보라색)
- **summary-box**: 요약 섹션용, gradient 배경 + 라운드 보더
- **tier 뱃지**: `.tier-0`~`.tier-3` 색상별 뱃지
- **체크박스**: `.chk` 클래스 (빈 체크박스 스타일)

### 기능
- 우측 하단 **맨 위로** 버튼 (스크롤 400px 이후 표시)
- **반응형**: 900px 이하에서 TOC 숨김

### 마크다운 → HTML 매핑

| Markdown | HTML |
|----------|------|
| `# 제목` | `<h1>` (문서 제목, 1개만) |
| `## 섹션` | `<h2 id="secN">` + TOC `.toc-h2` 항목 |
| `### 하위 섹션` | `<h3 id="secN-M">` + TOC `.toc-h3` 항목 |
| `#### 소제목` | `<h4 id="secN-M-K">` + TOC `.toc-h4` 항목 |
| `**굵게**` | `<strong>` |
| `` `코드` `` | `<code>` |
| 코드 블록 | `<pre><code>` (C/C++ 키워드에 `.kw`, 주석에 `.cm`, 문자열에 `.st`) |
| `\| 테이블 \|` | `<table>` |
| `- 목록` | `<ul><li>` |
| `1. 목록` | `<ol><li>` |
| `---` | `<hr>` |
| `> 인용` 또는 **주의/참고** 문단 | `.callout` 박스 (내용에 따라 warning/info/note) |
| `- [ ] 체크` | `<span class="chk">` + 텍스트 |

## 파일 생성 규칙

- 출력 파일명: 입력 `.md`를 `.html`로 교체 (예: `analysis.md` → `analysis.html`)
- 이미 `.html` 파일이 존재하면 먼저 Read한 후 덮어쓰기
- 모든 내용을 한 파일에 포함 (외부 CSS/JS 의존 없음, self-contained)

## Examples

```
/md2html /path/to/document.md
```

```
이 md 파일 html로 변환해줘: /path/to/analysis.md
```

## Notes

- 한국어/영어 혼용 문서 지원
- 매우 큰 md 파일(1000줄+)은 분할 읽기로 처리
- 기존 HTML이 있으면 md 변경분만 반영하는 것이 아니라 전체 재생성
