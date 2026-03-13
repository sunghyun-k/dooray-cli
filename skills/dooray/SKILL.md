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
dooray-cli project members <프로젝트코드>
```

### 태스크
```bash
# 태스크 조회 (ID, 프로젝트코드/번호, URL 모두 지원)
dooray-cli task get <식별자>

# 태스크 목록
dooray-cli task list <프로젝트코드> [--workflow backlog,registered,working] [--order -postUpdatedAt] [--to-member-ids 멤버ID,...] [--created-by me|멤버ID,...] [--created-at from,to] [--page 0]

# 태스크 생성
dooray-cli task create <프로젝트코드> "제목" [--body "본문"] [--priority normal] [--due-date 2024-12-31] [--to 멤버ID]

# 태스크 수정
dooray-cli task update <식별자> [--subject "새제목"] [--body "새본문"] [--priority high]

# 워크플로우 변경
dooray-cli task set-workflow <식별자> <워크플로우ID>
```

### 댓글
```bash
# 댓글 목록
dooray-cli comment list <식별자> [--page 0]

# 댓글 작성
dooray-cli comment create <식별자> "댓글 내용"

# 댓글 수정
dooray-cli comment update <식별자> <댓글ID> "수정할 내용"
```

### 워크플로우/태그
```bash
# 워크플로우 목록 (상태 변경시 ID 확인용)
dooray-cli workflow list <프로젝트코드>

# 태그 목록
dooray-cli tag list <프로젝트코드> [--page 0]
```

### 첨부파일
```bash
# 첨부파일 목록
dooray-cli file list <식별자>

# 첨부파일 다운로드
dooray-cli file download <식별자> [--output 저장경로] [파일ID]
```

## 태스크 식별자 형식

세 가지 형식을 지원합니다:
1. **태스크 ID**: 19자리 숫자 (예: `1234567890123456789`)
2. **프로젝트코드/번호**: `프로젝트코드/123`
3. **두레이 URL**: `https://your-tenant.dooray.com/project/my-project/task/456` 또는 `https://your-tenant.dooray.com/task/{projectId}/{postId}`

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
