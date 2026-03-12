# Dooray CLI

Swift로 작성된 Dooray API CLI 도구.

## Dooray API 문서 참조

API 스펙이나 엔드포인트 세부사항을 확인해야 할 때, agent-browser로 공식 문서를 탐색한다.

### 메인 API 문서

```
https://helpdesk.dooray.com/share/pages/9wWo-xwiR66BO5LGshgVTg/2939987647631384419
```

이 페이지는 Dooray 서비스 API 전체 스펙을 담고 있으며, 좌측 사이드바로 섹션 간 이동이 가능하다.

### 관련 하위 문서

- 파일 업로드 API: `https://helpdesk.dooray.com/share/pages/9wWo-xwiR66BO5LGshgVTg/3817617091196252578`
- 인증 토큰 발급: `https://helpdesk.dooray.com/share/pages/9wWo-xwiR66BO5LGshgVTg/2896332917094559861`

### agent-browser 탐색 방법

페이지가 무거우므로 `networkidle` 대신 고정 대기를 사용한다.

```bash
# 1. 페이지 열기
agent-browser open "https://helpdesk.dooray.com/share/pages/9wWo-xwiR66BO5LGshgVTg/2939987647631384419"
agent-browser wait 5000

# 2. 사이드바 네비게이션 확인 (섹션 목록)
agent-browser snapshot -i

# 3. 특정 섹션 클릭 (예: Project > Posts)
agent-browser click @e40   # ref는 snapshot 결과 참조

# 4. 본문 텍스트 추출
agent-browser get text body

# 5. 페이지가 길면 스크롤 후 다시 추출
agent-browser scroll down 3000
agent-browser get text body
```

### API 문서 구조 (사이드바 섹션)

- **기본**: End Point, 인증, TLS 지원, 메시지, 요청 제한(Rate limiter)
- **Common**: Members, IncomingHooks
- **Project**: Category, Projects (Workflows, EmailAddress, Tags, Milestones, Hooks, Members, MemberGroups, Template), Posts (Logs), 업무 Hook 형태
- **Calendar**: Calendars, Events
- **Drive**: Drives, Files, SharedLinks
- **Wiki**: Pages (Comments, SharedLinks, Files), Attach Files
- **Messenger**: Channels (direct-send)
- **Reservation**: ResourcesCategory, Resources, Resource Reservations
- **Contact**: Contacts (search)

## 문서 최신화

기능을 추가하거나 변경할 때, 관련 문서들도 함께 최신화한다:

- `README.md`: 사용법 섹션에 새 명령어 반영
- `skills/dooray/SKILL.md`: 명령어 요약 섹션에 새 명령어 반영

### API Base URLs

- `https://api.dooray.com` (일반)
- `https://api.dooray.co.kr` (한국)
- `https://api.gov-dooray.com` (정부)
- `https://api.gov-dooray.co.kr` (정부/한국)
