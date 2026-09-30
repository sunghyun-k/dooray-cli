---
name: dooray
description: Manage Dooray project tasks, comments, workflows, tags, and files
allowed-tools: Bash(dooray-cli:*)
---

# Dooray CLI Skill

두레이 프로젝트 관리 CLI 도구. 태스크, 댓글, 워크플로우, 태그 등을 조회하고 관리합니다.

## 사전 조건

- `DOORAY_API_TOKEN` 환경변수 설정 필요
- `dooray` CLI가 PATH에 있거나 빌드되어 있어야 함

## 명령어 요약

### 프로젝트
```bash
# 프로젝트 목록
dooray-cli project list [--state active|archived] [--mine] [--page 0]

# 프로젝트 멤버
dooray-cli project members <프로젝트코드>   # id,name,email,role

# 멤버 조회 (이름·이메일·userCode·멤버 ID) — id,name,email,mention. 동명이인은 모두 출력
dooray-cli member get <지정자>
```

### 태스크
```bash
# 태스크 조회 (ID, 프로젝트코드/번호, URL 모두 지원) — 하위 태스크 목록 포함
dooray-cli task get <식별자>   # 작성자·담당자·참조자는 '이름 (멤버ID) 멘션링크' 로 출력

# 본문(마크다운)만 출력 — 파일 저장 후 편집·재업데이트 라운드트립 용도
dooray-cli task get <식별자> --body-only > task.md

# API 응답(result)을 JSON 그대로 출력 — 스크립트에서 멤버 ID 등을 꺼내는 용도
dooray-cli task get <식별자> --json

# 태스크 목록
dooray-cli task list <프로젝트코드> [--workflow backlog,registered,working] [--order -postUpdatedAt] [--to-member-ids 멤버ID,...] [--created-by me|멤버ID,...] [--created-at today|thisweek|prev-Nd|next-Nd|ISO8601~ISO8601] [--page 0]

# 태스크 생성 (--parent 지정 시 하위 태스크로 생성, 태그 필수 프로젝트는 --tag 지정 필요)
dooray-cli task create <프로젝트코드> "제목" [--body "본문"] [--body-file 본문.md] [--priority normal] [--due-date 2024-12-31] [--to 이름|이메일|멤버ID] [--parent 상위태스크식별자] [--tag "Platform: iOS" --tag "업무: Document"]

# 태스크 수정 (--body-mime 미지정 시 기존 본문 형식 자동 보존, --tag 는 태그 목록을 교체)
dooray-cli task update <식별자> [--subject "새제목"] [--body "새본문"] [--body-file 본문.md] [--body-mime text/html] [--priority high] [--tag iOS,Document] [--to 담당자,...] [--cc 참조자,...]

# 기존 태스크를 하위 태스크로 연결 (같은 프로젝트 내에서만, 1단계 계층만 지원)
dooray-cli task set-parent <식별자> <상위태스크식별자>

# 워크플로우 변경
dooray-cli task set-workflow <식별자> <워크플로우ID>
```

### 댓글
```bash
# 댓글 목록
dooray-cli comment list <식별자> [--page 0]

# 댓글 작성 (텍스트 또는 마크다운 파일)
dooray-cli comment create <식별자> "댓글 내용"
dooray-cli comment create <식별자> --body-file 내용.md   # - 이면 표준 입력

# 댓글 수정
dooray-cli comment update <식별자> <댓글ID> "수정할 내용"   # 또는 --body-file 파일
```

### 워크플로우/태그
```bash
# 워크플로우 목록 (상태 변경시 ID 확인용)
dooray-cli workflow list <프로젝트코드>

# 태그 목록 (id,name,color,group,mandatory)
dooray-cli tag list <프로젝트코드> [--page 0]
```

### 첨부파일
```bash
# 첨부파일 목록
dooray-cli file list <식별자>

# 첨부파일 다운로드
dooray-cli file download <식별자> [--output 저장경로] [파일ID]

# 첨부파일 업로드 (--inline: 본문/댓글 인라인 이미지용, 첨부 목록에 표시 안 됨)
dooray-cli file upload <식별자> <파일경로> [파일경로...] [--inline]
```

### 태그

`--tag` 는 태그 이름 또는 ID를 받는다. 쉼표로 묶거나 여러 번 지정할 수 있고, 그룹 접두사를 뺀 짧은 이름(`iOS`)도 유일하면 인식한다. `task update --tag` 는 태그 목록을 교체한다.

태그 그룹이 필수인 프로젝트에서는 태그 없이 생성할 수 없다. 이 경우 CLI가 요청 전에 필수 그룹과 선택 가능한 태그를 알려 주므로, 그 목록에서 골라 `--tag` 로 지정한다. `tag list` 의 `mandatory` 컬럼으로도 확인할 수 있다.

### 멘션·담당자 지정

