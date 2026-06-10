# dooray-cli

두레이 프로젝트 관리 CLI. 태스크, 댓글, 워크플로우, 태그, 첨부파일을 조회하고 관리합니다.

## 설치

```bash
brew install sunghyun-k/tap/dooray-cli
```

## 사전 요구사항

- macOS 13+
- `DOORAY_API_TOKEN` 환경변수 설정 필요
- (선택) `DOORAY_TENANT` 환경변수: 테넌트 코드 (예: `your-tenant`) 또는 전체 URL (예: `https://your-tenant.dooray.com`)

```bash
export DOORAY_API_TOKEN="your-api-token"
export DOORAY_TENANT="your-tenant"
```

## 사용법

```bash
# 프로젝트 목록
dooray-cli project list [--state active|archived] [--mine] [--page 0]

# 프로젝트 멤버
dooray-cli project members <프로젝트코드>

# 태스크 조회 (ID, 프로젝트코드/번호, URL 모두 지원) — 하위 태스크 목록 포함
dooray-cli task get <식별자>

# 태스크 목록
dooray-cli task list <프로젝트코드> [--workflow backlog,registered,working,closed] [--order -postUpdatedAt] [--to-member-ids 멤버ID,...] [--created-by me|멤버ID,...] [--created-at today|thisweek|prev-Nd|next-Nd|ISO8601~ISO8601] [--page 0]

# 태스크 생성
dooray-cli task create <프로젝트코드> "제목" [--body "본문"] [--body-file 본문.md] [--priority normal] [--due-date 2024-12-31] [--to 멤버ID]

# 태스크 수정
dooray-cli task update <식별자> [--subject "새제목"] [--body "새본문"] [--body-file 본문.md] [--priority high]

# 워크플로우 변경
dooray-cli task set-workflow <식별자> <워크플로우ID>

# 댓글 목록/작성/수정
dooray-cli comment list <식별자> [--page 0]
dooray-cli comment create <식별자> "댓글 내용"
dooray-cli comment create <식별자> --body-file 내용.md
dooray-cli comment update <식별자> <댓글ID> "수정할 내용"

# 워크플로우/태그 목록
dooray-cli workflow list <프로젝트코드>
dooray-cli tag list <프로젝트코드> [--page 0]

# 첨부파일 목록/다운로드/업로드
dooray-cli file list <식별자>
dooray-cli file download <식별자> [--output 저장경로] [파일ID]
dooray-cli file upload <식별자> <파일경로> [파일경로...] [--inline]
```

### 인라인 이미지

본문(`--body`, `--body-file`)과 댓글 내용의 마크다운에서 `![이름](로컬경로)` 형태로 로컬 이미지를 참조하면, 자동으로 인라인 이미지로 업로드되고 `/files/{fileId}` 참조로 치환됩니다.

- `--body` 또는 댓글 텍스트 입력: 상대경로는 **현재 디렉토리 기준**
- `--body-file`: 상대경로는 **마크다운 파일이 있는 디렉토리 기준**
- URL(`https://...`), 기존 `/files/` 참조, 존재하지 않는 경로는 치환하지 않습니다.

```bash
dooray-cli comment create my-project/123 "결과 스크린샷:

![결과](./screenshot.png)"
```

미리 업로드해두고 직접 참조하려면 `file upload --inline`으로 fileId를 받아 `![이름](/files/{fileId})`로 본문에 넣으면 됩니다.

출력은 CSV 형식입니다. 태스크 상세 조회는 사람이 읽기 쉬운 형식으로 출력됩니다.

### 태스크 식별자

세 가지 형식을 지원합니다:

- **태스크 ID**: 19자리 숫자 (예: `1234567890123456789`)
- **프로젝트코드/번호**: `my-project/123`
- **두레이 URL**: `https://your-tenant.dooray.com/project/my-project/task/456` 또는 `https://your-tenant.dooray.com/task/{projectId}/{postId}`

## AI 에이전트 연동

### Claude Code

[Claude Code](https://docs.anthropic.com/en/docs/claude-code) 플러그인으로 사용할 수 있습니다.

```
/plugin marketplace add sunghyun-k/dooray-cli
/plugin install dooray-cli@dooray-cli
```

## License

MIT
