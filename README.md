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

# 본문(마크다운)만 출력 — 파일로 저장 후 편집·재업데이트하는 라운드트립 용도
dooray-cli task get <식별자> --body-only > task.md

# 태스크 목록
dooray-cli task list <프로젝트코드> [--workflow backlog,registered,working,closed] [--order -postUpdatedAt] [--to-member-ids 멤버ID,...] [--created-by me|멤버ID,...] [--created-at today|thisweek|prev-Nd|next-Nd|ISO8601~ISO8601] [--page 0]

# 태스크 생성 (--parent 지정 시 하위 태스크로 생성)
dooray-cli task create <프로젝트코드> "제목" [--body "본문"] [--body-file 본문.md] [--priority normal] [--due-date 2024-12-31] [--to 멤버ID] [--parent 상위태스크식별자] [--tag "Platform: iOS" --tag "업무: Document"]

# 태스크 수정 (--body-mime 미지정 시 기존 본문 형식을 그대로 유지, --tag 는 태그 목록을 교체)
dooray-cli task update <식별자> [--subject "새제목"] [--body "새본문"] [--body-file 본문.md] [--body-mime text/html] [--priority high] [--tag iOS,Document]

# 기존 태스크를 하위 태스크로 연결 (같은 프로젝트 내에서만, 1단계 계층만 지원)
dooray-cli task set-parent <식별자> <상위태스크식별자>

# 워크플로우 변경
dooray-cli task set-workflow <식별자> <워크플로우ID>

# 댓글 목록/작성/수정
dooray-cli comment list <식별자> [--page 0]
dooray-cli comment create <식별자> "댓글 내용"
dooray-cli comment create <식별자> --body-file 내용.md
dooray-cli comment update <식별자> <댓글ID> "수정할 내용"

# 워크플로우/태그 목록 (태그는 소속 그룹과 필수 여부를 함께 출력)
dooray-cli workflow list <프로젝트코드>
dooray-cli tag list <프로젝트코드> [--page 0]

# 첨부파일 목록/다운로드/업로드
dooray-cli file list <식별자>
dooray-cli file download <식별자> [--output 저장경로] [파일ID]
dooray-cli file upload <식별자> <파일경로> [파일경로...] [--inline]
```

### 태그

`--tag` 는 태그 이름 또는 ID를 받습니다. 쉼표로 여러 개를 묶거나 옵션을 여러 번 지정할 수 있고, 그룹 접두사를 생략한 짧은 이름(`iOS`)도 그 이름이 프로젝트에서 유일하면 인식합니다.

```bash
dooray-cli task create my-project "제목" --tag "Platform: iOS" --tag "Project: Etc,업무: Document"
dooray-cli task update my-project/123 --tag iOS,Document   # 태그 목록을 이 둘로 교체
```

태그 그룹을 필수로 설정한 프로젝트에서는 태그 없이 태스크를 만들 수 없습니다. 두레이 서버는 이때 `USER_INVALID_TAG_MANDATORY_PREFIX` 만 반환해 어떤 그룹이 빠졌는지 알려 주지 않으므로, CLI가 요청을 보내기 전에 필수 그룹과 선택 가능한 태그를 먼저 안내합니다.

```
$ dooray-cli task create my-project "제목"
Error: 이 프로젝트는 다음 태그 그룹을 필수로 요구합니다. --tag 로 각 그룹에서 하나 이상 지정하세요.
  [Platform] Platform: Android, Platform: Etc, Platform: iOS
  [업무] 업무: Document, 업무: Etc, 업무: Feature
```

### 인라인 이미지

본문(`--body`, `--body-file`)과 댓글 내용의 마크다운에서 `![이름](로컬경로)` 형태로 로컬 이미지를 참조하면, 자동으로 인라인 이미지로 업로드되고 `/files/{fileId}` 참조로 치환됩니다.

두레이 파일 업로드 API는 태스크에 종속된 엔드포인트라 태스크가 없으면 파일을 올릴 수 없습니다. 그래서 `task create` 는 본문에 로컬 이미지가 있으면 **본문을 비워 태스크를 먼저 만들고, 이미지를 업로드한 뒤 본문을 채웁니다.** 업로드가 중간에 실패해도 로컬 경로가 그대로 박힌 본문이 남지 않으며, 실패 시 이어서 올릴 수 있는 `task update` 명령을 안내합니다.

- `--body` 또는 댓글 텍스트 입력: 상대경로는 **현재 디렉토리 기준**
- `--body-file`: 상대경로는 **마크다운 파일이 있는 디렉토리 기준**
- URL(`https://...`), 기존 `/files/` 참조, 존재하지 않는 경로는 치환하지 않습니다.

### 본문 라운드트립 (조회 → 편집 → 재업데이트)

```bash
dooray-cli task get <식별자> --body-only > task.md   # 본문만 저장
$EDITOR task.md                                       # 로컬에서 편집
dooray-cli task update <식별자> --body-file task.md   # 다시 반영
```

- `--body-only` 출력 형식은 `task update --body-file`의 입력 형식과 동일하므로 추가 변환 없이 그대로 되돌릴 수 있습니다.
- `task update`는 `--body-mime` 미지정 시 **기존 본문 형식(mimeType)을 자동 보존**합니다. 본문이 마크다운이 아닌 HTML 등으로 작성된 경우 `--body-only` 출력 시 경고가 표시되며, 이때는 `--body-mime`으로 원본 형식을 맞춰야 깨지지 않습니다.

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