두레이 멘션은 `[@이름](dooray://{조직ID}/members/{멤버ID} "member")` 링크 형식이어야 한다(평문 `@이름` 은 멘션되지 않는다). 댓글에 넣으면 알림이 가고, 앞에 `->` 를 붙이면(`->[@이름](…)`) 담당자가 그 멤버로 바뀐다. 여러 명에게 `->` 를 붙이면 모두 담당자가 된다.

링크는 `task get`(작성자·담당자·참조자 줄)이나 `member get` 출력에서 그대로 가져다 쓴다.

```bash
dooray-cli task get my-project/123 | grep '^작성자'   # 작성자: 홍길동 (123…) [@홍길동](dooray://…)
dooray-cli comment create my-project/123 '->[@홍길동](dooray://…) 수정되었습니다. 확인 부탁드립니다.'
```

`task update --to/--cc`(및 `task create --to`)는 멤버를 이름·이메일·userCode·멤버 ID 로 받고, `author` 는 업무 등록자다. 지정한 쪽 목록을 교체하고 지정하지 않은 쪽은 기존 값(그룹 포함)을 유지하며, `""` 을 주면 비운다. 두레이 API 는 users 를 통째로 교체하므로 CLI 가 반대쪽을 채워 보낸다. 이름은 업무에 등장한 사람을 먼저 찾고 없으면 조직 전체에서 찾으며, 동명이인이면 후보를 보여 주고 멈춘다.

```bash
dooray-cli task update my-project/123 --to 홍길동,김철수
```

### `-` 로 시작하는 내용

`->@담당자 …` 처럼 `-` 로 시작하는 댓글·제목도 그대로 인자로 넘기면 된다. CLI 가 옵션이 아닌 토큰을 알아서 위치 인자로 처리한다(이전 버전은 `-h` 로 읽혀 도움말만 출력하고 종료 코드 0 으로 끝났다). `--body-file -` 로 표준 입력도 받는다.

### 인라인 이미지

본문/댓글 마크다운에서 `![이름](로컬경로)`로 로컬 이미지를 참조하면 자동으로 인라인 업로드되고 `/files/{fileId}`로 치환됩니다.

- 텍스트 입력(`--body`, 댓글 내용): 상대경로는 현재 디렉토리 기준
- `--body-file`: 상대경로는 마크다운 파일 위치 기준
- URL, 기존 `/files/` 참조, 존재하지 않는 경로는 그대로 유지
- 파일 업로드 API가 태스크 종속이라, `task create` 는 로컬 이미지가 있으면 본문을 비워 태스크를 먼저 만들고 업로드 후 본문을 채운다. 업로드 실패 시에도 깨진 로컬 경로가 본문에 남지 않는다

```bash
dooray-cli comment create my-project/123 "결과 스크린샷: ![결과](./screenshot.png)"
```

### 본문 라운드트립 (조회 → 편집 → 재업데이트)

```bash
dooray-cli task get my-project/123 --body-only > task.md   # 본문만 저장
# task.md 편집
dooray-cli task update my-project/123 --body-file task.md   # 다시 반영
```

- `--body-only` 출력은 `task update --body-file` 입력과 동일 형식이라 변환 없이 되돌릴 수 있음
- `task update`는 `--body-mime` 미지정 시 기존 본문 형식을 보존. 본문이 HTML 등 비마크다운이면 `--body-only` 출력 시 stderr 경고가 뜨며, 이땐 `--body-mime`으로 원본 형식을 맞춰야 함

## 태스크 식별자 형식

세 가지 형식을 지원합니다:
1. **태스크 ID**: 19자리 숫자 (예: `1234567890123456789`)
2. **프로젝트코드/번호**: `프로젝트코드/123`
3. **두레이 URL**: `https://your-tenant.dooray.com/project/my-project/task/456` 또는 `https://your-tenant.dooray.com/task/{projectId}/{postId}`

프로젝트코드/번호 형식과 코드가 들어간 URL(`/project/projects/{코드}/{번호}`)은 프로젝트 목록에서 코드를 찾아 ID 로 바꾼다. 두레이 API 에 코드로 프로젝트를 조회하는 기능이 없기 때문이다. 목록에는 공개 프로젝트와 내가 참여한 비공개 프로젝트만 나오므로, 참여하지 않은 비공개 프로젝트나 다른 사람의 개인 프로젝트(`@userCode`)는 업무를 볼 권한이 있어도 코드로 찾을 수 없다. 이때는 업무 ID 나 `https://{테넌트}.dooray.com/project/tasks/{업무ID}` URL 을 쓴다.

## 출력 형식

목록 조회 결과는 CSV 형식으로 출력됩니다. 태스크 상세 조회는 사람이 읽기 쉬운 형식으로 출력됩니다.

## 활용 예시

사용자가 "내 프로젝트의 진행중인 태스크 보여줘"라고 하면:
```bash
dooray-cli task list my-project --workflow working
```

사용자가 특정 태스크의 상태를 변경하고 싶다면:
1. 먼저 워크플로우 목록을 조회: `dooray-cli workflow list my-project`
2. 원하는 워크플로우 ID로 변경: `dooray-cli task set-workflow my-project/123 <워크플로우ID>`
